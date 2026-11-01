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
const PRIVACY_URL := "https://maxdflamegaming-byte.github.io/New-game/tower-siege/privacy.html"

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
var hint_btn: Button
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
var level_map: VBoxContainer       # the campaign map: a card for each chapter
var map_buttons := {}              # level -> its button on the map
var levels_stars: Label
var objective: Label               # the mission's goal, under the HUD bar
var brief_n := 1                   # the mission the briefing is about
var brief_from := "menu"           # where the briefing's Back goes
var brief_chapter: Label
var brief_title: Label
var brief_goal: Label
var brief_text: Label
var brief_stars: Label
var brief_start: Button
var brief_face: TextureRect         # Captain Skye's portrait (drawn the first time)
var _drawing_face := false
var lose_reason: Label
var shop_list: VBoxContainer
var shop_coins: Label
var win_stars: Array[Label] = []
var win_stats: HBoxContainer
var win_coins: Label
var win_unlock: Label
var win_rays: TextureRect
var win_face: TextureRect
var win_land: Label
var win_land_bar: ProgressBar
var next_btn: Button
var ad_btn: Button
var win_ribbon: Control
var lose_ribbon: Control
var _win_coins := 0
var lose_tip: Label
var vibrate_btn: Button
var cutscenes_btn: Button
var reminders_btn: Button
var stats_btn: Button
var gfx_btns := {}
var lang_btns := {}
var missions_btn: Button
var daily_btn: Button
var reward_days: HBoxContainer
var reward_title: Label
var reward_btn: Button
var mission_list: VBoxContainer
var mission_streak: Label
var quest_track: Control          # the chest track on Quests
var quest_tabs := {}              # "daily" / "weekly" -> its tab button
var quest_tab := "daily"
var quest_note: Label
var prof_face: TextureRect
var prof_name: Label
var prof_rank: Label
var prof_bar: ProgressBar
var prof_next: Label
var prof_stats: GridContainer
var prof_medals: Button
var ach_summary: Label
var ach_list: VBoxContainer
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
	_build_brief()
	_build_shop()
	_build_help()
	_build_settings()
	_build_reward()
	_build_missions()
	_build_profile()
	_build_event()
	_build_replays()
	_build_achievements()
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
	if main != null and main.screen_open == "win":
		win_rays.rotation += dt * 0.35
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
	objective.get_parent().offset_top = 90 + top
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
	# A lesson's words stay on the battle, not over a screen (pause, results)
	hint_panel.visible = id == "" and hint_label.text != ""
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
		"profile":
			refresh_profile()
		"event":
			refresh_event()
		"replays":
			refresh_replays()
		"achievements":
			refresh_achievements()
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
	# The mission's goal, under the bar: "🛡 Hold your HQ: 0:42"
	objective = _pill("")
	objective.add_theme_font_size_override("font_size", 22)
	var op: Control = objective.get_parent()
	op.set_anchors_preset(Control.PRESET_CENTER_TOP)
	op.grow_horizontal = Control.GROW_DIRECTION_BOTH
	op.offset_top = 90
	op.visible = false
	hud.add_child(op)
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
	# 💡: what to do now (campaign)
	hint_btn = button("💡", "yellow", 40, func(): main.show_hint())
	hint_btn.custom_minimum_size = Vector2(100, 100)
	hint_btn.add_theme_constant_override("content_margin_bottom", 22)
	hint_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var hcap := label("Hint", 16)
	hcap.position = Vector2(0, 74)
	hcap.size = Vector2(100, 24)
	hcap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hcap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	hint_btn.add_child(hcap)
	abilities.add_child(hint_btn)
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
	var goal: Dictionary = main.goal
	var op: Control = objective.get_parent()
	op.visible = campaign and not goal.is_empty()
	if op.visible:
		op.add_theme_stylebox_override("panel", UISkin.pill(Missions.GOALS[goal.goal].color))
		objective.text = Missions.objective(goal, main.battle)
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
	var t: float = b.time if main.mode == "campaign" or main.mode == "replay" else maxf(0, Net.PVP_TIME - b.time)
	time_label.text = "%d:%02d" % [floori(t / 60), floori(fmod(t, 60))]
	time_label.add_theme_color_override("font_color", Color("#fff3a0") if main.mode != "campaign" and t < 20 else WHITE)
	if objective.get_parent().visible and not main.goal.is_empty():
		objective.text = Missions.objective(main.goal, b)
		var hurry := Missions.urgent(main.goal, b)
		objective.add_theme_color_override("font_color", Color("#ffe14d") if hurry and int(b.time * 2) % 2 == 0 else WHITE)
	refresh_abilities()


func refresh_abilities() -> void:
	for id in ability_btns:
		var a: Dictionary = ability_btns[id]
		var unlocked: bool = main.level >= (3 if id == "strike" else 6)
		a.btn.visible = unlocked or main.charges[id] > 0
		a.count.text = str(main.charges[id])
		a.btn.disabled = main.state != "play" or (main.charges[id] <= 0 and main.armed != id) or (id == "rally" and main.battle.rally > 0)
		a.btn.modulate = Color(1, 0.75, 0.75) if main.armed == id else Color.WHITE
	if hint_btn:
		hint_btn.disabled = main.state != "play"


func refresh_speed() -> void:
	speed_btn.text = "%d×" % main.speed


## lesson: a step of the lessons, written big on the field in white (not in a box), so it
## can't be missed
func set_hint(text: String, lesson := false) -> void:
	hint_label.text = text
	hint_panel.visible = text != ""
	if lesson:
		hint_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		hint_label.add_theme_font_size_override("font_size", 30)
		hint_label.add_theme_color_override("font_color", WHITE)
		hint_label.add_theme_color_override("font_outline_color", INK)
		hint_label.add_theme_constant_override("outline_size", 12)
	else:
		hint_panel.add_theme_stylebox_override("panel", box(WHITE, INK, 18, 3, 4))
		hint_label.add_theme_font_size_override("font_size", 22)
		hint_label.add_theme_color_override("font_color", INK)
		hint_label.add_theme_constant_override("outline_size", 0)


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
	# Under the top bar, and under the mission's goal when it shows (on the home screen,
	# under the level's name, clear of ☰ and Quests)
	var y := (150.0 if objective.get_parent().is_visible_in_tree() else 380.0 if main.screen_open == "menu" else 104.0) + safe_top
	toast_panel.offset_top = y - 34
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.parallel().tween_property(toast_panel, "offset_top", y, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.3)


# ---------- Menu ----------
var menu_badges := {}            # tile id -> its little red badge (Label inside a panel)


