extends SceneTree
## The game as a player sees it, without a screen: the menu, a level, dragging a road and
## swiping to cut it with touch events, winning (stars, coins, the next level saved), losing,
## and buying an upgrade.
##   godot --headless --path tower-siege-godot -s tests/flow.gd
## Prints PASS/FAIL lines and "FLOW DONE n failed".

var main
var fails := 0


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak", "user://tower_siege.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false # tested on their own at the end
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	_touch(index, from, true)
	for i in 6:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = from.lerp(to, (i + 1) / 6.0)
		root.push_input(e, true)
		await process_frame
	_touch(index, to, false)
	await process_frame


func _run() -> void:
	await _frames(10)
	ok("The daily reward pops up on the first visit of the day", main.screen_open == "reward" and main.state == "menu" and main.battle.towers.size() > 4)
	main.ui.reward_btn.pressed.emit()
	await _frames(2)
	ok("Collecting it pays day 1's coins and opens the menu", int(main.save.coins) == 20 and int(main.save.streak.count) == 1 and main.screen_open == "menu")
	main.open_menu()
	ok("It doesn't pop up again the same day", main.screen_open == "menu")
	main.save.coins = 0

	main.start_level(1)
	await _frames(3)
	ok("Play starts level 1", main.state == "play" and main.level == 1 and main.battle.towers.size() == 4)
	ok("Level 1 shows the hint and the hand", main.hand_shown and main.hint_text != "")
	# Freeze the enemy (with no enemies at all, the level would count as won)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	var me: Battle.Tower = main.battle.towers[0]
	var gray: Battle.Tower = main.battle.towers[1]
	var a: Dictionary = main.world.tower_screen(me)
	var b: Dictionary = main.world.tower_screen(gray)
	await _drag(0, Vector2(a.x, a.y), Vector2(b.x, b.y))
	ok("Dragging builds a road", me.has_road(gray))
	ok("The hand goes away after the first road", not main.hand_shown)
	await _frames(30)
	for i in 30:
		main.battle.update(0.05)
	ok("Soldiers march along the road", main.battle.units.any(func(u): return u.owner == 1))

	# Swipe straight across the road
	var p1: Vector2 = main.world.project(me.x, me.y)
	var p2: Vector2 = main.world.project(gray.x, gray.y)
	var mid := (p1 + p2) / 2
	var n := (p2 - p1).normalized().orthogonal() * 70
	await _drag(1, mid - n, mid + n)
	ok("Swiping across a road cuts it", not me.has_road(gray))

	# Winning
	for t in main.battle.towers:
		if t.owner == 2:
			t.owner = 1
	main.battle.units.clear()
	await _frames(5)
	ok("Taking every enemy building wins", main.state == "over")
	await create_timer(1.5).timeout
	ok("The win screen shows", main.screen_open == "win")
	ok("A win is saved: next level, stars, coins", int(main.save.level) == 2 and int(main.save.stars.get("1", 0)) >= 1 and int(main.save.coins) > 0, JSON.stringify(main.save))

	# Losing
	main.start_level(2)
	await _frames(3)
	for t in main.battle.towers:
		if t.owner == 1:
			t.owner = 2
	main.battle.units.clear()
	await _frames(5)
	await create_timer(1.5).timeout
	ok("Losing every building shows Defeat", main.screen_open == "lose")

	# A save cut off halfway (the phone killed the app mid-write) falls back to the backup
	var level_before := int(main.save.level)
	main.save.coins = 7
	main.write_save()
	main.save.coins = 8
	main.write_save()
	var broken := FileAccess.open("user://tower_siege.json", FileAccess.WRITE)
	broken.store_string("{\"level\": 9, \"coi")
	broken.close()
	main.load_save()
	ok("A broken save falls back to the last good one", int(main.save.level) == level_before and int(main.save.coins) == 7, "level %d coins %d" % [main.save.level, main.save.coins])

	# Upgrades
	main.save.coins = 500
	main.buy("drill")
	ok("Buying an upgrade spends coins", int(main.save.up.drill) == 1 and int(main.save.coins) == 440)
	main.ui.show_screen("shop")
	await _frames(3)
	ok("The shop opens", main.screen_open == "shop")

	# 2 players on one phone: both colors can be dragged, and blue cuts from the bottom half
	main.net.start_pvp("duo", 12345)
	await _frames(3)
	ok("2 players on one phone starts with no bots", main.mode == "duo" and main.battle.ai_sides.is_empty())
	ok("Both blue and red can be steered", main.controls(1) and main.controls(2))
	main.net.start_pvp("practice", 777)
	ok("Practice has a bot", main.mode == "practice" and main.battle.ai_sides.size() == 1)

	# Online updates: a guest's copy, rebuilt only from what the host sends, matches the host
	main.net.role = "host"
	main.net.start_pvp("online", 4242)
	var host_b: Battle = main.battle
	for t in host_b.towers:
		if t.owner != 0:
			t.units += 60
	host_b.ai_sides = [{"side": 1, "timer": 0.5, "cfg": {"think": 0.8, "margin": 1.5, "bold": 0.8}}, {"side": 2, "timer": 0.5, "cfg": {"think": 0.8, "margin": 1.5, "bold": 0.8}}]
	var copy := Battle.new()
	copy.load_map(Levels.gen(14, true, 4242))
	var msgs := []
	var full_bytes := 0
	var sent_bytes := 0
	main.net.tap = func(m): msgs.append(m)
	var same := true
	var most := 0
	var checks := 0
	for i in 1200:
		host_b.update(1.0 / 60)
		main.net.host_tick(1.0 / 60)
		for m in msgs:
			if m.t != "snap":
				continue
			sent_bytes += JSON.stringify(m).length()
			var us := []
			for u in host_b.units:
				us.append(main.net._row(u))
			full_bytes += JSON.stringify({"t": "snap", "tm": m.tm, "u": us, "ev": m.ev}).length() + 200
			main.battle = copy
			main.net._apply_snap(m)
			main.battle = host_b
			var want := {}
			for u in host_b.units:
				want[u.id] = [u.power, Net.swap_side(u.owner)]
			var got := {}
			for u in copy.units:
				got[u.id] = [u.power, u.owner]
			var towers_same := true
			for k in host_b.towers.size():
				var h := host_b.towers[k]
				var c := copy.towers[k]
				towers_same = towers_same and c.owner == Net.swap_side(h.owner) and absi(floori(c.units) - floori(h.units)) <= 1 and c.roads.size() == h.roads.size()
			if want != got or not towers_same:
				same = false
			checks += 1
			most = maxi(most, host_b.units.size())
		msgs.clear()
	main.net.tap = Callable()
	ok("Online: the guest's copy matches the host's after every update", same and checks > 100 and most > 30, "%d updates, up to %d soldiers" % [checks, most])
	ok("Online: updates use much less data than sending everything", sent_bytes * 2 < full_bytes, "%d vs %d bytes" % [sent_bytes, full_bytes])
	main.net.role = ""
	main.open_menu()

	# Upgrading a building: tap it, then the ⬆ button
	main.save.level = 9
	main.start_level(8)
	await _frames(3)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	var mine: Battle.Tower = main.battle.towers[0]
	mine.units = 40
	var ms: Dictionary = main.world.tower_screen(mine)
	await _drag(0, Vector2(ms.x, ms.y), Vector2(ms.x + 3, ms.y))
	ok("Tapping your building offers an upgrade", not main.upgrade_offer.is_empty() and main.upgrade_offer.t == mine)
	var btn: Dictionary = main.overlay.upgrade_button(mine)
	_touch(0, btn.c, true)
	_touch(0, btn.c, false)
	await _frames(2)
	ok("The ⬆ button upgrades it for 10 soldiers", mine.stars == 1 and mine.units < 31.0, "%d %.1f" % [mine.stars, mine.units])
	var rate1: float = main.battle.prod_rate(mine)
	mine.stars = 0
	ok("An upgraded building trains faster", rate1 > main.battle.prod_rate(mine) * 1.25)

	# Missions: the briefing, the goal on the HUD, and the ways a mission is lost
	main.open_menu()
	main.ui.play_btn.pressed.emit()
	await _frames(2)
	ok("PLAY opens the mission briefing", main.screen_open == "brief" and main.ui.brief_n == 9 and main.ui.brief_title.text.begins_with("Operation") and main.ui.brief_text.text.length() > 20)
	main.ui.brief_start.pressed.emit()
	await _frames(3)
	ok("Start begins the mission", main.state == "play" and main.level == 9 and main.goal.goal == Missions.goal_for(9))
	main.start_level(4)
	await _frames(3)
	ok("The HUD shows the mission's goal", main.ui.objective.get_parent().visible and main.ui.objective.text.contains("0:"), main.ui.objective.text)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	main.battle.capture(main.goal.hq, 2)
	await _frames(3)
	await create_timer(1.5).timeout
	ok("Losing the HQ loses a defend mission, and the defeat screen says why", main.screen_open == "lose" and main.ui.lose_reason.text == "Your headquarters has fallen.", main.ui.lose_reason.text)
	main.start_level(9)
	await _frames(3)
	main.battle.time = main.goal.time + 1
	await _frames(3)
	await create_timer(1.5).timeout
	ok("A blitz is lost when the clock runs out", main.screen_open == "lose" and main.ui.lose_reason.text.begins_with("Time's up"), main.ui.lose_reason.text)
	main.start_level(7)
	await _frames(3)
	var t7: Array = main.battle.totals()
	await create_timer(1.0).timeout
	ok("No reinforcements: nobody trains", main.battle.frozen and main.battle.totals()[1] <= t7[1] + 0.01)
	# Anonymous level stats: each level's start and how it ended, kept until they can be sent
	main.open_menu()
	main.save.stats_rows = []
	main.start_level(3)
	await _frames(2)
	main.start_level(3)
	await _frames(2)
	for t in main.battle.towers:
		if t.owner == 1:
			t.owner = 2
	main.battle.units.clear()
	await _frames(5)
	var kinds: Array = main.save.stats_rows.map(func(r): return "%d %s" % [r[0], r[1]])
	ok("Level stats: a level left for another counts as quit, then start and how it ended", kinds == ["3 start", "3 quit", "3 start", "3 lose"], str(kinds))
	ok("...and the tests send nothing anywhere", main.analytics._target() == "")
	main.ui.show_screen("settings")
	await _frames(2)
	main.ui.stats_btn.pressed.emit()
	ok("Settings can switch the stats off, which forgets what's waiting", not main.save.stats and main.save.stats_rows.is_empty())
	main.start_level(3)
	await _frames(2)
	ok("...and then nothing is kept", main.save.stats_rows.is_empty())
	main.ui.stats_btn.pressed.emit()
	ok("...and back on", main.save.stats)
	main.open_menu()

	# A long battle gets a final push, so it can't drag on
	main.start_level(12)
	await _frames(3)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	main.battle.time = 119.0
	main.step(0.05)
	ok("No final push in the first two minutes", main.battle.push == 1.0)
	var rate_before: float = main.battle.prod_rate(main.battle.towers[0])
	main.battle.time = 121.0
	main.step(0.05)
	ok("After two minutes, a final push: your buildings train faster and the enemy attacks", main.battle.push > 1.0 and main.battle.prod_rate(main.battle.towers[0]) > rate_before * 1.3 and main.battle.ai_sides.all(func(a): return float(a.cfg.bold) >= 0.5))
	main.start_level(4)
	await _frames(3)
	main.battle.time = main.goal.time - 1.0
	main.step(0.05)
	ok("A mission with its own clock has no final push", main.battle.push == 1.0)
	main.start_level(7)
	await _frames(3)
	main.battle.time = 70.0
	main.step(0.05)
	ok("With no reinforcements and nothing happening, a tip says how to gather soldiers", main.battle.push == 1.0 and main.hint_text.begins_with("Stuck?"), main.hint_text)
	main.net.start_pvp("practice", 778)
	await _frames(2)
	ok("PvP has no mission goal and plays at the web version's speed", main.goal.is_empty() and not main.ui.objective.get_parent().visible and main.battle.pace == 1.0 and not main.battle.frozen and main.battle.push == 1.0)
	main.open_menu()

	# Boss levels, endless levels and the daily challenge
	main.start_level(10)
	await _frames(3)
	ok("Level 10 is a boss level with a castle", main.battle.towers.any(func(t): return t.type == "castle" and t.owner == 2) and main.ui.level_label.text.contains("Boss"))
	main.save.level = 64
	main.ui.show_screen("levels")
	await _frames(2)
	ok("Endless levels show up after 60, in chapters of 5", main.ui.map_buttons.size() == 65 and main.ui.level_map.get_child_count() == 13, "%d levels" % main.ui.map_buttons.size())
	main.start_level(64)
	await _frames(3)
	ok("An endless level plays", main.state == "play" and main.battle.towers.size() >= 8)
	var coins0 := int(main.save.coins)
	main.start_daily()
	await _frames(3)
	ok("The daily challenge starts", main.daily and main.state == "play" and main.ui.level_label.text == "Daily challenge")
	var t_first: Array = main.battle.towers.map(func(t): return [t.bx, t.by, t.type])
	main.start_daily()
	ok("It's the same map every time today", main.battle.towers.map(func(t): return [t.bx, t.by, t.type]) == t_first)
	for t in main.battle.towers:
		if t.owner >= 2:
			t.owner = 1
	main.battle.units.clear()
	await _frames(5)
	await create_timer(1.5).timeout
	ok("Winning it pays the daily prize once", int(main.save.coins) == coins0 + Progress.DAILY_COINS and int(main.save.daily_won) == Progress.today() and not main.ui.next_btn.visible)

	# Missions
	var list := Progress.missions(main.save)
	ok("There are 3 missions today", list.size() == 3)
	var m0: Dictionary = list[0]
	m0.have = 0
	m0.claimed = false
	Progress.add(main.save, m0.id, int(m0.goal))
	var before := int(main.save.coins)
	main.ui.show_screen("missions")
	await _frames(2)
	ok("A finished mission can be collected", Progress.claim_mission(main.save, 0) == int(m0.coins) and int(main.save.coins) == before + int(m0.coins))
	ok("Only once", Progress.claim_mission(main.save, 0) == 0)

	# Looks
	main.save.coins = 1000
	ok("Buying a hat", Progress.pick_look(main.save, "hat", "crown") == "" and int(main.save.coins) == 200 and main.save.looks.hat == "crown")
	main.world.set_look(main.save.looks.hat, main.save.looks.flag)
	ok("Your soldiers wear it", main.world.look_hat == "crown")
	ok("Can't buy what you can't afford", Progress.pick_look(main.save, "flag", "skull") == "coins")
	main.ui.show_screen("looks")
	await _frames(2)
	ok("The looks screen opens", main.screen_open == "looks" and main.ui.looks_lists.hat.get_child_count() == Progress.HATS.size())
	main.open_menu()

	# Languages
	await _languages()

	# Cut scenes
	await _cutscenes()

	# Graphics settings
	await _graphics()


