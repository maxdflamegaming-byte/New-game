extends Node
## Playing online, on the phone: connects to the server, sends your steering, and keeps the
## World in step with what the server sends. The World isn't simulated here; this sets where
## everyone is (smoothed between snapshots) and fires the World's usual signals, so the board,
## sounds and HUD work exactly as offline.

signal connected # welcome received
signal round_started(first: bool) # a round's board arrived
signal round_over(data: Dictionary)
signal failed(reason: String) # couldn't connect, or the connection dropped

const CONNECT_TIMEOUT := 8.0
const INTERP_DELAY := 0.12 # others are drawn this far behind the latest snapshot, to stay smooth
const INPUT_EVERY := 0.05

var world
var net # the Net node
var url := ""
var my_id := 0
var room := 0
var round_no := 0
var status := "off" # off, connecting, joining, in
var round_limit := 300.0
var desyncs := 0 # snapshots where our board didn't match the server's
var snaps := 0

var _peer: WebSocketMultiplayerPeer
var _connect_time := 0.0
var _samples := {} # player id -> [[server time, pos, angle], ...] (the last few)
var _server_time := 0.0 # the latest snapshot's time
var _clock := 0.0 # our estimate of the server's time now
var _sent_angle := INF
var _input_timer := 0.0
var _join_info := {}


## Starts connecting; `info` is what the server shows of you (name, colour, looks)
func start(server_url: String, info: Dictionary) -> void:
	stop()
	url = server_url
	_join_info = info
	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = 1 << 22
	_peer.outbound_buffer_size = 1 << 16
	var err := _peer.create_client(url)
	if err != OK:
		failed.emit("connect")
		return
	get_tree().get_multiplayer().multiplayer_peer = _peer
	net.handler = self
	status = "connecting"
	_connect_time = 0.0
	var mp := get_tree().get_multiplayer()
	if not mp.connected_to_server.is_connected(_on_connected):
		mp.connected_to_server.connect(_on_connected)
		mp.connection_failed.connect(_on_failed)
		mp.server_disconnected.connect(_on_dropped)


func stop() -> void:
	if _peer:
		_peer.close()
	get_tree().get_multiplayer().multiplayer_peer = null
	_peer = null
	status = "off"
	my_id = 0
	_samples.clear()


func is_on() -> bool:
	return status != "off"


func _on_connected() -> void:
	status = "joining"
	var info := _join_info.duplicate()
	info["v"] = net.PROTOCOL
	net.c_join.rpc_id(1, info)


func _on_failed() -> void:
	if status != "off":
		stop()
		failed.emit("connect")


func _on_dropped() -> void:
	if status != "off":
		stop()
		failed.emit("dropped")


## Tap Play (or Play again): come into the round
func respawn() -> void:
	if status == "in":
		net.c_respawn.rpc_id(1, 0)


# ---------- Messages from the server ----------

func on_welcome(_peer_id: int, d: Dictionary) -> void:
	room = int(d.get("room", 0))
	connected.emit()


func on_error(_peer_id: int, d: Dictionary) -> void:
	var code := str(d.get("code", "error"))
	stop()
	failed.emit(code)


func on_round(_peer_id: int, d: Dictionary) -> void:
	var first := status != "in"
	status = "in"
	round_no = int(d.get("round", 0))
	round_limit = float(d.get("limit", 300.0))
	world.setup_mirror(str(d.get("map", "square")), d.get("walls", PackedByteArray()))
	_samples.clear()
	for info in d.get("players", []):
		world._put(NetCodec.from_info(info))
	var land: PackedByteArray = d.get("land", PackedByteArray())
	var trail: PackedByteArray = d.get("trail", PackedByteArray())
	for i in mini(land.size(), world.N * world.N):
		if land[i] and _player(land[i]):
			world.set_land(i, land[i])
	for i in mini(trail.size(), world.N * world.N):
		if trail[i] and _player(trail[i]):
			world.trail[i] = trail[i]
			_player(trail[i]).trail.append(i)
	world.land_version += 1
	my_id = int(d.get("you", 0))
	world.me = _player(my_id)
	_server_time = float(d.get("time", 0.0))
	_clock = _server_time
	_apply_states(d.get("states", PackedFloat32Array()), _server_time)
	var st: Array = d.get("storm", [0.0, 0.0])
	world.storm_r = st[0]
	world.storm_next = st[1]
	if world.me:
		world.me.alive = false # until you tap Play
	round_started.emit(first)


func on_round_over(_peer_id: int, d: Dictionary) -> void:
	round_over.emit(d)


