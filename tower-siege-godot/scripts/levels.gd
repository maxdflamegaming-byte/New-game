class_name Levels
extends RefCounted
## The campaign's levels and the PvP maps. The generator follows the web version
## (tower-siege/game.js, genLevel) step for step with the same random numbers, so a level,
## or a PvP map made from a seed, is the same in both versions.
##
## Buildings are [x, y, owner, soldiers, type]; walls are [x, y, radius] circles that block roads.
## Coordinates are a 900 × 1400 field in portrait, your base at the bottom.

const FW := 900.0
const FH := 1400.0
const MAX_LEVEL := 60          # the levels that match the web version; after them, endless levels
const LAST_LEVEL := 999
const THEMES := ["grass", "desert", "snow", "beach"]

## AI: think = seconds between moves, margin = spare soldiers it wants before attacking,
## bold = how much it prefers hitting you.
## The first five story levels are small and made by hand, each teaching one thing (the
## lessons in tutorial.gd walk you through them). Only this app has them: from level 6 on,
## levels are made the same way as the web version's. Towers: [x, y, army, soldiers, type];
## rocks (walls): [x, y, radius].
## AI: think = seconds between moves, margin = spare soldiers it wants before attacking,
## bold = how much it prefers hitting you.
const FIRST := [
	# 1. Attack: take the gray tower, then the red one
	{
		"towers": [[450.0, 1130.0, 1, 12], [450.0, 380.0, 2, 3], [450.0, 760.0, 0, 5]],
		"ai": {"think": 5.0, "margin": 9.0, "bold": 0.0},
	},
	# 2. Grow: gather soldiers into one tower; at 10 it gets a storey and a second road.
	# Walls keep the middle tower from reaching the sides, so the army goes round from below
	{
		"towers": [[450.0, 1160.0, 1, 7], [180.0, 760.0, 2, 3], [450.0, 780.0, 1, 4], [720.0, 760.0, 0, 5]],
		"rocks": [[315.0, 600.0, 30.0], [315.0, 660.0, 30.0], [315.0, 720.0, 30.0], [315.0, 780.0, 30.0], [315.0, 840.0, 30.0],
			[585.0, 600.0, 30.0], [585.0, 660.0, 30.0], [585.0, 720.0, 30.0], [585.0, 780.0, 30.0], [585.0, 840.0, 30.0]],
		"ai": {"think": 5.0, "margin": 9.0, "bold": 0.0},
	},
	# 3. Cheap towers first, two attacks at once, and the 💡 Hint
	{
		"towers": [[450.0, 1150.0, 1, 15], [450.0, 330.0, 2, 12], [200.0, 760.0, 0, 3], [700.0, 760.0, 0, 4]],
		"ai": {"think": 3.6, "margin": 6.0, "bold": 0.2},
	},
	# 4. The Airstrike, and a Watchtower that shoots inside its circle
	{
		"towers": [[450.0, 1160.0, 1, 20], [630.0, 520.0, 2, 11], [230.0, 790.0, 0, 5, "watch"], [150.0, 1060.0, 0, 2], [720.0, 850.0, 0, 7]],
		"ai": {"think": 3.4, "margin": 5.0, "bold": 0.3},
	},
	# 5. Boss: feed your small towers into the big one, then storm Grumble's castle
	{
		"towers": [[450.0, 880.0, 1, 12], [450.0, 300.0, 2, 30, "castle"], [210.0, 760.0, 1, 6], [690.0, 760.0, 1, 5], [250.0, 1140.0, 1, 6], [650.0, 1140.0, 1, 5]],
		"ai": {"think": 3.4, "margin": 6.0, "bold": 0.4},
	},
]

const HINTS := {
	4: "Soldiers from different armies fight when they meet on the field",
	6: "Walls block roads. Find a way around them.",
	12: "A third army! The enemies fight each other too. Let them wear each other down.",
}


