extends Node2D
## Color Claim: game flow (menu, countdown, play, win/lose), controls, camera, HUD and screens.
## Behind the menu a bots-only game plays as a live background.

const CELL := 32.0
const SAVE_PATH := "user://save.cfg"
const INK := Color("#1f2744")
const MUTED := Color("#6b7690")
const YELLOW := Color("#ffc233")
const NAVY := Color("#1d2342")

var world
var view
var sfx
var music
var cam: Camera2D
var font: Font
var font_med: Font

var state := "menu" # menu, countdown, play, won, paused, over
var my_color := 0
var map_id := "square"
var wallet := 0 # coins you've saved up
var best := 0.0
var games := 0
var wins := 0
var countdown := 0.0
var slowmo := 0.0
var shake := 0.0
var peak := 0.0
var play_time := 0.0
var ending := false
var _game_id := 0 # bumps every game, so a delayed event from an old game does nothing
var _kos: Array[float] = []
var _marks := {}
var _hud_timer := 0.0
var _mm_timer := 0.0
var _last_count := 0

# Touch joystick: put a finger down anywhere and drag
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO

# UI
var ui_layer: CanvasLayer
var hud: Control
var pct_label: Label
var goal_bar: Control
var status_label: Label
var coin_label: Label
var fx_row: HBoxContainer
var board_rows: Array = []
var minimap: TextureRect
var mm_dot: Control
var mm_img: Image
var mm_tex: ImageTexture
var toast_label: Label
var toast_panel: PanelContainer
var _toast_tween: Tween
var callout_label: Label
var count_label: Label
var stick_view: Control
var menu: Control
var pause_screen: Control
var over_screen: Control
var over_title: Label
var over_reason: Label
var over_stats: Label
var over_best: Label
var over_coins: Label
var wallet_label: Label
var maps_row: HBoxContainer
var music_btn: Button
var best_label: Label
var swatches: HBoxContainer
var sound_btn: Button


func _ready() -> void:
	randomize()
	_load()
	font = load("res://assets/fonts/Fredoka-Bold.ttf")
	font_med = load("res://assets/fonts/Fredoka-Medium.ttf")
	sfx = preload("res://scripts/sfx.gd").new()
	sfx.muted = get_meta("muted", false)
	add_child(sfx)
	music = preload("res://scripts/music.gd").new()
	music.enabled = get_meta("music", true)
	add_child(music)
	world = preload("res://scripts/world.gd").new()
	add_child(world)
	view = preload("res://scripts/board_view.gd").new()
	add_child(view)
	view.setup(world, font, 128)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	world.captured.connect(_on_captured)
	world.knocked_out.connect(_on_knocked_out)
	world.picked.connect(_on_picked)
	world.coin_taken.connect(_on_coin)
	_build_ui()
	_start_demo()


# ---------- Game flow ----------

func _start_demo() -> void:
	_game_id += 1
	state = "menu"
	world.setup(my_color, "You", true, map_id)
	view.rebuild()
	_snap_camera()
	_show(menu)
	_refresh_menu()


func start_game() -> void:
	_game_id += 1
	world.setup(my_color, "You", false, map_id)
	view.rebuild()
	_snap_camera()
	state = "countdown"
	countdown = 3.0
	_last_count = 4
	peak = 0.0
	play_time = 0.0
	slowmo = 0.0
	ending = false
	_kos.clear()
	_marks.clear()
	_show(null)
	hud.visible = true
	_update_hud()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var me: Player = world.me
	match state:
		"menu":
			world.update(dt)
			if not me.alive:
				world.spawn(me)
		"countdown":
			countdown -= dt
			_steer()
			me.angle = me.desired
			var c := int(ceil(countdown))
			if c != _last_count and c > 0:
				_last_count = c
				_pop(count_label, str(c))
				sfx.play("beep")
			if countdown <= 0:
				state = "play"
				_pop(count_label, "GO!")
				sfx.play("go")
				_vibrate(40)
		"play", "won":
			var k := 0.35 if slowmo > 0 else 1.0
			slowmo = maxf(0.0, slowmo - dt)
			if me.alive and state == "play":
				_steer()
			world.update(dt * k)
			play_time += dt * k
			if me.alive:
				peak = maxf(peak, world.pct(me))
				if state == "play" and world.pct(me) >= world.WIN_PCT:
					_win()
			_check_danger()
			_milestones()
	_update_camera(dt)
	_hud_timer -= dt
	if hud.visible and _hud_timer <= 0:
		_hud_timer = 0.2
		_update_hud()
	_mm_timer -= dt
	if hud.visible and _mm_timer <= 0:
		_mm_timer = 0.25
		_update_minimap()
	stick_view.queue_redraw()


