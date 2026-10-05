class_name Cutscene
extends CanvasLayer
## Cut scenes: cinema bars, camera moves over the 3D field, characters (characters.gd) who
## appear, talk and act, a dialog box with their portrait and typewriter text, title banners,
## fades, fireworks and a cheering crowd. The scenes themselves are in story.gd.
##
## A scene is a Run: `var r := cutscene.begin()`, then `await r.say(...)`, `await r.cam_move(...)`
## and so on, then `cutscene.finish(r)`. Skip ends a run early (every step then returns at
## once); starting another run while one plays makes the old one give up quietly.

const BAR := 74.0

var main
var ui: UI
var run: Run                     # the scene playing, if any
var auto := false                # dialogs move on by themselves (for tests)
var stage: Node3D                # the characters and props on the field
var actors := {}                 # id -> Characters.Actor
var portraits := {}              # id -> Texture2D (made the first time each one speaks)
var _tap := false

var root: Control
var bar_top: ColorRect
var bar_bottom: ColorRect
var dialog: PanelContainer
var portrait_box: PanelContainer
var portrait: TextureRect
var portrait_letter: Label
var name_label: Label
var text_label: Label
var next_arrow: Label
var banner_root: VBoxContainer
var banner_box: PanelContainer
var banner_label: Label
var banner_sub: Label
var skip_btn: Button
var fade_rect: ColorRect
var tint_rect: ColorRect
var _banner_tween: Tween
var safe_top := 0.0              # a camera notch: the top bar grows by this much