static func theme_for(n: int) -> String:
	return THEMES[((n - 1) / 5) % THEMES.size()]


static func data(n: int) -> Dictionary:
	var b := boss(n)
	if not b.is_empty():
		return b
	if n <= FIRST.size():
		var d: Dictionary = FIRST[n - 1].duplicate(true)
		d["rocks"] = d.get("rocks", [])
		d["hint"] = ""
		d.ai.upgrade = false
		return d
	return extras(gen(n), n)


## Enemy soldiers on a few generated levels, from playing them with the level bot: less than 1
## where it got stuck, more where a late level fell in seconds
const TUNE := {29: 0.8, 43: 1.4, 44: 0.6, 58: 1.4}


## A line of wall blocks from one point to another (a block every 44, like the generator's)
static func _wall(x0: float, y0: float, x1: float, y1: float) -> Array:
	var out := []
	var n := maxi(1, roundi(_d(x0, y0, x1, y1) / 44.0))
	for i in n + 1:
		out.append([lerpf(x0, x1, float(i) / n), lerpf(y0, y1, float(i) / n), 30.0])
	return out


## A ring of wall blocks round a point, with gaps (angles in degrees, 0 = right, 90 = down)
static func _ring(cx: float, cy: float, r: float, gaps: Array) -> Array:
	var out := []
	for a in range(0, 360, 15):
		if gaps.any(func(g): return absf(fposmod(a - g + 180.0, 360.0) - 180.0) < 25):
			continue
		out.append([cx + cos(deg_to_rad(a)) * r, cy + sin(deg_to_rad(a)) * r, 30.0])
	return out


