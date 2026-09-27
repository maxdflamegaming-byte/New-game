extends Node2D
## Color Claim: game flow (menu, countdown, play, win/lose), controls, camera, HUD and screens.
## Behind the menu a bots-only game plays as a live background.

const CELL := 32.0
const SAVE_PATH := "user://save.cfg"
const INK := Color("#1f2744")
const MUTED := Color("#6b7690")
const YELLOW := Color("#ffc233")
const NAVY := Color("#1d2342")

var world
var view
var sfx
var music
var cam: Camera2D
var font: Font
var font_med: Font

var state := "menu" # menu, countdown, play, won, paused, over
var my_color := 0
var map_id := "square"
var mode_id := "classic"
var wallet := 0 # coins you've saved up
var owned := {"skin": ["plain"], "trail": ["none"], "pet": ["none"]} # bought in the shop
var equipped := {"skin": "plain", "trail": "none", "pet": "none"} # what you're wearing
var prog := Progress.new() # levels, missions, streak, trophies and stats
var difficulty := "normal"
var vibration := true
var big_stick := false
var player_name := "You"
var play_mode := "classic" # the mode being played (the tutorial isn't picked on the menu)
# This game's tallies, for missions and trophies
var _power_count := 0
var _best_loop := 0.0
var _multi := 0
var _lives_lost := 0
var _king_hits := 0
var _tut_step := 0 # 1..5 in the tutorial
var bests := {} # best claim per mode (the Daily's is per day)
var games := 0
var wins := 0
var countdown := 0.0
var slowmo := 0.0
var shake := 0.0
var peak := 0.0
var play_time := 0.0
var ending := false
var _game_id := 0 # bumps every game, so a delayed event from an old game does nothing
var _kos: Array[float] = []
var _marks := {}
var _hud_timer := 0.0
var _mm_timer := 0.0
var _last_count := 0
var _tick := 0
var split = null # the split screen in 2 Players

# Player 2's touch joystick (the other half of the screen)
var _stick2_index := -1
var _stick2_origin := Vector2.ZERO
var _stick2_pos := Vector2.ZERO

# Touch joystick: put a finger down anywhere and drag
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO

# UI
var ui_layer: CanvasLayer
var hud: Control
var pct_label: Label
var goal_bar: Control
var status_label: Label
var coin_label: Label
var fx_row: HBoxContainer
var mode_pill: PanelContainer
var mode_row: HBoxContainer
var left_card: Control
var right_card: Control
var mm_card: Control
var duo_labels: Array = []
var board_rows: Array = []
var minimap: TextureRect
var mm_dot: Control
var mm_img: Image
var mm_tex: ImageTexture
var toast_label: Label
var toast_panel: PanelContainer
var _toast_tween: Tween
var callout_label: Label
var count_label: Label
var stick_view: Control
var menu: Control
var pause_screen: Control
var over_screen: Control
var over_title: Label
var over_reason: Label
var over_stats: Label
var over_best: Label
var over_coins: Label
var wallet_label: Label
var maps_row: HBoxContainer
var modes_row: HFlowContainer
var mode_desc: Label
var best_label: Label
var swatches: HBoxContainer
var shop: Control
var missions_screen: Control
var profile_screen: Control
var settings_screen: Control
var level_label: Label
var level_bar: Control
var missions_badge: Label
var diff_row: HBoxContainer
var over_rewards: VBoxContainer
var over_xp: Label
var over_xp_bar: Control
var again_btn: Button
var ask_box: Control
var tut_card: PanelContainer
var tut_label: Label
var toast_row: HBoxContainer
var fps_label: Label
var vignette: CanvasLayer
var flash_rect: ColorRect
var _punch := 0.0 # a quick zoom-in when you claim land
var _punch_k := 1.0
var _fps_timer := 0.0


func _ready() -> void:
	randomize()
	_load()
	Gfx.apply(get_tree())
	font = load("res://assets/fonts/Fredoka-Bold.ttf")
	font_med = load("res://assets/fonts/Fredoka-Medium.ttf")
	sfx = preload("res://scripts/sfx.gd").new()
	sfx.muted = get_meta("muted", false)
	add_child(sfx)
	music = preload("res://scripts/music.gd").new()
	music.enabled = get_meta("music", true)
	add_child(music)
	world = preload("res://scripts/world.gd").new()
	add_child(world)
	view = preload("res://scripts/board_view.gd").new()
	add_child(view)
	view.setup(world, font, 128)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	world.captured.connect(_on_captured)
	world.knocked_out.connect(_on_knocked_out)
	world.picked.connect(_on_picked)
	world.coin_taken.connect(_on_coin)
	world.boss_hit.connect(_on_boss_hit)
	world.guards_called.connect(_on_guards)
	_build_ui()
	_start_demo()


# ---------- Game flow ----------

func _start_demo() -> void:
	_game_id += 1
	state = "menu"
	_split_off()
	world.looks = equipped
	world.difficulty = "normal"
	world.setup(my_color, player_name, true, map_id)
	view.rebuild()
	_snap_camera()
	_show(menu)
	_refresh_menu()


func start_game(mode := "") -> void:
	# The first game ever offers the tutorial
	if mode == "" and state == "menu" and prog.stats.games == 0 and not prog.tutorial_done and not ask_box.get_meta("asked", false):
		ask_box.set_meta("asked", true)
		ask_box.visible = true
		return
	ask_box.visible = false
	_game_id += 1
	play_mode = mode if mode != "" else mode_id
	world.looks = equipped
	world.difficulty = difficulty
	world.setup(my_color, player_name, false, map_id, play_mode)
	view.rebuild()
	if world.p2:
		_split_on()
	else:
		_split_off()
	_snap_camera()
	state = "countdown"
	countdown = 3.0
	_last_count = 4
	peak = 0.0
	play_time = 0.0
	slowmo = 0.0
	ending = false
	_kos.clear()
	_marks.clear()
	_power_count = 0
	_best_loop = 0.0
	_multi = 0
	_lives_lost = 0
	_king_hits = 0
	_tut_step = 1 if play_mode == "tutorial" else 0
	_update_tutorial()
	_show(null)
	hud.visible = true
	_update_hud()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var me: Player = world.me
	match state:
		"menu":
			world.update(dt)
			if not me.alive:
				world.spawn(me)
		"countdown":
			countdown -= dt
			_steer()
			me.angle = me.desired
			if world.p2:
				world.p2.angle = world.p2.desired
			var c := int(ceil(countdown))
			if c != _last_count and c > 0:
				_last_count = c
				_pop(count_label, str(c))
				sfx.play("beep")
			if countdown <= 0:
				state = "play"
				_pop(count_label, "GO!")
				sfx.play("go")
				_vibrate(40)
		"play", "won":
			var k := 0.35 if slowmo > 0 else 1.0
			slowmo = maxf(0.0, slowmo - dt)
			if state == "play":
				_steer()
			world.update(dt * k)
			play_time += dt * k
			if me.alive:
				peak = maxf(peak, world.pct(me))
			if state == "play":
				_check_end()
				if _tut_step > 0:
					_update_tutorial()
			_check_danger()
			if not world.p2:
				_milestones()
	_update_camera(dt)
	_hud_timer -= dt
	if hud.visible and _hud_timer <= 0:
		_hud_timer = 0.2
		_update_hud()
	_mm_timer -= dt
	if hud.visible and _mm_timer <= 0:
		_mm_timer = 0.25
		_update_minimap()
	stick_view.queue_redraw()
	if Gfx.show_fps:
		_fps_timer -= delta
		if _fps_timer <= 0:
			_fps_timer = 0.5
			fps_label.text = "%d FPS" % Engine.get_frames_per_second()


## How each mode is won or lost
func _check_end() -> void:
	var me: Player = world.me
	var m: Dictionary = world.mode
	var goal: float = m.get("win", 0.0)
	if m.get("duo", false):
		if world.pct(me) >= goal:
			_win("%s claimed %d%% of the map!" % [me.name, int(goal)], me)
		elif world.pct(world.p2) >= goal:
			_win("%s claimed %d%% of the map!" % [world.p2.name, int(goal)], world.p2)
	elif m.get("teams", false):
		if world.team_pct(0) >= goal:
			_win("Your team claimed %d%% of the map!" % int(goal))
		elif world.team_pct(1) >= goal:
			_lose("The other team claimed %d%% first." % int(goal), 0.6)
	elif m.get("boss", false):
		if world.king and not world.king.alive:
			_win("You defeated the King!")
	elif m.has("time"):
		var left: float = m.time - play_time
		if left <= 10 and ceili(left) != _tick and left > 0:
			_tick = ceili(left)
			sfx.play("tick")
			if _tick == 10:
				_callout("10 SECONDS!", Color("#ff5d73"))
		if left <= 0 and me.alive:
			var place: int = world.rank_of(me)
			if place == 1:
				_win("Time's up and you're the biggest!")
			else:
				_lose("Time's up! You finished #%d of %d." % [place, world.alive_count()], 0.6)
	elif m.get("tutorial", false):
		if _tut_step >= 5 and me.alive and world.pct(me) >= goal:
			_win("You finished the tutorial!")
	elif goal > 0 and me.alive and world.pct(me) >= goal:
		_win("You claimed %d%% of the map!" % int(goal))


