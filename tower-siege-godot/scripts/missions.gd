class_name Missions
extends RefCounted
## The campaign as a story: chapters of five missions, one land each, the fifth always a boss
## fight at General Grumble's castle. The maps come from levels.gd (the same as the web
## version's); a mission adds a goal on top of its map:
##   conquer  take every enemy building
##   defend   hold your headquarters until help arrives (the enemy goes for it)
##   capture  take the radar stations (marked on the map) and hold them all at once
##   puzzle   no reinforcements: nobody trains soldiers, so make every one count
##   blitz    take every enemy building before the clock runs out
##   hq       the boss fight: take Grumble's castle and his army runs

const GOALS := {
	"conquer": {"icon": "⚔", "name": "Conquer", "color": "blue"},
	"defend": {"icon": "🛡", "name": "Defend the HQ", "color": "green"},
	"capture": {"icon": "📡", "name": "Capture the radars", "color": "orange"},
	"puzzle": {"icon": "🧩", "name": "No reinforcements", "color": "purple"},
	"blitz": {"icon": "⏱", "name": "Blitz", "color": "yellow"},
	"hq": {"icon": "🎯", "name": "Boss: take the castle", "color": "red"},
}
## What Captain Skye says before the mission (%s is the land); two of each, taken in turn
const BRIEFS := {
	"conquer": [
		"Grumble's army has dug in all over %s. Take every enemy building!",
		"Red flags everywhere in %s! Take every building and send Grumble's soldiers home.",
	],
	"defend": [
		"Grumble is attacking our headquarters in %s! Hold it for %d seconds until help arrives.",
		"Our headquarters in %s is surrounded! Keep it blue for %d seconds and help will come.",
	],
	"capture": [
		"Grumble wants the %d radar stations in %s. Take them all and hold them at the same time!",
		"Whoever holds the %d radar stations in %s sees everything. Hold them all at once!",
	],
	"puzzle": [
		"Our supply lines in %s are cut, and so are Grumble's: nobody trains soldiers. Make every soldier count!",
		"A storm stops all training in %s. Win with the soldiers you have, and don't waste any!",
	],
	"blitz": [
		"Grumble's reinforcements reach %s in %d seconds. Take every enemy building before they do!",
		"Quick, Commander! Take every building in %s in %d seconds, before Grumble wakes up!",
	],
	"hq": [
		"Grumble himself is in the castle in %s. Take it, and his army runs!",
	],
}
## The chapters: a title and what happens (one land each; the endless levels share the last)
const CHAPTERS := [
	["The Invasion", "Grumble's Red Army marches into Green Valley. Drive them out!"],
	["Desert Chase", "Grumble ran into the desert to build a new castle. After him!"],
	["Into the Snow", "Red soldiers hide in the snowy mountains, and Duke Mustard's Yellow army joins the fight."],
	["The Beach Castle", "Push Grumble back to the sea and take his toughest castle yet."],
	["Grumble Returns", "Grumble has rebuilt his army, and it's bigger. Then Major Moss arrives!"],
	["Four Armies", "Red, Yellow and Green all want the desert. Outsmart them all!"],
	["Halfway There", "The armies are getting tougher. Upgrade your buildings and keep going!"],
	["Storm on the Coast", "Grumble's castles line the beach. Break through!"],
	["The Generals", "Grumble's best generals take the field. Show them you're unstoppable!"],
	["Sandstorm", "Fight through the sandstorm to Grumble's desert fortress."],
	["The Final Stretch", "Only two castles left. Grumble is running out of places to hide!"],
	["Grumble's Last Stand", "Grumble's last and greatest castle. Take it and free the land!"],
	["Endless Armies", "More armies keep marching from beyond the hills. How far can you go?"],
]
const CODE_A := ["Iron", "Silver", "Golden", "Thunder", "Steel", "Swift", "Brave", "Night", "Storm", "Stone", "Fire", "Frost", "Sky"]
const CODE_B := ["Hawk", "Fist", "Hammer", "Arrow", "Shield", "Wolf", "Eagle", "Lion", "Bridge", "Spear", "Fox", "Bear"]
const PER_CHAPTER := 5
## The goals of a chapter's first four missions turn around from chapter to chapter
const ROTATION := ["conquer", "capture", "defend", "blitz", "puzzle"]


## The goal of campaign level n (0 = the daily challenge: conquer)
static func goal_for(n: int) -> String:
	if n <= 3:
		return "conquer"
	if Levels.is_boss(n):
		return "hq"
	var c := chapter_of(n)
	var pos := (n - 1) % PER_CHAPTER
	match c:
		1:
			return "defend"                                  # 4
		2:
			return ["capture", "puzzle", "conquer", "blitz"][pos]  # 6-9 (8 teaches upgrades)
	# A new army's first level is a plain fight (they fight each other too)
	if n == 12 or n == 26:
		return "conquer"
	return ROTATION[(pos + c * 2) % ROTATION.size()]


