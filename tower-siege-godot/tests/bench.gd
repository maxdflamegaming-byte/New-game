extends SceneTree
## Frame time of a battle on each graphics setting. Under xvfb (opengl3 on the CPU) the
## frame time mostly measures how much pixel work the GPU has, so it's a rough guide to
## what a slow phone feels:
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/bench.gd
var main

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
	var qs := ["low", "medium", "high"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("q="):
			qs = a.substr(2).split(",")
	for q in qs:
		main.save.level = 80
		main.set_gfx(q)
		main.start_level(30)
		main.battle.ai_sides.append({"side": 1, "timer": 0.3, "cfg": {"think": 0.8, "margin": 2.0, "bold": 0.6}})
		for a in OS.get_cmdline_user_args():
			if a == "nomsaa": root.msaa_3d = Viewport.MSAA_DISABLED
			if a == "half": root.scaling_3d_scale = 0.5
			if a == "noshadow": main.world.sun.shadow_enabled = false
			if a == "noui": main.ui.visible = false
			if a == "nooverlay": main.overlay.visible = false
			if a == "no2d":
				main.ui.visible = false
				main.overlay.visible = false
			if a == "noground" or a == "noprops":
				for c in main.world.level_root.get_children():
					if (a == "noground" and c is MeshInstance3D and c.material_override is ShaderMaterial and str(c.material_override.shader.resource_path).contains("ground")) or (a == "noprops" and c is MultiMeshInstance3D):
						c.visible = false
		for i in 30:
			await process_frame
		var tot := []
		var last := Time.get_ticks_usec()
		for i in 120:
			await process_frame
			var now := Time.get_ticks_usec()
			tot.append((now - last) / 1000.0)
			last = now
		tot.sort()
		print("BENCH %s: frame ms median %.1f p90 %.1f | draws %d prims %d" % [q, tot[60], tot[108], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	quit(0)
