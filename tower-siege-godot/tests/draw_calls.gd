extends SceneTree
## How much a crowded battle costs to draw, on each graphics setting (needs a screen: run it
## under xvfb-run with opengl3, like phone.gd). Cheap phones slow down with many draw calls,
## so each setting has a budget:
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/draw_calls.gd
## Prints PASS/FAIL lines and "DRAW DONE n failed".

const BUDGET := {"low": 190, "medium": 270, "high": 290}

var main
var fails := 0


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1600))
	root.size = Vector2i(720, 1600)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()


func _run() -> void:
	for i in 20:
		await process_frame
	for q in ["low", "medium", "high"]:
		main.set_gfx(q)
		main.save.level = 80
		# A big map, both sides played by the computer with large armies
		main.start_level(30)
		main.battle.ai_sides.append({"side": 1, "timer": 0.3, "cfg": {"think": 0.8, "margin": 2.0, "bold": 0.6}})
		for t in main.battle.towers:
			if t.owner != 0:
				t.units += 40
		for i in 300:
			main.battle.update(0.05)
		for i in 30:
			await process_frame
		var most := 0
		for i in 30:
			await process_frame
			most = maxi(most, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		ok("%s graphics: a crowded battle (%d soldiers) stays within %d draw calls" % [q.capitalize(), main.battle.units.size(), BUDGET[q]], most <= BUDGET[q], "%d draw calls" % most)
	print("DRAW DONE %d failed" % fails)
	quit(1 if fails else 0)
