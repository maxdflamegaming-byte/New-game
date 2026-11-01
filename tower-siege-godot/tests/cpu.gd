extends SceneTree
## The game's own work per battle frame (main.cpu_ms: scripts and the 2D overlay), in a
## crowded battle where the computer plays both sides:
##   godot --headless --path tower-siege-godot -s tests/cpu.gd
## A phone is several times slower than a desktop, so this should stay well under 2 ms here.
var main

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1080, 2400))
	root.size = Vector2i(1080, 2400)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()

func _run() -> void:
	for i in 60:
		await process_frame
	main.save.level = 80
	for lv in [4, 30]:
		main.start_level(lv)
		main.tutor = null
		seed(5)
		if lv == 30:
			main.battle.ai_sides.append({"side": 1, "timer": 0.3, "cfg": {"think": 0.8, "margin": 2.0, "bold": 0.6}})
		var sum := 0.0
		var most := 0.0
		var units := 0
		for i in 600:
			await process_frame
			if i >= 60:
				sum += main.cpu_ms
				most = maxf(most, main.cpu_ms)
				units = maxi(units, main.battle.units.size())
		print("CPU level %d: game work %.2f ms a frame on average (smoothed peak %.2f), up to %d soldiers" % [lv, sum / 540.0, most, units])
	quit(0)
