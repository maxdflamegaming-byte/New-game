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
const MAX_LEVEL := 60
const THEMES := ["grass", "desert", "snow", "beach"]

## AI: think = seconds between moves, margin = spare soldiers it wants before attacking,
## bold = how much it prefers hitting you.
const TUTORIAL := [
	{
		"towers": [[450.0, 1180.0, 1, 12], [260.0, 760.0, 0, 5], [640.0, 700.0, 0, 7], [450.0, 240.0, 2, 6]],
		"ai": {"think": 4.5, "margin": 8.0, "bold": 0.0},
		"hint": "Drag from your blue tower to a gray one to send soldiers",
		"hand": true,
	},
	{
		"towers": [[230.0, 1190.0, 1, 14], [690.0, 1150.0, 0, 4], [450.0, 880.0, 0, 10], [200.0, 560.0, 0, 8], [700.0, 520.0, 0, 8], [450.0, 220.0, 2, 12]],
		"ai": {"think": 3.6, "margin": 6.0, "bold": 0.1},
		"hint": "Swipe across one of your roads to cut it. Soldiers on it keep marching.",
	},
	{
		"towers": [[450.0, 1210.0, 1, 16], [200.0, 940.0, 0, 6], [700.0, 940.0, 0, 6], [450.0, 700.0, 0, 16, "fort"], [200.0, 460.0, 0, 6], [700.0, 460.0, 0, 6], [450.0, 190.0, 2, 16]],
		"ai": {"think": 3.2, "margin": 5.0, "bold": 0.2},
		"hint": "Bigger towers hold more roads: 2 roads from 10 soldiers, 3 from 30",
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
	if n <= TUTORIAL.size():
		var d: Dictionary = TUTORIAL[n - 1].duplicate(true)
		d["rocks"] = []
		return d
	return gen(n)


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
