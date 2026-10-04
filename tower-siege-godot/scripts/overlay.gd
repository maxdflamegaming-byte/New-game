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
	if show_labels and main.state != "menu" and main.screen_open == "":
		for t in b.towers:
			_label(t, w)
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
	if main.state != "menu" and main.screen_open == "":
		for f in main.floats:
			var p := w.project(f.t.x, f.t.y, w.tower_top(f.t) + 30 + (1.3 - f.life) * 40)
			var col: Color = f.color
			col.a = minf(1, f.life * 1.5)
			outlined(f.text, p, 26, col, Color(0.08, 0.1, 0.2, col.a))
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


# The number on a roof, and dots for its roads (white = free, faded = in use)
func _label(t, w: World) -> void:
	var s := w.tower_screen(t)
	var size := int(clampf(w.px_per_unit(t.x, t.y) * 46, 16, 40))
	var n := floori(maxf(0, t.units))
	var text := "Max" if n >= Battle.CAP else str(n)
	if t.type == "factory":
		text = "⇡" + text
	var y: float = s.top_y - size * 0.55
	var dark: Color = main.SIDES[t.owner].dark
	outlined(text, Vector2(s.top_x, y), size, Color.WHITE, dark)
	# Upgrades: a gold star for each
	if t.stars > 0:
		outlined("★".repeat(t.stars), Vector2(s.top_x, y - size * 0.95), int(size * 0.6), Color("#ffd23f"), Color("#9a5b00"))
	var m: int = t.max_roads()
	var dr := maxf(3.0, size * 0.17)
	for i in m:
		var c := Vector2(s.top_x + (i - (m - 1) / 2.0) * dr * 2.9, y + size * 0.72)
		draw_circle(c, dr + 1.5, dark)
		draw_circle(c, dr, Color.WHITE if i < m - t.roads.size() else Color(1, 1, 1, 0.35))


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
			ok = b.can_link(a, d.over, d.side) == true
		var col: Color = main.SIDES[d.side].color if ok else Color("#ff4a3a")
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


# A ghost hand that shows how to drag a road, on the first level
func _hand(w: World, b: Battle) -> void:
	if not main.hand_shown or not main.drags.is_empty():
		return
	var from = null
	var to = null
	for t in b.towers:
		if t.owner == Battle.PLAYER and from == null:
			from = t
		if t.owner == 0 and (to == null or t.units < to.units):
			to = t
	if from == null or to == null:
		return
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
