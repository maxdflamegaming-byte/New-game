extends Node
## Tower Siege (Godot): the game flow, touch input, saving, and the link between the battle
## (battle.gd), the 3D world (world.gd), the overlay (overlay.gd) and the screens (ui.gd).
## PvP, the leaderboard and clans are in net.gd.

const SIDES := [
	{"name": "Neutral", "color": Color("#9eaabd"), "dark": Color("#66728a"), "light": Color("#dfe5ee")},
	{"name": "Blue", "color": Color("#3d9bff"), "dark": Color("#2366d6"), "light": Color("#b5dcff")},
	{"name": "Red", "color": Color("#ff5257"), "dark": Color("#cc2b3a"), "light": Color("#ffb3b5")},
	{"name": "Yellow", "color": Color("#ffc21f"), "dark": Color("#d98a00"), "light": Color("#ffe796")},
	{"name": "Green", "color": Color("#45d35a"), "dark": Color("#22963a"), "light": Color("#b3f2bb")},
]
const HUD_TOP := 92.0
const HUD_BOTTOM := 130.0
const SAVE_PATH := "user://tower_siege.json"
const UPGRADES := [
	{"id": "drill", "icon": "Drill", "name": "Drill Sergeant", "desc": "Your buildings train soldiers 8% faster per level", "max": 5, "cost": [60, 120, 220, 360, 550]},
	{"id": "boots", "icon": "Boots", "name": "Swift Boots", "desc": "Your soldiers and tanks move 7% faster per level", "max": 5, "cost": [50, 100, 180, 300, 480]},
	{"id": "garrison", "icon": "Fort", "name": "Garrison", "desc": "+3 soldiers in each of your starting buildings per level", "max": 5, "cost": [40, 90, 160, 260, 400]},
	{"id": "armory", "icon": "Bomb", "name": "Armory", "desc": "+1 Airstrike and +1 Rally every battle", "max": 2, "cost": [250, 600]},
]
const TIPS := [
	"Take the gray buildings near you first. They're cheap, and every building trains soldiers.",
	"Attack from two or three buildings at once to break a big tower.",
	"Cut roads to buildings that are already safe, so your soldiers stay home to defend.",
	"Tank factories send tanks worth 3 soldiers each. Grab them early.",
	"Bunkers take half damage. Leave them for later unless you have a big army.",
	"Stay out of watchtower circles, or send a big wave all at once.",
	"Upgrades make every battle easier. Spend your coins!",
	"When two enemies fight, wait for them to wear each other down.",
]

var save := {}
var battle: Battle
var world: World
var overlay: Overlay
var ui: UI
var net: Net
var sfx
var music

var state := "menu"            # menu, play, paused, over, cutscene
var mode := "campaign"         # campaign, online, duo, practice
var level := 1
var daily := false             # playing today's daily challenge
var upgrade_offer := {}        # {t, life}: the ⬆ button over one of your buildings
var reward_shown_day := -1
var cinematics := true         # cut scenes play (the tests switch them off to go faster)
var cutscene: Cutscene
var story: Story
var screen_open := ""          # the screen showing, or "" during play
var speed := 1
var charges := {"strike": 0, "rally": 0}
var armed := ""                # an ability waiting for a target
var hint_text := ""
var hint_timer := 0.0
var hand_shown := false
var landscape := false
var scene_level := 1
var scene_theme := ""
var shake := 0.0
var demo_timer := 0.0
var quiet := false             # the menu's demo battle makes no sound
var slow_frames := 0
const GFX := ["low", "medium", "high"]
var safe_override := Vector2(-1, -1) # tests pretend the phone has a notch (top, bottom)
var _back_at := -10000              # when the back button was last pressed on the menu

# Input and things the overlay draws
var drags := {}                # touch index -> {from, side, pos, p, over}
var cuts := {}                 # touch index -> {last, side}
var cut_marks := []
var floats := []
var shells := []


