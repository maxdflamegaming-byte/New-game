extends Node2D
## Draws the world: the board, everyone's land (as raised tiles), trails, squares and all the
## effects (flashes, rings, particles, floating text). Everything is vector drawing, so it's
## sharp at any screen resolution.

const CELL := 32.0
const BG := Color("#cfd6e4")
const EDGE := Color("#aab4c8")
const FLOOR := Color("#f5f7fc")
const CHECK := Color("#ebeff8")

var w
var font: Font
var tex_px := 64
var views := {} # player id -> PlayerView
var lines := {} # player id -> [glow, rope, shine] Line2Ds
var danger := 0.0

var _floor: Node2D
var _land: Node2D
var _fx: Node2D
var _trails: Node2D
var _actors: Node2D
var _top: Node2D
var _land_version := -1
var _flashes := [] # {cells, life, max, origin}
var _fades := [] # {cells, color, life}
var _rings := [] # {pos, color, life, size}
var _glow: Texture2D
var _tile: Texture2D
var _spark: Texture2D
var _add_mat: CanvasItemMaterial


func setup(world, ui_font: Font, px: int) -> void:
	w = world
	font = ui_font
	tex_px = px
	_glow = Art.tex(Art.GLOW, 64)
	_tile = Art.tex(Art.TILE, 32)
	_spark = Art.tex(Art.SPARK, 64)
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for n in ["_floor", "_land", "_fx", "_trails", "_actors", "_top"]:
		var node := Node2D.new()
		node.name = n
		add_child(node)
		set(n, node)
	_floor.draw.connect(_draw_floor)
	_land.draw.connect(_draw_land)
	_fx.draw.connect(_draw_fx)
	w.captured.connect(_on_captured)
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
	_land_version = -1
	for p in w.players:
		if p == null:
			continue
		var ropes := []
		for k in 3:
			var l := Line2D.new()
			l.joint_mode = Line2D.LINE_JOINT_ROUND
			l.begin_cap_mode = Line2D.LINE_CAP_ROUND
			l.end_cap_mode = Line2D.LINE_CAP_ROUND
			l.antialiased = true
			l.width = CELL * [1.35, 0.8, 0.2][k]
			_trails.add_child(l)
			ropes.append(l)
		lines[p.id] = ropes
		var v := preload("res://scripts/player_view.gd").new()
		v.setup(p, tex_px, font)
		_actors.add_child(v)
		views[p.id] = v
	# You're drawn last, so you're always on top
	if w.me:
		_actors.move_child(views[w.me.id], -1)
	_floor.queue_redraw()


func _process(dt: float) -> void:
	if w == null or w.players.is_empty():
		return
	if w.land_version != _land_version:
		_land_version = w.land_version
		_land.queue_redraw()
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
	_fx.queue_redraw()
	# The leader wears a crown
	var leader: Player = null
	for p in w.players:
		if p and p.alive and (leader == null or w.counts[p.id] > w.counts[leader.id]):
			leader = p
	for id in views:
		views[id].leader = leader != null and leader.id == id


func _update_trails() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for p in w.players:
		if p == null:
			continue
		var ropes: Array = lines[p.id]
		if not p.alive or p.trail.is_empty():
			for l in ropes:
				l.visible = false
			continue
		var pts := PackedVector2Array()
		for q in p.path:
			pts.append(q * CELL)
		if pts.is_empty():
			for l in ropes:
				l.visible = false
			continue
		pts.append(p.pos * CELL)
		var col: Color = p.color
		if p == w.me and danger > 0:
			col = Color("#ff3c50").lerp(p.color, 0.35 - 0.35 * sin(t * 18.0))
		for k in 3:
			var l: Line2D = ropes[k]
			l.visible = true
			l.points = pts
			l.default_color = [Color(col, 0.2), Color(col, 0.65), Color(1, 1, 1, 0.35)][k]


# ---------- Board and land ----------

