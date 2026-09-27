extends SceneTree
## Plays many short games in a row and prints objects and memory, to catch leaks:
##   godot --headless --path godot -s tests/leak.gd

var main


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _run() -> void:
	await create_timer(0.3).timeout
	main.welcomed = true
	main.prog.tutorial_done = true
	var maps := ["square", "portals", "storm", "saws", "conveyor", "islands", "maze"]
	var modes := ["classic", "boss", "teams", "timed"]
	for g in 24:
		main.mode_id = modes[g % modes.size()]
		main.map_id = maps[g % maps.size()]
		main.start_game()
		main.countdown = 0.0
		var w = main.world
		for h in w.humans():
			h.is_bot = true
		for i in 900:
			w.update(1.0 / 60)
			if i % 30 == 0:
				await process_frame
			if main.state != "play":
				break
		if main.state == "play":
			main._game_over(false, "test")
		await process_frame
		main._to_menu()
		for i in 5:
			await process_frame
		print("game %2d  objects %d  nodes %d  orphans %d  mem %.1f MB" % [g, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	quit()
