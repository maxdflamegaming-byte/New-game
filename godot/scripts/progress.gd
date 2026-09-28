class_name Progress
extends RefCounted
## Everything you build up by playing: XP and levels, 3 daily missions, the daily streak,
## trophies and lifetime stats. Main hands over a summary of each finished game and pays
## out the coins in the rewards that come back.

## Daily missions: `stat` is added up over the day, or for "best" ones the best single game
const MISSIONS := {
	"play3": {"text": "Play 3 games", "goal": 3, "stat": "games", "reward": 60},
	"win2": {"text": "Win 2 games", "goal": 2, "stat": "wins", "reward": 120},
	"kos5": {"text": "Knock out 5 players", "goal": 5, "stat": "kos", "reward": 100},
	"power8": {"text": "Grab 8 power-ups", "goal": 8, "stat": "powerups", "reward": 80},
	"coins10": {"text": "Pick up 10 coins", "goal": 10, "stat": "coins", "reward": 80},
	"claim30": {"text": "Claim 30% in one game", "goal": 30, "stat": "pct", "best": true, "reward": 100},
	"loop5": {"text": "Claim 5% in a single loop", "goal": 5, "stat": "best_loop", "best": true, "reward": 100},
	"time5": {"text": "Play for 5 minutes", "goal": 300, "stat": "time", "reward": 60, "time": true},
	"timed": {"text": "Finish a Timed game", "goal": 1, "stat": "mode_timed", "reward": 60},
	"teams": {"text": "Win a Teams game", "goal": 1, "stat": "win_teams", "reward": 120},
	"boss": {"text": "Knock a heart off a boss", "goal": 1, "stat": "king_hits", "reward": 80},
	"daily": {"text": "Play today's Daily", "goal": 1, "stat": "mode_daily", "reward": 60},
}

const TROPHIES := {
	"first_win": {"name": "First Win", "desc": "Win a game"},
	"wins10": {"name": "Winner", "desc": "Win 10 games"},
	"wins50": {"name": "Champion", "desc": "Win 50 games"},
	"first_ko": {"name": "Snip!", "desc": "Knock someone out"},
	"kos100": {"name": "Trail Cutter", "desc": "Knock out 100 players"},
	"double": {"name": "Double Trouble", "desc": "Knock out 2 players within 4 seconds"},
	"ko5": {"name": "Rampage", "desc": "Knock out 5 players in one game"},
	"pct75": {"name": "Land Baron", "desc": "Claim 75% of a map"},
	"loop10": {"name": "Giga Loop", "desc": "Claim 10% in a single loop"},
	"modes": {"name": "Try Everything", "desc": "Play every mode"},
	"maps": {"name": "Globetrotter", "desc": "Play on every map"},
	"king": {"name": "King Slayer", "desc": "Beat the King"},
	"queen": {"name": "Queen Slayer", "desc": "Beat the Queen"},
	"wizard": {"name": "Wizard Slayer", "desc": "Beat the Wizard"},
	"flawless": {"name": "Flawless", "desc": "Beat a boss without losing a life"},
	"teams": {"name": "Team Player", "desc": "Win a Teams game"},
	"clock": {"name": "Beat the Clock", "desc": "Win a Timed game"},
	"quick": {"name": "Speed Run", "desc": "Win a game in under 2 minutes"},
	"power5": {"name": "Power Hungry", "desc": "Grab 5 power-ups in one game"},
	"level10": {"name": "Rising Star", "desc": "Reach level 10"},
	"streak7": {"name": "Regular", "desc": "Play 7 days in a row"},
	"shopper": {"name": "Shopper", "desc": "Buy something in the shop"},
	"rich": {"name": "Piggy Bank", "desc": "Save up 1000 coins"},
	"tutorial": {"name": "Graduate", "desc": "Finish the tutorial"},
}
const TROPHY_COINS := 25
const STREAK_COINS := [20, 30, 40, 60, 80, 100, 150] # day 1..7, then 100 a day
const ALL_MODES := ["classic", "timed", "daily", "teams", "boss", "duo"]
const ALL_MAPS := ["square", "round", "pillars", "maze", "islands", "saws", "storm", "conveyor", "portals"]