func _win() -> void:
	state = "won"
	world.won = true
	slowmo = 1.4
	sfx.play("win")
	_vibrate(120)
	_callout("VICTORY!", YELLOW)
	for i in 6:
		view.burst(world.me.pos + Vector2(randf_range(-6, 6), randf_range(-5, 5)), world.COLORS[i], 30, 520.0)
	var id := _game_id
	await get_tree().create_timer(1.6).timeout
	if id == _game_id:
		_game_over(true, "You claimed %d%% of the map!" % int(world.WIN_PCT))


func _game_over(won: bool, reason: String) -> void:
	if state == "over":
		return
	state = "over"
	games += 1
	if won:
		wins += 1
	var score := snappedf(peak, 0.1)
	var new_best := score > best
	if new_best:
		best = score
	var earned: int = roundi(score * 2) + world.me.kills * 5 + (50 if won else 0) + world.coins_picked
	wallet += earned
	_save()
	over_coins.text = "+%d coins" % earned
	over_title.text = "You win!" if won else "Game over"
	over_title.label_settings.font_color = YELLOW if won else Color.WHITE
	over_reason.text = reason
	over_stats.text = "Best size %.1f%%  ·  %d knockout%s  ·  %s" % [score, world.me.kills, "" if world.me.kills == 1 else "s", _fmt_time(play_time)]
	over_best.text = "New best!" if new_best else "Your best: %.1f%%" % best
	_show(over_screen)


func _pause() -> void:
	if state != "play" and state != "countdown":
		return
	pause_screen.set_meta("was", state)
	state = "paused"
	_show(pause_screen)


func _resume() -> void:
	if state != "paused":
		return
	state = pause_screen.get_meta("was", "play")
	_show(null)


func _to_menu() -> void:
	hud.visible = false
	_start_demo()


func _back() -> void:
	match state:
		"play", "countdown":
			_pause()
		"paused":
			_resume()
		"over":
			_to_menu()
		"menu":
			get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()


# ---------- Events ----------

func _on_captured(p: Player, _cells: PackedInt32Array, gain: float) -> void:
	if p != world.me or state == "menu":
		return
	sfx.play("capture")
	if gain >= 1.0:
		_vibrate(20)
	if gain >= 10:
		_callout("GIGA LOOP!", Color("#ff5d73"))
		shake = 0.5
	elif gain >= 5:
		_callout("MEGA LOOP!", Color("#ff8c42"))
		shake = 0.3


func _on_knocked_out(v: Player, killer: Player, how: String, _lost: PackedInt32Array) -> void:
	if state == "menu":
		return
	var me: Player = world.me
	if v == me and not ending:
		ending = true
		sfx.play("death")
		shake = 1.0
		_vibrate(300)
		var reason := "You crossed your own trail!" if killer == me \
			else "%s swallowed all your land!" % killer.name if how == "swallow" \
			else "You bumped into %s outside your land!" % killer.name if how == "bump" \
			else "%s cut your trail!" % killer.name
		var id := _game_id
		await get_tree().create_timer(0.9).timeout
		if id == _game_id:
			_game_over(false, reason)
	elif killer == me and v != me:
		sfx.play("cut")
		shake = maxf(shake, 0.4)
		_vibrate(40)
		_toast("You knocked out %s!" % v.name)
		var now: float = world.time
		_kos = _kos.filter(func(t): return now - t < 4.0)
		_kos.append(now)
		if _kos.size() >= 3:
			_callout("TRIPLE KO!", Color("#ff5d73"))
		elif _kos.size() == 2:
			_callout("DOUBLE KO!", Color("#ff8c42"))