func _win(reason: String, who: Player = null) -> void:
	state = "won"
	world.won = true
	slowmo = 1.4
	sfx.play("win")
	_vibrate(120)
	_callout("VICTORY!" if who == null else "%s WINS!" % who.name.to_upper(), YELLOW)
	var at: Vector2 = (who if who else world.me).pos
	for i in 6:
		view.burst(at + Vector2(randf_range(-6, 6), randf_range(-5, 5)), world.COLORS[i], 30, 520.0)
	var id := _game_id
	await get_tree().create_timer(1.6).timeout
	if id == _game_id:
		_game_over(true, reason, who)


func _lose(reason: String, delay: float) -> void:
	state = "won" # the game is over; keep playing the moment out
	var id := _game_id
	await get_tree().create_timer(delay).timeout
	if id == _game_id:
		_game_over(false, reason)


func start_tutorial() -> void:
	start_game("tutorial")


func _best_key() -> String:
	return "daily-" + world.today() if play_mode == "daily" else play_mode


func _game_over(won: bool, reason: String, who: Player = null) -> void:
	if state == "over":
		return
	state = "over"
	_split_off(true)
	over_title.label_settings.font_color = YELLOW if won else Color.WHITE
	over_reason.text = reason
	again_btn.text = "Play again"
	over_xp.text = ""
	over_xp_bar.visible = false
	var rewards := []
	if play_mode == "tutorial":
		over_title.text = "Well done!"
		over_stats.text = "You know how to play. Now take on the real bots!"
		over_best.text = ""
		var first: bool = not prog.tutorial_done
		prog.tutorial_done = true
		if first:
			rewards.append({"text": "Tutorial complete", "coins": 50, "kind": "mission"})
		rewards.append_array(prog.award("tutorial"))
		over_coins.text = ""
		again_btn.text = "Play for real"
	elif world.p2:
		# 2 Players is just for fun: no coins or records (but it counts for trying every mode)
		var winner: Player = who if who else (world.p2 if not world.me.alive else world.me)
		over_title.text = "%s wins!" % winner.name
		over_title.label_settings.font_color = winner.color.lightened(0.2)
		over_stats.text = "%s %.1f%%  ·  %s %.1f%%" % [world.me.name, world.pct(world.me), world.p2.name, world.pct(world.p2)]
		over_best.text = "2-player games are just for fun"
		over_coins.text = ""
		rewards = prog.finish({"mode": "duo", "map": world.map_id}, world.today())
	else:
		games += 1
		if won:
			wins += 1
		var score := snappedf(peak, 0.1)
		var key := _best_key()
		var new_best: bool = score > bests.get(key, 0.0)
		if new_best:
			bests[key] = score
		var earned: int = roundi(score * 2) + world.me.kills * 5 + (50 if won else 0) + world.coins_picked
		if won and world.mode.get("boss", false):
			earned += 100
		var mult: float = world.DIFFICULTY[difficulty].coins
		earned = roundi(earned * mult)
		wallet += earned
		var level_before: int = prog.level
		var xp_before: float = float(prog.xp) / Progress.need(prog.level)
		var gained := Progress.xp_for({"pct": score, "kos": world.me.kills, "won": won})
		rewards = prog.finish({
			"mode": play_mode, "map": world.map_id, "won": won, "pct": score, "kos": world.me.kills,
			"powerups": _power_count, "coins": world.coins_picked / world.COIN_VALUE, "time": play_time,
			"best_loop": _best_loop, "king_hits": _king_hits, "lives_lost": _lives_lost, "multi_ko": _multi,
			"wallet": wallet,
		}, world.today())
		over_coins.text = "+%d coins" % earned + ("  (x%s %s)" % [str(mult), world.DIFFICULTY[difficulty].name] if mult != 1.0 else "")
		over_title.text = "You win!" if won else "Game over"
		over_stats.text = "Best size %.1f%%  ·  %d knockout%s  ·  %s" % [score, world.me.kills, "" if world.me.kills == 1 else "s", _fmt_time(play_time)]
		var label: String = "Today's best" if play_mode == "daily" else "%s best" % world.MODES[play_mode].name
		over_best.text = ("New %s!" % label.to_lower()) if new_best else "%s: %.1f%%" % [label, bests.get(key, 0.0)]
		# XP: the bar fills up (and wraps round on a level up)
		over_xp.text = "Level %d  ·  +%d XP" % [prog.level, gained]
		over_xp_bar.visible = true
		var to: float = float(prog.xp) / Progress.need(prog.level)
		over_xp_bar.set_meta("fill", xp_before)
		var tw := over_xp_bar.create_tween()
		if prog.level > level_before:
			tw.tween_method(_set_xp_fill, xp_before, 1.0, 0.6)
			tw.tween_method(_set_xp_fill, 0.0, to, 0.5)
		else:
			tw.tween_method(_set_xp_fill, xp_before, to, 0.8)
	for r in rewards:
		wallet += r.coins
	_save()
	_show_rewards(rewards)
	_show(over_screen)


func _flash(c: Color) -> void:
	flash_rect.color = c
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.45)


func _set_xp_fill(f: float) -> void:
	over_xp_bar.set_meta("fill", f)
	over_xp_bar.queue_redraw()


## Level-ups, missions, streak and trophies on the results screen, popping in one by one
func _show_rewards(rewards: Array) -> void:
	for c in over_rewards.get_children():
		c.queue_free()
	over_rewards.visible = not rewards.is_empty()
	var colors := {"level": Color("#8d7bd6"), "mission": Color("#2ec48a"), "streak": Color("#ff8a1f"), "trophy": Color("#e0a800")}
	var id := _game_id
	for i in rewards.size():
		var r: Dictionary = rewards[i]
		var pill := PanelContainer.new()
		var st := _style(colors.get(r.kind, INK), 20)
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		pill.add_theme_stylebox_override("panel", st)
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		pill.add_child(row)
		row.add_child(_label(r.text, 26, Color.WHITE))
		row.add_child(_icon(Art.COIN, 26, Color.WHITE))
		row.add_child(_label("+%d" % r.coins, 26, Color("#fff1a8")))
		pill.modulate.a = 0.0
		over_rewards.add_child(pill)
		var tw := pill.create_tween()
		tw.tween_interval(0.5 + i * 0.35)
		tw.tween_property(pill, "modulate:a", 1.0, 0.25)
		tw.tween_callback(func():
			if id == _game_id and state == "over":
				sfx.play("hype" if r.kind == "level" else "coin"))


func _pause() -> void:
	if state != "play" and state != "countdown":
		return
	pause_screen.set_meta("was", state)
	state = "paused"
	_show(pause_screen)


func _resume() -> void:
	if state != "paused":
		return
	state = pause_screen.get_meta("was", "play")
	_show(null)


func _to_menu() -> void:
	hud.visible = false
	_start_demo()


# ---------- 2 Players: split screen ----------

func _split_on() -> void:
	if split == null:
		split = preload("res://scripts/split_view.gd").new()
		add_child(split)
	split.visible = true
	split.layout()
	# The main camera looks far away, so the world isn't drawn a third time
	cam.position = Vector2(1e6, 1e6)
	_layout_hud()


## Leaves the split screen; keep_view leaves it up (for the results screen)
func _split_off(keep_view := false) -> void:
	if split and not keep_view:
		split.visible = false
	if hud:
		_layout_hud()


func _back() -> void:
	match state:
		"play", "countdown":
			_pause()
		"paused":
			_resume()
		"over":
			_to_menu()
		"menu":
			if ask_box.visible:
				ask_box.visible = false
				return
			for sc in [shop, missions_screen, profile_screen, settings_screen]:
				if sc.visible:
					sc.close()
					return
			get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Gfx.apply(get_tree()) # the screen may have been rebuilt; ask for our frame rate again


