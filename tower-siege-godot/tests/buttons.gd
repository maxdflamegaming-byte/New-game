extends SceneTree
## A restless player: from the menu it taps every button on every screen it can reach (and
## the buttons on the screens those open, a few levels deep), then plays a battle of every
## kind with random taps, drags and swipes, uses the pause, speed, hint and airstrike buttons,
## and presses every button on the win, defeat and pause screens. Any script or engine error
## along the way is a FAIL, with what was being done when it happened.
##   godot --headless --path tower-siege-godot -s tests/buttons.gd -- --server=ws://127.0.0.1:9
## (the online buttons then meet a server that isn't there, the same on every machine; with
## the real address, whether it answers decides what happens)
## Prints PASS/FAIL lines and "BUTTONS DONE n failed".

## Errors that come from the test machine, not the game
const IGNORE := ["audio_driver", "ERR_CANT_OPEN", "All audio drivers failed", "alsa"]
const MAX_DEPTH := 3
## Buttons not pressed: they leave the app or open a web page
const SKIP := ["Privacy policy"]


class Catch extends Logger:
	var lines: Array = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		var text := "%s (%s:%d %s) %s" % [code, file, line, function, rationale]
		for i in IGNORE:
			if text.contains(i):
				return
		mutex.lock()
		lines.append(text)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var main
var catch := Catch.new()
var fails := 0
var pressed := 0
var seen := {}        # screen keys reached
var doing := ""       # what the test is doing (for error reports)
var rng := RandomNumberGenerator.new()


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


## Any errors since the last check are reported against what was being done
func check_errors() -> void:
	catch.mutex.lock()
	var got: Array = catch.lines.duplicate()
	catch.lines.clear()
	catch.mutex.unlock()
	for e in got:
		ok("No error while: " + doing, false, e)


func _initialize() -> void:
	OS.add_logger(catch)
	rng.seed = 2026
	DisplayServer.window_set_size(Vector2i(720, 1600))
	root.size = Vector2i(720, 1600)
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak", "user://tower_siege.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func glass(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func touch(index: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = glass(p)
	e.pressed = down
	Input.parse_input_event(e)


func drag(from: Vector2, to: Vector2, steps := 6) -> void:
	touch(0, from, true)
	await _frames(1)
	for i in steps:
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = glass(from.lerp(to, (i + 1.0) / steps))
		e.relative = (to - from) / steps
		Input.parse_input_event(e)
		await process_frame
	touch(0, to, false)
	await _frames(1)


func tap_at(p: Vector2) -> void:
	touch(0, p, true)
	await _frames(2)
	touch(0, p, false)
	await _frames(2)


func key() -> String:
	return "%s/%s/%s" % [main.screen_open, main.state, main.mode]


## The buttons a player can see now: on the open screen (or the HUD in a battle)
func visible_buttons() -> Array:
	# (everything showing: the open screen, panels over it like ☰'s, or the battle's HUD)
	var out := []
	for n in main.ui.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.disabled and not tr(b.text) in SKIP and not b.text in SKIP:
			out.append(b)
	return out


func label_of(b: Button) -> String:
	var t := b.text.strip_edges().replace("\n", " ")
	return t if t != "" else b.name


## The part of a button a finger can reach: inside the screen and any list it scrolls in
func reachable(b: Control) -> Rect2:
	var r := b.get_global_rect().intersection(root.get_visible_rect())
	var n := b.get_parent()
	while n != null and r.has_area():
		if n is ScrollContainer or (n is Control and n.clip_contents):
			r = r.intersection(n.get_global_rect())
		n = n.get_parent()
	return r


## Press a button the way a finger does when it's on screen, else (scrolled away) directly.
## A button on the open screen that shows but can't be tapped is a FAIL: something covers it.
func press(b: Button) -> void:
	pressed += 1
	var full := b.get_global_rect()
	var r := reachable(b)
	var whole := r.get_area() >= full.get_area() * 0.95
	var hit := [false]
	var f := func(): hit[0] = true
	b.pressed.connect(f)
	if whole:
		await tap_at(r.get_center())
	if is_instance_valid(b) and b.pressed.is_connected(f):
		b.pressed.disconnect(f)
	var on_screen: Node = main.ui.screens.get(main.screen_open) if main.screen_open != "" else main.ui.hud
	if whole and not hit[0] and is_instance_valid(b) and on_screen != null and on_screen.is_ancestor_of(b):
		ok("\"%s\" on %s can be tapped" % [label_of(b), key()], false, "a tap at %s didn't reach it" % r.get_center())
	if not hit[0] and is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled:
		b.pressed.emit()
	await _frames(4)