static func chapter_of(n: int) -> int:
	return (n - 1) / PER_CHAPTER + 1


static func chapter_title(c: int) -> String:
	return I18n.t(CHAPTERS[mini(c, CHAPTERS.size()) - 1][0])


static func chapter_story(c: int) -> String:
	return I18n.t(CHAPTERS[mini(c, CHAPTERS.size()) - 1][1])


## "Operation Iron Hawk": a code name of its own for every mission
static func title(n: int) -> String:
	var a: String = CODE_A[(n * 7) % CODE_A.size()]
	var b: String = CODE_B[(n * 5 + n / CODE_B.size()) % CODE_B.size()]
	return I18n.t("Operation %s") % (a + " " + b)


static func land(n: int) -> String:
	return I18n.t(Story.LANDS[Levels.theme_for(n)])


## How long you hold out in a defend mission
static func defend_time(n: int) -> float:
	return roundf(40.0 + minf(30.0, n * 0.6))


## A blitz's time limit: more buildings, more time
static func blitz_time(towers: int) -> float:
	return roundf(24.0 + towers * 5.0)


static func capture_count(towers: int) -> int:
	return 2 if towers < 8 else 3


## What Captain Skye says before mission n (on a map with `towers` buildings)
static func brief(n: int, towers := 9) -> String:
	var g := goal_for(n)
	var list: Array = BRIEFS[g]
	var text := I18n.t(list[n % list.size()])
	match g:
		"defend":
			return text % [land(n), int(defend_time(n))]
		"capture":
			return text % [capture_count(towers), land(n)]
		"blitz":
			return text % [land(n), int(blitz_time(towers))]
	return text % land(n)


static func goal_name(g: String) -> String:
	return I18n.t(GOALS[g].name)


static func icon(g: String) -> String:
	return GOALS[g].icon


## The battle's goal as it's played: which buildings matter, and the clock. Called once the
## level's battle and its enemy armies are loaded; changes the battle to suit the goal.
static func setup(n: int, battle: Battle, goal := "") -> Dictionary:
	var g := goal if goal != "" else goal_for(n)
	var m := {"goal": g, "n": n, "hq": null, "targets": [], "time": 0.0, "start": 0.0}
	var mine := battle.towers.filter(func(t): return t.owner == Battle.PLAYER)
	var others := battle.towers.filter(func(t): return t.owner != Battle.PLAYER)
	match g:
		"defend":
			# Your headquarters: your biggest building, nearest the bottom of the map
			mine.sort_custom(func(a, b): return a.units > b.units or (a.units == b.units and a.by > b.by))
			if not mine.is_empty():
				m.hq = mine[0]
				m.hq.units += 10
			m.time = defend_time(n)
			# Grumble's army goes for it, with more soldiers than usual (other armies just fight)
			for a in battle.ai_sides:
				if a.side != 2:
					continue
				a.cfg = a.cfg.duplicate()
				a.cfg.bold = maxf(float(a.cfg.bold), 0.6)
				a.cfg.focus = m.hq.id if m.hq != null else -1
				a.cfg.focus_bonus = 1.2
				a.cfg.think = float(a.cfg.think) * 0.85
			for t in others:
				if t.owner == 2:
					t.units = roundf(t.units * 1.2)
		"capture":
			# Radar stations: gray buildings spread from near your base to far away (an enemy's
			# home base never, or taking it would end the battle anyway)
			var base = mine[0] if not mine.is_empty() else null
			var pool := others.filter(func(t): return t.owner == Battle.NEUTRAL)
			if base != null:
				pool.sort_custom(func(a, b): return Battle.dist(a.x, a.y, base.x, base.y) < Battle.dist(b.x, b.y, base.x, base.y))
			var k := mini(capture_count(battle.towers.size()), pool.size())
			for i in k:
				var idx := clampi(int(round((i + 0.5) * pool.size() / float(k) - 0.5)), 0, pool.size() - 1)
				while pool[idx] in m.targets:
					idx = (idx + 1) % pool.size()
				m.targets.append(pool[idx])
		"puzzle":
			# Nobody trains. You get a few more soldiers than it takes to beat everyone,
			# so you can't waste many.
			battle.frozen = true
			var need := 0.0
			for t in others:
				need += t.units * float(Battle.TYPES[t.type].defense) + 1
			var total := ceilf(need * 1.2 + 6)
			var share := 0.0
			for t in mine:
				share += t.units
			for t in mine:
				t.units = ceilf(total * t.units / maxf(1.0, share))
			m.start = total
		"blitz":
			m.time = blitz_time(battle.towers.size())
		"hq":
			var hq = null
			for t in others:
				if t.type == "castle" and (hq == null or t.owner == 2):
					hq = t
			if hq == null:
				var enemy := others.filter(func(t): return t.owner != Battle.NEUTRAL)
				enemy.sort_custom(func(a, b): return a.units > b.units)
				hq = enemy[0] if not enemy.is_empty() else null
			m.hq = hq
			# Grumble stays home to guard his castle, and Skye sends you reinforcements
			for a in battle.ai_sides:
				if a.side == 2:
					a.cfg = a.cfg.duplicate()
					a.cfg.bold = 0.0
					a.cfg.margin = float(a.cfg.margin) + 4
					a.cfg.think = float(a.cfg.think) * 1.25
			for t in mine:
				t.units += 6
	return m