## New graphics settings: apply and save them
func _apply_gfx() -> void:
	Gfx.apply(get_tree())
	fps_label.get_parent().visible = Gfx.show_fps
	vignette.visible = Gfx.level >= Gfx.HIGH
	if split and split.visible:
		split.layout()
	_save()


# ---------- Events ----------

func _on_captured(p: Player, _cells: PackedInt32Array, gain: float) -> void:
	if p != world.me or state == "menu":
		return
	_best_loop = maxf(_best_loop, gain)
	_punch = clampf(gain / 4.0, 0.3, 1.0)
	if _tut_step == 2:
		_tut_next()
	sfx.play("capture")
	if gain >= 1.0:
		_vibrate(20)
	if gain >= 10:
		_callout("GIGA LOOP!", Color("#ff5d73"))
		shake = 0.5
	elif gain >= 5:
		_callout("MEGA LOOP!", Color("#ff8c42"))
		shake = 0.3


func _on_knocked_out(v: Player, killer: Player, how: String, _lost: PackedInt32Array) -> void:
	if state == "menu":
		return
	var me: Player = world.me
	if world.p2 and (v == me or v == world.p2) and not ending:
		# 2 Players: the first human knocked out loses
		ending = true
		sfx.play("death")
		shake = 1.0
		_vibrate(300)
		var winner: Player = world.p2 if v == me else me
		var id := _game_id
		await get_tree().create_timer(0.9).timeout
		if id == _game_id:
			_game_over(true, "%s was knocked out%s." % [v.name, "" if killer == null or killer == v else " by " + killer.name], winner)
	elif v == me and me.lives > 1 and not ending:
		# Boss Battle: lose a life and come back somewhere else (the tutorial has lots)
		me.lives -= 1
		_lives_lost += 1
		_flash(Color(1, 0.3, 0.35, 0.35))
		sfx.play("hurt")
		shake = 1.0
		_vibrate(200)
		if _tut_step > 0:
			_toast("Oops! Never cross your own trail. Try again!")
		else:
			_toast("Ouch! %d %s left" % [me.lives, "life" if me.lives == 1 else "lives"])
		var id := _game_id
		await get_tree().create_timer(1.2).timeout
		if id == _game_id and not me.alive:
			if not world.spawn(me):
				world.spawn(me, world.N / 2, world.N / 2)
			_snap_camera()
	elif v == me and not ending:
		ending = true
		_flash(Color(1, 0.3, 0.35, 0.45))
		sfx.play("death")
		shake = 1.0
		_vibrate(300)
		var reason := "You crossed your own trail!" if killer == me \
			else "%s swallowed all your land!" % killer.name if how == "swallow" \
			else "You bumped into %s outside your land!" % killer.name if how == "bump" \
			else "The %s cut your trail!" % killer.name if killer.is_boss \
			else "%s cut your trail!" % killer.name
		var id := _game_id
		await get_tree().create_timer(0.9).timeout
		if id == _game_id:
			_game_over(false, reason)
	elif v.is_boss and state != "menu":
		sfx.play("bossdown")
		shake = 1.0
		_vibrate(250)
	elif killer == me and v != me:
		sfx.play("cut")
		shake = maxf(shake, 0.4)
		_vibrate(40)
		_toast("You knocked out %s!" % v.name)
		var now: float = world.time
		_kos = _kos.filter(func(t): return now - t < 4.0)
		_kos.append(now)
		_multi = maxi(_multi, _kos.size())
		if _tut_step == 4:
			_tut_next()
		if _kos.size() >= 3:
			_callout("TRIPLE KO!", Color("#ff5d73"))
		elif _kos.size() == 2:
			_callout("DOUBLE KO!", Color("#ff8c42"))


func _on_boss_hit(k: Player, by: Player) -> void:
	if state == "menu":
		return
	if by == world.me:
		_king_hits += 1
	sfx.play("bosshit")
	shake = maxf(shake, 0.8)
	_vibrate(80)
	view.float_text(k.pos + Vector2(0, -3), "-1 heart", Color("#ff5d73"), Color.WHITE, 1.3)
	if k.hp == 1:
		_callout("LAST HEART!", Color("#ff5d73"))
		_toast("The King is furious!")


func _on_guards(_k: Player) -> void:
	if state == "menu":
		return
	sfx.play("roar")
	_toast("The King calls for guards!")


const PICK_TOASTS := {
	"speed": "Speed boost!", "shield": "Shield! Nobody can cut your trail", "freeze": "Freeze! Everyone else slows down",
	"ghost": "Ghost! You can cross your own trail", "paint": "Paint bomb!",
}


func _on_picked(p: Player, kind: String, _at: Vector2) -> void:
	if state == "menu":
		return
	if p == world.me:
		_power_count += 1
		sfx.play(kind)
		_toast(PICK_TOASTS[kind])
		_vibrate(15)
		if _tut_step == 3:
			_tut_next()
	elif kind == "freeze" and world.me.alive and p.pos.distance_to(world.me.pos) < 40:
		sfx.play("freeze")
		_toast("%s froze everyone!" % p.name)


func _on_coin(p: Player, at: Vector2) -> void:
	if p == world.me and state != "menu":
		sfx.play("coin")
		view.float_text(at + Vector2(0, -1), "+%d" % world.COIN_VALUE, Color("#ffd23f"), Color("#9a6a00"), 0.8)


func _milestones() -> void:
	var p: float = world.pct(world.me)
	for m in [[10, "10% CLAIMED", Color("#4f8cff")], [25, "DOMINATING!", Color("#b06bff")], [40, "ALMOST THERE!", Color("#2ec4b6")]]:
		if p >= m[0] and not _marks.has(m[0]):
			_marks[m[0]] = true
			_callout(m[1], m[2])


## Enemies close to your exposed trail get a "!" and your trail pulses red
func _check_danger() -> void:
	var me: Player = world.me
	var danger := 0.0
	var n: int = world.N
	for p in world.players:
		if p == null or world.allies(p, me) or (world.p2 and p == world.p2):
			continue
		var close := INF
		if me.alive and me.trail.size() > 0 and me.shield <= 0 and p.alive:
			for k in range(0, me.trail.size(), 2):
				var i: int = me.trail[k]
				close = minf(close, p.pos.distance_to(Vector2(i % n + 0.5, i / n + 0.5)))
		if view.views.has(p.id):
			view.views[p.id].threat = close < 10
		if close < 7:
			danger = maxf(danger, 1.0 - close / 7.0)
	if danger > 0.3 and view.danger <= 0.3:
		sfx.play("warn")
	view.danger = danger


# ---------- Tutorial ----------

const TUT_STEPS := [
	"",
	"Step 1 of 5\nDrag anywhere to steer. Leave your land to draw a trail!",
	"Step 2 of 5\nNow come back to your land. Everything inside your loop becomes yours!",
	"Step 3 of 5\nGrab the power-up! Follow the arrow.",
	"Step 4 of 5\nKnock out Coach: drive across Coach's trail while it's outside its land. Coach can't hurt you.",
	"Step 5 of 5\nClaim 15% of the map to finish. Never cross your own trail!",
]


func _update_tutorial() -> void:
	tut_card.visible = _tut_step > 0 and state != "over"
	toast_row.offset_top = (430 if _tut_step > 0 else 340) + _safe_margins().y
	if _tut_step == 0:
		return
	tut_label.text = TUT_STEPS[_tut_step]
	var me: Player = world.me
	if _tut_step == 1 and me.alive and me.trail.size() >= 4:
		_tut_next()
	elif _tut_step == 3 and world.powerups.is_empty():
		_place_tut_powerup()


