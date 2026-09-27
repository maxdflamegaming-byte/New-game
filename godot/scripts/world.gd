extends Node
## The board and its rules: the grid, movement, trails, capturing land, knockouts and bumps.
## Positions are in cells (a player at (10.5, 3.5) is in the middle of cell 10, 3).

signal captured(p: Player, cells: PackedInt32Array, gain_pct: float)
signal knocked_out(victim: Player, killer: Player, how: String, lost: PackedInt32Array)
signal spawned(p: Player)

const N := 80
const SPEED := 7.5 # cells per second
const TURN := 5.5 # radians per second
const SPAWN_SHIELD := 3.0
const WIN_PCT := 50.0

const COLORS: Array[Color] = [
	Color("#4f8cff"), Color("#ff5d73"), Color("#ffb84d"), Color("#2ec4b6"),
	Color("#b06bff"), Color("#ff7ac6"), Color("#8bd346"), Color("#ff8c42"),
]
const BOT_NAMES := ["Mango", "Zigzag", "Pixel", "Turbo", "Luna", "Nacho", "Bloop"]

var land := PackedByteArray() # who owns each cell (0 = nobody)
var trail := PackedByteArray() # whose trail is on each cell (0 = none)
var counts := PackedInt32Array() # cells owned, per player id
var play_cells := N * N
var players: Array = [] # players[id]; players[0] is null
var me: Player
var bots
var time := 0.0
var won := false
var land_version := 0 # goes up whenever land changes, so the view knows to redraw

var _seen := PackedByteArray()
var _stack := PackedInt32Array()


func _init() -> void:
	bots = preload("res://scripts/bots.gd").new(self)
	land.resize(N * N)
	trail.resize(N * N)
	_seen.resize(N * N)
	_stack.resize(N * N)
	counts.resize(16)


## A new game: you (unless demo is true) and 7 bots with different personalities
func setup(my_color: int, my_name: String, demo := false) -> void:
	land.fill(0)
	trail.fill(0)
	counts.fill(0)
	time = 0.0
	won = false
	land_version += 1
	players = [null]
	me = Player.new(1, my_name if my_name != "" else "You", COLORS[my_color], demo)
	players.append(me)
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var others: Array[Color] = []
	for i in COLORS.size():
		if i != my_color:
			others.append(COLORS[i])
	var mix: Array = bots.PERSONA_MIX.duplicate()
	mix.shuffle()
	for i in 7:
		var b := Player.new(i + 2, names[i], others[i], true)
		bots.give_personality(b, mix[i])
		players.append(b)
	if demo:
		bots.give_personality(me, "wildcard")
	spawn(me, N / 2, N / 2)
	for p in players:
		if p and p != me:
			spawn(p)


func pct(p: Player) -> float:
	return counts[p.id] * 100.0 / play_cells


func set_land(i: int, id: int) -> void:
	var prev := land[i]
	if prev == id:
		return
	if prev:
		counts[prev] -= 1
	land[i] = id
	if id:
		counts[id] += 1


# ---------- Spawning ----------

