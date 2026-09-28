extends Node2D
## Draws the world: the board, everyone's land (as raised tiles), trails, squares and all the
## effects (flashes, rings, particles, floating text). Everything is vector drawing, so it's
## sharp at any screen resolution.

const CELL := 32.0
const BG := Color("#cfd6e4")
const EDGE := Color("#aab4c8")
const FLOOR := Color("#f5f7fc")
const CHECK := Color("#ebeff8")
const PILLAR := Color("#6b7690")
const PILLAR_DARK := Color("#4a5369")
const WATER := Color("#56b6e2")
const SHORE := Color("#3f8fb8")
const STORM := Color("#4b416e")
const PORTAL_COLORS := [Color("#ff8c42"), Color("#b06bff"), Color("#2ec4b6")]

var w
var font: Font
var tex_px := 64
var views := {} # player id -> PlayerView
var lines := {} # player id -> one [glow, rope, shine] set of Line2Ds per piece of trail
var danger := 0.0
var cull := true # skip drawing squares that are off screen (off in 2 Players, with two cameras)

var _floor: Node2D
var _water: Node2D
var _items: Node2D
var _land: Node2D # drawn by a shader from land_grid
var _pattern: Node2D # colourblind patterns over the land
var _fx: Node2D
var _hazards: Node2D # portals, belts' arrows, the storm's ring, traps
var _glows: Node2D # additive: halos under the squares
var _air: Node2D # additive: floating specks of light
var _trails: Node2D
var _actors: Node2D
var _top: Node2D
var _land_version := -1
var _map_version := -1
var _hazards_drawn := false
var _belt_marks := [] # [pos, dir]: where the arrows on the conveyor belts go
var _waves := PackedVector2Array() # spots on the sea where wave crests roll
var _icons := {}
var _coin: Texture2D
var _flashes := [] # {cells, life, max, origin}
var _fades := [] # {cells, color, life}
var _rings := [] # {pos, color, life, size}
var _outlines := [] # {lines, color, life}: the edge of freshly claimed land, glowing
var _motes := [] # {pos, vel, phase, size}: specks of light floating over the board (High and Ultra)
var _glow: Texture2D
var _tile: Texture2D
var _spark: Texture2D
var _add_mat: CanvasItemMaterial
var _checker: Texture2D
var _gfx_seen := -1
var _cam_view := Rect2() # the part of the world on screen, for skipping what's off it
## One texel per cell, for the land shader and the minimap
var land_grid := Shaders.Grid.new()
var trail_grid := Shaders.Grid.new()
var wall_grid := Shaders.Grid.new()
var pal_img := Image.create(16, 2, false, Image.FORMAT_RGBA8)
var pal_tex := ImageTexture.create_from_image(pal_img)


func setup(world, ui_font: Font, px: int) -> void:
	w = world
	font = ui_font
	tex_px = px
	_glow = Art.tex(Art.GLOW, 64)
	_tile = Art.tex(Art.TILE, 32)
	_spark = Art.tex(Art.SPARK, 64)
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_coin = Art.tex(Art.COIN, 96)
	for k in Art.ICONS:
		_icons[k] = Art.tex(Art.ICONS[k], 96)
	var ck := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	ck.fill(FLOOR)
	ck.fill_rect(Rect2i(0, 0, 32, 32), CHECK)
	ck.fill_rect(Rect2i(32, 32, 32, 32), CHECK)
	_checker = ImageTexture.create_from_image(ck)
	for n in ["_floor", "_water", "_land", "_pattern", "_fx", "_hazards", "_glows", "_trails", "_items", "_actors", "_top", "_air"]:
		var node := Node2D.new()
		node.name = n
		add_child(node)
		set(n, node)
	_floor.draw.connect(_draw_floor)
	_land.draw.connect(_draw_land)
	_land.material = Shaders.material(Shaders.LAND)
	_pattern.draw.connect(_draw_pattern)
	_floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED # the checker tiles
	_fx.draw.connect(_draw_fx)
	_water.draw.connect(_draw_water)
	_items.draw.connect(_draw_items)
	_hazards.draw.connect(_draw_hazards)
	w.teleported.connect(_on_teleported)
	w.blinked.connect(_on_blinked)
	w.storm_hit.connect(func(_r): _floor.queue_redraw())
	_glows.material = _add_mat
	_glows.draw.connect(_draw_glows)
	_air.material = _add_mat
	_air.draw.connect(_draw_air)
	_items.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_pattern.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED # colourblind patterns tile
	_pattern.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	w.captured.connect(_on_captured)
	w.picked.connect(_on_picked)
	w.painted.connect(_on_painted)
	w.coin_taken.connect(func(_p, at): burst(at, Color("#ffc93c"), 10, 180.0))
	w.knocked_out.connect(_on_knocked_out)
	w.spawned.connect(_on_spawned)