## The home screen, over the map of the level you play next: your name and coins at the top,
## ☰ (settings, help, leaderboard, looks) and 📜 Quests under them, the level's number and
## mission in the middle, a big PLAY, the daily challenge beside it, and a bar of tabs along
## the bottom that open up as you go through the levels
const TABS := [
	{"id": "shop", "icon": "🛒", "text": "Shop", "unlock": 4},
	{"id": "levels", "icon": "🗺", "text": "Map", "unlock": 2},
	{"id": "home", "icon": "⚔", "text": "Battle", "unlock": 1},
	{"id": "pvp", "icon": "🏆", "text": "PvP", "unlock": 6},
	{"id": "clans", "icon": "🛡", "text": "Clans", "unlock": 10},
]
const DAILY_UNLOCK := 8
var tab_btns := {}                # tab id -> its button
var menu_level: Label             # "LEVEL 7" over the map
var menu_mission: Label           # the mission's code name and goal
var menu_name: Label
var menu_rank: Label             # your rank under your name
var medals_btn: Button
var event_btn: Button
var replay_list: VBoxContainer
var event_name: Label
var event_desc: Label
var event_when: Label
var event_stages: HBoxContainer
var event_prize: Label
var event_play: Button
var profile_btn: Button          # your face and name on the home screen
var menu_face: TextureRect
var more_panel: PanelContainer    # what ☰ opens


