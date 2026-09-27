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

	# Music is synthesized on a thread and ends up playable
	for t in 40:
		if main.music.stream != null:
			break
		await _wait(0.25)
	ok("Music is ready and loops", main.music.stream != null and main.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)

	print("%d failed" % fails)
	quit(1 if fails else 0)
