extends SceneTree
## The game as a player sees it, without a screen: the menu, a level, dragging a road and
## swiping to cut it with touch events, winning (stars, coins, the next level saved), losing,
## and buying an upgrade.
##   godot --headless --path tower-siege-godot -s tests/flow.gd
## Prints PASS/FAIL lines and "FLOW DONE n failed".

var main
var fails := 0


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tower_siege.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	_touch(index, from, true)
	for i in 6:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = from.lerp(to, (i + 1) / 6.0)
		root.push_input(e, true)
		await process_frame
	_touch(index, to, false)
	await process_frame


func _run() -> void:
	await _frames(10)
	ok("The menu shows with a battle behind it", main.screen_open == "menu" and main.state == "menu" and main.battle.towers.size() > 4)

	main.start_level(1)
	await _frames(3)
	ok("Play starts level 1", main.state == "play" and main.level == 1 and main.battle.towers.size() == 4)
	ok("Level 1 shows the hint and the hand", main.hand_shown and main.hint_text != "")
	# Freeze the enemy (with no enemies at all, the level would count as won)
	for side in main.battle.ai_sides:
		side.timer = 1e9
	var me: Battle.Tower = main.battle.towers[0]
	var gray: Battle.Tower = main.battle.towers[1]
	var a: Dictionary = main.world.tower_screen(me)
	var b: Dictionary = main.world.tower_screen(gray)
	await _drag(0, Vector2(a.x, a.y), Vector2(b.x, b.y))
	ok("Dragging builds a road", me.has_road(gray))
	ok("The hand goes away after the first road", not main.hand_shown)
	await _frames(30)
	for i in 30:
		main.battle.update(0.05)
	ok("Soldiers march along the road", main.battle.units.any(func(u): return u.owner == 1))

	# Swipe straight across the road
	var p1: Vector2 = main.world.project(me.x, me.y)
	var p2: Vector2 = main.world.project(gray.x, gray.y)
	var mid := (p1 + p2) / 2
	var n := (p2 - p1).normalized().orthogonal() * 70
	await _drag(1, mid - n, mid + n)
	ok("Swiping across a road cuts it", not me.has_road(gray))

	# Winning
	for t in main.battle.towers:
		if t.owner == 2:
			t.owner = 1
	main.battle.units.clear()
	await _frames(5)
	ok("Taking every enemy building wins", main.state == "over")
	await create_timer(1.5).timeout
	ok("The win screen shows", main.screen_open == "win")
	ok("A win is saved: next level, stars, coins", int(main.save.level) == 2 and int(main.save.stars.get("1", 0)) >= 1 and int(main.save.coins) > 0, JSON.stringify(main.save))

	# Losing
	main.start_level(2)
	await _frames(3)
	for t in main.battle.towers:
		if t.owner == 1:
			t.owner = 2
	main.battle.units.clear()
	await _frames(5)
	await create_timer(1.5).timeout
	ok("Losing every building shows Defeat", main.screen_open == "lose")

	# Upgrades
	main.save.coins = 500
	main.buy("drill")
	ok("Buying an upgrade spends coins", int(main.save.up.drill) == 1 and int(main.save.coins) == 440)
	main.ui.show_screen("shop")
	await _frames(3)
	ok("The shop opens", main.screen_open == "shop")

	# 2 players on one phone: both colors can be dragged, and blue cuts from the bottom half
	main.net.start_pvp("duo", 12345)
	await _frames(3)
	ok("2 players on one phone starts with no bots", main.mode == "duo" and main.battle.ai_sides.is_empty())
	ok("Both blue and red can be steered", main.controls(1) and main.controls(2))
	main.net.start_pvp("practice", 777)
	ok("Practice has a bot", main.mode == "practice" and main.battle.ai_sides.size() == 1)

	# Graphics settings
	main.set_gfx("low")
	ok("Low graphics: no smoothing, no soldier shadows", main.world.quality == 0 and not main.world.soldier_shadows.visible and get_root().msaa_3d == Viewport.MSAA_DISABLED)
	main.set_gfx("high")
	ok("High graphics: full resolution", main.world.quality == 2 and is_equal_approx(get_root().scaling_3d_scale, 1.0) and main.world.soldier_shadows.visible)
	main.set_gfx("auto")
	ok("Auto starts at Medium", main.world.quality == 1)
	main.state = "menu"
	for i in 200:
		main._process(0.06)
	ok("Auto steps the graphics down when the game runs slowly", main.world.quality == 0)
	main.ui.show_screen("settings")
	await _frames(2)
	ok("The settings screen opens", main.screen_open == "settings")
	var tris := 0
	var m: Mesh = main.world.soldiers.multimesh.mesh
	tris = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	ok("Soldiers are light to draw", tris <= 300, str(tris))

	print("FLOW DONE %d failed" % fails)
	quit(1 if fails else 0)
