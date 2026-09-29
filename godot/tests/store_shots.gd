extends SceneTree
## Screenshots for the Google Play listing (run under xvfb-run, see store/README.md):
##   godot --path godot --rendering-driver opengl3 -s tests/store_shots.gd -- OUT_DIR
## Each game is fast-forwarded until the board is busy, so the pictures show real play.

var main
var out := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## Starts a game that plays itself, then runs it `seconds` of game time ahead
func _game(mode: String, map: String, seconds: float) -> void:
	main.mode_id = mode
	main.map_id = map
	main.start_game()
	main.countdown = 0.0
	var w = main.world
	for h in w.humans():
		h.is_bot = true
		w.bots.give_personality(h, "explorer")
	await _wait(0.3)
	# While fast-forwarding, you're shielded, and a knockout doesn't end the game
	main.ending = true
	var steps := int(seconds * 60)
	for i in steps:
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		w.update(1.0 / 60)
		for h in w.humans():
			if not h.alive:
				w.spawn(h)
		if i % 600 == 599:
			await process_frame # let the views catch up
	for h in w.humans():
		h.shield = 0.0
	main.ending = false
	main._snap_camera()
	# Sweep away leftover effects from the fast-forward
	for c in main.view._top.get_children():
		c.queue_free()
	await _wait(1.2)


func _run() -> void:
	await _wait(0.5) # let the game start up
	Gfx.level = Gfx.HIGH
	Gfx.show_fps = false
	main._apply_gfx()
	main.prog.tutorial_done = true
	main.welcomed = true
	main.welcome.visible = false
	main.crash_box.visible = false
	Events.forced = "coins" # the menu shows an event
	if not main.prog.stats.modes.has("hill"):
		main.prog.stats.modes.append("hill") # no first-time hint cards in the pictures
	for m in ["bumpers", "ice"]:
		if not main.prog.stats.maps.has(m):
			main.prog.stats.maps.append(m)
	main.player_name = "You"
	main.difficulty = "normal"
	main.equipped = {"skin": "ninja", "trail": "stars", "pet": "dragon"}
	main.my_color = 0
	await _wait(1.5)

	# 1. Classic: loops and land
	await _game("classic", "square", 40.0)
	await _shot("1-classic")
	main._to_menu()

	# 2. Boss Battle against the Queen, with her traps
	main.equipped = {"skin": "galaxy", "trail": "fire", "pet": "chick"}
	main.prog.stats.king_wins = maxi(1, main.prog.stats.king_wins)
	main.boss_kind = "queen"
	await _game("boss", "square", 25.0)
	await _shot("2-boss")
	main._to_menu()
	main.boss_kind = "king"

	# 3. A new map: Pinball, with its bumpers, in reward-track gear
	main.equipped = {"skin": "gold", "trail": "lightning", "pet": "fox"}
	for kind in main.equipped:
		if not main.owned[kind].has(main.equipped[kind]):
			main.owned[kind].append(main.equipped[kind])
	await _game("classic", "bumpers", 35.0)
	main.tut_card.visible = false
	await _shot("3-pinball")
	main._to_menu()

	# 4. The shop
	main.wallet = 1240
	main.owned = {"skin": ["plain", "stripes", "cat", "ninja"], "trail": ["none", "stars"], "pet": ["none", "dragon"]}
	main.equipped = {"skin": "ninja", "trail": "stars", "pet": "dragon"}
	main.shop.open()
	await _wait(2.0)
	await _shot("4-shop")
	main.shop.close()

	# 5. The menu
	await _wait(3.0)
	await _shot("5-menu")

	# 6. A win, with rewards
	await _game("hill", "square", 30.0)
	main.tut_card.visible = false
	main.peak = 34.6
	main.play_time = 131.0
	main.world.me.kills = 3
	main._game_over(true, "You held the hill for 100 points!")
	await _wait(3.0)
	await _shot("6-results")
	main._to_menu()

	# 7. Missions and the profile
	main.missions_screen.open()
	await _wait(1.0)
	await _shot("7-missions")
	main.missions_screen.close()
	main.profile_screen.open()
	await _wait(1.0)
	await _shot("8-profile")
	quit()
