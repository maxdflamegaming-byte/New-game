extends Node2D
## Draws one square: shadow, raised body with shine, eyes that look where it's going, shield
## bubble, a crown on the leader and a "!" when it's close to your trail.

const CELL := 32.0

var p: Player
var leader := false
var threat := false
var frozen := false
var on_screen := true # the board skips drawing squares that are off screen
var label: Label
var _shadow: Texture2D
var _crown: Texture2D
var _emitter: CPUParticles2D # the trail effect from the shop
var _pet_pos := Vector2.INF # where the pet is, in the world
var _pet_face := 1.0
var _world # for the palette (colourblind patterns)


func setup(player: Player, tex_px: int, font: Font, world = null) -> void:
	p = player
	_world = world
	_shadow = Art.tex(Art.SHADOW, tex_px)
	_crown = Art.tex(Art.CROWN, tex_px)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label = Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = 24
	ls.font_color = Color("#26304a")
	ls.outline_size = 8
	ls.outline_color = Color(1, 1, 1, 0.9)
	label.label_settings = ls
	label.text = p.name
	# Teams: your teammates' names are blue with a star, the other team's red
	if world and world.mode.get("teams", false) and p != world.me:
		var mate: bool = world.allies(p, world.me)
		label.text = ("* " if mate else "") + p.name
		ls.font_color = Color("#1f5fd6") if mate else Color("#d6304a")
	if p.is_boss:
		ls.font_color = Color("#d6304a")
		ls.font_size = 34
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 44)
	label.position = Vector2(-120, -CELL * (1.6 + 0.65 * p.size))
	add_child(label)
	_emitter = Cosmetics.make_emitter(p.trail_fx, 1.0 + 0.5 * (p.size - 1.0), p.color)
	if _emitter:
		add_child(_emitter)


func _process(_dt: float) -> void:
	visible = p.alive
	if not visible:
		return
	position = p.pos * CELL
	if _emitter:
		_emitter.emitting = not p.trail.is_empty()
	# The pet trots along behind, catching up when it falls back
	if p.pet != "none":
		var back := Vector2.from_angle(p.angle + PI)
		var goal := position + back * CELL * 1.5 + back.orthogonal() * CELL * 0.7
		if _pet_pos == Vector2.INF or _pet_pos.distance_to(goal) > CELL * 8:
			_pet_pos = goal
		var old := _pet_pos
		_pet_pos = _pet_pos.lerp(goal, 1.0 - exp(-_dt * 6.0))
		if absf(_pet_pos.x - old.x) > 0.3:
			_pet_face = signf(_pet_pos.x - old.x)
	if on_screen:
		queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var s := CELL * 1.4 * p.size
	var bob := sin(t * 12.0 + p.id) * CELL * 0.05
	if p.pet != "none" and _pet_pos != Vector2.INF:
		Cosmetics.draw_pet(self, _pet_pos - position, CELL * 1.3, p.pet, p.color, t + p.id, _pet_face)
	# Soft shadow on the ground
	draw_texture_rect(_shadow, Rect2(-s * 0.75, s * 0.3, s * 1.5, s * 0.55), false)
	# Shield: a glowing bubble that flickers as it runs out
	if p.shield > 0:
		var fade := 0.5 + 0.5 * sin(t * 20.0) if p.shield < 1.5 else 1.0
		draw_circle(Vector2(0, bob), s * 0.98, Color(0.31, 0.55, 1.0, 0.13 * fade), true, -1, true)
		draw_arc(Vector2(0, bob), s * 0.98 + sin(t * 6.0) * 1.5, 0, TAU, 48, Color(0.31, 0.55, 1.0, 0.85 * fade), 3.0, true)
	# Speed: motion lines streaming behind
	if p.fx.speed > 0:
		var back := Vector2.from_angle(p.angle + PI)
		var side := back.orthogonal()
		for k in [-0.35, 0.0, 0.35]:
			var from: Vector2 = back * s * 0.75 + side * k * s + Vector2(0, bob)
			var length: float = s * (0.6 + 0.3 * sin(t * 30.0 + k * 9.0))
			draw_line(from, from + back * length, Color(1.0, 0.72, 0.3, 0.75), maxf(2.0, CELL * 0.14), true)
	# Ghost: see-through and flickering
	if p.fx.ghost > 0:
		modulate.a = 0.45 + 0.15 * sin(t * 10.0)
	else:
		modulate.a = 1.0
	# Body, leaning into turns and squashing a little when it lands, in its shop skin
	var extra := []
	if frozen:
		extra.append(Color(0.63, 0.88, 1.0, 0.55))
	if p.hit_flash > 0:
		extra.append(Color(1, 1, 1, p.hit_flash * 0.8))
	var pattern: Texture2D = Patterns.body(Patterns.index_of(p, _world.COLORS)) if Patterns.on and _world else null
	Cosmetics.draw_square(self, Vector2(0, bob), s, p.color, p.dark, p.skin, Vector2.from_angle(p.angle), t,
			p.turning * 0.14, p.squash, p.blink < 0, extra, pattern)
	var top := -CELL * (2.3 + 0.6 * p.size) + sin(t * 4.0) * 2.0
	if p.boss_kind == "queen":
		# A tiara with a pink gem
		var w := CELL * 1.3
		var pts := PackedVector2Array()
		for k in 7:
			pts.append(Vector2(-w / 2 + k * w / 6, top + w * (0.55 if k % 2 == 0 else 0.15) + (0.0 if k != 3 else -w * 0.15)))
		pts.append(Vector2(w / 2, top + w * 0.8))
		pts.append(Vector2(-w / 2, top + w * 0.8))
		draw_colored_polygon(pts, Color("#ffc93c"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#c98a00"), 3.0, true)
		draw_circle(Vector2(0, top + w * 0.5), w * 0.12, Color("#ff5d9e"), true, -1, true)
	elif p.boss_kind == "wizard":
		# A tall pointy hat with stars
		var w := CELL * 1.5
		var base := top + w * 0.95
		draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.45, base), Vector2(w * 0.12, top - w * 0.35), Vector2(w * 0.45, base)]), Color("#5b3fb0"))
		draw_rect(Rect2(-w * 0.6, base - w * 0.08, w * 1.2, w * 0.16), Color("#3d2a7a"))
		for q in [Vector2(-0.1, 0.45), Vector2(0.12, 0.15), Vector2(0.05, 0.7)]:
			draw_circle(Vector2(q.x * w, top + q.y * w), w * 0.06, Color("#ffd23f"), true, -1, true)
	elif leader or p.is_boss:
		var w := CELL * (1.0 if not p.is_boss else 1.4)
		draw_texture_rect(_crown, Rect2(-w / 2, top, w, w), false)
	if threat:
		var pulse := 1.0 + 0.15 * sin(t * 14.0)
		var c := Vector2(CELL * 1.3, -CELL * 1.3)
		draw_circle(c, CELL * 0.5 * pulse, Color("#ff3c50"), true, -1, true)
		draw_rect(Rect2(c + Vector2(-CELL * 0.07, -CELL * 0.3), Vector2(CELL * 0.14, CELL * 0.34)), Color.WHITE)
		draw_circle(c + Vector2(0, CELL * 0.2), CELL * 0.08, Color.WHITE, true, -1, true)