func _build_menu() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	# Shade at the top and bottom, so the bars stand out from the map
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.72, 1.0])
	g.colors = PackedColorArray([Color(0.06, 0.1, 0.25, 0.55), Color(0.06, 0.1, 0.25, 0.0), Color(0.06, 0.1, 0.25, 0.0), Color(0.06, 0.1, 0.25, 0.6)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var frame := Control.new()       # (fit_safe keeps it clear of a notch)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	add_child(root)
	screens["menu"] = root

	# Top bar: your captain's face and name, and your coins
	var bar := PanelContainer.new()
	var bs := box(Color("#24345e"), Color("#101a38"), 0, 0, 0)
	bs.bg_color.a = 0.86
	bs.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", bs)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 92
	frame.add_child(bar)
	var row := hbox(12)
	bar.add_child(row)
	# Your face, name and rank open your profile
	var me := Button.new()
	profile_btn = me
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		me.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	me.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me.custom_minimum_size.y = 70
	me.pressed.connect(func():
		main.play_sound("tap")
		show_screen("profile"))
	squishy(me)
	row.add_child(me)
	var me_row := hbox(12)
	me_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	me_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me.add_child(me_row)
	var face := PanelContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", box(Color("#3a9df3"), WHITE, 16, 3, 0))
	face.custom_minimum_size = Vector2(70, 70)
	var helmet := label("🎖", 40, WHITE, 0)
	helmet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.add_child(helmet)
	menu_face = TextureRect.new()
	menu_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.add_child(menu_face)
	me_row.add_child(face)
	var names := vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_name = label("", 28, WHITE, 6)
	menu_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	names.add_child(menu_name)
	menu_rank = label("", 18, YELLOW, 5)
	menu_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu_rank.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	names.add_child(menu_rank)
	me_row.add_child(names)
	menu_coins = _pill("0")
	menu_coins.add_theme_font_size_override("font_size", 30)
	menu_coins.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(menu_coins.get_parent())

	# ☰ on the left, 📜 Quests on the right
	var more := button("☰", "blue", 40, func(): more_panel.visible = not more_panel.visible)
	more.custom_minimum_size = Vector2(88, 88)
	more.position = Vector2(16, 108)
	frame.add_child(more)
	missions_btn = _side_button("missions", "📜", "Quests", "orange", func(): show_screen("missions"))
	missions_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	missions_btn.offset_left = -124
	missions_btn.offset_right = -16
	missions_btn.offset_top = 104
	missions_btn.offset_bottom = 212
	frame.add_child(missions_btn)
	medals_btn = _side_button("achievements", "🏅", "Medals", "purple", func(): show_screen("achievements"))
	medals_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	medals_btn.offset_left = -240
	medals_btn.offset_right = -132
	medals_btn.offset_top = 104
	medals_btn.offset_bottom = 212
	frame.add_child(medals_btn)
	more_panel = PanelContainer.new()
	more_panel.add_theme_stylebox_override("panel", box(Color("#24345e"), WHITE, 18, 3, 6))
	more_panel.position = Vector2(16, 204)
	more_panel.visible = false
	var list := vbox(10)
	more_panel.add_child(list)
	for item in [["⚙  Settings", func(): show_screen("settings")], ["❓  How to play", func(): show_screen("help")],
			["🏆  Leaderboard", func(): main.net.open_board()], ["🎨  Looks", func(): show_screen("looks")],
			["🎬  Replays", func(): show_screen("replays")]]:
		var on: Callable = item[1]
		var b := button(item[0], "blue", 24, func():
			more_panel.visible = false
			on.call())
		b.custom_minimum_size = Vector2(280, 70)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	frame.add_child(more_panel)

	# The level you play next, over its map
	var mid := vbox(4)
	mid.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mid.offset_top = 226
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(mid)
	var band := PanelContainer.new()
	var bandst := StyleBoxFlat.new()
	bandst.bg_color = Color(0.13, 0.4, 0.85, 0.72)
	bandst.content_margin_top = 4
	bandst.content_margin_bottom = 6
	band.add_theme_stylebox_override("panel", bandst)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_level = label("", 64, WHITE, 14)
	menu_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_level.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	band.add_child(menu_level)
	mid.add_child(band)
	menu_mission = label("", 26, WHITE, 8)
	menu_mission.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_mission.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mid.add_child(menu_mission)

	# PLAY, and the daily challenge beside it
	play_btn = button("PLAY", "green", 64, func(): show_brief(mini(main.save.level, Levels.LAST_LEVEL), "menu"))
	play_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	play_btn.offset_left = -190
	play_btn.offset_right = 190
	play_btn.offset_top = -290
	play_btn.offset_bottom = -170
	frame.add_child(play_btn)
	event_btn = _side_button("event", "🎪", "Event", "red", _event)
	event_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	event_btn.offset_left = 16
	event_btn.offset_right = 124
	event_btn.offset_top = -284
	event_btn.offset_bottom = -176
	frame.add_child(event_btn)
	daily_btn = _side_button("daily", "📅", "Daily", "purple", _daily)
	daily_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	daily_btn.offset_left = -124
	daily_btn.offset_right = -16
	daily_btn.offset_top = -284
	daily_btn.offset_bottom = -176
	frame.add_child(daily_btn)

	# The tabs
	var tabs := PanelContainer.new()
	var ts := box(Color("#24345e"), Color("#101a38"), 0, 0, 0)
	ts.bg_color.a = 0.94
	ts.set_content_margin_all(6)
	tabs.add_theme_stylebox_override("panel", ts)
	tabs.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tabs.offset_top = -138
	frame.add_child(tabs)
	var trow := hbox(6)
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_child(trow)
	for t in TABS:
		var id: String = t.id
		var b := tile(id, t.icon, t.text, "blue" if id == "home" else "gray", func(): _open_tab(id))
		b.custom_minimum_size = Vector2(132, 124)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btns[id] = b
		trow.add_child(b)


## A round-cornered square button at the side of the home screen: a picture over a word
func _side_button(id: String, icon: String, text: String, kind: String, on_press: Callable) -> Button:
	var b := tile(id, icon, text, kind, on_press)
	b.custom_minimum_size = Vector2(108, 108)
	b.add_theme_font_size_override("font_size", 18)
	var dot: Control = menu_badges[id].get_parent()
	dot.position = Vector2(78, -12)
	return b


## A tab on the home screen: what it opens, or when it opens up
func _open_tab(id: String) -> void:
	var t: Dictionary = TABS.filter(func(x): return x.id == id)[0]
	if int(main.save.level) < int(t.unlock):
		main.play_sound("beep")
		toast(tr("Unlocks at level %d") % int(t.unlock))
		return
	match id:
		"shop":
			show_screen("shop")
		"levels":
			show_screen("levels")
		"pvp":
			main.net.open_pvp()
		"clans":
			main.net.open_clans()


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
		reminders_btn.text = "Reminders: on" if main.save.get("reminders", true) else "Reminders: off"
		stats_btn.text = "Share anonymous level stats: on" if main.save.get("stats", true) else "Share anonymous level stats: off"
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
		# The first time: Android asks if the game may remind you when the next one is ready
		if not main.save.seen.has("reminders") and main.save.get("reminders", true):
			main.save.seen["reminders"] = true
			PhoneReminders.ask()
		main.write_save()
		main.check_achievements()
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
	col.add_child(ribbon("Quests"))
	var tabs := hbox(10)
	quest_tabs = {"daily": button("Daily quests", "yellow", 24, func(): _quest_tab("daily")),
		"weekly": button("Weekly quests", "blue", 24, func(): _quest_tab("weekly"))}
	for k in quest_tabs:
		quest_tabs[k].custom_minimum_size = Vector2(290, 72)
		tabs.add_child(quest_tabs[k])
	col.add_child(tabs)
	# The chest track: today's quest points fill it, and its chests open at set points
	quest_track = Control.new()
	quest_track.custom_minimum_size = Vector2(620, 236)
	col.add_child(quest_track)
	mission_streak = wrapped(label("", 22, WHITE, 5, font_m), 600)
	col.add_child(mission_streak)
	mission_list = vbox(12)
	col.add_child(mission_list)
	quest_note = wrapped(label("", 18, WHITE, 4, font_m), 600)
	col.add_child(quest_note)
	col.add_child(back_button())


func _quest_tab(tab: String) -> void:
	quest_tab = tab
	refresh_missions()


func refresh_missions() -> void:
	for c in mission_list.get_children():
		c.queue_free()
	for k in quest_tabs:
		set_kind(quest_tabs[k], "yellow" if k == quest_tab else "blue")
	var weekly := quest_tab == "weekly"
	quest_track.visible = not weekly
	mission_streak.visible = not weekly
	if weekly:
		var days := Progress.days_left_in_week()
		quest_note.text = tr("Bigger quests that last all week. New ones in %d days.") % days if days > 1 else tr("Bigger quests that last all week. New ones tomorrow.")
		var wl := Progress.weekly(main.save)
		for i in wl.size():
			var m: Dictionary = wl[i]
			var idx := i
			mission_list.add_child(progress_row("📆", Progress.mission_text(m), "", int(m.have), int(m.goal), int(m.coins), m.claimed, func():
				return Progress.claim_weekly(main.save, idx)))
		return
	quest_note.text = tr("New quests every day, the same for everyone. Each one you collect earns ⭐ points that open the chests.")
	_refresh_track()
	if Progress.reward_ready(main.save):
		var rb := button(tr("🎁 Collect your daily reward (day %d)") % Progress.streak_next(main.save), "yellow", 24, func(): show_screen("reward"))
		mission_list.add_child(rb)
	mission_streak.text = "Daily reward streak: 1 day" if int(main.save.streak.count) == 1 else tr("Daily reward streak: %d days") % int(main.save.streak.count)
	var list := Progress.missions(main.save)
	for i in list.size():
		var m: Dictionary = list[i]
		var idx := i
		mission_list.add_child(progress_row("📜", Progress.mission_text(m), "⭐ +%d" % Progress.QUEST_POINTS, int(m.have), int(m.goal), int(m.coins), m.claimed, func():
			return Progress.claim_mission(main.save, idx)))


## A row with a progress bar: a picture, what to do, how far you are, and a button that
## collects its coins once it's done. claim: returns the coins collected.
func progress_row(icon: String, title: String, sub: String, have: int, goal: int, coins: int, claimed: bool, claim: Callable) -> PanelContainer:
	var done := have >= goal
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", box(PANEL if done or claimed else Color("#3a6fc4"), INK, 20, 3, 4))
	row.custom_minimum_size.x = 620
	var h := hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	var pic := label(icon, 38, WHITE, 0)
	pic.custom_minimum_size = Vector2(56, 56)
	pic.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if claimed:
		pic.modulate = Color(1, 1, 1, 0.55)
	h.add_child(pic)
	var info := vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := wrapped(label(title, 22), 340)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(name_l)
	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = mini(have, goal)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 20)
	bar.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.3), INK, 10, 2, 0))
	bar.add_theme_stylebox_override("fill", box(YELLOW if not done else Color("#4cbc45"), INK, 10, 2, 0))
	info.add_child(bar)
	var count := label("%d / %d" % [mini(have, goal), goal] + ("   ·   " + sub if sub != "" else ""), 17, WHITE, 4)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.add_child(count)
	h.add_child(info)
	var b := button("✓" if claimed else "🪙 %d" % coins, "green" if done and not claimed else "blue", 24, func():
		var got: int = claim.call()
		if got > 0:
			main.write_save()
			main.play_sound("coin")
			toast(tr("+%d coins!") % got)
			main.check_achievements()
		show_screen(main.screen_open))
	b.disabled = not done or claimed
	b.custom_minimum_size.x = 124
	h.add_child(b)
	row.add_child(h)
	return row


# ---------- Replays ----------
## Your last battles, to watch again
func _build_replays() -> void:
	var col := screen("replays")
	col.add_child(ribbon("Replays"))
	col.add_child(wrapped(label("Your last battles are kept here, so you can watch them again.", 20, WHITE, 4, font_m), 600))
	replay_list = vbox(12)
	col.add_child(replay_list)
	col.add_child(back_button())