func _tut_next() -> void:
	_tut_step = mini(_tut_step + 1, 5)
	sfx.play("coin")
	_callout(["", "", "NICE!", "GREAT!", "AWESOME!", "SUPER!"][_tut_step], Color("#2ec48a"))
	if _tut_step == 3:
		_place_tut_powerup()
	elif _tut_step == 5:
		world._coin_timer = 1.0 # coins start showing up
	tut_label.text = TUT_STEPS[_tut_step]
	tut_card.pivot_offset = tut_card.size / 2
	tut_card.scale = Vector2(1.08, 1.08)
	tut_card.create_tween().tween_property(tut_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


## A power-up a few cells in front of you, somewhere open
func _place_tut_powerup() -> void:
	var me: Player = world.me
	for k in 12:
		var q: Vector2 = me.pos + Vector2.from_angle(me.angle + k * 0.5) * 7.0
		if q.x > 2 and q.y > 2 and q.x < world.N - 2 and q.y < world.N - 2 and not world.is_wall_at(q.x, q.y):
			world.powerups.append({"pos": q, "kind": "speed", "age": 0.0})
			return


## In the tutorial, an arrow points at the power-up or at Coach
func _draw_tut_arrow() -> void:
	if _tut_step != 3 and _tut_step != 4:
		return
	var target := Vector2.INF
	if _tut_step == 3 and not world.powerups.is_empty():
		target = world.powerups[0].pos
	elif _tut_step == 4 and world.players.size() > 2 and world.players[2].alive:
		target = world.players[2].pos
	if target == Vector2.INF:
		return
	var at: Vector2 = get_viewport().canvas_transform * (target * CELL)
	var vis := get_viewport_rect().size
	var t := Time.get_ticks_msec() / 1000.0
	var inside := Rect2(Vector2(60, 330), vis - Vector2(120, 520))
	var tip: Vector2
	var dir: Vector2
	if inside.has_point(at):
		dir = Vector2.DOWN
		tip = at - Vector2(0, 46 + sin(t * 8.0) * 8.0)
	else:
		var c := inside.get_center()
		dir = (at - c).normalized()
		# Where the line to the target leaves the box
		var k := INF
		if dir.x != 0:
			k = minf(k, absf((inside.size.x / 2) / dir.x))
		if dir.y != 0:
			k = minf(k, absf((inside.size.y / 2) / dir.y))
		tip = c + dir * (k + sin(t * 8.0) * 8.0)
	var side := dir.orthogonal()
	var pts := PackedVector2Array([tip, tip - dir * 44 + side * 26, tip - dir * 44 - side * 26])
	stick_view.draw_colored_polygon(pts, Color("#ffc233"))
	stick_view.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color("#5a3200"), 4.0, true)


func _build_ask() -> void:
	ask_box = Control.new()
	ask_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ask_box.visible = false
	ui_layer.add_child(ask_box)
	_dim(ask_box, Color(0.08, 0.1, 0.2, 0.6), Color(0.08, 0.1, 0.2, 0.8))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ask_box.add_child(center)
	var c := _card(Color(1, 1, 1, 0.97))
	center.add_child(c)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	c.add_child(col)
	col.add_child(_label("New here?", 54, INK))
	var t := _label("Learn the basics in a quick tutorial, and get 50 coins for finishing it.", 28, MUTED, 0, INK, font_med)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 520
	col.add_child(t)
	var yes := _button("Play the tutorial", YELLOW, Color("#5a3200"), Color("#d27a06"), 36)
	yes.custom_minimum_size = Vector2(0, 96)
	yes.pressed.connect(start_tutorial)
	col.add_child(yes)
	var no := _button("Skip, just play", Color(0.12, 0.15, 0.27, 0.08), INK, Color(0.12, 0.15, 0.27, 0.1), 28)
	no.custom_minimum_size = Vector2(0, 80)
	no.pressed.connect(func(): start_game())
	col.add_child(no)


# ---------- Controls ----------

func _keys(left: int, right: int, up: int, down: int) -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(left):
		v.x -= 1
	if Input.is_key_pressed(right):
		v.x += 1
	if Input.is_key_pressed(up):
		v.y -= 1
	if Input.is_key_pressed(down):
		v.y += 1
	return v


func _steer() -> void:
	var me: Player = world.me
	var v := _keys(KEY_A, KEY_D, KEY_W, KEY_S)
	if not world.p2:
		v += _keys(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN)
	if v == Vector2.ZERO and _stick_index >= 0 and _stick_pos.distance_to(_stick_origin) > 12:
		v = _stick_pos - _stick_origin
	if v != Vector2.ZERO and me.alive:
		me.desired = v.angle()
	if world.p2 and world.p2.alive:
		var v2 := _keys(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN)
		if v2 == Vector2.ZERO and _stick2_index >= 0 and _stick2_pos.distance_to(_stick2_origin) > 12:
			v2 = _stick2_pos - _stick2_origin
		if v2 != Vector2.ZERO:
			world.p2.desired = v2.angle()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		# In 2 Players, a finger on Player 2's half of the screen steers Player 2
		var second: bool = world.p2 != null and split != null and split.rect(1).has_point(e.position)
		if e.pressed and second and _stick2_index == -1:
			_stick2_index = e.index
			_stick2_origin = e.position
			_stick2_pos = e.position
		elif e.pressed and not second and _stick_index == -1:
			_stick_index = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif not e.pressed and e.index == _stick_index:
			_stick_index = -1
		elif not e.pressed and e.index == _stick2_index:
			_stick2_index = -1
	elif e is InputEventScreenDrag and e.index == _stick_index:
		_stick_pos = e.position
		# Drag far and the joystick follows your finger, so you never run out of room
		var d: Vector2 = _stick_pos - _stick_origin
		if d.length() > _stick_r():
			_stick_origin = _stick_pos - d.normalized() * _stick_r()
	elif e is InputEventScreenDrag and e.index == _stick2_index:
		_stick2_pos = e.position
		var d2: Vector2 = _stick2_pos - _stick2_origin
		if d2.length() > _stick_r():
			_stick2_origin = _stick2_pos - d2.normalized() * _stick_r()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE or e.keycode == KEY_P:
			if state == "paused":
				_resume()
			else:
				_pause()
		elif e.keycode == KEY_ENTER or e.keycode == KEY_SPACE:
			if state == "menu" or state == "over":
				start_game()


func _stick_r() -> float:
	return 125.0 if big_stick else 90.0


func _draw_stick() -> void:
	if not (state == "play" or state == "countdown"):
		return
	_draw_tut_arrow()
	var r := _stick_r()
	for s in [[_stick_index, _stick_origin, _stick_pos], [_stick2_index, _stick2_origin, _stick2_pos]]:
		if s[0] < 0:
			continue
		stick_view.draw_circle(s[1], r, Color(1, 1, 1, 0.12), true, -1, true)
		stick_view.draw_arc(s[1], r, 0, TAU, 64, Color(0.12, 0.15, 0.27, 0.35), 3.0, true)
		var d: Vector2 = (s[2] - s[1]).limit_length(r)
		stick_view.draw_circle(s[1] + d, r * 0.42, Color(0.12, 0.15, 0.27, 0.35), true, -1, true)


func _vibrate(ms: int) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------- Camera ----------

func _cam_zoom(p: Player = null) -> float:
	var who: Player = p if p else world.me
	var vis := get_viewport_rect().size
	if world.p2 and split:
		vis = split.rect(0).size
	var cell_px := minf(vis.x, vis.y) / (25.0 if not world.p2 else 18.0)
	var z := cell_px / CELL * (1.0 - minf(0.3, world.pct(who) / 90.0))
	return z * (0.8 if state == "menu" else 1.0)


var _duo_cams := [{}, {}]


func _snap_camera() -> void:
	cam.position = world.me.pos * CELL
	cam.zoom = Vector2.ONE * _cam_zoom()
	_punch = 0.0
	_punch_k = 1.0
	if world.p2:
		cam.position = Vector2(1e6, 1e6)
		for i in 2:
			var p: Player = world.humans()[i]
			_duo_cams[i] = {"pos": p.pos * CELL, "zoom": _cam_zoom(p)}


## The camera glides after you, looking a little ahead, and zooms out as your land grows
func _update_camera(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 2.0)
	var jiggle := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * CELL * 0.35
	if world.p2 and split and split.visible:
		for i in 2:
			var p: Player = world.humans()[i]
			var c: Dictionary = _duo_cams[i]
			var lead := Vector2.from_angle(p.angle) * 2.0 if p.alive else Vector2.ZERO
			c.pos = c.pos.lerp((p.pos + lead) * CELL, 1.0 - exp(-dt * 4.5))
			c.zoom = lerpf(c.zoom, _cam_zoom(p), 1.0 - exp(-dt * 1.8))
			split.aim(i, c.pos, c.zoom, jiggle)
		return
	var me: Player = world.me
	var lead := Vector2.from_angle(me.angle) * 2.2 if me.alive else Vector2.ZERO
	cam.position = cam.position.lerp((me.pos + lead) * CELL, 1.0 - exp(-dt * 4.5))
	var base := (cam.zoom / _punch_k).lerp(Vector2.ONE * _cam_zoom(), 1.0 - exp(-dt * 1.8))
	_punch = move_toward(_punch, 0.0, dt * 2.2)
	_punch_k = 1.0 + 0.05 * sin(_punch * PI * 0.5)
	cam.zoom = base * _punch_k
	cam.offset = jiggle