const PICK_TOASTS := {
	"speed": "Speed boost!", "shield": "Shield! Nobody can cut your trail", "freeze": "Freeze! Everyone else slows down",
	"ghost": "Ghost! You can cross your own trail", "paint": "Paint bomb!",
}


func _on_picked(p: Player, kind: String, _at: Vector2) -> void:
	if state == "menu":
		return
	if p == world.me:
		sfx.play(kind)
		_toast(PICK_TOASTS[kind])
		_vibrate(15)
	elif kind == "freeze" and world.me.alive and p.pos.distance_to(world.me.pos) < 40:
		sfx.play("freeze")
		_toast("%s froze everyone!" % p.name)


func _on_coin(p: Player, at: Vector2) -> void:
	if p == world.me and state != "menu":
		sfx.play("coin")
		view.float_text(at + Vector2(0, -1), "+%d" % world.COIN_VALUE, Color("#ffd23f"), Color("#9a6a00"), 0.8)


func _milestones() -> void:
	var p: float = world.pct(world.me)
	for m in [[10, "10% CLAIMED", Color("#4f8cff")], [25, "DOMINATING!", Color("#b06bff")], [40, "ALMOST THERE!", Color("#2ec4b6")]]:
		if p >= m[0] and not _marks.has(m[0]):
			_marks[m[0]] = true
			_callout(m[1], m[2])


## Enemies close to your exposed trail get a "!" and your trail pulses red
func _check_danger() -> void:
	var me: Player = world.me
	var danger := 0.0
	var n: int = world.N
	for p in world.players:
		if p == null or p == me:
			continue
		var close := INF
		if me.alive and me.trail.size() > 0 and me.shield <= 0 and p.alive:
			for k in range(0, me.trail.size(), 2):
				var i: int = me.trail[k]
				close = minf(close, p.pos.distance_to(Vector2(i % n + 0.5, i / n + 0.5)))
		view.views[p.id].threat = close < 10
		if close < 7:
			danger = maxf(danger, 1.0 - close / 7.0)
	if danger > 0.3 and view.danger <= 0.3:
		sfx.play("warn")
	view.danger = danger


# ---------- Controls ----------

func _steer() -> void:
	var me: Player = world.me
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		v.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		v.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		v.y += 1
	if v == Vector2.ZERO and _stick_index >= 0 and _stick_pos.distance_to(_stick_origin) > 12:
		v = _stick_pos - _stick_origin
	if v != Vector2.ZERO:
		me.desired = v.angle()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _stick_index == -1:
			_stick_index = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif not e.pressed and e.index == _stick_index:
			_stick_index = -1
	elif e is InputEventScreenDrag and e.index == _stick_index:
		_stick_pos = e.position
		# Drag far and the joystick follows your finger, so you never run out of room
		var d: Vector2 = _stick_pos - _stick_origin
		if d.length() > 90:
			_stick_origin = _stick_pos - d.normalized() * 90
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE or e.keycode == KEY_P:
			if state == "paused":
				_resume()
			else:
				_pause()
		elif e.keycode == KEY_ENTER or e.keycode == KEY_SPACE:
			if state == "menu" or state == "over":
				start_game()


func _draw_stick() -> void:
	if _stick_index < 0 or not (state == "play" or state == "countdown"):
		return
	stick_view.draw_circle(_stick_origin, 90, Color(1, 1, 1, 0.12), true, -1, true)
	stick_view.draw_arc(_stick_origin, 90, 0, TAU, 64, Color(0.12, 0.15, 0.27, 0.35), 3.0, true)
	var d := (_stick_pos - _stick_origin).limit_length(90)
	stick_view.draw_circle(_stick_origin + d, 38, Color(0.12, 0.15, 0.27, 0.35), true, -1, true)


func _vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------- Camera ----------

func _cam_zoom() -> float:
	var vis := get_viewport_rect().size
	var cell_px := minf(vis.x, vis.y) / 25.0
	var z := cell_px / CELL * (1.0 - minf(0.3, world.pct(world.me) / 90.0))
	return z * (0.8 if state == "menu" else 1.0)


