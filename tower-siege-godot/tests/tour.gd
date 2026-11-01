extends SceneTree
## Screenshots of every screen, for checking by eye (needs a screen: xvfb, opengl3):
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/tour.gd -- OUT_DIR [LANG]
## A player who has seen most of the game: every screen from the menu, a battle's HUD, the
## pause, briefing, win and defeat screens, 2 players, and the settings with the frame rate on.

var main
var out := "/tmp/tour"
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(720, 1600))
	root.size = Vector2i(720, 1600)
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run(args[1] if args.size() > 1 else "")


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func shot(name: String) -> void:
	await _frames(25)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(360, 800, Image.INTERPOLATE_BILINEAR)
	n += 1
	img.save_png("%s/%02d-%s.png" % [out, n, name])


func _run(lang: String) -> void:
	await _frames(40)
	if lang != "":
		main.set_lang(lang)
	var s: Dictionary = main.save
	s.level = 34
	s.coins = 4321
	s.trophies = 640
	for i in range(1, 34):
		s.stars[str(i)] = 1 + i % 3
	s.show_fps = true
	main.reward_shown_day = Progress.today()
	main.open_menu()
	await shot("menu")
	main.ui.more_panel.visible = true
	await shot("menu-more")
	main.ui.more_panel.visible = false
	for id in ["levels", "missions", "profile", "achievements", "looks", "shop", "event", "replays", "settings", "help", "pvp", "pvp-help", "board", "clans"]:
		main.open_menu()
		main.ui.show_screen(id)
		await shot(id)
	main.open_menu()
	main.reward_shown_day = -1
	s.streak = {"day": -5, "count": 3}
	main.open_menu()
	await shot("reward")
	main.reward_shown_day = Progress.today()
	# A battle: the briefing, the HUD, the pause screen
	main.open_menu()
	main.start_level(34)
	await _frames(10)
	if main.screen_open == "brief":
		await shot("brief")
		main.ui.screens.brief.visible = false
		main.ui.show_screen("")
		main.begin_battle() if main.has_method("begin_battle") else null
	await _frames(10)
	var guard := 0
	while main.state != "play" and guard < 200:
		guard += 1
		for b in main.ui.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and (b.text.contains("Play") or b.text.contains("Go") or b.text.contains("Start") or b.text.contains("Fight")):
				b.pressed.emit()
				break
		await _frames(3)
	main.battle.ai_sides.append({"side": 1, "timer": 0.3, "cfg": {"think": 0.8, "margin": 2.0, "bold": 0.6}})
	await _frames(240)
	await shot("battle")
	main.pause()
	await shot("paused")
	main.resume()
	# Win
	for t in main.battle.towers:
		t.owner = 1
	main.battle.units.clear()
	var until := Time.get_ticks_msec() + 8000
	while main.screen_open != "win" and Time.get_ticks_msec() < until:
		if main.state == "cutscene":
			main.cutscene.skip()
		await _frames(2)
	await shot("win")
	# Lose
	main.open_menu()
	main.start_level(20)
	guard = 0
	while main.state != "play" and guard < 200:
		guard += 1
		for b in main.ui.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and (b.text.contains("Play") or b.text.contains("Go") or b.text.contains("Start") or b.text.contains("Fight")):
				b.pressed.emit()
				break
		await _frames(3)
	for t in main.battle.towers:
		if t.owner == 1:
			t.owner = 2
	until = Time.get_ticks_msec() + 8000
	while main.screen_open != "lose" and Time.get_ticks_msec() < until:
		if main.state == "cutscene":
			main.cutscene.skip()
		await _frames(2)
	await shot("lose")
	# 2 players on one phone, and its result
	main.open_menu()
	main.net.start_pvp("duo", 4242)
	await _frames(200)
	await shot("duo")
	for t in main.battle.towers:
		t.owner = 1
	main.battle.units.clear()
	until = Time.get_ticks_msec() + 8000
	while main.screen_open != "pvp-end" and Time.get_ticks_msec() < until:
		await _frames(2)
	await shot("duo-end")
	print("TOUR DONE %d shots" % n)
	quit(0)
