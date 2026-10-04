class_name Story
extends RefCounted
## The campaign's story, told in cut scenes (cutscene.gd plays them):
##  - the opening at level 1, and a scene for each new land (desert at 6, snow at 11, beach at
##    16, then the second campaign at 21), new tricks (upgrades at 8), and the yellow and green
##    armies' leaders arriving (12, 25), each played once
##  - every boss level: General Grumble taunts you from his castle, and when it falls he runs
##  - every level: a quick fly over the map with its name, then GO!
##  - every win: your soldiers celebrate under fireworks; every loss: Grumble laughs
##  - after level 60: the ending

const LANDS := {"grass": "Green Valley", "desert": "Sunny Desert", "snow": "Frosty Peaks", "beach": "Palm Beach"}
const BOSS_TAUNTS := [
	"Welcome to my castle! Its walls have never fallen, and they never will!",
	"Back for more? My new castle is even tougher!",
	"I've added more cannons. Lots more cannons!",
	"My finest castle yet! You'll never take it!",
	"This castle is made of pure stubbornness!",
	"My last and greatest castle! If it falls... I give up!",
	"Endless castles! Endless Grumble! Bwahaha!",
]
const BOSS_DEFEATS := [
	"My castle! Grr... You haven't seen the last of me!",
	"Not again! Retreat! RETREAT!",
	"My cannons! My beautiful cannons!",
	"This isn't over, Commander! I'll be back!",
	"Stubbornness... not... enough...",
	"",
	"I'll build another one! And another!",
]

var main
var c: Cutscene


func _init(m, cut: Cutscene) -> void:
	main = m
	c = cut


static func land(n: int) -> String:
	return LANDS[Levels.theme_for(n)]


# ---------- Places on the field ----------
func _base(side: int):
	var best = null
	for t in main.battle.towers:
		if t.owner == side and (best == null or t.units > best.units):
			best = t
	return best


func _enemy_base():
	for side in [2, 3, 4]:
		var t = _base(side)
		if t != null:
			return t
	return null


## Which way the middle of the field is from z (+1 = further down the screen)
func _inward(z: float) -> float:
	return 1.0 if z <= main.world.fh / 2 else -1.0


## The most open spot on the field (furthest from any building or wall), nearest the middle
func _clear_spot() -> Vector2:
	var w = main.world
	var best := Vector2(w.fw / 2, w.fh / 2)
	var best_score := -INF
	for gx in range(120, int(w.fw) - 119, 40):
		for gy in range(160, int(w.fh) - 159, 40):
			var room := INF
			for t in main.battle.towers:
				room = minf(room, Battle.dist(gx, gy, t.x, t.y) - t.radius())
			for rk in main.battle.rocks:
				room = minf(room, Battle.dist(gx, gy, rk.x, rk.y) - rk.r)
			var score := minf(room, 260.0) - Vector2(gx, gy).distance_to(Vector2(w.fw / 2, w.fh / 2)) * 0.15
			if score > best_score:
				best_score = score
				best = Vector2(gx, gy)
	return best


## Where a character stands: beside a building, on the side towards the middle of the field
## (the edges of the field are full of trees and rocks that would hide them)
func _beside(t, right := true) -> Vector2:
	return Vector2(t.x + (t.radius() + 34) * (1.0 if right else -1.0), t.y + 46 * _inward(t.y))


## A camera looking at a building (or a point)
func _look(r: Cutscene.Run, t, dist := 470.0, pitch := 0.48, yaw := 0.0) -> Transform3D:
	return r.shot(Vector3(t.x, 55, t.y), dist, pitch, yaw)


## The whole field, from a little further back than the battle camera
func _wide(r: Cutscene.Run) -> Transform3D:
	var xf: Transform3D = main.world.cam_base
	xf.origin += xf.basis.z * 500.0
	return xf


## A camera on a character standing at p: from the middle of the field, a little to the side,
## the character above the dialog box with their building beside them
func _on_char(r: Cutscene.Run, p: Vector2, right := true, dist := 580.0, pitch := 0.42, high := 24.0) -> Transform3D:
	var s := 1.0 if right else -1.0
	var yaw := 0.32 * s if _inward(p.y) > 0 else PI - 0.32 * s
	return r.shot(Vector3(p.x - 20 * s, high, p.y), dist, pitch, yaw)


