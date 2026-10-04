class_name OnlineScreens
extends RefCounted
## The online screens: PvP (find a match, a friend's room code, 2 players on one phone,
## practice), searching, the VS card, the match result, the leaderboard and clans.
## Built with ui.gd's helpers, in the same style.

const EMBLEMS := ["🦁", "🐺", "🦅", "🐉", "🦈", "🐻", "⚡", "🔥", "❄️", "🌟", "🚀", "🛡️", "⚔️", "👑", "🍀", "💎"]
const CLAN_COLORS := ["#3d9bff", "#ff5257", "#ffc21f", "#45d35a", "#a66bff", "#ff8a3d", "#2ec3e0", "#ff6fb5"]
const CLAN_SIZE := 25

var net
var main
var ui

# PvP screen
var name_edit: LineEdit
var trophies_l: Label
var league_l: Label
var clan_btn: Button
var avatar_box: PanelContainer
var pvp_status: Label
var code_edit: LineEdit
# Waiting
var wait_l: Label
var wait_code: Label
var wait_time: Label
var wait_practice: Button
var _wait_started := 0
var _wait_room := false
# VS and the result
var vs_row: HBoxContainer
var end_title: Label
var end_ribbon: PanelContainer
var end_why: Label
var end_trophies: Label
var end_league: Label
var again_btn: Button
# Leaderboard
var board_tab := "players"
var board_data := {}
var board_list: VBoxContainer
var board_me: Label
var board_status: Label
var tab_btns := {}
# Clans
var clan_browse: VBoxContainer
var clan_mine: VBoxContainer
var clan_name: LineEdit
var clan_tag: LineEdit
var clan_search: LineEdit
var clan_list: VBoxContainer
var clan_head: HBoxContainer
var clan_members: VBoxContainer
var clan_join: Button
var clan_leave: Button
var clan_back: Button
var clans_status: Label
var emblem_row: HFlowContainer
var color_row: HBoxContainer
var preview: PanelContainer
var clan_view := {}
var new_clan := {"emblem": EMBLEMS[0], "color": CLAN_COLORS[0]}


func build() -> void:
	_build_pvp()
	_build_wait()
	_build_vs()
	_build_end()
	_build_board()
	_build_clans()


func _timer_tick() -> void:
	while main.screen_open == "pvp-wait":
		var s := (Time.get_ticks_msec() - _wait_started) / 1000
		wait_time.text = "%d:%02d" % [s / 60, s % 60]
		# Nobody around? Offer a practice match (it's a bot, and it says so)
		if s >= 10 and not _wait_room:
			wait_practice.visible = true
		await main.get_tree().create_timer(0.5).timeout


