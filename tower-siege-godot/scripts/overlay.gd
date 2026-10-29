class_name Overlay
extends Control
## Drawn on top of the 3D field: the number on each building's roof and dots for its roads,
## the road you're dragging, the swipe trail, the tutorial hand, the airstrike crosshair and
## floating words like "Captured!". main.gd fills in what to draw each frame.

var main # main.gd
var font: Font
var show_labels := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport().get_visible_rect().size)


func _process(_dt: float) -> void:
	queue_redraw()


func outlined(text: String, pos: Vector2, size: int, fill: Color, stroke: Color) -> void:
	text = tr(text)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos + Vector2(-w / 2, size * 0.35)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, int(size * 0.24)), stroke)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)


func _draw() -> void:
	if main == null or main.battle == null or main.world == null:
		return
	var b: Battle = main.battle
	var w: World = main.world
	if show_labels and main.state != "menu" and main.state != "cutscene" and main.screen_open == "" and not main.cutscene.playing():
		_marks(w)
		_labels(b.towers, w)
		_road_counts(w, b)
	# Swipe trail
	for c in main.cut_marks:
		var k: float = c.life / 0.35
		draw_line(w.project(c.x1, c.y1, 2), w.project(c.x2, c.y2, 2), Color(1, 1, 1, k * 0.9), 7 * k + 1, true)
	# Airstrike crosshair
	for st in b.strikes:
		var c := w.project(st.t.x, st.t.y)
		var r: float = 30 + (st.time / st.dur) * 30
		var red := Color("#ff3b30")
		draw_arc(c, r, 0, TAU, 48, red, 4, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * (r - 12), c + d * (r + 12), red, 4)
	if main.state != "menu" and main.screen_open == "" and not main.cutscene.playing():
		for f in main.floats:
			var p := w.project(f.t.x, f.t.y, w.tower_top(f.t) + 30 + (1.3 - f.life) * 40)
			var col: Color = f.color
			col.a = minf(1, f.life * 1.5)
			# Pops in big, then settles
			var age: float = 1.3 - f.life
			outlined(f.text, p, int(26 * (1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.18))), col, Color(0.08, 0.1, 0.2, col.a))
	_drags(w, b)
	_hand(w, b)
	if main.state == "play" and main.screen_open == "":
		_upgrade_offer()


## Where the ⬆ button over a building goes: {c: center, r: radius}
func upgrade_button(t) -> Dictionary:
	var w: World = main.world
	var s := w.tower_screen(t)
	var size := clampf(w.px_per_unit(t.x, t.y) * 46, 16, 40)
	return {"c": Vector2(s.top_x + size * 1.6 + 26, s.top_y - size * 0.6), "r": 32.0}


func _upgrade_offer() -> void:
	var o: Dictionary = main.upgrade_offer
	if o.is_empty():
		return
	var t = o.t
	var btn := upgrade_button(t)
	var maxed: bool = t.stars >= Battle.UPGRADE_COST.size()
	var can: bool = main.battle.can_upgrade(t, Battle.PLAYER) is bool
	var pop := minf(1.0, (3.0 - o.life) * 6)
	var r: float = btn.r * (0.6 + 0.4 * pop)
	var ink := Color("#b06a00") if can else Color("#66728a")
	draw_circle(btn.c + Vector2(0, 4), r, ink)
	draw_circle(btn.c, r, Color("#ffc928") if can else Color("#c9d3e2"))
	draw_arc(btn.c, r, 0, TAU, 32, Color("#2160b8"), 3, true)
	if maxed:
		outlined("MAX", btn.c, int(r * 0.6), Color.WHITE, ink)
	else:
		# An up arrow, and the soldiers it costs under it
		var a: Vector2 = btn.c + Vector2(0, -r * 0.2)
		var s := r * 0.42
		var arrow := PackedVector2Array([a + Vector2(0, -s), a + Vector2(s, 0), a + Vector2(s * 0.4, 0), a + Vector2(s * 0.4, s * 0.7), a + Vector2(-s * 0.4, s * 0.7), a + Vector2(-s * 0.4, 0), a + Vector2(-s, 0)])
		draw_colored_polygon(arrow, Color.WHITE)
		draw_polyline(arrow + PackedVector2Array([arrow[0]]), ink, 2.5, true)
		outlined(str(Battle.UPGRADE_COST[t.stars]), btn.c + Vector2(0, r * 0.5), int(r * 0.5), Color.WHITE, ink)


