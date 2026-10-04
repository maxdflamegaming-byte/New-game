class_name Net
extends Node
## PvP (online 1-vs-1, two players on one phone, practice against a bot), the leaderboard and
## clans. It talks to the same server as the web version (tower-siege/server/server.js) in the
## same messages, so phones with this app and web browsers play together.
##
## Online, one phone (the host) runs the battle and sends what's happening about 10 times a
## second; the other (the guest) sends its moves. Each player sees their own army in blue at
## the bottom: the guest's copy swaps blue and red and turns the field around.
## To save data, the host sends every soldier and building only once a second; in between it
## sends just the soldiers that appeared, the ones that are gone and the ones that changed
## strength (the guest moves the rest along their roads itself), and the buildings that changed. If either connection drops, the match pauses for up
## to 15 seconds while that phone reconnects.

const PROTOCOL := 3
const SERVER := "wss://tower-siege-server.onrender.com"
const PVP_TIME := 180.0          # a match lasts at most 3 minutes; then the bigger army wins
const SNAP_EVERY := 0.1
const KEY_EVERY := 10            # every 10th update has every soldier in it
const RECONNECT_TIME := 15.0     # seconds a match waits for a dropped connection
const LEAGUES := [
	{"name": "Bronze", "min": 0, "color": Color("#e0965a")},
	{"name": "Silver", "min": 150, "color": Color("#c3cede")},
	{"name": "Gold", "min": 400, "color": Color("#ffc928")},
	{"name": "Platinum", "min": 800, "color": Color("#5fe0d0")},
	{"name": "Diamond", "min": 1500, "color": Color("#8ec5ff")},
]

var main
var screens: OnlineScreens
var ws: WebSocketPeer
var online := false               # connected and said hello
var role := ""                   # "host" or "guest" during a match
var opp := {}                    # {name, trophies, tag}
var pvp := {}                    # this match: {kind, seed, snap_t, events, over, units, result, winner}
var _was_open := false
var _waiters: Array = []         # [{types, reply}]
var _searching := false
var _early: Array = []           # the guest's moves that arrived before our match started
var _back := false               # reconnecting to a match we were in


static func league_of(trophies: int) -> Dictionary:
	var l: Dictionary = LEAGUES[0]
	for x in LEAGUES:
		if trophies >= x.min:
			l = x
	return l


static func swap_side(s: int) -> int:
	return 2 if s == 1 else 1 if s == 2 else s


func _ready() -> void:
	screens = OnlineScreens.new()
	screens.net = self
	screens.main = main
	screens.ui = main.ui
	screens.build()


func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.substr(9)
	return SERVER


func is_guest() -> bool:
	return main != null and main.mode == "online" and role == "guest"


