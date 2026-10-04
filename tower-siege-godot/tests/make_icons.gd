extends SceneTree
## Makes the app icons from the game itself: level 1 with the HUD hidden and the camera close on
## your blue tower (run under xvfb-run, opengl3):
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/make_icons.gd
## Writes assets/icon.png (512, rounded corners), and the adaptive icon layers icon_fg.png,
## icon_bg.png and icon_mono.png (432).

var main


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(720, 1280))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The game's view of a tall blue tower, cut to a square
func _shot(size: int) -> Image:
	main.start_level(1)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	main.hand_shown = false
	main.set_hint("")
	main.ui.visible = false
	main.overlay.visible = false
	var t: Battle.Tower = main.battle.towers[0]
	t.units = 70
	await _frames(10)
	var cam: Camera3D = main.world.camera
	cam.position = Vector3(t.x + 120, 640, t.y + 620)
	cam.look_at(Vector3(t.x, 105, t.y))
	await _frames(20)
	var full := root.get_texture().get_image()
	full.convert(Image.FORMAT_RGBA8)
	var c := cam.unproject_position(Vector3(t.x, 105, t.y))
	var side := mini(full.get_width(), 560)
	var img := full.get_region(Rect2i(int(c.x - side / 2.0), int(c.y - side / 2.0), side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img


func _round_corners(img: Image) -> void:
	var size := img.get_width()
	var r := size * 0.22
	for y in size:
		for x in size:
			var dx := maxf(0, maxf(r - x, x - (size - 1 - r)))
			var dy := maxf(0, maxf(r - y, y - (size - 1 - r)))
			var a := clampf(r - sqrt(dx * dx + dy * dy) + 0.5, 0, 1)
			if a < 1:
				var p := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(p, a))


## A plain stacked-tower outline with a flag, for the monochrome (themed) icon
func _mono(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx := size / 2.0
	for y in size:
		for x in size:
			var a := 0.0
			# Four stacked floors, narrower going up, with a cap
			for i in 4:
				var top := size * (0.68 - i * 0.09)
				var w := size * (0.17 - i * 0.012)
				if y > top - size * 0.07 and y < top and absf(x - cx) < w:
					a = 1.0
			if y > size * 0.29 and y < size * 0.33 and absf(x - cx) < size * 0.15:
				a = 1.0
			# The flag
			if x > cx - 2 and x < cx + 4 and y > size * 0.16 and y < size * 0.3:
				a = 1.0
			if x >= cx + 4 and x < cx + size * 0.12 and y > size * 0.16 and y < size * 0.22:
				a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


func _run() -> void:
	await _frames(20)
	var shot := await _shot(512)
	var icon: Image = shot.duplicate()
	_round_corners(icon)
	icon.save_png("res://assets/icon.png")
	var fg: Image = shot.duplicate()
	fg.resize(432, 432, Image.INTERPOLATE_LANCZOS)
	fg.save_png("res://assets/icon_fg.png")
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(Color("#5fbf36"))
	bg.save_png("res://assets/icon_bg.png")
	_mono(432).save_png("res://assets/icon_mono.png")
	print("ICONS DONE")
	quit()