## Call after world.setup(): makes a view and trail ropes for every player
func rebuild() -> void:
	for c in _actors.get_children():
		c.queue_free()
	for c in _trails.get_children():
		c.queue_free()
	for c in _top.get_children():
		c.queue_free()
	views.clear()
	lines.clear()
	_flashes.clear()
	_fades.clear()
	_rings.clear()
	_outlines.clear()
	_land_version = -1
	_ensure_views()
	# You're drawn last, so you're always on top
	if w.me:
		_actors.move_child(views[w.me.id], -1)
	_floor.queue_redraw()


## A trail rope and a view for every player (the King's guards join mid-game)
func _ensure_views() -> void:
	for p in w.players:
		if p == null or views.has(p.id):
			continue
		lines[p.id] = [_make_ropes(p)]
		var v := preload("res://scripts/player_view.gd").new()
		v.setup(p, tex_px, font, w)
		_actors.add_child(v)
		views[p.id] = v
		if w.me and views.has(w.me.id):
			_actors.move_child(views[w.me.id], -1)


func _process(dt: float) -> void:
	if w == null or w.players.is_empty():
		return
	if views.size() < w.players.size() - 1:
		_ensure_views()
	if w.map_version != _map_version:
		_map_version = w.map_version
		_find_waves()
		wall_grid.set_bytes(w.N, w.wall)
		_floor.queue_redraw()
		_water.queue_redraw() # clears the waves when leaving Islands
	if w.land_version != _land_version or Gfx.level != _gfx_seen:
		_land_version = w.land_version
		_gfx_seen = Gfx.level
		_update_land()
	_cam_view = get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	# Low redraws the waves less often
	if w.map_id == "islands" and (Gfx.level > Gfx.LOW or Engine.get_process_frames() % 3 == 0):
		_water.queue_redraw()
	_items.queue_redraw()
	if not w.portals.is_empty() or w.storm_r > 0 or not w.traps.is_empty() or w.map_id == "conveyor":
		_hazards.queue_redraw()
	elif _hazards_drawn:
		_hazards.queue_redraw() # clear what's left from the last map
	_hazards_drawn = not w.portals.is_empty() or w.storm_r > 0 or not w.traps.is_empty() or w.map_id == "conveyor"
	_update_trails()
	# Effects fade out
	for f in _flashes:
		f.life -= dt
	_flashes = _flashes.filter(func(f): return f.life > 0)
	for f in _fades:
		f.life -= dt
	_fades = _fades.filter(func(f): return f.life > 0)
	for r in _rings:
		r.life -= dt
	_rings = _rings.filter(func(r): return r.life > 0)
	for o in _outlines:
		o.life -= dt
	_outlines = _outlines.filter(func(o): return o.life > 0)
	_fx.queue_redraw()
	_update_motes(dt)
	_glows.visible = Gfx.level >= Gfx.HIGH
	if _glows.visible:
		_glows.queue_redraw()
	# The leader wears a crown
	var leader: Player = null
	for p in w.players:
		if p and p.alive and (leader == null or w.counts[p.id] > w.counts[leader.id]):
			leader = p
	var seen := _cam_view.grow(CELL * 6)
	for id in views:
		var v = views[id]
		v.leader = leader != null and leader.id == id
		v.frozen = w.freezer != null and w.freezer.id != id
		v.on_screen = not cull or seen.has_point(v.p.pos * CELL)


## A trail is drawn as up to five ropes, more at higher graphics levels:
## a shadow on the ground (High), a soft glow (Medium), the rope itself, a shine along it
## (Medium) and a bright neon halo (Ultra)
const SHADOW := 0
const GLOW := 1
const ROPE := 2
const SHINE := 3
const NEON := 4
const ROPE_WIDTHS := [0.8, 1.35, 0.8, 0.2, 2.4]
const ROPE_MIN_LEVEL := [Gfx.HIGH, Gfx.MEDIUM, Gfx.LOW, Gfx.MEDIUM, Gfx.ULTRA]


func _make_ropes(p: Player) -> Array:
	var ropes := []
	for k in 5:
		var l := Line2D.new()
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		l.width = CELL * ROPE_WIDTHS[k] * p.size
		if k == SHADOW:
			l.position = Vector2(0, CELL * 0.28)
		if k == NEON:
			l.material = _add_mat
		_trails.add_child(l)
		ropes.append(l)
	return ropes