func _snap_camera() -> void:
	cam.position = world.me.pos * CELL
	cam.zoom = Vector2.ONE * _cam_zoom()


## The camera glides after you, looking a little ahead, and zooms out as your land grows
func _update_camera(dt: float) -> void:
	var me: Player = world.me
	var lead := Vector2.from_angle(me.angle) * 2.2 if me.alive else Vector2.ZERO
	cam.position = cam.position.lerp((me.pos + lead) * CELL, 1.0 - exp(-dt * 4.5))
	cam.zoom = cam.zoom.lerp(Vector2.ONE * _cam_zoom(), 1.0 - exp(-dt * 1.8))
	shake = maxf(0.0, shake - dt * 2.0)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * CELL * 0.35


# ---------- HUD ----------

func _update_hud() -> void:
	var me: Player = world.me
	pct_label.text = "%.1f%%" % world.pct(me)
	goal_bar.set_meta("fill", clampf(world.pct(me) / world.WIN_PCT, 0, 1))
	goal_bar.set_meta("color", me.color)
	goal_bar.queue_redraw()
	var kos := "%d KO%s" % [me.kills, "" if me.kills == 1 else "s"]
	status_label.text = ("#%d of %d  ·  %s" % [world.rank_of(me), world.alive_count(), kos]) if me.alive else "Knocked out  ·  " + kos
	coin_label.text = str(wallet + world.coins_picked)
	# Power-ups running now, with seconds left
	for c in fx_row.get_children():
		c.queue_free()
	var chips := []
	if me.alive:
		for k in me.fx:
			if me.fx[k] > 0:
				chips.append([world.POWERUPS[k].name, me.fx[k], world.POWERUPS[k].color])
		if me.shield > 0:
			chips.append(["Shield", me.shield, world.POWERUPS.shield.color])
		if world.freezer and world.freezer != me:
			chips.append(["Frozen!", world.freezer.fx.freeze, Color("#3fc7f5")])
	for c in chips:
		var chip := PanelContainer.new()
		var st := _style(c[2], 12)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", st)
		chip.add_child(_label("%s %ds" % [c[0], ceili(c[1])], 18, Color.WHITE))
		fx_row.add_child(chip)
	var ranked := []
	for p in world.players:
		if p and p.alive:
			ranked.append(p)
	ranked.sort_custom(func(a, b): return world.counts[a.id] > world.counts[b.id])
	var top := ranked.slice(0, 5)
	if me.alive and not top.has(me):
		top[4] = me
	for r in board_rows.size():
		var row: Array = board_rows[r]
		row[0].visible = r < top.size()
		if r >= top.size():
			continue
		var p: Player = top[r]
		row[1].color = p.color
		row[2].text = "%d. %s" % [ranked.find(p) + 1, p.name]
		row[3].text = "%.1f%%" % world.pct(p)
		var c := Color("#1f5fd6") if p == me else INK
		row[2].label_settings.font_color = c


func _update_minimap() -> void:
	var n: int = world.N
	var lut := PackedByteArray()
	lut.resize(16 * 4)
	for p in world.players:
		if p:
			lut[p.id * 4] = int(p.color.r8)
			lut[p.id * 4 + 1] = int(p.color.g8)
			lut[p.id * 4 + 2] = int(p.color.b8)
			lut[p.id * 4 + 3] = 255
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var land: PackedByteArray = world.land
	var tr: PackedByteArray = world.trail
	for i in n * n:
		var id := land[i]
		if id == 0:
			id = tr[i]
		var o := i * 4
		if id:
			data[o] = lut[id * 4]
			data[o + 1] = lut[id * 4 + 1]
			data[o + 2] = lut[id * 4 + 2]
			data[o + 3] = 255
		elif world.wall[i] == 1:
			data[o] = 107
			data[o + 1] = 118
			data[o + 2] = 144
			data[o + 3] = 255
		elif world.wall[i] == 2:
			var sea: bool = world.map_id == "islands"
			data[o] = 124 if sea else 200
			data[o + 1] = 199 if sea else 207
			data[o + 2] = 232 if sea else 222
			data[o + 3] = 255 if sea else 120
		else:
			data[o] = 235
			data[o + 1] = 239
			data[o + 2] = 248
			data[o + 3] = 255
	mm_img.set_data(n, n, false, Image.FORMAT_RGBA8, data)
	mm_tex.update(mm_img)
	var me: Player = world.me
	mm_dot.visible = me.alive
	mm_dot.position = me.pos / n * minimap.size - mm_dot.size / 2