func refresh_replays() -> void:
	for c in replay_list.get_children():
		c.queue_free()
	var list: Array = main.replays.list()
	if list.is_empty():
		replay_list.add_child(wrapped(label("No replays yet. Play a battle, and it will be here.", 24, WHITE, 6, font_m), 600))
		return
	var now := int(Time.get_unix_time_from_system())
	for i in list.size():
		var r: Dictionary = list[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", box(PANEL, INK, 20, 3, 4))
		row.custom_minimum_size.x = 620
		var h := hbox(12)
		var res: String = r.result
		var pic := label("🏆" if res == "won" else "🤝" if res == "draw" else "💀", 38, WHITE, 0)
		pic.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.add_child(pic)
		var info := vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := label(str(r.title), 24)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		info.add_child(t)
		var ago := now - int(r.when)
		var when := tr("just now") if ago < 120 else (tr("%d min ago") % (ago / 60) if ago < 7200 else (tr("%d h ago") % (ago / 3600) if ago < 172800 else tr("%d days ago") % (ago / 86400)))
		var sub := label("%s  ·  %d:%02d  ·  %s" % [tr({"won": "Victory", "lost": "Defeat", "draw": "Draw"}.get(res, "Defeat")), int(r.secs) / 60, int(r.secs) % 60, when], 18, WHITE, 4, font_m)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		info.add_child(sub)
		h.add_child(info)
		var idx := i
		h.add_child(button("▶ Watch", "green", 24, func(): main.watch_replay(idx)))
		row.add_child(h)
		replay_list.add_child(row)


# ---------- Weekend event ----------
## This weekend's event: what it is, its three battles, the look for winning them all, and
## Play (on weekdays: which event comes next, and when)
func _build_event() -> void:
	var col := screen("event")
	col.add_child(ribbon("Weekend event", RED))
	var p := panel()
	var v := vbox(12)
	p.add_child(v)
	event_name = label("", 40, YELLOW, 10)
	event_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(event_name)
	event_desc = wrapped(label("", 22, WHITE, 5, font_m), 560)
	event_desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(event_desc)
	event_stages = hbox(12)
	v.add_child(event_stages)
	event_prize = wrapped(label("", 24, YELLOW, 6), 560)
	event_prize.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(event_prize)
	event_when = wrapped(label("", 20, WHITE, 4, font_m), 560)
	event_when.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(event_when)
	col.add_child(p)
	event_play = button("", "green", 40, func(): main.start_event())
	event_play.custom_minimum_size = Vector2(420, 100)
	event_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(event_play)
	col.add_child(back_button())


func refresh_event() -> void:
	var live := Events.live()
	var st := Events.state(main.save)
	var k: String = st.kind if live else Events.kind()
	var e := Events.info(k)
	event_name.text = e.icon + "  " + tr(e.name)
	event_desc.text = tr(e.desc)
	for c in event_stages.get_children():
		c.queue_free()
	for i in Events.STAGES:
		var done := live and int(st.stage) > i
		var next := live and int(st.stage) == i
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", box(Color("#4cbc45") if done else (YELLOW if next else Color(1, 1, 1, 0.22)), INK, 18, 3, 3))
		card.custom_minimum_size = Vector2(176, 120)
		var cv := vbox(2)
		cv.add_child(label(tr("Battle %d") % (i + 1), 22, WHITE if not next else INK, 5 if not next else 0))
		cv.add_child(label("✓" if done else ("▶" if next else "🔒"), 34, WHITE if not next else INK, 5 if not next else 0))
		cv.add_child(label("🪙 %d" % Events.STAGE_COINS[i], 20, WHITE if not next else INK, 5 if not next else 0))
		card.add_child(cv)
		event_stages.add_child(card)
	var pz := Events.prize(k)
	event_prize.text = tr("Win all three: %s (a look you can't buy)") % tr(pz[2])
	if live:
		event_when.text = tr("Ends tonight at midnight (UTC).") if (Progress.today() + 3) % 7 == 6 else tr("On until Sunday midnight (UTC).")
		event_play.visible = int(st.stage) < Events.STAGES
		event_play.text = tr("Play battle %d") % (int(st.stage) + 1)
		if int(st.stage) >= Events.STAGES:
			event_when.text = tr("You won this weekend's event! A new one comes next weekend.")
	else:
		var dd := Events.days_until()
		event_when.text = tr("Next weekend's event starts in %d days (Saturday, UTC).") % dd if dd > 1 else tr("Next weekend's event starts tomorrow (Saturday, UTC).")
		event_play.visible = false


# ---------- Profile and achievements ----------
## Your profile: your captain, name and rank (with the stars to the next), your lifetime
## numbers, and the way to the achievements
func _build_profile() -> void:
	var col := screen("profile")
	col.add_child(ribbon("Profile"))
	var p := panel()
	var v := vbox(12)
	p.add_child(v)
	var top := hbox(16)
	var face := PanelContainer.new()
	face.add_theme_stylebox_override("panel", box(Color("#3a9df3"), WHITE, 22, 4, 0))
	face.custom_minimum_size = Vector2(130, 130)
	var medal := label("🎖", 70, WHITE, 0)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_child(medal)
	prof_face = TextureRect.new()
	prof_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prof_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.add_child(prof_face)
	top.add_child(face)
	var who := vbox(6)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_name = label("", 34, WHITE, 8)
	prof_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	prof_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(prof_name)
	prof_rank = label("", 26, YELLOW, 7)
	prof_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	prof_rank.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(prof_rank)
	prof_bar = ProgressBar.new()
	prof_bar.show_percentage = false
	prof_bar.custom_minimum_size = Vector2(340, 22)
	prof_bar.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.3), INK, 10, 2, 0))
	prof_bar.add_theme_stylebox_override("fill", box(YELLOW, INK, 10, 2, 0))
	who.add_child(prof_bar)
	prof_next = label("", 18, WHITE, 4, font_m)
	prof_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	prof_next.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	who.add_child(prof_next)
	top.add_child(who)
	v.add_child(top)
	prof_stats = GridContainer.new()
	prof_stats.columns = 3
	prof_stats.add_theme_constant_override("h_separation", 10)
	prof_stats.add_theme_constant_override("v_separation", 10)
	v.add_child(prof_stats)
	col.add_child(p)
	prof_medals = button("🏅 Achievements", "purple", 30, func(): show_screen("achievements"))
	prof_medals.custom_minimum_size = Vector2(440, 90)
	prof_medals.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(prof_medals)
	col.add_child(back_button())


func refresh_profile() -> void:
	var sv: Dictionary = main.save
	prof_name.text = sv.name if str(sv.get("name", "")) != "" else tr("Commander")
	var r := Achievements.rank(sv)
	prof_rank.text = "⭐ " + tr(r.name)
	if r.next < 0:
		prof_bar.max_value = 1
		prof_bar.value = 1
		prof_next.text = tr("The highest rank! %d stars.") % r.stars
	else:
		prof_bar.min_value = int(Achievements.RANKS[r.i][1])
		prof_bar.max_value = r.next
		prof_bar.value = r.stars
		prof_next.text = tr("⭐ %d / %d to %s") % [r.stars, r.next, tr(Achievements.RANKS[r.i + 1][0])]
	for c in prof_stats.get_children():
		c.queue_free()
	var life: Dictionary = sv.life
	var won := int(life.get("win", 0))
	for item in [[str(Achievements.value(sv, "level")), "Levels beaten"], ["%d / 180" % r.stars, "Stars"],
			[str(Achievements.value(sv, "bosses")), "Bosses beaten"], [str(won), "Battles won"],
			[str(int(life.get("capture", 0))), "Buildings taken"], [str(int(life.get("beat", 0))), "Soldiers beaten"],
			[str(int(life.get("perfect", 0))), "Flawless wins"], [str(int(life.get("pvp_win", 0))), "PvP wins"],
			[str(int(sv.trophies)), "Trophies"]]:
		var t := _stat(item[0], item[1])
		t.custom_minimum_size = Vector2(196, 0)
		prof_stats.add_child(t)
	var have: int = sv.ach.done.size()
	prof_medals.text = tr("🏅 Achievements  %d / %d") % [have, Achievements.LIST.size()]
	_profile_face()