func _update_trails() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var smooth := Gfx.level > Gfx.LOW
	for p in w.players:
		if p == null:
			continue
		var sets: Array = lines[p.id]
		# The path in pieces: a portal jump starts a new piece
		var pieces := []
		if p.alive and not p.trail.is_empty() and not p.path.is_empty():
			var start := 0
			for b in p.path_breaks:
				if b > start and b <= p.path.size():
					pieces.append(p.path.slice(start, b))
					start = b
			var last: PackedVector2Array = p.path.slice(start)
			last.append(p.pos)
			pieces.append(last)
		while sets.size() < pieces.size():
			sets.append(_make_ropes(p))
		var col: Color = p.color
		if p == w.me and danger > 0:
			col = Color("#ff3c50").lerp(p.color, 0.35 - 0.35 * sin(t * 18.0))
		for si in sets.size():
			var ropes: Array = sets[si]
			if si >= pieces.size() or pieces[si].size() < 2:
				for l in ropes:
					l.visible = false
				continue
			var pts := PackedVector2Array()
			for q in pieces[si]:
				pts.append(q * CELL)
			for k in 5:
				var l: Line2D = ropes[k]
				l.visible = Gfx.level >= ROPE_MIN_LEVEL[k]
				if not l.visible:
					continue
				l.points = pts
				l.antialiased = smooth
				l.default_color = [Color(0.06, 0.08, 0.16, 0.16), Color(col, 0.2), Color(col, 0.65), Color(1, 1, 1, 0.35), Color(col, 0.22)][k]
				# Colourblind mode: the pattern runs along the middle of the rope
				if k == SHINE:
					var patterned: bool = Patterns.on
					if patterned and l.texture == null:
						l.texture = Patterns.tile(Patterns.index_of(p, w.COLORS))
						l.texture_mode = Line2D.LINE_TEXTURE_TILE
						l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
						l.width = CELL * 0.75 * p.size
					elif not patterned and l.texture:
						l.texture = null
						l.width = CELL * 0.2 * p.size
					if patterned:
						l.default_color = Color(0.06, 0.08, 0.16, 0.35)
				# The Rainbow trail from the shop: colours flowing along the rope
				if p.trail_fx == "rainbow" and (k == GLOW or k == ROPE) and not (p == w.me and danger > 0):
					if l.gradient == null:
						l.gradient = Gradient.new()
						l.gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
					var cols := PackedColorArray()
					for i in 6:
						cols.append(Color(Cosmetics.rainbow(-t, i / 5.0), [0.3, 0.85][k - GLOW]))
					l.gradient.colors = cols
				elif l.gradient:
					l.gradient = null


# ---------- Board and land ----------