func _toast(text: String) -> void:
	toast_label.text = text
	toast_panel.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.3)


func _callout(text: String, color: Color) -> void:
	sfx.play("hype")
	callout_label.label_settings.font_color = color
	_pop(callout_label, text)


## Text that pops in big and fades out
func _pop(l: Label, text: String) -> void:
	l.text = text
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.4, 0.4)
	l.modulate.a = 1.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)


# ---------- UI building ----------

func _style(bg: Color, radius := 28, border_bottom := 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_width_bottom = border_bottom
	s.border_color = border
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 12
	s.content_margin_bottom = 12 + border_bottom
	s.anti_aliasing = true
	return s


func _label(text: String, size: int, color: Color = INK, outline := 0, outline_color: Color = INK, f: Font = null) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = f if f else font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = outline_color
	l.label_settings = ls
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, bg: Color, fg: Color, edge: Color, size := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_stylebox_override("normal", _style(bg, 26, 8, edge))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.06), 26, 8, edge))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.05), 26, 3, edge))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): sfx.play("tap"))
	return b


func _card(bg: Color = Color(1, 1, 1, 0.9)) -> PanelContainer:
	var c := PanelContainer.new()
	var s := _style(bg, 26)
	s.shadow_color = Color(0.08, 0.1, 0.2, 0.18)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	c.add_theme_stylebox_override("panel", s)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	ui_layer.add_child(c)
	return c