func _profile_face() -> void:
	var cut: Cutscene = main.cutscene
	if not cut.portraits.has("skye") and not _drawing_face:
		_drawing_face = true
		cut.portraits["skye"] = await cut._portrait("skye")
		_drawing_face = false
	prof_face.texture = cut.portraits.get("skye")


## Every achievement, in its group: earned ones to collect first
func _build_achievements() -> void:
	var col := screen("achievements")
	col.add_child(ribbon("Achievements"))
	ach_summary = wrapped(label("", 24, WHITE, 6, font_m), 600)
	col.add_child(ach_summary)
	col.add_child(back_button("profile"))   # (a long list: a way back at the top too)
	ach_list = vbox(12)
	col.add_child(ach_list)
	col.add_child(back_button("profile"))


func refresh_achievements() -> void:
	for c in ach_list.get_children():
		c.queue_free()
	var sv: Dictionary = main.save
	var waiting := 0
	for a in Achievements.LIST:
		if Achievements.earned(sv, a[1]) and not Achievements.claimed(sv, a[1]):
			waiting += int(a[7])
	ach_summary.text = tr("%d of %d earned") % [sv.ach.done.size(), Achievements.LIST.size()] + \
		("   ·   " + tr("🪙 %d to collect") % waiting if waiting > 0 else "")
	for g in Achievements.GROUPS:
		ach_list.add_child(label(g, 30, YELLOW, 8))
		var group := Achievements.LIST.filter(func(a): return a[0] == g)
		# Ready to collect first, then the ones in progress, then the collected
		group.sort_custom(func(a, b): return _ach_order(a) < _ach_order(b))
		for a in group:
			var id: String = a[1]
			ach_list.add_child(progress_row(a[2], tr(a[3]), Achievements.text(a), Achievements.value(sv, a[5]), int(a[6]), int(a[7]),
				Achievements.claimed(sv, id), func(): return Achievements.claim(main.save, id)))


func _ach_order(a: Array) -> int:
	var sv: Dictionary = main.save
	if Achievements.claimed(sv, a[1]):
		return 2
	return 0 if Achievements.earned(sv, a[1]) else 1