# ---------- HUD ----------

func _update_hud() -> void:
	var me: Player = world.me
	_update_mode_pill()
	if world.p2:
		for i in 2:
			var h: Player = world.humans()[i]
			duo_labels[i].text = "%s  %.1f%%%s" % [h.name, world.pct(h), "" if h.alive else "  ·  out"]
			duo_labels[i].label_settings.font_color = h.color.lightened(0.1)
		return
	pct_label.text = "%.1f%%" % world.pct(me)
	var goal: float = world.mode.get("win", 0.0)
	goal_bar.visible = goal > 0
	goal_bar.set_meta("fill", clampf((world.team_pct(0) if world.mode.get("teams", false) else world.pct(me)) / maxf(goal, 1.0), 0, 1))
	goal_bar.set_meta("color", me.color)
	goal_bar.queue_redraw()
	var kos := "%d KO%s" % [me.kills, "" if me.kills == 1 else "s"]
	status_label.text = ("#%d of %d  ·  %s" % [world.rank_of(me), world.alive_count(), kos]) if me.alive else "Knocked out  ·  " + kos
	coin_label.text = str(wallet + world.coins_picked)
	# Power-ups running now, with seconds left
	for c in fx_row.get_children():
		c.queue_free()
	var chips := []
	if me.alive:
		for k in me.fx:
			if me.fx[k] > 0:
				chips.append([world.POWERUPS[k].name, me.fx[k], world.POWERUPS[k].color])
		if me.shield > 0:
			chips.append(["Shield", me.shield, world.POWERUPS.shield.color])
		if world.freezer and world.freezer != me:
			chips.append(["Frozen!", world.freezer.fx.freeze, Color("#3fc7f5")])
	for c in chips:
		var chip := PanelContainer.new()
		var st := _style(c[2], 12)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", st)
		chip.add_child(_label("%s %ds" % [c[0], ceili(c[1])], 18, Color.WHITE))
		fx_row.add_child(chip)
	var ranked := []
	for p in world.players:
		if p and p.alive:
			ranked.append(p)
	ranked.sort_custom(func(a, b): return world.counts[a.id] > world.counts[b.id])
	var top := ranked.slice(0, 5)
	if me.alive and not top.has(me):
		top[4] = me
	for r in board_rows.size():
		var row: Array = board_rows[r]
		row[0].visible = r < top.size()
		if r >= top.size():
			continue
		var p: Player = top[r]
		row[1].color = p.color
		var mark := "* " if world.mode.get("teams", false) and p != me and world.allies(p, me) else ""
		row[2].text = "%d. %s%s" % [ranked.find(p) + 1, mark, p.name]
		row[3].text = "%.1f%%" % world.pct(p)
		var c := Color("#1f5fd6") if p == me or mark != "" else Color("#d6304a") if p.is_boss else INK
		row[2].label_settings.font_color = c
	# The leaderboard shrinks to fit its rows (the Boss Battle has only a few players)
	right_card.size.y = right_card.get_combined_minimum_size().y


## The pill at the top: the clock, the team score, or the King's hearts and your lives
func _update_mode_pill() -> void:
	for c in mode_row.get_children():
		c.queue_free()
	var m: Dictionary = world.mode
	var parts := []
	if m.has("time"):
		var left: float = maxf(0.0, m.time - play_time)
		parts.append(_label("Time  " + _fmt_time(ceilf(left)), 30, Color("#ff3c50") if left <= 15 else INK))
	elif m.get("teams", false):
		parts.append(_label("Your team %.1f%%" % world.team_pct(0), 26, Color("#1f5fd6")))
		parts.append(_label("vs", 22, MUTED, 0, INK, font_med))
		parts.append(_label("%.1f%%" % world.team_pct(1), 26, Color("#d6304a")))
	elif m.get("boss", false) and world.king:
		parts.append(_label("King", 26, Color("#d6304a")))
		for i in world.king.max_hp:
			parts.append(_icon(Art.HEART, 26, Color("#ff3c50") if i < world.king.hp else Color("#d5dbe8")))
		parts.append(_label("  You", 26, INK))
		for i in 3:
			parts.append(_icon(Art.HEART, 22, world.me.color if i < world.me.lives else Color("#d5dbe8")))
	elif m.get("duo", false):
		parts.append(_label("First to %d%%" % int(m.win), 24, INK))
	elif m.get("daily", false):
		parts.append(_label("Daily · %s" % world.MAPS[world.map_id], 24, INK))
	mode_pill.visible = not parts.is_empty()
	for c in parts:
		mode_row.add_child(c)


func _icon(svg: String, size: int, tint: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.tex(svg, 64)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## 2 Players hides the solo cards and labels each half instead
func _layout_hud() -> void:
	var duo: bool = world.p2 != null and split != null and split.visible
	for c in [left_card, right_card, mm_card]:
		c.visible = not duo
	for i in duo_labels.size():
		duo_labels[i].visible = duo
		if duo:
			var r: Rect2 = split.rect(i)
			duo_labels[i].position = Vector2(r.position.x + 20, r.end.y - 64)


func _update_minimap() -> void:
	var n: int = world.N
	var lut := PackedByteArray()
	lut.resize(16 * 4)
	for p in world.players:
		if p:
			lut[p.id * 4] = int(p.color.r8)
			lut[p.id * 4 + 1] = int(p.color.g8)
			lut[p.id * 4 + 2] = int(p.color.b8)
			lut[p.id * 4 + 3] = 255
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var land: PackedByteArray = world.land
	var tr: PackedByteArray = world.trail
	for i in n * n:
		var id := land[i]
		if id == 0:
			id = tr[i]
		var o := i * 4
		if id:
			data[o] = lut[id * 4]
			data[o + 1] = lut[id * 4 + 1]
			data[o + 2] = lut[id * 4 + 2]
			data[o + 3] = 255
		elif world.wall[i] == 1:
			data[o] = 107
			data[o + 1] = 118
			data[o + 2] = 144
			data[o + 3] = 255
		elif world.wall[i] == 2:
			var sea: bool = world.map_id == "islands"
			data[o] = 124 if sea else 200
			data[o + 1] = 199 if sea else 207
			data[o + 2] = 232 if sea else 222
			data[o + 3] = 255 if sea else 120
		else:
			data[o] = 235
			data[o + 1] = 239
			data[o + 2] = 248
			data[o + 3] = 255
	mm_img.set_data(n, n, false, Image.FORMAT_RGBA8, data)
	mm_tex.update(mm_img)
	var me: Player = world.me
	mm_dot.visible = me.alive
	mm_dot.position = me.pos / n * minimap.size - mm_dot.size / 2


func _toast(text: String) -> void:
	toast_label.text = text
	toast_panel.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.3)


func _callout(text: String, color: Color) -> void:
	sfx.play("hype")
	callout_label.label_settings.font_color = color
	_pop(callout_label, text)


## Text that pops in big and fades out
func _pop(l: Label, text: String) -> void:
	l.text = text
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.4, 0.4)
	l.modulate.a = 1.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)


# ---------- UI building ----------

func _style(bg: Color, radius := 28, border_bottom := 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_width_bottom = border_bottom
	s.border_color = border
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 12
	s.content_margin_bottom = 12 + border_bottom
	s.anti_aliasing = true
	return s


func _label(text: String, size: int, color: Color = INK, outline := 0, outline_color: Color = INK, f: Font = null) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = f if f else font
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = outline_color
	l.label_settings = ls
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, bg: Color, fg: Color, edge: Color, size := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_stylebox_override("normal", _style(bg, 26, 8, edge))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.06), 26, 8, edge))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.05), 26, 3, edge))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): sfx.play("tap"))
	return b


func _card(bg: Color = Color(1, 1, 1, 0.9)) -> PanelContainer:
	var c := PanelContainer.new()
	var s := _style(bg, 26)
	s.shadow_color = Color(0.08, 0.1, 0.2, 0.18)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	c.add_theme_stylebox_override("panel", s)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	ui_layer.add_child(c)
	return c