## The boss levels at the end of chapters 2 to 12 are made by hand, each with its own twist
## (Grumble's taunt hints at it). Towers: [x, y, army, soldiers, type]; the castle is always
## the second. Level 5 is one of the first five; the endless levels' bosses are made.
static func boss(n: int) -> Dictionary:
	var t := []
	var rocks := []
	var hint := ""
	match n:
		10:
			# "Its walls have never fallen": the castle sits behind walls with one gate, so
			# only buildings in line with the gate can hit it
			t = [[450, 1180, 1, 14], [450, 250, 2, 26, "castle"], [450, 760, 0, 12, "factory"],
				[200, 1000, 0, 6], [700, 1000, 0, 6], [720, 600, 2, 10], [180, 600, 0, 8, "fort"]]
			rocks = _wall(270, 150, 270, 450) + _wall(630, 150, 630, 450) + _wall(314, 450, 380, 450) + _wall(520, 450, 586, 450)
			hint = "The castle's walls have one gate. Take the Tank Factory in front of it: only from there can you reach the castle."
		15:
			# "Frozen solid": Grumble and Duke Mustard side by side, a wall between them
			t = [[450, 1170, 1, 14], [250, 280, 2, 26, "castle"], [680, 300, 3, 18], [220, 900, 0, 8], [680, 900, 0, 8],
				[450, 700, 0, 14, "fort"], [230, 560, 0, 8, "watch"], [690, 560, 0, 8]]
			rocks = _wall(450, 140, 450, 480)
			hint = "Two armies at the top, a wall between them. Let them fight, take the middle, then hit the castle."
		20:
			# "Even tougher": three lanes split by long walls, each its own front
			t = [[450, 1170, 1, 14], [450, 220, 2, 46, "castle"], [150, 1100, 1, 8], [150, 700, 0, 7], [150, 390, 0, 9],
				[450, 800, 0, 12, "factory"], [450, 520, 0, 10, "fort"], [750, 1100, 0, 6], [750, 700, 2, 10], [750, 390, 0, 9]]
			rocks = _wall(300, 400, 300, 1010) + _wall(600, 400, 600, 1010)
			hint = "Walls split the field into three lanes. Push up each lane; the castle is open from the top of all three."
		25:
			# "A bigger army": Major Moss's Green army arrives, and Duke Mustard is back
			t = [[450, 1170, 1, 16], [450, 230, 2, 58, "castle"], [150, 520, 3, 16], [750, 520, 4, 16], [250, 1060, 1, 8],
				[450, 780, 0, 14, "factory"], [260, 820, 0, 8], [640, 820, 0, 8], [450, 520, 0, 10, "fort"]]
			hint = "Four armies! Let Yellow and Green wear Grumble down, then strike the castle."
		30:
			# "More cannons": Watchtowers guard the castle. Take the gray ones and they shoot for you
			t = [[450, 1170, 1, 16], [450, 230, 2, 85, "castle"], [280, 330, 2, 8, "watch"], [620, 330, 2, 8, "watch"],
				[320, 560, 0, 8, "watch"], [580, 560, 0, 8, "watch"], [200, 950, 1, 8], [700, 950, 1, 8],
				[450, 820, 0, 12, "factory"], [120, 560, 3, 14]]
			hint = "Watchtowers guard the castle. Take the gray ones first: then they shoot Grumble's soldiers for you."
		35:
			# "A moat": a ring of walls round the castle with a gate on each side
			t = [[450, 1180, 1, 16], [450, 330, 2, 64, "castle"], [130, 330, 0, 10], [770, 330, 0, 10], [200, 1100, 1, 8],
				[450, 760, 0, 14, "fort"], [200, 700, 0, 8, "factory"], [700, 700, 0, 8, "factory"]]
			rocks = _ring(450, 330, 170, [0, 180])
			hint = "The castle's moat has a gate on each side. Take the towers beside it and attack through the gates."
		40:
			# "My finest castle": Training Camps on both sides; whoever holds more trains faster
			t = [[450, 1180, 1, 18], [450, 200, 2, 95, "castle"], [250, 330, 2, 10, "camp"], [650, 330, 2, 10, "camp"],
				[250, 1050, 1, 8, "camp"], [650, 1050, 1, 8, "camp"], [450, 700, 0, 20, "fort"],
				[180, 700, 0, 10, "factory"], [720, 700, 0, 10, "factory"]]
			hint = "Training Camps train very fast. Grab yours, then take Grumble's before you storm the castle."
		45:
			# "I'll do it myself": the castle sits in the middle of the field, with the Yellow
			# and Green armies on the flanks
			t = [[450, 1180, 1, 18], [450, 580, 2, 90, "castle"], [250, 250, 2, 12], [650, 250, 2, 12],
				[120, 420, 3, 14], [780, 420, 4, 14], [450, 900, 0, 10, "fort"], [270, 1120, 1, 8], [630, 1120, 1, 8]]
			hint = "Grumble came out to fight: his castle is right in front of you. Hit it hard before the others close in."
		50:
			# "Pure stubbornness": a line of Bunkers guards the castle; Tank Factories help break it
			t = [[450, 1180, 1, 18], [450, 240, 2, 70, "castle"], [250, 520, 2, 10, "fort"], [450, 560, 2, 12, "fort"],
				[650, 520, 2, 10, "fort"], [220, 950, 1, 10, "factory"], [680, 950, 1, 10, "factory"],
				[450, 840, 0, 14], [790, 640, 4, 12]]
			hint = "A line of Bunkers guards the castle. Take the Tank Factories: each tank is worth 3 soldiers."
		55:
			# "Only two castles left": an empty castle stands in the middle. Take it and its guns
			# are yours
			t = [[450, 1180, 1, 18], [450, 220, 2, 110, "castle"], [450, 700, 0, 24, "castle"], [200, 1080, 1, 8], [700, 1080, 1, 8],
				[180, 700, 0, 10, "factory"], [720, 700, 0, 10, "factory"], [200, 380, 2, 12, "watch"], [700, 380, 2, 12, "watch"]]
			hint = "The castle in the middle is empty. Take it, and its guns shoot Grumble's soldiers for you."
		60:
			# "My last and greatest castle": everything at once
			t = [[450, 1190, 1, 20], [450, 190, 2, 90, "castle"], [280, 310, 2, 10, "watch"], [620, 310, 2, 10, "watch"],
				[120, 540, 3, 16], [780, 540, 4, 16], [450, 620, 0, 20, "fort"], [250, 820, 0, 10, "factory"],
				[650, 820, 0, 10, "factory"], [450, 920, 0, 12], [200, 1120, 1, 10], [700, 1120, 1, 10]]
			rocks = _wall(240, 450, 340, 520) + _wall(660, 450, 560, 520)
			hint = "Grumble's last castle! Everyone is here. Take the middle, let the others fight, and finish him."
		_:
			return {}
	var towers := []
	for x in t:
		towers.append([float(x[0]), float(x[1]), int(x[2]), int(x[3]), x[4] if x.size() > 4 else "barracks"])
	var ai := {"think": maxf(1.7, 3.1 - n * 0.04), "margin": maxf(3.0, 7 - n * 0.1), "bold": minf(0.75, 0.25 + n * 0.02), "upgrade": n >= 25}
	return {"towers": towers, "rocks": rocks, "ai": ai, "hint": hint}


