class_name UI
extends Control
## The HUD and every screen, built in code in the same light sky-blue cartoon style as the
## web version: rounded panels with a dark blue outline, yellow and blue buttons, ribbon titles.

const INK := Color("#2160b8")
const PANEL := Color("#3fa2ff")
const PANEL_LIGHT := Color("#6cc4ff")
const YELLOW := Color("#ffc928")
const YELLOW_DARK := Color("#e09a00")
const RED := Color("#ff5a5f")
const GREEN := Color("#4cc94a")
const ORANGE := Color("#ff8a3d")
const WHITE := Color.WHITE

var main
var font_b: Font
var font_m: Font
var screens := {}
var hud: Control
var level_label: Label
var time_label: Label
var power_bar: HBoxContainer
var speed_btn: Button
var abilities: HBoxContainer
var ability_btns := {}
var toast_panel: PanelContainer
var toast_label: Label
var hint_panel: PanelContainer
var hint_label: Label
var _toast_tween: Tween
var _hud_t := 0.0
var _anim_t := 0.0
var title_labels: Array[Label] = []

# Screen parts that change
var menu_coins: Label
var play_btn: Button
var sound_btns: Array[Button] = []
var music_btns: Array[Button] = []
var level_grid: GridContainer
var levels_stars: Label
var shop_list: VBoxContainer
var shop_coins: Label
var win_stars: Array[Label] = []
var win_stats: HBoxContainer
var win_coins: Label
var win_unlock: Label
var next_btn: Button
var ad_btn: Button
var win_ribbon: Control
var lose_ribbon: Control
var _win_coins := 0
var lose_tip: Label
var vibrate_btn: Button
var cutscenes_btn: Button
var gfx_btns := {}
var lang_btns := {}
var missions_btn: Button
var daily_btn: Button
var reward_days: HBoxContainer
var reward_title: Label
var reward_btn: Button
var mission_list: VBoxContainer
var mission_streak: Label
var looks_lists := {}
var looks_coins: Label
var look_pics := {}           # "hat:crown" -> a picture of it (made the first time Looks opens)
var _making_pics := false
var safe_top := 0.0               # a camera notch or rounded corners (see main.safe_insets)
var safe_bottom := 0.0


func build() -> void:
	# A Control inside a CanvasLayer doesn't size itself, so follow the window
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	font_b = _font("res://assets/fonts/Fredoka-Bold.ttf")
	font_m = _font("res://assets/fonts/Fredoka-Medium.ttf")
	I18n.add_fallbacks(font_b, font_m)
	theme = _make_theme()
	_build_hud()
	_build_menu()
	_build_levels()
	_build_shop()
	_build_help()
	_build_settings()
	_build_reward()
	_build_missions()
	_build_looks()
	_build_paused()
	_build_win()
	_build_lose()
	_build_toast()
	for id in screens:
		_let_drags_scroll(screens[id])
	get_tree().node_added.connect(func(n: Node):
		if n is Control and _on_a_screen(n):
			_let_drags_scroll(n))


func _process(dt: float) -> void:
	if main == null or main.screen_open != "menu":
		return
	# On the menu the title bobs and tilts, and PLAY gently breathes
	var t := Time.get_ticks_msec() / 1000.0
	for i in title_labels.size():
		var l := title_labels[i]
		l.pivot_offset = l.size / 2
		l.rotation = sin(t * 1.3 + i * 1.7) * 0.03
		l.scale = Vector2.ONE * (1.0 + 0.025 * sin(t * 2.0 + i))
	if play_btn.get_draw_mode() != BaseButton.DRAW_PRESSED:
		play_btn.scale = Vector2.ONE * (1.0 + 0.03 * sin(t * 3.2))


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


## Keep the HUD and the screens clear of a camera notch and the phone's rounded corners
func fit_safe(top: float, bottom: float) -> void:
	safe_top = top
	safe_bottom = bottom
	var bar: Control = hud.get_child(0)
	bar.offset_top = 14 + top
	abilities.offset_bottom = -18 - bottom
	abilities.offset_top = -122 - bottom
	hint_panel.offset_bottom = -150 - bottom
	hint_panel.offset_top = -230 - bottom
	toast_panel.offset_top = 104 + top
	for id in screens:
		var scroll: Control = screens[id].get_child(1)
		scroll.offset_top = top
		scroll.offset_bottom = -bottom


func _font(path: String) -> Font:
	var f: FontFile = load(path)
	# Emoji and symbols like ★ come with the game: newer Android phones keep their emoji in a
	# format Godot can't draw, so the phone's own fonts are only the last resort
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["sans-serif"])
	f.fallbacks = [load("res://assets/fonts/Emoji.ttf"), load("res://assets/fonts/Symbols.ttf"), sys]
	return f


