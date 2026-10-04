extends SceneTree
## Screenshots for checking by eye (run under xvfb-run, opengl3):
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/look.gd -- OUT_DIR WHAT [W H]
## WHAT: menu, level:N (a battle with both sides played by the computer for a few seconds),
## or a screen name (levels, shop, help, win, lose, pvp).

var main
var out := "/tmp"
var what := "menu"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	what = args[1] if args.size() > 1 else what
	var size := Vector2i(int(args[2]), int(args[3])) if args.size() > 3 else Vector2i(720, 1280)
	DisplayServer.window_set_size(size)
	root.size = size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(30)
	var q := OS.get_environment("GFX")
	if q != "":
		main.set_gfx(q)
	if what.begins_with("level:"):
		var n := int(what.split(":")[1])
		main.save.level = 60
		main.start_level(n)
		# Both sides played by the computer, with bigger armies, so there's a battle to see
		main.battle.ai_sides.append({"side": 1, "timer": 0.3, "cfg": {"think": 0.8, "margin": 2.0, "bold": 0.6}})
		for a in main.battle.ai_sides:
			a.cfg = a.cfg.duplicate()
			a.cfg.think = 0.8
		for t in main.battle.towers:
			if t.owner != 0:
				t.units += 25
		for i in 200:
			main.battle.update(0.05)
		await _frames(40)
	elif what == "pvp":
		main.net.open_pvp()
		await _frames(10)
	elif what in ["levels", "shop", "help", "settings"]:
		main.ui.show_screen(what)
		await _frames(10)
	elif what == "win":
		main.start_level(4)
		await _frames(5)
		main.ui.show_win(3, 33, "Rally unlocked! Double your marching power for 8 seconds.", 41.0, {"captured": 6, "killed": 40})
		await _frames(60)
	elif what == "lose":
		main.start_level(4)
		await _frames(5)
		main.show_lose()
		await _frames(20)
	else:
		await _frames(60)
	var img := root.get_texture().get_image()
	img.save_png("%s/godot-%s.png" % [out, what.replace(":", "-")])
	print("SHOT %s" % what)
	quit()
