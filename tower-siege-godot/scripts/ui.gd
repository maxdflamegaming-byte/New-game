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
var _win_coins := 0
var lose_tip: Label
var vibrate_btn: Button
var gfx_btns := {}
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


func build() -> void:
	# A Control inside a CanvasLayer doesn't size itself, so follow the window
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	font_b = _font("res://assets/fonts/Fredoka-Bold.ttf")
	font_m = _font("res://assets/fonts/Fredoka-Medium.ttf")
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


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _font(path: String) -> Font:
	var f: FontFile = load(path)
	# Symbols like ★ and emoji come from the phone's own fonts
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji", "Noto Sans Symbols 2", "DejaVu Sans", "sans-serif"])
	f.fallbacks = [fb]
	return f


# ---------- Style ----------
func box(bg: Color, border := INK, radius := 18, width := 3, shadow := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = border
	s.shadow_offset = Vector2(0, shadow)
	s.shadow_size = 0
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
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 8)
	_button_style(t, "Button", PANEL_LIGHT)
	t.set_stylebox("normal", "LineEdit", box(WHITE, INK, 14, 3, 0))
	t.set_stylebox("focus", "LineEdit", box(WHITE, INK, 14, 3, 0))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	t.set_font_size("font_size", "LineEdit", 26)
	return t


func _button_style(t: Theme, type: String, bg: Color) -> void:
	t.set_stylebox("normal", type, box(bg))
	t.set_stylebox("hover", type, box(bg.lightened(0.1)))
	var p := box(bg.darkened(0.06))
	p.shadow_offset = Vector2(0, 1)
	p.content_margin_top = 11
	p.content_margin_bottom = 7
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("disabled", type, box(Color("#a9c6e8")))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())


func button(text: String, kind := "blue", size := 26, on_press := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var bg: Color = {"blue": PANEL_LIGHT, "yellow": YELLOW, "red": RED, "green": GREEN, "white": WHITE}.get(kind, PANEL_LIGHT)
	if kind != "blue":
		b.add_theme_stylebox_override("normal", box(bg))
		b.add_theme_stylebox_override("hover", box(bg.lightened(0.08)))
		var p := box(bg.darkened(0.06))
		p.shadow_offset = Vector2(0, 1)
		b.add_theme_stylebox_override("pressed", p)
	if kind == "yellow":
		b.add_theme_color_override("font_outline_color", Color("#b06a00"))
	elif kind == "red":
		b.add_theme_color_override("font_outline_color", Color("#a3202b"))
	elif kind == "green":
		b.add_theme_color_override("font_outline_color", Color("#2a7a2a"))
	elif kind == "white":
		b.add_theme_color_override("font_color", INK)
		b.add_theme_constant_override("outline_size", 0)
	if on_press.is_valid():
		b.pressed.connect(func():
			main.play_sound("tap")
			on_press.call())
	return b


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


func ribbon(text: String, color := ORANGE) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, INK, 14, 3, 5))
	var l := label(text, 44)
	p.add_child(l)
	p.rotation_degrees = -1.5
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p


func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(PANEL, INK, 26, 4, 6)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 20
	s.content_margin_bottom = 24
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size.x = 600
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