func _ready() -> void:
	load_save()
	I18n.lang = save.lang
	I18n.setup()
	sfx = load("res://scripts/sfx.gd").new()
	sfx.muted = save.muted
	add_child(sfx)
	music = load("res://scripts/music.gd").new()
	add_child(music)
	music.set_enabled(save.music and not save.muted)
	world = World.new()
	add_child(world)
	world.setup(SIDES)
	world.set_plane_color(SIDES[1].color)
	world.set_look(save.looks.hat, save.looks.flag)
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Overlay.new()
	overlay.main = self
	overlay.font = load("res://assets/fonts/Fredoka-Bold.ttf")
	layer.add_child(overlay)
	ui = UI.new()
	ui.main = self
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui_layer.add_child(ui)
	ui.build()
	cutscene = Cutscene.new()
	cutscene.main = self
	cutscene.ui = ui
	add_child(cutscene)
	cutscene.build()
	story = Story.new(self, cutscene)
	net = Net.new()
	net.main = self
	add_child(net)
	battle = Battle.new()
	_connect_battle()
	get_viewport().size_changed.connect(_layout)
	_layout()
	apply_gfx()
	open_menu()


# ---------- Saving ----------
func default_save() -> Dictionary:
	var d := {"level": 1, "stars": {}, "coins": 0, "up": {"drill": 0, "boots": 0, "garrison": 0, "armory": 0},
		"seen": {}, "muted": false, "music": true, "name": "", "trophies": 0, "pvp_wins": 0, "pvp_losses": 0,
		"pid": "", "token": "", "clan": null, "gfx": "auto", "vibrate": true, "lang": "", "cutscenes": true}
	d.merge(Progress.defaults())
	return d


func load_save() -> void:
	save = default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Dictionary:
			for k in data:
				save[k] = data[k]
			var up: Dictionary = default_save().up
			up.merge(data.get("up", {}), true)
			save.up = up
	# JSON gives back numbers as floats
	save.level = int(save.level)
	save.coins = int(save.coins)
	save.trophies = int(save.trophies)
	for k in save.up:
		save.up[k] = int(save.up[k])
	var looks: Dictionary = default_save().looks
	looks.merge(save.looks if save.looks is Dictionary else {}, true)
	save.looks = looks


func write_save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


# ---------- The phone ----------
func _notification(what: int) -> void:
	if cutscene == null:
		return # not set up yet
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			go_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			# A call, the notification shade or another app: the battle waits for you
			if state == "play" and screen_open == "" and not cutscene.playing():
				pause()
			write_save()
		NOTIFICATION_WM_CLOSE_REQUEST:
			write_save()


## The phone's back button: skip a cut scene, pause or resume a battle, or close the screen
## that's open (like its Back button would). On the menu, pressing it twice leaves the game.
func go_back() -> void:
	if cutscene.playing():
		cutscene.skip()
		return
	if screen_open == "":
		if state == "play":
			pause()
		return
	if screen_open == "paused":
		resume()
		return
	if screen_open == "menu":
		if Time.get_ticks_msec() - _back_at < 2500:
			write_save()
			get_tree().quit()
		else:
			_back_at = Time.get_ticks_msec()
			ui.toast("Press back again to leave the game")
		return
	# The screen's own way out
	var page: Control = ui.screens.get(screen_open)
	if page:
		for text in ["Back", "Cancel", "Got it", "Got it!", "Menu"]:
			for b in page.find_children("*", "Button", true, false):
				if b.text == text and b.is_visible_in_tree() and not b.disabled:
					b.pressed.emit()
					return
	if screen_open in ["reward", "win", "lose"]:
		open_menu()