# ---------- Style ----------
## A plain rounded box (rows, cards, badges): a thin outline in a darker shade of its colour
## (or the one given) and a soft shadow under it
func box(bg: Color, border := INK, radius := 18, width := 3, shadow := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bg.darkened(0.32) if border == INK else border
	s.set_border_width_all(mini(width, 2) if border == INK else width)
	s.border_width_bottom = s.border_width_top + (2 if shadow > 0 else 0)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0.04, 0.1, 0.28, 0.25 if shadow > 0 else 0.0)
	s.shadow_offset = Vector2(0, mini(shadow, 3))
	s.shadow_size = 4 if shadow > 0 else 0
	s.anti_aliasing = true
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 10
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_b
	t.default_font_size = 26
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 7)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 7)
	_button_style(t, "Button", "blue")
	t.set_stylebox("normal", "LineEdit", box(WHITE, INK, 14, 3, 0))
	t.set_stylebox("focus", "LineEdit", box(WHITE, INK, 14, 3, 0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	t.set_font_size("font_size", "LineEdit", 26)
	return t


func _button_style(t: Theme, type: String, color: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, type, UISkin.button(color, state))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_outline_color", type, Color(UISkin.COLORS[color].text))


func button(text: String, kind := "blue", size := 26, on_press := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	set_kind(b, kind)
	if on_press.is_valid():
		b.pressed.connect(func():
			main.play_sound("tap")
			on_press.call())
	squishy(b)
	return b


## A button's colour (UISkin.COLORS): its glossy look in every state and its text outline
func set_kind(b: Button, kind: String) -> void:
	if not UISkin.COLORS.has(kind):
		kind = "blue"
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, UISkin.button(kind, state))
	b.add_theme_color_override("font_outline_color", Color(UISkin.COLORS[kind].text))
	if kind == "white":
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_constant_override("outline_size", 0)
	b.set_meta("kind", kind)


## Pressing squashes a control a little; letting go springs it back
func squishy(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size / 2)
	if c is BaseButton:
		c.button_down.connect(func():
			var tw := c.create_tween()
			tw.tween_property(c, "scale", Vector2(0.92, 0.92), 0.06))
		c.button_up.connect(func():
			var tw := c.create_tween()
			tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func label(text: String, size := 26, color := WHITE, outline := 8, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	if font:
		l.add_theme_font_override("font", font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Let a label wrap its words within this width
func wrapped(l: Label, width: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


## A screen's title on a glossy banner. color: one of UISkin.COLORS, or one of the UI colours
func ribbon(text: String, color: Variant = "orange") -> Control:
	if color is Color:
		color = {ORANGE: "orange", GREEN: "green", RED: "red", YELLOW: "yellow"}.get(color, "purple")
	var p := PanelContainer.new()
	var sb: StyleBoxTexture = UISkin.button(color).duplicate()
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, 46)
	l.add_theme_color_override("font_outline_color", Color(UISkin.COLORS[color].text))
	p.add_child(l)
	p.rotation_degrees = -1.5
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p


func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UISkin.panel())
	p.custom_minimum_size.x = 600
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# A finger dragging on a panel scrolls the screen (a panel would stop the drag otherwise)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func vbox(gap := 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	return v


func hbox(gap := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	return h


## A full-screen page: a soft blue backdrop and a centered column
func screen(id: String, backdrop := Color(0.43, 0.75, 1.0, 0.55)) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	# Tapping outside a text box closes the phone's keyboard (and saves what was typed)
	root.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			root.get_viewport().gui_release_focus())
	var bg := ColorRect.new()
	bg.color = backdrop
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := vbox(18)
	col.custom_minimum_size.x = 640
	center.add_child(col)
	var margin := Control.new()
	margin.custom_minimum_size.y = 24
	col.add_child(margin)
	add_child(root)
	screens[id] = root
	return col


## Buttons and panels on a screen let a finger drag scroll it (by default they'd catch the
## drag). Taps still press buttons, and a drag that scrolls doesn't press anything.
func _let_drags_scroll(n: Node) -> void:
	if n is Control and n.mouse_filter == Control.MOUSE_FILTER_STOP and _on_a_screen(n) \
			and not (n is LineEdit or n is TextEdit or n is ScrollContainer or n is ScrollBar or n is Slider):
		n.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in n.get_children():
		_let_drags_scroll(c)


## Inside a screen's scrolling part (where the scroll container stops a drag going further)
func _on_a_screen(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != self:
		if p is ScrollContainer and p.get_parent() in screens.values():
			return true
		p = p.get_parent()
	return false


## A screen appearing: it fades in and its content springs up from a little smaller
func _pop_in(root: Control) -> void:
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	var scroll: Control = root.get_child(1)
	scroll.pivot_offset = scroll.size / 2
	scroll.scale = Vector2(0.93, 0.93)
	var tw2 := scroll.create_tween()
	tw2.tween_property(scroll, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A control popping in: it grows from small with a little overshoot
func pop(c: Control, delay := 0.0, from := 0.4) -> void:
	c.scale = Vector2.ONE * from
	c.modulate.a = 0.0
	# Its size is only known once the screen has been laid out
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func back_button(to := "menu") -> Button:
	return button("Back", "blue", 26, func(): main.open_menu() if to == "menu" else show_screen(to))


func show_screen(id: String) -> void:
	var was: String = main.screen_open
	for k in screens:
		screens[k].visible = k == id
	main.screen_open = id
	if id != "" and id != was:
		_pop_in(screens[id])
	match id:
		"menu":
			refresh_menu()
		"levels":
			refresh_levels()
		"shop":
			refresh_shop()
		"paused", "settings":
			refresh_toggles()
		"reward":
			refresh_reward()
		"missions":
			refresh_missions()
		"looks":
			refresh_looks()


# ---------- HUD ----------
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	add_child(hud)
	var bar := hbox(10)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 14
	bar.offset_left = 14
	bar.offset_right = -14
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)
	var pause_btn := button("II", "blue", 28, func(): main.pause())
	pause_btn.custom_minimum_size = Vector2(64, 64)
	bar.add_child(pause_btn)
	level_label = _pill("Level 1")
	bar.add_child(level_label.get_parent())
	var bar_frame := PanelContainer.new()
	var fs := box(Color(1, 1, 1, 0.85), INK, 16, 3, 0)
	fs.set_content_margin_all(0)
	bar_frame.add_theme_stylebox_override("panel", fs)
	bar_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_frame.custom_minimum_size.y = 34
	bar_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	bar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_bar = HBoxContainer.new()
	power_bar.add_theme_constant_override("separation", 0)
	power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_frame.add_child(power_bar)
	bar.add_child(bar_frame)
	time_label = _pill("0:00")
	bar.add_child(time_label.get_parent())
	speed_btn = button("1×", "blue", 26, func(): main.toggle_speed())
	speed_btn.custom_minimum_size = Vector2(64, 64)
	bar.add_child(speed_btn)
	abilities = hbox(22)
	abilities.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	abilities.offset_bottom = -18
	abilities.offset_top = -122
	abilities.grow_horizontal = Control.GROW_DIRECTION_BOTH
	abilities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(abilities)
	for id in ["strike", "rally"]:
		var b := button("✈" if id == "strike" else "📯", "blue", 40, func(): main.use_ability(id))
		b.custom_minimum_size = Vector2(100, 100)
		b.add_theme_constant_override("content_margin_bottom", 22)
		var cap := label("Airstrike" if id == "strike" else "Rally", 16)
		cap.position = Vector2(0, 74)
		cap.size = Vector2(100, 24)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		var badge := label("1", 20)
		var bp := PanelContainer.new()
		var bs := box(RED, INK, 16, 3, 0)
		bs.set_content_margin_all(0)
		bp.add_theme_stylebox_override("panel", bs)
		bp.custom_minimum_size = Vector2(36, 36)
		bp.add_child(badge)
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bp.position = Vector2(76, -14)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bp)
		abilities.add_child(b)
		ability_btns[id] = {"btn": b, "count": badge}
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", box(WHITE, INK, 18, 3, 4))
	hint_label = wrapped(label("", 22, INK, 0), 560)
	hint_panel.add_child(hint_label)
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.offset_bottom = -150
	hint_panel.offset_top = -230
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.visible = false
	hud.add_child(hint_panel)


func _pill(text: String) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UISkin.pill("blue"))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, 26)
	p.add_child(l)
	return l


func start_hud(title: String, campaign: bool) -> void:
	hud.visible = true
	# The bars slide in from the edges
	hud.modulate.a = 0.0
	var tw := hud.create_tween()
	tw.tween_property(hud, "modulate:a", 1.0, 0.25)
	for c: Control in [hud.get_child(0), abilities]:
		# Where its anchors put it (not where a slide that was cut short left it)
		var y := c.anchor_top * hud.size.y + c.offset_top
		c.position.y = y + (-90.0 if c != abilities else 140.0)
		var t2 := c.create_tween()
		t2.tween_property(c, "position:y", y, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	level_label.text = title
	abilities.visible = campaign
	speed_btn.visible = campaign
	for c in power_bar.get_children():
		c.queue_free()
	power_bar.set_meta("sides", "")
	refresh_abilities()
	refresh_speed()


func hide_hud() -> void:
	hud.visible = false


func update_hud() -> void:
	var dt := get_process_delta_time()
	# Every frame: the strength bar glides to its new sizes, and ready abilities pulse
	for r in power_bar.get_children():
		if r.has_meta("want"):
			r.size_flags_stretch_ratio = lerpf(r.size_flags_stretch_ratio, r.get_meta("want"), minf(1.0, dt * 6))
	_anim_t += dt
	for id in ability_btns:
		var b: Button = ability_btns[id].btn
		b.pivot_offset = b.size / 2
		b.scale = Vector2.ONE * (1.0 + 0.045 * sin(_anim_t * 5.0)) if b.visible and not b.disabled and main.armed != id else Vector2.ONE
	_hud_t -= dt
	if _hud_t > 0:
		return
	_hud_t = 0.15
	var b: Battle = main.battle
	var tot := b.totals()
	var sum := 0.0
	for v in tot:
		sum += v
	sum = maxf(sum, 1)
	var present := [1]
	if main.mode == "campaign":
		for a in b.ai_sides:
			if a.side != 1:
				present.append(a.side)
	else:
		present.append(2)
	present.append(0)
	if power_bar.get_meta("sides", "") != str(present):
		power_bar.set_meta("sides", str(present))
		for c in power_bar.get_children():
			c.queue_free()
		for sd in present:
			var r := Panel.new()
			var s := StyleBoxFlat.new()
			s.bg_color = main.SIDES[sd].color
			r.add_theme_stylebox_override("panel", s)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.set_meta("side", sd)
			var l := label("", 18, WHITE, 5)
			l.set_anchors_preset(Control.PRESET_FULL_RECT)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.add_child(l)
			power_bar.add_child(r)
	for r in power_bar.get_children():
		if r.is_queued_for_deletion():
			continue
		var sd: int = r.get_meta("side")
		r.set_meta("want", maxf(0.001, tot[sd] / sum))
		r.get_child(0).text = str(floori(tot[sd])) if sd != 0 and tot[sd] / sum > 0.12 else ""
	var t: float = b.time if main.mode == "campaign" else maxf(0, Net.PVP_TIME - b.time)
	time_label.text = "%d:%02d" % [floori(t / 60), floori(fmod(t, 60))]
	time_label.add_theme_color_override("font_color", Color("#fff3a0") if main.mode != "campaign" and t < 20 else WHITE)
	refresh_abilities()


func refresh_abilities() -> void:
	for id in ability_btns:
		var a: Dictionary = ability_btns[id]
		var unlocked: bool = main.level >= (3 if id == "strike" else 6)
		a.btn.visible = unlocked or main.charges[id] > 0
		a.count.text = str(main.charges[id])
		a.btn.disabled = main.state != "play" or (main.charges[id] <= 0 and main.armed != id) or (id == "rally" and main.battle.rally > 0)
		a.btn.modulate = Color(1, 0.75, 0.75) if main.armed == id else Color.WHITE


func refresh_speed() -> void:
	speed_btn.text = "%d×" % main.speed


func set_hint(text: String) -> void:
	hint_label.text = text
	hint_panel.visible = text != ""


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", box(PANEL, INK, 18, 3, 4))
	toast_label = wrapped(label("", 22), 560)
	toast_panel.add_child(toast_label)
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.offset_top = 104
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0
	add_child(toast_panel)


func toast(text: String, seconds := 2.2) -> void:
	toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	toast_panel.offset_top = 70 + safe_top
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.parallel().tween_property(toast_panel, "offset_top", 104.0 + safe_top, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.3)


# ---------- Menu ----------
var menu_badges := {}            # tile id -> its little red badge (Label inside a panel)


func _build_menu() -> void:
	var col := screen("menu", Color(0.1, 0.25, 0.55, 0.18))
	var coins_row := hbox()
	coins_row.alignment = BoxContainer.ALIGNMENT_END
	menu_coins = _pill("0")
	menu_coins.add_theme_font_size_override("font_size", 30)
	coins_row.add_child(menu_coins.get_parent())
	col.add_child(coins_row)
	# The title: big, chunky letters with a deep outline and a drop shadow
	var title := vbox(0)
	for part in [["TOWER", YELLOW, Color("#b35a00")], ["SIEGE", Color("#ff6fb5"), Color("#8a1f5a")]]:
		var t := label(part[0], 128, part[1], 22)
		t.add_theme_color_override("font_outline_color", part[2])
		t.add_theme_color_override("font_shadow_color", Color(0.05, 0.1, 0.3, 0.45))
		t.add_theme_constant_override("shadow_offset_y", 9)
		t.add_theme_constant_override("shadow_outline_size", 22)
		t.add_theme_constant_override("line_spacing", -34)
		title_labels.append(t)
		title.add_child(t)
	col.add_child(title)
	col.add_child(spacer(18))
	play_btn = button("PLAY", "yellow", 54, func(): main.start_level(mini(main.save.level, Levels.LAST_LEVEL)))
	play_btn.custom_minimum_size = Vector2(470, 124)
	play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(play_btn)
	var pvp := button("⚔ PvP", "red", 40, func(): main.net.open_pvp())
	pvp.custom_minimum_size = Vector2(470, 92)
	pvp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(pvp)
	col.add_child(spacer(6))
	# Everything else: a grid of picture tiles
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	daily_btn = tile("daily", "📅", "Daily", "green", func(): main.start_daily())
	missions_btn = tile("missions", "🎁", "Missions", "orange", func(): show_screen("missions"))
	for b in [daily_btn, missions_btn,
			tile("looks", "🎨", "Looks", "purple", func(): show_screen("looks")),
			tile("levels", "🗺", "Levels", "blue", func(): show_screen("levels")),
			tile("shop", "🔨", "Upgrades", "blue", func(): show_screen("shop")),
			tile("board", "🏆", "Leaderboard", "blue", func(): main.net.open_board()),
			tile("clans", "🛡", "Clans", "blue", func(): main.net.open_clans()),
			tile("settings", "⚙", "Settings", "white", func(): show_screen("settings")),
			tile("help", "❓", "How to play", "white", func(): show_screen("help"))]:
		grid.add_child(b)
	col.add_child(grid)


## A menu tile: a big picture over its name, and a little red badge for news (hidden)
func tile(id: String, icon: String, text: String, kind: String, on_press: Callable) -> Button:
	var b := button(text, kind, 21, on_press)
	b.custom_minimum_size = Vector2(196, 132)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_BOTTOM
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxTexture = (b.get_theme_stylebox(state) as StyleBoxTexture).duplicate()
		sb.content_margin_top += 58
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)
	var pic := label(icon, 50, INK if kind == "white" else WHITE, 0)
	pic.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pic.offset_top = 8
	pic.offset_bottom = 72
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_child(pic)
	# Keep the picture with the face when the button is pressed down
	b.button_down.connect(func(): pic.offset_top = 13)
	b.button_up.connect(func(): pic.offset_top = 8)
	var dot := PanelContainer.new()
	var ds := box(RED, Color.WHITE, 18, 3, 3)
	ds.set_content_margin_all(0)
	ds.content_margin_left = 8
	ds.content_margin_right = 8
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(38, 38)
	dot.position = Vector2(166, -12)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := label("", 20, WHITE, 5)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_child(n)
	dot.visible = false
	b.add_child(dot)
	menu_badges[id] = n
	return b


## A tile's badge: a number or a tick, or "" to hide it
func set_badge(id: String, text: String) -> void:
	var n: Label = menu_badges.get(id)
	if n:
		n.text = text
		n.get_parent().visible = text != ""


func _toggles() -> HBoxContainer:
	var row := hbox()
	var s := button("Sound", "blue", 22, func(): main.toggle_sound())
	var m := button("Music", "blue", 22, func(): main.toggle_music())
	sound_btns.append(s)
	music_btns.append(m)
	row.add_child(s)
	row.add_child(m)
	return row


func refresh_toggles() -> void:
	for b in sound_btns:
		b.text = "Sound: off" if main.save.muted else "Sound: on"
	for b in music_btns:
		b.text = "Music: off" if not main.save.music or main.save.muted else "Music: on"
	if vibrate_btn:
		vibrate_btn.text = "Vibration: on" if main.save.vibrate else "Vibration: off"
		cutscenes_btn.text = "Story scenes: on" if main.save.cutscenes else "Story scenes: off"
		for g in gfx_btns:
			var on: bool = main.save.gfx == g
			set_kind(gfx_btns[g], "yellow" if on else "blue")
		for code in lang_btns:
			var on: bool = main.save.lang == code
			set_kind(lang_btns[code], "yellow" if on else "blue")


# ---------- Daily reward ----------
func _build_reward() -> void:
	var col := screen("reward")
	var p := panel()
	var v := vbox(18)
	p.add_child(v)
	v.add_child(ribbon("Daily reward", GREEN))
	reward_title = label("", 28)
	v.add_child(reward_title)
	reward_days = hbox(6)
	v.add_child(reward_days)
	v.add_child(wrapped(label("Come back every day: the reward grows for 7 days in a row.", 20, WHITE, 4, font_m), 540))
	reward_btn = button("Collect", "yellow", 40, func():
		var coins := Progress.claim_reward(main.save)
		main.write_save()
		if coins > 0:
			main.play_sound("coin")
			main.vibrate(40)
			toast(tr("+%d coins!") % coins)
		main.open_menu())
	reward_btn.custom_minimum_size = Vector2(360, 86)
	reward_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(reward_btn)
	col.add_child(p)


func refresh_reward() -> void:
	var next := Progress.streak_next(main.save)
	var ready := Progress.reward_ready(main.save)
	reward_title.text = (tr("Day %d") % next) if ready else "Collected today. See you tomorrow!"
	for c in reward_days.get_children():
		c.queue_free()
	var got := next - 1 if ready else int(main.save.streak.count)
	for i in Progress.STREAK_COINS.size():
		var today_box: bool = ready and i == next - 1
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", box(YELLOW if today_box else GREEN if i < got else PANEL_LIGHT, INK, 14, 3, 3))
		pc.custom_minimum_size = Vector2(74, 92)
		var vv := vbox(0)
		vv.add_child(label(tr("Day %d") % (i + 1), 15, WHITE, 4))
		vv.add_child(label("✓" if i < got else "🪙", 26, WHITE, 6))
		vv.add_child(label(str(Progress.STREAK_COINS[i]), 18, WHITE, 5))
		pc.add_child(vv)
		reward_days.add_child(pc)
	reward_btn.text = tr("Collect %d") % Progress.STREAK_COINS[next - 1] if ready else "Back"


# ---------- Missions ----------
func _build_missions() -> void:
	var col := screen("missions")
	col.add_child(ribbon("Missions"))
	mission_streak = wrapped(label("", 22, WHITE, 5, font_m), 600)
	col.add_child(mission_streak)
	mission_list = vbox(12)
	col.add_child(mission_list)
	col.add_child(wrapped(label("New missions every day. They're the same for everyone.", 18, WHITE, 4, font_m), 600))
	col.add_child(back_button())


func refresh_missions() -> void:
	for c in mission_list.get_children():
		c.queue_free()
	if Progress.reward_ready(main.save):
		var rb := button(tr("🎁 Collect your daily reward (day %d)") % Progress.streak_next(main.save), "yellow", 24, func(): show_screen("reward"))
		mission_list.add_child(rb)
	mission_streak.text = "Daily reward streak: 1 day" if int(main.save.streak.count) == 1 else tr("Daily reward streak: %d days") % int(main.save.streak.count)
	var list := Progress.missions(main.save)
	for i in list.size():
		var m: Dictionary = list[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", box(PANEL, INK, 20, 3, 4))
		row.custom_minimum_size.x = 620
		var h := hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		var info := vbox(6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := wrapped(label(Progress.mission_text(m), 24), 400)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = int(m.goal)
		bar.value = int(m.have)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(380, 22)
		bar.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.3), INK, 10, 2, 0))
		var fill := box(YELLOW, INK, 10, 2, 0)
		bar.add_theme_stylebox_override("fill", fill)
		info.add_child(bar)
		var count := label("%d / %d" % [int(m.have), int(m.goal)], 18, WHITE, 4)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(count)
		h.add_child(info)
		var done: bool = int(m.have) >= int(m.goal)
		var idx := i
		var b := button("✓" if m.claimed else "🪙 %d" % int(m.coins), "green" if done and not m.claimed else "blue", 24, func():
			var coins := Progress.claim_mission(main.save, idx)
			if coins > 0:
				main.write_save()
				main.play_sound("coin")
				toast(tr("+%d coins!") % coins)
			refresh_missions())
		b.disabled = not done or m.claimed
		b.custom_minimum_size.x = 130
		h.add_child(b)
		row.add_child(h)
		mission_list.add_child(row)


# ---------- Looks ----------
func _build_looks() -> void:
	var col := screen("looks")
	col.add_child(ribbon("Looks"))
	looks_coins = label("", 32)
	col.add_child(looks_coins)
	for kind in ["hat", "flag"]:
		var p := panel()
		var v := vbox(12)
		p.add_child(v)
		v.add_child(label("Your soldiers' hats" if kind == "hat" else "Your buildings' flags", 28))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		v.add_child(grid)
		looks_lists[kind] = grid
		col.add_child(p)
	col.add_child(back_button())


func _make_pics() -> void:
	_making_pics = true
	var items := []
	for kind in ["hat", "flag"]:
		for item in Progress.catalog(kind):
			items.append([kind, item.id])
	look_pics = await main.world.make_previews(items)
	if main.screen_open == "looks" and not look_pics.is_empty():
		refresh_looks()


func refresh_looks() -> void:
	if not _making_pics:
		_make_pics()
	looks_coins.text = "🪙 %d" % main.save.coins
	for kind in looks_lists:
		var grid: GridContainer = looks_lists[kind]
		for c in grid.get_children():
			c.queue_free()
		for item in Progress.catalog(kind):
			var owned := Progress.owns(main.save, item.id)
			var worn: bool = main.save.looks[kind] == item.id
			var state: String = ("Wearing" if worn else "Wear") if kind == "hat" else ("Flying" if worn else "Fly")
			var b := button("", "yellow" if worn else "blue", 20)
			b.custom_minimum_size = Vector2(176, 176)
			var card := vbox(0)
			card.set_anchors_preset(Control.PRESET_FULL_RECT)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pic: Texture2D = look_pics.get("%s:%s" % [kind, item.id])
			if pic:
				var tr := TextureRect.new()
				tr.texture = pic
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = Vector2(100, 100)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(tr)
			else:
				card.add_child(label(item.icon, 52, WHITE, 0))
			card.add_child(label(item.name, 22))
			card.add_child(label(state if owned else "🪙 %d" % item.cost, 20, WHITE, 6))
			for c in card.get_children():
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(card)
			b.disabled = not owned and int(main.save.coins) < int(item.cost)
			var id: String = item.id
			var k: String = kind
			b.pressed.connect(func():
				if Progress.pick_look(main.save, k, id) == "":
					main.write_save()
					main.world.set_look(main.save.looks.hat, main.save.looks.flag)
					main.play_sound("coin" if not owned else "tap")
				refresh_looks())
			grid.add_child(b)


# ---------- Settings ----------
func _build_settings() -> void:
	var col := screen("settings")
	col.add_child(ribbon("Settings"))
	var p := panel()
	var v := vbox(18)
	p.add_child(v)
	v.add_child(_toggles())
	vibrate_btn = button("Vibration: on", "blue", 22, func():
		main.save.vibrate = not main.save.vibrate
		main.write_save()
		main.vibrate(40)
		refresh_toggles())
	var row2 := hbox(10)
	row2.add_child(vibrate_btn)
	cutscenes_btn = button("Story scenes: on", "blue", 22, func():
		main.save.cutscenes = not main.save.cutscenes
		main.write_save()
		refresh_toggles())
	row2.add_child(cutscenes_btn)
	v.add_child(row2)
	var watch := button("🎬 Watch the story again", "blue", 22, func(): main.watch_story())
	watch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(watch)
	v.add_child(label("Graphics", 28))
	var row := hbox(8)
	for g in ["auto", "low", "medium", "high"]:
		var b := button(g.capitalize(), "blue", 22, func():
			main.set_gfx(g)
			refresh_toggles())
		b.custom_minimum_size.x = 128
		gfx_btns[g] = b
		row.add_child(b)
	v.add_child(row)
	v.add_child(wrapped(label("Auto starts at Medium and lowers the graphics by itself if the game runs slowly. Low is easiest on older phones and the battery.", 18, WHITE, 4, font_m), 540))
	v.add_child(label("Language", 28))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for code in I18n.LANGS:
		var b := button(I18n.LANGS[code], "blue", 18, func():
			main.set_lang(code)
			refresh_toggles())
		b.custom_minimum_size.x = 128
		# Language names are shown in their own language
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if code != "" else Node.AUTO_TRANSLATE_MODE_INHERIT
		lang_btns[code] = b
		grid.add_child(b)
	v.add_child(grid)
	col.add_child(p)
	col.add_child(back_button())


func refresh_menu() -> void:
	menu_coins.text = "🪙 %d" % main.save.coins
	play_btn.text = tr("PLAY  ·  Level %d") % mini(main.save.level, Levels.LAST_LEVEL)
	var n := Progress.claimable(main.save) + (1 if Progress.reward_ready(main.save) else 0)
	set_badge("missions", str(n) if n > 0 else "")
	set_badge("daily", "✓" if int(main.save.daily_won) == Progress.today() else "")
	refresh_toggles()


# ---------- Levels ----------
func _build_levels() -> void:
	var col := screen("levels")
	col.add_child(ribbon("Levels"))
	levels_stars = label("", 24)
	col.add_child(levels_stars)
	var p := panel()
	level_grid = GridContainer.new()
	level_grid.columns = 6
	level_grid.add_theme_constant_override("h_separation", 10)
	level_grid.add_theme_constant_override("v_separation", 10)
	p.add_child(level_grid)
	col.add_child(p)
	col.add_child(back_button())


func refresh_levels() -> void:
	for c in level_grid.get_children():
		c.queue_free()
	var total := 0
	var kinds := {"grass": "green", "desert": "orange", "snow": "blue", "beach": "purple"}
	# The 60 levels, then the endless levels reached so far (in full rows)
	var shown := maxi(Levels.MAX_LEVEL, ceili((int(main.save.level) + 1) / 6.0) * 6)
	for n in range(1, mini(shown, Levels.LAST_LEVEL) + 1):
		var st := int(main.save.stars.get(str(n), 0))
		total += st
		var locked: bool = n > main.save.level
		var b := button("%d\n%s" % [n, "🔒" if locked else "★".repeat(st) + "☆".repeat(3 - st)], "blue", 22)
		b.custom_minimum_size = Vector2(84, 84)
		set_kind(b, "yellow" if n == main.save.level else "red" if Levels.is_boss(n) else kinds[Levels.theme_for(n)])
		b.disabled = locked
		var level_n := n
		b.pressed.connect(func(): main.start_level(level_n))
		level_grid.add_child(b)
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(minf(0.6, n * 0.012))
		tw.tween_property(b, "modulate:a", 1.0, 0.15)
	levels_stars.text = tr("%d ★ collected") % total


# ---------- Upgrades ----------
func _build_shop() -> void:
	var col := screen("shop")
	col.add_child(ribbon("Upgrades"))
	shop_coins = label("", 32)
	col.add_child(shop_coins)
	shop_list = vbox(12)
	col.add_child(shop_list)
	# Coin packs (only shown once purchases are switched on, see Services)
	if Services.purchases_ready():
		var packs := hbox(12)
		for product in Services.COIN_PACKS:
			var pk: String = product
			packs.add_child(button("🪙 %d" % Services.COIN_PACKS[pk], "yellow", 24, func():
				Services.buy(pk, func(ok: bool):
					if ok:
						main.save.coins += Services.COIN_PACKS[pk]
						main.write_save()
						refresh_shop())))
		col.add_child(packs)
	col.add_child(back_button())


func refresh_shop() -> void:
	shop_coins.text = "🪙 %d" % main.save.coins
	for c in shop_list.get_children():
		c.queue_free()
	for u in main.UPGRADES:
		var lv: int = main.save.up[u.id]
		var maxed: bool = lv >= u.max
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", box(PANEL, INK, 20, 3, 4))
		row.custom_minimum_size.x = 620
		var h := hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		var icon := PanelContainer.new()
		icon.add_theme_stylebox_override("panel", box(WHITE, INK, 16, 3, 0))
		icon.custom_minimum_size = Vector2(76, 76)
		icon.add_child(label({"drill": "🥁", "boots": "👢", "garrison": "🏰", "armory": "💣"}[u.id], 36, INK, 0))
		h.add_child(icon)
		var info := vbox(4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := label(u.name, 26)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var desc := wrapped(label(u.desc, 18, WHITE, 4, font_m), 360)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(name_l)
		info.add_child(desc)
		var pips := label("■".repeat(lv) + "□".repeat(u.max - lv), 18, YELLOW, 4)
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(pips)
		h.add_child(info)
		var cost: int = 0 if maxed else u.cost[lv]
		var id: String = u.id
		var b := button("MAX" if maxed else "🪙 %d" % cost, "green", 24, func():
			main.buy(id)
			refresh_shop())
		b.disabled = maxed or main.save.coins < cost
		b.name = "buy-" + u.id
		b.custom_minimum_size.x = 120
		h.add_child(b)
		row.add_child(h)
		shop_list.add_child(row)


# ---------- Help, pause, results ----------
func _build_help() -> void:
	var col := screen("help")
	col.add_child(ribbon("How to play"))
	for line in [
		"Drag from your blue tower to another tower to build a road. Soldiers march along it.",
		"Soldiers attack enemy and gray towers, and reinforce your own. Bring a tower to zero to take it.",
		"Swipe across one of your roads to cut it.",
		"Bigger towers hold more roads: 1 road below 10 soldiers, 2 from 10, 3 from 30.",
		"Soldiers from different armies fight when they meet on the field.",
		"Tank factories send tanks worth 3 soldiers. Bunkers take half damage. Watchtowers shoot enemies in their circle. Walls block roads.",
		"Take every enemy building to win. Win fast for 3 stars.",
	]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", box(WHITE, INK, 16, 3, 0))
		var l := wrapped(label(line, 22, INK, 0, font_m), 580)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		p.add_child(l)
		col.add_child(p)
	col.add_child(button("Got it", "blue", 28, func(): main.open_menu()))


func _build_paused() -> void:
	var col := screen("paused")
	col.add_child(ribbon("Paused"))
	var r := button("Resume", "yellow", 44, func(): main.resume())
	r.custom_minimum_size = Vector2(400, 96)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(r)
	var row := hbox()
	row.add_child(button("Restart", "blue", 28, func(): main.restart()))
	row.add_child(button("Menu", "blue", 28, func(): main.quit_to_menu()))
	col.add_child(row)
	col.add_child(_toggles())


func _build_win() -> void:
	var col := screen("win")
	var p := panel()
	var v := vbox(16)
	p.add_child(v)
	win_ribbon = ribbon("Victory!", ORANGE)
	v.add_child(win_ribbon)
	var stars := hbox(8)
	for i in 3:
		var s := label("★", 96 if i == 1 else 76, Color(1, 1, 1, 0.35), 10)
		stars.add_child(s)
		win_stars.append(s)
	v.add_child(stars)
	win_stats = hbox(10)
	v.add_child(win_stats)
	win_coins = label("", 34)
	v.add_child(win_coins)
	win_unlock = wrapped(label("", 22, Color("#fff3a0")), 540)
	v.add_child(win_unlock)
	# Double coins for watching an ad (only shown once ads are switched on, see Services)
	ad_btn = button("📺 Watch an ad: double coins", "green", 24, func():
		ad_btn.disabled = true
		Services.show_rewarded(func(watched: bool):
			if watched:
				main.save.coins += _win_coins
				main.write_save()
				win_coins.text = "🪙 +%d" % (_win_coins * 2)
				main.play_sound("coin")
			ad_btn.visible = false))
	ad_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ad_btn)
	next_btn = button("Next level", "yellow", 40, func(): main.start_level(mini(main.level + 1, Levels.LAST_LEVEL)))
	next_btn.custom_minimum_size = Vector2(400, 90)
	next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(next_btn)
	var row := hbox()
	row.add_child(button("Replay", "blue", 26, func(): main.restart()))
	row.add_child(button("Menu", "blue", 26, func(): main.open_menu()))
	v.add_child(row)
	col.add_child(p)


func _stat(value: String, name: String) -> Control:
	var p := PanelContainer.new()
	var s := box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 14, 0, 0)
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(0)
	v.add_child(label(value, 30))
	v.add_child(label(name, 16, WHITE, 4, font_m))
	p.add_child(v)
	return p


