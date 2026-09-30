extends SceneTree
## Screenshots of screens for checking by eye (run under xvfb-run, opengl3):
##   godot --path godot --rendering-driver opengl3 -s tests/look.gd -- OUT_DIR WHAT [W H]
## WHAT: shop (each tab, all items owned), profile, menu, or game:<mode>:<map>

var main
var out := "/tmp"
var what := "shop"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	what = args[1] if args.size() > 1 else what
	var size := Vector2i(int(args[2]), int(args[3])) if args.size() > 3 else Vector2i(720, 1280)
	DisplayServer.window_set_size(size)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	await create_timer(0.5).timeout
	main.welcomed = true
	main.welcome.visible = false
	main.crash_box.visible = false
	main.prog.tutorial_done = true
	I18n.lang = "en"
	I18n.apply()
	if what == "shop":
		for kind in Cosmetics.KINDS:
			main.owned[kind] = Cosmetics.items(kind).keys().slice(0, 4)
		main.wallet = 500
		main.shop.open()
		for kind in ["skin", "trail", "pet"]:
			main.shop.show_tab(kind)
			await create_timer(0.6).timeout
			main.shop.scroller.scroll_vertical = 10000
			await create_timer(0.4).timeout
			await _shot("shop-" + kind)
	elif what == "profile":
		main.prog.level = 4
		main.profile_screen.open()
		await create_timer(0.8).timeout
		await _shot("profile")
	elif what == "menu":
		await create_timer(1.5).timeout
		await _shot("menu")
	elif what.begins_with("modes"):
		# modes or modes:<level> (a new player sees most things locked)
		if what.contains(":"):
			main.prog.level = int(what.split(":")[1])
			main.mode_id = what.split(":")[2] if what.split(":").size() > 2 else main.mode_id
			main.new_unlocks = ["mode:online", "map:pillars"]
			main._refresh_menu()
			await create_timer(0.5).timeout
			await _shot("menu-level%d" % main.prog.level)
		main.modes_screen.open()
		await create_timer(0.8).timeout
		await _shot(what.replace(":", "-"))
		main.modes_screen.scroller.scroll_vertical = 10000
		await create_timer(0.5).timeout
		await _shot(what.replace(":", "-") + "-bottom")
	elif what == "settings":
		main.settings_screen.open()
		await create_timer(0.8).timeout
		await _shot("settings")
	elif what == "results":
		main.mode_id = "hill"
		main.start_game()
		main.countdown = 0.0
		await create_timer(0.5).timeout
		main.peak = 31.2
		main.play_time = 131.0
		main._game_over(true, "You held the hill for 100 points!")
		await create_timer(3.0).timeout
		await _shot("results")
	elif what.begins_with("game:"):
		var parts := what.split(":")
		main.mode_id = parts[1]
		main.map_id = parts[2]
		main.start_game()
		main.countdown = 0.0
		var w = main.world
		for h in w.humans():
			h.is_bot = true
		main.ending = true
		for i in 60 * 25:
			for h in w.humans():
				h.shield = maxf(h.shield, 0.5)
			w.update(1.0 / 60)
			for h in w.humans():
				if not h.alive:
					w.spawn(h)
		main.ending = false
		main._snap_camera()
		await create_timer(1.0).timeout
		await _shot("game-" + parts[1] + "-" + parts[2])
	quit()