## One cut scene playing
class Run:
	extends RefCounted
	var c: Cutscene
	var skipping := false
	var dead := false            # another scene took over
	var short := false           # a tap anywhere ends it (intros and celebrations)

	func done() -> bool:
		return dead or skipping

	func _frame() -> float:
		await c.get_tree().process_frame
		return c.get_process_delta_time()

	func wait(secs: float) -> void:
		var t := 0.0
		while t < secs and not done():
			t += await _frame()

	## Where a camera at `dist` from `target`, raised by `pitch` and turned by `yaw`, sits
	func shot(target: Vector3, dist: float, pitch: float, yaw := 0.0) -> Transform3D:
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var pos := target + dir * dist
		return Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)

	func cam_cut(xf: Transform3D) -> void:
		if not dead:
			c.main.world.camera.transform = xf
			c._clear_view(xf)

	## Glide the camera (smoothly starting and stopping). The dialog box goes while it moves.
	func cam_move(xf: Transform3D, secs: float) -> void:
		if dead:
			return
		if secs > 0.2:
			c.dialog.visible = false
		c._clear_view(Transform3D()) # everything back while flying
		var cam: Camera3D = c.main.world.camera
		var from := cam.transform
		# Fly the camera and the spot it looks at separately (turning a transform straight
		# into one facing the other way would swing it up to look at the sky); a big move
		# arcs up over the field
		var p0 := from.origin
		var p1 := xf.origin
		var a0 := _aim(from)
		var a1 := _aim(xf)
		var lift := p0.distance_to(p1) * 0.22
		var t := 0.0
		while t < secs and not done():
			t += await _frame()
			var k := clampf(t / secs, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			var pos := p0.lerp(p1, k) + Vector3(0, sin(k * PI) * lift, 0)
			var aim := a0.lerp(a1, k)
			var dir := aim - pos
			if dir.length() > 1.0 and absf(dir.normalized().y) < 0.995:
				cam.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
		if not dead:
			cam.transform = xf
			c._clear_view(xf)

	## The point on the ground (or just above it) a camera looks at
	func _aim(xf: Transform3D) -> Vector3:
		var f := -xf.basis.z
		if f.y < -0.05:
			return xf.origin + f * ((xf.origin.y - 20.0) / -f.y)
		return xf.origin + f * 600.0

	## Back to the battle camera
	func fly_home(secs := 0.7) -> void:
		await cam_move(c.main.world.cam_base, secs)

	func say(id: String, text: String) -> void:
		if not done():
			await c._say(self, id, text)

	func banner(text: String, sub := "", color := UI.ORANGE, secs := 1.4) -> void:
		if not done():
			c._banner(text, sub, color, secs)

	## A character pops up at (x, z), turned towards `face`
	func spawn(id: String, x: float, z: float, face: Vector3) -> void:
		if not dead:
			c._spawn(id, x, z, face)

	func act(id: String, pose: String) -> void:
		var a = c.actors.get(id)
		if a != null and not dead:
			a.pose = pose

	## A character runs off in a direction (field units per second)
	func flee(id: String, dir: Vector3) -> void:
		var a = c.actors.get(id)
		if a != null and not dead:
			a.pose = "flee"
			a.run_dir = dir
			a.rotation.y = atan2(dir.x, dir.z)

	func crowd(t, n: int) -> void:
		if not dead:
			c._crowd(t, n)

	func fireworks(x: float, z: float, n: int, secs: float) -> void:
		for i in n:
			if done():
				return
			var a := randf() * TAU
			var d := 60 + randf() * 160
			c.main.world.burst(x + cos(a) * d, 200 + randf() * 120, z + sin(a) * d * 0.6, Color(World.BRIGHT[i % World.BRIGHT.size()]))
			c.main.play_sound("firework")
			await wait(secs / n)

	func tint(alpha: float, secs: float) -> void:
		if not dead:
			c.tint_rect.create_tween().tween_property(c.tint_rect, "color:a", alpha, secs)

	func fade_from_black(secs: float) -> void:
		if dead:
			return
		c.fade_rect.color = Color(0, 0, 0, 1)
		c.fade_rect.create_tween().tween_property(c.fade_rect, "color:a", 0.0, secs)

	func sfx(name: String) -> void:
		if not done():
			c.main.play_sound(name)


func build() -> void:
	layer = 3
	stage = Node3D.new()
	main.world.add_child(stage)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ui.theme
	root.visible = false
	add_child(root)
	_fit()
	get_viewport().size_changed.connect(_fit)

	tint_rect = _rect(Color(0.16, 0.18, 0.3, 0))
	# Cinema bars
	bar_top = ColorRect.new()
	bar_top.color = Color("#0d1022")
	bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_top)
	bar_bottom = ColorRect.new()
	bar_bottom.color = Color("#0d1022")
	bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bottom)

	# Title banner
	banner_root = ui.vbox(10)
	banner_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_root.offset_top = 210
	banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner_root)
	banner_box = PanelContainer.new()
	banner_box.add_theme_stylebox_override("panel", ui.box(UI.ORANGE, UI.INK, 16, 4, 6))
	banner_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_label = ui.label("", 62, Color.WHITE, 14)
	banner_box.add_child(banner_label)
	banner_root.add_child(banner_box)
	banner_sub = ui.label("", 30, Color.WHITE, 10)
	banner_root.add_child(banner_sub)
	banner_root.modulate.a = 0

	# Dialog box: portrait, name, text and a "tap to go on" arrow
	dialog = PanelContainer.new()
	var ds := ui.box(Color.WHITE, UI.INK, 24, 4, 6)
	ds.set_content_margin_all(18)
	dialog.add_theme_stylebox_override("panel", ds)
	dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialog.offset_left = 18
	dialog.offset_right = -18
	dialog.offset_bottom = -BAR - 14
	dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.visible = false
	root.add_child(dialog)
	var h := ui.hbox(16)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	dialog.add_child(h)
	portrait_box = PanelContainer.new()
	portrait_box.custom_minimum_size = Vector2(132, 132)
	portrait_box.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	h.add_child(portrait_box)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_box.add_child(portrait)
	portrait_letter = ui.label("", 64, Color.WHITE, 10)
	portrait_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_box.add_child(portrait_letter)
	var v := ui.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	name_label = ui.label("", 30, Color.WHITE, 8)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(name_label)
	text_label = ui.wrapped(ui.label("", 26, UI.INK, 0, ui.font_m), 470)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # translated before it's typed out
	text_label.custom_minimum_size.y = 96
	v.add_child(text_label)
	next_arrow = ui.label("▼", 26, UI.INK, 0)
	next_arrow.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	next_arrow.position = Vector2(-44, -40)
	next_arrow.visible = false
	dialog.add_child(next_arrow)

	skip_btn = ui.button("Skip ▶▶", "white", 22, func(): skip())
	skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_btn.offset_left = -170
	skip_btn.offset_right = -16
	skip_btn.offset_top = BAR + 12
	skip_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(skip_btn)

	fade_rect = _rect(Color(0, 0, 0, 0))


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _fit() -> void:
	root.position = Vector2.ZERO
	root.size = get_viewport().get_visible_rect().size