func _show(screen: Control) -> void:
	for s in [menu, pause_screen, over_screen]:
		if s != screen:
			s.visible = false
	if screen:
		screen.visible = true
		screen.modulate.a = 0.0
		create_tween().tween_property(screen, "modulate:a", 1.0, 0.25)
	hud.visible = state != "menu"


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var safe := _safe_margins()

	# ----- HUD -----
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	ui_layer.add_child(hud)

	var left := _card()
	hud.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	pct_label = _label("0.0%", 52)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.add_child(pct_label)
	goal_bar = Control.new()
	goal_bar.custom_minimum_size = Vector2(180, 12)
	goal_bar.draw.connect(func():
		var f: float = goal_bar.get_meta("fill", 0.0)
		goal_bar.draw_rect(Rect2(Vector2.ZERO, goal_bar.size), Color(0.12, 0.15, 0.27, 0.12))
		goal_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(goal_bar.size.x * f, goal_bar.size.y)), goal_bar.get_meta("color", Color.WHITE)))
	lv.add_child(goal_bar)
	status_label = _label("", 22, MUTED, 0, INK, font_med)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.add_child(status_label)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 6)
	var coin_icon := TextureRect.new()
	coin_icon.texture = Art.tex(Art.COIN, 64)
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_row.add_child(coin_icon)
	coin_label = _label("0", 24, Color("#b07800"))
	coin_row.add_child(coin_label)
	lv.add_child(coin_row)
	fx_row = HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 6)
	lv.add_child(fx_row)

	var right := _card()
	hud.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	for r in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_l := _label("", 22, INK, 0, INK, font_med)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.custom_minimum_size.x = 118
		var pct_l := _label("", 22, INK)
		pct_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct_l.custom_minimum_size.x = 66
		row.add_child(dot)
		row.add_child(name_l)
		row.add_child(pct_l)
		rv.add_child(row)
		board_rows.append([row, dot, name_l, pct_l])

	_pin(left, Control.PRESET_TOP_LEFT, safe)
	_pin(right, Control.PRESET_TOP_RIGHT, safe)

	var pause_btn := _button("II", Color(1, 1, 1, 0.9), INK, Color("#c7cfe0"), 30)
	pause_btn.custom_minimum_size = Vector2(76, 76)
	pause_btn.pressed.connect(_pause)
	hud.add_child(pause_btn)
	_pin(pause_btn, Control.PRESET_BOTTOM_RIGHT, safe)

	var mm_card := _card()
	hud.add_child(mm_card)
	mm_img = Image.create(world.N, world.N, false, Image.FORMAT_RGBA8)
	mm_tex = ImageTexture.create_from_image(mm_img)
	minimap = TextureRect.new()
	minimap.texture = mm_tex
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mm_card.add_child(minimap)
	mm_dot = Control.new()
	mm_dot.size = Vector2(12, 12)
	mm_dot.draw.connect(func():
		mm_dot.draw_circle(Vector2(6, 6), 6, INK, true, -1, true)
		mm_dot.draw_circle(Vector2(6, 6), 4, Color.WHITE, true, -1, true))
	minimap.add_child(mm_dot)
	_pin(mm_card, Control.PRESET_BOTTOM_LEFT, safe)

	# Messages pop up on a dark rounded label near the top
	var toast_row := HBoxContainer.new()
	toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_row.offset_top = 250 + safe.y
	hud.add_child(toast_row)
	toast_panel = PanelContainer.new()
	var ts := _style(Color(0.12, 0.15, 0.27, 0.78), 24)
	ts.content_margin_left = 24
	ts.content_margin_right = 24
	ts.content_margin_top = 8
	ts.content_margin_bottom = 10
	toast_panel.add_theme_stylebox_override("panel", ts)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0
	toast_row.add_child(toast_panel)
	toast_label = _label("", 28, Color.WHITE, 0, INK, font_med)
	toast_panel.add_child(toast_label)

	callout_label = _label("", 84, YELLOW, 18, INK)
	callout_label.set_anchors_preset(Control.PRESET_CENTER)
	callout_label.size = Vector2(900, 120)
	callout_label.position = -callout_label.size / 2 + Vector2(0, -160)
	callout_label.set_anchors_preset(Control.PRESET_CENTER, true)
	callout_label.modulate.a = 0
	hud.add_child(callout_label)

	count_label = _label("", 180, Color.WHITE, 24, INK)
	count_label.size = Vector2(500, 220)
	count_label.set_anchors_preset(Control.PRESET_CENTER)
	count_label.position = -count_label.size / 2 + Vector2(0, -120)
	count_label.set_anchors_preset(Control.PRESET_CENTER, true)
	count_label.modulate.a = 0
	hud.add_child(count_label)

	stick_view = Control.new()
	stick_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stick_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_view.draw.connect(_draw_stick)
	hud.add_child(stick_view)

	_build_menu(safe)
	_build_pause()
	_build_over()


## Puts a control in a corner of the screen, 16 units in (plus room for notches)
func _pin(c: Control, corner: int, safe: Vector4) -> void:
	c.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE, 16)
	var top := corner == Control.PRESET_TOP_LEFT or corner == Control.PRESET_TOP_RIGHT
	var left := corner == Control.PRESET_TOP_LEFT or corner == Control.PRESET_BOTTOM_LEFT
	var dy := safe.y if top else -safe.w
	var dx := safe.x if left else -safe.z
	c.offset_top += dy
	c.offset_bottom += dy
	c.offset_left += dx
	c.offset_right += dx