## Today's quest points on a bar, with a chest at each step: ready ones bounce and open with a
## tap, opened ones show a tick
func _refresh_track() -> void:
	for c in quest_track.get_children():
		c.queue_free()
	var q := Progress.quest(main.save)
	var most := float(Progress.CHESTS[-1].at)
	var x0 := 120.0
	var w := 470.0
	var y := 104.0
	var medal := label("⭐\n%d" % int(q.points), 30, YELLOW, 8)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.position = Vector2(8, 58)
	medal.size = Vector2(96, 90)
	quest_track.add_child(medal)
	var bar := ProgressBar.new()
	bar.max_value = most
	bar.value = minf(float(q.points), most)
	bar.show_percentage = false
	bar.position = Vector2(x0, y)
	bar.size = Vector2(w, 26)
	bar.add_theme_stylebox_override("background", box(Color("#1d2a4d"), INK, 10, 2, 0))
	bar.add_theme_stylebox_override("fill", box(YELLOW, INK, 10, 2, 0))
	quest_track.add_child(bar)
	for i in Progress.CHESTS.size():
		var c: Dictionary = Progress.CHESTS[i]
		var ready := Progress.chest_ready(main.save, i)
		var opened: bool = i in q.opened.map(func(v): return int(v))
		var idx := i
		var b := button("✓" if opened else "🎁", "yellow" if ready else "gray", 34, func():
			var coins := Progress.open_chest(main.save, idx)
			if coins > 0:
				main.write_save()
				main.check_achievements()
				main.play_sound("coin")
				toast(tr("+%d coins!") % coins)
				refresh_missions())
		b.disabled = not ready
		b.size = Vector2(76, 70)
		var cx := x0 + w * float(c.at) / most
		# Above and below the bar in turn, so they don't crowd
		b.position = Vector2(cx - 38, y - 78 if i % 2 == 0 else y + 34)
		quest_track.add_child(b)
		var at := label(str(int(c.at)), 18, WHITE, 5)
		at.position = Vector2(cx - 30, y - 104 if i % 2 == 0 else y + 104)
		at.size = Vector2(60, 24)
		at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quest_track.add_child(at)
		if ready:
			pop(b, 0.1 + i * 0.08, 0.6)


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
			# Bought with coins, or unlocked by an achievement or a weekend event
			var lock: String = item.get("lock", "")
			var open := Progress.unlocked(main.save, item)
			var price := "🪙 %d" % item.cost
			if lock.begins_with("ach:"):
				price = tr("Free!") if open else "🔒 " + tr(Achievements.info(lock.substr(4))[3])
			elif lock.begins_with("event:"):
				price = "🎪 " + tr("Weekend event")
			var price_l := wrapped(label(state if owned else price, 17 if not owned and lock != "" else 20, WHITE, 6), 160)
			card.add_child(price_l)
			for c in card.get_children():
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(card)
			b.disabled = not owned and (not open or int(main.save.coins) < int(item.cost))
			var id: String = item.id
			var k: String = kind
			b.pressed.connect(func():
				if Progress.pick_look(main.save, k, id) == "":
					main.write_save()
					main.check_achievements()
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
	reminders_btn = button("Reminders: on", "blue", 22, func():
		main.save.reminders = not bool(main.save.get("reminders", true))
		if main.save.reminders:
			PhoneReminders.ask()
		main.write_save()
		PhoneReminders.apply(main.save)
		refresh_toggles())
	reminders_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(reminders_btn)
	var watch := button("🎬 Watch the story again", "blue", 22, func(): main.watch_story())
	var lessons := button("🎓 Play the lessons again", "blue", 22, func(): main.replay_lessons())
	var row3 := hbox(10)
	row3.add_child(watch)
	row3.add_child(lessons)
	v.add_child(row3)
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
	# Anonymous level stats (see analytics.gd): which levels are too hard, so they can be fixed
	stats_btn = button("Share anonymous level stats: on", "blue", 20, func():
		main.save.stats = not main.save.get("stats", true)
		if not main.save.stats:
			main.save.stats_rows = []
		main.write_save()
		refresh_toggles())
	stats_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(stats_btn)
	v.add_child(wrapped(label("Only level numbers, times and results, to find levels that are too hard. Nothing about you or your phone.", 16, WHITE, 4, font_m), 540))
	var policy := button("Privacy policy", "white", 20, func(): OS.shell_open(PRIVACY_URL))
	policy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(policy)
	col.add_child(p)
	col.add_child(back_button())


func refresh_menu() -> void:
	var n := mini(int(main.save.level), Levels.LAST_LEVEL)
	menu_coins.text = "🪙 %d" % main.save.coins
	menu_name.text = main.save.name if str(main.save.get("name", "")) != "" else tr("Commander")
	menu_rank.text = "⭐ " + tr(Achievements.rank(main.save).name)
	var medals := Achievements.claimable(main.save)
	set_badge("achievements", str(medals) if medals > 0 else "")
	menu_level.text = tr("LEVEL %d") % n
	menu_mission.text = Missions.title(n) + "\n" + Missions.icon(Missions.goal_for(n)) + "  " + Missions.goal_name(Missions.goal_for(n))
	more_panel.visible = false
	var k := Progress.claimable(main.save) + Progress.weekly_claimable(main.save) + Progress.chests_ready(main.save) + (1 if Progress.reward_ready(main.save) else 0)
	set_badge("missions", str(k) if k > 0 else "")
	_lock(daily_btn, "📅", "Daily", DAILY_UNLOCK)
	_lock(event_btn, "🎪", "Event", DAILY_UNLOCK)
	var ev := Events.state(main.save)
	set_badge("event", "!" if Events.live() and int(ev.stage) < Events.STAGES and n >= DAILY_UNLOCK else "")
	set_badge("daily", "✓" if int(main.save.daily_won) == Progress.today() and n >= DAILY_UNLOCK else "")
	for t in TABS:
		_lock(tab_btns[t.id], t.icon, t.text, int(t.unlock))
	_menu_face()
	refresh_toggles()


## A locked button shows a padlock and the level it opens at
func _lock(b: Button, icon: String, text: String, unlock: int) -> void:
	var open := int(main.save.level) >= unlock
	var pic: Label = b.get_child(0)
	pic.text = icon if open else "🔒"
	b.text = tr(text) if open else tr("Level %d") % unlock
	b.modulate = Color.WHITE if open else Color(0.8, 0.85, 0.95)


## The weekend event's screen, once it's open (it opens with the daily challenge)
func _event() -> void:
	if int(main.save.level) < DAILY_UNLOCK:
		main.play_sound("beep")
		toast(tr("Unlocks at level %d") % DAILY_UNLOCK)
		return
	show_screen("event")


## The daily challenge, once it's open
func _daily() -> void:
	if int(main.save.level) < DAILY_UNLOCK:
		main.play_sound("beep")
		toast(tr("Unlocks at level %d") % DAILY_UNLOCK)
		return
	main.start_daily()


## Captain Skye's face in the top bar (a medal until it's drawn)
func _menu_face() -> void:
	var cut: Cutscene = main.cutscene
	if not cut.portraits.has("skye") and not _drawing_face:
		_drawing_face = true
		cut.portraits["skye"] = await cut._portrait("skye")
		_drawing_face = false
	menu_face.texture = cut.portraits.get("skye")


# ---------- The campaign map ----------
## The campaign as a map: a card for each chapter (its land, title and story) with its five
## missions on a winding trail, the boss's castle at the end
func _build_levels() -> void:
	var col := screen("levels")
	col.add_child(ribbon("Campaign"))
	levels_stars = label("", 24)
	col.add_child(levels_stars)
	level_map = vbox(22)
	col.add_child(level_map)
	col.add_child(back_button())


const LAND_COLORS := {"grass": "#3f9e3a", "desert": "#d18a2c", "snow": "#4f8fd0", "beach": "#1ea7a8"}
## Where a chapter's five missions sit on its card (fractions of its width, and pixels down)
const TRAIL := [Vector2(0.15, 78), Vector2(0.5, 52), Vector2(0.85, 96), Vector2(0.64, 226), Vector2(0.27, 236)]
const TRAIL_W := 560.0
const TRAIL_H := 320.0


## A chapter's trail: dots from mission to mission
class Trail:
	extends Control
	var points := PackedVector2Array()
	var reached := 0         # missions reached so far on this trail (the trail to them is bright)

	func _draw() -> void:
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			# A gentle curve between the two
			var mid := (a + b) / 2 + Vector2(0, -26 if i % 2 == 0 else 26)
			var steps := int(a.distance_to(b) / 22)
			for k in range(1, steps):
				var f := float(k) / steps
				var p := a.lerp(mid, f).lerp(mid.lerp(b, f), f)
				var lit := i + 1 < reached
				draw_circle(p + Vector2(0, 2), 7, Color(0, 0, 0, 0.18))
				draw_circle(p, 6.5, Color.WHITE if lit else Color(1, 1, 1, 0.45))


func refresh_levels() -> void:
	for c in level_map.get_children():
		c.queue_free()
	map_buttons.clear()
	var reached: int = main.save.level
	var total := 0
	for n in range(1, Levels.LAST_LEVEL + 1):
		total += int(main.save.stars.get(str(n), 0))
	# The 12 chapters, then the endless ones reached so far
	var chapters := maxi(Levels.MAX_LEVEL / Missions.PER_CHAPTER, Missions.chapter_of(mini(reached, Levels.LAST_LEVEL)))
	var here: Control = null
	for c in range(1, chapters + 1):
		var card := _chapter_card(c, reached)
		level_map.add_child(card)
		if Missions.chapter_of(reached) == c:
			here = card
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_interval(minf(0.5, c * 0.05))
		tw.tween_property(card, "modulate:a", 1.0, 0.2)
	levels_stars.text = tr("%d ★ collected") % total
	# Open the map at the chapter you're playing
	if here != null:
		await get_tree().process_frame
		await get_tree().process_frame
		var scroll: ScrollContainer = screens.levels.get_child(1)
		if is_instance_valid(here) and main.screen_open == "levels":
			scroll.scroll_vertical = int(here.get_global_rect().position.y - scroll.get_child(0).get_global_rect().position.y - 120)


func _chapter_card(c: int, reached: int) -> Control:
	var first := (c - 1) * Missions.PER_CHAPTER + 1
	var theme := Levels.theme_for(first)
	var locked := first > reached
	var p := PanelContainer.new()
	var bg := Color(LAND_COLORS[theme])
	var sb := box(bg if not locked else bg.lerp(Color("#7d8aa3"), 0.6), Color.WHITE, 26, 4, 6)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = 600
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := vbox(4)
	p.add_child(v)
	var head := label(tr("Chapter %d") % c + "  ·  " + tr(Story.LANDS[theme]), 20, WHITE, 6, font_m)
	v.add_child(head)
	v.add_child(label(Missions.chapter_title(c), 34, WHITE, 8))
	var story := wrapped(label(Missions.chapter_story(c) if not locked else tr("Win the chapter before it to get here."), 19, WHITE, 5, font_m), 540)
	v.add_child(story)
	var trail := Trail.new()
	trail.custom_minimum_size = Vector2(TRAIL_W, TRAIL_H)
	trail.mouse_filter = Control.MOUSE_FILTER_PASS
	trail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(trail)
	var pts := PackedVector2Array()
	for i in Missions.PER_CHAPTER:
		var n := first + i
		if n > Levels.LAST_LEVEL:
			break
		var at := Vector2(TRAIL[i].x * TRAIL_W, TRAIL[i].y)
		pts.append(at)
		var b := _map_button(n, reached)
		b.position = at - b.custom_minimum_size / 2
		trail.add_child(b)
	trail.points = pts
	trail.reached = clampi(reached - first + 1, 0, Missions.PER_CHAPTER)
	return p


## A mission on the map: its number and goal, and the stars you've won there
func _map_button(n: int, reached: int) -> Button:
	var boss := Levels.is_boss(n)
	var locked := n > reached
	var g := Missions.goal_for(n)
	var b := button("🔒" if locked else str(n), "blue", 34 if not boss else 40)
	var size := 124.0 if boss else 104.0
	b.custom_minimum_size = Vector2(size, size)
	b.size = b.custom_minimum_size
	set_kind(b, "gray" if locked else "yellow" if n == reached else "red" if boss else "white")
	b.disabled = locked
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# The goal's picture in a badge of its colour on the corner, and the stars under it
	var badge := PanelContainer.new()
	var bs := box(Color(UISkin.COLORS[Missions.GOALS[g].color].bottom), Color.WHITE, 22, 3, 2)
	bs.set_content_margin_all(0)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(44, 44)
	badge.position = Vector2(size - 30, -14)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := label("🏰" if boss else Missions.icon(g), 24, WHITE, 0)
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	badge.add_child(ic)
	b.add_child(badge)
	if not locked:
		var st := int(main.save.stars.get(str(n), 0))
		var stars := label("★".repeat(st) + "☆".repeat(3 - st), 24, Color("#ffd23f"), 6)
		stars.add_theme_color_override("font_outline_color", Color("#8a4d00"))
		stars.position = Vector2(0, size - 8)
		stars.size = Vector2(size, 30)
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stars)
	if n == reached:
		# The mission you're on bobs gently
		b.pivot_offset = b.size / 2
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2.ONE * 1.08, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	var level_n := n
	b.pressed.connect(func(): show_brief(level_n, "levels"))
	map_buttons[n] = b
	return b