func _draw_floor() -> void:
	var n: int = w.N
	var size := n * CELL
	var wall: PackedByteArray = w.wall
	var islands: bool = w.map_id == "islands"
	var storm: bool = w.map_id == "storm"
	var open_board: bool = w.map_id != "round" and not islands and not storm
	# Far background (the sea on Islands, dark clouds on Storm), then a soft shadow and a rim
	# under a square board
	# The far background is the screen's clear colour (no need to paint the whole screen)
	RenderingServer.set_default_clear_color(WATER if islands else STORM if storm else BG)
	if open_board:
		for k in range(4, 0, -1):
			var g := CELL * 0.4 * k
			_floor.draw_rect(Rect2(-6 - g, -6 + CELL * 0.5 + g * 0.6, size + 12 + g * 2, size + 12 + g), Color(0.08, 0.1, 0.18, 0.05))
		_floor.draw_rect(Rect2(-6, -6 + CELL * 0.45, size + 12, size + 12), EDGE)
	elif w.map_id == "round":
		_floor.draw_circle(Vector2(size / 2, size / 2 + CELL * 0.45), size / 2 - CELL * 0.6, EDGE, true, -1, true)
	# Open ground: a raised edge where it meets the sea or the outside, then the checker
	for y in n:
		for x in n:
			var i := y * n + x
			if wall[i] == 2 or (y + 1 < n and wall[i + n] != 2):
				continue
			_floor.draw_rect(Rect2(x * CELL, (y + 1) * CELL - 1, CELL, CELL * 0.4), SHORE if islands else EDGE)
	for y in n:
		var x := 0
		while x < n:
			if wall[y * n + x] == 2:
				x += 1
				continue
			var e := x
			while e + 1 < n and wall[y * n + e + 1] != 2:
				e += 1
			# Floor and checker in one: a tiled 2 x 2 cell texture, lined up across the board
			var r := Rect2(x * CELL, y * CELL, (e - x + 1) * CELL, CELL)
			_floor.draw_texture_rect_region(_checker, r, r)
			x = e + 1
	# Conveyor belts: dark strips with rails along their edges
	_belt_marks.clear()
	if w.map_id == "conveyor":
		for y in n:
			for x in n:
				var b: int = w.belt[y * n + x]
				if b == 0:
					continue
				_floor.draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), Color("#7d879c"))
				var dir: Vector2 = w.BELT_DIRS[b]
				var side := Vector2i(int(dir.orthogonal().x), int(dir.orthogonal().y))
				var a := Vector2i(x, y) + side
				var c := Vector2i(x, y) - side
				var inside_a: bool = a.x >= 0 and a.y >= 0 and a.x < n and a.y < n and w.belt[a.y * n + a.x] == b
				var inside_c: bool = c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and w.belt[c.y * n + c.x] == b
				if inside_a and inside_c and (x + y) % 2 == 0:
					_belt_marks.append([Vector2(x + 0.5, y + 0.5), dir])
				for e in [[inside_a, side], [inside_c, -side]]:
					if not e[0]:
						var off: Vector2 = Vector2(e[1]) * CELL * 0.42
						var mid := Vector2(x + 0.5, y + 0.5) * CELL + off
						var half := dir * CELL * 0.5
						_floor.draw_line(mid - half, mid + half, Color("#5b6378"), CELL * 0.16)
	# Saw tracks: rails the blades run along
	for s in w.saws:
		var corners: Array = s.corners
		for e in corners.size():
			var a: Vector2 = corners[e] * CELL
			var b: Vector2 = corners[(e + 1) % corners.size()] * CELL
			_floor.draw_line(a, b, Color("#c3cadb"), CELL * 0.7, true)
			_floor.draw_dashed_line(a, b, Color("#8d97ab"), CELL * 0.16, CELL * 0.5, true, true)
		for q in corners:
			_floor.draw_circle(q * CELL, CELL * 0.35, Color("#c3cadb"), true, -1, true)
	# Foam on the water side of every shore
	if islands:
		var f := CELL * 0.22
		var foam := Color(1, 1, 1, 0.6)
		for y in n:
			for x in n:
				var i := y * n + x
				if wall[i] != 2:
					continue
				var px := x * CELL
				var py := y * CELL
				if y > 0 and wall[i - n] != 2:
					_floor.draw_rect(Rect2(px, py + CELL * 0.4, CELL, f), foam)
				if y < n - 1 and wall[i + n] != 2:
					_floor.draw_rect(Rect2(px, py + CELL - f, CELL, f), foam)
				if x > 0 and wall[i - 1] != 2:
					_floor.draw_rect(Rect2(px, py, f, CELL), foam)
				if x < n - 1 and wall[i + 1] != 2:
					_floor.draw_rect(Rect2(px + CELL - f, py, f, CELL), foam)
	# Pillars and maze walls: raised blocks with a lit top edge
	for pass_i in 3:
		for y in n:
			var x := 0
			while x < n:
				if wall[y * n + x] != 1:
					x += 1
					continue
				var e := x
				while e + 1 < n and wall[y * n + e + 1] == 1:
					e += 1
				var r := Rect2(x * CELL, y * CELL, (e - x + 1) * CELL, CELL)
				if pass_i == 0:
					_floor.draw_rect(Rect2(r.position + Vector2(0, CELL * 0.35), r.size), PILLAR_DARK)
				elif pass_i == 1:
					_floor.draw_rect(r, PILLAR)
				elif y == 0 or wall[(y - 1) * n + x] != 1:
					_floor.draw_rect(Rect2(r.position, Vector2(r.size.x, CELL * 0.14)), Color(1, 1, 1, 0.22))
				x = e + 1


## Where wave crests roll on the Islands sea
func _find_waves() -> void:
	_waves.clear()
	if w.map_id != "islands":
		return
	var n: int = w.N
	for y in range(0, n, 3):
		for x in n:
			if (x + y * 2) % 5 == 0 and x + 1 < n and w.wall[y * n + x] == 2 and w.wall[y * n + x + 1] == 2:
				_waves.append(Vector2(x, y))


func _draw_water() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var crest := Color(1, 1, 1, 0.42)
	for q in _waves:
		var o := Vector2(q.x * CELL + sin(t * 1.2 + q.y * 0.7 + q.x * 0.3) * CELL * 0.6, q.y * CELL + sin(t * 2.0 + q.x) * CELL * 0.15)
		_water.draw_polyline(PackedVector2Array([o, o + Vector2(CELL * 0.35, -CELL * 0.22), o + Vector2(CELL * 0.8, -CELL * 0.28), o + Vector2(CELL * 1.2, 0)]), crest, CELL * 0.12, true)


