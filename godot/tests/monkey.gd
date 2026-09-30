extends SceneTree
## A random stress test: starts games in every mode and map, pauses, resumes, quits, opens
## every screen, flips settings and languages, all at random and fast, and reports any
## script error. Run with rendering (xvfb-run, --rendering-driver opengl3) to catch drawing
## errors too:  godot --path godot -s tests/monkey.gd -- [seconds] [seed]

var main
var seconds := 120.0
var actions := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seconds = float(args[0])
	seed(int(args[1]) if args.size() > 1 else 1)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _act(name: String) -> void:
	actions[name] = actions.get(name, 0) + 1


func _run() -> void:
	await create_timer(0.5).timeout
	main.welcomed = true
	main.welcome.visible = false
	main.prog.tutorial_done = true
	OnlineConfig.off = true # never the real server (tests/online_client.gd tests online)
	var modes: Array = main.world.MODES.keys()
	var maps: Array = main.world.MAPS.keys()
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		var r := randi() % 20
		if main.state == "menu" and r < 6:
			main.mode_id = modes.pick_random()
			if main.mode_id == "tutorial":
				main.start_tutorial()
			else:
				main.map_id = maps.pick_random()
				main.difficulty = ["easy", "normal", "hard"].pick_random()
				main.boss_kind = ["king", "queen", "wizard"].pick_random()
				main.start_game()
			_act("start " + main.play_mode)
		elif main.state == "play" and r < 3:
			main._pause()
			_act("pause")
		elif main.state == "paused" and r < 10:
			main._resume() if randf() < 0.7 else main._to_menu()
			_act("resume/quit")
		elif main.state == "over" and r < 8:
			main.start_game() if randf() < 0.5 else main._to_menu()
			_act("again/menu")
		elif r == 10:
			Gfx.level = randi() % Gfx.LEVELS.size()
			Gfx.fps = Gfx.FPS.pick_random()
			main._apply_gfx()
			_act("graphics")
		elif r == 11 and main.state == "menu":
			var sc = [main.shop, main.missions_screen, main.profile_screen, main.settings_screen].pick_random()
			sc.open()
			await create_timer(0.3).timeout
			sc.close()
			_act("screen")
		elif r == 12:
			Patterns.on = not Patterns.on
			main.view._land_version = -1
			_act("colourblind")
		elif r == 13:
			I18n.lang = I18n.LANGS.keys().pick_random()
			I18n.apply()
			if main.state == "menu":
				main._refresh_menu()
			_act("language")
		elif r == 14:
			main.controls = "tap" if main.controls == "stick" else "stick"
			_act("controls")
		elif r == 15 and main.state == "play":
			# Fast-forward a few seconds of play
			for i in 180:
				main.world.update(1.0 / 60)
				if main.state != "play":
					break
			_act("fast-forward")
		elif r == 16:
			main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
			_act("background")
		elif r == 17 and main.state == "play":
			# Steer at random
			main.world.me.desired = randf() * TAU
		for f in 3:
			await process_frame
	print("MONKEY DONE  ", actions)
	quit()