## Keep the Skip button and the banner below a camera notch (the black bar covers it)
func fit_safe(top: float) -> void:
	safe_top = top
	skip_btn.offset_top = BAR + top + 12
	banner_root.offset_top = 210 + top
	if run != null and bar_top.offset_bottom > 0:
		bar_top.offset_bottom = BAR + top


func playing() -> bool:
	return run != null


## Start a scene (any scene still playing gives up)
func begin(short := false) -> Run:
	if run != null:
		run.dead = true
	_clear_stage()
	run = Run.new()
	run.c = self
	run.short = short
	_tap = false
	main.world.cam_free = true
	root.visible = true
	skip_btn.visible = true
	dialog.visible = false
	banner_root.modulate.a = 0
	tint_rect.color.a = 0
	fade_rect.color.a = 0
	_bars(true)
	return run


func current(r: Run) -> bool:
	return r != null and r == run and not r.dead


func skip() -> void:
	if run != null:
		run.skipping = true
		_tap = true


## End a scene: the bars slide away and the camera is the battle's again
func finish(r: Run) -> void:
	if r != run:
		return
	run = null
	dialog.visible = false
	skip_btn.visible = false
	next_arrow.visible = false
	if _banner_tween:
		_banner_tween.kill()
	banner_root.modulate.a = 0
	tint_rect.color.a = 0
	fade_rect.color.a = 0
	_bars(false)
	_clear_view(Transform3D())
	_clear_stage()
	main.world.cam_free = false
	# Right away, so the first touch after the scene lands where it should
	main.world.camera.transform = main.world.cam_base


## Stop whatever is playing, without finishing it nicely (leaving to the menu, say)
func abort() -> void:
	if run != null:
		run.dead = true
		finish(run)


## A shot's view is cleared: buildings and celebrating soldiers standing between the camera
## and what it looks at are hidden for that shot (an identity transform shows them all again)
func _clear_view(xf: Transform3D) -> void:
	var hide := xf != Transform3D()
	var cam := Vector2(xf.origin.x, xf.origin.z)
	var aim3: Vector3 = run._aim(xf) if hide and run != null else Vector3.ZERO
	var aim := Vector2(aim3.x, aim3.z)
	var nodes := []
	for t in main.battle.towers:
		var m = main.world.models.get(t.id)
		if m != null:
			nodes.append([m.node, t.radius() + 30.0])
	for ch in stage.get_children():
		if ch is Cheerer:
			nodes.append([ch, 40.0])
	for n in nodes:
		var node: Node3D = n[0]
		var blocks := false
		if hide:
			var p := Vector2(node.position.x, node.position.z)
			var seg := aim - cam
			var k := clampf((p - cam).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
			blocks = k > 0.02 and k < 0.9 and p.distance_to(cam + seg * k) < n[1]
		node.visible = not blocks


func _clear_stage() -> void:
	for ch in stage.get_children():
		ch.queue_free()
	actors.clear()


func _bars(show: bool) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(bar_top, "offset_bottom", BAR + safe_top if show else 0.0, 0.35).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(bar_bottom, "offset_top", -BAR if show else 0.0, 0.35).set_trans(Tween.TRANS_CUBIC)
	if not show:
		tw.chain().tween_callback(func(): root.visible = run != null)


func _input(e: InputEvent) -> void:
	if run == null:
		return
	var pressed: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE])
	if not pressed:
		return
	if e is InputEventKey and e.keycode == KEY_ESCAPE:
		skip()
		return
	if e is InputEventScreenTouch and skip_btn.get_global_rect().has_point(e.position):
		return # the Skip button handles it
	if run.short:
		skip()
	else:
		_tap = true


