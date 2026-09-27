extends SceneTree
## Screenshots of the real game (run with a display, e.g. under xvfb-run):
##   godot --path godot --rendering-driver opengl3 -s tests/shots.gd -- OUT_DIR WIDTH HEIGHT [GAMES]
## GAMES is a comma-separated list of maps, or of mode:map pairs (e.g. boss:square,duo:round)

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
		var parts: PackedStringArray = m.split(":")
		main.mode_id = parts[0] if parts.size() > 1 else "classic"
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