## How much of the screen's top and bottom a camera notch or rounded corners cover, in the
## game's screen units (the phone's safe area)
func safe_insets() -> Vector2:
	if safe_override.x >= 0:
		return safe_override
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.y <= 0 or safe.size.y <= 0:
		return Vector2.ZERO
	var k := get_viewport().get_visible_rect().size.y / screen.y
	return Vector2(maxf(0, safe.position.y), maxf(0, screen.y - safe.end.y)) * k


# ---------- Layout ----------
func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var was := landscape
	landscape = size.x > size.y * 1.05
	var fw := Levels.FH if landscape else Levels.FW
	var fh := Levels.FW if landscape else Levels.FH
	var safe := safe_insets()
	ui.fit_safe(safe.x, safe.y)
	cutscene.fit_safe(safe.x)
	world.layout(size, HUD_TOP + safe.x, HUD_BOTTOM + safe.y, fw, fh)
	if world.soldier_shadows:
		world.set_quality(world.quality) # the 3D resolution follows the screen size
	if was != landscape and not battle.towers.is_empty():
		battle.landscape = landscape
		battle.place()
		build_scene()


func build_scene() -> void:
	world.build(scene_level * 101 + 7, scene_theme if scene_theme != "" else Levels.theme_for(scene_level), battle)


## "auto" starts at Medium and steps down by itself if the phone can't keep up
func apply_gfx() -> void:
	var g: String = save.gfx
	world.set_quality(GFX.find(g) if g in GFX else 1)
	slow_frames = 0


func set_gfx(g: String) -> void:
	save.gfx = g
	write_save()
	apply_gfx()


## Settings: watch the opening again (on level 1's map), then back to the menu
func watch_story() -> void:
	level = 1
	daily = false
	mode = "campaign"
	state = "cutscene"
	world.drift = false
	ui.show_screen("")
	ui.hide_hud()
	set_hint("")
	load_battle(Levels.data(1), 1)
	music.play_track("game")
	var r := cutscene.begin()
	await story.intro(r)
	if cutscene.current(r):
		cutscene.finish(r)
		open_menu()


func set_lang(code: String) -> void:
	save.lang = code
	write_save()
	I18n.lang = code
	I18n.apply()
	# Text made from numbers and names is built again in the new language
	ui.show_screen(screen_open)


func vibrate(ms: int) -> void:
	if save.vibrate and not quiet:
		Input.vibrate_handheld(ms)


func play_sound(name: String) -> void:
	if not quiet:
		sfx.play(name)


# ---------- Battles ----------
func _connect_battle() -> void:
	battle.captured.connect(_on_captured)
	battle.clashed.connect(_on_clashed)
	battle.shot.connect(_on_shot)
	battle.hit.connect(_on_hit)
	battle.bombed.connect(_on_bombed)


func load_battle(data: Dictionary, n: int, theme := "") -> void:
	battle.mode = mode
	battle.boost = {"drill": save.up.drill, "boots": save.up.boots}
	battle.landscape = landscape
	battle.flipped = net.is_guest()
	battle.load_map(data, 3 * save.up.garrison if mode == "campaign" and state != "menu" else 0)
	battle.ai_sides.clear()
	floats.clear()
	shells.clear()
	cut_marks.clear()
	scene_level = n
	scene_theme = theme
	build_scene()


func start_level(n: int) -> void:
	level = n
	daily = false
	mode = "campaign"
	state = "play"
	var data := Levels.data(n)
	load_battle(data, n)
	for side in [2, 3, 4]:
		if battle.towers.any(func(t): return t.owner == side):
			battle.ai_sides.append({"side": side, "timer": 2.5 + (side - 2) * 0.7, "cfg": data.ai})
	armed = ""
	shake = 0.0
	hand_shown = data.get("hand", false)
	charges = {"strike": 1 + save.up.armory if n >= 3 else 0, "rally": 1 + save.up.armory if n >= 6 else 0}
	_begin(data, tr("Level %d") % n + ("  ·  " + tr("Boss") if Levels.is_boss(n) else ""), n)