## Power-ups bob and sparkle; coins spin and blink before they vanish
func _draw_items() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pu in w.powerups:
		var c: Color = w.POWERUPS[pu.kind].color
		var at: Vector2 = pu.pos * CELL + Vector2(0, sin(t * 4.0 + pu.pos.x) * CELL * 0.15)
		var r := CELL * 0.85 * minf(1.0, pu.age * 4.0)
		_items.draw_circle(at, r * (1.5 + 0.15 * sin(t * 6.0)), Color(c, 0.25), true, -1, true)
		_items.draw_circle(at, r, Color.WHITE, true, -1, true)
		_items.draw_arc(at, r, 0, TAU, 40, c, r * 0.18, true)
		_items.draw_texture_rect(_icons[pu.kind], Rect2(at - Vector2(r, r) * 0.68, Vector2(r, r) * 1.36), false)
		for k in (3 if Gfx.level > Gfx.LOW else 0):
			var a := t * 2.5 + k * TAU / 3
			var sp := at + Vector2.from_angle(a) * r * 1.45
			_items.draw_texture_rect(_spark, Rect2(sp - Vector2(r, r) * 0.2, Vector2(r, r) * 0.4), false, Color(1, 1, 1, 0.9))
	# Saw blades, spinning as they run round their tracks
	for sw in w.saws:
		var at: Vector2 = sw.pos * CELL
		var r := CELL * 1.35
		var teeth := PackedVector2Array()
		for k in 24:
			var a: float = sw.spin + k * TAU / 24.0
			teeth.append(at + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.78))
		_items.draw_circle(at + Vector2(0, CELL * 0.25), r, Color(0.06, 0.08, 0.16, 0.18), true, -1, true)
		_items.draw_colored_polygon(teeth, Color("#aeb8cc"))
		_items.draw_circle(at, r * 0.7, Color("#dfe5f0"), true, -1, true)
		for k in 3:
			var a: float = sw.spin * 1.0 + k * TAU / 3.0
			_items.draw_line(at + Vector2.from_angle(a) * r * 0.2, at + Vector2.from_angle(a) * r * 0.62, Color("#9aa4b8"), CELL * 0.12, true)
		_items.draw_circle(at, r * 0.2, Color("#ff5d73"), true, -1, true)
	for co in w.coins:
		if co.life < 3 and int(co.life * 8) % 2:
			continue
		var at: Vector2 = co.pos * CELL + Vector2(0, sin(t * 3.0 + co.pos.x) * CELL * 0.1)
		var r := CELL * 0.5 * minf(1.0, co.age * 4.0)
		var spin := maxf(0.15, absf(cos(t * 4.0 + co.pos.x)))
		_items.draw_set_transform(at, 0, Vector2(spin, 1))
		_items.draw_texture_rect(_coin, Rect2(-r, -r, r * 2, r * 2), false)
		_items.draw_set_transform(Vector2.ZERO)


## New land (or new graphics settings): refresh the land texture, the palette and the shader
func _update_land() -> void:
	land_grid.set_bytes(w.N, w.land)
	for p in w.players:
		if p and p.id < 16:
			pal_img.set_pixel(p.id, 0, p.color)
			pal_img.set_pixel(p.id, 1, p.dark)
	pal_tex.update(pal_img)
	var m: ShaderMaterial = _land.material
	m.set_shader_parameter("ids", land_grid.tex)
	m.set_shader_parameter("pal", pal_tex)
	m.set_shader_parameter("n", float(w.N))
	m.set_shader_parameter("rims", 1.0 if Gfx.level >= Gfx.MEDIUM else 0.0)
	m.set_shader_parameter("shade", 1.0 if Gfx.level >= Gfx.HIGH else 0.0)
	m.set_shader_parameter("shine", 1.0 if Gfx.level >= Gfx.ULTRA else 0.0)
	_land.queue_redraw()
	if Patterns.on or _pattern_drawn:
		_pattern.queue_redraw()


## All the land in one rectangle; the shader paints each cell (see Shaders.LAND)
func _draw_land() -> void:
	if land_grid.tex == null:
		return
	var n: int = w.N
	_land.draw_texture_rect(land_grid.tex, Rect2(0, 0, n * CELL, (n + LAND_DEPTH) * CELL), false)


const LAND_DEPTH := 0.3 # the raised edge under the land, in cells (the shader's `depth`)
var _pattern_drawn := false


