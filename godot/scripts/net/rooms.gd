extends Node
## The online server's rooms. Each room is a World with up to 8 players; people fill the
## places bots leave, so a room is never empty and nobody waits for a match. The server runs
## the real game 30 times a second and sends each phone ~15 snapshots a second.
##
## A round is Classic rules (first to 50%), or the biggest after ROUND_TIME. Then everyone
## sees the results, and the next round starts on another map. People start each round (and
## come back after a knockout) when they tap Play again, which sends "respawn".

const TICK := 1.0 / 30.0
const SNAP_EVERY := 2 # ticks between snapshots (15 a second)
var ROUND_TIME := 300.0 # (a setting, so tests can use short rounds)
const BREAK_TIME := 6.0 # seconds between rounds
const MAX_ROOMS := 60
const EMPTY_ROOM_LIFE := 20.0 # a room nobody's in is closed after this long
const MAPS := ["square", "round", "pillars", "maze", "islands", "saws", "conveyor", "portals", "ice", "bumpers", "storm"]

var net # the Net node (see net.gd)
var rooms: Array = [] # Room
var _by_peer := {} # peer id -> Room
var _acc := 0.0
var log_to_console := true
var _bytes := 0 # snapshot bytes sent since the last report, for the log
var _snap_count := 0
var _report := 0.0


class Room:
	var id := 0
	var world
	var peers := {} # peer id -> {"player": Player, "info": Dictionary}
	var prev_land := PackedByteArray()
	var prev_trail := PackedByteArray()
	var events := []
	var joined := [] # player infos that appeared since the last snapshot
	var left := [] # player ids that went
	var tick := 0
	var round_no := 0
	var map_index := 0
	var over := false # between rounds
	var break_left := 0.0
	var empty_for := 0.0


func _ready() -> void:
	net.handler = self
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _log(s: String) -> void:
	if log_to_console:
		print("[server] ", s)


func _on_peer_connected(peer: int) -> void:
	_log("peer %d connected (%d online)" % [peer, multiplayer.get_peers().size()])


func _on_peer_disconnected(peer: int) -> void:
	var room: Room = _by_peer.get(peer)
	_by_peer.erase(peer)
	if room == null:
		return
	var entry: Dictionary = room.peers.get(peer, {})
	room.peers.erase(peer)
	if entry.has("player"):
		var p: Player = entry.player
		if room.world.players.size() > p.id and room.world.players[p.id] == p:
			room.world.remove_player(p)
			room.left.append(p.id)
		if not room.over:
			_match_bots(room)
			for b in _refill(room):
				room.joined.append(NetCodec.info(b))
	_log("peer %d left room %d" % [peer, room.id])


# ---------- Rooms ----------

## The room with the most people that still has space (so people play together)
func _pick_room() -> Room:
	var best: Room = null
	for r in rooms:
		if r.peers.size() < r.world.ROOM_SIZE and (best == null or r.peers.size() > best.peers.size()):
			best = r
	if best == null and rooms.size() < MAX_ROOMS:
		best = _new_room()
	return best


func _new_room() -> Room:
	var r := Room.new()
	r.id = (rooms.back().id + 1) if not rooms.is_empty() else 1
	r.world = preload("res://scripts/world.gd").new()
	add_child(r.world)
	r.map_index = randi() % MAPS.size()
	_connect_events(r)
	_start_round(r)
	rooms.append(r)
	_log("room %d opened (%d rooms)" % [r.id, rooms.size()])
	return r


func _close_room(r: Room) -> void:
	rooms.erase(r)
	r.world.queue_free()
	_log("room %d closed (%d rooms)" % [r.id, rooms.size()])


func _start_round(r: Room) -> void:
	r.round_no += 1
	r.over = false
	_match_bots(r)
	r.world.setup_room(MAPS[r.map_index % MAPS.size()])
	r.map_index += 1
	r.prev_land = r.world.land.duplicate()
	r.prev_trail = r.world.trail.duplicate()
	r.events.clear()
	r.joined.clear()
	r.left.clear()
	# Everyone in the room is back in: bots make way, and each person starts when they tap Play
	for peer in r.peers:
		var entry: Dictionary = r.peers[peer]
		var p: Player = r.world.add_human(entry.info.name, entry.info.color, entry.info)
		entry.player = p
		if p:
			p.alive = false
			_clear_player_cells(r, p)
	for peer in r.peers:
		_send_round(r, peer)