# ---------- The briefing ----------
## Before a mission: its code name, its goal, and Captain Skye's briefing
func _build_brief() -> void:
	var col := screen("brief")
	var p := panel()
	var v := vbox(14)
	p.add_child(v)
	brief_chapter = label("", 20, WHITE, 6, font_m)
	v.add_child(brief_chapter)
	v.add_child(ribbon("Mission briefing", "orange"))
	brief_title = label("", 40)
	v.add_child(brief_title)
	brief_goal = _pill("")
	brief_goal.add_theme_font_size_override("font_size", 26)
	brief_goal.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(brief_goal.get_parent())
	# Captain Skye's words, in a speech card
	var talk := PanelContainer.new()
	var ts := box(WHITE, INK, 20, 3, 4)
	ts.set_content_margin_all(16)
	talk.add_theme_stylebox_override("panel", ts)
	talk.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	talk.add_child(row)
	var face := PanelContainer.new()
	var fs := box(Color("#cfe9ff"), Color("#3a9df3"), 50, 3, 0)
	fs.set_content_margin_all(0)
	face.add_theme_stylebox_override("panel", fs)
	face.custom_minimum_size = Vector2(100, 100)
	face.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.mouse_filter = Control.MOUSE_FILTER_PASS
	var helmet := label("🪖", 50, WHITE, 0)
	helmet.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	helmet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_child(helmet)
	brief_face = TextureRect.new()
	brief_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brief_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	brief_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(brief_face)
	row.add_child(face)
	var words := vbox(4)
	words.alignment = BoxContainer.ALIGNMENT_BEGIN
	var who := label("Captain Skye", 22, INK, 0)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	words.add_child(who)
	brief_text = wrapped(label("", 22, Color("#24324d"), 0, font_m), 430)
	brief_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	words.add_child(brief_text)
	row.add_child(words)
	v.add_child(talk)
	brief_stars = label("", 40, Color("#ffd23f"), 8)
	brief_stars.add_theme_color_override("font_outline_color", Color("#8a4d00"))
	v.add_child(brief_stars)
	brief_start = button("Start", "yellow", 46, func(): main.start_level(brief_n))
	brief_start.custom_minimum_size = Vector2(400, 100)
	brief_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(brief_start)
	v.add_child(button("Back", "blue", 26, func(): show_screen(brief_from) if brief_from == "levels" else main.open_menu()))
	col.add_child(p)


func show_brief(n: int, from := "menu") -> void:
	brief_n = n
	brief_from = from
	var g := Missions.goal_for(n)
	var c := Missions.chapter_of(n)
	brief_chapter.text = tr("Chapter %d") % c + "  ·  " + Missions.chapter_title(c)
	brief_title.text = Missions.title(n)
	brief_goal.text = Missions.icon(g) + "  " + Missions.goal_name(g) + "  ·  " + tr("Level %d") % n
	brief_goal.get_parent().add_theme_stylebox_override("panel", UISkin.pill(Missions.GOALS[g].color))
	brief_text.text = Missions.brief(n, Levels.data(n).towers.size())
	var st := int(main.save.stars.get(str(n), 0))
	brief_stars.text = "★".repeat(st) + "☆".repeat(3 - st)
	brief_stars.visible = n < int(main.save.level)
	show_screen("brief")
	pop(brief_start, 0.15, 0.6)
	_skye_face()


## Captain Skye's face on the briefing: the cut scenes' portrait of her (a helmet until it's drawn)
func _skye_face() -> void:
	var cut: Cutscene = main.cutscene
	if not cut.portraits.has("skye") and not _drawing_face:
		_drawing_face = true
		cut.portraits["skye"] = await cut._portrait("skye")
		_drawing_face = false
	brief_face.texture = cut.portraits.get("skye")
	brief_face.get_parent().get_child(0).visible = brief_face.texture == null


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
	var row := hbox()
	row.add_child(button("🎨  Looks", "purple", 26, func(): show_screen("looks")))
	row.add_child(back_button())
	col.add_child(row)


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
		"While you drag, a label shows how many soldiers the attack needs and how many you have: green means enough.",
		"In the story, a road to attack sends what it takes and then stops by itself. A road between your own towers runs until you cut it.",
		"Each mission has a goal, shown under the top bar. Win fast for 3 stars.",
		"Stuck? Tap 💡 Hint in a battle: it shows a good move.",
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