## Colourblind mode: each player's pattern over their land, lined up across the board
func _draw_pattern() -> void:
	_pattern_drawn = Patterns.on
	if not Patterns.on:
		return
	var n: int = w.N
	var land: PackedByteArray = w.land
	var tex := {}
	for p in w.players:
		if p:
			tex[p.id] = Patterns.tile(Patterns.index_of(p, w.COLORS))
	for y in n:
		var x := 0
		while x < n:
			var id := land[y * n + x]
			if id == 0:
				x += 1
				continue
			var e := x
			while e + 1 < n and land[y * n + e + 1] == id:
				e += 1
			var r := Rect2(x * CELL, y * CELL, (e - x + 1) * CELL, CELL)
			_pattern.draw_texture_rect_region(tex[id], r, r, Color(0.06, 0.08, 0.16, 0.3))
			x = e + 1


func _draw_fx() -> void:
	var n: int = w.N
	# Land of knocked-out players shrinks away
	for f in _fades:
		var k: float = f.life / 0.7
		var s := CELL * k
		var c: Color = f.color
		c.a = k
		for i in f.cells:
			_fx.draw_rect(Rect2((i % n) * CELL + (CELL - s) / 2, (i / n) * CELL + (CELL - s) / 2, s, s), c)
	# Freshly claimed land: a bright wave rolls out from where the loop closed
	var cell := Vector2(CELL, CELL)
	for f in _flashes:
		var age: float = f.max - f.life
		var front := age * 55.0
		var fade: float = f.life / f.max
		var at: PackedVector2Array = f.at
		var dist: PackedFloat32Array = f.dist
		for k in at.size():
			var d := dist[k]
			var a := (maxf(0.0, 1.0 - absf(d - front) / 3.0) * 0.7 + (0.1 if d < front else 0.3)) * fade
			if a > 0.03:
				_fx.draw_rect(Rect2(at[k], cell), Color(1, 1, 1, a))
	# The edge of freshly claimed land glows, then fades
	for o in _outlines:
		var k: float = o.life / 0.9
		var c: Color = o.color
		c.a = k
		_fx.draw_multiline(o.lines, Color(c.lightened(0.5), k * 0.5), CELL * (0.5 + (1.0 - k) * 0.4))
		_fx.draw_multiline(o.lines, Color(1, 1, 1, k), CELL * 0.14)
	for r in _rings:
		var t: float = 1.0 - r.life / 0.6
		var c: Color = r.color
		c.a = r.life / 0.6
		_fx.draw_arc(r.pos * CELL, CELL * r.size * (0.3 + t), 0, TAU, 64, c, maxf(2.0, CELL * 0.45 * (1 - t)), true)


# ---------- Effects ----------

## A flash over claimed cells, with each cell's corner and distance from `origin` worked out
## once (Medium and up)
func _add_flash(cells: PackedInt32Array, origin: Vector2, life: float) -> void:
	if Gfx.level == Gfx.LOW:
		return
	var n: int = w.N
	var at := PackedVector2Array()
	var dist := PackedFloat32Array()
	at.resize(cells.size())
	dist.resize(cells.size())
	for k in cells.size():
		var i := cells[k]
		var c := Vector2(i % n, i / n)
		at[k] = c * CELL
		dist[k] = (c + Vector2(0.5, 0.5)).distance_to(origin)
	_flashes.append({"at": at, "dist": dist, "life": life, "max": life})


func _on_captured(p: Player, cells: PackedInt32Array, gain: float) -> void:
	if cells.is_empty():
		return
	_add_flash(cells, p.pos, 0.8)
	if Gfx.level > Gfx.LOW:
		_outlines.append({"lines": _edges(cells), "color": p.color, "life": 0.9})
	if cells.size() > 15:
		_rings.append({"pos": p.pos, "color": p.color, "life": 0.6, "size": minf(14.0, 4.0 + sqrt(cells.size()) * 0.5)})
	burst(p.pos, p.color, mini(40, 8 + cells.size() / 10), 260.0)
	if p == w.me and gain >= 0.1:
		float_text(p.pos + Vector2(0, -2.5), "+%.1f%%" % gain, Color.WHITE, p.dark, 1.5 if gain > 3 else 1.0)


func _on_knocked_out(v: Player, _killer: Player, _how: String, lost: PackedInt32Array) -> void:
	_fades.append({"cells": lost, "color": v.color, "life": 0.7})
	burst(v.pos, v.color, 40, 420.0)
	# Their land shatters into tiles that jump and fall
	var tiles := CPUParticles2D.new()
	tiles.texture = _tile
	tiles.one_shot = true
	tiles.explosiveness = 0.9
	tiles.amount = Gfx.particles(36)
	tiles.lifetime = 1.1
	tiles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	tiles.emission_sphere_radius = CELL * 2
	tiles.direction = Vector2.UP
	tiles.spread = 70
	tiles.gravity = Vector2(0, 1400)
	tiles.initial_velocity_min = 250
	tiles.initial_velocity_max = 650
	tiles.angular_velocity_min = -500
	tiles.angular_velocity_max = 500
	tiles.scale_amount_min = 0.35
	tiles.scale_amount_max = 0.7
	tiles.color = v.color
	var ramp := Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	tiles.color_ramp = ramp
	tiles.position = v.pos * CELL
	_top.add_child(tiles)
	tiles.emitting = true
	tiles.finished.connect(tiles.queue_free)