func _languages() -> void:
	var re := RegEx.create_from_string("%0?[0-9]*[ds]")
	var keys: Array = load("res://i18n/es.gd").T.keys()
	var langs_ok := true
	var why := ""
	for code in I18n.LANGS:
		if code == "" or code == "en":
			continue
		var table: Dictionary = load("res://i18n/%s.gd" % code).T
		if table.keys().size() != keys.size():
			langs_ok = false
			why += "%s has %d texts; " % [code, table.size()]
		for k in table:
			var a1 := re.search_all(k).map(func(m): return m.get_string())
			var a2 := re.search_all(table[k]).map(func(m): return m.get_string())
			if a1 != a2:
				langs_ok = false
				why += "%s: %s; " % [code, k]
	ok("Every language has every text, with the same blanks for numbers and names", langs_ok, why)
	main.set_lang("es")
	main.ui.show_screen("settings")
	await _frames(2)
	ok("Picking Spanish translates the screens", TranslationServer.get_locale() == "es" and main.ui.tr("Settings") != "Settings" and main.ui.vibrate_btn.can_auto_translate())
	ok("Text with numbers is translated too", main.tr("Level %d") % 5 != "Level 5")
	main.set_lang("")
	ok("Auto goes back to the phone's language (English here)", TranslationServer.get_locale() == "en" or I18n.current() == "en")
	main.open_menu()


