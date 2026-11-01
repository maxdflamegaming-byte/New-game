extends SceneTree
## Screenshots for checking by eye (run under xvfb-run, opengl3):
##   xvfb-run godot --path tower-siege-godot --rendering-driver opengl3 -s tests/look.gd -- OUT_DIR WHAT [W H]
## WHAT: menu, level:N (a battle with both sides played by the computer for a few seconds),
## brief:N (mission N's briefing), preview:N (dragging to attack), hint:N (💡 Hint pressed), growth (towers of each size), lesson:N (mission N's first lesson), or a screen name (levels, shop, help, win, lose, pvp).

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
	main.cinematics = what.begins_with("cut:")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(30)
	if OS.get_environment("LANG_CODE") != "":
		main.set_lang(OS.get_environment("LANG_CODE"))
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
	elif what.begins_with("preview:") or what.begins_with("hint:"):
		# A finger held over the cheapest building (the attack label), or 💡 Hint pressed
		var n := int(what.split(":")[1])
		main.save.level = 60
		main.start_level(n)
		for i in 60:
			main.battle.update(0.05)
		if what.begins_with("hint:"):
			main.show_hint()
		else:
			var mv: Array = Tutorial.new(main, n)._move("cheap")
			var to: Dictionary = main.world.tower_screen(mv[1])
			main.pointer_down(0, main.world.tower_screen(mv[0]).base)
			main.pointer_move(0, to.base + Vector2(0, -to.r * 0.5))
		await _frames(40)
	elif what.begins_with("lesson:"):
		# Mission N's first lesson step, as a new player sees it
		var n := int(what.split(":")[1])
		main.save.level = n
		main.start_level(n)
		await _frames(60)
	elif what == "growth":
		# Towers at each size: under 10, 10+, 30+ and 60+ soldiers
		main.save.level = 60
		main.start_level(2)
		for a in main.battle.ai_sides:
			a.timer = 1e9
		main.tutor = null
		var sizes := [4, 15, 35, 70, 8, 22]
		for i in main.battle.towers.size():
			main.battle.towers[i].units = sizes[i % sizes.size()]
		main.set_hint("")
		await _frames(40)
	elif what == "pvp":
		main.net.open_pvp()
		await _frames(10)
	elif what == "upgrade":
		main.save.level = 12
		main.save.looks.hat = "viking"
		main.save.looks.flag = "star"
		main.world.set_look("viking", "star")
		main.start_level(15)
		for a in main.battle.ai_sides:
			a.timer = 1e9
		var t: Battle.Tower = main.battle.towers[0]
		t.units = 34
		t.stars = 1
		for i in 60:
			main.battle.update(0.05)
		main.battle.link(t, main.battle.towers[2], 1)
		for i in 40:
			main.battle.update(0.05)
		main.upgrade_offer = {"t": t, "life": 2.5}
		await _frames(20)
	elif what == "quests":
		var list := Progress.missions(main.save)
		list[0].have = list[0].goal
		Progress.claim_reward(main.save)
		Progress.claim_mission(main.save, 0)
		list[1].have = 1
		main.ui.show_screen("missions")
		await _frames(40)
	elif what in ["profile", "achievements", "weekly", "home"]:
		# Some progress to show: 23 levels with stars, numbers, a few achievements earned
		main.save.level = 24
		for n in range(1, 24):
			main.save.stars[str(n)] = 3 if n % 3 else 2
		main.save.life = {"win": 31, "capture": 412, "beat": 2650, "perfect": 6, "pvp_win": 2, "roads": 380, "strike": 12, "fast": 3, "quest": 9, "chest": 7, "streak": 4}
		main.save.coins = 640
		main.save.name = "Commander Rex"
		Achievements.check(main.save)
		Achievements.claim(main.save, "win1")
		var wl := Progress.weekly(main.save)
		wl[0].have = wl[0].goal
		wl[1].have = int(wl[1].goal / 2)
		if what == "weekly":
			main.ui.quest_tab = "weekly"
			main.ui.show_screen("missions")
		elif what == "home":
			main.reward_shown_day = Progress.today()
			main.open_menu()
		else:
			main.ui.show_screen(what)
		await _frames(60)
	elif what == "looks":
		main.save.coins = 500
		main.ui.show_screen(what)
		await _frames(40)
	elif what in ["levels", "shop", "help", "settings", "reward", "missions", "pvp-help"]:
		if what == "levels":
			main.save.level = int(OS.get_environment("AT_LEVEL")) if OS.get_environment("AT_LEVEL") != "" else 13
			for n in range(1, main.save.level):
				main.save.stars[str(n)] = 1 + n % 3
		main.ui.show_screen(what)
		await _frames(30)
	elif what.begins_with("brief:"):
		main.save.level = 60
		main.ui.show_brief(int(what.split(":")[1]))
		await _frames(30)
	elif what == "win":
		main.start_level(4)
		await _frames(5)
		main.ui.show_win(3, 33, "Rally unlocked! Double your marching power for 8 seconds.", 41.0, {"captured": 6, "killed": 40})
		await _frames(120)
	elif what == "lose":
		main.start_level(4)
		await _frames(5)
		main.show_lose()
		await _frames(20)
	elif what == "menu":
		if OS.get_environment("AT_LEVEL") != "":
			main.save.level = int(OS.get_environment("AT_LEVEL"))
		main.reward_shown_day = Progress.today()
		main.open_menu()
		await _frames(60)
	else:
		await _frames(60)
	var img := root.get_texture().get_image()
	img.save_png("%s/godot-%s.png" % [out, what.replace(":", "-")])
	print("SHOT %s" % what)
	quit()