func _dim(screen: Control, top: Color, bottom: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(bg)


func _center_column(screen: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	return col


func _build_menu(safe: Vector4) -> void:
	menu = _screen()
	_dim(menu, Color(0.11, 0.14, 0.26, 0.15), Color(0.11, 0.14, 0.26, 0.8))
	var wallet_card := _card(Color(1, 1, 1, 0.92))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wicon := TextureRect.new()
	wicon.texture = Art.tex(Art.COIN, 64)
	wicon.custom_minimum_size = Vector2(32, 32)
	wicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wrow.add_child(wicon)
	wallet_label = _label("0", 30, Color("#b07800"))
	wrow.add_child(wallet_label)
	wallet_card.add_child(wrow)
	menu.add_child(wallet_card)
	_pin(wallet_card, Control.PRESET_TOP_RIGHT, safe)
	var col := _center_column(menu)
	# The title: every letter a player colour, bobbing gently
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 2)
	var word := "COLOR CLAIM"
	var title_size := int(clampf(get_viewport_rect().size.x / 7.6, 60, 110))
	for i in word.length():
		var ch := word[i]
		var l := _label(ch, title_size, world.COLORS[i % world.COLORS.size()] if ch != " " else Color.WHITE, 22, NAVY)
		l.custom_minimum_size.x = 26 if ch == " " else 0
		title.add_child(l)
		if ch != " ":
			var tw := l.create_tween().set_loops()
			tw.tween_interval(i * 0.08)
			tw.tween_property(l, "position:y", -10.0, 0.6).set_trans(Tween.TRANS_SINE)
			tw.tween_property(l, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	col.add_child(title)
	var tag := _label("Loop back to your land to claim it. Cut other trails, and protect yours!", 26, Color(1, 1, 1, 0.92), 0, INK, font_med)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 560
	col.add_child(tag)
	col.add_child(Control.new())
	var pick := _label("YOUR COLOUR", 22, Color(1, 1, 1, 0.75))
	col.add_child(pick)
	swatches = HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 12)
	col.add_child(swatches)
	for i in world.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			my_color = i
			_save()
			sfx.play("tap")
			_refresh_menu())
		swatches.add_child(b)
	col.add_child(_label("MAP", 22, Color(1, 1, 1, 0.75)))
	maps_row = HBoxContainer.new()
	maps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	maps_row.add_theme_constant_override("separation", 8)
	col.add_child(maps_row)
	for id in world.MAPS:
		var mb := Button.new()
		mb.text = world.MAPS[id]
		mb.focus_mode = Control.FOCUS_NONE
		mb.add_theme_font_override("font", font)
		mb.add_theme_font_size_override("font_size", 22)
		mb.pressed.connect(func():
			map_id = id
			_save()
			sfx.play("tap")
			_start_demo())
		maps_row.add_child(mb)
	col.add_child(Control.new())
	var play := _button("PLAY", YELLOW, Color("#5a3200"), Color("#d27a06"), 64)
	play.custom_minimum_size = Vector2(380, 120)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(start_game)
	col.add_child(play)
	var pulse := play.create_tween().set_loops()
	play.pivot_offset = Vector2(190, 60)
	pulse.tween_property(play, "scale", Vector2(1.04, 1.04), 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(play, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	best_label = _label("", 26, Color(1, 1, 1, 0.85), 0, INK, font_med)
	col.add_child(best_label)
	var toggles := HBoxContainer.new()
	toggles.alignment = BoxContainer.ALIGNMENT_CENTER
	toggles.add_theme_constant_override("separation", 12)
	col.add_child(toggles)
	sound_btn = _button("", Color(1, 1, 1, 0.16), Color.WHITE, Color(1, 1, 1, 0.1), 24)
	sound_btn.pressed.connect(func():
		sfx.muted = not sfx.muted
		_save()
		_refresh_menu())
	toggles.add_child(sound_btn)
	music_btn = _button("", Color(1, 1, 1, 0.16), Color.WHITE, Color(1, 1, 1, 0.1), 24)
	music_btn.pressed.connect(func():
		music.set_enabled(not music.enabled)
		_save()
		_refresh_menu())
	toggles.add_child(music_btn)
	var foot := _label("Steer by dragging anywhere · arrows or WASD on a keyboard", 20, Color(1, 1, 1, 0.6), 0, INK, font_med)
	col.add_child(foot)


func _refresh_menu() -> void:
	for i in swatches.get_child_count():
		var b: Button = swatches.get_child(i)
		var s := StyleBoxFlat.new()
		s.bg_color = world.COLORS[i]
		s.set_corner_radius_all(14)
		s.anti_aliasing = true
		if i == my_color:
			s.set_border_width_all(5)
			s.border_color = Color.WHITE
		else:
			s.border_width_bottom = 5
			s.border_color = world.COLORS[i].darkened(0.3)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, s)
	best_label.text = "Best: %.1f%%   ·   Wins: %d" % [best, wins] if games > 0 else "Claim 50% of the map to win"
	sound_btn.text = "Sound: off" if sfx.muted else "Sound: on"
	music_btn.text = "Music: on" if music.enabled else "Music: off"
	wallet_label.text = str(wallet)
	for mb in maps_row.get_children():
		var picked: bool = mb.text == world.MAPS[map_id]
		var st := _style(Color.WHITE if picked else Color(1, 1, 1, 0.16), 18)
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		for k in ["normal", "hover", "pressed"]:
			mb.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			mb.add_theme_color_override(k, INK if picked else Color.WHITE)


func _build_pause() -> void:
	pause_screen = _screen()
	_dim(pause_screen, Color(0.11, 0.14, 0.26, 0.55), Color(0.11, 0.14, 0.26, 0.8))
	var col := _center_column(pause_screen)
	col.add_child(_label("Paused", 72, Color.WHITE, 16, NAVY))
	var resume := _button("Resume", YELLOW, Color("#5a3200"), Color("#d27a06"), 44)
	resume.custom_minimum_size = Vector2(340, 100)
	resume.pressed.connect(_resume)
	col.add_child(resume)
	var quit := _button("Quit to menu", Color(1, 1, 1, 0.92), INK, Color("#c7cfe0"), 32)
	quit.custom_minimum_size = Vector2(340, 84)
	quit.pressed.connect(_to_menu)
	col.add_child(quit)


func _build_over() -> void:
	over_screen = _screen()
	_dim(over_screen, Color(0.11, 0.14, 0.26, 0.45), Color(0.11, 0.14, 0.26, 0.85))
	var col := _center_column(over_screen)
	over_title = _label("", 86, Color.WHITE, 18, NAVY)
	col.add_child(over_title)
	over_reason = _label("", 30, Color.WHITE, 0, INK, font_med)
	over_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_reason.custom_minimum_size.x = 600
	col.add_child(over_reason)
	over_stats = _label("", 26, Color(1, 1, 1, 0.85), 0, INK, font_med)
	col.add_child(over_stats)
	over_best = _label("", 30, YELLOW)
	col.add_child(over_best)
	over_coins = _label("", 34, Color("#ffd23f"), 10, Color("#6b4a00"))
	col.add_child(over_coins)
	col.add_child(Control.new())
	var again := _button("Play again", YELLOW, Color("#5a3200"), Color("#d27a06"), 46)
	again.custom_minimum_size = Vector2(380, 104)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(start_game)
	col.add_child(again)
	var menu_btn := _button("Menu", Color(1, 1, 1, 0.92), INK, Color("#c7cfe0"), 32)
	menu_btn.custom_minimum_size = Vector2(380, 84)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_btn.pressed.connect(_to_menu)
	col.add_child(menu_btn)


## Space taken by notches and rounded corners, in UI units: (left, top, right, bottom)
func _safe_margins() -> Vector4:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	# Only phones and tablets have notches (and there the game fills the screen)
	if not OS.has_feature("mobile") or win.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var k := get_viewport_rect().size.x / win.x
	return Vector4(maxf(0, safe.position.x) * k, maxf(0, safe.position.y) * k, maxf(0, win.x - safe.end.x) * k, maxf(0, win.y - safe.end.y) * k)


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ---------- Saving ----------

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	best = c.get_value("stats", "best", 0.0)
	games = c.get_value("stats", "games", 0)
	wins = c.get_value("stats", "wins", 0)
	my_color = clampi(c.get_value("player", "color", 0), 0, 7)
	wallet = c.get_value("player", "coins", 0)
	map_id = c.get_value("player", "map", "square")
	set_meta("music", c.get_value("settings", "music", true))
	set_meta("muted", c.get_value("settings", "muted", false))


func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("stats", "best", best)
	c.set_value("stats", "games", games)
	c.set_value("stats", "wins", wins)
	c.set_value("player", "color", my_color)
	c.set_value("player", "coins", wallet)
	c.set_value("player", "map", map_id)
	c.set_value("settings", "music", music.enabled)
	c.set_value("settings", "muted", sfx.muted)
	c.save(SAVE_PATH)
