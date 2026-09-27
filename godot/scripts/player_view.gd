extends Node2D
## Draws one square: shadow, raised body with shine, eyes that look where it's going, shield
## bubble, a crown on the leader and a "!" when it's close to your trail.

const CELL := 32.0

var p: Player
var leader := false
var threat := false
var frozen := false
var label: Label
var _body: Texture2D
var _side: Texture2D
var _gloss: Texture2D
var _shadow: Texture2D
var _crown: Texture2D


func setup(player: Player, tex_px: int, font: Font, world = null) -> void:
	p = player
	_body = Art.tex(Art.BODY, tex_px)
	_side = Art.tex(Art.SIDE, tex_px)
	_gloss = Art.tex(Art.GLOSS, tex_px)
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


func _process(_dt: float) -> void:
	visible = p.alive
	if not visible:
		return
	position = p.pos * CELL
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var s := CELL * 1.4 * p.size
	var bob := sin(t * 12.0 + p.id) * CELL * 0.05
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
	# Body, leaning into turns and squashing a little when it lands
	draw_set_transform(Vector2(0, bob), p.turning * 0.14, Vector2(1 + p.squash * 0.12, 1 - p.squash * 0.12))
	draw_texture_rect(_side, Rect2(-s / 2, -s / 2 + s * 0.17, s, s), false, p.dark)
	draw_texture_rect(_body, Rect2(-s / 2, -s / 2, s, s), false, p.color)
	draw_texture_rect(_gloss, Rect2(-s / 2, -s / 2, s, s), false)
	if frozen:
		draw_texture_rect(_side, Rect2(-s / 2, -s / 2, s, s), false, Color(0.63, 0.88, 1.0, 0.55))
	if p.hit_flash > 0:
		draw_texture_rect(_side, Rect2(-s / 2, -s / 2, s, s), false, Color(1, 1, 1, p.hit_flash * 0.8))
	# Eyes look the way it's heading
	var look := Vector2.from_angle(p.angle)
	for side in [-1, 1]:
		var e := Vector2(side * s * 0.2, -s * 0.05) + look * s * 0.08
		if p.blink < 0:
			draw_rect(Rect2(e - Vector2(s * 0.11, s * 0.025), Vector2(s * 0.22, s * 0.05)), Color("#26304a"))
		else:
			draw_circle(e, s * 0.14, Color.WHITE, true, -1, true)
			draw_circle(e + look * s * 0.06, s * 0.07, Color("#26304a"), true, -1, true)
			draw_circle(e + look * s * 0.06 + Vector2(-s * 0.025, -s * 0.03), s * 0.025, Color.WHITE, true, -1, true)
	draw_set_transform(Vector2.ZERO)
	if leader or p.is_boss:
		var w := CELL * (1.0 if not p.is_boss else 1.4)
		draw_texture_rect(_crown, Rect2(-w / 2, -CELL * (2.3 + 0.6 * p.size) + sin(t * 4.0) * 2.0, w, w), false)
	if threat:
		var pulse := 1.0 + 0.15 * sin(t * 14.0)
		var c := Vector2(CELL * 1.3, -CELL * 1.3)
		draw_circle(c, CELL * 0.5 * pulse, Color("#ff3c50"), true, -1, true)
		draw_rect(Rect2(c + Vector2(-CELL * 0.07, -CELL * 0.3), Vector2(CELL * 0.14, CELL * 0.34)), Color.WHITE)
		draw_circle(c + Vector2(0, CELL * 0.2), CELL * 0.08, Color.WHITE, true, -1, true)
