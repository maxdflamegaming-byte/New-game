class_name NetCodec
extends RefCounted
## How players and their state are packed into messages, shared by the server and the phone.

## Floats per player in a snapshot: id, x, y, angle, alive, shield, speed, ghost, freeze, kills
const STRIDE := 10


## Who a player is (sent when they appear)
static func info(p: Player) -> Dictionary:
	return {"id": p.id, "name": p.name, "color": p.color.to_html(false), "bot": p.is_bot,
		"skin": p.skin, "trail": p.trail_fx, "pet": p.pet, "skill": p.skill}


static func from_info(d: Dictionary) -> Player:
	var p := Player.new(int(d.get("id", 1)), str(d.get("name", "?")).left(16), Color(str(d.get("color", "ffffff"))), bool(d.get("bot", true)))
	for k in ["skin", "trail", "pet"]:
		var kind: String = {"skin": "skin", "trail": "trail", "pet": "pet"}[k]
		var v := str(d.get(k, Cosmetics.KINDS[kind].free))
		if not Cosmetics.items(kind).has(v):
			v = Cosmetics.KINDS[kind].free
		match k:
			"skin":
				p.skin = v
			"trail":
				p.trail_fx = v
			"pet":
				p.pet = v
	var skill := str(d.get("skill", ""))
	p.skill = skill if skill == "rookie" or skill == "regular" or skill == "pro" else ""
	p.team = p.id
	return p


## Everyone's position and state
static func states(players: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in players:
		if p == null:
			continue
		out.append_array([p.id, p.pos.x, p.pos.y, p.angle, 1.0 if p.alive else 0.0, p.shield,
			p.fx.speed, p.fx.ghost, p.fx.freeze, p.kills])
	return out


## Cells that differ between `now` and `before`, as [index, value, index, value, ...];
## `before` is updated to match
static func diff(now: PackedByteArray, before: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	# Most of the board doesn't change between snapshots: compare it in blocks (fast, done by
	# the engine) and only look cell by cell inside the blocks that differ
	var block := 256
	for start in range(0, now.size(), block):
		var end := mini(start + block, now.size())
		if now.slice(start, end) == before.slice(start, end):
			continue
		for i in range(start, end):
			if now[i] != before[i]:
				out.append(i)
				out.append(now[i])
				before[i] = now[i]
	return out


## Cleans up a name typed by a player: printable, short, and not empty
static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "%":
			out += ch
	out = out.left(12).strip_edges()
	for bad in BLOCKED:
		if out.to_lower().contains(bad):
			return "Player"
	return out if out != "" else "Player"


## A few words that never appear in names others can see
const BLOCKED := ["fuck", "shit", "bitch", "cunt", "nigg", "fag", "rape", "nazi", "hitler", "porn", "sex", "dick", "pussy", "whore", "slut"]