static func enemies_gone(battle: Battle) -> bool:
	return battle.ai_sides.all(func(a): return a.side == Battle.PLAYER or not battle.alive(a.side))


## Won, lost or still going: "" (playing), "won", or why it's lost:
## "army" (your last building fell), "hq", "time" or "soldiers"
static func result(m: Dictionary, battle: Battle) -> String:
	if m.goal == "defend" and m.hq != null and m.hq.owner != Battle.PLAYER:
		return "hq"
	if not battle.alive(Battle.PLAYER):
		return "army"
	var gone := enemies_gone(battle)
	match m.goal:
		"defend":
			if battle.time >= m.time or gone:
				return "won"
		"capture":
			if gone or (not m.targets.is_empty() and m.targets.all(func(t): return t.owner == Battle.PLAYER)):
				return "won"
		"hq":
			if gone or (m.hq != null and m.hq.owner == Battle.PLAYER):
				return "won"
		"blitz":
			if gone:
				return "won"
			if battle.time >= m.time:
				return "time"
		"puzzle":
			if gone and battle.towers.all(func(t): return t.owner == Battle.PLAYER):
				return "won"
			# Out of soldiers: too few left to take every building that isn't yours (nothing trains,
			# so it can only get worse)
			if not battle.units.any(func(u): return u.owner == Battle.PLAYER):
				var have := 0.0
				var cost := 0.0
				var cheapest := INF
				for t in battle.towers:
					if t.owner == Battle.PLAYER:
						have += t.units
					else:
						var c := t.units * float(Battle.TYPES[t.type].defense) + 1
						cost += c
						cheapest = minf(cheapest, c)
				for u in battle.units:
					cost += u.power
				if have < cheapest or have < cost * 0.9:
					return "soldiers"
		_:
			if gone:
				return "won"
	return ""


## The line under the HUD bar: the goal, and how it's going
static func objective(m: Dictionary, battle: Battle) -> String:
	var ic: String = GOALS[m.goal].icon + "  "
	match m.goal:
		"defend":
			return ic + I18n.t("Hold your HQ: %s") % clock(m.time - battle.time)
		"capture":
			var have: int = m.targets.filter(func(t): return t.owner == Battle.PLAYER).size()
			return ic + I18n.t("Radars held: %d of %d") % [have, m.targets.size()]
		"puzzle":
			return ic + I18n.t("Nobody trains: take every building")
		"blitz":
			return ic + I18n.t("Take every building: %s left") % clock(m.time - battle.time)
		"hq":
			return ic + I18n.t("Take Grumble's castle")
	return ic + I18n.t("Take every enemy building")


## Is the clock nearly out? (the objective line turns red)
static func urgent(m: Dictionary, battle: Battle) -> bool:
	return m.goal == "blitz" and m.time - battle.time < 15


static func clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Why a mission was lost, for the defeat screen
static func lost_text(why: String) -> String:
	match why:
		"hq":
			return "Your headquarters has fallen."
		"time":
			return "Time's up! Grumble's reinforcements arrived."
		"soldiers":
			return "You're out of soldiers."
	return "Your last building has fallen."


## Stars: how well it went (3 is best)
static func stars(m: Dictionary, battle: Battle) -> int:
	# Par: how long a quick win takes on a map this size
	var par := 20.0 + battle.towers.size() * 5
	match m.get("goal", ""):
		"defend":
			# How strong your headquarters still is
			var left: float = m.hq.units if m.hq != null else 0.0
			return 3 if left >= 25 else 2 if left >= 10 else 1
		"puzzle":
			# How many soldiers you have left
			var kept := 0.0
			for t in battle.towers:
				if t.owner == Battle.PLAYER:
					kept += t.units
			return 3 if kept >= m.start * 0.15 else 2 if kept >= m.start * 0.06 else 1
		"blitz":
			# How much time was left on the clock
			var left: float = m.time - battle.time
			return 3 if left >= m.time * 0.3 else 2 if left >= m.time * 0.12 else 1
	var t := battle.time
	return 3 if t <= par else 2 if t <= par * 1.8 else 1