func _show(screen: Control) -> void:
	for s in [menu, pause_screen, over_screen, shop, missions_screen, profile_screen, settings_screen]:
		if s and s != screen:
			s.visible = false
	if screen:
		screen.visible = true
		screen.modulate.a = 0.0
		create_tween().tween_property(screen, "modulate:a", 1.0, 0.25)
	hud.visible = state != "menu"


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 2 # above the 2-player split screen
	add_child(ui_layer)
	var safe := _safe_margins()

	# ----- HUD -----
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	ui_layer.add_child(hud)

	var left := _card()
	left_card = left
	hud.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	pct_label = _label("0.0%", 52)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.add_child(pct_label)
	goal_bar = Control.new()
	goal_bar.custom_minimum_size = Vector2(180, 12)
	goal_bar.draw.connect(func():
		var f: float = goal_bar.get_meta("fill", 0.0)
		goal_bar.draw_rect(Rect2(Vector2.ZERO, goal_bar.size), Color(0.12, 0.15, 0.27, 0.12))
		goal_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(goal_bar.size.x * f, goal_bar.size.y)), goal_bar.get_meta("color", Color.WHITE)))
	lv.add_child(goal_bar)
	status_label = _label("", 22, MUTED, 0, INK, font_med)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.add_child(status_label)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 6)
	var coin_icon := TextureRect.new()
	coin_icon.texture = Art.tex(Art.COIN, 64)
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_row.add_child(coin_icon)
	coin_label = _label("0", 24, Color("#b07800"))
	coin_row.add_child(coin_label)
	lv.add_child(coin_row)
	fx_row = HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 6)
	lv.add_child(fx_row)

	var right := _card()
	right_card = right
	hud.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	right.add_child(rv)
	for r in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_l := _label("", 22, INK, 0, INK, font_med)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.custom_minimum_size.x = 118
		var pct_l := _label("", 22, INK)
		pct_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct_l.custom_minimum_size.x = 66
		row.add_child(dot)
		row.add_child(name_l)
		row.add_child(pct_l)
		rv.add_child(row)
		board_rows.append([row, dot, name_l, pct_l])

	_pin(left, Control.PRESET_TOP_LEFT, safe)
	_pin(right, Control.PRESET_TOP_RIGHT, safe)

	var pause_btn := _button("II", Color(1, 1, 1, 0.9), INK, Color("#c7cfe0"), 30)
	pause_btn.custom_minimum_size = Vector2(76, 76)
	pause_btn.pressed.connect(_pause)
	hud.add_child(pause_btn)
	_pin(pause_btn, Control.PRESET_BOTTOM_RIGHT, safe)

	mm_card = _card()
	hud.add_child(mm_card)
	mm_img = Image.create(world.N, world.N, false, Image.FORMAT_RGBA8)
	mm_tex = ImageTexture.create_from_image(mm_img)
	minimap = TextureRect.new()
	minimap.texture = mm_tex
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mm_card.add_child(minimap)
	mm_dot = Control.new()
	mm_dot.size = Vector2(12, 12)
	mm_dot.draw.connect(func():
		mm_dot.draw_circle(Vector2(6, 6), 6, INK, true, -1, true)
		mm_dot.draw_circle(Vector2(6, 6), 4, Color.WHITE, true, -1, true))
	minimap.add_child(mm_dot)
	_pin(mm_card, Control.PRESET_BOTTOM_LEFT, safe)

	# The clock, team score or boss hearts, at the top in the middle
	var pill_row := HBoxContainer.new()
	pill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	pill_row.offset_top = 262 + safe.y
	hud.add_child(pill_row)
	mode_pill = _card()
	mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	mode_pill.add_child(mode_row)
	pill_row.add_child(mode_pill)
	for i in 2:
		var dl := _label("", 30, Color.WHITE, 10, NAVY)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		dl.visible = false
		hud.add_child(dl)
		duo_labels.append(dl)

	# Messages pop up on a dark rounded label near the top
	toast_row = HBoxContainer.new()
	toast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_row.offset_top = 340 + safe.y
	hud.add_child(toast_row)
	toast_panel = PanelContainer.new()
	var ts := _style(Color(0.12, 0.15, 0.27, 0.78), 24)
	ts.content_margin_left = 24
	ts.content_margin_right = 24
	ts.content_margin_top = 8
	ts.content_margin_bottom = 10
	toast_panel.add_theme_stylebox_override("panel", ts)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0
	toast_row.add_child(toast_panel)
	toast_label = _label("", 28, Color.WHITE, 0, INK, font_med)
	toast_panel.add_child(toast_label)

	# The tutorial's instructions
	var tut_row := HBoxContainer.new()
	tut_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tut_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tut_row.offset_top = 250 + safe.y
	hud.add_child(tut_row)
	tut_card = _card(Color(1, 1, 1, 0.95))
	tut_card.visible = false
	tut_row.add_child(tut_card)
	tut_label = _label("", 30, INK)
	tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_label.custom_minimum_size.x = 560
	tut_card.add_child(tut_label)

	callout_label = _label("", 84, YELLOW, 18, INK)
	callout_label.set_anchors_preset(Control.PRESET_CENTER)
	callout_label.size = Vector2(900, 120)
	callout_label.position = -callout_label.size / 2 + Vector2(0, -160)
	callout_label.set_anchors_preset(Control.PRESET_CENTER, true)
	callout_label.modulate.a = 0
	hud.add_child(callout_label)

	count_label = _label("", 180, Color.WHITE, 24, INK)
	count_label.size = Vector2(500, 220)
	count_label.set_anchors_preset(Control.PRESET_CENTER)
	count_label.position = -count_label.size / 2 + Vector2(0, -120)
	count_label.set_anchors_preset(Control.PRESET_CENTER, true)
	count_label.modulate.a = 0
	hud.add_child(count_label)

	stick_view = Control.new()
	stick_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stick_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_view.draw.connect(_draw_stick)
	hud.add_child(stick_view)

	# A soft darkening round the screen's edges (High and Ultra)
	vignette = CanvasLayer.new()
	vignette.layer = 1
	add_child(vignette)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.06, 0.08, 0.18, 0.0), Color(0.06, 0.08, 0.18, 0.0), Color(0.06, 0.08, 0.18, 0.32)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	var vr := TextureRect.new()
	vr.texture = gt
	vr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.add_child(vr)
	vignette.visible = Gfx.level >= Gfx.HIGH
	# A quick colour flash over everything (when you're knocked out)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	ui_layer.add_child(flash_rect)
	ui_layer.move_child(flash_rect, 0)

	# The frame counter (Settings -> Show FPS)
	var fps_card := _card(Color(0.12, 0.15, 0.27, 0.7))
	fps_label = _label("", 22, Color.WHITE)
	fps_card.add_child(fps_label)
	fps_card.visible = Gfx.show_fps
	ui_layer.add_child(fps_card)
	fps_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 6)
	fps_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	fps_card.offset_top += safe.y
	fps_card.offset_bottom += safe.y

	_build_menu(safe)
	_build_pause()
	_build_over()
	shop = preload("res://scripts/shop.gd").new()
	ui_layer.add_child(shop)
	shop.build(self)
	missions_screen = preload("res://scripts/missions_screen.gd").new()
	ui_layer.add_child(missions_screen)
	missions_screen.build(self)
	profile_screen = preload("res://scripts/profile_screen.gd").new()
	ui_layer.add_child(profile_screen)
	profile_screen.build(self)
	settings_screen = preload("res://scripts/settings_screen.gd").new()
	ui_layer.add_child(settings_screen)
	settings_screen.build(self)
	_build_ask()


## Puts a control in a corner of the screen, 16 units in (plus room for notches)
func _pin(c: Control, corner: int, safe: Vector4) -> void:
	c.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE, 16)
	var top := corner == Control.PRESET_TOP_LEFT or corner == Control.PRESET_TOP_RIGHT
	var left := corner == Control.PRESET_TOP_LEFT or corner == Control.PRESET_BOTTOM_LEFT
	var dy := safe.y if top else -safe.w
	var dx := safe.x if left else -safe.z
	c.offset_top += dy
	c.offset_bottom += dy
	c.offset_left += dx
	c.offset_right += dx


