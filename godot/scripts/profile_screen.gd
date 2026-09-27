extends MenuScreen
## You: your name, level, stats and trophies.

var info: Label
var avatar: Control
var name_edit: LineEdit


func build(main) -> void:
	frame(main, "PROFILE")


func refresh() -> void:
	super()
	clear()
	var p = m.prog
	# Your square, name and level
	var top := card(false)
	avatar = Control.new()
	avatar.custom_minimum_size = Vector2(170, 150)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.draw.connect(_draw_avatar)
	top.add_child(avatar)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	top.add_child(right)
	name_edit = LineEdit.new()
	name_edit.text = m.player_name
	name_edit.max_length = 12
	name_edit.placeholder_text = "Your name"
	name_edit.add_theme_font_override("font", m.font)
	name_edit.add_theme_font_size_override("font_size", 34)
	name_edit.add_theme_color_override("font_color", m.INK)
	var st: StyleBoxFlat = m._style(Color(0.12, 0.15, 0.27, 0.06), 16)
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	name_edit.add_theme_stylebox_override("normal", st)
	name_edit.add_theme_stylebox_override("focus", m._style(Color(1, 0.76, 0.2, 0.18), 16))
	name_edit.text_submitted.connect(func(_t): name_edit.release_focus())
	name_edit.focus_exited.connect(_save_name)
	right.add_child(name_edit)
	var lv: Label = m._label("Level %d" % p.level, 30, Color("#6a57b8"))
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(lv)
	right.add_child(bar(float(p.xp) / Progress.need(p.level), Color("#8d7bd6"), 18))
	var xl: Label = m._label("%d / %d XP to level %d" % [p.xp, Progress.need(p.level), p.level + 1], 22, m.MUTED, 0, m.INK, m.font_med)
	xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(xl)

	heading("STATS")
	var s: Dictionary = p.stats
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 8)
	card().add_child(grid)
	var hours := int(s.time) / 3600
	var mins := (int(s.time) % 3600) / 60
	var rows := [
		["Games", str(s.games)], ["Wins", str(s.wins)],
		["Knockouts", str(s.kos)], ["Best claim", "%.1f%%" % s.best_pct],
		["Biggest loop", "%.1f%%" % s.best_loop], ["Time played", "%dh %02dm" % [hours, mins] if hours else "%dm" % mins],
		["Power-ups", str(s.powerups)], ["Coins picked up", str(s.coins)],
		["Bosses beaten", str(s.king_wins + s.queen_wins + s.wizard_wins)], ["Best streak", "%d day%s" % [p.streak, "" if p.streak == 1 else "s"]],
	]
	for r in rows:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var a: Label = m._label(r[0], 24, m.MUTED, 0, m.INK, m.font_med)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(a)
		cell.add_child(m._label(r[1], 26, m.INK))
		grid.add_child(cell)

	heading("TROPHIES  %d / %d" % [p.trophies.size(), Progress.TROPHIES.size()])
	info = m._label("Tap a trophy to see how to get it. Each one pays %d coins." % Progress.TROPHY_COINS, 22, Color(1, 1, 1, 0.8), 0, m.INK, m.font_med)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)
	var tg := GridContainer.new()
	tg.columns = 4
	tg.add_theme_constant_override("h_separation", 10)
	tg.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.add_child(tg)
	body.add_child(center)
	for id in Progress.TROPHIES:
		var d: Dictionary = Progress.TROPHIES[id]
		var have: bool = p.trophies.has(id)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 150)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		var bs: StyleBoxFlat = m._style(Color(1, 1, 1, 0.95) if have else Color(1, 1, 1, 0.12), 22, 6,
				Color("#e0a800") if have else Color(1, 1, 1, 0.06))
		for k in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(k, bs)
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 4)
		b.add_child(v)
		var ic := icon(Art.TROPHY, 64, Color("#ffc233") if have else Color(1, 1, 1, 0.3))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var nl: Label = m._label(d.name, 20, m.INK if have else Color(1, 1, 1, 0.6))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 140
		v.add_child(nl)
		b.pressed.connect(func():
			m.sfx.play("tap")
			info.text = "%s: %s%s" % [d.name, d.desc, "  (You have it!)" if have else ""])
		tg.add_child(b)


func _save_name() -> void:
	var n := name_edit.text.strip_edges()
	m.player_name = n if n != "" else "You"
	name_edit.text = m.player_name
	m._save()


func _process(_dt: float) -> void:
	if visible and is_instance_valid(avatar):
		avatar.queue_redraw()


func _draw_avatar() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var color: Color = m.world.COLORS[m.my_color]
	var mid := Vector2(avatar.size.x / 2 - 10, avatar.size.y / 2 + 6)
	avatar.draw_set_transform(mid + Vector2(0, 46), 0, Vector2(1, 0.3))
	avatar.draw_circle(Vector2.ZERO, 50, Color(0.06, 0.08, 0.16, 0.15), true, -1, true)
	Cosmetics.draw_square(avatar, mid + Vector2(0, sin(t * 3.0) * 3), 92, color, color.darkened(0.3), m.equipped.skin,
			Vector2.from_angle(sin(t * 0.7) * 1.4), t, 0.0, 0.0, fmod(t, 3.2) < 0.12)
	if m.equipped.pet != "none":
		Cosmetics.draw_pet(avatar, mid + Vector2(62, 22), 48, m.equipped.pet, color, t, -1.0)