# Each building's badge: a rounded pill in its army's colour with the number of soldiers, gold
# stars for its upgrades, and dots for its roads (white = free, faded = in use). They're drawn
# in layers (every badge, then every dot, then all the text) rather than building by
# building, so the phone can draw each layer in one go.
func _labels(towers: Array, w: World) -> void:
	var list := []
	for t in towers:
		var s := w.tower_screen(t)
		# The number swells when soldiers arrive or the building changes hands
		var size := int(clampf(w.px_per_unit(t.x, t.y) * 50, 18, 42) * (1.0 + t.pop * 0.14))
		var n := floori(maxf(0, t.units))
		var text := "Max" if n >= Battle.CAP else str(n)
		if t.type == "factory":
			text = "⇡" + text
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var bh := size * 1.18
		var bw := maxf(tw + size * 0.75, bh * 1.25)
		var cy: float = s.top_y - bh * 0.5
		list.append({"t": t, "s": s, "size": size, "text": text, "tw": tw, "cy": cy,
			"r": Rect2(s.top_x - bw / 2, cy - bh / 2, bw, bh), "side": main.SIDES[t.owner]})
	# Badges and dots are textured rectangles, which the phone draws together in one go
	# (drawn shapes and circles would each take a draw call of their own)
	var dot := _dot_tex()
	for l in list:
		_pill(dot, Rect2(l.r.position + Vector2(-1, 2), l.r.size + Vector2(2, 2)), Color(0.05, 0.1, 0.25, 0.3))
		_pill(dot, l.r, Color.WHITE)
		_pill(dot, l.r.grow(-3), (l.side.color as Color).darkened(0.06))
	for l in list:
		var m: int = l.t.max_roads()
		var dr := maxf(3.0, l.size * 0.15)
		for i in m:
			var c := Vector2(l.s.top_x + (i - (m - 1) / 2.0) * dr * 2.9, l.r.end.y + dr + 3)
			draw_texture_rect(dot, Rect2(c - Vector2.ONE * (dr + 1.5), Vector2.ONE * (dr + 1.5) * 2), false, l.side.dark)
			draw_texture_rect(dot, Rect2(c - Vector2.ONE * dr, Vector2.ONE * dr * 2), false, Color.WHITE if i < m - l.t.roads.size() else Color(1, 1, 1, 0.35))
	for l in list:
		var p := Vector2(l.s.top_x - l.tw / 2, l.cy + l.size * 0.36)
		draw_string_outline(font, p, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, maxi(2, int(l.size * 0.16)), l.side.dark)
	for l in list:
		var p := Vector2(l.s.top_x - l.tw / 2, l.cy + l.size * 0.36)
		draw_string(font, p, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, Color.WHITE)
	# Upgrades: a gold star for each, above the badge
	for l in list:
		if l.t.stars > 0:
			outlined("★".repeat(l.t.stars), Vector2(l.s.top_x, l.r.position.y - l.size * 0.4), int(l.size * 0.62), Color("#ffd23f"), Color("#9a5b00"))


