class_name Battle
extends RefCounted
## One battle: the buildings, roads, soldiers and tanks, the rules and the enemy AI.
## It's the web version's simulation (tower-siege/game.js) in GDScript and draws nothing:
## main.gd shows it, and these signals tell it when something worth showing happens.
## Positions are in the field (900 × 1400 in portrait, or turned on its side when wide).

signal captured(t: Tower, side: int, old: int)
signal clashed(x: float, y: float, a: int, b: int, ua: Unit, ub: Unit)
signal shot(t: Tower, u: Unit)
signal hit(t: Tower, side: int)
signal bombed(t: Tower)

const NEUTRAL := 0
const PLAYER := 1
const CAP := 99.0            # buildings stop training here
const HARD_CAP := 150.0      # and can't be filled above this
const UNIT_SPEED := 115.0    # field units per second
const TANK_POWER := 3
const WATCH_RANGE := 230.0
const WATCH_RELOAD := 0.55
const STRIKE_TIME := 1.6
const RALLY_TIME := 8.0

const TYPES := {
	"barracks": {"name": "Tower", "prod": 1.0, "defense": 1.0},
	"fort": {"name": "Bunker", "prod": 0.8, "defense": 2.0, "intro": "New: the Bunker. Attackers only do half damage to it."},
	"factory": {"name": "Tank Factory", "prod": 1.1, "defense": 1.0, "intro": "New: the Tank Factory. It sends tanks: each one is worth 3 soldiers."},
	"watch": {"name": "Watchtower", "prod": 0.6, "defense": 1.0, "intro": "New: the Watchtower. It shoots enemies inside its circle."},
	# Campaign only (the web version and PvP maps don't have these)
	"camp": {"name": "Training Camp", "prod": 1.7, "defense": 0.7, "intro": "New: the Training Camp. It trains soldiers very fast, but it's easy to take."},
	"castle": {"name": "Castle", "prod": 1.1, "defense": 1.6, "intro": "Boss level! The enemy Castle is tough, trains fast and shoots. Take it to win."},
}
const CASTLE_RANGE := 190.0
const CASTLE_RELOAD := 1.2
const UPGRADE_COST := [10, 20]   # soldiers for a building's 1st and 2nd star
const STAR_BONUS := 0.3          # each star: trains 30% faster


class Tower:
	var id := 0
	var bx := 0.0          # where it is on the portrait level map
	var by := 0.0
	var x := 0.0           # where it is on the field as shown
	var y := 0.0
	var owner := 0
	var type := "barracks"
	var units := 0.0
	var roads: Array = []  # [{to: Tower, timer: float, born: float}]
	var flash := 0.0
	var pop := 0.0
	var reload := 0.0
	var aim := -PI / 2
	var stars := 0         # upgrades bought in this battle (campaign)

	func level() -> int:
		return 4 if units >= 60 else 3 if units >= 30 else 2 if units >= 10 else 1

	func max_roads() -> int:
		return mini(3, level())

	func radius() -> float:
		return (70.0 if type == "factory" else 72.0 if type == "fort" else 84.0 if type == "castle" else 64.0 if type == "camp" else 60.0) + level() * 3

	func shoots() -> bool:
		return type == "watch" or type == "castle"

	func shot_range() -> float:
		return CASTLE_RANGE if type == "castle" else WATCH_RANGE

	func has_road(b: Tower) -> bool:
		for r in roads:
			if r.to == b:
				return true
		return false


class Unit:
	var id := 0
	var from: Tower
	var to: Tower
	var owner := 0
	var power := 1
	var d := 0.0           # how far along its road
	var lane := 0.0        # a little to one side, so a column isn't a single file
	var x := 0.0
	var y := 0.0
	var dead := false
	var tank := false      # started out as a tank (for how it's drawn when knocked out)


class Wall:
	var bx := 0.0
	var by := 0.0
	var x := 0.0
	var y := 0.0
	var r := 30.0


var towers: Array[Tower] = []
var units: Array[Unit] = []
var rocks: Array[Wall] = []
var ai_sides: Array = []     # [{side, timer, cfg}]
var strikes: Array = []      # [{t: Tower, time, dur, done}]
var time := 0.0
var rally := 0.0
var mode := "campaign"       # campaign, online, duo or practice
var boost := {"drill": 0, "boots": 0}   # your upgrades (campaign only)
var stats := {"captured": 0, "lost": 0, "killed": 0}
var next_unit_id := 0
var landscape := false
var flipped := false         # an online guest sees the field turned around
var struck: Array = []       # the soldiers the last airstrike knocked out: [[x, y, owner, tank]]


func load_map(data: Dictionary, garrison := 0) -> void:
	towers.clear()
	units.clear()
	rocks.clear()
	strikes.clear()
	var i := 0
	for d in data.towers:
		var t := Tower.new()
		t.id = i
		t.bx = d[0]
		t.by = d[1]
		t.owner = int(d[2])
		t.units = float(d[3]) + (garrison if t.owner == PLAYER else 0)
		t.type = d[4] if d.size() > 4 else "barracks"
		towers.append(t)
		i += 1
	for d in data.rocks:
		var w := Wall.new()
		w.bx = d[0]
		w.by = d[1]
		w.r = d[2]
		rocks.append(w)
	place()
	time = 0.0
	rally = 0.0
	stats = {"captured": 0, "lost": 0, "killed": 0}


## Level-map coordinates to the field as it's shown now
func to_field(x: float, y: float) -> Vector2:
	if flipped:
		x = Levels.FW - x
		y = Levels.FH - y
	return Vector2(Levels.FH - y, x) if landscape else Vector2(x, y)


func place() -> void:
	for t in towers:
		var p := to_field(t.bx, t.by)
		t.x = p.x
		t.y = p.y
	for w in rocks:
		var p := to_field(w.bx, w.by)
		w.x = p.x
		w.y = p.y
	for u in units:
		place_unit(u)


static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))


# ---------- Rules ----------
func boosted(side: int) -> bool:
	return side == PLAYER and mode == "campaign"


func prod_rate(t: Tower) -> float:
	return (0.55 + 0.2 * t.level()) * TYPES[t.type].prod * (1 + 0.08 * boost.drill if boosted(t.owner) else 1.0) * (1 + STAR_BONUS * t.stars)


func sends_tanks(t: Tower) -> bool:
	return t.type == "factory"


func send_interval(t: Tower) -> float:
	return (2.4 if sends_tanks(t) else 1.0) / (1.6 + 0.4 * t.level()) / (2.0 if boosted(t.owner) and rally > 0 else 1.0)


func unit_speed(u: Unit) -> float:
	var s := UNIT_SPEED * (0.8 if u.power > 1 else 1.0)
	if boosted(u.owner):
		s *= (1 + 0.07 * boost.boots) * (1.4 if rally > 0 else 1.0)
	return s


func blocked(ax: float, ay: float, bx: float, by: float) -> bool:
	for w in rocks:
		if Levels.seg_dist(w.x, w.y, ax, ay, bx, by) < w.r + 6:
			return true
	return false


## Would a road from a to b work for `side`? true, or why not
func can_link(a: Tower, b: Tower, side: int) -> Variant:
	if a == null or b == null or a == b:
		return "same"
	if a.owner != side:
		return "not yours"
	if a.has_road(b):
		return "exists"
	if blocked(a.x, a.y, b.x, b.y):
		return "blocked"
	if a.roads.size() >= a.max_roads():
		return "full"
	return true


## Build a road from a to b for `side`. Returns true or why it can't.
func link(a: Tower, b: Tower, side: int) -> Variant:
	var ok = can_link(a, b, side)
	if ok is String:
		return ok
	# A road the other way between your own buildings turns around
	if b.owner == side:
		for i in b.roads.size():
			if b.roads[i].to == a:
				b.roads.remove_at(i)
				break
	a.roads.append({"to": b, "timer": 0.0, "born": time})
	return true


func cut(a: Tower, b: Tower) -> bool:
	for i in a.roads.size():
		if a.roads[i].to == b:
			a.roads.remove_at(i)
			return true
	return false


## Spend soldiers to give a building a star: it trains faster. Returns true or why not.
func can_upgrade(t: Tower, side: int) -> Variant:
	if t == null or t.owner != side:
		return "not yours"
	if t.stars >= UPGRADE_COST.size():
		return "max"
	if t.units < UPGRADE_COST[t.stars] + 1:
		return "soldiers"
	return true


func upgrade(t: Tower, side: int) -> Variant:
	var ok = can_upgrade(t, side)
	if ok is String:
		return ok
	t.units -= UPGRADE_COST[t.stars]
	t.stars += 1
	t.pop = 1.5
	return true


func spawn_unit(from: Tower, to: Tower, power: int) -> void:
	var u := Unit.new()
	u.id = next_unit_id
	next_unit_id += 1
	u.from = from
	u.to = to
	u.owner = from.owner
	u.power = power
	u.tank = power > 1
	u.d = from.radius() * 0.5
	u.lane = (randf() - 0.5) * 10
	u.x = from.x
	u.y = from.y
	units.append(u)


## A soldier's place on its road; returns the road's length
func place_unit(u: Unit) -> float:
	var L := dist(u.from.x, u.from.y, u.to.x, u.to.y)
	if L <= 0.0:
		L = 1.0
	var k := minf(1.0, u.d / L)
	var nx := -(u.to.y - u.from.y) / L
	var ny := (u.to.x - u.from.x) / L
	var sway := sin(k * PI) * u.lane
	u.x = u.from.x + (u.to.x - u.from.x) * k + nx * sway
	u.y = u.from.y + (u.to.y - u.from.y) * k + ny * sway
	return L


# ---------- Simulation ----------
func update(dt: float, run_ai := true) -> void:
	time += dt
	if rally > 0:
		rally = maxf(0, rally - dt)

	for t in towers:
		if t.owner != NEUTRAL and t.units < CAP:
			t.units = minf(CAP, t.units + prod_rate(t) * dt)
		t.flash = maxf(0, t.flash - dt * 3)
		t.pop = maxf(0, t.pop - dt * 4)
		for r in t.roads:
			r.timer -= dt
			if r.timer > 0:
				continue
			# Tank factories send a tank when they have enough soldiers for one
			var power := TANK_POWER if sends_tanks(t) and t.units >= TANK_POWER else 1
			if t.units >= power:
				t.units -= power
				spawn_unit(t, r.to, power)
				r.timer = send_interval(t) * (1.0 if power > 1 else 0.8)
			else:
				r.timer = 0.0
		if t.shoots():
			_update_watch(t, dt)

	# March
	for u in units:
		if u.dead:
			continue
		u.d += unit_speed(u) * dt
		var L := place_unit(u)
		if u.d >= L - u.to.radius() * 0.5:
			_arrive(u)
			u.dead = true

	_fight()
	units = units.filter(func(u): return not u.dead)

	if run_ai:
		for a in ai_sides:
			a.timer -= dt
			if a.timer <= 0:
				a.timer = a.cfg.think * (0.8 + randf() * 0.4)
				ai_think(a.side, a.cfg)
	_update_strikes(dt)


func _arrive(u: Unit) -> void:
	var t := u.to
	if t.owner == u.owner:
		t.units = minf(HARD_CAP, t.units + u.power)
		t.pop = 1.0
		return
	t.units -= u.power / TYPES[t.type].defense
	t.flash = 1.0
	hit.emit(t, u.owner)
	if t.units < 0:
		capture(t, u.owner)


func capture(t: Tower, side: int) -> void:
	var old := t.owner
	t.owner = side
	t.units = absf(t.units)
	t.stars = 0
	t.roads.clear()
	t.pop = 1.5
	if side == PLAYER:
		stats.captured += 1
	elif old == PLAYER:
		stats.lost += 1
	captured.emit(t, side, old)


## Soldiers of different armies that meet fight: the stronger one (a tank) survives, weakened
func _fight() -> void:
	const R := 22.0
	const CELL := 40.0
	var grid := {}
	for u in units:
		if u.dead:
			continue
		var key := Vector2i(floori(u.x / CELL), floori(u.y / CELL))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(u)
	for u in units:
		if u.dead:
			continue
		var cx := floori(u.x / CELL)
		var cy := floori(u.y / CELL)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if u.dead:
					break
				var list = grid.get(Vector2i(cx + dx, cy + dy))
				if list == null:
					continue
				for v in list:
					if v.dead or v == u or v.owner == u.owner:
						continue
					if absf(u.x - v.x) < R and absf(u.y - v.y) < R:
						var m := mini(u.power, v.power)
						u.power -= m
						v.power -= m
						if u.power <= 0:
							u.dead = true
						if v.power <= 0:
							v.dead = true
						if u.owner == PLAYER or v.owner == PLAYER:
							stats.killed += 1
						clashed.emit((u.x + v.x) / 2, (u.y + v.y) / 2, u.owner, v.owner, u, v)
						if u.dead:
							break


## Watchtowers (and a boss level's castle) shoot the nearest enemy inside their circle
func _update_watch(t: Tower, dt: float) -> void:
	t.reload -= dt
	if t.owner == NEUTRAL or t.reload > 0:
		return
	var best: Unit = null
	var bd := t.shot_range()
	for u in units:
		if u.dead or u.owner == t.owner:
			continue
		var d := dist(u.x, u.y, t.x, t.y)
		if d < bd:
			bd = d
			best = u
	if best == null:
		return
	best.power -= 1
	if best.power <= 0:
		best.dead = true
	t.reload = CASTLE_RELOAD if t.type == "castle" else WATCH_RELOAD
	t.aim = atan2(best.y - t.y, best.x - t.x)
	shot.emit(t, best)


func totals() -> Array:
	var tot := [0.0, 0.0, 0.0, 0.0, 0.0]
	for t in towers:
		tot[t.owner] += t.units
	for u in units:
		tot[u.owner] += u.power
	return tot


func alive(side: int) -> bool:
	for t in towers:
		if t.owner == side:
			return true
	for u in units:
		if u.owner == side:
			return true
	return false


# ---------- Enemy brains ----------
## Enemy strength heading for tower t
func threat_on(t: Tower) -> int:
	var n := 0
	for u in units:
		if u.to == t and u.owner != t.owner:
			n += u.power
	return n


## `side`'s own strength heading for tower t
func inbound(t: Tower, side: int) -> int:
	var n := 0
	for u in units:
		if u.to == t and u.owner == side:
			n += u.power
	return n


func ai_think(side: int, cfg: Dictionary) -> void:
	var mine := towers.filter(func(t): return t.owner == side)
	if mine.is_empty():
		return

	# Tidy up: pull back hopeless attacks and supply roads from threatened buildings
	for t in mine:
		for i in range(t.roads.size() - 1, -1, -1):
			var tgt: Tower = t.roads[i].to
			if tgt.owner == side:
				if threat_on(t) > t.units * 0.6 or (threat_on(tgt) == 0 and randf() < 0.35):
					t.roads.remove_at(i)
			else:
				var need: float = tgt.units * TYPES[tgt.type].defense
				var sending := float(inbound(tgt, side))
				for s in towers:
					if s.owner == side and s.has_road(tgt):
						sending += s.units
				if t.units < 3 and sending < need * 0.7 and randf() < 0.6:
					t.roads.remove_at(i)

	# Attack: find the cheapest, closest building it can take with up to 3 of its own
	var best := {}
	for tgt in towers:
		if tgt.owner == side:
			continue
		var already := float(inbound(tgt, side))
		for s in mine:
			if s.has_road(tgt):
				already += s.units
		var sources := mine.filter(func(s): return s.roads.size() < s.max_roads() and s.units >= 5 and not s.has_road(tgt) and not blocked(s.x, s.y, tgt.x, tgt.y) and threat_on(s) < s.units * 0.5)
		if sources.is_empty():
			continue
		sources.sort_custom(func(a, b): return dist(a.x, a.y, tgt.x, tgt.y) < dist(b.x, b.y, tgt.x, tgt.y))
		var travel := dist(sources[0].x, sources[0].y, tgt.x, tgt.y) / UNIT_SPEED
		var grow := 0.0 if tgt.owner == NEUTRAL else prod_rate(tgt) * travel
		# Watchtowers shoot some of the attackers on the way in
		var guard := 0
		for w in towers:
			if w.shoots() and w.owner != NEUTRAL and w.owner != side and dist(w.x, w.y, tgt.x, tgt.y) < w.shot_range():
				guard += 4
		var need: float = (tgt.units + grow) * TYPES[tgt.type].defense + cfg.margin + guard - already
		var used := []
		var total := 0.0
		for s in sources:
			if total >= need or used.size() >= 3:
				break
			used.append(s)
			total += s.units - 1
		if total < need:
			continue
		var dsum := 0.0
		for s in used:
			dsum += dist(s.x, s.y, tgt.x, tgt.y)
		var value: float = 1.0 + (cfg.bold if tgt.owner == PLAYER else 0.0) + (0.4 if tgt.type == "factory" or tgt.type == "camp" else 0.0) + (0.2 if tgt.owner != NEUTRAL else 0.0)
		var score := value / (maxf(1, need) + dsum / used.size() / 22)
		if best.is_empty() or score > best.score:
			best = {"score": score, "tgt": tgt, "used": used}
	if not best.is_empty():
		for s in best.used:
			link(s, best.tgt, side)

	# On later levels: upgrade a safe building that has soldiers to spare
	if cfg.get("upgrade", false) and randf() < 0.2:
		for t in mine:
			if t.stars < UPGRADE_COST.size() and t.units > 25 + UPGRADE_COST[t.stars] and threat_on(t) == 0:
				upgrade(t, side)
				break

	# Reinforce buildings under attack from safe buildings nearby
	for t in mine:
		if threat_on(t) <= t.units * 0.8:
			continue
		var helpers := mine.filter(func(s): return s != t and s.units > 8 and threat_on(s) == 0 and s.roads.size() < s.max_roads() and not s.has_road(t) and not blocked(s.x, s.y, t.x, t.y))
		if helpers.is_empty():
			continue
		helpers.sort_custom(func(a, b): return dist(a.x, a.y, t.x, t.y) < dist(b.x, b.y, t.x, t.y))
		link(helpers[0], t, side)


# ---------- Abilities ----------
func drop_strike(t: Tower) -> void:
	strikes.append({"t": t, "time": STRIKE_TIME, "dur": STRIKE_TIME, "done": false})


func _update_strikes(dt: float) -> void:
	for s in strikes:
		s.time -= dt
		if s.time <= 0 and not s.done:
			s.done = true
			var t: Tower = s.t
			if t.owner != PLAYER:
				t.units = maxf(0, t.units - maxf(8, t.units * 0.5))
			t.flash = 1.0
			struck = []
			for u in units:
				if u.owner != PLAYER and dist(u.x, u.y, t.x, t.y) < 130:
					u.dead = true
					struck.append([u.x, u.y, u.owner, u.tank])
			units = units.filter(func(u): return not u.dead)
			bombed.emit(t)
	strikes = strikes.filter(func(s): return not s.done)