## Today's challenge: the same map for everyone, a big prize the first time you win it
func start_daily() -> void:
	daily = true
	level = maxi(int(save.level), 6)
	mode = "campaign"
	state = "play"
	var day := Progress.today()
	var data := Levels.daily(day)
	load_battle(data, 500 + day % 997, data.theme)
	for side in [2, 3, 4]:
		if battle.towers.any(func(t): return t.owner == side):
			battle.ai_sides.append({"side": side, "timer": 2.5, "cfg": data.ai})
	armed = ""
	shake = 0.0
	hand_shown = false
	charges = {"strike": 1 + save.up.armory, "rally": 1 + save.up.armory}
	_begin(data, "Daily challenge", level)


## Before a level: its cut scenes (story, boss, the fly-in), then the HUD, hints and music
func _begin(data: Dictionary, title: String, n: int) -> void:
	world.drift = false
	upgrade_offer = {}
	clear_pointers()
	ui.show_screen("")
	ui.hide_hud()
	set_hint("")
	var boss: bool = Levels.is_boss(n) and not daily
	if cinematics:
		state = "cutscene"
		music.play_track("boss" if boss else "game")
		var r := cutscene.begin(not save.cutscenes)
		await story.level_start(r, 0 if daily else n, title)
		if not cutscene.current(r):
			return # something else started meanwhile
		cutscene.finish(r)
	state = "play"
	ui.start_hud(title, true)
	set_hint(data.get("hint", ""), 25.0 if n == 2 else 10.0)
	# Introduce a new building the first time it shows up
	for k in Battle.TYPES:
		if Battle.TYPES[k].has("intro") and not save.seen.has(k) and battle.towers.any(func(t): return t.type == k):
			save.seen[k] = true
			write_save()
			get_tree().create_timer(0.6).timeout.connect(func(): ui.toast(Battle.TYPES[k].intro, 4.2))
			break
	music.play_track("boss" if boss else "game")


func set_hint(text: String, seconds := 10.0) -> void:
	hint_text = text
	hint_timer = seconds
	ui.set_hint(text)


## Count progress on today's missions, and say when one is finished
func mission(id: String, n := 1) -> void:
	if quiet:
		return
	for m in Progress.add(save, id, n):
		ui.toast(tr("Mission done: %s! Collect %d coins in Missions.") % [Progress.mission_text(m), int(m.coins)], 3.0)
		play_sound("coin")
	write_save()


func _on_captured(t, side: int, old: int) -> void:
	world.capture(t.x, t.y, side)
	if side == Battle.PLAYER:
		mission("capture")
	if not upgrade_offer.is_empty() and upgrade_offer.t == t:
		upgrade_offer = {}
	net.event(["cap", t.id, side])
	if mode == "duo":
		play_sound("capture")
		floats.append({"t": t, "text": "Captured!", "color": SIDES[side].light, "life": 1.3})
	elif side == Battle.PLAYER:
		play_sound("capture")
		vibrate(25)
		floats.append({"t": t, "text": "Captured!", "color": SIDES[1].light, "life": 1.3})
	elif old == Battle.PLAYER:
		play_sound("warn")
		vibrate(70)
		if not quiet:
			shake = maxf(shake, 6)
		floats.append({"t": t, "text": "Lost!", "color": SIDES[side].light, "life": 1.3})


func _on_clashed(x: float, y: float, a: int, b: int, ua, ub) -> void:
	world.clash(x, y, a, b)
	for u in [ua, ub]:
		if u.dead:
			world.knock(u.x, u.y, u.owner, u.tank)
	net.event(["cl", ua.id, ub.id])
	if randf() < 0.3:
		play_sound("pop")