## Wait (in game time) until cond is true
func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		if cond.call():
			return true
		await process_frame
	return false


func _cutscenes() -> void:
	main.cinematics = true
	main.cutscene.auto = true
	Engine.time_scale = 4.0
	main.save.seen.erase("story_1")
	main.start_level(1)
	await _frames(5)
	ok("Level 1 starts with the story", main.state == "cutscene" and main.cutscene.playing() and not main.ui.hud.visible)
	ok("Captain Skye comes on and talks", await _until(func(): return main.cutscene.actors.has("skye") and main.cutscene.dialog.visible, 10))
	var me: Battle.Tower = main.battle.towers[0]
	var g: Battle.Tower = main.battle.towers[1]
	var a: Dictionary = main.world.tower_screen(me)
	var b: Dictionary = main.world.tower_screen(g)
	await _drag(3, Vector2(a.x, a.y), Vector2(b.x, b.y))
	ok("Touches during a cut scene don't play the game", me.roads.is_empty() and main.battle.units.is_empty())
	ok("General Grumble comes on too", await _until(func(): return main.cutscene.actors.has("grumble"), 15))
	main.cutscene.skip()
	ok("Skip goes straight to the level", await _until(func(): return main.state == "play", 3) and not main.cutscene.playing() and main.ui.hud.visible and not main.world.cam_free)
	ok("The camera is back where the battle needs it", main.world.camera.transform.is_equal_approx(main.world.cam_base))
	ok("The story is told once", main.save.seen.has("story_1"))
	main.start_level(4)
	await _frames(3)
	ok("Other levels start with a quick fly-in", main.state == "cutscene" and main.cutscene.actors.is_empty())
	ok("... and then the level begins", await _until(func(): return main.state == "play", 5))
	main.save.level = 11
	main.start_level(10)
	ok("A boss level: Grumble taunts from his castle", await _until(func(): return main.cutscene.actors.has("grumble") and main.cutscene.dialog.visible, 12))
	ok("... then the boss level begins", await _until(func(): return main.state == "play", 25))
	for t in main.battle.towers:
		if t.owner >= 2:
			t.owner = 1
	main.battle.units.clear()
	ok("Winning a boss level: Grumble runs off, then the celebration", await _until(func(): return main.cutscene.actors.has("grumble"), 10) and await _until(func(): return main.cutscene.stage.get_child_count() >= 12, 15))
	ok("... then the results", await _until(func(): return main.screen_open == "win", 15))
	main.start_level(7)
	await _until(func(): return main.state == "play", 6)
	for t in main.battle.towers:
		if t.owner == 1:
			t.owner = 2
	main.battle.units.clear()
	ok("Losing: Grumble laughs, then the results", await _until(func(): return main.cutscene.playing(), 3) and await _until(func(): return main.screen_open == "lose", 10))
	main.save.cutscenes = false
	main.save.seen.erase("story_6")
	main.start_level(6)
	await _frames(3)
	ok("With story scenes off, levels start with just the fly-in", main.state == "cutscene" and await _until(func(): return main.state == "play", 5) and not main.save.seen.has("story_6"))
	main.save.cutscenes = true
	main.watch_story()
	ok("Settings can play the story again", await _until(func(): return main.cutscene.actors.has("skye"), 10))
	main.cutscene.skip()
	ok("... and it goes back to the menu", await _until(func(): return main.state == "menu" and main.screen_open == "menu", 5))
	Engine.time_scale = 1.0
	main.cinematics = false
	main.cutscene.auto = false


func _graphics() -> void:
	# Graphics settings
	main.set_gfx("low")
	ok("Low graphics: full resolution with light smoothing, no soldier shadows", main.world.quality == 0 and not main.world.soldier_shadows.visible and get_root().msaa_3d == Viewport.MSAA_2X and is_equal_approx(get_root().scaling_3d_scale, 1.0))
	main.set_gfx("high")
	ok("High graphics: full resolution", main.world.quality == 2 and is_equal_approx(get_root().scaling_3d_scale, 1.0) and main.world.soldier_shadows.visible)
	main.set_gfx("auto")
	ok("Auto starts at Medium", main.world.quality == 1)
	main.state = "menu"
	for i in 200:
		main._process(0.06)
	ok("Auto steps the graphics down when the game runs slowly", main.world.quality == 0)
	main.ui.show_screen("settings")
	await _frames(2)
	ok("The settings screen opens", main.screen_open == "settings")
	var tris := 0
	var m: Mesh = main.world.soldiers.multimesh.mesh
	tris = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	ok("Soldiers are light to draw", tris <= 300, str(tris))

	print("FLOW DONE %d failed" % fails)
	quit(1 if fails else 0)