## Bring a character on beside a building, with the camera on them
func _enter(r: Cutscene.Run, id: String, t, right := true, _yaw := 0.3, secs := 1.1) -> void:
	if t == null:
		return
	var p := _beside(t, right)
	var xf := _on_char(r, p, right)
	await r.cam_move(xf, secs)
	r.spawn(id, p.x, p.y, xf.origin)
	if c.actors.has(id):
		c.actors[id].set_meta("right", right)
	await r.wait(0.35)


## Turn the camera to a character already on the field
func _to_char(r: Cutscene.Run, id: String, secs := 0.7, pitch := 0.42) -> void:
	var a = c.actors.get(id)
	if a == null:
		return
	var p := Vector2(a.position.x, a.position.z)
	await r.cam_move(_on_char(r, p, a.get_meta("right", true), 560.0, pitch), secs)


# ---------- Before a level ----------
## Everything before a level starts: its story scene (once), the boss's taunt, then the fly-in
func level_start(r: Cutscene.Run, n: int, title: String) -> void:
	var told := false
	if main.save.cutscenes and n > 0:
		var key := "story_%d" % n
		if not main.save.seen.has(key) and n in [1, 6, 8, 11, 12, 16, 21, 25, 31, 41, 51]:
			main.save.seen[key] = true
			main.write_save()
			await beat(r, n)
			told = true
		if Levels.is_boss(n) and not r.done():
			await boss_intro(r, n)
			told = true
	if r.done():
		return
	r.short = true
	if told:
		# The story already showed the field: just fly back and go
		await r.fly_home(0.8)
		_go(r)
		await r.wait(0.35)
	else:
		await level_intro(r, title, land(n) if n > 0 else "")


## The quick fly-in: from the enemy's base over yours to the battle camera
func level_intro(r: Cutscene.Run, title: String, sub: String) -> void:
	var me = _base(1)
	var foe = _enemy_base()
	r.cam_cut(_look(r, foe if foe != null else me, 560.0, 0.62, -0.3))
	r.banner(title, I18n.t(sub) if sub != "" else "", UI.ORANGE, 1.2)
	r.sfx("whoosh")
	if me != null:
		await r.cam_move(_look(r, me, 600.0, 0.72, 0.25), 1.05)
	await r.fly_home(0.75)
	_go(r)
	await r.wait(0.3)


func _go(r: Cutscene.Run) -> void:
	r.banner("GO!", "", UI.GREEN, 0.45)
	r.sfx("go")


## The story scenes, each played the first time its level starts
func beat(r: Cutscene.Run, n: int) -> void:
	var me = _base(1)
	var foe = _base(2)
	match n:
		1:
			await intro(r)
		6, 11, 16, 21:
			r.fade_from_black(0.6)
			r.cam_cut(_wide(r))
			r.banner(land(n), I18n.t("Chapter %d") % ((n - 1) / 5 + 1), UI.GREEN, 1.6)
			await r.wait(1.0)
			if n == 21:
				await _enter(r, "grumble", foe, false)
				r.act("grumble", "laugh")
				r.sfx("roar")
				await r.say("grumble", "Did you miss me? I've rebuilt my army, and it's BIGGER!")
				await _enter(r, "skye", me, true, 0.3, 0.9)
				r.act("skye", "point")
				await r.say("skye", "Bigger, maybe. Smarter? Let's find out!")
			else:
				await _enter(r, "skye", me)
				r.act("skye", "wave")
				match n:
					6:
						await r.say("skye", "Grumble ran off into the Sunny Desert! After him!")
						r.act("skye", "point")
						await r.say("skye", "Walls of crates block roads here. Find a way around them!")
					11:
						await r.say("skye", "Brrr! Frosty Peaks. Grumble's soldiers are hiding in the snow.")
						r.act("skye", "point")
						await r.say("skye", "Watchtowers shoot anything inside their circle. Attack them with one big wave!")
					16:
						await r.say("skye", "Palm Beach! Sand, sun... and Red soldiers everywhere.")
						r.act("skye", "point")
						await r.say("skye", "Grumble's toughest castle is near. Let's push him into the sea!")
			r.act("skye", "cheer")
			await r.wait(0.5)
		8:
			await _enter(r, "skye", me)
			r.act("skye", "wave")
			await r.say("skye", "New trick, Commander! Tap one of your buildings, then the up arrow.")
			r.act("skye", "point")
			await r.say("skye", "It costs a few soldiers, but the building trains faster. Two upgrades each!")
			r.act("skye", "cheer")
			await r.wait(0.4)
		12:
			await _enter(r, "mustard", _base(3), false)
			r.act("mustard", "laugh")
			await r.say("mustard", "Ahem! Duke Mustard, at your service... NOT! This land shall be YELLOW!")
			await _enter(r, "skye", me, true, 0.3, 0.9)
			r.act("skye", "point")
			await r.say("skye", "A third army! Let the Duke and Grumble fight each other, then strike!")
		25:
			await _enter(r, "moss", _base(4), false)
			r.act("moss", "wave")
			await r.say("moss", "Major Moss reporting! The Green Forest Army wants this land too!")
			await _enter(r, "skye", me, true, 0.3, 0.9)
			r.act("skye", "cheer")
			await r.say("skye", "Four armies on one map? Commander, this is going to be fun!")
		31:
			await _enter(r, "skye", me)
			r.act("skye", "point")
			await r.say("skye", "Halfway there! The armies are getting tougher, so spend your coins on upgrades.")
		41:
			await _enter(r, "grumble", foe, false)
			r.act("grumble", "angry")
			await r.say("grumble", "You again?! My generals say you're unstoppable. Prove it!")
		51:
			await _enter(r, "skye", me)
			r.act("skye", "wave")
			await r.say("skye", "The final stretch! Grumble's last castle waits at level 60.")


