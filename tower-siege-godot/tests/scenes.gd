extends SceneTree
## A contact sheet of frames from a cut scene, for checking camera work and animation by eye
## (run under xvfb-run, opengl3; dialogs move on by themselves):
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/scenes.gd -- WHAT OUT.png [SECONDS_APART] [FRAMES]
## WHAT: intro, levelN (the scenes before level N), victory, defeat, bossdown or ending.
var main
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1280))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tower_siege.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	await _frames(20)
	var what := OS.get_cmdline_user_args()[0]
	var out := OS.get_cmdline_user_args()[1]
	var every := float(OS.get_cmdline_user_args()[2]) if OS.get_cmdline_user_args().size() > 2 else 0.5
	var count := int(OS.get_cmdline_user_args()[3]) if OS.get_cmdline_user_args().size() > 3 else 16
	main.cutscene.auto = true
	main.save.level = 61
	if what == "intro":
		main.start_level(1)
	elif what.begins_with("level"):
		main.start_level(int(what.substr(5)))
	elif what == "victory" or what == "defeat" or what == "bossdown" or what == "ending":
		main.cinematics = false
		main.start_level(10 if what == "bossdown" else 60 if what == "ending" else 4)
		await _frames(5)
		main.cinematics = true
		for t in main.battle.towers:
			if what == "defeat":
				if t.owner == 1:
					t.owner = 2
			elif t.owner >= 2:
				t.owner = 1
		main.battle.units.clear()
	var shots := []
	for i in count:
		await create_timer(every).timeout
		var img := root.get_texture().get_image()
		img.resize(360, 640)
		shots.append(img)
	var cols := 4
	var sheet := Image.create(360 * cols, 640 * ceili(shots.size() / float(cols)), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, 360, 640), Vector2i((i % cols) * 360, (i / cols) * 640))
	sheet.save_png(out)
	print("SHEET %d state=%s screen=%s" % [shots.size(), main.state, main.screen_open])
	quit()