func show_win(stars: int, coins: int, unlock: String, time: float, stats: Dictionary) -> void:
	hide_hud()
	for c in win_stats.get_children():
		c.queue_free()
	win_stats.add_child(_stat("%d:%02d" % [floori(time / 60), floori(fmod(time, 60))], "Time"))
	win_stats.add_child(_stat(str(stats.captured), "Captured"))
	win_stats.add_child(_stat(str(stats.killed), "Beaten"))
	win_coins.text = "🪙 +0"
	_win_coins = coins
	var count := create_tween()
	count.tween_interval(0.5)
	count.tween_method(func(v: float):
		win_coins.text = "🪙 +%d" % roundi(v)
		main.play_sound("tick"), 0.0, float(coins), minf(1.2, 0.3 + coins * 0.01))
	ad_btn.visible = coins > 0 and Services.rewarded_ready()
	ad_btn.disabled = false
	win_unlock.text = unlock
	win_unlock.visible = unlock != ""
	next_btn.visible = main.level < Levels.LAST_LEVEL and not main.daily
	for i in 3:
		var s := win_stars[i]
		s.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		s.scale = Vector2.ONE
		if i < stars:
			get_tree().create_timer(0.25 + i * 0.28).timeout.connect(func():
				s.add_theme_color_override("font_color", Color("#ffd23f"))
				s.pivot_offset = s.size / 2
				var tw := create_tween()
				s.scale = Vector2(0.4, 0.4)
				tw.tween_property(s, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				main.play_sound("coin"))
	show_screen("win")
	pop(win_ribbon, 0.05, 0.3)
	for i in win_stats.get_child_count():
		pop(win_stats.get_child(i), 0.9 + i * 0.1, 0.6)


func _build_lose() -> void:
	var col := screen("lose")
	var p := panel()
	var v := vbox(16)
	p.add_child(v)
	lose_ribbon = ribbon("Defeat", Color("#9a8cff"))
	v.add_child(lose_ribbon)
	v.add_child(label("Your last building has fallen.", 26, WHITE, 6, font_m))
	lose_tip = wrapped(label("", 22, WHITE, 5, font_m), 540)
	v.add_child(lose_tip)
	var r := button("Try again", "yellow", 40, func(): main.restart())
	r.custom_minimum_size = Vector2(400, 90)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	var row := hbox()
	row.add_child(button("Upgrades", "blue", 26, func(): show_screen("shop")))
	row.add_child(button("Menu", "blue", 26, func(): main.open_menu()))
	v.add_child(row)
	col.add_child(p)


func show_lose(tip: String) -> void:
	hide_hud()
	lose_tip.text = tr("Tip: %s") % tr(tip)
	show_screen("lose")
	pop(lose_ribbon, 0.05, 0.3)