## The opening: the valley, Captain Skye, General Grumble
func intro(r: Cutscene.Run) -> void:
	var me = _base(1)
	var foe = _base(2)
	r.short = false
	r.fade_from_black(1.2)
	r.cam_cut(_wide(r))
	r.banner(land(1), I18n.t("Chapter %d") % 1, UI.GREEN, 1.8)
	await r.wait(1.4)
	await _enter(r, "skye", me, true, 0.3, 1.6)
	r.act("skye", "wave")
	await r.say("skye", "Commander! I'm Captain Skye. Welcome to Green Valley!")
	r.act("skye", "idle")
	await r.say("skye", "General Grumble's Red Army wants every tower in the land. We have to stop him!")
	await _enter(r, "grumble", foe, false, 0.3, 1.3)
	r.act("grumble", "laugh")
	r.sfx("roar")
	await r.say("grumble", "Bwahaha! Soon every flag in the valley will be RED!")
	r.act("grumble", "angry")
	await r.say("grumble", "Nobody stands up to General Grumble!")
	await _to_char(r, "skye", 1.0)
	r.act("skye", "point")
	await r.say("skye", "Let's show him how Blue fights. Drag a road from our tower to the gray one!")
	r.act("skye", "cheer")
	await r.wait(0.6)


## A boss level: Grumble taunts you from his castle
func boss_intro(r: Cutscene.Run, n: int) -> void:
	var castle = null
	for t in main.battle.towers:
		if t.type == "castle":
			castle = t
	if castle == null:
		return
	r.short = false
	r.cam_cut(r.shot(Vector3(castle.x, 60, castle.y), 900, 1.0, -0.2))
	r.sfx("drum")
	r.banner("BOSS BATTLE!", I18n.t("Level %d") % n, UI.RED, 1.6)
	await r.cam_move(_look(r, castle, 700.0, 0.45, -0.2), 1.3)
	await r.wait(0.3)
	await _enter(r, "grumble", castle, false, 0.3, 0.8)
	r.act("grumble", "laugh")
	r.sfx("roar")
	await r.say("grumble", BOSS_TAUNTS[mini(n / 10 - 1, BOSS_TAUNTS.size() - 1)])
	r.act("grumble", "angry")
	if n == 10:
		await _enter(r, "skye", _base(1), true, 0.3, 1.0)
		r.act("skye", "point")
		await r.say("skye", "That castle is tough and it shoots. Attack it from several buildings at once!")


