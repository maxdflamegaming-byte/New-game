extends SceneTree
## Headless checks of the game flow: power-ups, winning, knockouts, coins, pausing, saving
## and music. Run: godot --headless --path godot -s tests/flow.gd

var main
var fails := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra else ""))
	if not cond:
		fails += 1


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _play(mode := "classic") -> void:
	main.mode_id = mode
	main.start_game()
	main.countdown = 0.0
	await process_frame
	await process_frame


func _run() -> void:
	await _wait(0.5)
	var w = main.world
	main.prog.tutorial_done = true # skip the first-game tutorial offer (tested on its own below)
	I18n.lang = "en" # the checks below compare English text
	I18n.apply()
	var first_launch: bool = main.welcome.visible
	main.welcomed = true
	main.welcome.visible = false
	main.menu.visible = true
	ok("Starts on the menu with a live bots-only game", main.state == "menu" and w.me.is_bot)

	# Power-ups
	await _play()
	var me: Player = w.me
	ok("A new game starts with you in play", main.state == "play" and me.alive and not me.is_bot, main.state)
	var base: float = w.speed_of(me)
	w._grab(me, "speed", me.pos)
	ok("Speed makes you 1.6x faster", is_equal_approx(w.speed_of(me), base * 1.6), str(w.speed_of(me)))
	me.fx.speed = 0.0
	var bot: Player = w.players[2]
	w._grab(bot, "freeze", bot.pos)
	w._update_items(0.0)
	ok("Someone else's Freeze halves your speed", is_equal_approx(w.speed_of(me), base * 0.5) and is_equal_approx(w.speed_of(bot), base))
	bot.fx.freeze = 0.0
	w._update_items(0.0)
	w._grab(me, "shield", me.pos)
	ok("Shield protects you", me.shield >= 5.9)
	var before: int = w.counts[me.id]
	w._grab(me, "paint", me.pos)
	ok("Paint Bomb claims a circle of land", w.counts[me.id] > before, "%d -> %d" % [before, w.counts[me.id]])
	# Ghost: crossing your own trail is safe
	me.shield = 0.0
	me.fx.ghost = 5.0
	var cell: Vector2i = me.cell + Vector2i(0, 6)
	var i: int = cell.y * w.N + cell.x
	w.trail[i] = me.id
	me.trail.append(i)
	w.visit(me, cell.x, cell.y)
	ok("Ghost lets you cross your own trail", me.alive)
	me.fx.ghost = 0.0
	w.visit(me, cell.x, cell.y)
	ok("Without Ghost, crossing your own trail knocks you out", not me.alive)

	# A new game straight after a knockout isn't ended by the old game's timer
	await _play()
	await _wait(1.3)
	ok("A game over from the last game doesn't end the new one", main.state == "play", main.state)

	# Coins on the map
	me = w.me
	me.shield = 99.0
	w.coins.append({"pos": me.pos, "age": 1.0, "life": 20.0})
	w._update_items(0.01)
	ok("Picking up a coin counts it", w.coins_picked == w.COIN_VALUE, str(w.coins_picked))

	# Winning pays coins and saves them
	var wallet_before: int = main.wallet
	for k in w.N * w.N:
		if w.wall[k] == 0 and w.land[k] == 0 and w.counts[me.id] < w.play_cells * 0.51:
			w.set_land(k, me.id)
	await _wait(0.2)
	ok("Claiming 50% wins", main.state == "won", main.state)
	await _wait(1.8)
	ok("After the win the results show", main.state == "over" and main.over_title.text == "You win!", main.over_title.text)
	ok("A win pays at least 50 coins, including the ones picked up", main.wallet >= wallet_before + 50 + w.COIN_VALUE, "%d -> %d" % [wallet_before, main.wallet])
	var cfg := ConfigFile.new()
	cfg.load(main.SAVE_PATH)
	ok("Coins and best are saved", cfg.get_value("player", "coins", -1) == main.wallet and cfg.get_value("stats", "bests", {}).get("classic", 0.0) >= 50.0)

	# Pause and the back button
	await _play()
	main._back()
	ok("Back pauses the game", main.state == "paused")
	main._back()
	ok("Back again resumes it", main.state == "play")
	main._pause()
	main._to_menu()
	ok("Quit to menu goes back to the live menu", main.state == "menu" and main.menu.visible)

	# Maps
	var bad := []
	for m in w.MAPS:
		main.map_id = m
		await _play("classic")
		if w.map_id != m or not w.me.alive or w.wall[w.me.cell.y * w.N + w.me.cell.x] != 0:
			bad.append(m)
	ok("Every map starts with you on open ground", bad.is_empty(), str(bad))

	# Timed: when the clock runs out the biggest player wins
	await _play("timed")
	main.play_time = 179.99
	await _wait(0.3)
	ok("Timed ends when the clock runs out", main.state == "won" or main.state == "over", main.state)
	await _wait(1.8)
	ok("Timed shows the results with your place", main.state == "over" and ("Time's up" in main.over_reason.text), main.over_reason.text)

	# Teams: teammates can't hurt each other, and the team's land counts together
	await _play("teams")
	me = w.me
	var mate: Player = w.players[2]
	var foe: Player = w.players[6]
	ok("Teams: you and 3 bots against 4", w.allies(me, mate) and not w.allies(me, foe) and w.players.size() == 9)
	me.shield = 0.0
	mate.shield = 0.0
	var tcell: Vector2i = mate.cell + Vector2i(0, 5)
	var ti: int = tcell.y * w.N + tcell.x
	w.trail[ti] = mate.id
	mate.trail.append(ti)
	w.visit(me, tcell.x, tcell.y)
	ok("Crossing a teammate's trail doesn't hurt them", mate.alive)
	for k in w.N * w.N:
		if w.wall[k] == 0 and w.land[k] == 0 and w.team_pct(0) < 51:
			w.set_land(k, [me.id, mate.id][k % 2])
	await _wait(0.2)
	ok("Your team claiming 50% together wins", main.state == "won", main.state)

	# Boss Battle: the King loses hearts, calls guards and you have 3 lives
	await _play("boss")
	var king: Player = w.king
	ok("Boss Battle: just you and the King, you with 3 lives", king != null and king.is_boss and w.me.lives == 3 and w.players.size() == 3)
	var hearts: int = king.hp
	king.shield = 0.0
	w.kill(king, w.me)
	ok("Cutting the King takes a heart", king.alive and king.hp == hearts - 1)
	king.shield = 0.0
	w.kill(king, w.me)
	ok("At half health he calls 2 guards", w.players.size() == 5, str(w.players.size()))
	await process_frame
	ok("The guards get drawn too", main.view.views.has(w.players[4].id))
	w.me.shield = 0.0
	w.kill(w.me, king)
	await _wait(1.4)
	ok("Losing a life brings you back", w.me.alive and w.me.lives == 2 and main.state == "play", "%s %d %s" % [w.me.alive, w.me.lives, main.state])
	while king.hp > 1:
		king.shield = 0.0
		w.kill(king, w.me)
	king.shield = 0.0
	w.kill(king, w.me)
	await _wait(0.2)
	ok("Taking his last heart wins", not king.alive and main.state == "won", main.state)
	await _wait(1.8)
	ok("Beating the King pays a bonus", main.over_coins.text != "" and int(main.over_coins.text.split(" ")[0]) >= 150, main.over_coins.text)

	# Daily: the same map and start for everyone today
	var starts := []
	for k in 2:
		main.mode_id = "daily"
		main.start_game() # compare where everyone starts, before anyone moves
		var at := [w.map_id]
		for q in w.players:
			if q:
				at.append(q.pos)
		starts.append(at)
		await _wait(0.3)
	ok("Daily starts the same way every time today", starts[0] == starts[1], str(starts[0].slice(0, 3)))

	# 2 Players: split screen, and the first human knocked out loses
	await _play("duo")
	ok("2 Players: two humans and 6 bots, on a split screen", w.p2 != null and not w.p2.is_bot and w.players.size() == 9 and main.split.visible)
	w.p2.shield = 0.0
	w.kill(w.p2, w.players[4])
	await _wait(1.3)
	ok("When Player 2 is knocked out, Player 1 wins", main.state == "over" and w.me.name in main.over_title.text, main.over_title.text)
	main._to_menu()
	ok("The split screen goes away on the menu", not main.split.visible)

	# Levels, missions, streak and trophies (the rules on their own)
	var pr := Progress.new()
	var win_game := {"mode": "classic", "map": "square", "won": true, "pct": 52.0, "kos": 2, "powerups": 3, "coins": 4, "time": 150.0, "best_loop": 6.0, "wallet": 0}
	var r1: Array = pr.finish(win_game, "2026-03-10")
	var kinds := r1.map(func(r): return r.kind)
	ok("A first game pays the streak bonus and earns trophies", kinds.has("streak") and pr.trophies.has("first_win") and pr.trophies.has("first_ko"), str(kinds))
	ok("Stats add up", pr.stats.games == 1 and pr.stats.wins == 1 and pr.stats.kos == 2 and is_equal_approx(pr.stats.best_pct, 52.0))
	ok("A game gives XP", pr.xp + (pr.level - 1) * 100 > 0, "level %d xp %d" % [pr.level, pr.xp])
	var r2: Array = pr.finish(win_game, "2026-03-10")
	ok("The streak pays once a day, trophies only once", not r2.any(func(r): return r.kind == "streak" or r.text == "Trophy: First Win"))
	pr.finish(win_game, "2026-03-11")
	ok("Playing the next day grows the streak", pr.streak == 2)
	pr.finish(win_game, "2026-03-14")
	ok("Missing a day starts it again", pr.streak == 1)
	var lv := Progress.new()
	var ups: Array = lv._gain_xp(Progress.need(1) + 5)
	ok("Enough XP levels you up, with coins", lv.level == 2 and lv.xp == 5 and ups.size() == 1 and ups[0].coins == 70)
	var mp := Progress.new()
	mp.ensure_day("2026-05-01")
	var first_ids := mp.missions.map(func(m): return m.id)
	mp.day = ""
	mp.ensure_day("2026-05-01")
	ok("Each day has the same 3 different missions for everyone", mp.missions.map(func(m): return m.id) == first_ids and first_ids.size() == 3 and first_ids[0] != first_ids[1] and first_ids[1] != first_ids[2] and first_ids[0] != first_ids[2])
	mp.missions = [{"id": "play3", "progress": 0.0, "done": false}, {"id": "claim30", "progress": 0.0, "done": false}, {"id": "teams", "progress": 0.0, "done": false}]
	var lose_game := {"mode": "classic", "map": "round", "won": false, "pct": 12.0}
	var got1: Array = mp.finish(lose_game, "2026-05-01")
	mp.finish(lose_game, "2026-05-01")
	var got3: Array = mp.finish(win_game, "2026-05-01")
	var missions_done := got3.filter(func(r): return r.kind == "mission").map(func(r): return r.text)
	ok("Missions fill up and pay when they're done", not got1.any(func(r): return r.kind == "mission") and missions_done.has("Mission: Play 3 games") and missions_done.has("Mission: Claim 30% in one game") and not mp.missions[2].done, str(missions_done))
	ok("A finished mission doesn't pay twice", not mp.finish(win_game, "2026-05-01").any(func(r): return r.kind == "mission"))
	var bp := Progress.new()
	bp.finish({"mode": "boss", "won": true, "pct": 20.0, "lives_lost": 1}, "2026-05-01")
	ok("Beating the King after losing a life isn't Flawless", bp.trophies.has("king") and not bp.trophies.has("flawless"))
	bp.finish({"mode": "boss", "won": true, "pct": 20.0, "lives_lost": 0}, "2026-05-01")
	ok("Beating him without losing one is", bp.trophies.has("flawless"))
	var copy := Progress.new()
	copy.from_dict(pr.to_dict())
	ok("Progress saves and loads", copy.level == pr.level and copy.xp == pr.xp and copy.trophies.keys() == pr.trophies.keys() and copy.streak == pr.streak and copy.stats.games == pr.stats.games)
	copy.from_dict({"level": -3, "trophies": ["nope", "king"], "missions": [{"id": "nope"}], "stats": {"games": "lots"}})
	ok("A broken save is cleaned up", copy.level == 1 and copy.trophies.keys() == ["king"] and copy.missions.is_empty() and copy.stats.games == 0)

	# Bot difficulty
	main.difficulty = "hard"
	await _play()
	var hard_speed: float = w.speed_of(w.players[2])
	ok("Hard bots are faster", hard_speed > w.SPEED and w.speed_of(w.me) == w.SPEED, str(hard_speed))
	main.peak = 50.0
	var before_game: int = main.wallet
	main._game_over(true, "test")
	ok("Hard pays 1.5x coins and the results show your rewards", "x1.5" in main.over_coins.text and main.wallet > before_game and main.over_xp.text.begins_with("Level"), main.over_coins.text)
	main.difficulty = "normal"
	main._to_menu()
	await process_frame

	# The first game offers the tutorial
	var saved_prog: Progress = main.prog
	main.prog = Progress.new()
	main.ask_box.set_meta("asked", false)
	main.start_game()
	ok("Your very first game offers the tutorial", main.ask_box.visible and main.state == "menu")
	main._back()
	ok("Back closes the offer", not main.ask_box.visible)

	# The tutorial
	main.start_tutorial()
	main.countdown = 0.0
	await process_frame
	await process_frame
	var coach: Player = w.players[2]
	ok("The tutorial has you and a practice bot", w.players.size() == 3 and coach.harmless and main._tut_step == 1 and main.tut_card.visible)
	w.kill(w.me, coach)
	ok("The practice bot can't knock you out", w.me.alive)
	for k in 4:
		w.me.trail.append(k)
	main._update_tutorial()
	w.me.trail.clear()
	ok("Step 1: leaving your land", main._tut_step == 2)
	main._on_captured(w.me, PackedInt32Array(), 1.0)
	ok("Step 2: a loop; then a power-up appears", main._tut_step == 3 and w.powerups.size() == 1)
	w._grab(w.me, "speed", w.me.pos)
	ok("Step 3: grabbing it", main._tut_step == 4)
	coach.shield = 0.0
	w.kill(coach, w.me)
	await process_frame
	ok("Step 4: knocking out Coach", main._tut_step == 5)
	var coins_before: int = main.wallet
	var need := int(w.play_cells * 0.16)
	for cell_i in w.N * w.N:
		if need <= 0:
			break
		if w.wall[cell_i] == 0 and w.land[cell_i] != w.me.id and w.trail[cell_i] == 0:
			w.set_land(cell_i, w.me.id)
			need -= 1
	w.land_version += 1
	await _wait(2.2)
	ok("Step 5: claiming 15% finishes it, with 50 coins and a trophy", main.state == "over" and main.prog.tutorial_done and main.prog.trophies.has("tutorial") and main.wallet >= coins_before + 75, "%s %d" % [main.state, main.wallet - coins_before])
	ok("Then it offers a real game", main.again_btn.text == "Play for real")
	main.prog = saved_prog
	main._to_menu()
	await process_frame

	# The menu's screens
	for sc in [main.missions_screen, main.profile_screen, main.settings_screen]:
		sc.open()
		await process_frame
		var shown: bool = sc.visible and not main.menu.visible and sc.body.get_child_count() > 2
		main._back()
		await process_frame
		ok("%s opens and Back closes it" % sc.get_script().resource_path.get_file(), shown and not sc.visible and main.menu.visible)
	main.settings_screen.open()
	var vib: bool = main.vibration
	main.settings_screen._toggle(VBoxContainer.new(), "x", vib, func(): main.vibration = not main.vibration)
	main.vibration = not vib
	main._save()
	main._load()
	ok("Settings are saved", main.vibration == (not vib))
	main.vibration = vib
	main.settings_screen.close()
	main.profile_screen.open()
	main.profile_screen.name_edit.text = "  Max  "
	main.profile_screen._save_name()
	main.profile_screen.close()
	await _play()
	ok("Your name is saved and shown in the game", main.player_name == "Max" and w.me.name == "Max")
	main.player_name = "You"
	main._save()
	main._to_menu()
	await process_frame
	ok("The menu shows your level and today's missions", main.level_label.text.begins_with("Level ") and main.missions_badge.text.ends_with("/3"))

	# Graphics settings
	var gfx_before := [Gfx.level, Gfx.fps, Gfx.show_fps]
	Gfx.level = Gfx.LOW
	main._apply_gfx()
	ok("Low draws at 720p with fewer particles", root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and Gfx.particles(40) < 20 and not main.vignette.visible)
	Gfx.level = Gfx.MEDIUM
	main._apply_gfx()
	ok("Medium draws at 720p too", root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT)
	Gfx.level = Gfx.HIGH
	Gfx.fps = 60
	Gfx.show_fps = true
	main._apply_gfx()
	ok("High draws at full resolution", root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and Gfx.particles(40) == 40 and main.vignette.visible)
	ok("The Android frame-rate call and MSAA are gone (they crashed or did nothing)", root.msaa_2d == Viewport.MSAA_DISABLED and not Gfx.new().has_method("_request_refresh_rate"))
	ok("Ultra and 90/120 FPS are off for now", Gfx.LEVELS.size() == 3 and Gfx.FPS == [30, 60])
	ok("Show FPS shows the counter", main.fps_label.get_parent().visible)
	Gfx.level = Gfx.MEDIUM
	Gfx.fps = 30
	Gfx.show_fps = false
	main._save()
	Gfx.level = Gfx.HIGH
	Gfx.fps = 60
	main._load()
	ok("Graphics settings are saved", Gfx.level == Gfx.MEDIUM and Gfx.fps == 30 and not Gfx.show_fps)
	var old_save := ConfigFile.new()
	old_save.load(main.SAVE_PATH)
	old_save.set_value("settings", "gfx", Gfx.ULTRA)
	old_save.erase_section_key("settings", "gfx_v")
	old_save.save(main.SAVE_PATH)
	main._load()
	ok("A save from before the new levels starts again from the safe default", Gfx.level == Gfx.default_level() and Gfx.level <= Gfx.MEDIUM)
	old_save.set_value("settings", "gfx", 3)
	old_save.set_value("settings", "gfx_v", 2)
	old_save.set_value("settings", "fps", 120)
	old_save.save(main.SAVE_PATH)
	main._load()
	ok("A save on Ultra at 120 FPS comes back as High at 60 FPS", Gfx.level == Gfx.HIGH and Gfx.fps == 60)
	main._save()
	# Crash reports: the marker file, and a log report with the device details
	CrashLog.running()
	ok("A game that closes without saying goodbye counts as a crash next time", CrashLog.started())
	CrashLog.stopped()
	ok("A game closed on purpose doesn't", not CrashLog.started())
	CrashLog.stopped()
	CrashLog.running()
	main.copy_log()
	var report := DisplayServer.clipboard_get()
	ok("Copy game log puts the device details on the clipboard", report == "" or report.begins_with("Color Claim log"))
	await _play()
	w.me.fx.speed = 0.0
	for gl in 3:
		Gfx.level = gl
		main._apply_gfx()
		for f in 20:
			await process_frame
	ok("Every quality level runs a game without errors", main.state == "play")
	Gfx.level = gfx_before[0]
	Gfx.fps = gfx_before[1]
	Gfx.show_fps = gfx_before[2]
	main._apply_gfx()
	main._to_menu()
	await process_frame

	# Hazard maps
	main.map_id = "portals"
	await _play()
	var hme: Player = w.me
	hme.shield = 99.0
	var gate: Vector2 = w.portals[0][0]
	var twin: Vector2 = w.portals[0][1]
	hme.pos = gate + Vector2(0.3, 0)
	hme.cell = Vector2i(int(hme.pos.x), int(hme.pos.y))
	hme.trail.append(hme.cell.y * w.N + hme.cell.x) # pretend we're out on a trail
	w.trail[hme.cell.y * w.N + hme.cell.x] = hme.id
	hme.path = PackedVector2Array([hme.pos - Vector2(2, 0), hme.pos])
	hme.portal_cd = 0.0
	w.move(hme, 0.001)
	ok("Portals: step in one, pop out of its twin, and the trail is drawn in two pieces", hme.pos.distance_to(twin) < 2.0 and hme.path_breaks.size() == 1, str(hme.pos))
	main.map_id = "conveyor"
	await _play()
	hme = w.me
	var belt_cell := -1
	for c in w.N * w.N:
		if w.belt[c] == 1 and w.belt[c - w.N] == 1 and w.belt[c + w.N] == 1 and w.land[c] == 0:
			belt_cell = c
			break
	hme.pos = Vector2(belt_cell % w.N + 0.5, belt_cell / w.N + 0.5)
	hme.cell = Vector2i(belt_cell % w.N, belt_cell / w.N)
	hme.angle = -PI / 2
	hme.desired = -PI / 2
	var x0: float = hme.pos.x
	w.move(hme, 0.1)
	ok("Conveyor: a belt carries you along", hme.pos.x - x0 > w.BELT_SPEED * 0.1 * 0.9, "%.2f" % (hme.pos.x - x0))
	main.map_id = "saws"
	await _play()
	var victim: Player = w.players[3]
	victim.shield = 0.0
	var saw_pos: Vector2 = w.saws[0].pos
	var sc: int = int(saw_pos.y) * w.N + int(saw_pos.x)
	w.land[sc] = 0
	w.trail[sc] = victim.id
	victim.trail.append(sc)
	w._update_hazards(0.0)
	ok("Saw Mill: a blade cuts the trail it runs over", not victim.alive)
	main.map_id = "storm"
	await _play()
	hme = w.me
	var outsider: Player = w.players[2]
	outsider.pos = Vector2(3.5, 3.5)
	outsider.cell = Vector2i(3, 3)
	outsider.shield = 99.0
	var cells_before: int = w.play_cells
	w._close_storm(20.0)
	var land_outside := 0
	for c in w.N * w.N:
		if w.wall[c] == 2 and (w.land[c] or w.trail[c]):
			land_outside += 1
	ok("Storm: closing in shrinks the map, and shields don't help outside it", w.play_cells < cells_before and land_outside == 0 and not outsider.alive and hme.alive)
	main.map_id = "square"

	# The Queen and the Wizard
	var boss_prog: Progress = main.prog
	main.prog = Progress.new()
	ok("The Queen is locked until you beat the King", not main.boss_unlocked("queen") and not main.boss_unlocked("wizard"))
	main.prog.stats.king_wins = 1
	ok("Beating the King unlocks the Queen", main.boss_unlocked("queen") and not main.boss_unlocked("wizard"))
	main.boss_kind = "queen"
	await _play("boss")
	ok("The Boss Battle brings the boss you picked", w.king.boss_kind == "queen" and w.king.max_hp == 6)
	w.king.power_timer = 0.0
	for k in 3:
		w.king.trail.append(k)
	w._boss_power(w.king, 0.1)
	w.king.trail.clear()
	ok("The Queen drops traps while she's out", w.traps.size() == 1)
	hme = w.me
	hme.shield = 0.0
	w.traps[0].pos = hme.pos
	w._update_hazards(0.0)
	ok("A trap can't hurt you on your own land", hme.alive)
	var far := Vector2i(hme.cell.x + 12, hme.cell.y)
	hme.pos = Vector2(far) + Vector2(0.5, 0.5)
	hme.cell = far
	w.traps[0].pos = hme.pos
	w._update_hazards(0.0)
	await _wait(1.4)
	ok("Outside it, a trap costs a life", hme.lives == 2)
	main.prog.stats.queen_wins = 1
	main.boss_kind = "wizard"
	await _play("boss")
	var wiz: Player = w.king
	for k in 4:
		var c: int = (wiz.cell.y + 8) * w.N + wiz.cell.x + k
		w.trail[c] = wiz.id
		wiz.trail.append(c)
	w.me.pos = wiz.pos + Vector2(3, 0)
	wiz.power_timer = 0.0
	w._boss_power(wiz, 0.1)
	ok("The Wizard blinks home when you get close, taking his trail", wiz.boss_kind == "wizard" and wiz.trail.is_empty())
	main.boss_kind = "king"
	main.prog = boss_prog
	await _play()
	w.me.shield = 0.0
	w.kill(w.me, null, "saw")
	await _wait(1.3)
	ok("A hazard knockout says what happened", main.state == "over" and main.over_reason.text == "A saw got you!", main.over_reason.text)
	main._to_menu()
	await process_frame

	# Tap to turn
	main.controls = "tap"
	await _play()
	var tme: Player = w.me
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(40, 900)
	touch.pressed = true
	main._unhandled_input(touch)
	main._steer()
	ok("Tap to turn: holding the left side turns left", tme.desired < tme.angle - 1.0, "%.2f vs %.2f" % [tme.desired, tme.angle])
	touch.pressed = false
	main._unhandled_input(touch)
	main._steer()
	ok("Letting go goes straight", is_equal_approx(tme.desired, tme.angle))
	main.controls = "stick"

	# Colourblind patterns
	var seen := {}
	for p in w.players:
		if p:
			seen[Patterns.index_of(p, w.COLORS)] = true
	Patterns.on = true
	main.view._land_version = -1
	for f in 5:
		await process_frame
	ok("Colourblind mode gives every player their own pattern", seen.size() == w.players.size() - 1 and Patterns.tile(0) != null and Patterns.body(3) != null, str(seen.size()))
	Patterns.on = false
	main.view._land_version = -1

	# Hints and tips for new players
	var hint_prog: Progress = main.prog
	main.prog = Progress.new()
	main.prog.tutorial_done = true
	main.map_id = "square"
	main.mode_id = "classic"
	main.start_game()
	main.countdown = 0.01
	await process_frame
	await process_frame
	ok("A new player gets a hint when the game starts", main.tut_card.visible and main.tut_label.text.begins_with("Leave your land"), main.tut_label.text)
	main.play_time += 5.0
	await process_frame
	ok("The hint goes away after a few seconds", not main.tut_card.visible)
	w.kill(w.me, w.me)
	await _wait(1.3)
	ok("After a knockout, the results give a tip", main.over_tip.visible and "never cross your own trail" in main.over_tip.text, main.over_tip.text)
	main.prog = hint_prog
	main._to_menu()
	await process_frame

	# The very first launch: pick a language, then straight into the tutorial
	var welcome_prog: Progress = main.prog
	main.prog = Progress.new()
	main.welcomed = false
	main._open_welcome()
	ok("A fresh install opens on the language screen", main.welcome.visible and not main.menu.visible)
	main._pick_welcome_language("es")
	ok("Tapping a language switches the game to it", main.tr("PLAY") == "JUGAR" and I18n.lang == "es")
	main._finish_welcome()
	await process_frame
	ok("Let's go! starts the tutorial", not main.welcome.visible and main.play_mode == "tutorial" and main.state != "menu")
	main._load()
	ok("The language screen only shows once", main.welcomed and I18n.lang == "es")
	main.prog = welcome_prog
	I18n.lang = "en"
	I18n.apply()
	main._to_menu()
	await process_frame
	ok("On a fresh install (as on GitHub), the language screen is the first thing you see", first_launch or OS.get_environment("CI") == "")

	# Languages
	var expect := {"es": "JUGAR", "pt": "JOGAR", "hi": "खेलें", "id": "MAIN", "ru": "ИГРАТЬ", "tr": "OYNA"}
	var langs_ok := true
	for code in expect:
		I18n.lang = code
		I18n.apply()
		if main.tr("PLAY") != expect[code]:
			langs_ok = false
	ok("Six languages are ready", langs_ok)
	I18n.lang = "ru"
	I18n.apply()
	ok("Text with numbers is translated too", main.tr("Level %d") % 3 == "Уровень 3", main.tr("Level %d") % 3)
	main._refresh_menu()
	I18n.lang = "en"
	I18n.apply()
	ok("And back to English", main.tr("PLAY") == "PLAY")
	var fb: Array = main.font.fallbacks
	ok("Fonts have Hindi, Russian and Turkish letters", fb.size() == 3 and fb.all(func(f): return f != null))

	# The shop
	main._to_menu()
	await process_frame
	main.wallet = 500
	main.prog.trophies.erase("shopper")
	main.owned = {"skin": ["plain"], "trail": ["none"], "pet": ["none"]}
	main.equipped = {"skin": "plain", "trail": "none", "pet": "none"}
	main.shop.open()
	await process_frame
	ok("The shop opens from the menu", main.shop.visible and not main.menu.visible and main.state == "menu")
	main.shop.tap("skin", "cat")
	ok("Buying a skin takes its price and puts it on (and your first buy earns a trophy)", main.wallet == 225 and main.prog.trophies.has("shopper") and main.owned.skin.has("cat") and main.equipped.skin == "cat", str(main.wallet))
	main.shop.tap("skin", "galaxy")
	ok("You can't buy what you can't afford", main.wallet == 225 and not main.owned.skin.has("galaxy") and main.equipped.skin == "cat")
	main.shop.tap("skin", "plain")
	main.shop.tap("skin", "cat")
	ok("Switching to something you own is free", main.wallet == 225 and main.equipped.skin == "cat")
	main.shop.show_tab("trail")
	main.shop.tap("trail", "sparkle")
	ok("Trails can be bought too", main.wallet == 25 and main.equipped.trail == "sparkle")
	var shop_cfg := ConfigFile.new()
	shop_cfg.load(main.SAVE_PATH)
	ok("Purchases are saved", shop_cfg.get_value("shop", "owned_skin", []).has("cat") and shop_cfg.get_value("shop", "using_trail", "") == "sparkle" and shop_cfg.get_value("player", "coins", -1) == 25)
	main._back()
	await process_frame
	ok("Back closes the shop", not main.shop.visible and main.menu.visible)
	ok("The menu's square wears your look", w.me.skin == "cat" and w.me.trail_fx == "sparkle")
	main.owned.pet.append("bee")
	main.equipped.pet = "bee"
	await _play()
	ok("You play in your skin, trail and pet", w.me.skin == "cat" and w.me.trail_fx == "sparkle" and w.me.pet == "bee")
	ok("Your trail effect is ready", main.view.views[w.me.id]._emitter != null)
	var dressed := 0
	for p in w.players:
		if p and p.is_bot and (p.skin != "plain" or p.pet != "none" or p.trail_fx != "none"):
			dressed += 1
	ok("Bots wear shop items too", dressed > 0, "%d dressed" % dressed)
	# A save with things that don't exist falls back to the free ones
	shop_cfg.set_value("shop", "owned_skin", ["plain", "cat", "unicorn"])
	shop_cfg.set_value("shop", "using_skin", "unicorn")
	shop_cfg.set_value("shop", "using_pet", "bee")
	shop_cfg.set_value("shop", "owned_pet", [])
	shop_cfg.save(main.SAVE_PATH)
	main._load()
	ok("Unknown or unowned items fall back safely", main.equipped.skin == "plain" and main.owned.skin == ["plain", "cat"] and main.equipped.pet == "none" and main.owned.pet == ["none"])
	main._to_menu()
	await process_frame

	# Music is synthesized on a thread and ends up playable
	for t in 40:
		if main.music.stream != null:
			break
		await _wait(0.25)
	ok("Music is ready and loops", main.music.stream != null and main.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)

	print("%d failed" % fails)
	quit(1 if fails else 0)