func _on_picked(p: Player, kind: String, at: Vector2) -> void:
	burst(at, w.POWERUPS[kind].color, 20, 300.0)
	if kind == "shield" or kind == "speed":
		_rings.append({"pos": p.pos, "color": w.POWERUPS[kind].color, "life": 0.6, "size": 5.0})


func _on_painted(p: Player, cells: PackedInt32Array) -> void:
	_add_flash(cells, p.pos, 0.6)
	_rings.append({"pos": p.pos, "color": w.POWERUPS.paint.color, "life": 0.6, "size": 9.0})
	burst(p.pos, w.POWERUPS.paint.color, 36, 480.0)


func _on_spawned(p: Player) -> void:
	if views.has(p.id):
		burst(p.pos, p.color, 16, 200.0)


## A puff of glowing sparks
func burst(at: Vector2, color: Color, amount: int, speed: float) -> void:
	var ps := CPUParticles2D.new()
	ps.texture = _glow
	ps.material = _add_mat
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.amount = Gfx.particles(maxi(4, amount))
	ps.lifetime = 0.7
	ps.spread = 180
	ps.gravity = Vector2(0, 300)
	ps.initial_velocity_min = speed * 0.3
	ps.initial_velocity_max = speed
	ps.damping_min = 200
	ps.damping_max = 400
	ps.scale_amount_min = 0.25
	ps.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.35))
	ramp.set_color(1, Color(color, 0))
	ps.color_ramp = ramp
	ps.position = at * CELL
	_top.add_child(ps)
	ps.emitting = true
	ps.finished.connect(ps.queue_free)


## "+2.5%" floating up from the board
func float_text(at: Vector2, text: String, color: Color, outline: Color, big := 1.0) -> void:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = int(40 * big)
	ls.font_color = color
	ls.outline_size = 10
	ls.outline_color = outline
	l.label_settings = ls
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(300, 60)
	l.position = at * CELL - Vector2(150, 30)
	l.pivot_offset = Vector2(150, 30)
	l.scale = Vector2(0.4, 0.4)
	_top.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - CELL * 1.8, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.tween_callback(l.queue_free)


## The outline of a patch of cells, as pairs of points for draw_multiline
func _edges(cells: PackedInt32Array) -> PackedVector2Array:
	var n: int = w.N
	var inside := {}
	for i in cells:
		inside[i] = true
	var out := PackedVector2Array()
	for i in cells:
		var x := i % n
		var y := i / n
		var a := Vector2(x, y) * CELL
		if y == 0 or not inside.has(i - n):
			out.append_array([a, a + Vector2(CELL, 0)])
		if y == n - 1 or not inside.has(i + n):
			out.append_array([a + Vector2(0, CELL), a + Vector2(CELL, CELL)])
		if x == 0 or not inside.has(i - 1):
			out.append_array([a, a + Vector2(0, CELL)])
		if x == n - 1 or not inside.has(i + 1):
			out.append_array([a + Vector2(CELL, 0), a + Vector2(CELL, CELL)])
	return out


## A soft coloured glow under every square (High and Ultra; stronger on Ultra)
func _draw_glows() -> void:
	var strength := 0.35 if Gfx.level == Gfx.ULTRA else 0.22
	for p in w.players:
		if p and p.alive:
			var s: float = CELL * 3.6 * p.size
			_glows.draw_texture_rect(_glow, Rect2(p.pos * CELL - Vector2(s, s) / 2, Vector2(s, s)), false, Color(p.color, strength))


## Specks of light drifting over the part of the board on screen
func _update_motes(dt: float) -> void:
	var want: int = [0, 0, 12, 34][Gfx.level]
	_air.visible = want > 0
	if want == 0:
		_motes.clear()
		return
	var view := _cam_view
	while _motes.size() < want:
		_motes.append(_new_mote(view))
	if _motes.size() > want:
		_motes.resize(want)
	for m in _motes:
		m.pos += m.vel * dt
		m.phase += dt
		if not view.grow(CELL * 2).has_point(m.pos):
			var fresh := _new_mote(view)
			m.pos = fresh.pos
			m.vel = fresh.vel
	_air.queue_redraw()


