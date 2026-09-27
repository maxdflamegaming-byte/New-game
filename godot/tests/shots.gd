extends SceneTree
## Screenshots of the real game (run with a display, e.g. under xvfb-run):
##   godot --path godot --rendering-driver opengl3 -s tests/shots.gd -- OUT_DIR WIDTH HEIGHT [GAMES]
## GAMES is a comma-separated list of maps, or of mode:map pairs (e.g. boss:square,duo:round).
## "shop" takes the shop's three tabs; "looks:MAP" plays with a skin, trail effect and pet on.

var main
var out := "/tmp"
var maps := ["square", "round", "pillars", "maze", "islands"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 2:
		DisplayServer.window_set_size(Vector2i(int(args[1]), int(args[2])))
	if args.size() > 3:
		maps = args[3].split(",")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	await _wait(2.5)
	await _shot("0-menu")
	for m in maps:
		if m == "screens":
			main.prog.finish({"mode": "classic", "map": "square", "won": true, "pct": 55.0, "kos": 4, "powerups": 3, "time": 200.0, "best_loop": 7.0}, main.world.today())
			main.prog.finish({"mode": "boss", "map": "round", "won": true, "pct": 20.0, "lives_lost": 0}, main.world.today())
			main.equipped = {"skin": "robot", "trail": "stars", "pet": "bee"}
			main._to_menu()
			await _wait(1.0)
			await _shot("menu")
			for sc in ["missions_screen", "profile_screen", "settings_screen"]:
				main.get(sc).open()
				await _wait(0.8)
				await _shot(sc)
				main.get(sc).close()
			continue
		if m == "tutorial":
			main.start_tutorial()
			await _wait(6.0)
			await _shot("tutorial-1")
			main._tut_step = 3
			main._place_tut_powerup()
			await _wait(1.0)
			await _shot("tutorial-3")
			main._to_menu()
			continue
		if m == "results":
			main.prog.tutorial_done = true
			main.mode_id = "classic"
			main.start_game()
			await _wait(4.0)
			main.peak = 51.0
			main._game_over(true, "You claimed 50% of the map!")
			await _wait(2.5)
			await _shot("results")
			main._to_menu()
			continue
		if m == "shop":
			main.wallet = 700
			main.owned.skin.append("cat")
			main.shop.open()
			for tab in ["skin", "trail", "pet"]:
				main.equipped = {"skin": "ninja", "trail": "stars", "pet": "dragon"}
				main.shop.show_tab(tab)
				await _wait(1.6)
				await _shot("shop-" + tab)
			main.shop.close()
			continue
		var parts: PackedStringArray = m.split(":")
		main.mode_id = parts[0] if parts.size() > 1 and parts[0] != "looks" else "classic"
		if parts[0] == "looks":
			main.equipped = {"skin": "galaxy", "trail": "fire", "pet": "chick"}
		main.map_id = parts[-1]
		main.start_game()
		var w = main.world
		for h in w.humans():
			h.is_bot = true # let the game play itself
			w.bots.give_personality(h, "explorer")
		await _wait(8.0)
		w.me.shield = 30.0
		# Put some power-ups and coins near you, and show a few effects
		var at: Vector2 = w.me.pos
		var kinds := ["speed", "shield", "freeze", "ghost", "paint"]
		for k in 5:
			var q: Vector2 = at + Vector2.from_angle(k * TAU / 5 + 0.4) * 5.0
			if not w.is_wall_at(q.x, q.y):
				w.powerups.append({"pos": q, "kind": kinds[k], "age": 1.0})
		for k in 4:
			var q: Vector2 = at + Vector2.from_angle(k * TAU / 4) * 3.0
			if not w.is_wall_at(q.x, q.y):
				w.coins.append({"pos": q, "age": 1.0, "life": 20.0})
		w.me.fx.speed = 5.0
		await _wait(0.7)
		await _shot("map-" + m.replace(":", "-"))
	quit()
