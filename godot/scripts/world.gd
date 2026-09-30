extends Node
## The board and its rules: maps, movement, trails, capturing land, knockouts, bumps,
## power-ups and coins. Positions are in cells (a player at (10.5, 3.5) is in the middle of
## cell 10, 3).

signal captured(p: Player, cells: PackedInt32Array, gain_pct: float)
signal knocked_out(victim: Player, killer: Player, how: String, lost: PackedInt32Array)
signal spawned(p: Player)
signal picked(p: Player, kind: String, at: Vector2)
signal painted(p: Player, cells: PackedInt32Array)
signal coin_taken(p: Player, at: Vector2)
signal boss_hit(king: Player, by: Player)
signal guards_called(king: Player)
signal teleported(p: Player, from: Vector2, to: Vector2)
signal storm_coming(radius: float)
signal storm_hit(radius: float)
signal trap_dropped(boss: Player, at: Vector2)
signal blinked(boss: Player, from: Vector2, to: Vector2)
signal bumped(p: Player, at: Vector2)

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
const MORE_NAMES := ["Nova", "Dash", "Kiwi", "Pogo", "Mochi", "Ziggy", "Blip", "Rocket"] # online rooms need a few more

const MODES := {
	"classic": {"name": "Classic", "desc": "Claim 50% of the map to win", "win": 50.0},
	"timed": {"name": "Timed", "desc": "Be the biggest when the 3:00 clock runs out", "time": 180.0},
	"daily": {"name": "Daily", "desc": "Today's map and start, the same for everyone · claim 50%", "win": 50.0, "daily": true},
	"teams": {"name": "Teams", "desc": "You + 3 bots vs 4 bots · first team to 50% wins", "win": 50.0, "teams": true},
	"boss": {"name": "Boss", "desc": "Cut the King's trail to knock off his hearts · you have 3 lives", "boss": true},
	"duo": {"name": "2 Players", "desc": "Two players on one screen · first to 40% wins", "win": 40.0, "duo": true},
	"hill": {"name": "King of the Hill", "desc": "Own land on the glowing hill to score · first to 100 points wins", "hill": true, "goal": 100.0, "limit": 240.0},
	"online": {"name": "Online", "desc": "Play people from around the world · claim 50% to win the round", "win": 50.0, "online": true},
	"tutorial": {"name": "Tutorial", "desc": "Learn to play in 5 quick steps", "win": 15.0, "tutorial": true, "hidden": true},
}

## Bot difficulty: how fast and bold the bots are, and how much a game pays
const DIFFICULTY := {
	"easy": {"name": "Easy", "speed": 0.9, "coins": 0.75},
	"normal": {"name": "Normal", "speed": 1.0, "coins": 1.0},
	"hard": {"name": "Hard", "speed": 1.08, "coins": 1.5},
}
const KING_HEARTS := 5
## How many rookie, regular and pro bots each difficulty brings (chances)
const SKILL_MIX := {"easy": [0.5, 0.4, 0.1], "normal": [0.25, 0.5, 0.25], "hard": [0.1, 0.4, 0.5]}

const MAPS := {
	"square": "Square", "round": "Round", "pillars": "Pillars", "maze": "Maze", "islands": "Islands",
	"saws": "Saw Mill", "storm": "Storm", "conveyor": "Conveyor", "portals": "Portals",
	"ice": "Ice Rink", "bumpers": "Pinball",
}

## The Boss Battle's bosses: beat one to unlock the next
const BOSSES := {
	"king": {"name": "King", "color": "#3b3f58", "hearts": 5, "bonus": 100},
	"queen": {"name": "Queen", "color": "#8e2f6b", "hearts": 6, "bonus": 150},
	"wizard": {"name": "Wizard", "color": "#3d2a7a", "hearts": 7, "bonus": 200},
}