func _draw_floor() -> void:
	var n: int = w.N
	var size := n * CELL
	# Far background, then a soft shadow and a rim under the board
	_floor.draw_rect(Rect2(-size, -size, size * 3, size * 3), BG)
	for k in range(4, 0, -1):
		var g := CELL * 0.4 * k
		_floor.draw_rect(Rect2(-6 - g, -6 + CELL * 0.5 + g * 0.6, size + 12 + g * 2, size + 12 + g), Color(0.08, 0.1, 0.18, 0.05))
	_floor.draw_rect(Rect2(-6, -6 + CELL * 0.45, size + 12, size + 12), EDGE)
	_floor.draw_rect(Rect2(0, 0, size, size), FLOOR)
	for y in n:
		for x in range(y % 2, n, 2):
			_floor.draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), CHECK)


func _draw_land() -> void:
	var n: int = w.N
	var land: PackedByteArray = w.land
	var colors := {}
	var darks := {}
	for p in w.players:
		if p:
			colors[p.id] = p.color
			darks[p.id] = p.dark
	# A darker copy nudged down gives each patch a chunky raised edge...
	_runs(land, darks, CELL * 0.3)
	# ...then the top colour
	_runs(land, colors, 0.0)
	# A light rim along top and left edges
	var rim := Color(1, 1, 1, 0.32)
	for y in n:
		var x := 0
		while x < n:
			var id := land[y * n + x]
			if id == 0 or (y > 0 and land[(y - 1) * n + x] == id):
				x += 1
				continue
			var e := x
			while e + 1 < n and land[y * n + e + 1] == id and not (y > 0 and land[(y - 1) * n + e + 1] == id):
				e += 1
			_land.draw_rect(Rect2(x * CELL, y * CELL, (e - x + 1) * CELL, CELL * 0.14), rim)
			x = e + 1
	var rim2 := Color(1, 1, 1, 0.16)
	for y in n:
		for x in n:
			var id := land[y * n + x]
			if id and (x == 0 or land[y * n + x - 1] != id):
				_land.draw_rect(Rect2(x * CELL, y * CELL, CELL * 0.1, CELL), rim2)


## Horizontal runs of cells with the same owner, as one rectangle each
func _runs(grid: PackedByteArray, palette: Dictionary, y_off: float) -> void:
	var n: int = w.N
	for y in n:
		var x := 0
		while x < n:
			var id := grid[y * n + x]
			if id == 0:
				x += 1
				continue
			var e := x
			while e + 1 < n and grid[y * n + e + 1] == id:
				e += 1
			_land.draw_rect(Rect2(x * CELL, y * CELL + y_off, (e - x + 1) * CELL, CELL), palette[id])
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
	for f in _flashes:
		var age: float = f.max - f.life
		var front := age * 55.0
		var fade: float = f.life / f.max
		for i in f.cells:
			var d := Vector2(i % n + 0.5, i / n + 0.5).distance_to(f.origin)
			var a := (maxf(0.0, 1.0 - absf(d - front) / 3.0) * 0.7 + (0.1 if d < front else 0.3)) * fade
			if a > 0.03:
				_fx.draw_rect(Rect2((i % n) * CELL, (i / n) * CELL, CELL, CELL), Color(1, 1, 1, a))
	for r in _rings:
		var t: float = 1.0 - r.life / 0.6
		var c: Color = r.color
		c.a = r.life / 0.6
		_fx.draw_arc(r.pos * CELL, CELL * r.size * (0.3 + t), 0, TAU, 64, c, maxf(2.0, CELL * 0.45 * (1 - t)), true)


# ---------- Effects ----------

func _on_captured(p: Player, cells: PackedInt32Array, gain: float) -> void:
	if cells.is_empty():
		return
	_flashes.append({"cells": cells, "life": 0.8, "max": 0.8, "origin": p.pos})
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
	tiles.amount = 36
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
	ps.amount = maxi(4, amount)
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