func _dim(screen: Control, top: Color, bottom: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(bg)


func _center_column(screen: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	return col


func _build_menu(safe: Vector4) -> void:
	menu = _screen()
	_dim(menu, Color(0.11, 0.14, 0.26, 0.15), Color(0.11, 0.14, 0.26, 0.8))
	var wallet_card := _card(Color(1, 1, 1, 0.92))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	var wicon := TextureRect.new()
	wicon.texture = Art.tex(Art.COIN, 64)
	wicon.custom_minimum_size = Vector2(32, 32)
	wicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wrow.add_child(wicon)
	wallet_label = _label("0", 30, Color("#b07800"))
	wrow.add_child(wallet_label)
	wallet_card.add_child(wrow)
	menu.add_child(wallet_card)
	_pin(wallet_card, Control.PRESET_TOP_RIGHT, safe)
	wallet_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN # bigger numbers grow to the left
	# Your level (tap it for your profile)
	var badge := Button.new()
	badge.focus_mode = Control.FOCUS_NONE
	var bs := _style(Color(1, 1, 1, 0.92), 26)
	bs.shadow_color = Color(0.08, 0.1, 0.2, 0.18)
	bs.shadow_size = 12
	bs.shadow_offset = Vector2(0, 5)
	for k in ["normal", "hover", "pressed"]:
		badge.add_theme_stylebox_override(k, bs)
	badge.pressed.connect(func():
		sfx.play("tap")
		profile_screen.open())
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_theme_constant_override("separation", 6)
	bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bv.offset_left = 20
	bv.offset_right = -20
	bv.offset_top = 10
	bv.offset_bottom = -12
	badge.add_child(bv)
	level_label = _label("Level 1", 26, Color("#6a57b8"))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_label.clip_text = true
	bv.add_child(level_label)
	level_bar = Control.new()
	level_bar.custom_minimum_size = Vector2(0, 12)
	level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_bar.draw.connect(func():
		var f: float = level_bar.get_meta("fill", 0.0)
		level_bar.draw_rect(Rect2(Vector2.ZERO, level_bar.size), Color(0.12, 0.15, 0.27, 0.12))
		level_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(level_bar.size.x * f, level_bar.size.y)), Color("#8d7bd6")))
	bv.add_child(level_bar)
	badge.custom_minimum_size = Vector2(250, 84)
	menu.add_child(badge)
	_pin(badge, Control.PRESET_TOP_LEFT, safe)
	var col := _center_column(menu)
	# The title: every letter a player colour, bobbing gently
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 2)
	var word := "COLOR CLAIM"
	var title_size := int(clampf(get_viewport_rect().size.x / 7.6, 60, 110))
	for i in word.length():
		var ch := word[i]
		var l := _label(ch, title_size, world.COLORS[i % world.COLORS.size()] if ch != " " else Color.WHITE, 22, NAVY)
		l.custom_minimum_size.x = 26 if ch == " " else 0
		title.add_child(l)
		if ch != " ":
			var tw := l.create_tween().set_loops()
			tw.tween_interval(i * 0.08)
			tw.tween_property(l, "position:y", -10.0, 0.6).set_trans(Tween.TRANS_SINE)
			tw.tween_property(l, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	col.add_child(title)
	var tag := _label("Loop back to your land to claim it. Cut other trails, and protect yours!", 26, Color(1, 1, 1, 0.92), 0, INK, font_med)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 560
	col.add_child(tag)
	col.add_child(Control.new())
	var pick := _label("YOUR COLOUR", 22, Color(1, 1, 1, 0.75))
	col.add_child(pick)
	swatches = HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 12)
	col.add_child(swatches)
	for i in world.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			my_color = i
			_save()
			sfx.play("tap")
			_refresh_menu())
		swatches.add_child(b)
	col.add_child(_label("MODE", 22, Color(1, 1, 1, 0.75)))
	modes_row = HFlowContainer.new()
	modes_row.alignment = FlowContainer.ALIGNMENT_CENTER
	modes_row.add_theme_constant_override("h_separation", 8)
	modes_row.add_theme_constant_override("v_separation", 8)
	modes_row.custom_minimum_size.x = 600
	col.add_child(modes_row)
	for id in world.MODES:
		if world.MODES[id].get("hidden", false):
			continue
		var b := Button.new()
		b.text = world.MODES[id].name
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(func():
			mode_id = id
			_save()
			sfx.play("tap")
			_refresh_menu())
		modes_row.add_child(b)
	mode_desc = _label("", 22, Color(1, 1, 1, 0.85), 0, INK, font_med)
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.custom_minimum_size.x = 600
	col.add_child(mode_desc)
	col.add_child(_label("MAP", 22, Color(1, 1, 1, 0.75)))
	maps_row = HBoxContainer.new()
	maps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	maps_row.add_theme_constant_override("separation", 8)
	col.add_child(maps_row)
	for id in world.MAPS:
		var mb := Button.new()
		mb.text = world.MAPS[id]
		mb.focus_mode = Control.FOCUS_NONE
		mb.add_theme_font_override("font", font)
		mb.add_theme_font_size_override("font_size", 22)
		mb.pressed.connect(func():
			map_id = id
			_save()
			sfx.play("tap")
			_start_demo())
		maps_row.add_child(mb)
	col.add_child(_label("BOTS", 22, Color(1, 1, 1, 0.75)))
	diff_row = HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	col.add_child(diff_row)
	for id in world.DIFFICULTY:
		var db := Button.new()
		db.text = world.DIFFICULTY[id].name
		db.set_meta("id", id)
		db.focus_mode = Control.FOCUS_NONE
		db.add_theme_font_override("font", font)
		db.add_theme_font_size_override("font_size", 22)
		db.pressed.connect(func():
			difficulty = id
			_save()
			sfx.play("tap")
			_refresh_menu())
		diff_row.add_child(db)
	col.add_child(Control.new())
	var play := _button("PLAY", YELLOW, Color("#5a3200"), Color("#d27a06"), 64)
	play.custom_minimum_size = Vector2(380, 120)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(start_game)
	col.add_child(play)
	var pulse := play.create_tween().set_loops()
	play.pivot_offset = Vector2(190, 60)
	pulse.tween_property(play, "scale", Vector2(1.04, 1.04), 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(play, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	best_label = _label("", 26, Color(1, 1, 1, 0.85), 0, INK, font_med)
	col.add_child(best_label)
	# The dock: Shop, Missions, Profile and Settings
	var dock := HBoxContainer.new()
	dock.alignment = BoxContainer.ALIGNMENT_CENTER
	dock.add_theme_constant_override("separation", 12)
	menu.add_child(dock)
	var items := [["Shop", Art.BAG, Color("#4ed8a0"), func(): shop.open()],
		["Missions", Art.TARGET, Color("#ff8a5c"), func(): missions_screen.open()],
		["Profile", Art.PERSON, Color("#8d7bd6"), func(): profile_screen.open()],
		["Settings", Art.GEAR, Color("#7f8aa6"), func(): settings_screen.open()]]
	for it in items:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 112)
		var c: Color = it[2]
		b.add_theme_stylebox_override("normal", _style(c, 26, 8, c.darkened(0.25)))
		b.add_theme_stylebox_override("hover", _style(c.lightened(0.06), 26, 8, c.darkened(0.25)))
		b.add_theme_stylebox_override("pressed", _style(c.darkened(0.05), 26, 3, c.darkened(0.25)))
		var open: Callable = it[3]
		b.pressed.connect(func():
			sfx.play("tap")
			open.call())
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_bottom = -6
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		b.add_child(v)
		var ic := _icon(it[1], 44, Color.WHITE)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		v.add_child(_label(it[0], 24, Color.WHITE, 6, c.darkened(0.35)))
		if it[0] == "Missions":
			# How many of today's missions are done
			missions_badge = _label("", 20, Color.WHITE)
			var bp := PanelContainer.new()
			var bst := _style(Color("#ff3c50"), 14)
			bst.content_margin_left = 8
			bst.content_margin_right = 8
			bst.content_margin_top = 0
			bst.content_margin_bottom = 2
			bp.add_theme_stylebox_override("panel", bst)
			bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bp.add_child(missions_badge)
			bp.position = Vector2(104, -10)
			b.add_child(bp)
		dock.add_child(b)
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.offset_top -= safe.w + 8
	dock.offset_bottom -= safe.w + 8


func _refresh_menu() -> void:
	for i in swatches.get_child_count():
		var b: Button = swatches.get_child(i)
		var s := StyleBoxFlat.new()
		s.bg_color = world.COLORS[i]
		s.set_corner_radius_all(14)
		s.anti_aliasing = true
		if i == my_color:
			s.set_border_width_all(5)
			s.border_color = Color.WHITE
		else:
			s.border_width_bottom = 5
			s.border_color = world.COLORS[i].darkened(0.3)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, s)
	var b: float = bests.get("daily-" + world.today() if mode_id == "daily" else mode_id, 0.0)
	best_label.text = ("Best: %.1f%%   ·   Wins: %d" % [b, wins]) if games > 0 else "Pick a mode and a map, then play!"
	if difficulty != "normal":
		best_label.text += "   ·   Coins x%s" % str(world.DIFFICULTY[difficulty].coins)
	mode_desc.text = world.MODES[mode_id].desc
	if mode_id == "daily":
		var h: int = absi(world.today().hash())
		mode_desc.text += "  ·  Today's map: %s" % world.MAPS.values()[h % world.MAPS.size()]
	for mb in modes_row.get_children():
		var on: bool = mb.text == world.MODES[mode_id].name
		var st := _style(YELLOW if on else Color(1, 1, 1, 0.16), 18)
		st.content_margin_left = 18
		st.content_margin_right = 18
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		for k in ["normal", "hover", "pressed"]:
			mb.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			mb.add_theme_color_override(k, Color("#5a3200") if on else Color.WHITE)
	wallet_label.text = str(wallet)
	level_label.text = "Level %d  ·  %s" % [prog.level, player_name]
	level_bar.set_meta("fill", float(prog.xp) / Progress.need(prog.level))
	level_bar.queue_redraw()
	prog.ensure_day(world.today())
	var done := prog.missions.filter(func(m): return m.done).size()
	missions_badge.text = "%d/3" % done
	missions_badge.get_parent().visible = done < 3
	for db in diff_row.get_children():
		var on: bool = db.get_meta("id") == difficulty
		var st := _style(Color.WHITE if on else Color(1, 1, 1, 0.16), 18)
		st.content_margin_left = 18
		st.content_margin_right = 18
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		for k in ["normal", "hover", "pressed"]:
			db.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			db.add_theme_color_override(k, INK if on else Color.WHITE)
	for mb in maps_row.get_children():
		mb.disabled = mode_id == "daily"
		var picked: bool = mb.text == world.MAPS[map_id] and mode_id != "daily"
		var st := _style(Color.WHITE if picked else Color(1, 1, 1, 0.16), 18)
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		for k in ["normal", "hover", "pressed"]:
			mb.add_theme_stylebox_override(k, st)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			mb.add_theme_color_override(k, INK if picked else Color.WHITE)


