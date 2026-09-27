extends SceneTree
## Screenshots of the real game (run with a display, e.g. under xvfb-run):
##   godot --path godot --rendering-driver opengl3 -s tests/shots.gd -- OUT_DIR WIDTH HEIGHT

var main
var out := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 2:
		DisplayServer.window_set_size(Vector2i(int(args[1]), int(args[2])))
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
	await _shot("1-menu")
	main.start_game()
	main.world.me.is_bot = true # let the game play itself
	main.world.bots.give_personality(main.world.me, "explorer")
	await _wait(1.5)
	await _shot("2-countdown")
	await _wait(9.0)
	await _shot("3-play")
	main.world.me.shield = 30.0
	await _wait(12.0)
	await _shot("4-play-later")
	main._game_over(true, "You claimed 50% of the map!")
	await _wait(0.6)
	await _shot("5-over")
	quit()