var xp := 0 # towards the next level
var level := 1
var stats := blank_stats()
var trophies := {} # id -> true
var day := "" # the day the missions are for
var missions := [] # [{id, progress, done}]
var streak := 0
var streak_day := ""
var tutorial_done := false


static func blank_stats() -> Dictionary:
	return {
		"games": 0, "wins": 0, "kos": 0, "time": 0.0, "powerups": 0, "coins": 0,
		"best_pct": 0.0, "best_loop": 0.0, "best_streak": 0, "king_wins": 0, "queen_wins": 0, "wizard_wins": 0, "modes": [], "maps": [],
	}


## XP needed to go from `lvl` to the next level
static func need(lvl: int) -> int:
	return 100 + (lvl - 1) * 40


## New missions when the day changes (the same 3 for everyone on a given day)
func ensure_day(today: String) -> void:
	if day == today and missions.size() == 3:
		return
	day = today
	var rng := RandomNumberGenerator.new()
	rng.seed = today.hash()
	var ids := MISSIONS.keys()
	missions = []
	while missions.size() < 3:
		var id: String = ids[rng.randi() % ids.size()]
		if not missions.any(func(m): return m.id == id):
			missions.append({"id": id, "progress": 0.0, "done": false})


## A finished game. `s` has: mode, map, won, pct, kos, powerups, coins, time, best_loop,
## king_hits, lives_lost, multi_ko, wallet. Returns the rewards: [{text, coins}]
func finish(s: Dictionary, today: String) -> Array:
	var out := []
	var mode: String = s.get("mode", "classic")
	_add_unique("modes", mode)
	_add_unique("maps", s.get("map", "square"))
	if mode != "duo":
		var won: bool = s.get("won", false)
		stats.games += 1
		stats.wins += 1 if won else 0
		stats.kos += s.get("kos", 0)
		stats.time += s.get("time", 0.0)
		stats.powerups += s.get("powerups", 0)
		stats.coins += s.get("coins", 0)
		stats.best_pct = maxf(stats.best_pct, s.get("pct", 0.0))
		stats.best_loop = maxf(stats.best_loop, s.get("best_loop", 0.0))
		if won and mode == "boss":
			var key: String = s.get("boss", "king") + "_wins"
			if stats.has(key):
				stats[key] += 1
		out.append_array(_streak(today))
		out.append_array(_missions(s, today))
		out.append_array(_gain_xp(xp_for(s)))
	out.append_array(check_trophies(s))
	return out


## XP for a game: a little for playing, more for land, knockouts and winning
static func xp_for(s: Dictionary) -> int:
	return 10 + roundi(s.get("pct", 0.0)) + s.get("kos", 0) * 5 + (25 if s.get("won", false) else 0)


func _gain_xp(amount: int) -> Array:
	var out := []
	xp += amount
	while xp >= need(level):
		xp -= need(level)
		level += 1
		out.append({"text": tr("Level %d!") % level, "coins": 50 + level * 10, "kind": "level"})
	return out


func _streak(today: String) -> Array:
	if streak_day == today:
		return []
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today) - 86400)
	streak = streak + 1 if streak_day == yesterday else 1
	streak_day = today
	stats.best_streak = maxi(stats.best_streak, streak)
	var coins: int = STREAK_COINS[streak - 1] if streak <= STREAK_COINS.size() else 100
	return [{"text": tr("Day %d streak") % streak if streak > 1 else tr("First game today"), "coins": coins, "kind": "streak"}]