func spacer(h := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func back_button(to := "menu") -> Button:
	return button("Back", "blue", 26, func(): main.open_menu() if to == "menu" else show_screen(to))


func show_screen(id: String) -> void:
	for k in screens:
		screens[k].visible = k == id
	main.screen_open = id
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
	p.add_theme_stylebox_override("panel", box(PANEL, INK, 16, 3, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, 26)
	p.add_child(l)
	return l


func start_hud(title: String, campaign: bool) -> void:
	hud.visible = true
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
	_hud_t -= get_process_delta_time()
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
		r.size_flags_stretch_ratio = maxf(0.001, tot[sd] / sum)
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
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.3)


# ---------- Menu ----------
func _build_menu() -> void:
	var col := screen("menu", Color(0.55, 0.82, 1.0, 0.25))
	var coins_row := hbox()
	coins_row.alignment = BoxContainer.ALIGNMENT_END
	menu_coins = _pill("0")
	coins_row.add_child(menu_coins.get_parent())
	col.add_child(coins_row)
	var t1 := label("TOWER", 120, YELLOW, 18)
	t1.add_theme_constant_override("line_spacing", -30)
	var t2 := label("SIEGE", 120, Color("#ff7ad1"), 18)
	col.add_child(t1)
	col.add_child(t2)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", box(Color(1, 1, 1, 0.88), Color(INK, 0.4), 18, 0, 4))
	tag.add_child(wrapped(label("Drag roads between towers, march your army and take every building on the map.", 22, INK, 0, font_m), 560))
	tag.custom_minimum_size.x = 600
	col.add_child(tag)
	col.add_child(spacer(110))
	play_btn = button("PLAY", "yellow", 52, func(): main.start_level(mini(main.save.level, Levels.LAST_LEVEL)))
	play_btn.custom_minimum_size = Vector2(440, 110)
	play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(play_btn)
	var pvp := button("⚔ PvP", "red", 40, func(): main.net.open_pvp())
	pvp.custom_minimum_size = Vector2(440, 84)
	pvp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(pvp)
	var row0 := hbox(10)
	daily_btn = button("📅 Daily", "green", 24, func(): main.start_daily())
	missions_btn = button("🎁 Missions", "blue", 24, func(): show_screen("missions"))
	row0.add_child(daily_btn)
	row0.add_child(missions_btn)
	row0.add_child(button("🎨 Looks", "blue", 24, func(): show_screen("looks")))
	col.add_child(row0)
	var row := hbox()
	row.add_child(button("Levels", "blue", 28, func(): show_screen("levels")))
	row.add_child(button("Upgrades", "blue", 28, func(): show_screen("shop")))
	col.add_child(row)
	var row2 := hbox()
	row2.add_child(button("🏆 Leaderboard", "blue", 26, func(): main.net.open_board()))
	row2.add_child(button("🛡 Clans", "blue", 26, func(): main.net.open_clans()))
	col.add_child(row2)
	var row3 := hbox()
	row3.add_child(button("⚙ Settings", "blue", 24, func(): show_screen("settings")))
	row3.add_child(button("?", "blue", 26, func(): show_screen("help")))
	col.add_child(row3)


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
		for g in gfx_btns:
			var on: bool = main.save.gfx == g
			gfx_btns[g].add_theme_stylebox_override("normal", box(YELLOW if on else PANEL_LIGHT))
			gfx_btns[g].add_theme_color_override("font_outline_color", Color("#b06a00") if on else INK)


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
			toast("+%d coins!" % coins)
		main.open_menu())
	reward_btn.custom_minimum_size = Vector2(360, 86)
	reward_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(reward_btn)
	col.add_child(p)