## Every chapter (five levels, one land) ends with a boss: General Grumble's castle
static func is_boss(n: int) -> bool:
	return n >= 5 and n % 5 == 0


## What this version adds to a generated campaign level: a boss Castle every 5th level,
## Training Camps, enemies that upgrade their buildings from level 25, and endless levels
## (after 60) whose enemies keep getting stronger
static func extras(d: Dictionary, n: int) -> Dictionary:
	var towers: Array = d.towers
	if is_boss(n):
		towers[1][4] = "castle"
		# The first castle (level 5) starts as strong as your base; the later ones stronger
		if n >= 10:
			towers[1][3] = int(towers[1][3]) + 5 + n / 6
		d.hint = "Boss level! Attack the Castle from several buildings at once, and stay clear of its circle until you do."
	# Training Camps: the first pair of gray towers (they come in mirrored pairs) on some levels
	if n >= 15 and (n * 37) % 5 < 2:
		for i in range(2, towers.size() - 1, 2):
			if towers[i][2] == 0 and towers[i][4] == "barracks" and towers[i + 1][4] == "barracks":
				towers[i][4] = "camp"
				towers[i + 1][4] = "camp"
				break
	# From level 40 the web version gives the enemy two outposts beside its base, so you'd
	# start one building against three. Here the buildings mirroring them are yours, so both
	# sides start even (the map is the same; maps come in mirrored pairs)
	if n >= 40:
		for i in range(2, towers.size()):
			var t: Array = towers[i]
			if int(t[2]) != 2:
				continue
			for m in towers:
				if int(m[2]) == 0 and absf(float(m[0]) - (FW - float(t[0]))) < 1 and absf(float(m[1]) - (FH - float(t[1]))) < 1:
					m[2] = 1
					m[3] = t[3]
					break
	# Levels the level bot found too hard or too easy (tests/levels.gd): the enemy armies'
	# soldiers scaled
	if TUNE.has(n):
		for t in towers:
			if int(t[2]) >= 2:
				t[3] = maxi(1, roundi(float(t[3]) * TUNE[n]))
	if n > MAX_LEVEL:
		var extra := (n - MAX_LEVEL) / 2
		for t in towers:
			if int(t[2]) >= 2:
				t[3] = int(t[3]) + extra
	d.ai = d.ai.duplicate()
	d.ai.upgrade = n >= 25
	# The web version's enemy gets so quick and bold after level 35 that the story turned into a
	# wall (the level bot in tests/levels.gd lost nearly every level there): here it never
	# moves more often than every 1.7 seconds or attacks without a few soldiers to spare
	d.ai.think = maxf(float(d.ai.think), 1.7)
	d.ai.margin = maxf(float(d.ai.margin), 3.0)
	d.ai.bold = minf(float(d.ai.bold), 0.75)
	if n == 8 and d.hint == "":
		d.hint = "Tap one of your buildings, then the ⬆ button: spend soldiers so it trains faster."
	if n == MAX_LEVEL + 1 and d.hint == "":
		d.hint = "Endless levels: every level from here gets a little harder."
	return d