## Victory: Captain Skye cheering on a badge with rays turning behind it, the stars, a big
## VICTORY band, your reward, how far you are through this land, and Next level
func _build_win() -> void:
	var col := screen("win", Color(0.04, 0.07, 0.2, 0.66))
	var stars := hbox(8)
	for i in 3:
		var s := label("★", 96 if i == 1 else 76, Color(1, 1, 1, 0.35), 10)
		stars.add_child(s)
		win_stars.append(s)
	col.add_child(stars)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(320, 250)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	win_rays = TextureRect.new()
	win_rays.texture = _rays_texture()
	win_rays.size = Vector2(440, 440)
	win_rays.position = Vector2(-60, -95)
	win_rays.pivot_offset = Vector2(220, 220)
	win_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(win_rays)
	var shield := PanelContainer.new()
	shield.add_theme_stylebox_override("panel", box(Color("#3a9df3"), WHITE, 46, 6, 8))
	shield.position = Vector2(60, 5)
	shield.size = Vector2(200, 220)
	var medal := label("🎖", 110, WHITE, 0)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shield.add_child(medal)
	win_face = TextureRect.new()
	win_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shield.add_child(win_face)
	badge.add_child(shield)
	col.add_child(badge)
	win_ribbon = ribbon("Victory!", ORANGE)
	col.add_child(win_ribbon)
	# The reward, and how far through this land you are
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color("#c9d3f5"), INK, 22, 3, 5))
	p.custom_minimum_size.x = 600
	var v := vbox(10)
	p.add_child(v)
	v.add_child(label("Rewards", 26, Color("#3b4a75"), 0))
	var tile_p := PanelContainer.new()
	tile_p.add_theme_stylebox_override("panel", box(Color("#4cbc45"), Color("#1d6623"), 18, 4, 3))
	tile_p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile_p.custom_minimum_size = Vector2(150, 110)
	win_coins = label("", 34)
	win_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile_p.add_child(win_coins)
	v.add_child(tile_p)
	win_land = label("", 22, Color("#3b4a75"), 0, font_m)
	v.add_child(win_land)
	win_land_bar = ProgressBar.new()
	win_land_bar.show_percentage = false
	win_land_bar.custom_minimum_size = Vector2(420, 24)
	win_land_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	win_land_bar.add_theme_stylebox_override("background", box(Color("#8e9cc7"), INK, 10, 2, 0))
	win_land_bar.add_theme_stylebox_override("fill", box(Color("#4cbc45"), INK, 10, 2, 0))
	v.add_child(win_land_bar)
	win_unlock = wrapped(label("", 22, Color("#7a4b00"), 0, font_m), 540)
	v.add_child(win_unlock)
	win_stats = hbox(10)
	win_stats.visible = false
	v.add_child(win_stats)
	col.add_child(p)
	# Double coins for watching an ad (only shown once ads are switched on, see Services)
	ad_btn = button("📺 Watch an ad: double coins", "yellow", 24, func():
		ad_btn.disabled = true
		Services.show_rewarded(func(watched: bool):
			if watched:
				main.save.coins += _win_coins
				main.write_save()
				win_coins.text = "🪙\n+%d" % (_win_coins * 2)
				main.play_sound("coin")
			ad_btn.visible = false))
	ad_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ad_btn)
	next_btn = button("Next level", "green", 44, func(): show_brief(mini(main.level + 1, Levels.LAST_LEVEL), "win"))
	next_btn.custom_minimum_size = Vector2(420, 100)
	next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(next_btn)
	var row := hbox()
	row.add_child(button("Replay", "blue", 26, func(): main.restart()))
	row.add_child(button("🎬 Watch", "purple", 26, func(): main.watch_replay(0)))
	row.add_child(button("Menu", "blue", 26, func(): main.open_menu()))
	col.add_child(row)


## Rays of light, turning slowly behind the victory badge
func _rays_texture() -> Texture2D:
	return ImageTexture.create_from_image(UISkin._cached("rays", _draw_rays, 256))


func _draw_rays() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0)
			var r := d.length() / (n / 2.0)
			var ray := 0.5 + 0.5 * cos(atan2(d.y, d.x) * 12.0)
			var a := clampf(1.0 - r, 0.0, 1.0) * (0.25 + 0.6 * smoothstep(0.45, 0.6, ray))
			img.set_pixel(x, y, Color(1.0, 0.92, 0.55, a))
	return img


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
	win_coins.text = "🪙\n+0"
	_win_coins = coins
	# How far through this land: the land's five levels, and what comes next
	var n: int = main.level
	var done := (n - 1) % Missions.PER_CHAPTER + 1
	win_land.visible = not main.daily
	win_land_bar.visible = not main.daily
	win_land_bar.max_value = Missions.PER_CHAPTER
	win_land_bar.value = done
	win_land.text = tr("%s: %d of %d") % [Missions.land(n), done, Missions.PER_CHAPTER] if done < Missions.PER_CHAPTER \
		else tr("New land: %s!") % Missions.land(n + 1)
	_win_face()
	var count := create_tween()
	count.tween_interval(0.5)
	count.tween_method(func(v: float):
		win_coins.text = "🪙\n+%d" % roundi(v)
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
	pop(win_face.get_parent(), 0.0, 0.5)


## Captain Skye's face on the victory badge (a medal until it's drawn)
func _win_face() -> void:
	var cut: Cutscene = main.cutscene
	if not cut.portraits.has("skye") and not _drawing_face:
		_drawing_face = true
		cut.portraits["skye"] = await cut._portrait("skye")
		_drawing_face = false
	win_face.texture = cut.portraits.get("skye")


func _build_lose() -> void:
	var col := screen("lose")
	var p := panel()
	var v := vbox(16)
	p.add_child(v)
	lose_ribbon = ribbon("Defeat", Color("#9a8cff"))
	v.add_child(lose_ribbon)
	lose_reason = wrapped(label("Your last building has fallen.", 26, WHITE, 6, font_m), 540)
	v.add_child(lose_reason)
	lose_tip = wrapped(label("", 22, WHITE, 5, font_m), 540)
	v.add_child(lose_tip)
	var r := button("Try again", "yellow", 40, func(): main.restart())
	r.custom_minimum_size = Vector2(400, 90)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	var row := hbox()
	row.add_child(button("Upgrades", "blue", 26, func(): show_screen("shop")))
	row.add_child(button("🎬 Watch", "purple", 26, func(): main.watch_replay(0)))
	row.add_child(button("Menu", "blue", 26, func(): main.open_menu()))
	v.add_child(row)
	col.add_child(p)


func show_lose(tip: String, why := "Your last building has fallen.") -> void:
	hide_hud()
	lose_reason.text = why
	lose_tip.text = tr("Tip: %s") % tr(tip)
	show_screen("lose")
	pop(lose_ribbon, 0.05, 0.3)