func _missions(s: Dictionary, today: String) -> Array:
	ensure_day(today)
	var out := []
	var mode: String = s.get("mode", "")
	var won: bool = s.get("won", false)
	for m in missions:
		if m.done:
			continue
		var d: Dictionary = MISSIONS[m.id]
		var stat: String = d.stat
		var v := 0.0
		if stat == "games":
			v = 1
		elif stat == "wins":
			v = 1 if won else 0
		elif stat.begins_with("mode_"):
			v = 1 if mode == stat.substr(5) else 0
		elif stat.begins_with("win_"):
			v = 1 if won and mode == stat.substr(4) else 0
		else:
			v = float(s.get(stat, 0))
		m.progress = maxf(m.progress, v) if d.get("best", false) else m.progress + v
		if m.progress >= d.goal:
			m.progress = float(d.goal)
			m.done = true
			out.append({"text": tr("Mission: %s") % tr(d.text), "coins": d.reward, "kind": "mission"})
	return out


## Trophies you've just earned (each pays TROPHY_COINS)
func check_trophies(s: Dictionary = {}) -> Array:
	var won: bool = s.get("won", false)
	var mode: String = s.get("mode", "")
	var solo: bool = mode != "duo" and not s.is_empty()
	var got := {
		"first_win": stats.wins >= 1,
		"wins10": stats.wins >= 10,
		"wins50": stats.wins >= 50,
		"first_ko": stats.kos >= 1,
		"kos100": stats.kos >= 100,
		"double": solo and s.get("multi_ko", 0) >= 2,
		"ko5": solo and s.get("kos", 0) >= 5,
		"pct75": stats.best_pct >= 75,
		"loop10": stats.best_loop >= 10,
		"modes": ALL_MODES.all(func(m): return stats.modes.has(m)),
		"maps": ALL_MAPS.all(func(m): return stats.maps.has(m)),
		"king": stats.king_wins >= 1,
		"queen": stats.queen_wins >= 1,
		"wizard": stats.wizard_wins >= 1,
		"flawless": solo and won and mode == "boss" and s.get("lives_lost", 1) == 0,
		"teams": solo and won and mode == "teams",
		"clock": solo and won and mode == "timed",
		"quick": solo and won and s.get("time", INF) < 120,
		"power5": solo and s.get("powerups", 0) >= 5,
		"level10": level >= 10,
		"streak7": streak >= 7,
		"rich": s.get("wallet", 0) >= 1000,
		"tutorial": tutorial_done,
	}
	var out := []
	for id in got:
		if got[id]:
			out.append_array(award(id))
	return out


## Gives a trophy (if it's new). Returns its reward, or nothing.
func award(id: String) -> Array:
	if trophies.has(id) or not TROPHIES.has(id):
		return []
	trophies[id] = true
	return [{"text": tr("Trophy: %s") % tr(TROPHIES[id].name), "coins": TROPHY_COINS, "kind": "trophy"}]


func _add_unique(key: String, v: String) -> void:
	if not stats[key].has(v):
		stats[key].append(v)


# ---------- Saving ----------

func to_dict() -> Dictionary:
	return {"xp": xp, "level": level, "stats": stats, "trophies": trophies.keys(), "day": day,
		"missions": missions, "streak": streak, "streak_day": streak_day, "tutorial": tutorial_done}


func from_dict(d: Dictionary) -> void:
	xp = int(d.get("xp", 0))
	level = maxi(1, int(d.get("level", 1)))
	var st: Dictionary = d.get("stats", {})
	stats = blank_stats()
	for k in stats:
		if st.has(k) and typeof(st[k]) == typeof(stats[k]):
			stats[k] = st[k]
		elif st.has(k) and typeof(stats[k]) == TYPE_FLOAT and typeof(st[k]) == TYPE_INT:
			stats[k] = float(st[k])
	trophies = {}
	for id in d.get("trophies", []):
		if TROPHIES.has(id):
			trophies[id] = true
	day = d.get("day", "")
	missions = []
	for m in d.get("missions", []):
		if typeof(m) == TYPE_DICTIONARY and MISSIONS.has(m.get("id", "")):
			missions.append({"id": m.id, "progress": float(m.get("progress", 0)), "done": bool(m.get("done", false))})
	streak = int(d.get("streak", 0))
	streak_day = d.get("streak_day", "")
	tutorial_done = bool(d.get("tutorial", false))
