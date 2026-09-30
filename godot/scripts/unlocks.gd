class_name Unlocks
extends RefCounted
## Modes and maps open up as you level up, so a new player starts simple (Classic on the
## Square) and something new arrives every level or two.

## The level each mode opens at
const MODE_LEVEL := {
	"classic": 1, "online": 2, "timed": 3, "duo": 3, "teams": 4, "daily": 5, "hill": 6, "boss": 8,
}

## The level each map opens at
const MAP_LEVEL := {
	"square": 1, "round": 1, "pillars": 2, "maze": 3, "islands": 4, "saws": 5, "ice": 6,
	"conveyor": 7, "portals": 8, "bumpers": 9, "storm": 10,
}


static func mode_level(id: String) -> int:
	return MODE_LEVEL.get(id, 1)


static func map_level(id: String) -> int:
	return MAP_LEVEL.get(id, 1)


static func mode_open(id: String, level: int) -> bool:
	return level >= mode_level(id)


static func map_open(id: String, level: int) -> bool:
	return level >= map_level(id)


## What opened up going from `from` to `to` (exclusive, inclusive): [["mode", id], ["map", id], ...]
static func opened_between(from: int, to: int) -> Array:
	var out := []
	for id in MODE_LEVEL:
		if MODE_LEVEL[id] > from and MODE_LEVEL[id] <= to:
			out.append(["mode", id])
	for id in MAP_LEVEL:
		if MAP_LEVEL[id] > from and MAP_LEVEL[id] <= to:
			out.append(["map", id])
	return out


## The next thing to unlock after `level`: [level, kind, id], or [] when everything is open
static func next_after(level: int) -> Array:
	var best := []
	for kind in ["mode", "map"]:
		var table: Dictionary = MODE_LEVEL if kind == "mode" else MAP_LEVEL
		for id in table:
			if table[id] > level and (best.is_empty() or table[id] < best[0]):
				best = [table[id], kind, id]
	return best