# ---------- After a level ----------
## Your soldiers celebrate under fireworks (after Grumble runs from a fallen castle)
func victory(r: Cutscene.Run, n: int) -> void:
	main.battle.units.clear()
	var me = _base(1)
	if me == null:
		return
	if Levels.is_boss(n) and main.save.cutscenes and not main.daily and n != Levels.MAX_LEVEL:
		await _boss_down(r, n)
	if r.dead:
		return
	r.short = true
	# From the field, looking back at your base and the crowd around it
	var xf := _look(r, me, 780.0, 0.5, PI - 0.25 if _inward(me.y) < 0 else 0.25)
	r.sfx("fanfare")
	r.banner("VICTORY!", "", UI.ORANGE, 1.9)
	r.crowd(me, 12)
	r.cam_move(xf, 1.2)
	await r.fireworks(me.x, me.y, 7, 2.3)
	if n == Levels.MAX_LEVEL and main.save.cutscenes and not main.save.seen.has("ending") and not r.dead:
		main.save.seen["ending"] = true
		main.write_save()
		r.skipping = false
		await ending(r)


func _boss_down(r: Cutscene.Run, n: int) -> void:
	var castle = null
	for t in main.battle.towers:
		if t.type == "castle":
			castle = t
	if castle == null:
		return
	r.short = false
	await _enter(r, "grumble", castle, false, 0.3, 1.0)
	r.act("grumble", "angry")
	var line: String = BOSS_DEFEATS[mini(n / 10 - 1, BOSS_DEFEATS.size() - 1)]
	if line != "":
		await r.say("grumble", line)
	# He runs off the field, away from the camera
	r.flee("grumble", Vector3(-0.4, 0, -1).normalized() * 210)
	r.sfx("boing")
	await r.wait(1.3)


## Grumble laughs as your last building falls
func defeat(r: Cutscene.Run) -> void:
	r.short = true
	r.tint(0.38, 0.8)
	r.banner("DEFEAT", "", Color("#9a8cff"), 1.6)
	var foe = _enemy_base()
	if foe != null and main.save.cutscenes and foe.owner == 2:
		var p := _beside(foe, false)
		# Further back and from higher up, so the banner stays clear of his face
		var xf := _on_char(r, p, false, 760.0, 0.6, 70.0)
		r.cam_move(xf, 1.0)
		await r.wait(0.5)
		r.spawn("grumble", p.x, p.y, xf.origin)
		r.act("grumble", "laugh")
		r.sfx("roar")
		await r.wait(1.4)
	else:
		await r.cam_move(_wide(r), 1.8)


## After level 60: everyone gives up, and the endless levels begin
func ending(r: Cutscene.Run) -> void:
	r.short = false
	var spot := _clear_spot()
	var mid := Vector3(spot.x, 0, spot.y)
	var xf := r.shot(mid, 1000.0, 0.42)
	await r.cam_move(xf, 1.2)
	var spots := {"grumble": Vector2(-120, 0), "mustard": Vector2(-40, 40), "moss": Vector2(40, 40), "skye": Vector2(120, 0)}
	for id in spots:
		r.spawn(id, mid.x + spots[id].x, mid.z + spots[id].y, xf.origin)
		c.actors[id].set_meta("right", spots[id].x > 0)
		await r.wait(0.2)
	await _to_char(r, "grumble", 0.7, 0.72)
	r.act("grumble", "shock")
	await r.say("grumble", "Alright, alright! I give up! The towers are yours, Commander.")
	await _to_char(r, "mustard", 0.7, 0.72)
	r.act("mustard", "shock")
	await r.say("mustard", "Yellow... retreats. With dignity!")
	await _to_char(r, "moss", 0.7, 0.72)
	r.act("moss", "wave")
	await r.say("moss", "Good game, Blue! Rematch next spring?")
	await _to_char(r, "skye", 0.7, 0.72)
	r.act("skye", "cheer")
	await r.say("skye", "We did it, Commander! The whole land is free!")
	r.act("skye", "point")
	await r.say("skye", "But scouts say endless armies are marching beyond the hills...")
	r.act("grumble", "cheer")
	r.act("mustard", "cheer")
	r.act("moss", "cheer")
	r.cam_move(xf, 1.0)
	r.banner("THE END?", "Endless levels unlocked!", UI.ORANGE, 2.5)
	await r.fireworks(mid.x, mid.z, 8, 2.6)