## A person starts out of the game until they tap Play (their starting patch goes)
## The bots' skill follows the people in the room: newcomers meet mostly rookies, high levels
## mostly pros. It applies to bots that join from now on (and to the next round's).
func _match_bots(r: Room) -> void:
	var total := 0
	for peer in r.peers:
		total += int(r.peers[peer].info.get("level", 1))
	var avg := float(total) / r.peers.size() if r.peers.size() > 0 else 1.0
	r.world.skill_mix = r.world.skill_mix_for_level(avg)


func _clear_player_cells(r: Room, p: Player) -> void:
	var w = r.world
	for i in w.N * w.N:
		if w.land[i] == p.id:
			w.set_land(i, 0)
	w.land_version += 1


func _refill(r: Room) -> Array:
	var before := {}
	for p in r.world.players:
		if p:
			before[p.id] = true
	r.world.fill_with_bots()
	var added := []
	for p in r.world.players:
		if p and not before.has(p.id):
			added.append(p)
	return added


func _connect_events(r: Room) -> void:
	var w = r.world
	var ev: Array = r.events
	w.captured.connect(func(p, cells, gain): ev.append(["cap", p.id, cells, gain]))
	w.knocked_out.connect(func(v, k, how, _lost): ev.append(["ko", v.id, k.id if k else 0, how]))
	w.spawned.connect(func(p): ev.append(["spawn", p.id]))
	w.picked.connect(func(p, kind, at): ev.append(["pick", p.id, kind, at.x, at.y]))
	w.painted.connect(func(p, cells): ev.append(["paint", p.id, cells]))
	w.coin_taken.connect(func(p, at): ev.append(["coin", p.id, at.x, at.y]))
	w.teleported.connect(func(p, a, b): ev.append(["tele", p.id, a.x, a.y, b.x, b.y]))
	w.storm_coming.connect(func(rad): ev.append(["stormc", rad]))
	w.storm_hit.connect(func(rad): ev.append(["stormh", rad]))
	w.bumped.connect(func(p, at): ev.append(["bump", p.id, at.x, at.y]))


func _roster(r: Room) -> Array:
	var out := []
	for p in r.world.players:
		if p:
			out.append(NetCodec.info(p))
	return out


func _send_round(r: Room, peer: int) -> void:
	var w = r.world
	var me: Player = r.peers[peer].get("player")
	# The board as of the last snapshot (not as it is now): the next snapshot lists the changes
	# since then, so a cell that changed and changed back in between still comes out right
	net.s_round.rpc_id(peer, {
		"round": r.round_no, "map": w.map_id, "walls": w.wall, "land": r.prev_land, "trail": r.prev_trail,
		"players": _roster(r), "you": me.id if me else 0, "states": NetCodec.states(w.players),
		"storm": [w.storm_r, w.storm_next], "limit": ROUND_TIME, "time": w.time,
	})


# ---------- Messages from phones ----------

func on_join(peer: int, info: Dictionary) -> void:
	if _by_peer.has(peer):
		return
	if int(info.get("v", 0)) != net.PROTOCOL:
		net.s_error.rpc_id(peer, {"code": "version"})
		return
	var r := _pick_room()
	if r == null:
		net.s_error.rpc_id(peer, {"code": "full"})
		return
	var clean := {
		"name": NetCodec.clean_name(str(info.get("name", "Player"))),
		"color": clampi(int(info.get("color", 0)), 0, 7),
		"skin": str(info.get("skin", "plain")), "trail": str(info.get("trail", "none")), "pet": str(info.get("pet", "none")),
		"level": clampi(int(info.get("level", 1)), 1, 999),
	}
	for k in [["skin", "skin"], ["trail", "trail"], ["pet", "pet"]]:
		if not Cosmetics.items(k[1]).has(clean[k[0]]):
			clean[k[0]] = Cosmetics.KINDS[k[1]].free
	var entry := {"info": clean}
	r.peers[peer] = entry
	_by_peer[peer] = r
	r.empty_for = 0.0
	_match_bots(r)
	net.s_welcome.rpc_id(peer, {"v": net.PROTOCOL, "room": r.id})
	if not r.over:
		var removed := []
		for p in r.world.players:
			if p:
				removed.append(p.id)
		var p: Player = r.world.add_human(clean.name, clean.color, clean)
		entry.player = p
		if p:
			p.alive = false # in when they tap Play
			_clear_player_cells(r, p)
			# Whoever the new player replaced has gone
			for id in removed:
				if r.world.players.size() <= id or r.world.players[id] == null:
					r.left.append(id)
			r.joined.append(NetCodec.info(p))
		_send_round(r, peer)
	_log("peer %d joined room %d (%d people)" % [peer, r.id, r.peers.size()]) # (no names in the log)