func on_snap(_peer_id: int, d: Dictionary) -> void:
	if status != "in":
		return
	snaps += 1
	var t: float = d.get("t", 0.0)
	# People who left, and people (or bots) who came
	for id in d.get("left", []):
		_drop(int(id))
	for info in d.get("join", []):
		var id := int(info.get("id", 0))
		if _player(id):
			_drop(id)
		var p := NetCodec.from_info(info)
		world._put(p)
	world.me = _player(my_id)
	# What happened (before the cells change, so a knockout can still find the land it loses)
	for e in d.get("ev", []):
		_event(e)
	# Cells that changed
	var l: PackedInt32Array = d.get("l", PackedInt32Array())
	for k in range(0, l.size(), 2):
		world.set_land(l[k], l[k + 1])
	if l.size() > 0:
		world.land_version += 1
	var tr: PackedInt32Array = d.get("tr", PackedInt32Array())
	for k in range(0, tr.size(), 2):
		var i := tr[k]
		var old: int = world.trail[i]
		if old and _player(old):
			var arr: PackedInt32Array = _player(old).trail
			var at := arr.find(i)
			if at >= 0:
				arr.remove_at(at)
			_player(old).trail = arr
		world.trail[i] = tr[k + 1]
		if tr[k + 1] and _player(tr[k + 1]):
			_player(tr[k + 1]).trail.append(i)
	_apply_states(d.get("p", PackedFloat32Array()), t)
	# Power-ups, coins and hazards
	world.powerups.clear()
	var pu: PackedFloat32Array = d.get("pu", PackedFloat32Array())
	var kinds: Array = world.POWERUPS.keys()
	for k in range(0, pu.size(), 4):
		world.powerups.append({"pos": Vector2(pu[k], pu[k + 1]), "kind": kinds[clampi(int(pu[k + 2]), 0, kinds.size() - 1)], "age": pu[k + 3]})
	world.coins.clear()
	var co: PackedFloat32Array = d.get("co", PackedFloat32Array())
	for k in range(0, co.size(), 4):
		world.coins.append({"pos": Vector2(co[k], co[k + 1]), "age": co[k + 2], "life": co[k + 3]})
	var saws: PackedFloat32Array = d.get("saws", PackedFloat32Array())
	for k in mini(world.saws.size(), saws.size() / 3):
		world.saws[k].pos = Vector2(saws[k * 3], saws[k * 3 + 1])
		world.saws[k].spin = saws[k * 3 + 2]
	var fl: PackedFloat32Array = d.get("bump", PackedFloat32Array())
	for k in mini(world.bumpers.size(), fl.size()):
		world.bumpers[k].flash = maxf(world.bumpers[k].flash, fl[k])
	var st: Array = d.get("storm", [world.storm_r, world.storm_next])
	world.storm_next = st[1]
	world.freezer = _player(int(d.get("freezer", 0)))
	# The board must match the server's exactly; if it ever doesn't, count it (tests check this)
	if d.has("h") and int(d.h) != (hash(world.land) ^ hash(world.trail)):
		desyncs += 1
	world.time = t
	_server_time = t


func _player(id: int) -> Player:
	if id <= 0 or id >= world.players.size():
		return null
	return world.players[id]


func _drop(id: int) -> void:
	var p := _player(id)
	if p == null:
		return
	for i in p.trail:
		if world.trail[i] == id:
			world.trail[i] = 0
	p.alive = false
	world.players[id] = null
	_samples.erase(id)
	if world.me == p:
		world.me = null


func _event(e: Array) -> void:
	if e.is_empty():
		return
	var p := _player(int(e[1])) if e.size() > 1 and e[0] != "stormc" and e[0] != "stormh" else null
	match str(e[0]):
		"cap":
			if p:
				world.captured.emit(p, e[2], e[3])
		"ko":
			if p == null:
				return
			var lost := PackedInt32Array()
			for i in world.N * world.N:
				if world.land[i] == p.id or world.trail[i] == p.id:
					lost.append(i)
			p.alive = false
			p.path.clear()
			p.path_breaks.clear()
			var killer := _player(int(e[2]))
			if killer and killer != p:
				killer.kills += 1
			world.knocked_out.emit(p, killer, str(e[3]), lost)
		"spawn":
			if p:
				p.alive = true
				p.shield = world.SPAWN_SHIELD
				p.squash = 1.0
				world.spawned.emit(p)
		"pick":
			if p:
				world.picked.emit(p, str(e[2]), Vector2(e[3], e[4]))
		"paint":
			if p:
				world.painted.emit(p, e[2])
		"coin":
			if p:
				if p == world.me:
					world.coins_picked += world.COIN_VALUE
				world.coin_taken.emit(p, Vector2(e[2], e[3]))
		"tele":
			if p:
				if not p.trail.is_empty():
					p.path_breaks.append(p.path.size())
				_samples.erase(p.id) # no gliding across the map
				world.teleported.emit(p, Vector2(e[2], e[3]), Vector2(e[4], e[5]))
		"stormc":
			world.storm_next = e[1]
			world.storm_coming.emit(e[1])
		"stormh":
			_close_storm(e[1])
		"bump":
			if p:
				p.squash = 1.0
				world.bumped.emit(p, Vector2(e[2], e[3]))