func _on_shot(t, u) -> void:
	shells.append({"x1": t.x, "y1": t.y, "x2": u.x, "y2": u.y, "h": 50.0, "time": 0.18, "dur": 0.18})
	world.muzzle(t, u.x, u.y)
	world.kick(t)
	world.hit(u.x, u.y, u.owner)
	if u.dead:
		world.knock(u.x, u.y, u.owner, u.tank)
	net.event(["sh", t.id, u.id])
	if t.owner == Battle.PLAYER or u.owner == Battle.PLAYER:
		play_sound("shoot")


func _on_hit(t, side: int) -> void:
	if randf() < 0.5:
		world.hit(t.x, t.y, side)
	if t.owner == Battle.PLAYER:
		play_sound("hit")


func _on_bombed(t) -> void:
	world.blast(t)
	for k in battle.struck:
		world.knock(k[0], k[1], k[2], k[3])
	shake = 12
	play_sound("boom")
	vibrate(90)


func check_end() -> void:
	if state != "play":
		return
	if mode != "campaign":
		net.check_end()
		return
	if not battle.alive(Battle.PLAYER):
		end_game(false)
	elif battle.ai_sides.all(func(a): return a.side == Battle.PLAYER or not battle.alive(a.side)):
		end_game(true)


func end_game(won: bool) -> void:
	state = "over"
	upgrade_offer = {}
	mission("beat", battle.stats.killed)
	clear_pointers()
	armed = ""
	set_hint("")
	music.play_track("menu")
	vibrate(120 if won else 200)
	if won:
		play_sound("win")
		for t in battle.towers:
			world.capture(t.x, t.y, Battle.PLAYER)
	else:
		play_sound("death")
	if not cinematics:
		get_tree().create_timer(1.1).timeout.connect(func(): show_win() if won else show_lose())
		return
	# The celebration (or Grumble's laugh), then the results
	ui.hide_hud()
	var r := cutscene.begin(true)
	if won:
		await story.victory(r, 0 if daily else level)
	else:
		await story.defeat(r)
	if not cutscene.current(r):
		return
	cutscene.finish(r)
	if won:
		show_win()
	else:
		show_lose()


func stars_for(time: float) -> int:
	var par := 30.0 + battle.towers.size() * 7
	return 3 if time <= par else 2 if time <= par * 1.8 else 1


func show_win() -> void:
	var stars := stars_for(battle.time)
	mission("win")
	if stars == 3:
		mission("stars3")
	if daily:
		var first_today: bool = int(save.daily_won) != Progress.today()
		var prize: int = Progress.DAILY_COINS if first_today else Progress.DAILY_REPLAY_COINS
		save.coins += prize
		save.daily_won = Progress.today()
		if first_today:
			mission("daily")
		write_save()
		ui.show_win(stars, prize, "Daily challenge won! Come back tomorrow for a new map." if first_today else "", battle.time, battle.stats)
		return
	var key := str(level)
	var first: bool = level >= save.level
	var coins := 15 + level * 2 + stars * 5
	if not first:
		coins = roundi(coins / 2.0)
	save.coins += coins
	save.stars[key] = maxi(int(save.stars.get(key, 0)), stars)
	var unlock := ""
	if first and level < Levels.LAST_LEVEL:
		save.level = level + 1
		if level + 1 == 3:
			unlock = "Airstrike unlocked! Bomb a building once per battle."
		elif level + 1 == 6:
			unlock = "Rally unlocked! Double your marching power for 8 seconds."
		elif level + 1 == 8:
			unlock = "Upgrades unlocked! Tap one of your buildings, then ⬆, to make it train faster."
		elif level == Levels.MAX_LEVEL:
			unlock = "You beat all 60 levels! Endless levels unlocked: they keep getting harder."
	write_save()
	ui.show_win(stars, coins, unlock, battle.time, battle.stats)


func show_lose() -> void:
	ui.show_lose(TIPS[(level + int(battle.time)) % TIPS.size()])


