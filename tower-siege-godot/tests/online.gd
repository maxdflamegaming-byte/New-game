extends SceneTree
## A Godot player for the cross-play test (tests/suites/siege-crossplay.js runs it next to a web
## player and the server). It finds a match, plays its part as host or guest, makes a clan and
## prints what it saw, each line starting with "GD ".
##   godot --headless --path tower-siege-godot -s tests/online.gd -- --server=ws://127.0.0.1:PORT --name=Godo [--delay=S] [--clan=TAG] [--drop | --peer-drops]
## --drop: this player's connection drops right after the match starts, and it must get back in.
## --peer-drops: the other player's will; this one must wait for them, then carry on.

var main
var my_name := "Godo"
var delay := 0.0
var clan_tag := "GDT"
var drop := false
var peer_drops := false
var saw_wait := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			my_name = a.substr(7)
		elif a.begins_with("--delay="):
			delay = float(a.substr(8))
		elif a.begins_with("--clan="):
			clan_tag = a.substr(7)
		elif a == "--drop":
			drop = true
		elif a == "--peer-drops":
			peer_drops = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tower_siege.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func say(s: String) -> void:
	print("GD " + s)


func _wait(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000:
		if cond.call():
			return true
		await process_frame
	return false


func _run() -> void:
	for i in 10:
		await process_frame
	main.save.name = my_name
	# Waiting a moment lets the other player search first (then they host)
	if delay > 0:
		await create_timer(delay).timeout
	main.net.find_match()
	await _wait(func(): return main.net.online, 30)
	await create_timer(0.5).timeout
	say("SEARCHING")
	var ok: bool = await _wait(func(): return main.mode == "online" and main.state == "play", 40)
	say("MATCH %s role=%s towers=%d" % [ok, main.net.role, main.battle.towers.size()])
	if not ok:
		quit(1)
		return
	var b: Battle = main.battle
	say("MAP " + JSON.stringify(b.towers.map(func(t): return [roundi(t.bx), roundi(t.by), t.type])))
	if drop:
		await create_timer(0.5).timeout
		main.net.ws.close()
		ok = await _wait(func(): return main.net.paused(), 5)
		say("DROPPED %s" % ok)
		ok = await _wait(func(): return main.mode == "online" and not main.net.paused() and not main.net.pvp.over, 25)
		say("RESUMED %s role=%s" % [ok, main.net.role])
	elif peer_drops:
		# Reconnecting can take only a moment, so look for the "wait" message, not the pause itself
		ok = await _wait(func(): return main.net.pvp.waits > 0, 10)
		say("WAITED %s" % ok)
		ok = await _wait(func(): return not main.net.paused() and not main.net.pvp.over, 25)
		say("PEER_BACK %s" % ok)
	if main.net.role == "guest":
		var me: Battle.Tower = null
		for t in b.towers:
			if t.owner == 1:
				me = t
		var target: Battle.Tower = null
		for t in b.towers:
			if t.owner == 0 and not b.blocked(me.x, me.y, t.x, t.y) and (target == null or Battle.dist(t.x, t.y, me.x, me.y) < Battle.dist(target.x, target.y, me.x, me.y)):
				target = t
		say("GUEST_LINK %s" % str(main.request_link(me, target, 1)))
		ok = await _wait(func(): return me.has_road(target) and b.units.any(func(u): return u.owner == 1), 30)
		say("GUEST_ROAD %s" % ok)
	else:
		ok = await _wait(func(): return b.towers.any(func(t): return t.owner == 2 and not t.roads.is_empty()), 40)
		say("HOST_SAW_ROAD %s" % ok)
		for i in 30:
			await process_frame
		# Take everything: the host decides the match
		for t in b.towers:
			if t.owner == 2:
				t.owner = 1
		b.units = b.units.filter(func(u): return u.owner != 2)
	ok = await _wait(func(): return main.screen_open == "pvp-end" and main.net.pvp.result != null, 40)
	say("RESULT %s title=%s trophies=%d" % [ok, main.net.screens.end_title.text, int(main.save.trophies)])
	var res: Dictionary = await main.net.request({"t": "mkclan", "name": "Godot Gang " + clan_tag, "tag": clan_tag, "emblem": "🐉", "color": "#45d35a"}, ["clan"])
	say("CLAN %s" % res.get("t", ""))
	var top: Dictionary = await main.net.request({"t": "top"}, ["top"])
	say("TOP " + JSON.stringify(top.get("players", []).map(func(p): return [p.name, int(p.trophies), p.tag])))
	quit(0)