## Back to a known place: the menu, nothing running, English, plenty of everything
func reset() -> void:
	if main.mode == "online" or main.net.ws != null:
		main.net.leave()
	main.cutscene.abort()
	main.drags.clear()
	if main.save.lang != "":
		main.set_lang("")
	main.reward_shown_day = Progress.today()
	main.open_menu()
	main.save.coins = 99999
	await _frames(3)


## Repeat a list of button labels from the menu
func follow(path: Array) -> bool:
	await reset()
	for step in path:
		var found: Button = null
		for b in visible_buttons():
			if label_of(b) == step:
				found = b
				break
		if found == null:
			return false
		await press(found)
	return true


## Taps every button it can reach from the menu, breadth first, a few screens deep
func explore() -> void:
	var queue := [[]]
	var tried := {}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		if not await follow(path):
			continue
		var here := key()
		var labels: Array = visible_buttons().map(func(b): return label_of(b))
		for label in labels:
			var id: String = here + "|" + str(label)
			if tried.has(id):
				continue
			tried[id] = true
			if not await follow(path):
				break
			var b: Button = null
			for x in visible_buttons():
				if label_of(x) == label:
					b = x
					break
			if b == null:
				continue
			doing = "pressing \"%s\" on %s (after %s)" % [label, here, " > ".join(path) if not path.is_empty() else "the menu"]
			await press(b)
			await _frames(6)
			check_errors()
			var now := key()
			if main.state in ["play", "cutscene"]:
				# It started something: play it for a moment like a restless player
				doing = "playing after \"%s\" (%s)" % [label, now]
				await monkey(1.5)
				check_errors()
				seen[now] = true
				continue
			if not seen.has(now):
				seen[now] = true
				if path.size() < MAX_DEPTH and now != here:
					queue.append(path + [label])