# ---------- Abilities ----------
func use_ability(id: String) -> void:
	if state != "play":
		return
	if id == "strike":
		if armed == "strike":
			armed = ""
			ui.set_hint(hint_text)
		elif charges.strike > 0:
			armed = "strike"
			ui.set_hint("Tap an enemy or gray building to bomb it")
			play_sound("beep")
	elif id == "rally" and charges.rally > 0 and battle.rally <= 0:
		charges.rally -= 1
		battle.rally = Battle.RALLY_TIME
		play_sound("speed")
		ui.toast("Rally! Your roads send twice as fast for 8 seconds")
		for t in battle.towers:
			if t.owner == Battle.PLAYER:
				world.capture(t.x, t.y, Battle.PLAYER)
	ui.refresh_abilities()


func drop_strike(t) -> void:
	mission("strike")
	charges.strike -= 1
	armed = ""
	ui.set_hint(hint_text)
	battle.drop_strike(t)
	play_sound("warn")
	ui.refresh_abilities()


# ---------- Input ----------
## Which armies the person (or people) at this screen control
func controls(side: int) -> bool:
	return side == 1 or side == 2 if mode == "duo" else side == 1


## With two players on one phone, blue sits at the bottom and red at the top
func side_at(pos: Vector2) -> int:
	return 2 if mode == "duo" and pos.y < get_viewport().get_visible_rect().size.y / 2 else 1


func tower_at(pos: Vector2, slack := 1.0):
	var best = null
	var bd := INF
	for t in battle.towers:
		var s := world.tower_screen(t)
		var d := Geometry2D.get_closest_point_to_segment(pos, s.base, Vector2(s.top_x, s.top_y)).distance_to(pos)
		var reach := maxf(s.r + 10, 30) * slack
		if d < reach and d < bd:
			bd = d
			best = t
	return best