func on_input(peer: int, angle: float) -> void:
	var r: Room = _by_peer.get(peer)
	if r == null or not r.peers[peer].has("player") or r.peers[peer].player == null:
		return
	if is_finite(angle):
		r.peers[peer].player.desired = wrapf(angle, -PI, PI)


func on_respawn(peer: int, _x) -> void:
	var r: Room = _by_peer.get(peer)
	if r == null or r.over:
		return
	var p: Player = r.peers[peer].get("player")
	if p and not p.alive:
		p.kills = 0
		r.world.spawn(p)


# ---------- The game ----------

func _physics_process(delta: float) -> void:
	_report += delta
	if _report >= 30.0:
		if _snap_count > 0:
			_log("%d rooms, %d people, %.1f KB/s per phone (%d bytes a snapshot)" % [rooms.size(), _by_peer.size(),
				float(_bytes) / _snap_count * 15.0 / 1024.0, _bytes / _snap_count])
		_report = 0.0
		_bytes = 0
		_snap_count = 0
	_acc += delta
	var steps := 0
	while _acc >= TICK and steps < 5:
		_acc -= TICK
		steps += 1
		for r in rooms.duplicate():
			_step(r)


func _step(r: Room) -> void:
	var w = r.world
	if r.peers.is_empty():
		r.empty_for += TICK
		if r.empty_for > EMPTY_ROOM_LIFE:
			_close_room(r)
		return
	if r.over:
		r.break_left -= TICK
		if r.break_left <= 0:
			_start_round(r)
		return
	w.update(TICK)
	r.tick += 1
	_check_round_end(r)
	if r.tick % SNAP_EVERY == 0 or r.over:
		_send_snap(r)


func _check_round_end(r: Room) -> void:
	var w = r.world
	var winner: Player = null
	for p in w.players:
		if p and p.alive and w.pct(p) >= w.WIN_PCT:
			winner = p
	var timeout: bool = w.time >= ROUND_TIME
	if winner == null and not timeout:
		return
	if winner == null:
		for p in w.players:
			if p and p.alive and (winner == null or w.counts[p.id] > w.counts[winner.id]):
				winner = p
	r.over = true
	r.break_left = BREAK_TIME
	_log("room %d round %d won by %s%s" % [r.id, r.round_no, winner.name if winner else "nobody", " (time)" if timeout else ""])
	_send_snap(r) # the final state first
	var d := {"winner": winner.id if winner else 0, "name": winner.name if winner else "", "timeout": timeout,
		"next": MAPS[r.map_index % MAPS.size()], "in": BREAK_TIME}
	for peer in r.peers:
		net.s_round_over.rpc_id(peer, d)


func _send_snap(r: Room) -> void:
	var w = r.world
	var saws := PackedFloat32Array()
	for s in w.saws:
		saws.append_array([s.pos.x, s.pos.y, s.spin])
	var flashes := PackedFloat32Array()
	for b in w.bumpers:
		flashes.append(b.flash)
	var items := PackedFloat32Array()
	for pu in w.powerups:
		items.append_array([pu.pos.x, pu.pos.y, w.POWERUPS.keys().find(pu.kind), pu.age])
	var coins := PackedFloat32Array()
	for c in w.coins:
		coins.append_array([c.pos.x, c.pos.y, c.age, c.life])
	var snap := {
		"t": w.time, "p": NetCodec.states(w.players),
		"l": NetCodec.diff(w.land, r.prev_land), "tr": NetCodec.diff(w.trail, r.prev_trail),
		"pu": items, "co": coins, "saws": saws, "bump": flashes, "storm": [w.storm_r, w.storm_next],
		"ev": r.events.duplicate(), "join": r.joined.duplicate(), "left": r.left.duplicate(),
		"freezer": w.freezer.id if w.freezer else 0,
		"h": hash(w.land) ^ hash(w.trail), # the phone checks its board against this
	}
	r.events.clear()
	r.joined.clear()
	r.left.clear()
	# The size, for the log, measured on every 10th snapshot only (it costs a little)
	if r.tick % (SNAP_EVERY * 10) == 0:
		_bytes += var_to_bytes(snap).size() * r.peers.size()
		_snap_count += r.peers.size()
	for peer in r.peers:
		net.s_snap.rpc_id(peer, snap)