# ---------- Dialog ----------
func _say(r: Run, id: String, text: String) -> void:
	var a = actors.get(id)
	var col: Color = main.SIDES[Characters.side(id)].color
	# The portrait first (drawn the first time), so the name, face and words change together
	if not portraits.has(id):
		portraits[id] = await _portrait(id)
		if r.done():
			return
	name_label.text = Characters.display_name(id)
	name_label.add_theme_color_override("font_outline_color", col.darkened(0.35))
	name_label.add_theme_color_override("font_color", col.lightened(0.15))
	var ps := ui.box(col.lightened(0.55), col.darkened(0.2), 66, 4, 0)
	ps.set_content_margin_all(0)
	portrait_box.add_theme_stylebox_override("panel", ps)
	portrait.texture = portraits[id]
	portrait_letter.text = "" if portraits[id] else Characters.display_name(id).split(" ")[-1].left(1)
	if not dialog.visible:
		dialog.visible = true
		ui.pop(dialog, 0.0, 0.85)
	var shown := TranslationServer.translate(text)
	text_label.text = shown
	text_label.visible_ratio = 0.0
	next_arrow.visible = false
	if a != null:
		a.talking = true
	var dur := clampf(shown.length() * 0.028, 0.45, 2.6)
	var t := 0.0
	var blip := 0.0
	_tap = false
	var voice: String = Characters.CAST[id].voice
	while t < dur and not r.done() and not _tap:
		var dt: float = await r._frame()
		t += dt
		blip -= dt
		if blip <= 0:
			blip = 0.085
			main.play_sound(voice)
		text_label.visible_ratio = t / dur
	text_label.visible_ratio = 1.0
	if a != null:
		a.talking = false
	if r.done():
		return
	# Wait for a tap (or move on by itself in auto mode)
	next_arrow.visible = true
	_tap = false
	var waited := 0.0
	while not r.done() and not _tap and not (auto and waited > 0.6):
		waited += await r._frame()
		next_arrow.position.y = -40 + absf(sin(waited * 5.0)) * -6
	next_arrow.visible = false
	_tap = false


## A picture of the character's head and shoulders, for the dialog box
func _portrait(id: String) -> Texture2D:
	var mat: Material = main.world.paint_material(main.world.sides[Characters.side(id)].color)
	var a := Characters.build(id, mat)
	a.set_process(false)
	a.rotation.y = 0.35
	return await main.world.render_node(a, Vector3(4, 36, 50), Vector3(0, 31, 0), 200)


# ---------- Banner ----------
func _banner(text: String, sub: String, color: Color, secs: float) -> void:
	banner_label.text = text
	banner_sub.text = sub
	banner_sub.visible = sub != ""
	banner_box.add_theme_stylebox_override("panel", ui.box(color, UI.INK, 16, 4, 6))
	if _banner_tween:
		_banner_tween.kill()
	banner_box.pivot_offset = banner_box.size / 2
	banner_box.scale = Vector2(0.3, 0.3)
	banner_root.modulate.a = 0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_root, "modulate:a", 1.0, 0.12)
	_banner_tween.parallel().tween_property(banner_box, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(secs)
	_banner_tween.tween_property(banner_root, "modulate:a", 0.0, 0.25)
	# Its size is only right once it's laid out
	await get_tree().process_frame
	banner_box.pivot_offset = banner_box.size / 2


# ---------- Characters and props ----------
func _spawn(id: String, x: float, z: float, face: Vector3) -> void:
	if actors.has(id):
		actors[id].queue_free()
	var mat: Material = main.world.paint_material(main.world.sides[Characters.side(id)].color)
	var a := Characters.build(id, mat)
	var s := 1.75 * World.S
	a.position = Vector3(x, 0, z)
	a.rotation.y = atan2(face.x - x, face.z - z)
	a.scale = Vector3.ONE * s * 0.2
	stage.add_child(a)
	actors[id] = a
	a.create_tween().tween_property(a, "scale", Vector3.ONE * s, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 6:
		var ang := i * TAU / 6
		main.world.puff(x + cos(ang) * 30, 8, z + sin(ang) * 30, Color.WHITE, 34, 0.6, 30)
	main.play_sound("pop")


## Soldiers in your army's color jumping for joy around a building
func _crowd(t, n: int) -> void:
	var mesh: Mesh = main.world.soldiers_me.multimesh.mesh
	var mat: Material = main.world.paint_material(main.world.sides[1].color, false, true)
	for i in n:
		var c := Cheerer.new()
		c.mesh = mesh
		c.material_override = mat
		var ang := (i + 0.5) * TAU / n
		var d: float = t.radius() * 1.1 + 40 + (i % 3) * 26
		c.position = Vector3(t.x + cos(ang) * d, 0, t.y + sin(ang) * d)
		c.rotation.y = randf() * TAU
		c.scale = Vector3.ONE * 1.75 * World.S
		c.phase = randf() * TAU
		stage.add_child(c)


class Cheerer:
	extends MeshInstance3D
	var phase := 0.0
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		position.y = absf(sin(t * 6.5 + phase)) * 22.0
		rotation.y += dt * (1.5 if int(phase * 10) % 2 == 0 else -1.5)
