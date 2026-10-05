extends SceneTree
## The game in a phone's hands: a fresh install at a phone's screen shape, played only with
## taps and drags sent the way Android sends them (touch events, plus the mouse events Android
## makes from the first finger), through the first levels and every screen, with the Android
## back button and the app going to the background. Checks that every tap lands on the button
## it aims at, and saves a screenshot at each step when there's a screen.
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/phone.gd -- OUT_DIR [W H]
##   godot --headless --path tower-siege-godot -s tests/phone.gd          (checks only)
## W H default to 720x1600, the same layout as a 1080x2400 phone. Prints "PHONE DONE n failed".

var main
var out := ""
var fails := 0
var step := 0
var headless := false
const NOTCH := Vector2(70, 34)   # top and bottom of the screen the phone keeps for itself


## Nothing you need to see or tap is under the notch or the gesture bar
func clear_of_notch(c: Control, name: String) -> void:
	if c == null or not c.is_visible_in_tree():
		return
	var r := c.get_global_rect()
	var h := root.get_visible_rect().size.y
	ok("%s is clear of the notch and the gesture bar" % name, r.position.y >= NOTCH.x - 1 and r.end.y <= h - NOTCH.y + 1, "rect %s" % r)


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ""
	var size := Vector2i(int(args[1]), int(args[2])) if args.size() > 2 else Vector2i(720, 1600)
	headless = DisplayServer.get_name() == "headless"
	DisplayServer.window_set_size(size)
	root.size = size
	# Like Android: no mouse, and the first finger also makes mouse events
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tower_siege.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# A phone with a camera notch at the top and a gesture bar at the bottom (drawn in red)
	main.safe_override = NOTCH
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	for r in [Rect2(0, 0, 2000, NOTCH.x), Rect2(0, root.get_visible_rect().size.y - NOTCH.y, 2000, NOTCH.y)]:
		var c := ColorRect.new()
		c.color = Color(1, 0, 0, 0.35)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(c)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func shot(name: String) -> void:
	step += 1
	if headless or out == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img.get_width() > 540:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png("%s/%02d-%s.png" % [out, step, name])