## The buildings a mission is about: a pulsing ring on the ground around each, and its picture
## over its badge (your headquarters 🛡, Grumble's castle 🎯, the radar stations 📡)
func _marks(w: World) -> void:
	var g: Dictionary = main.goal
	if g.is_empty():
		return
	var marked := []
	if g.hq != null:
		marked.append([g.hq, "🛡" if g.goal == "defend" else "🎯", Color("#ffd23f") if g.goal == "defend" else Color("#ff4a3a")])
	for t in g.targets:
		marked.append([t, "📡", main.SIDES[t.owner].color if t.owner == Battle.PLAYER else Color("#ff9a2e")])
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for m in marked:
		var t = m[0]
		var col: Color = m[2]
		var r: float = t.radius() + 16 + 8 * k
		var ring := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			ring.append(w.project(t.x + cos(a) * r, t.y + sin(a) * r, 2))
		draw_polyline(ring, Color(0.05, 0.1, 0.2, 0.35), 9, true)
		draw_polyline(ring, Color(col, 0.6 + 0.4 * k), 5, true)
		var s := w.tower_screen(t)
		var size := clampf(w.px_per_unit(t.x, t.y) * 50, 18, 42)
		var c := Vector2(s.top_x, s.top_y - size * 1.18 - size * (1.25 if t.stars > 0 else 0.7))
		draw_circle(c + Vector2(0, 3), size * 0.62, Color(0.05, 0.1, 0.2, 0.3))
		draw_circle(c, size * 0.62, Color.WHITE)
		draw_arc(c, size * 0.62, 0, TAU, 32, col, 3.5, true)
		var fs := int(size * 0.66)
		var tw := font.get_string_size(m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-tw / 2, fs * 0.36), m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)


var _dot: Texture2D


## A white dot with a soft edge: the badges' ends and the road dots are made from it
func _dot_tex() -> Texture2D:
	if _dot == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() - (n / 2.0 - 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - d, 0, 1)))
		_dot = ImageTexture.create_from_image(img)
	return _dot


## A pill-shaped badge: the dot's left half, its middle stretched, and its right half
func _pill(tex: Texture2D, r: Rect2, color: Color) -> void:
	var h := r.size.y
	var mid := maxf(0.0, r.size.x - h)
	draw_texture_rect_region(tex, Rect2(r.position, Vector2(h / 2, h)), Rect2(0, 0, 32, 64), color)
	draw_texture_rect_region(tex, Rect2(r.position + Vector2(h / 2, 0), Vector2(mid, h)), Rect2(31, 0, 2, 64), color)
	draw_texture_rect_region(tex, Rect2(r.position + Vector2(h / 2 + mid, 0), Vector2(h / 2, h)), Rect2(32, 0, 32, 64), color)


var _badges := {}


func _badge(owner: int) -> StyleBoxFlat:
	if not _badges.has(owner):
		var sb := StyleBoxFlat.new()
		sb.bg_color = (main.SIDES[owner].color as Color).darkened(0.06)
		sb.border_color = Color.WHITE
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(64)
		sb.shadow_color = Color(0.05, 0.1, 0.25, 0.3)
		sb.shadow_offset = Vector2(0, 3)
		sb.shadow_size = 2
		sb.anti_aliasing = true
		_badges[owner] = sb
	return _badges[owner]


func _drags(w: World, b: Battle) -> void:
	for d in main.drags.values():
		var a = d.from
		var start := w.project(a.x, a.y, 4)
		var end: Vector2 = d.pos
		var ok: bool = a.roads.size() < a.max_roads()
		if d.p != null:
			ok = ok and not b.blocked(a.x, a.y, d.p.x, d.p.y)
		if d.over != null and d.over != a:
			end = w.project(d.over.x, d.over.y, 4)
			# can_link gives true, or the reason it can't ("full", "blocked"...)
			var can = b.can_link(a, d.over, d.side)
			ok = can is bool and can
		var col: Color = main.SIDES[d.side].color if ok else Color("#ff4a3a")
		if d.over != null and d.over != a:
			_preview(w, b, a, d.over, d.side)
		draw_line(start, end, Color(1, 1, 1, 0.9), 16, true)
		# A dashed line that crawls toward the target
		var L := start.distance_to(end)
		var dir := (end - start) / maxf(1, L)
		var off := fmod(Time.get_ticks_msec() / 20.0, 24)
		var x := -off
		while x < L:
			var s0 := maxf(0, x)
			var s1 := minf(L, x + 14)
			if s1 > s0:
				draw_line(start + dir * s0, start + dir * s1, col, 10)
			x += 24
		draw_circle(end, 9, col)