func _new_mote(view: Rect2) -> Dictionary:
	return {
		"pos": view.position + Vector2(randf() * view.size.x, randf() * view.size.y),
		"vel": Vector2(randf_range(-12, 12), randf_range(-28, -8)),
		"phase": randf() * TAU,
		"size": randf_range(0.25, 0.6) * CELL,
	}


func _draw_air() -> void:
	for m in _motes:
		var a := 0.22 + 0.18 * sin(m.phase * 1.7)
		var s: float = m.size * (1.0 + 0.2 * sin(m.phase * 2.3))
		_air.draw_texture_rect(_glow, Rect2(m.pos - Vector2(s, s) / 2, Vector2(s, s)), false, Color(1, 0.96, 0.8, a))


# ---------- Hazards ----------

func _draw_hazards() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Conveyor: arrows sliding along the belts
	var shift := fmod(t * w.BELT_SPEED, 2.0)
	for m in _belt_marks:
		var dir: Vector2 = m[1]
		var at: Vector2 = (m[0] + dir * (shift - 1.0)) * CELL
		var side := dir.orthogonal() * CELL * 0.45
		_hazards.draw_polyline(PackedVector2Array([at - dir * CELL * 0.3 + side, at + dir * CELL * 0.2, at - dir * CELL * 0.3 - side]), Color(1, 1, 1, 0.55), CELL * 0.16, true)
	# Portals: swirling rings, a colour for each pair
	for k in w.portals.size():
		var col: Color = PORTAL_COLORS[k % PORTAL_COLORS.size()]
		for end in w.portals[k]:
			var at: Vector2 = end * CELL
			var pulse := 1.0 + 0.08 * sin(t * 5.0)
			_hazards.draw_circle(at, CELL * 2.3 * pulse, Color(col, 0.16), true, -1, true)
			_hazards.draw_circle(at, CELL * 1.6, col, true, -1, true)
			_hazards.draw_circle(at, CELL * 1.3, col.darkened(0.5), true, -1, true)
			_hazards.draw_circle(at, CELL * 0.7, col.darkened(0.78), true, -1, true)
			for a in 4:
				var start := t * 3.5 + a * TAU / 4.0
				_hazards.draw_arc(at, CELL * (0.45 + 0.22 * a), start, start + 2.2, 20, col.lightened(0.15 + 0.15 * a), CELL * 0.18, true)
	# Storm: the next ring pulses red, with the doomed band shaded
	if w.storm_r > 0 and w.storm_next > 0:
		var c: Vector2 = w.center() * CELL
		var pulse := 0.5 + 0.5 * sin(t * 8.0)
		var band: float = (w.storm_r - w.storm_next) * CELL
		_hazards.draw_arc(c, w.storm_next * CELL + band / 2, 0, TAU, 128, Color(1, 0.25, 0.35, 0.12 + 0.1 * pulse), band, true)
		_hazards.draw_arc(c, w.storm_next * CELL, 0, TAU, 128, Color(1, 0.3, 0.4, 0.6 + 0.4 * pulse), CELL * 0.3, true)
	# The Queen's traps: spiky, and blinking before they vanish
	for trap in w.traps:
		if trap.life < 2.0 and int(trap.life * 8) % 2:
			continue
		var at: Vector2 = trap.pos * CELL
		var spikes := PackedVector2Array()
		for k in 16:
			var a: float = k * TAU / 16.0 + t
			spikes.append(at + Vector2.from_angle(a) * CELL * (0.75 if k % 2 == 0 else 0.4))
		_hazards.draw_colored_polygon(spikes, Color("#8e2f6b"))
		_hazards.draw_circle(at, CELL * 0.28, Color("#ff5d9e"), true, -1, true)


func _on_teleported(p: Player, from: Vector2, to: Vector2) -> void:
	var col: Color = PORTAL_COLORS[0]
	for k in w.portals.size():
		for end in w.portals[k]:
			if end.distance_to(from) < 1.5:
				col = PORTAL_COLORS[k % PORTAL_COLORS.size()]
	burst(from, col, 18, 260.0)
	burst(to, col, 24, 320.0)
	_rings.append({"pos": to, "color": col, "life": 0.6, "size": 4.0})
	if views.has(p.id):
		p.squash = 1.0


func _on_blinked(_k: Player, from: Vector2, to: Vector2) -> void:
	burst(from, Color("#b06bff"), 30, 380.0)
	burst(to, Color("#b06bff"), 30, 380.0)
	_rings.append({"pos": to, "color": Color("#b06bff"), "life": 0.6, "size": 7.0})