## The storm closed in: everything outside the circle becomes storm (the land there was
## already cleared by the server's cell changes)
func _close_storm(r: float) -> void:
	var c: Vector2 = world.center()
	for y in world.N:
		for x in world.N:
			var i: int = y * world.N + x
			if world.wall[i] != 2 and Vector2(x + 0.5, y + 0.5).distance_to(c) > r:
				world.wall[i] = 2
	world.play_cells = 0
	for i in world.N * world.N:
		if world.wall[i] == 0:
			world.play_cells += 1
	world.storm_r = r
	world.storm_next = 0.0
	world.map_version += 1
	world.storm_hit.emit(r)


func _apply_states(s: PackedFloat32Array, t: float) -> void:
	var stride: int = NetCodec.STRIDE
	for k in range(0, s.size() - stride + 1, stride):
		var p := _player(int(s[k]))
		if p == null:
			continue
		var pos := Vector2(s[k + 1], s[k + 2])
		var was_alive := p.alive
		p.alive = s[k + 4] > 0.5
		p.shield = s[k + 5]
		p.fx.speed = s[k + 6]
		p.fx.ghost = s[k + 7]
		p.fx.freeze = s[k + 8]
		p.kills = int(s[k + 9])
		if not p.alive:
			_samples.erase(p.id)
			continue
		if not was_alive or not _samples.has(p.id):
			_samples[p.id] = []
			p.pos = pos
			p.angle = s[k + 3]
			p.desired = p.angle
		var list: Array = _samples[p.id]
		list.append([t, pos, s[k + 3]])
		if list.size() > 6:
			list.pop_front()


# ---------- Every frame ----------

func _process(dt: float) -> void:
	if status == "connecting":
		_connect_time += dt
		if _connect_time > CONNECT_TIMEOUT:
			stop()
			failed.emit("timeout")
		return
	if status != "in" or world == null:
		return
	# Our clock runs on from the latest snapshot, never far ahead of it
	_clock = minf(_clock + dt, _server_time + 0.25)
	_clock = maxf(_clock, _server_time - 0.25)
	for p in world.players:
		if p == null or not p.alive or not _samples.has(p.id):
			continue
		var list: Array = _samples[p.id]
		if list.is_empty():
			continue
		var before: Vector2 = p.pos
		if p == world.me:
			# You: the newest position, carried on the way you're going (so steering feels
			# instant rather than a snapshot late)
			var last: Array = list.back()
			var ahead := clampf(_clock - last[0], 0.0, 0.2)
			var v: float = world.speed_of(p)
			p.pos = last[1] + Vector2.from_angle(last[2]) * v * ahead
			p.angle = last[2]
		else:
			p.pos = _sample_at(list, _clock - INTERP_DELAY, p)
		p.pos = p.pos.clamp(Vector2(0.01, 0.01), Vector2(world.N - 0.01, world.N - 0.01))
		p.cell = Vector2i(int(p.pos.x), int(p.pos.y))
		p.turning = clampf(wrapf(p.desired - p.angle, -PI, PI) * 2.0, -1.0, 1.0) if p == world.me else 0.0
		# The trail is drawn along where the square actually went
		if not p.trail.is_empty():
			if p.path.is_empty():
				p.path.append(before)
			if p.path[p.path.size() - 1].distance_to(p.pos) >= 0.3:
				p.path.append(p.pos)
		elif not p.path.is_empty():
			p.path.clear()
			p.path_breaks.clear()
		p.squash = move_toward(p.squash, 0.0, dt * 3.0)
		p.hit_flash = maxf(0.0, p.hit_flash - dt * 2.0)
		p.blink -= dt
		if p.blink < -0.12:
			p.blink = randf_range(2.0, 5.0)
	for b in world.bumpers:
		b.flash = maxf(0.0, b.flash - dt * 3.0)
	# Send your steering (a few times a second, or when it changes)
	_input_timer -= dt
	var me: Player = world.me
	if me and me.alive and _input_timer <= 0 and absf(wrapf(me.desired - _sent_angle, -PI, PI)) > 0.01:
		_input_timer = INPUT_EVERY
		_sent_angle = me.desired
		net.c_input.rpc_id(1, me.desired)


## Where a player was at server time `t`, between the two snapshots around it
func _sample_at(list: Array, t: float, p: Player) -> Vector2:
	if t <= list[0][0]:
		p.angle = list[0][2]
		return list[0][1]
	for k in range(list.size() - 1):
		var a: Array = list[k]
		var b: Array = list[k + 1]
		if t <= b[0]:
			var f: float = (t - a[0]) / maxf(0.0001, b[0] - a[0])
			p.angle = lerp_angle(a[2], b[2], f)
			return a[1].lerp(b[1], f)
	var last: Array = list.back()
	p.angle = last[2]
	return last[1]