## Today's challenge: one map for everyone, made from the date (days since 1970, UTC)
static func daily(day: int) -> Dictionary:
	var seed_value := (day * 2654435761 + 977) & 0x7fffffff
	var n := 25 + day % 20
	var d := gen(14, true, seed_value)
	var base := gen(n)
	d.ai = base.ai.duplicate()
	d.ai.upgrade = true
	for t in d.towers:
		if int(t[2]) == 2:
			t[3] = int(t[3]) + n / 3
		elif int(t[2]) == 0:
			t[3] = int(t[3]) + n / 6
	d.hint = "Daily challenge: the same map for everyone today. Win it for a big coin prize!"
	d.theme = THEMES[day % THEMES.size()]
	return d


## The web version's random numbers (mulberry32), on 32-bit unsigned values
class Rng:
	var s: int

	func _init(seed_value: int) -> void:
		s = seed_value & 0xffffffff

	static func imul(a: int, b: int) -> int:
		a &= 0xffffffff
		b &= 0xffffffff
		return (a * (b & 0xffff) + (((a * (b >> 16)) & 0xffff) << 16)) & 0xffffffff

	func next() -> float:
		s = (s + 0x6d2b79f5) & 0xffffffff
		var t := imul(s ^ (s >> 15), 1 | s)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0

	func pick(a: float, b: float) -> float:
		return a + next() * (b - a)


static func _d(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))


## Distance from point p to the segment a-b
static func seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var len2 := dx * dx + dy * dy
	if len2 == 0.0:
		len2 = 1.0
	var t := clampf(((px - ax) * dx + (py - ay) * dy) / len2, 0.0, 1.0)
	return _d(px, py, ax + dx * t, ay + dy * t)


