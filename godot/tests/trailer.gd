extends SceneTree
## A gameplay video for the store listings (Uptodown, YouTube), recorded with Godot's movie maker:
##   xvfb-run godot --path godot --rendering-driver opengl3 --write-movie OUT.avi --fixed-fps 30 \
##     -s tests/trailer.gd
## Then ffmpeg turns it into an MP4 (see store/README.md). The games play themselves at normal
## speed; you can't be knocked out of the game while it records (you just come back).

var main
var _keep_alive := false


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	process_frame.connect(_tick)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## Each frame while a game records: a knockout doesn't end it
func _tick() -> void:
	if not _keep_alive or main.world == null:
		return
	main.tut_card.visible = false # the video shows the game, not hint cards
	for h in main.world.humans():
		if not h.alive:
			main.world.spawn(h)


## Starts a game that plays itself, runs it `ahead` seconds forward (so the board is busy),
## then lets it play for real for `seconds`
func _game(mode: String, map: String, ahead: float, seconds: float) -> void:
	main.mode_id = mode
	main.map_id = map
	main.start_game()
	main.countdown = 0.0
	var w = main.world
	for h in w.humans():
		h.is_bot = true
		w.bots.give_personality(h, "explorer")
	main.ending = true
	for i in int(ahead * 60):
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		w.update(1.0 / 60)
		for h in w.humans():
			if not h.alive:
				w.spawn(h)
	for h in w.humans():
		h.shield = 0.0
	main._snap_camera()
	for c in main.view._top.get_children():
		c.queue_free()
	main.tut_card.visible = false
	_keep_alive = true
	await _wait(seconds)
	_keep_alive = false
	main.ending = false


func _run() -> void:
	Gfx.level = Gfx.HIGH
	Gfx.show_fps = false
	main._apply_gfx()
	main.prog.tutorial_done = true
	main.welcomed = true
	main.welcome.visible = false
	main.crash_box.visible = false
	Events.forced = "coins"
	I18n.lang = "en"
	I18n.apply()
	for m in ["hill", "boss", "timed"]:
		if not main.prog.stats.modes.has(m):
			main.prog.stats.modes.append(m) # no first-time hint cards
	for m in ["bumpers", "ice", "square"]:
		if not main.prog.stats.maps.has(m):
			main.prog.stats.maps.append(m)
	main.player_name = "You"
	main.difficulty = "normal"
	main.prog.level = maxi(main.prog.level, 7)
	main.prog.xp = Progress.need(main.prog.level) / 2
	main.games = maxi(main.games, 25)
	main.wins = maxi(main.wins, 12)
	main.bests["classic"] = maxf(main.bests.get("classic", 0.0), 46.3)
	main.wallet = 1240
	main.mode_id = "classic"
	main.map_id = "square"
	main.equipped = {"skin": "ninja", "trail": "stars", "pet": "dragon"}
	for kind in main.equipped:
		if not main.owned[kind].has(main.equipped[kind]):
			main.owned[kind].append(main.equipped[kind])
	main.my_color = 0
	main._start_demo()
	await _wait(3.0) # the home screen

	# Classic: leave your land, loop back, claim it
	await _game("classic", "square", 25.0, 14.0)
	main._to_menu()

	# Boss Battle against the Queen
	main.equipped = {"skin": "galaxy", "trail": "fire", "pet": "chick"}
	for kind in main.equipped:
		if not main.owned[kind].has(main.equipped[kind]):
			main.owned[kind].append(main.equipped[kind])
	main.prog.stats.king_wins = maxi(1, main.prog.stats.king_wins)
	main.boss_kind = "queen"
	await _game("boss", "square", 18.0, 9.0)
	main._to_menu()
	main.boss_kind = "king"

	# Pinball map with bumpers
	main.equipped = {"skin": "gold", "trail": "lightning", "pet": "fox"}
	for kind in main.equipped:
		if not main.owned[kind].has(main.equipped[kind]):
			main.owned[kind].append(main.equipped[kind])
	await _game("classic", "bumpers", 25.0, 8.0)
	main._to_menu()

	# Modes, then the shop
	main.equipped = {"skin": "ninja", "trail": "stars", "pet": "dragon"}
	main._start_demo()
	main.modes_screen.open()
	await _wait(2.5)
	main.modes_screen.scroller.scroll_vertical = 600
	await _wait(1.5)
	main.modes_screen.close()
	main.shop.open()
	await _wait(3.0)
	main.shop.close()

	# A win
	await _game("hill", "square", 25.0, 4.0)
	main.peak = 34.6
	main.play_time = 131.0
	main.world.me.kills = 3
	main._game_over(true, "You held the hill for 100 points!")
	await _wait(4.5)
	quit()
