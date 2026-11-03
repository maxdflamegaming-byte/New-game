extends SceneTree
## Battle checker: a careless player (random roads, cuts, airstrikes, upgrades, hints, the
## speed button) plays every story level, endless levels, the daily challenge, the weekend
## events, 2 players and practice, while the game's rules are checked on every frame:
##   - every number is a real number, buildings hold 0 to 150 soldiers
##   - no soldier stands still or walks forever, nobody marches for the gray army
##   - gray buildings have no roads, no road leads to its own building or twice to one place,
##     a road that has sent everything is gone
##   - the battle clock runs while you play (nothing freezes it)
##   - a battle that's won or lost ends, and one that ends was really won or lost
##   - a frame never takes long (no hang)
## Any break is a FAIL saying where (mode, level, battle time) and what.
##   godot --headless --path tower-siege-godot -s tests/fuzz.gd [-- quick]
## Prints "FUZZ DONE n failed".

const FRAME := 1.0 / 60.0

var main
var fails := 0
var reported := {}
var rng := RandomNumberGenerator.new()
var where := ""


func bad(what: String, extra := "") -> void:
	# The same break in the same battle is reported once
	var k := where.get_slice(" at ", 0) + RegEx.create_from_string("[0-9.]+").sub(what, "#", true)
	if reported.has(k):
		return
	reported[k] = true
	fails += 1
	print("FAIL %s — %s%s" % [where, what, ("  " + extra) if extra != "" else ""])


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1600))
	root.size = Vector2i(720, 1600)
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Get from "starting" to playing: skip cut scenes and press the briefing's button
func _into_battle() -> void:
	var guard := 0
	while main.state != "play" and guard < 300:
		guard += 1
		if main.state == "cutscene":
			main.cutscene.skip()
		for b in main.ui.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and main.screen_open == "brief" and not b.disabled and (b.text.contains("Play") or b.text.contains("Start") or b.text.contains("Go") or b.text.contains("Fight")):
				b.pressed.emit()
				break
		await _frames(2)


## One careless move, through the same functions a finger's touch reaches
func _move() -> void:
	var b: Battle = main.battle
	var mine: Array = b.towers.filter(func(t): return main.controls(t.owner) and t.owner != Battle.NEUTRAL)
	if mine.is_empty():
		return
	var r := rng.randf()
	var a = mine[rng.randi() % mine.size()]
	if r < 0.55:
		var t = b.towers[rng.randi() % b.towers.size()]
		if t != a:
			var res = main.request_link(a, t, a.owner)
			if res is bool and res and main.tutor != null:
				main.tutor.event("own_road" if t.owner == a.owner else "road")
	elif r < 0.7 and not a.roads.is_empty():
		var to = a.roads[rng.randi() % a.roads.size()].to
		var p := Vector2(a.x, a.y).lerp(Vector2(to.x, to.y), 0.5)
		var n := (Vector2(to.x, to.y) - Vector2(a.x, a.y)).normalized().orthogonal() * 30
		main.swipe(p - n, p + n, a.owner)
	elif r < 0.78 and main.mode == "campaign" and main.charges.get("strike", 0) > 0:
		var targets: Array = b.towers.filter(func(t): return t.owner != Battle.PLAYER)
		if not targets.is_empty():
			main.use_ability("strike")
			main.drop_strike(targets[rng.randi() % targets.size()])
	elif r < 0.84 and main.mode == "campaign" and main.charges.get("rally", 0) > 0:
		main.use_ability("rally")
	elif r < 0.9 and main.mode == "campaign" and main.can_upgrade_here():
		main.upgrade_building(a)
	elif r < 0.95 and main.mode == "campaign":
		main.show_hint()
	else:
		main.toggle_speed()


## Every rule the battle must keep, checked now
func _check(seen_units: Dictionary) -> void:
	var b: Battle = main.battle
	for t in b.towers:
		if is_nan(t.units) or is_inf(t.units):
			bad("a building's soldiers aren't a number", "building %d" % t.id)
		if t.units < -0.001 or (t.units > Battle.HARD_CAP + 0.001 and not b.frozen):
			bad("a building holds %.1f soldiers" % t.units, "building %d (%s)" % [t.id, t.type])
		if t.owner == Battle.NEUTRAL and not t.roads.is_empty():
			bad("a gray building has roads", "building %d" % t.id)
		var targets := {}
		for road in t.roads:
			if road.to == t:
				bad("a road leads to its own building", "building %d" % t.id)
			if targets.has(road.to):
				bad("two roads from one building to the same place", "building %d" % t.id)
			targets[road.to] = true
			if int(road.get("left", -1)) == 0:
				bad("a road that has sent everything is still there", "building %d" % t.id)
	var speed_min: float = Battle.UNIT_SPEED * b.march * 0.8 * 0.2  # a tank, in a lesson's slow motion
	for u in b.units:
		if u.owner == Battle.NEUTRAL:
			bad("soldiers march for the gray army")
		if is_nan(u.x) or is_nan(u.y) or is_nan(u.d):
			bad("a soldier's place isn't a number")
		var s = seen_units.get(u.id)
		if s == null:
			seen_units[u.id] = [b.time, u.d]
			continue
		var L: float = Battle.dist(u.from.x, u.from.y, u.to.x, u.to.y)
		if b.time - s[0] > L / speed_min + 5.0:
			bad("a soldier has been on the road too long", "%.0f s on a %.0f road, d %.0f" % [b.time - s[0], L, u.d])
		if b.time - s[0] > 1.0 and u.d <= s[1] and b.time > 0:
			bad("a soldier stands still on its road", "d %.1f" % u.d)
		s[1] = u.d if b.time - s[0] > 1.0 else s[1]