## pvp: a fair 1-vs-1 map from seed_value (same start for both, no extra armies)
static func gen(n: int, pvp := false, seed_value := 0) -> Dictionary:
	var rng := Rng.new(seed_value if pvp else n * 7919 + 13)
	var per := mini(7, 3 + n / 7)
	var pts := [[rng.pick(280, 620), rng.pick(1180, 1260)]]
	var k := 0
	while k < 600 and pts.size() < per:
		var px := rng.pick(90, 810)
		var py := rng.pick(770, 1280)
		var ok := true
		for q in pts:
			if not (_d(px, py, q[0], q[1]) > 200 and _d(px, py, FW - q[0], FH - q[1]) > 200):
				ok = false
				break
		if ok and _d(px, py, FW - px, FH - py) > 200:
			pts.append([px, py])
		k += 1

	var towers := []
	var base_units := 15 if pvp else 12 + n / 6
	for i in pts.size():
		var p: Array = pts[i]
		var mx: float = FW - p[0]
		var my: float = FH - p[1]
		if i == 0:
			towers.append([p[0], p[1], 1, base_units if pvp else 12, "barracks"])
			towers.append([mx, my, 2, base_units, "barracks"])
		else:
			var u := int(round(4 + rng.next() * (6 + n * 0.22)))
			var type := "barracks"
			var r := rng.next()
			if n >= 3 and r < 0.15:
				type = "fort"
			elif n >= 4 and r < 0.32:
				type = "factory"
			elif n >= 7 and r < 0.45:
				type = "watch"
			towers.append([p[0], p[1], 0, u, type])
			towers.append([mx, my, 0, u, type])
	# A big neutral prize in the middle
	if rng.next() < 0.6:
		var type := "barracks"
		if n >= 3 and rng.next() < 0.5:
			type = "fort"
		elif n >= 4:
			type = "factory"
		towers.append([FW / 2, FH / 2, 0, 14 + n / 3, type])

	# Enemy outposts on later levels: the gray buildings nearest the red base turn red
	var ex: float = towers[1][0]
	var ey: float = towers[1][1]
	var by_enemy := towers.filter(func(t): return t[2] == 0 and t[1] < FH / 2)
	by_enemy.sort_custom(func(a, b): return _d(a[0], a[1], ex, ey) < _d(b[0], b[1], ex, ey))
	var outposts := 0 if pvp else mini(2, floori((n - 10) / 15.0))
	k = 0
	while k < outposts and k < by_enemy.size() - 1:
		by_enemy[k][2] = 2
		by_enemy[k][3] = 8 + n / 6
		k += 1
	# Every third level from 12: a yellow army far from the red base. From 25, every fifth: green too.
	var extra := []
	if not pvp and n >= 12 and n % 3 == 0:
		extra.append(3)
	if not pvp and n >= 25 and n % 5 == 0:
		extra.append(4)
	for side in extra:
		var cands := towers.filter(func(t): return t[2] == 0 and t[1] < FH * 0.62)
		if cands.is_empty():
			continue
		var far: Array = cands[0]
		for c in cands:
			if absf(c[0] - ex) > absf(far[0] - ex):
				far = c
		far[2] = side
		far[3] = base_units

	# Walls: short lines of blocks in the middle, mirrored, never cutting a building off
	var rocks := []
	if n >= 6:
		var count := 1 + (1 if n >= 18 else 0) + (1 if n >= 35 else 0)
		k = 0
		while k < 300 and rocks.size() < count * 2 * 4:
			k += 1
			var length := 3 + floori(rng.next() * 3)
			var r := 30.0
			var gap := 44.0
			var a := floori(rng.next() * 4) * PI / 4
			var cx := rng.pick(140, 760)
			var cy := rng.pick(540, 860)
			var wall := []
			for i in length:
				var off := gap * (i - (length - 1) / 2.0)
				wall.append([cx + cos(a) * off, cy + sin(a) * off, r])
			var both := wall.duplicate()
			for w in wall:
				both.append([FW - w[0], FH - w[1], r])
			var clear := true
			for w in both:
				if not (w[0] > 40 and w[0] < FW - 40):
					clear = false
					break
				for t in towers:
					if not (_d(t[0], t[1], w[0], w[1]) > r + 80):
						clear = false
						break
				if not clear:
					break
				for o in rocks:
					if not (_d(o[0], o[1], w[0], w[1]) > r + o[2] + 8):
						clear = false
						break
				if not clear:
					break
			var near_middle := false
			for w in wall:
				if _d(w[0], w[1], FW / 2, FH / 2) < 60:
					near_middle = true
			if not clear or near_middle:
				continue
			rocks.append_array(both)
			if not connected(towers, rocks):
				rocks.resize(rocks.size() - both.size())

	var ai := {"think": maxf(0.8, 3.1 - n * 0.04), "margin": maxf(1.5, 7 - n * 0.1), "bold": minf(1, 0.25 + n * 0.02)}
	return {"towers": towers, "rocks": rocks, "ai": ai, "hint": HINTS.get(n, "")}


## Every building can be reached from every other by roads that don't hit walls
static func connected(towers: Array, rocks: Array) -> bool:
	var seen := {0: true}
	var queue := [0]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in towers.size():
			if seen.has(j):
				continue
			var ok := true
			for r in rocks:
				if not (seg_dist(r[0], r[1], towers[i][0], towers[i][1], towers[j][0], towers[j][1]) > r[2] + 6):
					ok = false
					break
			if ok:
				seen[j] = true
				queue.append(j)
	return seen.size() == towers.size()