func _build_pause() -> void:
	pause_screen = _screen()
	_dim(pause_screen, Color(0.11, 0.14, 0.26, 0.55), Color(0.11, 0.14, 0.26, 0.8))
	var col := _center_column(pause_screen)
	col.add_child(_label("Paused", 72, Color.WHITE, 16, NAVY))
	var resume := _button("Resume", YELLOW, Color("#5a3200"), Color("#d27a06"), 44)
	resume.custom_minimum_size = Vector2(340, 100)
	resume.pressed.connect(_resume)
	col.add_child(resume)
	var quit := _button("Quit to menu", Color(1, 1, 1, 0.92), INK, Color("#c7cfe0"), 32)
	quit.custom_minimum_size = Vector2(340, 84)
	quit.pressed.connect(_to_menu)
	col.add_child(quit)


func _build_over() -> void:
	over_screen = _screen()
	_dim(over_screen, Color(0.11, 0.14, 0.26, 0.45), Color(0.11, 0.14, 0.26, 0.85))
	var col := _center_column(over_screen)
	over_title = _label("", 86, Color.WHITE, 18, NAVY)
	col.add_child(over_title)
	over_reason = _label("", 30, Color.WHITE, 0, INK, font_med)
	over_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_reason.custom_minimum_size.x = 600
	col.add_child(over_reason)
	over_stats = _label("", 26, Color(1, 1, 1, 0.85), 0, INK, font_med)
	col.add_child(over_stats)
	over_best = _label("", 30, YELLOW)
	col.add_child(over_best)
	over_coins = _label("", 34, Color("#ffd23f"), 10, Color("#6b4a00"))
	col.add_child(over_coins)
	over_xp = _label("", 26, Color("#d8cfff"))
	col.add_child(over_xp)
	over_xp_bar = Control.new()
	over_xp_bar.custom_minimum_size = Vector2(380, 16)
	over_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	over_xp_bar.draw.connect(func():
		var f: float = clampf(over_xp_bar.get_meta("fill", 0.0), 0, 1)
		over_xp_bar.draw_rect(Rect2(Vector2.ZERO, over_xp_bar.size), Color(1, 1, 1, 0.15))
		over_xp_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(over_xp_bar.size.x * f, over_xp_bar.size.y)), Color("#a996ff")))
	col.add_child(over_xp_bar)
	over_rewards = VBoxContainer.new()
	over_rewards.add_theme_constant_override("separation", 8)
	col.add_child(over_rewards)
	col.add_child(Control.new())
	var again := _button("Play again", YELLOW, Color("#5a3200"), Color("#d27a06"), 46)
	again.custom_minimum_size = Vector2(380, 104)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func(): start_game())
	col.add_child(again)
	again_btn = again
	var menu_btn := _button("Menu", Color(1, 1, 1, 0.92), INK, Color("#c7cfe0"), 32)
	menu_btn.custom_minimum_size = Vector2(380, 84)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_btn.pressed.connect(_to_menu)
	col.add_child(menu_btn)


## Space taken by notches and rounded corners, in UI units: (left, top, right, bottom)
func _safe_margins() -> Vector4:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	# Only phones and tablets have notches (and there the game fills the screen)
	if not OS.has_feature("mobile") or win.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var k := get_viewport_rect().size.x / win.x
	return Vector4(maxf(0, safe.position.x) * k, maxf(0, safe.position.y) * k, maxf(0, win.x - safe.end.x) * k, maxf(0, win.y - safe.end.y) * k)


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ---------- Saving ----------

func _load() -> void:
	Gfx.level = Gfx.default_level() # until the save says otherwise
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	bests = c.get_value("stats", "bests", {"classic": c.get_value("stats", "best", 0.0)})
	mode_id = c.get_value("player", "mode", "classic")
	games = c.get_value("stats", "games", 0)
	wins = c.get_value("stats", "wins", 0)
	my_color = clampi(c.get_value("player", "color", 0), 0, 7)
	wallet = c.get_value("player", "coins", 0)
	map_id = c.get_value("player", "map", "square")
	for kind in owned:
		var have: Array = c.get_value("shop", "owned_" + kind, owned[kind])
		var free: String = Cosmetics.KINDS[kind].free
		owned[kind] = []
		for id in have:
			if Cosmetics.items(kind).has(id) and not owned[kind].has(id):
				owned[kind].append(id)
		if not owned[kind].has(free):
			owned[kind].insert(0, free)
		var on: String = c.get_value("shop", "using_" + kind, free)
		equipped[kind] = on if owned[kind].has(on) else free
	if c.has_section_key("progress", "data"):
		prog.from_dict(c.get_value("progress", "data", {}))
	else:
		# Saves from before levels and stats: carry over what we know
		prog.stats.games = games
		prog.stats.wins = wins
		for k in bests:
			prog.stats.best_pct = maxf(prog.stats.best_pct, bests[k])
		prog.tutorial_done = games > 0
	difficulty = c.get_value("player", "difficulty", "normal")
	if not world_difficulties().has(difficulty):
		difficulty = "normal"
	player_name = c.get_value("player", "name", "You")
	vibration = c.get_value("settings", "vibration", true)
	Gfx.level = clampi(c.get_value("settings", "gfx", Gfx.default_level()), 0, Gfx.LEVELS.size() - 1)
	Gfx.fps = c.get_value("settings", "fps", 60)
	if not Gfx.FPS.has(Gfx.fps):
		Gfx.fps = 60
	Gfx.show_fps = c.get_value("settings", "show_fps", false)
	big_stick = c.get_value("settings", "big_stick", false)
	set_meta("music", c.get_value("settings", "music", true))
	set_meta("muted", c.get_value("settings", "muted", false))


static func world_difficulties() -> Array:
	return ["easy", "normal", "hard"]


func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("stats", "bests", bests)
	c.set_value("player", "mode", mode_id)
	c.set_value("stats", "games", games)
	c.set_value("stats", "wins", wins)
	c.set_value("player", "color", my_color)
	c.set_value("player", "coins", wallet)
	c.set_value("player", "map", map_id)
	for kind in owned:
		c.set_value("shop", "owned_" + kind, owned[kind])
		c.set_value("shop", "using_" + kind, equipped[kind])
	c.set_value("progress", "data", prog.to_dict())
	c.set_value("player", "difficulty", difficulty)
	c.set_value("player", "name", player_name)
	c.set_value("settings", "vibration", vibration)
	c.set_value("settings", "gfx", Gfx.level)
	c.set_value("settings", "fps", Gfx.fps)
	c.set_value("settings", "show_fps", Gfx.show_fps)
	c.set_value("settings", "big_stick", big_stick)
	c.set_value("settings", "music", music.enabled)
	c.set_value("settings", "muted", sfx.muted)
	c.save(SAVE_PATH)