## Cells in the small starting patch around (x, y) that nobody owns and no trail crosses
func free_start_cells(x: int, y: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cx := x + dx
			var cy := y + dy
			if dx * dx + dy * dy > 7 or cx < 0 or cy < 0 or cx >= N or cy >= N:
				continue
			var i := cy * N + cx
			if land[i] == 0 and trail[i] == 0:
				cells.append(i)
	return cells


## Puts a player on the map with a small patch of land. Returns false if there's no room
## right now (bots then try again a moment later).
func spawn(p: Player, fx := -1, fy := -1) -> bool:
	var bx := fx
	var by := fy
	if bx < 0:
		var best := -INF
		for t in 60:
			var x := randi_range(4, N - 5)
			var y := randi_range(4, N - 5)
			var i := y * N + x
			if land[i] or trail[i]:
				continue
			var score := float(free_start_cells(x, y).size())
			for o in players:
				if o and o != p and o.alive and Vector2(x, y).distance_to(o.pos) < 10:
					score -= 30
			if score > best:
				best = score
				bx = x
				by = y
		if bx < 0 or free_start_cells(bx, by).size() < 5:
			p.respawn = 1.0
			return false
	var cells := free_start_cells(bx, by)
	for i in cells:
		set_land(i, p.id)
	land_version += 1
	p.pos = Vector2(bx + 0.5, by + 0.5)
	p.cell = Vector2i(bx, by)
	p.angle = randf() * TAU
	p.desired = p.angle
	p.alive = true
	p.trail = PackedInt32Array()
	p.path.clear()
	p.wp.clear()
	p.mode = "idle"
	p.think = randf_range(0.2, 1.0)
	p.route = null
	p.shield = SPAWN_SHIELD
	p.squash = 1.0
	spawned.emit(p)
	return true


# ---------- Knockouts ----------

func kill(victim: Player, killer: Player, how := "cut") -> void:
	if not victim.alive:
		return
	# Once you've won, the celebration can't be spoiled
	if won and victim == me:
		return
	# A shield stops other players, but not your own mistakes or losing all your land
	if victim.shield > 0 and killer != victim and how != "swallow":
		return
	victim.alive = false
	var lost := PackedInt32Array()
	for i in victim.trail:
		if trail[i] == victim.id:
			trail[i] = 0
			lost.append(i)
	victim.trail = PackedInt32Array()
	victim.path.clear()
	for i in N * N:
		if land[i] == victim.id:
			set_land(i, 0)
			lost.append(i)
	land_version += 1
	victim.respawn = 3.0
	if killer and killer != victim:
		killer.kills += 1
	knocked_out.emit(victim, killer, how, lost)


# ---------- Capturing land ----------

## Your trail becomes land, and so does everything it encloses: a flood fill from the map
## edges through every cell that isn't yours; whatever it can't reach is enclosed.
func capture(p: Player) -> void:
	var gained := PackedInt32Array()
	for i in p.trail:
		if trail[i] == p.id:
			trail[i] = 0
		if land[i] != p.id:
			gained.append(i)
		set_land(i, p.id)
	p.trail = PackedInt32Array()
	p.path.clear()

	_seen.fill(0)
	var top := 0
	for k in N:
		for i in [k, (N - 1) * N + k, k * N, k * N + N - 1]:
			if _seen[i] == 0 and land[i] != p.id:
				_seen[i] = 1
				_stack[top] = i
				top += 1
	while top > 0:
		top -= 1
		var i := _stack[top]
		var x := i % N
		if x > 0 and _seen[i - 1] == 0 and land[i - 1] != p.id:
			_seen[i - 1] = 1
			_stack[top] = i - 1
			top += 1
		if x < N - 1 and _seen[i + 1] == 0 and land[i + 1] != p.id:
			_seen[i + 1] = 1
			_stack[top] = i + 1
			top += 1
		if i >= N and _seen[i - N] == 0 and land[i - N] != p.id:
			_seen[i - N] = 1
			_stack[top] = i - N
			top += 1
		if i < N * (N - 1) and _seen[i + N] == 0 and land[i + N] != p.id:
			_seen[i + N] = 1
			_stack[top] = i + N
			top += 1
	for i in N * N:
		if _seen[i] == 0 and land[i] != p.id:
			set_land(i, p.id)
			gained.append(i)
	land_version += 1

	# Anyone who lost all their land is out
	for o in players:
		if o and o != p and o.alive and counts[o.id] == 0:
			kill(o, p, "swallow")
	p.wp.clear()
	p.mode = "idle"
	captured.emit(p, gained, gained.size() * 100.0 / play_cells)


# ---------- Movement ----------

func speed_of(_p: Player) -> float:
	return SPEED


func is_wall_at(x: float, y: float) -> bool:
	return x < 0 or y < 0 or x >= N or y >= N


func visit(p: Player, x: int, y: int) -> void:
	var i := y * N + x
	var t := trail[i]
	if t:
		var other: Player = players[t]
		if other == p:
			kill(p, p)
			return
		kill(other, p)
		if other.alive:
			return # their shield held: the cell stays part of their trail
	if land[i] == p.id:
		if p.trail.size() > 0:
			capture(p)
	else:
		trail[i] = p.id
		p.trail.append(i)


func move(p: Player, dt: float) -> void:
	var before := p.pos
	_step(p, dt)
	# The trail is drawn along the path the square really drove, so it's smooth
	if p.alive and p.trail.size() > 0:
		if p.path.is_empty():
			p.path.append(before)
		if p.path[p.path.size() - 1].distance_to(p.pos) >= 0.3:
			p.path.append(p.pos)


func _step(p: Player, dt: float) -> void:
	var diff := wrapf(p.desired - p.angle, -PI, PI)
	var turn := clampf(diff, -TURN * dt, TURN * dt)
	p.angle = wrapf(p.angle + turn, -PI, PI)
	p.turning = turn / (TURN * dt) if dt > 0 else 0.0
	var v := speed_of(p)
	var nx := clampf(p.pos.x + cos(p.angle) * v * dt, 0.01, N - 0.01)
	var ny := clampf(p.pos.y + sin(p.angle) * v * dt, 0.01, N - 0.01)
	p.blocked = is_equal_approx(nx, p.pos.x) and is_equal_approx(ny, p.pos.y)
	p.pos = Vector2(nx, ny)
	var cx := int(nx)
	var cy := int(ny)
	if cx == p.cell.x and cy == p.cell.y:
		return
	# Diagonal step: also visit a corner cell, so trails never have gaps to slip through
	if cx != p.cell.x and cy != p.cell.y:
		visit(p, cx, p.cell.y)
		if not p.alive:
			return
	visit(p, cx, cy)
	p.cell = Vector2i(cx, cy)


## Two squares touching: whoever is safe on their own land wins. If both are outside, the
## longer trail loses; equal trails knock both out.
func check_bumps() -> void:
	for a in range(1, players.size()):
		for b in range(a + 1, players.size()):
			var p: Player = players[a]
			var q: Player = players[b]
			if not p.alive or not q.alive or p.pos.distance_to(q.pos) > 0.9:
				continue
			var p_safe := land[p.cell.y * N + p.cell.x] == p.id
			var q_safe := land[q.cell.y * N + q.cell.x] == q.id
			if p_safe and q_safe:
				continue
			if p_safe:
				kill(q, p, "bump")
			elif q_safe:
				kill(p, q, "bump")
			elif p.trail.size() > q.trail.size():
				kill(p, q, "bump")
			elif q.trail.size() > p.trail.size():
				kill(q, p, "bump")
			else:
				kill(p, q, "bump")
				kill(q, p, "bump")


func update(dt: float) -> void:
	time += dt
	for p in players:
		if p == null:
			continue
		if not p.alive:
			if p.is_bot and p != me:
				p.respawn -= dt
				if p.respawn <= 0:
					spawn(p)
			continue
		p.shield = maxf(0.0, p.shield - dt)
		p.squash = move_toward(p.squash, 0.0, dt * 3.0)
		p.blink -= dt
		if p.blink < -0.12:
			p.blink = randf_range(2.0, 5.0)
		if p.is_bot:
			bots.steer(p, dt)
		move(p, dt)
	check_bumps()


## Place (1 = biggest) among players still in the game
func rank_of(p: Player) -> int:
	var r := 1
	for o in players:
		if o and o != p and o.alive and counts[o.id] > counts[p.id]:
			r += 1
	return r


func alive_count() -> int:
	var n := 0
	for o in players:
		if o and o.alive:
			n += 1
	return n