## While dragging a road onto a building: will it work? For an attack, the soldiers it takes
## to win the building (counting a Bunker's double defence, what it trains meanwhile and
## watchtowers on the way) against what you have; for your own building, that soldiers move
## there; or why the road can't be built.
func _preview(w: World, b: Battle, a, t, side: int) -> void:
	var can = b.can_link(a, t, side)
	var text := ""
	var good := false
	if can is String:
		text = {"full": tr("No free road: %d soldiers give more roads") % (10 if a.max_roads() == 1 else 30), "blocked": tr("A wall is in the way"), "exists": tr("Already sending here")}.get(can, "")
	elif t.owner == side:
		text = tr("Moves soldiers here until you cut the road")
		good = true
	else:
		var need: int = b.attack_need(a, t, side)
		var have := floori(a.units)
		good = have >= need
		text = (tr("Need %d · You have %d") % [need, have]) + ("  ✔" if good else "  ✖")
		if need == 0:
			text = tr("Enough soldiers are on the way")
	if text == "":
		return
	var s := w.tower_screen(t)
	var size := 22
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := Rect2(s.top_x - tw / 2 - 16, s.top_y - 118, tw + 32, 40)
	r.position.x = clampf(r.position.x, 6, size_px().x - r.size.x - 6)
	var bg := Color("#27a845") if good else Color("#e2453c")
	if t.owner == side:
		bg = Color("#2f7fe0")
	_pill(_dot_tex(), r.grow(3), Color.WHITE)
	_pill(_dot_tex(), r, bg)
	draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func size_px() -> Vector2:
	return get_viewport().get_visible_rect().size


## Soldiers still to leave on your attack roads: a small count halfway along each
func _road_counts(w: World, b: Battle) -> void:
	for t in b.towers:
		for r in t.roads:
			var left := int(r.get("left", -1))
			if left <= 0:
				continue
			var p := w.project((t.x + r.to.x) / 2, (t.y + r.to.y) / 2, 6)
			var text := str(left)
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var rr := Rect2(p.x - tw / 2 - 9, p.y - 13, tw + 18, 26)
			_pill(_dot_tex(), rr.grow(2), Color.WHITE)
			_pill(_dot_tex(), rr, main.SIDES[t.owner].dark)
			draw_string(font, Vector2(rr.position.x + 9, rr.position.y + 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


# A ghost hand that shows how to drag a road: on the first level, for a hint, or a tutorial step
func _hand(w: World, b: Battle) -> void:
	if not main.drags.is_empty() or main.state != "play":
		return
	var mv: Dictionary = main.guide_move()
	if mv.is_empty():
		return
	var from = mv.from
	var to = mv.to
	var k := fmod(Time.get_ticks_msec() / 1600.0, 1.0)
	var m := clampf((k - 0.15) / 0.6, 0, 1)
	var e := m * m * (3 - 2 * m)
	var a := w.project(from.x, from.y, 4)
	var c := w.project(to.x, to.y, 4)
	var p := a.lerp(c, e)
	var alpha := (1 - k) / 0.15 if k > 0.85 else 1.0
	draw_line(a, p, Color(1, 1, 1, 0.85 * alpha), 6, true)
	# A simple pointing hand: a round palm and a finger
	var hand := Color(1, 1, 1, alpha)
	var edge := Color(0.13, 0.2, 0.35, alpha)
	draw_circle(p + Vector2(10, 26), 15, edge)
	draw_circle(p + Vector2(10, 26), 13, hand)
	draw_rect(Rect2(p + Vector2(-1, -2), Vector2(10, 28)), edge)
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(6, 26)), hand)