## Random taps, drags between buildings, swipes and HUD buttons for a while
func monkey(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000
	var size := root.get_visible_rect().size
	while Time.get_ticks_msec() < end:
		if main.state == "cutscene":
			await tap_at(size / 2)
			continue
		if main.state != "play":
			break
		var r := rng.randf()
		var towers: Array = main.battle.towers
		if r < 0.45 and towers.size() >= 2:
			var a = towers[rng.randi() % towers.size()]
			var t = towers[rng.randi() % towers.size()]
			await drag(main.world.project(a.x, a.y), main.world.project(t.x, t.y))
		elif r < 0.6:
			await drag(Vector2(rng.randf() * size.x, rng.randf() * size.y), Vector2(rng.randf() * size.x, rng.randf() * size.y), 4)
		elif r < 0.8:
			await tap_at(Vector2(rng.randf() * size.x, rng.randf() * size.y))
		else:
			var hud := visible_buttons()
			if not hud.is_empty():
				var b: Button = hud[rng.randi() % hud.size()]
				await press(b)
				if main.screen_open == "paused":
					main.resume()
		await _frames(2)


## Start a battle of some kind and get to its first frame of play
func start(kind: String) -> void:
	await reset()
	match kind:
		"lesson":
			main.save.level = 1
			main.start_level(1)
		"level 7":
			main.start_level(7)
		"boss 15":
			main.start_level(15)
		"level 42":
			main.start_level(42)
		"endless 75":
			main.start_level(75)
		"daily":
			main.start_daily()
		"event":
			Progress.test_day = 20393  # a Saturday
			main.start_event()
		"duo", "practice":
			main.net.start_pvp(kind, 777)
	await _frames(4)
	var guard := 0
	while main.state != "play" and guard < 400:
		guard += 1
		if main.state == "cutscene":
			main.cutscene.skip()
		elif main.screen_open == "brief":
			var go := visible_buttons().filter(func(b): return label_of(b).contains("Play") or label_of(b).contains("Start") or label_of(b).contains("Go"))
			if not go.is_empty():
				await press(go[0])
		await _frames(2)


func finish(won: bool) -> void:
	var b: Battle = main.battle
	for t in b.towers:
		if won and t.owner != Battle.PLAYER:
			t.owner = Battle.PLAYER
		elif not won and t.owner == Battle.PLAYER:
			t.owner = 2
	b.units.clear()
	var guard := 0
	while main.state == "play" and guard < 600:
		guard += 1
		main.check_end()
		await _frames(1)
	# The results come up after a moment (and maybe a cut scene first)
	var until := Time.get_ticks_msec() + 8000
	while main.screen_open == "" and Time.get_ticks_msec() < until:
		if main.state == "cutscene":
			main.cutscene.skip()
		await _frames(2)
	await _frames(10)


func battles() -> void:
	main.save.level = 80
	for kind in ["lesson", "level 7", "boss 15", "level 42", "endless 75", "daily", "event", "duo", "practice"]:
		doing = "starting a %s battle" % kind
		await start(kind)
		ok("A %s battle starts" % kind, main.state == "play", key())
		check_errors()
		doing = "playing a %s battle with random taps, drags and buttons" % kind
		await monkey(6.0)
		check_errors()
		Progress.test_day = -1
	# Every button on the pause, win and defeat screens, each from a fresh battle
	for end_kind in ["paused", "win", "lose"]:
		for kind in ["level 7", "duo"]:
			await start(kind)
			if end_kind == "paused":
				main.pause()
				await _frames(4)
			else:
				await finish(end_kind == "win")
			var screen: String = main.screen_open
			var labels: Array = visible_buttons().map(func(b): return label_of(b))
			ok("The %s screen after a %s battle shows, with buttons" % [end_kind, kind], screen != "" and not labels.is_empty(), "%s: %s" % [key(), ", ".join(labels)])
			for label in labels:
				await start(kind)
				if end_kind == "paused":
					main.pause()
					await _frames(4)
				else:
					await finish(end_kind == "win")
				var b: Button = null
				for x in visible_buttons():
					if label_of(x) == label:
						b = x
				if b == null:
					continue
				doing = "pressing \"%s\" on the %s screen (%s battle, %s)" % [label, end_kind, kind, screen]
				await press(b)
				await _frames(20)
				if main.state == "play":
					await monkey(1.0)
				check_errors()
	Progress.test_day = -1


func _run() -> void:
	await _frames(30)
	# The test's own check: an error must be caught
	push_error("buttons.gd self-test")
	catch.mutex.lock()
	var caught: bool = catch.lines.any(func(l): return l.contains("buttons.gd self-test"))
	catch.lines.clear()
	catch.mutex.unlock()
	ok("The test catches errors (checked with one of its own)", caught)
	doing = "starting the game"
	check_errors()
	# A new player first (only the first things are open), then one who has seen it all
	main.save.level = 1
	doing = "exploring as a new player"
	await explore()
	ok("A new player's screens: every button pressed without an error", true, "%d screens, %d presses" % [seen.size(), pressed])
	var new_seen := seen.size()
	main.save.level = 61
	main.save.stars = {}
	for i in range(1, 61):
		main.save.stars[str(i)] = 3
	main.save.trophies = 900
	doing = "exploring as a player who has finished the story"
	await explore()
	ok("A veteran's screens: every button pressed without an error", seen.size() >= new_seen, "%d screens, %d presses" % [seen.size(), pressed])
	# Screens no button path reached: open each straight from the menu and press its buttons
	for id in main.ui.screens.keys():
		if id in ["win", "lose", "paused", "brief", "pvp-wait", "pvp-vs", "pvp-end", "reward"] or seen.keys().any(func(k): return k.begins_with(id + "/")):
			continue
		await reset()
		main.ui.show_screen(id)
		await _frames(4)
		seen[key()] = true
		var labels: Array = visible_buttons().map(func(b): return label_of(b))
		for label in labels:
			await reset()
			main.ui.show_screen(id)
			await _frames(4)
			for x in visible_buttons():
				if label_of(x) == label:
					doing = "pressing \"%s\" on the %s screen" % [label, id]
					await press(x)
					await _frames(6)
					if main.state == "play":
						await monkey(1.0)
					check_errors()
					break
	ok("Every screen opened", seen.size() >= main.ui.screens.size() - 8, "%d screens" % seen.size())
	await battles()
	await reset()
	check_errors()
	print("Screens reached: " + ", ".join(seen.keys()))
	print("BUTTONS DONE %d failed (%d presses)" % [fails, pressed])
	quit(1 if fails else 0)