func avatar(name: String, color: Color, size := 64) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ui.box(color, UI.INK, 16, 3, 3))
	p.custom_minimum_size = Vector2(size, size)
	var l: Label = ui.label(name.strip_edges().substr(0, 1).to_upper() if name != "" else "?", int(size * 0.55))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func emblem(e: String, color: String, size := 64) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ui.box(Color(color), UI.INK, 16, 3, 3))
	p.custom_minimum_size = Vector2(size, size)
	var l: Label = ui.label(e, int(size * 0.5), Color.WHITE, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _edit(placeholder: String, max_len: int, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(width, 56)
	e.add_theme_font_override("font", ui.font_b)
	return e


func _row(left: Control, middle: String, sub: String, right: String, me := false, data := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ui.box(Color("#fff6c8") if me else Color(1, 1, 1, 0.93), UI.YELLOW_DARK if me else Color(UI.INK, 0.35), 14, 3, 0))
	p.custom_minimum_size.x = 600
	var h: HBoxContainer = ui.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_child(left)
	var v: VBoxContainer = ui.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n: Label = ui.label(middle, 24, UI.INK, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	n.clip_text = true
	v.add_child(n)
	if sub != "":
		var s: Label = ui.label(sub, 16, Color("#6b7fa6"), 0, ui.font_m)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(s)
	h.add_child(v)
	h.add_child(ui.label(right, 24, UI.INK, 0))
	p.add_child(h)
	if data != "":
		p.set_meta("clan", data)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				show_clan(data))
	return p


func _rank(i: int) -> Control:
	return ui.label(["🥇", "🥈", "🥉"][i] if i < 3 else str(i + 1), 26, UI.INK, 0)


# ---------- PvP ----------
func _build_pvp() -> void:
	var col: VBoxContainer = ui.screen("pvp")
	col.add_child(ui.ribbon("PvP"))
	var p: PanelContainer = ui.panel()
	var v: VBoxContainer = ui.vbox(16)
	p.add_child(v)
	var me: HBoxContainer = ui.hbox(12)
	avatar_box = PanelContainer.new()
	me.add_child(avatar_box)
	var who: VBoxContainer = ui.vbox(4)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit = _edit("Your name", 16, 260)
	name_edit.text_submitted.connect(func(_t): _rename())
	name_edit.focus_exited.connect(_rename)
	who.add_child(name_edit)
	var tags: HBoxContainer = ui.hbox(8)
	tags.alignment = BoxContainer.ALIGNMENT_BEGIN
	league_l = ui.label("", 16, UI.INK, 0)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", ui.box(Color("#e0965a"), UI.INK, 10, 2, 0))
	lp.add_child(league_l)
	lp.name = "league"
	tags.add_child(lp)
	clan_btn = ui.button("No clan yet", "white", 16, func(): open_clans())
	tags.add_child(clan_btn)
	who.add_child(tags)
	me.add_child(who)
	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", ui.box(Color.WHITE, UI.INK, 14, 3, 0))
	trophies_l = ui.label("🏆 0", 26, UI.INK, 0)
	tp.add_child(trophies_l)
	me.add_child(tp)
	v.add_child(me)
	var find: Button = ui.button("FIND OPPONENT", "yellow", 40, func(): net.find_match())
	find.custom_minimum_size.y = 90
	v.add_child(find)
	var room: HBoxContainer = ui.hbox(10)
	room.add_child(ui.button("Create room", "blue", 22, func(): net.find_match("create")))
	code_edit = _edit("CODE", 4, 130)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room.add_child(code_edit)
	room.add_child(ui.button("Join", "blue", 22, func():
		var code := code_edit.text.to_upper().strip_edges()
		if code.length() != 4:
			pvp_status.text = "A room code has 4 letters."
		else:
			net.find_match(code)))
	v.add_child(room)
	var modes: HBoxContainer = ui.hbox(10)
	modes.add_child(ui.button("👥 2 players, 1 phone", "blue", 20, func(): net.start_pvp("duo", randi() % 1000000000)))
	modes.add_child(ui.button("🤖 Practice vs bot", "blue", 20, func(): net.start_pvp("practice", randi() % 1000000000)))
	v.add_child(modes)
	pvp_status = ui.wrapped(ui.label("", 20, Color("#fff3a0"), 5), 540)
	v.add_child(pvp_status)
	v.add_child(ui.wrapped(ui.label("Online: win +30 🏆, lose −15 🏆. No upgrades or abilities in PvP, everyone starts equal. Matches last up to 3 minutes.", 17, Color.WHITE, 4, ui.font_m), 540))
	col.add_child(p)
	var bottom: HBoxContainer = ui.hbox(12)
	bottom.add_child(ui.back_button())
	bottom.add_child(ui.button("? How PvP works", "blue", 24, func(): ui.show_screen("pvp-help")))
	col.add_child(bottom)
	_build_help()


## The first time you open PvP: how it works, in a few cards
func _build_help() -> void:
	var col: VBoxContainer = ui.screen("pvp-help")
	col.add_child(ui.ribbon("How PvP works", UI.RED))
	for card in [
		["🔵", "You're always blue, at the bottom. Your opponent is red, at the top: their phone shows it the other way round."],
		["⚔", "Take every enemy building, or have the bigger army when the 3 minutes are up."],
		["⚖", "Everyone starts equal: no upgrades, abilities or bosses in PvP."],
		["🏆", "Win +30 trophies and 20 coins, lose −15 trophies. Climb from Bronze to Diamond league."],
		["📶", "If a connection drops, the match waits up to 15 seconds for that player to come back."],
		["🤖", "Nobody online? Practice against a bot, or play with a friend on one phone."],
	]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", ui.box(Color.WHITE, UI.INK, 16, 3, 0))
		var h: HBoxContainer = ui.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.add_child(ui.label(card[0], 40, UI.INK, 0))
		var l: Label = ui.wrapped(ui.label(card[1], 21, UI.INK, 0, ui.font_m), 500)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(l)
		pc.add_child(h)
		col.add_child(pc)
	var go: Button = ui.button("Got it!", "yellow", 34, func(): open_pvp(""))
	go.custom_minimum_size = Vector2(320, 80)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(go)


func _rename() -> void:
	var name := ""
	var rx := RegEx.create_from_string("[^\\p{L}\\p{N} _.-]")
	name = rx.sub(name_edit.text, "", true).strip_edges().substr(0, 16)
	if name != "" and name != main.save.name:
		main.save.name = name
		main.write_save()
		net.send({"t": "name", "name": name})
	refresh_pvp_card()


func refresh_pvp_card() -> void:
	if main.save.name == "":
		main.save.name = "Commander%d" % (100 + randi() % 900)
		main.write_save()
	name_edit.text = main.save.name
	var lg := Net.league_of(int(main.save.trophies))
	trophies_l.text = "🏆 %d" % int(main.save.trophies)
	league_l.text = "%s league · %d wins" % [lg.name, int(main.save.pvp_wins)]
	var lp: PanelContainer = league_l.get_parent()
	lp.add_theme_stylebox_override("panel", ui.box(lg.color, UI.INK, 10, 2, 0))
	var c = main.save.clan
	clan_btn.text = "%s %s [%s]" % [c.emblem, c.name, c.tag] if c is Dictionary else "No clan yet"
	for ch in avatar_box.get_children():
		ch.queue_free()
	avatar_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	avatar_box.add_child(avatar(main.save.name, main.SIDES[1].color))


func open_pvp(status: String) -> void:
	refresh_pvp_card()
	pvp_status.text = status
	ui.show_screen("pvp")


# ---------- Waiting ----------
func _build_wait() -> void:
	var col: VBoxContainer = ui.screen("pvp-wait")
	col.add_child(ui.ribbon("Searching"))
	col.add_child(ui.spacer(20))
	var spin: Label = ui.label("⏳", 80, Color.WHITE, 0)
	col.add_child(spin)
	wait_l = ui.wrapped(ui.label("Connecting…", 26), 560)
	col.add_child(wait_l)
	wait_code = ui.label("", 80, UI.INK, 0)
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", ui.box(Color.WHITE, UI.INK, 20, 4, 5))
	cp.add_child(wait_code)
	cp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(cp)
	wait_time = ui.label("0:00", 24)
	col.add_child(wait_time)
	wait_practice = ui.button("🤖 Practice vs a bot while you wait", "blue", 22, func():
		net.send({"t": "cancel"})
		net.start_pvp("practice", randi() % 1000000000))
	col.add_child(wait_practice)
	col.add_child(ui.button("Cancel", "blue", 26, func(): net.cancel_find()))


func show_wait(room: bool) -> void:
	_wait_room = room
	_wait_started = Time.get_ticks_msec()
	wait_l.text = "Connecting…"
	wait_code.get_parent().visible = false
	wait_practice.visible = false
	ui.show_screen("pvp-wait")
	_timer_tick()


func wait_text(t: String) -> void:
	wait_l.text = t


func show_code(code: String) -> void:
	wait_code.text = code
	wait_code.get_parent().visible = true


# ---------- VS ----------
func _build_vs() -> void:
	var col: VBoxContainer = ui.screen("pvp-vs")
	col.add_child(ui.spacer(300))
	vs_row = ui.hbox(14)
	col.add_child(vs_row)


func _vs_card(p: Dictionary, side: int) -> Control:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", ui.box(main.SIDES[side].color, main.SIDES[side].dark, 22, 4, 6))
	c.custom_minimum_size = Vector2(250, 280)
	var v: VBoxContainer = ui.vbox(8)
	var a := avatar(p.get("name", "?"), main.SIDES[side].light, 96)
	a.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(a)
	var tag: String = p.get("tag", "")
	v.add_child(ui.label(("[%s] " % tag if tag != "" else "") + str(p.get("name", "Player")), 26))
	var tr := int(p.get("trophies", 0))
	v.add_child(ui.label("🏆 %d · %s" % [tr, Net.league_of(tr).name], 18, Color.WHITE, 5, ui.font_m))
	c.add_child(v)
	return c


func show_vs(then: Callable) -> void:
	for c in vs_row.get_children():
		c.queue_free()
	var me := {"name": main.save.name, "trophies": int(main.save.trophies), "tag": main.save.clan.tag if main.save.clan is Dictionary else ""}
	vs_row.add_child(_vs_card(me, 1))
	vs_row.add_child(ui.label("VS", 70, UI.YELLOW, 14))
	vs_row.add_child(_vs_card(net.opp, 2))
	ui.show_screen("pvp-vs")
	main.play_sound("go")
	await main.get_tree().create_timer(2.2).timeout
	if main.screen_open == "pvp-vs":
		then.call()


# ---------- The result ----------
func _build_end() -> void:
	var col: VBoxContainer = ui.screen("pvp-end")
	var p: PanelContainer = ui.panel()
	var v: VBoxContainer = ui.vbox(16)
	p.add_child(v)
	end_ribbon = ui.ribbon("Victory!")
	end_title = end_ribbon.get_child(0)
	v.add_child(end_ribbon)
	end_why = ui.wrapped(ui.label("", 24, Color.WHITE, 6, ui.font_m), 540)
	v.add_child(end_why)
	end_trophies = ui.label("", 40)
	v.add_child(end_trophies)
	end_league = ui.label("", 20, Color.WHITE, 5, ui.font_m)
	v.add_child(end_league)
	again_btn = ui.button("Play again", "yellow", 36, func(): net.restart())
	again_btn.custom_minimum_size = Vector2(420, 86)
	again_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(again_btn)
	var row: HBoxContainer = ui.hbox()
	row.add_child(ui.button("PvP", "blue", 26, func():
		if main.mode == "online":
			net.leave()
		open_pvp("")))
	row.add_child(ui.button("Menu", "blue", 26, func(): main.quit_to_menu()))
	v.add_child(row)
	col.add_child(p)


func show_end(winner: int, why: String) -> void:
	var mode: String = main.mode
	var text := ""
	if mode == "duo":
		text = "Blue wins!" if winner == 1 else "Red wins!" if winner == 2 else "Draw!"
	else:
		text = "Victory!" if winner == 1 else "Draw!" if winner == 0 else "Disconnected" if winner < 0 else "Defeat"
	end_title.text = text
	var color: Color = UI.ORANGE if (winner == 1 or (mode == "duo" and winner != 2)) else UI.RED if mode == "duo" else Color("#9a8cff")
	end_ribbon.add_theme_stylebox_override("panel", ui.box(color, UI.INK, 14, 3, 5))
	end_why.text = {"time": "Time's up! The bigger army wins.", "left": "Your opponent left the match.",
		"lost": "The connection to the server was lost. No trophies were lost."}.get(why,
		"Every enemy building taken!" if winner == 1 or mode == "duo" else "Your last building has fallen.")
	again_btn.text = "Find a new match" if mode == "online" else "Play again"
	main.ui.hide_hud()
	ui.show_screen("pvp-end")
	show_trophy_change()


func show_trophy_change() -> void:
	if net.pvp.is_empty():
		return
	var online: bool = main.mode == "online" and int(net.pvp.winner if net.pvp.winner != null else -1) >= 0
	end_trophies.visible = online
	var d = net.pvp.result
	if online:
		if d == null:
			end_trophies.text = "🏆 …"
		else:
			end_trophies.text = "🏆 %s%d   (%d total)" % ["+" if d >= 0 else "", d, int(main.save.trophies)] + ("   ● +20" if d > 0 else "")
	end_league.text = "%s league" % Net.league_of(int(main.save.trophies)).name if main.mode == "online" else "Practice matches don't change your trophies" if main.mode == "practice" else ""


# ---------- Leaderboard ----------
func _build_board() -> void:
	var col: VBoxContainer = ui.screen("board")
	col.add_child(ui.ribbon("Leaderboard"))
	var p: PanelContainer = ui.panel()
	var v: VBoxContainer = ui.vbox(12)
	p.add_child(v)
	var tabs: HBoxContainer = ui.hbox(8)
	for id in ["players", "clans"]:
		var b: Button = ui.button(id.capitalize(), "blue", 24, func():
			board_tab = id
			render_board())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btns[id] = b
		tabs.add_child(b)
	v.add_child(tabs)
	board_list = ui.vbox(8)
	v.add_child(board_list)
	board_me = ui.label("", 20, Color.WHITE, 5, ui.font_m)
	v.add_child(board_me)
	board_status = ui.wrapped(ui.label("", 20, Color("#fff3a0"), 5), 540)
	v.add_child(board_status)
	col.add_child(p)
	col.add_child(ui.back_button())


func open_board() -> void:
	board_data = {}
	ui.show_screen("board")
	render_board()
	board_status.text = "Connecting…"
	var err: String = await net.go_online(func(s): board_status.text = s)
	if err != "":
		board_status.text = "Can't reach the server right now. Try again in a little while." if err == "down" else "This version of the game is too old for the server. Please update it."
		return
	board_status.text = ""
	var res: Dictionary = await net.request({"t": "top"}, ["top"])
	if res.t == "clanerr":
		board_status.text = res.msg
		return
	board_data = res
	render_board()


func render_board() -> void:
	for id in tab_btns:
		tab_btns[id].add_theme_stylebox_override("normal", ui.box(UI.YELLOW if id == board_tab else UI.PANEL_LIGHT))
	for c in board_list.get_children():
		c.queue_free()
	if board_data.is_empty():
		board_me.text = ""
		return
	if board_tab == "players":
		var players: Array = board_data.players
		var shown_me := false
		for i in players.size():
			var pl: Dictionary = players[i]
			var me: bool = pl.id == main.save.pid
			shown_me = shown_me or me
			var left: HBoxContainer = ui.hbox(8)
			left.add_child(_rank(i))
			left.add_child(avatar(pl.name, main.SIDES[1 if me else 2].color, 48))
			board_list.add_child(_row(left, ("[%s] " % pl.tag if pl.tag != "" else "") + pl.name, "", "🏆 %d" % int(pl.trophies), me))
		if not shown_me:
			var left: HBoxContainer = ui.hbox(8)
			left.add_child(ui.label(str(int(board_data.rank)) if int(board_data.rank) > 0 else "–", 24, UI.INK, 0))
			left.add_child(avatar(main.save.name, main.SIDES[1].color, 48))
			board_list.add_child(_row(left, main.save.name, "", "🏆 %d" % int(main.save.trophies), true))
		if players.is_empty():
			board_list.add_child(ui.label("No one has played online yet. Be the first!", 22))
	else:
		var clans: Array = board_data.clans
		for i in clans.size():
			var c: Dictionary = clans[i]
			var left: HBoxContainer = ui.hbox(8)
			left.add_child(_rank(i))
			left.add_child(emblem(c.emblem, c.color, 48))
			var mine: bool = main.save.clan is Dictionary and main.save.clan.id == c.id
			board_list.add_child(_row(left, "%s [%s]" % [c.name, c.tag], "%d/%d members" % [int(c.members), CLAN_SIZE], "🏆 %d" % int(c.trophies), mine, c.id))
		if clans.is_empty():
			board_list.add_child(ui.label("No clans yet. Start one!", 22))
	var rank := int(board_data.get("rank", 0))
	board_me.text = "Your rank: %s · 🏆 %d · %s" % [str(rank) if rank > 0 else "–", int(main.save.trophies), Net.league_of(int(main.save.trophies)).name]


# ---------- Clans ----------
func _build_clans() -> void:
	var col: VBoxContainer = ui.screen("clans")
	col.add_child(ui.ribbon("Clans"))
	var p: PanelContainer = ui.panel()
	var v: VBoxContainer = ui.vbox(12)
	p.add_child(v)
	clan_browse = ui.vbox(12)
	var h1: Label = ui.label("Start a clan", 26)
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	clan_browse.add_child(h1)
	var form: HBoxContainer = ui.hbox(10)
	preview = PanelContainer.new()
	form.add_child(preview)
	clan_name = _edit("Clan name", 20, 300)
	clan_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(clan_name)
	clan_tag = _edit("TAG", 4, 110)
	clan_tag.alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(clan_tag)
	clan_browse.add_child(form)
	emblem_row = HFlowContainer.new()
	emblem_row.alignment = FlowContainer.ALIGNMENT_CENTER
	emblem_row.add_theme_constant_override("h_separation", 8)
	emblem_row.add_theme_constant_override("v_separation", 8)
	clan_browse.add_child(emblem_row)
	color_row = ui.hbox(8)
	clan_browse.add_child(color_row)
	clan_browse.add_child(ui.button("Create clan", "yellow", 30, func(): _create_clan()))
	var h2: Label = ui.label("Join a clan", 26)
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	clan_browse.add_child(h2)
	clan_search = _edit("Search by name or tag", 20, 560)
	clan_search.text_changed.connect(func(_t): _search_later())
	clan_browse.add_child(clan_search)
	clan_list = ui.vbox(8)
	clan_browse.add_child(clan_list)
	v.add_child(clan_browse)
	clan_mine = ui.vbox(12)
	clan_head = ui.hbox(14)
	clan_head.alignment = BoxContainer.ALIGNMENT_BEGIN
	clan_mine.add_child(clan_head)
	clan_members = ui.vbox(8)
	clan_mine.add_child(clan_members)
	var row: HBoxContainer = ui.hbox(10)
	clan_join = ui.button("Join clan", "yellow", 28, func(): _join_clan())
	clan_back = ui.button("All clans", "blue", 24, func(): browse_clans(clan_search.text))
	clan_leave = ui.button("Leave clan", "blue", 24, func(): _leave_clan())
	row.add_child(clan_join)
	row.add_child(clan_back)
	row.add_child(clan_leave)
	clan_mine.add_child(row)
	v.add_child(clan_mine)
	clans_status = ui.wrapped(ui.label("", 20, Color("#fff3a0"), 5), 540)
	v.add_child(clans_status)
	col.add_child(p)
	col.add_child(ui.back_button())


func open_clans() -> void:
	ui.show_screen("clans")
	clan_browse.visible = false
	clan_mine.visible = false
	clans_status.text = "Connecting…"
	var err: String = await net.go_online(func(s): clans_status.text = s)
	if err != "":
		clans_status.text = "Can't reach the server right now. Try again in a little while." if err == "down" else "This version of the game is too old for the server. Please update it."
		return
	clans_status.text = ""
	# Ask who we are first: a leader may have removed us since
	await net.request({"t": "whoami"}, ["me"])
	if main.save.clan is Dictionary:
		await show_clan(main.save.clan.id)
	else:
		await browse_clans("")


var _search_n := 0


func _search_later() -> void:
	_search_n += 1
	var n := _search_n
	await main.get_tree().create_timer(0.3).timeout
	if n == _search_n:
		browse_clans(clan_search.text.strip_edges())


func browse_clans(q: String) -> void:
	clan_view = {}
	clan_mine.visible = false
	clan_browse.visible = true
	_render_pickers()
	var res: Dictionary = await net.request({"t": "clans", "q": q}, ["clans"])
	for c in clan_list.get_children():
		c.queue_free()
	if res.t == "clanerr":
		clans_status.text = res.msg
		return
	for c in res.list:
		clan_list.add_child(_row(emblem(c.emblem, c.color, 48), "%s [%s]" % [c.name, c.tag], "%d/%d members" % [int(c.members), CLAN_SIZE], "🏆 %d" % int(c.trophies), false, c.id))
	if res.list.is_empty():
		clan_list.add_child(ui.label("No clans match that." if q != "" else "No clans yet. Start the first one!", 22))


func show_clan(id: String) -> void:
	if main.screen_open != "clans":
		ui.show_screen("clans")
	var res: Dictionary = await net.request({"t": "clan", "id": id}, ["clan"])
	if res.t == "clanerr":
		clans_status.text = res.msg
		if main.save.clan is Dictionary and main.save.clan.id == id:
			main.save.clan = null
			main.write_save()
		browse_clans("")
		return
	clan_view = res.clan
	_render_clan()


func _render_clan() -> void:
	var c := clan_view
	var mine: bool = main.save.clan is Dictionary and main.save.clan.id == c.id
	var leader: bool = c.leader == main.save.pid
	clan_browse.visible = false
	clan_mine.visible = true
	for ch in clan_head.get_children():
		ch.queue_free()
	clan_head.add_child(emblem(c.emblem, c.color, 84))
	var info: VBoxContainer = ui.vbox(2)
	var n: Label = ui.label("%s [%s]" % [c.name, c.tag], 30)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(n)
	var s: Label = ui.label("🏆 %d · %d/%d members" % [int(c.trophies), int(c.members), CLAN_SIZE], 18, Color.WHITE, 5, ui.font_m)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(s)
	clan_head.add_child(info)
	for ch in clan_members.get_children():
		ch.queue_free()
	var list: Array = c.list
	for i in list.size():
		var m: Dictionary = list[i]
		var me: bool = m.id == main.save.pid
		var left: HBoxContainer = ui.hbox(8)
		left.add_child(_rank(i))
		left.add_child(avatar(m.name, main.SIDES[1 if me else 2].color, 48))
		var row := _row(left, m.name + (" 👑" if m.leader else ""), "", "🏆 %d" % int(m.trophies), me)
		if leader and not m.leader:
			var kick: Button = ui.button("✖", "red", 18, func(): _kick(m))
			row.get_child(0).add_child(kick)
		clan_members.add_child(row)
	clan_join.visible = not mine
	clan_join.disabled = int(c.members) >= CLAN_SIZE
	clan_join.text = "Clan is full" if int(c.members) >= CLAN_SIZE else "Switch to this clan" if main.save.clan is Dictionary else "Join clan"
	clan_leave.visible = mine
	clan_back.visible = not mine


func _render_pickers() -> void:
	for ch in emblem_row.get_children():
		ch.queue_free()
	for e in EMBLEMS:
		var b: Button = ui.button(e, "white", 26, func():
			new_clan.emblem = e
			_render_pickers())
		b.custom_minimum_size = Vector2(60, 60)
		if e == new_clan.emblem:
			b.add_theme_stylebox_override("normal", ui.box(UI.YELLOW))
		emblem_row.add_child(b)
	for ch in color_row.get_children():
		ch.queue_free()
	for c in CLAN_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.add_theme_stylebox_override("normal", ui.box(Color(c), Color.WHITE if c == new_clan.color else UI.INK, 14, 4 if c == new_clan.color else 2, 2))
		b.add_theme_stylebox_override("hover", ui.box(Color(c).lightened(0.1)))
		b.pressed.connect(func():
			new_clan.color = c
			_render_pickers())
		color_row.add_child(b)
	for ch in preview.get_children():
		ch.queue_free()
	preview.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	preview.add_child(emblem(new_clan.emblem, new_clan.color, 60))


func _clan_reply(res: Dictionary) -> bool:
	if res.t == "clanerr":
		clans_status.text = res.msg
		return false
	clans_status.text = ""
	return true


func _create_clan() -> void:
	var res: Dictionary = await net.request({"t": "mkclan", "name": clan_name.text.strip_edges(), "tag": clan_tag.text.strip_edges().to_upper(),
		"emblem": new_clan.emblem, "color": new_clan.color}, ["clan"])
	if _clan_reply(res):
		clan_view = res.clan
		main.play_sound("trophy")
		_render_clan()


func _join_clan() -> void:
	var res: Dictionary = await net.request({"t": "joinclan", "id": clan_view.id}, ["clan"])
	if _clan_reply(res):
		clan_view = res.clan
		main.play_sound("capture")
		_render_clan()


func _leave_clan() -> void:
	var res: Dictionary = await net.request({"t": "leaveclan"}, ["me"])
	if _clan_reply(res):
		browse_clans("")


func _kick(m: Dictionary) -> void:
	var res: Dictionary = await net.request({"t": "kick", "id": m.id}, ["clan"])
	if _clan_reply(res):
		clan_view = res.clan
		_render_clan()