func clear_pointers() -> void:
	drags.clear()
	cuts.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_down(event.index, event.position)
		else:
			pointer_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		pointer_move(event.index, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P, KEY_ESCAPE:
				if screen_open == "paused":
					resume()
				elif state == "play":
					pause()
			KEY_M:
				toggle_sound()
			KEY_N:
				toggle_music()
			KEY_F:
				if state == "play" and mode == "campaign":
					toggle_speed()
			KEY_1:
				use_ability("strike")
			KEY_2:
				use_ability("rally")


func pointer_down(index: int, pos: Vector2) -> void:
	if state != "play" or screen_open != "" or net.paused():
		return
	# The ⬆ button over one of your buildings
	if not upgrade_offer.is_empty():
		var btn := overlay.upgrade_button(upgrade_offer.t)
		var t0 = upgrade_offer.t
		upgrade_offer = {}
		if pos.distance_to(btn.c) < btn.r * 1.4:
			upgrade_building(t0)
			return
	var p = world.ground(pos)
	var t = tower_at(pos)
	if armed == "strike":
		if t != null and t.owner != Battle.PLAYER:
			drop_strike(t)
		else:
			ui.toast("Pick an enemy or gray building")
		return
	if t != null and controls(t.owner):
		drags[index] = {"from": t, "side": t.owner, "pos": pos, "start": pos, "p": p, "over": null}
	elif p != null:
		cuts[index] = {"last": p, "side": side_at(pos)}


func pointer_move(index: int, pos: Vector2) -> void:
	if drags.has(index):
		drags[index].pos = pos
		drags[index].p = world.ground(pos)
	if cuts.has(index):
		var p = world.ground(pos)
		if p != null:
			swipe(cuts[index].last, p, cuts[index].side)
			cuts[index].last = p


func pointer_up(index: int, pos: Vector2) -> void:
	if drags.has(index):
		var d: Dictionary = drags[index]
		drags.erase(index)
		var t = tower_at(pos, 1.2)
		# A tap on your own building offers its upgrade (campaign, from level 8)
		if t == d.from and pos.distance_to(d.start) < 40 and state == "play" and can_upgrade_here() and d.from.owner == Battle.PLAYER:
			upgrade_offer = {"t": t, "life": 3.0}
			play_sound("tap")
		elif t != null and t != d.from and state == "play" and d.from.owner == d.side:
			var res = request_link(d.from, t, d.side)
			if res is bool and res:
				play_sound("go")
				if d.side == Battle.PLAYER:
					mission("roads")
				if hand_shown:
					hand_shown = false
					set_hint("")
			elif res is String and res == "full":
				ui.toast("This building can hold 1 road. More soldiers unlock more." if d.from.max_roads() == 1 else tr("This building can hold %d roads. More soldiers unlock more.") % d.from.max_roads())
				play_sound("beep")
			elif res is String and res == "blocked":
				ui.toast("A wall is in the way")
				play_sound("beep")
	cuts.erase(index)


func can_upgrade_here() -> bool:
	return mode == "campaign" and (level >= 8 or daily)


func upgrade_building(t) -> void:
	var res = battle.upgrade(t, Battle.PLAYER)
	if res is bool:
		play_sound("speed")
		vibrate(30)
		world.capture(t.x, t.y, Battle.PLAYER)
		floats.append({"t": t, "text": "★ Trains faster!", "color": Color("#ffe14d"), "life": 1.4})
		mission("upgrade")
	elif res == "max":
		ui.toast("This building has every upgrade")
	elif res == "soldiers":
		ui.toast(tr("Needs %d soldiers to upgrade") % (Battle.UPGRADE_COST[t.stars] + 1))
		play_sound("beep")


## Build a road. Online, a guest asks the host, who runs the battle.
func request_link(a, b, side: int):
	if net.is_guest():
		var ok = battle.can_link(a, b, side)
		if ok is bool:
			net.send({"t": "cmd", "c": "link", "a": a.id, "b": b.id})
		return ok
	return battle.link(a, b, side)


## Cut any of that army's roads the swipe crosses
func swipe(a: Vector2, b: Vector2, side: int) -> void:
	cut_marks.append({"x1": a.x, "y1": a.y, "x2": b.x, "y2": b.y, "life": 0.35})
	for t in battle.towers:
		if t.owner != side:
			continue
		for i in range(t.roads.size() - 1, -1, -1):
			var to = t.roads[i].to
			var hit = Geometry2D.segment_intersects_segment(a, b, Vector2(t.x, t.y), Vector2(to.x, to.y))
			if hit != null:
				if net.is_guest():
					net.send({"t": "cmd", "c": "cut", "a": t.id, "b": to.id})
				t.roads.remove_at(i)
				world.hit(hit.x, hit.y, side)
				play_sound("cut")
				if level == 2 and hint_text != "" and mode == "campaign":
					set_hint("")


## The ring under a building: the drag source, a drag target, or an airstrike target
func highlight(t) -> String:
	if armed == "strike" and t.owner != Battle.PLAYER:
		return "target"
	for d in drags.values():
		if t == d.from:
			return "source"
		if d.over == t:
			return "over" if battle.can_link(d.from, t, d.side) is bool else "bad"
	return ""


# ---------- Screens and buttons ----------
func open_menu() -> void:
	cutscene.abort()
	state = "menu"
	world.drift = true
	mode = "campaign"
	armed = ""
	scene_theme = ""
	demo_timer = 0.0
	battle.rally = 0.0
	ui.hide_hud()
	set_hint("")
	ui.show_screen("menu")
	music.play_track("menu")
	# The daily reward pops up once a day
	if Progress.reward_ready(save) and reward_shown_day != Progress.today():
		reward_shown_day = Progress.today()
		ui.show_screen("reward")


func pause() -> void:
	if state != "play":
		return
	clear_pointers()
	# An online match keeps going: the other player is still playing
	if mode != "online":
		state = "paused"
	ui.show_screen("paused")


func resume() -> void:
	if screen_open != "paused":
		return
	if state == "paused":
		state = "play"
	ui.show_screen("")


func restart() -> void:
	if mode == "campaign" and daily:
		start_daily()
	elif mode == "campaign":
		start_level(level)
	else:
		net.restart()


func quit_to_menu() -> void:
	if mode == "online":
		net.leave()
	open_menu()


func toggle_speed() -> void:
	speed = 2 if speed == 1 else 1
	ui.refresh_speed()


func toggle_sound() -> void:
	save.muted = not save.muted
	sfx.muted = save.muted
	music.set_enabled(save.music and not save.muted)
	write_save()
	ui.refresh_toggles()


func toggle_music() -> void:
	save.music = not save.music
	music.set_enabled(save.music and not save.muted)
	write_save()
	ui.refresh_toggles()


func buy(id: String) -> void:
	for u in UPGRADES:
		if u.id != id:
			continue
		var lv: int = save.up[id]
		if lv >= u.max or save.coins < u.cost[lv]:
			return
		save.coins -= u.cost[lv]
		save.up[id] = lv + 1
		write_save()
		play_sound("coin")


# ---------- Each frame ----------
func _process(delta: float) -> void:
	var dt := minf(0.05, delta)
	# On Auto, if the game keeps running below ~35 frames a second, step the graphics down
	if save.gfx == "auto" and world.quality > 0 and delta < 0.5:
		slow_frames = slow_frames + 1 if delta > 1.0 / 35 else maxi(0, slow_frames - 2)
		if slow_frames > 150:
			slow_frames = 0
			world.lower_quality()
			if state == "play":
				ui.toast("Graphics lowered to keep the game smooth")
	if state == "play":
		for i in speed:
			step(dt)
		ui.update_hud()
	elif state == "menu":
		_menu_demo(dt)
	_update_effects(dt)
	for d in drags.values():
		d.over = tower_at(d.pos, 1.2)
	world.render(dt, battle, highlight, shells)
	shake = maxf(0, shake - dt * 30)
	world.camera.h_offset = (randf() - 0.5) * shake * 0.6 if shake > 0 else 0.0
	world.camera.v_offset = (randf() - 0.5) * shake * 0.6 if shake > 0 else 0.0


func step(dt: float) -> void:
	if net.pause_tick(dt):
		return
	if net.is_guest():
		net.guest_update(dt)
		return
	battle.update(dt)
	if hint_text != "" and armed == "":
		hint_timer -= dt
		if hint_timer <= 0 and not hand_shown:
			set_hint("")
	check_end()
	if mode == "online":
		net.host_tick(dt)


func _update_effects(dt: float) -> void:
	for f in floats:
		f.life -= dt
	floats = floats.filter(func(f): return f.life > 0)
	for s in shells:
		s.time -= dt
	shells = shells.filter(func(s): return s.time > 0)
	for c in cut_marks:
		c.life -= dt
	cut_marks = cut_marks.filter(func(c): return c.life > 0)
	if not upgrade_offer.is_empty():
		upgrade_offer.life -= dt
		if upgrade_offer.life <= 0 or upgrade_offer.t.owner != Battle.PLAYER or state != "play":
			upgrade_offer = {}


## A battle between computer armies plays behind the menu
func _menu_demo(dt: float) -> void:
	if not battle.towers.is_empty() and (not battle.alive(1) or not battle.alive(2)):
		demo_timer = minf(demo_timer, 3)
	if demo_timer <= 0 or battle.towers.is_empty():
		var n := 7 + randi() % 30
		mode = "campaign"
		load_battle(Levels.gen(n), n)
		for side in [1, 2, 3, 4]:
			if battle.towers.any(func(t): return t.owner == side):
				battle.ai_sides.append({"side": side, "timer": 1.0 + side * 0.4, "cfg": {"think": 1.4, "margin": 3.0, "bold": 0.5}})
		demo_timer = 90.0
	demo_timer -= dt
	quiet = true
	battle.update(dt)
	quiet = false
