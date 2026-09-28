extends SceneTree
## Frame-time profile of a busy game (run under xvfb-run with opengl3):
##   godot --path godot --rendering-driver opengl3 -s tests/bench.gd -- [level] [map]
## Prints how long the scripts take per frame, split by part, so slow code shows up.

var main
var level := 2
var map := "square"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		level = int(args[0])
	if args.size() > 1:
		map = args[1]
	DisplayServer.window_set_size(Vector2i(720, 1280))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	main.welcomed = true
	if main.welcome:
		main.welcome.visible = false
	main.prog.tutorial_done = true
	Gfx.level = level
	Gfx.fps = 60
	main._apply_gfx()
	Engine.max_fps = 0
	main.mode_id = "classic"
	main.map_id = map
	main.start_game()
	main.countdown = 0.0
	var w = main.world
	for h in w.humans():
		h.is_bot = true
		w.bots.give_personality(h, "explorer")
	# Warm up: let the board fill with land and trails
	main.ending = true
	for i in 60 * 40:
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		w.update(1.0 / 60)
		for h in w.humans():
			if not h.alive:
				w.spawn(h)
	main.ending = false
	await process_frame
	var frames := 0
	var t_proc := 0.0
	var t_world := 0.0
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	while frames < 600:
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		var a := Time.get_ticks_usec()
		await process_frame
		var d := (Time.get_ticks_usec() - a) / 1000.0
		worst = maxf(worst, d)
		t_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		frames += 1
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	# Parts timed on their own
	var parts := {}
	var n := 200
	var s := Time.get_ticks_usec()
	for i in n:
		w.update(1.0 / 60)
	parts["world.update"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	s = Time.get_ticks_usec()
	for i in n:
		main._update_hud()
	parts["_update_hud"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	s = Time.get_ticks_usec()
	for i in n:
		main._update_minimap()
	parts["_update_minimap"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	s = Time.get_ticks_usec()
	for i in n:
		main._check_danger()
	parts["_check_danger"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	s = Time.get_ticks_usec()
	for i in n:
		main.view._update_trails()
	parts["_update_trails"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	s = Time.get_ticks_usec()
	for i in n:
		main.view._process(1.0 / 60)
	parts["view._process"] = (Time.get_ticks_usec() - s) / 1000.0 / n
	print("level %d map %s players %d alive %d" % [level, map, w.players.size(), w.alive_count()])
	print("frame avg %.2f ms (%.0f fps), worst %.1f ms, process avg %.2f ms" % [total / frames, 1000.0 * frames / total, worst, t_proc / frames])
	for k in parts:
		print("  %-16s %.3f ms" % [k, parts[k]])
	# What each layer costs: hide it and see how much faster frames get
	var base := await _avg(w, 300)
	print("  all layers      %.2f ms" % base)
	for layer in ["_actors", "_fx", "_items", "_trails", "_glows", "_air", "_hazards", "_top", "_land"]:
		var node: Node2D = main.view.get(layer)
		node.visible = false
		print("  without %-8s %.2f ms" % [layer, base - await _avg(w, 300)])
		node.visible = true
	main.hud.visible = false
	print("  without hud      %.2f ms" % [base - await _avg(w, 300)])
	main.hud.visible = true
	print("objects %d nodes %d" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("draw calls %d items %d prims %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	quit()


func _avg(w, frames: int) -> float:
	await process_frame
	var t0 := Time.get_ticks_usec()
	for i in frames:
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames
