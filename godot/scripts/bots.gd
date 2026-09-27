extends RefCounted
## Bot brains: plan loops out of their land, head home the safe way, and hunt trails.

const PERSONAS := {
	"hunter": {"aggro": 0.8, "greed": 26, "loop": 0.9, "flee": 4},
	"turtle": {"aggro": 0.06, "greed": 18, "loop": 0.7, "flee": 8},
	"explorer": {"aggro": 0.15, "greed": 60, "loop": 1.6, "flee": 5},
	"collector": {"aggro": 0.25, "greed": 35, "loop": 1.0, "flee": 5},
	"wildcard": {},
}
const PERSONA_MIX := ["hunter", "turtle", "explorer", "collector", "wildcard", "hunter", "explorer"]
const THINK_EVERY := 0.25
const LOOK := 16 # steps of 0.05 s the safety check looks ahead
const OFFSETS := [0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.6, -2.6, PI]

var w # the world
var _prev := PackedInt32Array()
var _mark := PackedInt32Array()
var _queue := PackedInt32Array()
var _gen := 0


func _init(world) -> void:
	w = world
	var n: int = world.N * world.N
	_prev.resize(n)
	_mark.resize(n)
	_queue.resize(n)


func give_personality(p: Player, id: String) -> void:
	var d: Dictionary = PERSONAS[id]
	p.persona = id
	if d.has("aggro"):
		p.aggro = d.aggro
		p.greed = d.greed
		p.loop_scale = d.loop
	p.flee = d.get("flee", 5)


# ---------- Pathfinding ----------

func _touches_own_trail(p: Player, x: int, y: int) -> bool:
	var n: int = w.N
	var i := y * n + x
	return (x > 0 and w.trail[i - 1] == p.id) or (x < n - 1 and w.trail[i + 1] == p.id) \
		or (y > 0 and w.trail[i - n] == p.id) or (y < n - 1 and w.trail[i + n] == p.id)


## Next to the map edge? Squares need room to turn, so bots keep off it when they can.
func _beside_wall(x: int, y: int) -> bool:
	return x <= 0 or y <= 0 or x >= w.N - 1 or y >= w.N - 1


## Breadth-first search from the bot's head to its nearest own land that never steps on its
## own trail. The padded pass also keeps a cell of room from the trail and the edge.
## Returns the path (without the start) or null.
func _bfs_home(p: Player, padded: bool):
	var n: int = w.N
	_gen += 1
	var start := p.cell.y * n + p.cell.x
	var head := 0
	var tail := 1
	_queue[0] = start
	_mark[start] = _gen
	while head < tail:
		var i := _queue[head]
		head += 1
		if w.land[i] == p.id:
			var path := PackedInt32Array()
			var c := i
			while c != start:
				path.append(c)
				c = _prev[c]
			path.reverse()
			return path
		var x := i % n
		var y := i / n
		for d in 4:
			var nx := x + (1 if d == 0 else -1 if d == 1 else 0)
			var ny := y + (1 if d == 2 else -1 if d == 3 else 0)
			if nx < 0 or ny < 0 or nx >= n or ny >= n:
				continue
			var j := ny * n + nx
			if _mark[j] == _gen or w.trail[j] == p.id:
				continue
			if padded and (absi(nx - p.cell.x) > 2 or absi(ny - p.cell.y) > 2):
				if _touches_own_trail(p, nx, ny) or (w.land[j] != p.id and _beside_wall(nx, ny)):
					continue
			_mark[j] = _gen
			_prev[j] = i
			_queue[tail] = j
			tail += 1
	return null


func route_home(p: Player):
	var r = _bfs_home(p, true)
	return r if r != null else _bfs_home(p, false)


## Simulates the curve a square really drives (it can only turn so fast) while aiming at
## `desired`, and returns how many steps it survives before touching its own trail.
func safe_steps(p: Player, desired: float, steps := LOOK, dt := 0.05) -> int:
	var n: int = w.N
	var x := p.pos.x
	var y := p.pos.y
	var a := p.angle
	var cx := p.cell.x
	var cy := p.cell.y
	var v: float = w.speed_of(p)
	for k in steps:
		a += clampf(wrapf(desired - a, -PI, PI), -w.TURN * dt, w.TURN * dt)
		x = clampf(x + cos(a) * v * dt, 0.01, n - 0.01)
		y = clampf(y + sin(a) * v * dt, 0.01, n - 0.01)
		var fx := int(x)
		var fy := int(y)
		if fx == cx and fy == cy:
			continue
		if fx != cx and fy != cy and w.trail[cy * n + fx] == p.id:
			return k
		if w.trail[fy * n + fx] == p.id:
			return k
		if w.land[fy * n + fx] == p.id:
			return steps # made it home
		cx = fx
		cy = fy
	return steps


func nearest_own(p: Player) -> Vector2:
	var n: int = w.N
	for r in n:
		for d in range(-r, r + 1):
			for c in [Vector2i(p.cell.x + d, p.cell.y - r), Vector2i(p.cell.x + d, p.cell.y + r), Vector2i(p.cell.x - r, p.cell.y + d), Vector2i(p.cell.x + r, p.cell.y + d)]:
				if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and w.land[c.y * n + c.x] == p.id:
					return Vector2(c.x + 0.5, c.y + 0.5)
	return p.pos


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var steps := int(ceil(a.distance_to(b) * 2))
	for k in steps + 1:
		var q := a.lerp(b, float(k) / maxi(steps, 1))
		if w.is_wall_at(q.x, q.y):
			return false
	return true


## Like a clear line, but with room either side: a turning square swings wider than the line
func _clear_lane(a: Vector2, b: Vector2, r: float) -> bool:
	var side := (b - a).normalized().orthogonal() * r
	return _clear_line(a, b) and _clear_line(a + side, b + side) and _clear_line(a - side, b - side)


# ---------- Decisions ----------

func plan_loop(p: Player) -> void:
	var n: int = w.N
	for tries in 10:
		var shrink := 1.0 if tries < 6 else 0.5
		var a := randf() * TAU
		var length := randf_range(5, 11 + minf(10, w.counts[p.id] / 60.0)) * p.loop_scale * shrink
		var wid := randf_range(4, 10) * p.loop_scale * shrink * (1 if randf() < 0.5 else -1)
		var A := (p.pos + Vector2.from_angle(a) * length).clamp(Vector2(1.5, 1.5), Vector2(n - 1.5, n - 1.5))
		var B := (A + Vector2.from_angle(a + PI / 2) * wid).clamp(Vector2(1.5, 1.5), Vector2(n - 1.5, n - 1.5))
		var r := 1.0 if tries < 8 else 0.0
		if _clear_lane(p.pos, A, r) and _clear_lane(A, B, r) and _clear_lane(B, p.pos, r):
			p.wp = [A, B]
			p.mode = "loop"
			return
	p.wp = [nearest_own(p)]
	p.mode = "idle"


func go_home(p: Player) -> void:
	p.wp.clear()
	p.mode = "home"
	p.route = null


func _closest_trail_point(p: Player, o: Player) -> Vector2:
	var n: int = w.N
	var best := o.trail[0]
	var best_d := INF
	for k in range(0, o.trail.size(), 2):
		var i := o.trail[k]
		var d := p.pos.distance_squared_to(Vector2(i % n + 0.5, i / n + 0.5))
		if d < best_d:
			best_d = d
			best = i
	return Vector2(best % n + 0.5, best / n + 0.5)


func think(p: Player) -> void:
	var outside := p.trail.size() > 0
	# Head home if an enemy gets close while the trail is out, or if we got greedy
	if outside and p.mode != "home":
		var threat := false
		if p.mode != "hunt":
			for o in w.players:
				if o and o != p and o.alive and o.pos.distance_to(p.pos) < p.flee:
					threat = true
					break
		if threat or p.trail.size() > p.greed:
			go_home(p)
			return
	# Hunt: go for the closest part of a nearby trail. The bigger you get, the further bots
	# look for your trail and the more often they come for it.
	if p.mode != "home" and p.mode != "hunt" and p.trail.size() < 25:
		var growth := clampf(w.pct(w.me) / 30.0, 0, 1) if w.me.alive and not w.me.is_bot else 0.0
		for o in w.players:
			if o == null or o == p or not o.alive or o.trail.size() < 4 or o.shield > 0:
				continue
			var bold := growth if o == w.me else 0.0
			if o.pos.distance_to(p.pos) < 14 + bold * 12 and randf() < p.aggro + bold * 0.4:
				p.wp = [_closest_trail_point(p, o)]
				p.mode = "hunt"
				return
	if not outside and p.wp.is_empty():
		plan_loop(p)


func steer(p: Player, dt: float) -> void:
	p.think -= dt
	if p.think <= 0:
		p.think = THINK_EVERY
		think(p)
	while not p.wp.is_empty() and p.pos.distance_to(p.wp[0]) < 0.8:
		p.wp.pop_front()
	if p.trail.size() > 0 and p.mode != "home" and (p.blocked or (not p.wp.is_empty() and not _clear_line(p.pos, p.wp[0]))):
		go_home(p)
	elif p.blocked and not p.wp.is_empty():
		p.wp.pop_front()
	if p.wp.is_empty() and p.trail.size() > 0 and p.mode != "home":
		go_home(p)

	var target = p.wp[0] if not p.wp.is_empty() else null
	if p.mode == "home":
		# Re-plan often: the route is cheap and the board keeps changing
		p.route_timer -= dt
		if p.route == null or p.route_timer <= 0:
			p.route = route_home(p)
			p.route_timer = 0.15
		if p.route != null and p.route.size() > 0:
			# Aim a few cells down the route, but never past a corner of the map
			var n: int = w.N
			var k := mini(2, p.route.size() - 1)
			while k > 0 and not _clear_line(p.pos, Vector2(p.route[k] % n + 0.5, p.route[k] / n + 0.5)):
				k -= 1
			target = Vector2(p.route[k] % n + 0.5, p.route[k] / n + 0.5)
		else:
			target = nearest_own(p)
	if target != null:
		p.desired = (target - p.pos).angle()

	# Last-moment safety: never steer into our own trail. Try nearby directions and keep
	# whichever survives longest.
	if p.trail.size() > 0 and safe_steps(p, p.desired) < LOOK:
		var best_dir := p.desired
		var best_steps := -1
		for off in OFFSETS:
			var s := safe_steps(p, p.desired + off)
			if s > best_steps:
				best_steps = s
				best_dir = p.desired + off
			if s >= LOOK:
				break
		p.desired = best_dir