func refresh_reward() -> void:
	var next := Progress.streak_next(main.save)
	var ready := Progress.reward_ready(main.save)
	reward_title.text = ("Day %d" % next) if ready else "Collected today. See you tomorrow!"
	for c in reward_days.get_children():
		c.queue_free()
	var got := next - 1 if ready else int(main.save.streak.count)
	for i in Progress.STREAK_COINS.size():
		var today_box: bool = ready and i == next - 1
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", box(YELLOW if today_box else GREEN if i < got else PANEL_LIGHT, INK, 14, 3, 3))
		pc.custom_minimum_size = Vector2(74, 92)
		var vv := vbox(0)
		vv.add_child(label("Day %d" % (i + 1), 15, WHITE, 4))
		vv.add_child(label("✓" if i < got else "●", 26, WHITE, 6))
		vv.add_child(label(str(Progress.STREAK_COINS[i]), 18, WHITE, 5))
		pc.add_child(vv)
		reward_days.add_child(pc)
	reward_btn.text = "Collect %d" % Progress.STREAK_COINS[next - 1] if ready else "Back"


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
		var rb := button("🎁 Collect your daily reward (day %d)" % Progress.streak_next(main.save), "yellow", 24, func(): show_screen("reward"))
		mission_list.add_child(rb)
	mission_streak.text = "Daily reward streak: %d day%s" % [int(main.save.streak.count), "" if int(main.save.streak.count) == 1 else "s"]
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
		var b := button("✓" if m.claimed else "● %d" % int(m.coins), "green" if done and not m.claimed else "blue", 24, func():
			var coins := Progress.claim_mission(main.save, idx)
			if coins > 0:
				main.write_save()
				main.play_sound("coin")
				toast("+%d coins!" % coins)
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
	looks_coins.text = "● %d" % main.save.coins
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
			card.add_child(label(state if owned else "● %d" % item.cost, 20, WHITE, 6))
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
	vibrate_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(vibrate_btn)
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
	col.add_child(p)
	col.add_child(back_button())


func refresh_menu() -> void:
	menu_coins.text = "● %d" % main.save.coins
	play_btn.text = "PLAY  ·  Level %d" % mini(main.save.level, Levels.LAST_LEVEL)
	var n := Progress.claimable(main.save) + (1 if Progress.reward_ready(main.save) else 0)
	missions_btn.text = "🎁 Missions" + (" (%d)" % n if n > 0 else "")
	missions_btn.add_theme_stylebox_override("normal", box(ORANGE if n > 0 else PANEL_LIGHT))
	daily_btn.text = "📅 Daily ✓" if int(main.save.daily_won) == Progress.today() else "📅 Daily"
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
	var colors := {"grass": Color("#4caf3c"), "desert": Color("#d99a3a"), "snow": Color("#4a9fd6"), "beach": Color("#2ec3e0")}
	# The 60 levels, then the endless levels reached so far (in full rows)
	var shown := maxi(Levels.MAX_LEVEL, ceili((int(main.save.level) + 1) / 6.0) * 6)
	for n in range(1, mini(shown, Levels.LAST_LEVEL) + 1):
		var st := int(main.save.stars.get(str(n), 0))
		total += st
		var locked: bool = n > main.save.level
		var b := button("%d\n%s" % [n, "🔒" if locked else "★".repeat(st) + "☆".repeat(3 - st)], "blue", 22)
		b.custom_minimum_size = Vector2(84, 84)
		var bg: Color = YELLOW if n == main.save.level else RED if Levels.is_boss(n) else colors[Levels.theme_for(n)]
		b.add_theme_stylebox_override("normal", box(bg))
		b.disabled = locked
		var level_n := n
		b.pressed.connect(func(): main.start_level(level_n))
		level_grid.add_child(b)
	levels_stars.text = "%d ★ collected" % total


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
			packs.add_child(button("● %d" % Services.COIN_PACKS[pk], "yellow", 24, func():
				Services.buy(pk, func(ok: bool):
					if ok:
						main.save.coins += Services.COIN_PACKS[pk]
						main.write_save()
						refresh_shop())))
		col.add_child(packs)
	col.add_child(back_button())


func refresh_shop() -> void:
	shop_coins.text = "● %d" % main.save.coins
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
		var b := button("MAX" if maxed else "● %d" % cost, "green", 24, func():
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
	v.add_child(ribbon("Victory!", ORANGE))
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
				win_coins.text = "● +%d" % (_win_coins * 2)
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
	win_coins.text = "● +%d" % coins
	_win_coins = coins
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


func _build_lose() -> void:
	var col := screen("lose")
	var p := panel()
	var v := vbox(16)
	p.add_child(v)
	v.add_child(ribbon("Defeat", Color("#9a8cff")))
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
	lose_tip.text = "Tip: " + tip
	show_screen("lose")