# ---------- Connection ----------
func _process(_dt: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			var hello := {"t": "hello", "v": PROTOCOL, "id": main.save.pid, "token": main.save.token, "name": main.save.name, "trophies": main.save.trophies}
			if _back:
				hello.back = true
			send_raw(hello)
		while ws.get_available_packet_count() > 0:
			var data = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if data is Dictionary:
				_on_message(data)
	elif st == WebSocketPeer.STATE_CLOSED:
		var lost := online
		ws = null
		online = false
		_was_open = false
		if lost:
			_on_lost()


## Connect and say hello. A free server may be asleep, so keep trying for up to a minute.
## Returns "" when connected, or why not ("down", "old").
func go_online(status: Callable = Callable(), max_ms := 60000) -> String:
	if main.save.name == "":
		main.save.name = "Commander%d" % (100 + randi() % 900)
		main.write_save()
	if online and ws != null:
		return ""
	var started := Time.get_ticks_msec()
	while true:
		if ws == null:
			ws = WebSocketPeer.new()
			_was_open = false
			if ws.connect_to_url(server_url()) != OK:
				ws = null
		var t0 := Time.get_ticks_msec()
		while ws != null and not online and Time.get_ticks_msec() - t0 < mini(8000, max_ms):
			await get_tree().process_frame
			if _old:
				_old = false
				return "old"
		if online:
			return ""
		if Time.get_ticks_msec() - started > max_ms:
			return "down"
		if status.is_valid():
			status.call("Waking up the server… (this can take up to a minute)")
		if ws != null:
			ws.close()
			ws = null
		await get_tree().create_timer(3.0 if max_ms >= 60000 else 1.0).timeout
	return "down"


var _old := false


func send_raw(msg: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


var tap := Callable()             # tests: sees every message we send


func send(msg: Dictionary) -> void:
	if tap.is_valid():
		tap.call(msg)
	send_raw(msg)


## Send a message and wait for the server's answer (one of `types`). Returns the answer, or
## {"t": "clanerr", "msg": ...} for an error or no answer.
func request(msg: Dictionary, types: Array) -> Dictionary:
	var w := {"types": types + ["clanerr"], "reply": null}
	_waiters.append(w)
	send(msg)
	var t0 := Time.get_ticks_msec()
	while w.reply == null and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	_waiters.erase(w)
	if w.reply == null:
		return {"t": "clanerr", "msg": "The server didn't answer. Try again."}
	return w.reply


## What the server knows about us: name, trophies, wins and clan
func apply_you(you) -> void:
	if not you is Dictionary:
		return
	main.save.pid = you.id
	main.save.name = you.name
	main.save.trophies = int(you.trophies)
	main.save.pvp_wins = int(you.wins)
	main.save.pvp_losses = int(you.losses)
	main.save.clan = you.clan
	main.write_save()


func _on_message(m: Dictionary) -> void:
	var t: String = m.get("t", "")
	if t == "welcome":
		online = true
		if m.get("token"):
			main.save.token = m.token
		apply_you(m.get("you"))
		return
	if t == "old":
		_old = true
		return
	# Answers to requests (leaderboard, clans)
	for w in _waiters:
		if w.reply == null and t in w.types:
			if m.has("you"):
				apply_you(m.you)
			w.reply = m
			return
	match t:
		"me":
			apply_you(m.get("you"))
		"result":
			# The server keeps the trophies; it sends the change after every online match
			apply_you(m.get("you"))
			if int(m.delta) > 0:
				main.save.coins += 20
				main.write_save()
			if not pvp.is_empty():
				pvp.result = int(m.delta)
			screens.show_trophy_change()
		"waiting":
			screens.wait_text("Looking for an opponent…")
		"room":
			screens.wait_text("Send this code to a friend. The match starts when they join.")
			screens.show_code(m.code)
		"noroom":
			screens.open_pvp("No room with that code. Check the letters and try again.")
		"match":
			_searching = false
			_early.clear()
			role = m.role
			opp = m.opp
			screens.show_vs(func(): start_pvp("online", int(m.seed)))
		"snap":
			if is_guest() and not pvp.is_empty() and not pvp.over:
				_apply_snap(m)
		"cmd":
			# A move can arrive while our VS card is still up: keep it for when the match starts
			if role == "host" and main.mode != "online":
				_early.append(m)
			elif main.mode == "online" and role == "host" and not pvp.is_empty() and not pvp.over:
				_apply_cmd(m)
		"end":
			if is_guest() and not pvp.is_empty() and not pvp.over:
				finish(swap_side(int(m.w)), m.get("why", ""))
		"wait":
			# The other player's connection dropped: the match waits for them
			if main.mode == "online" and not pvp.is_empty() and not pvp.over:
				pvp.paused = "opp"
				pvp.wait_left = float(m.get("secs", RECONNECT_TIME))
				pvp.waits += 1
		"back":
			if main.mode == "online" and not pvp.is_empty() and not pvp.over and pvp.paused == "opp":
				pvp.paused = ""
				pvp.need_key = true
				main.set_hint("")
		"resume":
			# We're back after our own connection dropped
			if main.mode == "online" and not pvp.is_empty() and not pvp.over and pvp.paused == "self":
				if m.get("ok", false):
					pvp.paused = ""
					role = m.role
					pvp.need_key = true
					main.set_hint("")
					main.play_sound("go")
				else:
					finish(-1, "lost")
		"gone":
			if main.mode == "online" and not pvp.is_empty() and not pvp.over:
				finish(1, "left")
			elif main.screen_open == "pvp-vs":
				screens.open_pvp("Your opponent left before the match started.")


## Our own connection dropped: in a match, pause and try to get back in
func _on_lost() -> void:
	if main.mode == "online" and not pvp.is_empty() and not pvp.over:
		_reconnect()
	elif main.screen_open == "pvp-wait":
		screens.open_pvp("Lost the connection to the server.")


func _reconnect() -> void:
	pvp.paused = "self"
	pvp.wait_left = RECONNECT_TIME
	main.clear_pointers()
	_back = true
	var err: String = await go_online(Callable(), int(RECONNECT_TIME * 1000))
	_back = false
	if err != "" and not pvp.is_empty() and not pvp.over and pvp.paused == "self":
		finish(-1, "lost")


func paused() -> bool:
	return main.mode == "online" and not pvp.is_empty() and not pvp.over and pvp.paused != ""


## While a match waits for a dropped connection, nothing moves. Returns true while paused.
func pause_tick(dt: float) -> bool:
	if not paused():
		return false
	pvp.wait_left -= dt
	var secs := maxi(0, ceili(pvp.wait_left))
	var text: String = ("Connection lost. Reconnecting… %d" if pvp.paused == "self" else "Your opponent's connection dropped. Waiting for them… %d") % secs
	if main.hint_text != text:
		main.set_hint(text, 99.0)
	if pvp.paused == "self" and pvp.wait_left < -3:
		finish(-1, "lost")
	return true


# ---------- Finding a match ----------
func find_match(room := "") -> void:
	_searching = true
	screens.show_wait(room != "")
	var err: String = await go_online(func(s): screens.wait_text(s))
	if err != "":
		_searching = false
		screens.open_pvp("This version of the game is too old for the server. Please update it." if err == "old"
			else "Can't reach the PvP server right now. Try 2 players on one phone, or practice against a bot.")
		return
	if main.screen_open != "pvp-wait":
		return # cancelled while connecting
	if room == "create":
		send({"t": "room"})
	elif room != "":
		send({"t": "join", "code": room})
	else:
		send({"t": "find"})


func cancel_find() -> void:
	_searching = false
	send({"t": "cancel"})
	screens.open_pvp("")


func leave() -> void:
	send({"t": "leave"})
	role = ""


func open_pvp() -> void:
	# The first time: how PvP works
	if not main.save.seen.has("pvp"):
		main.save.seen["pvp"] = true
		main.write_save()
		main.ui.show_screen("pvp-help")
		return
	screens.open_pvp("")


func open_board() -> void:
	screens.open_board()


func open_clans() -> void:
	screens.open_clans()


# ---------- Starting a match ----------
func start_pvp(kind: String, seed_value: int) -> void:
	if kind != "online":
		role = ""
	main.mode = kind
	main.level = 0
	main.state = "play"
	main.load_battle(Levels.gen(14, true, seed_value), 1000 + seed_value % 997, Levels.THEMES[seed_value % Levels.THEMES.size()])
	# The guest's copy: their army (red on the host) shows as blue
	if is_guest():
		for t in main.battle.towers:
			t.owner = swap_side(t.owner)
	if kind == "practice":
		main.battle.ai_sides = [{"side": 2, "timer": 2.5, "cfg": {"think": 2.2, "margin": 4.0, "bold": 0.5}}]
	main.armed = ""
	main.shake = 0.0
	main.hand_shown = false
	main.charges = {"strike": 0, "rally": 0}
	main.speed = 1
	pvp = {"kind": kind, "seed": seed_value, "snap_t": 0.0, "snap_n": 0, "sent": {}, "sent_tw": {}, "need_key": false, "paused": "", "wait_left": 0.0, "waits": 0,
		"events": [], "over": false, "units": {}, "result": null, "winner": null}
	if kind == "online" and role == "host":
		for m in _early:
			_apply_cmd(m)
		_early.clear()
	main.clear_pointers()
	main.ui.show_screen("")
	main.ui.start_hud("2 Players" if kind == "duo" else "Practice" if kind == "practice" else "vs " + str(opp.get("name", "Player")), false)
	main.set_hint("Blue plays from the bottom, red from the top. Drag from your own buildings!" if kind == "duo"
		else "PvP: take every enemy building, or have the bigger army when the 3 minutes are up", 8.0)
	main.music.play_track("boss")


func restart() -> void:
	if pvp.is_empty():
		open_pvp()
	elif pvp.kind == "online":
		leave()
		find_match()
	else:
		start_pvp(pvp.kind, randi() % 1000000000)


# ---------- Host: send the battle, take the guest's moves ----------
func event(e: Array) -> void:
	if main.mode != "online" or pvp.is_empty() or is_guest():
		return
	if e[0] == "cl" and pvp.events.size() > 60:
		return
	pvp.events.append(e)


func host_tick(dt: float) -> void:
	if pvp.is_empty() or pvp.over:
		return
	pvp.snap_t -= dt
	if pvp.snap_t > 0:
		return
	pvp.snap_t = SNAP_EVERY
	var b: Battle = main.battle
	var msg := {"t": "snap", "tm": snappedf(b.time, 0.01), "ev": pvp.events}
	var sent: Dictionary = pvp.sent
	var tw := []
	var tc := []
	var key: bool = pvp.need_key or pvp.snap_n % KEY_EVERY == 0
	for t in b.towers:
		var row := [roundi(t.units * 10), t.owner, t.roads.map(func(r): return r.to.id)]
		var sig := str([floori(t.units), t.owner, row[2]])
		tw.append(row)
		if pvp.sent_tw.get(t.id) != sig:
			tc.append([t.id] + row)
		pvp.sent_tw[t.id] = sig
	if key:
		var us := []
		for u in b.units:
			us.append(_row(u))
		msg.k = 1
		msg.tw = tw
		msg.u = us
	else:
		# Only what changed since the last update: buildings whose soldier count, owner or
		# roads changed, and soldiers that appeared, are gone or changed strength
		if not tc.is_empty():
			msg.tc = tc
		var nu := []
		var pw := []
		var x := []
		var seen := {}
		for u in b.units:
			seen[u.id] = true
			if not sent.has(u.id):
				nu.append(_row(u))
			elif sent[u.id] != u.power:
				pw.append([u.id, u.power])
		for id in sent:
			if not seen.has(id):
				x.append(id)
		if not nu.is_empty():
			msg.nu = nu
		if not pw.is_empty():
			msg.pw = pw
		if not x.is_empty():
			msg.x = x
	pvp.snap_n += 1
	pvp.need_key = false
	var now := {}
	for u in b.units:
		now[u.id] = u.power
	pvp.sent = now
	send(msg)
	pvp.events = []


func _row(u: Battle.Unit) -> Array:
	return [u.id, u.from.id, u.to.id, roundi(u.d), u.power, u.owner, roundi(u.lane)]


func _apply_cmd(m: Dictionary) -> void:
	var b: Battle = main.battle
	var ai := int(m.get("a", -1))
	var bi := int(m.get("b", -1))
	if ai < 0 or bi < 0 or ai >= b.towers.size() or bi >= b.towers.size():
		return
	var a := b.towers[ai]
	var t := b.towers[bi]
	if a.owner != 2:
		return
	if m.get("c") == "link":
		b.link(a, t, 2)
	elif m.get("c") == "cut":
		b.cut(a, t)


# ---------- Guest: show what the host sends ----------
func _apply_snap(m: Dictionary) -> void:
	var b: Battle = main.battle
	var old: Dictionary = pvp.units
	# Effects first, while the soldiers they mention still exist here
	for e in m.get("ev", []):
		_guest_event(e, old)
	b.time = float(m.tm)
	var tw: Array = m.get("tw", [])
	for i in mini(tw.size(), b.towers.size()):
		_guest_tower(b.towers[i], tw[i])
	for row in m.get("tc", []):
		if int(row[0]) < b.towers.size():
			_guest_tower(b.towers[int(row[0])], row.slice(1))
	var next: Dictionary
	if m.get("k", 0):
		# Every soldier
		next = {}
		for row in m.u:
			var u := _guest_unit(row, old.get(int(row[0])))
			if u != null:
				next[u.id] = u
	else:
		# Only what changed: the rest keep marching here
		next = old
		for id in m.get("x", []):
			next.erase(int(id))
		for p in m.get("pw", []):
			var u = next.get(int(p[0]))
			if u != null:
				u.power = int(p[1])
		for row in m.get("nu", []):
			var u := _guest_unit(row, next.get(int(row[0])))
			if u != null:
				next[u.id] = u
	var list: Array[Battle.Unit] = []
	for u in next.values():
		list.append(u)
	b.units = list
	pvp.units = next


## row: [soldiers * 10, owner, [road target ids]]
func _guest_tower(t: Battle.Tower, row: Array) -> void:
	var b: Battle = main.battle
	var side := swap_side(int(row[1]))
	var n := float(row[0]) / 10.0
	if side == t.owner and n > t.units + 0.5:
		t.pop = 1.0
	if side == t.owner and n < t.units - 0.5:
		t.flash = 1.0
	t.owner = side
	t.units = n
	var roads := []
	for id in row[2]:
		var keep = null
		for r in t.roads:
			if r.to.id == int(id):
				keep = r
		if keep == null and int(id) < b.towers.size():
			keep = {"to": b.towers[int(id)], "timer": 0.0, "born": b.time}
		if keep != null:
			roads.append(keep)
	t.roads = roads


func _guest_unit(row: Array, u: Battle.Unit) -> Battle.Unit:
	var b: Battle = main.battle
	if u == null:
		if int(row[1]) >= b.towers.size() or int(row[2]) >= b.towers.size():
			return null
		u = Battle.Unit.new()
		u.id = int(row[0])
		u.from = b.towers[int(row[1])]
		u.to = b.towers[int(row[2])]
		u.lane = -float(row[6])
		u.d = float(row[3])
	# Keep the smooth local position unless it has drifted
	var d := float(row[3])
	u.d = d if absf(u.d - d) > 40 else u.d + (d - u.d) * 0.5
	u.power = int(row[4])
	u.owner = swap_side(int(row[5]))
	b.place_unit(u)
	return u


func _guest_event(e: Array, old: Dictionary) -> void:
	var b: Battle = main.battle
	if e[0] == "cap" and int(e[1]) < b.towers.size():
		var t := b.towers[int(e[1])]
		var side := swap_side(int(e[2]))
		var was := t.owner
		t.owner = side
		main.world.capture(t.x, t.y, side)
		if side == 1:
			b.stats.captured += 1
			main.play_sound("capture")
			main.floats.append({"t": t, "text": "Captured!", "color": main.SIDES[1].light, "life": 1.3})
		elif was == 1:
			b.stats.lost += 1
			main.play_sound("warn")
			main.shake = maxf(main.shake, 6)
			main.floats.append({"t": t, "text": "Lost!", "color": main.SIDES[side].light, "life": 1.3})
	elif e[0] == "cl":
		var a = old.get(int(e[1]))
		var c = old.get(int(e[2]))
		var u = a if a != null else c
		if u != null:
			if a != null and c != null and (a.owner == 1 or c.owner == 1):
				b.stats.killed += 1
			main.world.clash(u.x, u.y, a.owner if a != null else 1, c.owner if c != null else 2)
	elif e[0] == "sh" and int(e[1]) < b.towers.size():
		var t := b.towers[int(e[1])]
		var u = old.get(int(e[2]))
		if u != null:
			main.shells.append({"x1": t.x, "y1": t.y, "x2": u.x, "y2": u.y, "h": 50.0, "time": 0.18, "dur": 0.18})
			main.world.muzzle(t, u.x, u.y)
			main.world.hit(u.x, u.y, u.owner)


func guest_update(dt: float) -> void:
	var b: Battle = main.battle
	b.time += dt
	for t in b.towers:
		t.flash = maxf(0, t.flash - dt * 3)
		t.pop = maxf(0, t.pop - dt * 4)
	# Soldiers keep marching between updates, so they move smoothly
	for u in b.units:
		var L := Battle.dist(u.from.x, u.from.y, u.to.x, u.to.y)
		u.d = minf(u.d + b.unit_speed(u) * dt, L - u.to.radius() * 0.5)
		b.place_unit(u)
	if main.hint_text != "":
		main.hint_timer -= dt
		if main.hint_timer <= 0:
			main.set_hint("")


# ---------- The end of a match ----------
func check_end() -> void:
	if pvp.is_empty() or pvp.over or is_guest():
		return
	var b: Battle = main.battle
	var blue := b.alive(1)
	var red := b.alive(2)
	var winner := -1
	var why := ""
	if not blue or not red:
		winner = 1 if blue else 2 if red else 0
	elif b.time >= PVP_TIME:
		var tot := b.totals()
		winner = 1 if tot[1] > tot[2] else 2 if tot[2] > tot[1] else 0
		why = "time"
	if winner < 0:
		return
	if main.mode == "online":
		send({"t": "end", "w": winner, "why": why})
	finish(winner, why)


## winner: 1 = us online (or blue on one phone), 2 = them / red, 0 = a draw, -1 = no result
func finish(winner: int, why: String) -> void:
	pvp.over = true
	main.mission("pvp")
	main.mission("beat", main.battle.stats.killed)
	pvp.winner = winner
	main.state = "over"
	main.clear_pointers()
	main.set_hint("")
	main.music.play_track("menu")
	var happy: bool = main.mode == "duo" or winner == 1
	main.play_sound("win" if happy else "death")
	if happy and winner > 0:
		for t in main.battle.towers:
			if t.owner == winner:
				main.world.capture(t.x, t.y, winner)
	get_tree().create_timer(1.1).timeout.connect(func(): screens.show_end(winner, why))
