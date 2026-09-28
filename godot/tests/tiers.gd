extends SceneTree
## One screenshot of the same game at each graphics level (run under xvfb-run):
##   godot --path godot --rendering-driver opengl3 -s tests/tiers.gd -- OUT_DIR

var main
var out := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	main.welcomed = true
	if main.welcome:
		main.welcome.visible = false
	main.prog.tutorial_done = true
	main.equipped = {"skin": "ninja", "trail": "none", "pet": "none"}
	main.mode_id = "classic"
	main.map_id = "square"
	seed(7)
	main.start_game()
	main.countdown = 0.0
	var w = main.world
	for h in w.humans():
		h.is_bot = true
		w.bots.give_personality(h, "explorer")
	main.ending = true
	for i in 60 * 30:
		for h in w.humans():
			h.shield = maxf(h.shield, 0.5)
		w.update(1.0 / 60)
		for h in w.humans():
			if not h.alive:
				w.spawn(h)
	main.ending = false
	main._snap_camera()
	w.me.shield = 0.0
	get_root().get_tree().paused = false
	for lv in 3:
		Gfx.level = lv
		main._apply_gfx()
		main.state = "won" # hold the game still
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/tier-%d.png" % [out, lv])
		print("saved tier ", lv)
	quit()
