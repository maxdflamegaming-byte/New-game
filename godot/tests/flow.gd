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


func _play() -> void:
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
	ok("Coins and best are saved", cfg.get_value("player", "coins", -1) == main.wallet and cfg.get_value("stats", "best", 0.0) >= 50.0)

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
		await _play()
		if w.map_id != m or not w.me.alive or w.wall[w.me.cell.y * w.N + w.me.cell.x] != 0:
			bad.append(m)
	ok("Every map starts with you on open ground", bad.is_empty(), str(bad))

	# Music is synthesized on a thread and ends up playable
	for t in 40:
		if main.music.stream != null:
			break
		await _wait(0.25)
	ok("Music is ready and loops", main.music.stream != null and main.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)

	print("%d failed" % fails)
	quit(1 if fails else 0)