# Hazard maps
const BELT_SPEED := 3.5 # cells per second a conveyor belt carries you
const BELT_DIRS := [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
const STORM_FIRST := 40.0 # seconds before the storm first closes in
const STORM_EVERY := 25.0
const STORM_WARN := 5.0 # the next ring shows this long before it closes
const STORM_STEP := 7.0 # cells it closes in each time
const STORM_MIN := 13.0
const SAW_SPEED := 4.5
const ICE_TURN := 0.4 # on ice you turn this much slower...
const ICE_SPEED := 1.15 # ...and slide this much faster
const BUMPER_R := 1.7 # a Pinball bumper's radius, in cells
const HILL_R := 9.0 # King of the Hill: the hill's radius
const HILL_RATE := 6.5 # points a second for owning all of the hill

## Power-ups appear on the map; anyone (bots too) can grab them
const POWERUPS := {
	"speed": {"name": "Speed", "time": 4.0, "color": Color("#ffb84d")},
	"shield": {"name": "Shield", "time": 6.0, "color": Color("#4f8cff")},
	"freeze": {"name": "Freeze", "time": 4.0, "color": Color("#3fc7f5")},
	"ghost": {"name": "Ghost", "time": 5.0, "color": Color("#8d7bd6")},
	"paint": {"name": "Paint Bomb", "time": 0.0, "color": Color("#ff5d9e")},
}
const MAX_POWERUPS := 4
const MAX_COINS := 6
const COIN_VALUE := 2

var map_id := "square"
var mode_id := "classic"
var mode: Dictionary = MODES.classic
var p2: Player # the second human in 2 Players
var king: Player # the Boss Battle's King
var land := PackedByteArray() # who owns each cell (0 = nobody)
var trail := PackedByteArray() # whose trail is on each cell (0 = none)
var wall := PackedByteArray() # 0 floor, 1 pillar or wall, 2 outside the arena or water
var counts := PackedInt32Array() # cells owned, per player id
var play_cells := N * N
var players: Array = [] # players[id]; players[0] is null
var me: Player
var bots
var time := 0.0
var won := false
var land_version := 0 # goes up whenever land changes, so the view knows to redraw
var map_version := 0 # goes up when a new map is built

var powerups: Array = [] # {pos, kind, age}
var coins: Array = [] # {pos, age, life}
var freezer: Player = null # whoever has Freeze running
var coins_picked := 0 # by you, this game
var looks := {} # your skin, trail and pet from the shop
var difficulty := "normal"
## Online rooms set their own mix of bot skills to match the people in them (empty: use
## the difficulty's)
var skill_mix: Array = []
var boss_kind := "king" # which boss the Boss Battle brings
var event := "" # this week's event (see Events), for everything but the tutorial and the menu
var portals := [] # [[a, b], ...]: step into one end and pop out of the other
var saws := [] # {corners, d, speed, pos, spin}: blades running round their tracks
var belt := PackedByteArray() # per cell: 0 none, else an index into BELT_DIRS
var avoid := PackedByteArray() # cells bots keep out of (portals)
var tracks := PackedByteArray() # cells next to a saw's track: bots don't plan loops across them
var storm_r := 0.0 # the storm's safe circle (0 = no storm)
var storm_next := 0.0 # where it closes in to next (while the warning shows)
var storm_timer := 0.0
var traps := [] # {pos, life, owner}: the Queen's spiky traps
var ice := PackedByteArray() # Ice Rink: 1 where the floor is ice
var bumpers := [] # Pinball: {pos, flash}
var hill_r := 0.0 # King of the Hill: the hill's radius (0 = no hill)
var hill_cells := PackedInt32Array()
var points := {} # King of the Hill: player id -> points

var _setting_up := false # no spawn events while a game is being set up
var _power_timer := 3.0
var _coin_timer := 3.0
var _seen := PackedByteArray()
var _stack := PackedInt32Array()


func _init() -> void:
	bots = preload("res://scripts/bots.gd").new(self)
	land.resize(N * N)
	trail.resize(N * N)
	wall.resize(N * N)
	belt.resize(N * N)
	avoid.resize(N * N)
	tracks.resize(N * N)
	ice.resize(N * N)
	_seen.resize(N * N)
	_stack.resize(N * N)
	counts.resize(16)


# ---------- Online rooms ----------
# On the server a room is a World with no local player: people join and leave mid-game, and
# bots fill the empty places. On a phone playing online, the World only mirrors what the
# server sends (see scripts/net/): nothing is simulated there.

const ROOM_SIZE := 8

var online := false # an online room (server) or a mirror of one (phone)


## A server room: bots only for now, on `map`; people are added with add_human()
func setup_room(map: String) -> void:
	_setting_up = true
	online = true
	mode_id = "online"
	mode = MODES.online
	map_id = map if MAPS.has(map) else "square"
	event = ""
	land.fill(0)
	trail.fill(0)
	counts.fill(0)
	_build_map()
	_build_hill()
	time = 0.0
	won = false
	land_version += 1
	powerups.clear()
	coins.clear()
	traps.clear()
	freezer = null
	coins_picked = 0
	_power_timer = 3.0
	_coin_timer = 3.0
	players = [null]
	me = null
	p2 = null
	king = null
	for i in ROOM_SIZE:
		_add_bot()
	_setting_up = false


## The lowest free player id (ids index `players`; 0 is never used)
func _free_id() -> int:
	for i in range(1, players.size()):
		if players[i] == null:
			return i
	return players.size() if players.size() < 16 else -1


func _free_color(wanted := -1) -> Color:
	var used := []
	for p in players:
		if p:
			used.append(p.color)
	if wanted >= 0 and wanted < COLORS.size() and not used.has(COLORS[wanted]):
		return COLORS[wanted]
	for c in COLORS:
		if not used.has(c):
			return c
	return COLORS[randi() % COLORS.size()]


func _put(p: Player) -> void:
	if p.id >= players.size():
		players.resize(p.id + 1)
	players[p.id] = p


func _add_bot() -> Player:
	var id := _free_id()
	if id < 0:
		return null
	var names := BOT_NAMES + MORE_NAMES
	for p in players:
		if p:
			names.erase(p.name)
	var b := Player.new(id, names.pick_random() if not names.is_empty() else "Bot", _free_color(), true)
	bots.give_personality(b, bots.PERSONA_MIX.pick_random())
	_tune(b)
	bots.give_skill(b, pick_skill())
	Cosmetics.dress_bot(b)
	b.team = b.id
	_put(b)
	spawn(b)
	return b


func humans_in_room() -> int:
	var n := 0
	for p in players:
		if p and not p.is_bot:
			n += 1
	return n


## Someone joins: a bot makes room for them. Returns their player, or null if the room's full.
func add_human(p_name: String, color_idx: int, looks_in: Dictionary) -> Player:
	if humans_in_room() >= ROOM_SIZE:
		return null
	var count := 0
	for p in players:
		if p:
			count += 1
	if count >= ROOM_SIZE:
		for p in players:
			if p and p.is_bot:
				remove_player(p)
				break
	var id := _free_id()
	var h := Player.new(id, p_name, _free_color(color_idx), false)
	h.skin = looks_in.get("skin", "plain")
	h.trail_fx = looks_in.get("trail", "none")
	h.pet = looks_in.get("pet", "none")
	h.team = h.id
	_put(h)
	spawn(h)
	return h


## Someone leaves (or a bot makes room): their land and trail go, and a bot may come back
func remove_player(p: Player) -> void:
	for i in N * N:
		if trail[i] == p.id:
			trail[i] = 0
		if land[i] == p.id:
			set_land(i, 0)
	land_version += 1
	p.alive = false
	players[p.id] = null
	if freezer == p:
		freezer = null


## Keeps the room at ROOM_SIZE players by adding bots
func fill_with_bots() -> void:
	var count := 0
	for p in players:
		if p:
			count += 1
	while count < ROOM_SIZE:
		if _add_bot() == null:
			break
		count += 1


## A phone playing online: the board from the server (its walls, since the Maze is random),
## with nothing simulated here
func setup_mirror(map: String, walls: PackedByteArray) -> void:
	online = true
	mode_id = "online"
	mode = MODES.online
	map_id = map if MAPS.has(map) else "square"
	event = ""
	land.fill(0)
	trail.fill(0)
	counts.fill(0)
	_build_map()
	if walls.size() == N * N:
		wall = walls
		play_cells = 0
		for i in N * N:
			if wall[i] == 0:
				play_cells += 1
		map_version += 1
	land_version += 1
	powerups.clear()
	coins.clear()
	traps.clear()
	freezer = null
	players = [null]
	me = null
	p2 = null
	king = null


## Today's date, which picks the Daily map and start
static func today() -> String:
	return Time.get_date_string_from_system()


## A new game of mode `mode_name` on map `map`: you (a bot too if demo is true) and bots
## with personalities
func setup(my_color: int, my_name: String, demo := false, map := "square", mode_name := "classic") -> void:
	_setting_up = true
	online = false
	mode_id = mode_name if MODES.has(mode_name) else "classic"
	mode = MODES[mode_id]
	map_id = map if MAPS.has(map) else "square"
	if mode.get("tutorial", false):
		map_id = "square" # the tutorial is always on the plain map
	# Daily: the date picks the map and seeds the start, so it's the same for everyone today
	if mode.get("daily", false):
		var h := today().hash()
		seed(h)
		map_id = MAPS.keys()[absi(h) % MAPS.size()]
	land.fill(0)
	trail.fill(0)
	counts.fill(0)
	_build_map()
	_build_hill()
	time = 0.0
	won = false
	land_version += 1
	powerups.clear()
	coins.clear()
	traps.clear()
	freezer = null
	coins_picked = 0
	_power_timer = 3.0
	_coin_timer = 3.0
	players = [null]
	p2 = null
	king = null
	var duo: bool = mode.get("duo", false)
	me = Player.new(1, (my_name if my_name != "" else "You") if not duo else "Player 1", COLORS[my_color], demo)
	players.append(me)
	me.skin = looks.get("skin", "plain")
	me.trail_fx = looks.get("trail", "none")
	me.pet = looks.get("pet", "none")
	var taken := [my_color]
	if duo:
		var c2 := (my_color + 4) % COLORS.size()
		taken.append(c2)
		p2 = Player.new(2, "Player 2", COLORS[c2], false)
		Cosmetics.dress_bot(p2)
		players.append(p2)
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var others: Array[Color] = []
	for i in COLORS.size():
		if not taken.has(i):
			others.append(COLORS[i])
	var mix: Array = bots.PERSONA_MIX.duplicate()
	mix.shuffle()
	var tutorial: bool = mode.get("tutorial", false)
	var bot_count := 0 if mode.get("boss", false) else 1 if tutorial else 8 - players.size() + 1
	for i in bot_count:
		var b := Player.new(players.size(), names[i] if not tutorial else "Coach", others[i], true)
		bots.give_personality(b, mix[i])
		_tune(b)
		if not tutorial:
			bots.give_skill(b, pick_skill())
		Cosmetics.dress_bot(b)
		players.append(b)
	if tutorial:
		# A slow, harmless practice bot that makes long loops, so its trail is easy to cut
		var coach: Player = players[players.size() - 1]
		bots.give_personality(coach, "explorer")
		coach.harmless = true
		coach.aggro = 0.0
		coach.flee = 0.0
		coach.grab_chance = 0.0
		coach.greed = 34
		coach.loop_scale = 1.3
		me.lives = 999
		_power_timer = INF # the tutorial places its own power-up
		_coin_timer = INF
	if demo:
		bots.give_personality(me, "wildcard")
	# Teams: you and the first 3 bots against the other 4
	for p in players:
		if p:
			p.team = (0 if p.id <= 4 else 1) if mode.get("teams", false) else p.id
	if duo:
		spawn(me, roundi(N * 0.3), N / 2)
		spawn(p2, roundi(N * 0.7), N / 2)
	else:
		spawn(me, N / 2, N / 2)
	for p in players:
		if p and p.is_bot and p != me:
			spawn(p)
	if mode.get("boss", false):
		me.lives = 3
		_spawn_king()
	_setting_up = false
	if mode.get("daily", false):
		randomize() # only the start is the same for everyone


func pct(p: Player) -> float:
	return counts[p.id] * 100.0 / play_cells


## In Teams, teammates can't cut, bump or steal from each other
func allies(a: Player, b: Player) -> bool:
	return a == b or (mode.get("teams", false) and a.team == b.team)


func team_pct(team: int) -> float:
	var total := 0
	for p in players:
		if p and p.team == team:
			total += counts[p.id]
	return total * 100.0 / play_cells


## The humans in this game (you, and Player 2 in 2 Players)
func humans() -> Array:
	return [me, p2] if p2 else [me]


func set_land(i: int, id: int) -> void:
	var prev := land[i]
	if prev == id:
		return
	if prev:
		counts[prev] -= 1
	land[i] = id
	if id:
		counts[id] += 1


# ---------- Maps ----------

func _build_map() -> void:
	wall.fill(0)
	belt.fill(0)
	avoid.fill(0)
	tracks.fill(0)
	ice.fill(0)
	bumpers.clear()
	portals.clear()
	saws.clear()
	storm_r = 0.0
	storm_next = 0.0
	var c := N / 2.0
	match map_id:
		"saws":
			# Four blades running round square tracks, one in each corner of the map
			var q := [[0.11, 0.11], [0.61, 0.11], [0.11, 0.61], [0.61, 0.61]]
			for k in 4:
				var a := Vector2(roundi(N * q[k][0]), roundi(N * q[k][1])) + Vector2(0.5, 0.5)
				var s := roundi(N * 0.28)
				var corners := [a, a + Vector2(s, 0), a + Vector2(s, s), a + Vector2(0, s)]
				saws.append({"corners": corners, "d": k * 22.0, "speed": SAW_SPEED * (1 if k % 2 == 0 else -1), "pos": a, "spin": 0.0})
				for e in 4:
					var from: Vector2 = corners[e]
					var to: Vector2 = corners[(e + 1) % 4]
					for t in int(from.distance_to(to)) + 1:
						var pt := from.move_toward(to, t)
						for oy in range(-1, 2):
							for ox in range(-1, 2):
								var x := int(pt.x) + ox
								var y := int(pt.y) + oy
								if x >= 0 and y >= 0 and x < N and y < N:
									tracks[y * N + x] = 1
		"storm":
			storm_r = N * 0.75
			storm_timer = STORM_FIRST
		"conveyor":
			# Two belts across and two down, each three cells wide
			for y in range(roundi(N * 0.19), roundi(N * 0.19) + 3):
				for x in range(8, N - 8):
					belt[y * N + x] = 1
			for y in range(roundi(N * 0.78), roundi(N * 0.78) + 3):
				for x in range(8, N - 8):
					belt[y * N + x] = 2
			for x in range(roundi(N * 0.19), roundi(N * 0.19) + 3):
				for y in range(roundi(N * 0.28), roundi(N * 0.72)):
					belt[y * N + x] = 3
			for x in range(roundi(N * 0.78), roundi(N * 0.78) + 3):
				for y in range(roundi(N * 0.28), roundi(N * 0.72)):
					belt[y * N + x] = 4
		"portals":
			var f := func(fx: float, fy: float) -> Vector2: return Vector2(roundi(N * fx) + 0.5, roundi(N * fy) + 0.5)
			portals = [[f.call(0.18, 0.18), f.call(0.82, 0.82)], [f.call(0.82, 0.18), f.call(0.18, 0.82)], [f.call(0.5, 0.13), f.call(0.5, 0.87)]]
			for pair in portals:
				for end in pair:
					for y in range(int(end.y) - 2, int(end.y) + 3):
						for x in range(int(end.x) - 2, int(end.x) + 3):
							if x >= 0 and y >= 0 and x < N and y < N and Vector2(x + 0.5, y + 0.5).distance_to(end) < 2.2:
								avoid[y * N + x] = 1
		"ice":
			# Patches of ice: turning is slow and sliding is fast
			var patches := [[0.26, 0.26, 0.13], [0.74, 0.26, 0.13], [0.26, 0.74, 0.13], [0.74, 0.74, 0.13], [0.5, 0.14, 0.08], [0.5, 0.86, 0.08]]
			for pa in patches:
				var pc := Vector2(N * pa[0], N * pa[1])
				var pr: float = N * pa[2]
				for y in N:
					for x in N:
						var d := Vector2(x + 0.5, y + 0.5) - pc
						if Vector2(d.x, d.y * 1.25).length() <= pr:
							ice[y * N + x] = 1
		"bumpers":
			# Round bumpers that bounce you away, in a ring and by the corners
			var spots := []
			for k in 6:
				spots.append(Vector2(c, c) + Vector2.from_angle(k * TAU / 6 + PI / 6) * N * 0.3)
			for q in [Vector2(0.14, 0.14), Vector2(0.86, 0.14), Vector2(0.14, 0.86), Vector2(0.86, 0.86)]:
				spots.append(q * N)
			for q in spots:
				var at := Vector2(roundi(q.x) + 0.5, roundi(q.y) + 0.5)
				bumpers.append({"pos": at, "flash": 0.0})
				for y in range(int(at.y) - 4, int(at.y) + 5):
					for x in range(int(at.x) - 4, int(at.x) + 5):
						if x < 0 or y < 0 or x >= N or y >= N:
							continue
						var d := Vector2(x + 0.5, y + 0.5).distance_to(at)
						if d < BUMPER_R - 0.5:
							wall[y * N + x] = 1 # the bumper itself
						elif d < BUMPER_R + 2.0:
							avoid[y * N + x] = 1 # bots plan round it
		"round":
			var r := N / 2.0 - 1
			for y in N:
				for x in N:
					if Vector2(x - (N - 1) / 2.0, y - (N - 1) / 2.0).length() > r:
						wall[y * N + x] = 2
		"pillars":
			var s := roundi(N * 0.07)
			for fx in [0.22, 0.5, 0.78]:
				for fy in [0.22, 0.5, 0.78]:
					if fx == 0.5 and fy == 0.5:
						continue # keep the middle free for your start
					var x0 := roundi(N * fx - s / 2.0)
					var y0 := roundi(N * fy - s / 2.0)
					for y in range(y0, y0 + s):
						for x in range(x0, x0 + s):
							wall[y * N + x] = 1
		"maze":
			# Blocks with a wall on their top or left edge, each with a gap to get through
			var g := roundi(N / 8.0)
			for by in range(0, N, g):
				for bx in range(0, N, g):
					var top := randf() < 0.5
					if (top and by == 0) or (not top and bx == 0):
						continue # leave the outer edge open
					var gap := 2 + randi() % (g - 6)
					for k in g:
						if k >= gap and k < gap + 4:
							continue
						var x := bx + k if top else bx
						var y := by if top else by + k
						if x < N and y < N and Vector2(x - c, y - c).length() > 8:
							wall[y * N + x] = 1
		"islands":
			# A central island and a ring of six, joined by bridges, with water between
			wall.fill(2)
			var isles := [[Vector2(c, c), N * 0.16]]
			for k in 6:
				var a := k / 6.0 * TAU + 0.3
				isles.append([Vector2(c, c) + Vector2.from_angle(a) * N * 0.33, N * 0.13])
			var bridges := []
			for k in range(1, 7):
				bridges.append([isles[0][0], isles[k][0]])
				bridges.append([isles[k][0], isles[k % 6 + 1][0]])
			for y in N:
				for x in N:
					var q := Vector2(x, y)
					var is_land := false
					for isle in isles:
						if q.distance_to(isle[0]) <= isle[1]:
							is_land = true
							break
					if not is_land:
						for b in bridges:
							if Geometry2D.get_closest_point_to_segment(q, b[0], b[1]).distance_to(q) <= 2.2:
								is_land = true
								break
					if is_land:
						wall[y * N + x] = 0
	play_cells = 0
	for i in N * N:
		if wall[i] == 0:
			play_cells += 1
	map_version += 1


func is_wall_at(x: float, y: float) -> bool:
	if x < 0 or y < 0 or x >= N or y >= N:
		return true
	return wall[int(y) * N + int(x)] != 0


# ---------- Spawning ----------

## Cells in the small starting patch around (x, y) that are open ground nobody owns
func free_start_cells(x: int, y: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cx := x + dx
			var cy := y + dy
			if dx * dx + dy * dy > 7 or cx < 0 or cy < 0 or cx >= N or cy >= N:
				continue
			var i := cy * N + cx
			if land[i] == 0 and trail[i] == 0 and wall[i] == 0:
				cells.append(i)
	return cells


## King of the Hill: the hill in the middle of the map, and everyone's points at 0
func _build_hill() -> void:
	hill_cells = PackedInt32Array()
	points = {}
	hill_r = HILL_R if mode.get("hill", false) else 0.0
	if hill_r <= 0:
		return
	var c := center()
	for y in N:
		for x in N:
			if wall[y * N + x] == 0 and Vector2(x + 0.5, y + 0.5).distance_to(c) <= hill_r:
				hill_cells.append(y * N + x)


## Points for owning the hill: your share of it, every second
func _score_hill(dt: float) -> void:
	if hill_cells.is_empty():
		return
	var owned := {}
	for i in hill_cells:
		var id := land[i]
		if id:
			owned[id] = owned.get(id, 0) + 1
	for id in owned:
		var p: Player = players[id]
		if p and p.alive:
			points[id] = points.get(id, 0.0) + HILL_RATE * owned[id] / float(hill_cells.size()) * dt


## Whoever has the most hill points (or null before anyone scores)
func hill_leader() -> Player:
	var best: Player = null
	for p in players:
		if p and points.get(p.id, 0.0) > (points.get(best.id, 0.0) if best else 0.0):
			best = p
	return best


func on_ice(x: float, y: float) -> bool:
	if x < 0 or y < 0 or x >= N or y >= N:
		return false
	return ice[int(y) * N + int(x)] == 1


## How fast a square can turn where it is (slower on ice)
func turn_rate(x: float, y: float) -> float:
	return TURN * (ICE_TURN if on_ice(x, y) else 1.0)


## The nearest spot to (x, y) with room for a full starting patch
func open_spot_near(x: int, y: int) -> Vector2i:
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := x + dx
				var cy := y + dy
				if cx < 4 or cy < 4 or cx > N - 5 or cy > N - 5 or wall[cy * N + cx]:
					continue
				if free_start_cells(cx, cy).size() >= 13:
					return Vector2i(cx, cy)
	return Vector2i(x, y)


## Puts a player on the map with a small patch of land. Returns false if there's no room
## right now (bots then try again a moment later).
func spawn(p: Player, fx := -1, fy := -1) -> bool:
	var bx := fx
	var by := fy
	if bx >= 0:
		var spot := open_spot_near(bx, by)
		bx = spot.x
		by = spot.y
	else:
		var best := -INF
		for t in 60:
			var x := randi_range(4, N - 5)
			var y := randi_range(4, N - 5)
			var i := y * N + x
			if land[i] or trail[i] or wall[i]:
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
	p.path_breaks.clear()
	p.wp.clear()
	p.mode = "idle"
	p.think = randf_range(0.2, 1.0)
	p.route = null
	p.shield = SPAWN_SHIELD
	p.fx = {"speed": 0.0, "freeze": 0.0, "ghost": 0.0}
	p.rage = false if not p.is_boss else p.rage
	p.squash = 1.0
	if not _setting_up:
		spawned.emit(p)
	return true


# ---------- Knockouts ----------

func kill(victim: Player, killer: Player, how := "cut") -> void:
	if not victim.alive:
		return
	# Once you've won, the celebration can't be spoiled
	if won and not victim.is_bot:
		return
	# The practice bot can't hurt anyone
	if killer and killer.harmless and killer != victim:
		return
	# A shield stops other players, but not your own mistakes or losing all your land
	if victim.shield > 0 and killer != victim and how != "swallow" and how != "storm":
		return
	if victim.is_boss and victim.hp > 1:
		_hurt_king(victim, killer, how)
		return
	victim.alive = false
	var lost := PackedInt32Array()
	for i in victim.trail:
		if trail[i] == victim.id:
			trail[i] = 0
			lost.append(i)
	victim.trail = PackedInt32Array()
	victim.path.clear()
	victim.path_breaks.clear()
	for i in N * N:
		if land[i] == victim.id:
			set_land(i, 0)
			lost.append(i)
	land_version += 1
	victim.respawn = INF if victim.is_boss else 3.0
	if victim.is_boss:
		victim.hp = 0
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
	p.path_breaks.clear()

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
		if _seen[i] == 0 and land[i] != p.id and wall[i] == 0 and not (land[i] and allies(players[land[i]], p)):
			set_land(i, p.id)
			gained.append(i)
	land_version += 1

	_swallow_check(p)
	p.wp.clear()
	p.mode = "idle"
	captured.emit(p, gained, gained.size() * 100.0 / play_cells)


## Anyone who lost all their land is out
func _swallow_check(by: Player) -> void:
	for o in players:
		if o and o != by and o.alive and counts[o.id] == 0:
			kill(o, by, "swallow")


# ---------- Power-ups and coins ----------

func _free_item_spot(margin: float) -> Vector2:
	for t in 20:
		var x := randi_range(3, N - 4)
		var y := randi_range(3, N - 4)
		if wall[y * N + x]:
			continue
		var q := Vector2(x + 0.5, y + 0.5)
		var ok := true
		for pu in powerups:
			if pu.pos.distance_to(q) < margin:
				ok = false
				break
		if ok:
			return q
	return Vector2(-1, -1)


func _update_items(dt: float) -> void:
	_power_timer -= dt
	if _power_timer <= 0:
		_power_timer = randf_range(6.0, 10.0) * (0.5 if event == "power" else 1.0)
		if powerups.size() < MAX_POWERUPS + (2 if event == "power" else 0):
			var q := _free_item_spot(10.0)
			if q.x >= 0:
				powerups.append({"pos": q, "kind": POWERUPS.keys().pick_random(), "age": 0.0})
	_coin_timer -= dt
	if _coin_timer <= 0:
		_coin_timer = randf_range(3.0, 6.0) * (0.5 if event == "coinrain" else 1.0)
		if coins.size() < MAX_COINS * (2 if event == "coinrain" else 1):
			var q := _free_item_spot(0.0)
			if q.x >= 0:
				coins.append({"pos": q, "age": 0.0, "life": 25.0})
	for pu in powerups:
		pu.age += dt
		for p in players:
			if p and p.alive and not pu.has("taken") and p.pos.distance_to(pu.pos) < 1.3:
				pu.taken = true
				_grab(p, pu.kind, pu.pos)
	powerups = powerups.filter(func(pu): return not pu.has("taken"))
	for c in coins:
		c.age += dt
		c.life -= dt
		for p in players:
			if p and p.alive and not c.has("taken") and p.pos.distance_to(c.pos) < 1.1:
				c.taken = true
				if p == me:
					coins_picked += COIN_VALUE
				coin_taken.emit(p, c.pos)
	coins = coins.filter(func(c): return not c.has("taken") and c.life > 0)
	freezer = null
	for p in players:
		if p and p.alive:
			for k in p.fx:
				p.fx[k] = maxf(0.0, p.fx[k] - dt)
			if p.fx.freeze > 0:
				freezer = p


func _grab(p: Player, kind: String, at: Vector2) -> void:
	match kind:
		"shield":
			p.shield = maxf(p.shield, POWERUPS.shield.time)
		"paint":
			_paint_bomb(p)
		_:
			p.fx[kind] = POWERUPS[kind].time
	picked.emit(p, kind, at)


## Paint Bomb: instantly claims a circle of land around you, even other players' land
func _paint_bomb(p: Player) -> void:
	var cells := PackedInt32Array()
	var r := sqrt(20.0)
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var x := p.cell.x + dx
			var y := p.cell.y + dy
			if dx * dx + dy * dy > r * r or x < 0 or y < 0 or x >= N or y >= N:
				continue
			var i := y * N + x
			if wall[i] or land[i] == p.id or trail[i] == p.id:
				continue # your own trail becomes land when you get home
			if land[i] and allies(players[land[i]], p):
				continue # never paint over a teammate
			set_land(i, p.id)
			cells.append(i)
	land_version += 1
	painted.emit(p, cells)
	_swallow_check(p)


# ---------- Movement ----------

func speed_of(p: Player) -> float:
	var v := SPEED
	if p.harmless:
		v *= 0.6
	elif p.is_bot and p != me:
		v *= DIFFICULTY.get(difficulty, DIFFICULTY.normal).speed * p.skill_speed
	if p.is_boss:
		v *= 1.28 if p.rage else 1.12
	if event == "speed":
		v *= 1.2
	if on_ice(p.pos.x, p.pos.y):
		v *= ICE_SPEED
	if p.fx.speed > 0:
		v *= 1.6
	if freezer and freezer != p:
		v *= 0.5
	return v


func visit(p: Player, x: int, y: int) -> void:
	var i := y * N + x
	if wall[i]:
		return
	var t := trail[i]
	if t:
		var other: Player = players[t]
		if other == p:
			if p.fx.ghost > 0:
				return # Ghost: pass over your own trail
			kill(p, p)
			return
		if allies(p, other):
			return # a teammate's trail is safe (and stays theirs)
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
	if p.alive and belt[p.cell.y * N + p.cell.x]:
		_ride_belt(p, dt)
	if p.alive and not portals.is_empty():
		p.portal_cd = maxf(0.0, p.portal_cd - dt)
		if p.portal_cd <= 0:
			for pair in portals:
				for k in 2:
					if p.pos.distance_to(pair[k]) < 0.8:
						_teleport(p, pair[k], pair[1 - k])
						return


func _step(p: Player, dt: float) -> void:
	var diff := wrapf(p.desired - p.angle, -PI, PI)
	var rate := turn_rate(p.pos.x, p.pos.y)
	var turn := clampf(diff, -rate * dt, rate * dt)
	p.angle = wrapf(p.angle + turn, -PI, PI)
	p.turning = turn / (TURN * dt) if dt > 0 else 0.0
	var v := speed_of(p)
	var nx := clampf(p.pos.x + cos(p.angle) * v * dt, 0.01, N - 0.01)
	var ny := clampf(p.pos.y + sin(p.angle) * v * dt, 0.01, N - 0.01)
	# Pinball: a bumper bounces you off the way a ball would
	for b in bumpers:
		var bpos: Vector2 = b.pos
		var d: Vector2 = Vector2(nx, ny) - bpos
		var reach: float = BUMPER_R + 0.45 * p.size
		if d.length() < reach:
			var n: Vector2 = d.normalized() if d.length() > 0.01 else Vector2.from_angle(p.angle + PI)
			var dir := Vector2.from_angle(p.angle)
			if dir.dot(n) < 0:
				dir = dir - 2.0 * dir.dot(n) * n
			p.angle = dir.angle()
			p.desired = p.angle
			var out: Vector2 = bpos + n * (reach + 0.05)
			nx = clampf(out.x, 0.01, N - 0.01)
			ny = clampf(out.y, 0.01, N - 0.01)
			p.squash = 1.0
			b.flash = 1.0
			bumped.emit(p, b.pos)
			break
	# Walls aren't deadly: slide along them
	if is_wall_at(nx, ny):
		if not is_wall_at(p.pos.x, ny):
			nx = p.pos.x
		elif not is_wall_at(nx, p.pos.y):
			ny = p.pos.y
		else:
			nx = p.pos.x
			ny = p.pos.y
	p.blocked = is_equal_approx(nx, p.pos.x) and is_equal_approx(ny, p.pos.y)
	_arrive(p, Vector2(nx, ny))


## Puts a player at `to` (a small step away) and visits the cells it crossed
func _arrive(p: Player, to: Vector2) -> void:
	p.pos = to
	var cx := int(to.x)
	var cy := int(to.y)
	if cx == p.cell.x and cy == p.cell.y:
		return
	# Diagonal step: also visit a corner cell, so trails never have gaps to slip through
	if cx != p.cell.x and cy != p.cell.y:
		if wall[p.cell.y * N + cx]:
			visit(p, p.cell.x, cy)
		else:
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
			if p == null or q == null or not p.alive or not q.alive or allies(p, q):
				continue
			if p.pos.distance_to(q.pos) > (1.5 if p.is_boss or q.is_boss else 0.9):
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
		p.hit_flash = maxf(0.0, p.hit_flash - dt * 2.0)
		p.squash = move_toward(p.squash, 0.0, dt * 3.0)
		p.blink -= dt
		if p.blink < -0.12:
			p.blink = randf_range(2.0, 5.0)
		if p.is_bot:
			bots.steer(p, dt)
		move(p, dt)
		if p.is_boss and p.alive:
			_boss_power(p, dt)
	check_bumps()
	_update_items(dt)
	_update_hazards(dt)
	if hill_r > 0:
		_score_hill(dt)
	for b in bumpers:
		b.flash = maxf(0.0, b.flash - dt * 3.0)


# ---------- Hazard maps ----------

func center() -> Vector2:
	return Vector2(N / 2.0, N / 2.0)


## Conveyor: the belt carries you along (walls still stop you)
func _ride_belt(p: Player, dt: float) -> void:
	var push: Vector2 = BELT_DIRS[belt[p.cell.y * N + p.cell.x]] * BELT_SPEED * dt
	var to := p.pos + push
	if is_wall_at(to.x, to.y):
		return
	var before := p.pos
	_arrive(p, to.clamp(Vector2(0.01, 0.01), Vector2(N - 0.01, N - 0.01)))
	if p.alive and p.trail.size() > 0 and not p.path.is_empty() and p.path[p.path.size() - 1].distance_to(p.pos) >= 0.3:
		p.path.append(p.pos)
	elif p.alive and p.trail.size() > 0 and p.path.is_empty():
		p.path.append(before)


## Portals: pop out of the twin, heading the same way, trail and all
func _teleport(p: Player, from: Vector2, to: Vector2) -> void:
	var exit := to + Vector2.from_angle(p.angle) * 1.3
	if is_wall_at(exit.x, exit.y):
		exit = to
	p.portal_cd = 1.2
	p.pos = exit
	if p.trail.size() > 0:
		p.path_breaks.append(p.path.size())
		p.path.append(exit)
	var cx := int(exit.x)
	var cy := int(exit.y)
	if cx != p.cell.x or cy != p.cell.y:
		visit(p, cx, cy)
		p.cell = Vector2i(cx, cy)
	if p.is_bot:
		p.route = null
		p.wp.clear()
		p.think = 0.0
	teleported.emit(p, from, exit)


func _update_hazards(dt: float) -> void:
	# Saw Mill: a blade cuts any trail it runs over, and anyone it hits outside their land
	for s in saws:
		s.d = fposmod(s.d + s.speed * dt, _loop_length(s.corners))
		s.pos = _along(s.corners, s.d)
		s.spin += dt * 14.0
		var cx := int(s.pos.x)
		var cy := int(s.pos.y)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var x := cx + ox
				var y := cy + oy
				if x < 0 or y < 0 or x >= N or y >= N:
					continue
				if Vector2(x + 0.5, y + 0.5).distance_to(s.pos) > 1.2:
					continue
				var t := trail[y * N + x]
				if t and players[t] and players[t].alive:
					kill(players[t], null, "saw")
		for p in players:
			if p and p.alive and p.pos.distance_to(s.pos) < 1.3 * p.size and land[p.cell.y * N + p.cell.x] != p.id:
				kill(p, null, "saw")
	# Storm: a warning ring, then everything outside it is lost
	if storm_r > 0:
		storm_timer -= dt
		if storm_next == 0.0 and storm_timer <= STORM_WARN and storm_r > STORM_MIN:
			storm_next = maxf(STORM_MIN, storm_r - STORM_STEP)
			storm_coming.emit(storm_next)
		if storm_timer <= 0:
			if storm_next > 0:
				_close_storm(storm_next)
			storm_next = 0.0
			storm_timer = STORM_EVERY
	# The Queen's traps: step on one outside your land and you're out
	for t in traps:
		t.life -= dt
		if t.life <= 0:
			continue
		for p in players:
			if p and p.alive and p != t.owner and not p.is_boss and p.pos.distance_to(t.pos) < 0.9 \
					and land[p.cell.y * N + p.cell.x] != p.id:
				kill(p, null, "trap")
				if not p.alive:
					t.life = 0.0
	traps = traps.filter(func(t): return t.life > 0)


func _close_storm(r: float) -> void:
	storm_r = r
	var c := center()
	var hit := {}
	for y in N:
		for x in N:
			var i := y * N + x
			if wall[i] == 2 or Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				continue
			if trail[i]:
				hit[trail[i]] = true
			if land[i]:
				set_land(i, 0)
			wall[i] = 2
			play_cells -= 1
	for id in hit:
		if players[id] and players[id].alive:
			kill(players[id], null, "storm")
	for p in players:
		if p == null or not p.alive:
			continue
		if wall[p.cell.y * N + p.cell.x] != 0 or counts[p.id] == 0:
			kill(p, null, "storm")
		# A boss survives a hit, but not standing in the storm: he moves somewhere safe
		if p.alive and wall[p.cell.y * N + p.cell.x] != 0:
			p.alive = false
			if spawn(p) and p.is_boss:
				_grow_kingdom(p)
	land_version += 1
	map_version += 1
	storm_hit.emit(r)


## Inside the storm's safe circle (with `margin` to spare)? Always true without a storm.
func inside_storm(q: Vector2, margin := 0.0) -> bool:
	if storm_r <= 0:
		return true
	var r := storm_next if storm_next > 0 else storm_r
	return q.distance_to(center()) <= r - margin


func trap_near(q: Vector2, r := 1.3) -> bool:
	for t in traps:
		if t.pos.distance_to(q) < r:
			return true
	return false


func _loop_length(corners: Array) -> float:
	var total := 0.0
	for k in corners.size():
		total += corners[k].distance_to(corners[(k + 1) % corners.size()])
	return total


## The point `d` cells along a closed loop of corners
func _along(corners: Array, d: float) -> Vector2:
	for k in corners.size():
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % corners.size()]
		var l := a.distance_to(b)
		if d <= l:
			return a.lerp(b, d / l)
		d -= l
	return corners[0]


# ---------- Boss powers ----------

func _boss_power(k: Player, dt: float) -> void:
	k.power_timer -= dt
	if k.power_timer > 0:
		return
	match k.boss_kind:
		"queen":
			# She drops spiky traps behind her while she's out of her land
			if k.trail.size() > 2 and traps.size() < 14:
				traps.append({"pos": k.pos, "life": 14.0, "owner": k})
				k.power_timer = 1.6 if k.rage else 2.4
				trap_dropped.emit(k, k.pos)
		"wizard":
			# Get close while he's out, and he blinks home, taking his trail with him
			if k.trail.size() >= 3:
				for h in humans():
					if h.alive and h.pos.distance_to(k.pos) < 7.5:
						_blink(k)
						k.power_timer = 5.0 if k.rage else 7.0
						return


func _blink(k: Player) -> void:
	var from := k.pos
	for i in k.trail:
		if trail[i] == k.id:
			trail[i] = 0
	k.trail = PackedInt32Array()
	k.path.clear()
	k.path_breaks.clear()
	# Somewhere in his land, as far from you as he can find
	var best := -1
	var best_d := -1.0
	for tries in 300:
		var i := randi() % (N * N)
		if land[i] != k.id:
			continue
		var q := Vector2(i % N + 0.5, i / N + 0.5)
		var d := INF
		for h in humans():
			if h.alive:
				d = minf(d, q.distance_to(h.pos))
		if d > best_d:
			best_d = d
			best = i
	if best >= 0:
		k.pos = Vector2(best % N + 0.5, best / N + 0.5)
		k.cell = Vector2i(best % N, best / N)
	k.wp.clear()
	k.mode = "idle"
	k.route = null
	k.shield = 1.0
	blinked.emit(k, from, k.pos)


# ---------- Boss Battle: the King ----------
# A big, fast bot with hearts. Cutting his trail (or him crossing it) takes a heart instead of
# knocking him out. At half health he calls two guards; on his last heart he gets faster.

## A skill level for a new bot, from the room's mix or the difficulty's
func pick_skill() -> String:
	var mix: Array = skill_mix if skill_mix.size() == 3 else SKILL_MIX.get(difficulty, SKILL_MIX.normal)
	var r: float = randf() * (mix[0] + mix[1] + mix[2])
	return "rookie" if r < mix[0] else "regular" if r < mix[0] + mix[1] else "pro"


## The mix for an online room from the average level of the people in it: new players meet
## mostly rookies, experienced ones mostly pros
static func skill_mix_for_level(avg_level: float) -> Array:
	var t := clampf((avg_level - 3.0) / 22.0, 0.0, 1.0)
	return [lerpf(0.5, 0.05, t), lerpf(0.4, 0.35, t), lerpf(0.1, 0.6, t)]


## Easy bots are timid and slow to hunt; Hard ones go for your trail
func _tune(b: Player) -> void:
	match difficulty:
		"easy":
			b.aggro *= 0.4
			b.flee += 2.0
		"hard":
			b.aggro = minf(1.0, b.aggro * 1.4 + 0.1)
			b.flee = maxf(2.0, b.flee - 1.0)


func _spawn_king() -> void:
	var kind: String = boss_kind if BOSSES.has(boss_kind) else "king"
	var b: Dictionary = BOSSES[kind]
	var k := Player.new(players.size(), b.name, Color(b.color), true)
	bots.give_personality(k, "hunter")
	k.is_boss = true
	k.boss_kind = kind
	k.size = 1.7
	k.hp = b.hearts + (2 if event == "giants" else 0)
	k.max_hp = k.hp
	k.greed = 55
	k.aggro = 0.7
	k.loop_scale = 1.7
	k.flee = 0
	if difficulty == "easy":
		k.aggro = 0.4
	k.team = k.id
	players.append(k)
	king = k
	if spawn(k):
		_grow_kingdom(k)


## The King starts with a bigger home than everyone else
func _grow_kingdom(k: Player) -> void:
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var x := k.cell.x + dx
			var y := k.cell.y + dy
			if x < 0 or y < 0 or x >= N or y >= N or dx * dx + dy * dy > 26:
				continue
			var i := y * N + x
			if land[i] == 0 and trail[i] == 0 and wall[i] == 0:
				set_land(i, k.id)
	land_version += 1


func _hurt_king(k: Player, by: Player, how: String) -> void:
	k.hp -= 1
	# His trail breaks, and he gets a moment to recover
	for i in k.trail:
		if trail[i] == k.id:
			trail[i] = 0
	k.trail = PackedInt32Array()
	k.path.clear()
	k.path_breaks.clear()
	k.shield = 2.5
	k.wp.clear()
	k.mode = "idle"
	k.route = null
	k.hit_flash = 1.0
	# Swallowed: he escapes to a new home
	if how == "swallow" or counts[k.id] == 0:
		k.alive = false
		if spawn(k):
			_grow_kingdom(k)
			k.shield = 2.5
	if k.hp == 1:
		k.rage = true
	boss_hit.emit(k, by)
	if k.hp == ceili(k.max_hp / 2.0):
		_call_guards(k)


func _call_guards(k: Player) -> void:
	var used := []
	for p in players:
		if p:
			used.append(p.color)
	var spare: Array[Color] = []
	for c in COLORS:
		if not used.has(c):
			spare.append(c)
	for guard in ["Guard", "Knight"]:
		var g := Player.new(players.size(), guard, spare.pop_front() if spare.size() else Color("#8d97ab"), true)
		bots.give_personality(g, "hunter")
		_tune(g)
		Cosmetics.dress_bot(g)
		g.team = g.id
		players.append(g)
		spawn(g)
	guards_called.emit(k)


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