func _play(label: String, seconds: float) -> void:
	await _into_battle()
	where = label
	if main.state != "play":
		bad("the battle doesn't start", "state %s, screen %s" % [main.state, main.screen_open])
		return
	main.tutor = null if rng.randf() < 0.5 else main.tutor  # half the time with the lessons on
	var seen_units := {}
	var next_move := 0.5
	var t_real := 0.0
	var last_time := -1.0
	var still := 0
	while t_real < seconds and main.state == "play":
		var t0 := Time.get_ticks_usec()
		main._process(FRAME)
		var took := (Time.get_ticks_usec() - t0) / 1000.0
		if took > 60.0:
			bad("a frame took %.0f ms" % took, "%d soldiers, %d roads" % [main.battle.units.size(), main.battle.towers.reduce(func(acc, t): return acc + t.roads.size(), 0)])
		if took > 12.0 and OS.get_environment("FUZZ_SLOW") != "":
			print("SLOW %.1f ms at %s: %d soldiers, speed %d, strikes %d, screen '%s'" % [took, where, main.battle.units.size(), main.speed, main.battle.strikes.size(), main.screen_open])
		t_real += FRAME
		where = "%s at %.1fs" % [label, main.battle.time]
		if main.state != "play":
			break
		if main.screen_open == "" and main.mode != "online":
			# The clock must run
			if main.battle.time <= last_time:
				still += 1
				if still > 90:
					bad("the battle clock stopped for 1.5 seconds", "screen '%s', tutor %s" % [main.screen_open, main.tutor != null and main.tutor.holding()])
					still = 0
			else:
				still = 0
			last_time = main.battle.time
		_check(seen_units)
		# Won or lost, the battle has to end now
		var decided := ""
		if main.mode == "campaign":
			decided = Missions.result(main.goal if not main.goal.is_empty() else {"goal": "conquer"}, main.battle)
		elif not main.battle.alive(1) or not main.battle.alive(2):
			decided = "over"
		if decided != "":
			main.check_end()
			if main.state == "play" and main.mode != "online":
				bad("the battle is %s but goes on" % decided)
		next_move -= FRAME
		if next_move <= 0:
			next_move = rng.randf_range(0.3, 1.4)
			_move()
		if int(t_real * 60) % 60 == 0:
			await process_frame
	# It ended: was it really won or lost?
	if main.state == "over" and main.mode == "campaign":
		var r := Missions.result(main.goal if not main.goal.is_empty() else {"goal": "conquer"}, main.battle)
		if r == "":
			bad("the battle ended though nobody had won or lost")
		elif r == "won":
			for t in main.battle.towers:
				if t.owner > 1 and main.goal.get("goal", "conquer") in ["conquer", "puzzle", "blitz"]:
					bad("won while an enemy army still holds a building", "building %d owned by side %d" % [t.id, t.owner])
					break
	await _frames(2)


func _run() -> void:
	await _frames(30)
	rng.seed = 4242
	var quick := "quick" in OS.get_cmdline_user_args()
	main.save.level = 90
	main.save.coins = 99999
	for u in main.UPGRADES:
		main.save.up[u.id] = 1
	var levels := range(1, 61) + [61, 68, 75, 90]
	if quick:
		levels = [1, 2, 3, 4, 5, 7, 10, 15, 22, 30, 40, 50, 60, 70]
	for n in levels:
		for k in (1 if quick else 2):
			main.open_menu()
			main.reward_shown_day = Progress.today()
			seed(n * 31 + k)
			main.start_level(n)
			await _play("level %d (try %d)" % [n, k + 1], 150.0)
	for kind in ["daily", "duo", "practice"]:
		main.open_menu()
		if kind == "daily":
			main.start_daily()
		else:
			main.net.start_pvp(kind, 900 + kind.length())
		await _play(kind, 150.0)
	for day in [20393, 20400, 20407, 20414]:  # four Saturdays: the four events
		Progress.test_day = day
		for stage in 3:
			main.open_menu()
			main.reward_shown_day = day
			main.save.erase("event")
			Events.state(main.save, day).stage = stage
			main.start_event()
			await _play("event %s battle %d" % [Events.kind(day), stage + 1], 150.0)
	Progress.test_day = -1
	print("FUZZ DONE %d failed" % fails)
	quit(1 if fails else 0)
