extends MenuScreen
## Today's 3 missions with their progress, and the daily streak.


func build(main) -> void:
	frame(main, "MISSIONS")


func refresh() -> void:
	super()
	clear()
	var today: String = m.world.today()
	m.prog.ensure_day(today)
	heading("TODAY'S MISSIONS")
	for mi in m.prog.missions:
		var d: Dictionary = Progress.MISSIONS[mi.id]
		var row := card(false)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 6)
		row.add_child(left)
		var t: Label = m._label(d.text, 28, m.INK)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		left.add_child(t)
		left.add_child(bar(mi.progress / float(d.goal), Color("#2ec48a") if mi.done else m.YELLOW))
		var amount := "%s / %s" % [_amount(mi.progress, d), _amount(d.goal, d)]
		var p: Label = m._label(amount, 22, m.MUTED, 0, m.INK, m.font_med)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		left.add_child(p)
		var right := VBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		right.custom_minimum_size.x = 110
		row.add_child(right)
		if mi.done:
			right.add_child(icon(Art.CHECK, 52))
			right.add_child(m._label("Done", 24, Color("#2a9d5c")))
		else:
			var r := HBoxContainer.new()
			r.alignment = BoxContainer.ALIGNMENT_CENTER
			r.add_theme_constant_override("separation", 4)
			r.add_child(icon(Art.COIN, 30))
			r.add_child(m._label("+%d" % d.reward, 28, Color("#b07800")))
			right.add_child(r)
	var clock := Time.get_time_dict_from_system()
	var left_s: int = 86400 - (clock.hour * 3600 + clock.minute * 60 + clock.second)
	var soon: Label = m._label("New missions in %dh %02dm  ·  they pay out as soon as you finish them" % [left_s / 3600, (left_s % 3600) / 60],
			22, Color(1, 1, 1, 0.7), 0, m.INK, m.font_med)
	soon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(soon)

	heading("DAILY STREAK")
	var box := card()
	var played_today: bool = m.prog.streak_day == today
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) - 86400)
	var alive: bool = played_today or m.prog.streak_day == yesterday
	var streak: int = m.prog.streak if alive else 0
	var days := HBoxContainer.new()
	days.alignment = BoxContainer.ALIGNMENT_CENTER
	days.add_theme_constant_override("separation", 6)
	box.add_child(days)
	# Where the week of 7 starts (after day 7 it keeps paying 100 a day)
	var shown := streak if played_today else streak + 1
	var start := maxi(0, shown - 7)
	for k in 7:
		var n := start + k + 1
		var coins: int = Progress.STREAK_COINS[n - 1] if n <= Progress.STREAK_COINS.size() else 100
		days.add_child(_day(n, coins, n <= streak, n == shown and not played_today))
	var msg := "Today's bonus is collected. Come back tomorrow for day %d!" % (streak + 1) if played_today \
		else "Play a game today for the day %d bonus!" % (streak + 1)
	var ml: Label = m._label(msg, 24, m.INK, 0, m.INK, m.font_med)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ml)


func _amount(v: float, d: Dictionary) -> String:
	if d.get("time", false):
		return "%d:%02d" % [int(v) / 60, int(v) % 60]
	return str(int(v))


## One day of the streak: a flame when done, a ring around the next one
func _day(n: int, coins: int, done: bool, next: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(84, 118)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flame := Art.tex(Art.FLAME, 64)
	var coin := Art.tex(Art.COIN, 64)
	var font: Font = m.font
	c.draw.connect(func():
		var mid := Vector2(c.size.x / 2, 38)
		c.draw_circle(mid, 34, Color("#fff1d6") if done else Color(0.12, 0.15, 0.27, 0.08), true, -1, true)
		if next:
			c.draw_arc(mid, 34, 0, TAU, 48, m.YELLOW, 5.0, true)
		if done:
			c.draw_texture_rect(flame, Rect2(mid - Vector2(22, 24), Vector2(44, 44)), false)
		else:
			c.draw_string(font, mid + Vector2(-40, 10), str(n), HORIZONTAL_ALIGNMENT_CENTER, 80, 30, m.MUTED)
		c.draw_texture_rect(coin, Rect2(Vector2(c.size.x / 2 - 34, 86), Vector2(22, 22)), false)
		c.draw_string(font, Vector2(c.size.x / 2 - 10, 106), str(coins), HORIZONTAL_ALIGNMENT_LEFT, 60, 22, Color("#b07800")))
	return c
