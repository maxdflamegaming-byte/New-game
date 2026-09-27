extends MenuScreen
## Graphics, sound, music, vibration and joystick size, plus the tutorial.


func build(main) -> void:
	frame(main, "SETTINGS")


func refresh() -> void:
	super()
	clear()
	heading("LANGUAGE")
	var box := card()
	var codes: Array = I18n.LANGS.keys()
	_choice(box, "", codes.map(func(c): return I18n.LANGS[c] if c != "" else tr("Auto")), codes.find(I18n.lang), func(i):
		I18n.lang = codes[i]
		I18n.apply()
		m._refresh_menu())
	heading("GRAPHICS")
	box = card()
	_choice(box, "Quality", Gfx.LEVELS, Gfx.level, func(i):
		Gfx.level = i
		m._apply_gfx())
	var labels := Gfx.FPS.map(func(f): return "%d FPS" % f)
	_choice(box, "Frame rate", labels, Gfx.FPS.find(Gfx.fps), func(i):
		Gfx.fps = Gfx.FPS[i]
		m._apply_gfx())
	_toggle(box, "Show FPS", Gfx.show_fps, func():
		Gfx.show_fps = not Gfx.show_fps
		m._apply_gfx())
	var hz := Gfx.screen_hz()
	var about_gfx: Label = m._label(tr(["Low: 720p and fewer effects, for older phones.", "Medium: full resolution, lighter effects.",
			"High: full resolution, all effects, smoother edges.", "Ultra: sharpest edges, extra glow and sparkle."][Gfx.level])
			+ ("  " + tr("Your screen is running at %d Hz.") % hz if hz > 0 else "")
			+ ("  " + tr("90 and 120 FPS need a 90 or 120 Hz screen, and use more battery.") if Gfx.fps > 60 else ""),
			22, m.MUTED, 0, m.INK, m.font_med)
	about_gfx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(about_gfx)
	heading("SOUND")
	box = card()
	_toggle(box, "Sound effects", not m.sfx.muted, func():
		m.sfx.muted = not m.sfx.muted)
	_toggle(box, "Music", m.music.enabled, func():
		m.music.set_enabled(not m.music.enabled))
	heading("CONTROLS")
	box = card()
	_toggle(box, "Vibration", m.vibration, func():
		m.vibration = not m.vibration
		m._vibrate(60))
	_choice(box, "Steering", ["Joystick", "Tap to turn"], 1 if m.controls == "tap" else 0, func(i):
		m.controls = "tap" if i == 1 else "stick")
	if m.controls == "stick":
		_choice(box, "Joystick size", ["Normal", "Large"], 1 if m.big_stick else 0, func(i):
			m.big_stick = i == 1)
	var how := "Drag anywhere on the screen to steer." if m.controls == "stick" \
		else "Hold the left or right side of the screen to turn; let go to go straight. (2 Players always uses joysticks.)"
	var hint: Label = m._label(tr(how) + " " + tr("On a keyboard: arrows or WASD, P to pause."), 22, m.MUTED, 0, m.INK, m.font_med)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	heading("ACCESSIBILITY")
	box = card()
	_toggle(box, "Colourblind patterns", Patterns.on, func():
		Patterns.on = not Patterns.on
		m.view._land_version = -1) # redraw the land with (or without) patterns
	var cb: Label = m._label("Every player's land, trail and square also gets its own pattern, so you can tell them apart without colour.", 22, m.MUTED, 0, m.INK, m.font_med)
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(cb)
	heading("LEARN")
	box = card()
	var t: Label = m._label("New to Color Claim? The tutorial teaches you in 5 quick steps.", 24, m.INK, 0, m.INK, m.font_med)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var play: Button = m._button("Play the tutorial", m.YELLOW, Color("#5a3200"), Color("#d27a06"), 32)
	play.custom_minimum_size = Vector2(0, 90)
	play.pressed.connect(func():
		visible = false
		m.start_tutorial())
	box.add_child(play)
	var about: Label = m._label("Color Claim HD · made with Godot", 20, Color(1, 1, 1, 0.5), 0, m.INK, m.font_med)
	body.add_child(about)


## A row with a name and an On/Off switch
func _toggle(box: BoxContainer, text: String, on: bool, flip: Callable) -> void:
	_choice(box, text, ["Off", "On"], 1 if on else 0, func(_i): flip.call())


## A row with a name and a set of buttons, one of them picked (more than 2 buttons go on a
## row of their own under the name)
func _choice(box: BoxContainer, text: String, options: Array, picked: int, pick: Callable) -> void:
	var row: Container = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var l: Label = m._label(text, 28, m.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	# More than two choices, or two long ones, go on a row of their own under the name
	var wide := options.size() > 2 or "".join(options).length() > 16
	if text == "":
		row.visible = false
	if options.size() > 4:
		# Lots of choices: they wrap onto as many rows as they need
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		box.add_child(flow)
		row = flow
		wide = false
	elif wide:
		row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
	for i in options.size():
		var on := i == picked
		var b := Button.new()
		b.text = options[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 64)
		if wide:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", m.font)
		b.add_theme_font_size_override("font_size", 26)
		var st: StyleBoxFlat = m._style(m.YELLOW if on else Color(0.12, 0.15, 0.27, 0.08), 18)
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		for k in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color("#5a3200") if on else m.MUTED)
		b.pressed.connect(func():
			if i == picked:
				return
			m.sfx.play("tap")
			pick.call(i)
			m._save()
			refresh.call_deferred())
		row.add_child(b)