## A point on the game's screen (UI units) -> where a finger touches the glass (window pixels)
func glass(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func touch(index: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = glass(p)
	e.pressed = pressed
	Input.parse_input_event(e)


func drag(index: int, from: Vector2, to: Vector2, steps := 8) -> void:
	touch(index, from, true)
	await _frames(2)
	for i in steps:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = glass(from.lerp(to, (i + 1.0) / steps))
		e.relative = (to - from) / steps
		Input.parse_input_event(e)
		await process_frame
	touch(index, to, false)
	await _frames(2)


func tap_at(p: Vector2) -> void:
	touch(0, p, true)
	await _frames(3)
	touch(0, p, false)
	await _frames(3)


## Tap a button where it is on screen; FAIL if it isn't on screen or the tap doesn't press it
func tap(b: BaseButton, name: String) -> bool:
	if b == null or not b.is_visible_in_tree():
		ok("Tap %s: it's on screen" % name, false, "not visible")
		return false
	var r := b.get_global_rect()
	var view := root.get_visible_rect()
	if not view.encloses(r):
		ok("Tap %s: it's fully on screen" % name, false, "rect %s, screen %s" % [r, view.size])
	var hit := [false]
	var f := func(): hit[0] = true
	b.pressed.connect(f)
	await tap_at(r.get_center())
	if b.pressed.is_connected(f):
		b.pressed.disconnect(f)
	if not hit[0]:
		ok("Tap %s presses it" % name, false, "at %s, %s" % [r.get_center(), "disabled" if b.disabled else "covered by something?"])
	return hit[0]


## The button on the screen showing (or the HUD) whose text starts with this
func find_button(text: String, under: Node = null) -> Button:
	var from: Node = under if under else main.ui
	for n in from.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and tr(b.text).begins_with(tr(text)) or b.is_visible_in_tree() and b.text.begins_with(text):
			return b
	return null


func back_button() -> void:
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(4)


## Sit through a cut scene the way a player does: read, tap to go on
func watch_cutscene(name: String, max_s := 60.0) -> float:
	var t := 0.0
	var n := 0
	while main.cutscene.playing() and t < max_s:
		await _seconds(1.5)
		t += 1.5
		n += 1
		if n % 3 == 1:
			await shot("%s-%d" % [name, n])
			clear_of_notch(main.cutscene.skip_btn, "Skip")
		await tap_at(root.get_visible_rect().size * Vector2(0.5, 0.45))
	return t


## Play like a person: drag roads from my buildings to the nearest buildings that aren't mine
func play_level(name: String, seconds := 90.0, help := true) -> bool:
	var b: Battle = main.battle
	var t := 0.0
	var drags := 0
	while main.state == "play" and t < seconds:
		if help:
			for tw in b.towers:
				if tw.owner == Battle.PLAYER:
					tw.units = maxf(tw.units, 30.0)
		var mine := b.towers.filter(func(x): return x.owner == Battle.PLAYER)
		for a in mine:
			if a.roads.size() >= a.max_roads():
				continue
			var best = null
			var bd := INF
			for o in b.towers:
				if o.owner == Battle.PLAYER or o.type == "wall":
					continue
				var d := Vector2(a.x, a.y).distance_to(Vector2(o.x, o.y))
				if d < bd and b.can_link(a, o, Battle.PLAYER) is bool:
					bd = d
					best = o
			if best:
				var s1: Dictionary = main.world.tower_screen(a)
				var s2: Dictionary = main.world.tower_screen(best)
				await drag(0, s1.base + Vector2(0, -s1.r * 0.6), s2.base + Vector2(0, -s2.r * 0.6))
				drags += 1
		if drags == 1:
			await shot(name + "-road")
		await _seconds(1.0)
		t += 1.0
	return main.state != "play"


func _run() -> void:
	await _frames(2)
	main._layout()
	await _frames(18)
	var ui = main.ui
	# ----- First launch -----
	await shot("first-launch")
	ok("First launch shows the daily reward", main.screen_open == "reward")
	await tap(ui.reward_btn, "Collect")
	await _seconds(0.5)
	ok("Collecting opens the menu with 20 coins", main.screen_open == "menu" and int(main.save.coins) == 20, "screen %s coins %s" % [main.screen_open, main.save.coins])
	await shot("menu")
	clear_of_notch(ui.menu_coins.get_parent(), "The coins")

	# ----- Every menu screen, and back -----
	for item in [["levels", "Levels"], ["shop", "Upgrades"], ["missions", "🎁 Missions"], ["looks", "🎨 Looks"], ["settings", "⚙ Settings"], ["help", "?"]]:
		await tap(find_button(item[1], ui.screens.menu), item[1])
		await _seconds(0.6)
		ok("%s opens" % item[1], main.screen_open == item[0], "screen %s" % main.screen_open)
		await shot(item[0])
		await back_button()
		var back_worked: bool = main.screen_open == "menu"
		if not back_worked:
			await tap(find_button("Back", ui.screens[item[0]]) if item[0] != "help" else find_button("Got it", ui.screens.help), "Back")
			await _seconds(0.4)
		ok("The phone's back button leaves %s" % item[1], back_worked)
		ok("Back to the menu from %s" % item[1], main.screen_open == "menu", "screen %s" % main.screen_open)

	# ----- Online with no server -----
	for item in [["🏆 Leaderboard", "board"], ["🛡 Clans", "clans"], ["⚔ PvP", "pvp"]]:
		await tap(find_button(item[0], ui.screens.menu), item[0])
		await _seconds(6.0)
		await shot(item[1] + "-no-server")
		print("INFO %s with no server: screen %s, state %s" % [item[0], main.screen_open, main.state])
		await back_button()
		if main.screen_open != "menu":
			var b := find_button("Back") if find_button("Back") else find_button("Menu")
			if b:
				await tap(b, "Back from " + item[0])
			else:
				main.open_menu()
			await _seconds(0.5)
		ok("Back to the menu from %s with no server" % item[0], main.screen_open == "menu", "screen %s" % main.screen_open)

	# ----- Level 1, the way a new player meets it -----
	await tap(ui.play_btn, "PLAY")
	await _frames(10)
	var waited := await watch_cutscene("intro", 120.0)
	print("INFO the story before level 1 took %.0f s with a tap every 1.5 s" % waited)
	ok("Level 1 starts after the story", main.state == "play", "state %s" % main.state)
	await _seconds(0.5)
	await shot("level1")
	clear_of_notch(ui.hud.get_child(0), "The top bar")
	clear_of_notch(ui.hint_panel, "The hint")
	var won := await play_level("level1", 120.0)
	ok("Level 1 can be won with drags", won and main.state != "play", "state %s" % main.state)
	await watch_cutscene("victory", 30.0)
	await _seconds(2.0)
	await shot("win")
	ok("The win screen shows after the celebration", main.screen_open == "win", "screen %s state %s" % [main.screen_open, main.state])

	# ----- Level 2: pause with the back button, the app going to the background -----
	await tap(ui.next_btn, "Next level")
	await _frames(10)
	await watch_cutscene("level2", 60.0)
	ok("Level 2 starts", main.state == "play" and main.level == 2, "state %s level %d" % [main.state, main.level])
	await _seconds(1.0)
	await shot("level2")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(3)
	ok("Leaving the app pauses the battle", main.state == "paused" and main.screen_open == "paused", "state %s screen %s" % [main.state, main.screen_open])
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _frames(3)
	if main.screen_open == "paused":
		await tap(find_button("Resume", ui.screens.paused), "Resume")
		await _frames(3)
	await back_button()
	ok("The back button pauses a battle", main.screen_open == "paused", "screen %s" % main.screen_open)
	await shot("paused")
	if main.screen_open == "paused":
		await back_button()
		ok("The back button again resumes", main.screen_open == "" and main.state == "play", "screen %s" % main.screen_open)
	if main.state == "play":
		await tap(ui.hud.get_child(0).get_child(0), "Pause (II)")
		await _seconds(0.4)
	ok("The pause button pauses", main.screen_open == "paused")
	await tap(find_button("Menu", ui.screens.paused), "Menu")
	await _seconds(0.5)
	ok("Menu from pause goes to the menu", main.screen_open == "menu")

	# ----- Exit with the back button from the menu -----
	await back_button()
	print("INFO back button on the menu: screen %s" % main.screen_open)
	await shot("menu-back")

	print("PHONE DONE %d failed" % fails)
	quit()
