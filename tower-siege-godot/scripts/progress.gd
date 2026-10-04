class_name Progress
extends RefCounted
## Things that bring you back each day, kept in the save: a daily reward that grows over a
## 7-day streak, 3 daily missions (the same for everyone each day), the daily challenge, and
## Looks (hats for your soldiers and flags for your buildings, bought with coins).
## Days are counted in UTC, so a new day starts at the same moment everywhere.

const STREAK_COINS := [20, 30, 40, 50, 60, 80, 150]
const DAILY_COINS := 100         # winning today's challenge the first time
const DAILY_REPLAY_COINS := 20

## goal and coins: easy, medium, hard. need: the level you must have reached for it to come up.
const MISSIONS := [
	{"id": "capture", "text": "Capture %d buildings", "goal": [10, 18, 28], "coins": [40, 60, 90]},
	{"id": "win", "text": "Win %d levels", "goal": [2, 3, 5], "coins": [40, 60, 90]},
	{"id": "beat", "text": "Beat %d enemy soldiers", "goal": [80, 160, 300], "coins": [40, 60, 90]},
	{"id": "roads", "text": "Build %d roads", "goal": [20, 35, 55], "coins": [30, 50, 70]},
	{"id": "stars3", "text": "Win %d levels with 3 stars", "goal": [1, 2, 3], "coins": [50, 80, 120]},
	{"id": "strike", "text": "Use %d airstrikes", "goal": [2, 3, 5], "coins": [40, 60, 80], "need": 3},
	{"id": "upgrade", "text": "Upgrade your buildings %d times", "goal": [2, 4, 7], "coins": [40, 60, 90], "need": 8},
	{"id": "pvp", "text": "Play %d PvP or practice matches", "goal": [1, 2, 3], "coins": [40, 70, 100]},
	{"id": "daily", "text": "Win the daily challenge", "goal": [1, 1, 1], "coins": [80, 80, 80], "need": 5},
]

const HATS := [
	{"id": "helmet", "name": "Helmet", "icon": "⛑", "cost": 0},
	{"id": "cap", "name": "Cap", "icon": "🧢", "cost": 150},
	{"id": "beret", "name": "Beret", "icon": "🎨", "cost": 200},
	{"id": "party", "name": "Party Hat", "icon": "🥳", "cost": 300},
	{"id": "viking", "name": "Viking", "icon": "🪓", "cost": 450},
	{"id": "crown", "name": "Crown", "icon": "👑", "cost": 800},
]
const FLAGS := [
	{"id": "plain", "name": "Plain", "icon": "🏳", "cost": 0},
	{"id": "stripe", "name": "Stripe", "icon": "➖", "cost": 100},
	{"id": "cross", "name": "Cross", "icon": "✚", "cost": 150},
	{"id": "star", "name": "Gold Star", "icon": "⭐", "cost": 250},
	{"id": "checks", "name": "Checks", "icon": "🏁", "cost": 300},
	{"id": "skull", "name": "Pirate", "icon": "☠", "cost": 500},
]


static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


static func defaults() -> Dictionary:
	return {
		"streak": {"day": -1, "count": 0},
		"missions": {"day": -1, "list": []},
		"daily_won": -1,
		"looks": {"hat": "helmet", "flag": "plain", "owned": ["helmet", "plain"]},
	}


# ---------- Daily reward ----------
static func reward_ready(save: Dictionary, day := today()) -> bool:
	return int(save.streak.day) != day


## The streak day (1-7) the next reward is for
static func streak_next(save: Dictionary, day := today()) -> int:
	var count := int(save.streak.count)
	if int(save.streak.day) == day - 1:
		return count % STREAK_COINS.size() + 1
	return 1


## Collect today's reward; returns the coins (0 if already collected today)
static func claim_reward(save: Dictionary, day := today()) -> int:
	if not reward_ready(save, day):
		return 0
	var n := streak_next(save, day)
	save.streak = {"day": day, "count": n}
	var coins: int = STREAK_COINS[n - 1]
	save.coins = int(save.coins) + coins
	return coins


# ---------- Daily missions ----------
## Today's 3 missions (made the first time they're asked for each day)
static func missions(save: Dictionary, day := today()) -> Array:
	if int(save.missions.day) != day:
		var rng := Levels.Rng.new(day * 31 + 7)
		var pool := MISSIONS.filter(func(m): return int(save.level) >= m.get("need", 0))
		var list := []
		while list.size() < 3 and not pool.is_empty():
			var m: Dictionary = pool[floori(rng.next() * pool.size())]
			pool.erase(m)
			var tier := list.size() # one easy, one medium, one hard
			list.append({"id": m.id, "goal": m.goal[tier], "coins": m.coins[tier], "have": 0, "claimed": false})
		save.missions = {"day": day, "list": list}
	return save.missions.list


static func mission_text(m: Dictionary) -> String:
	for d in MISSIONS:
		if d.id == m.id:
			return I18n.t(d.text) % m.goal if d.text.contains("%d") else I18n.t(d.text)
	return m.id


## Count progress; returns the missions this finished
static func add(save: Dictionary, id: String, n := 1) -> Array:
	var done := []
	if n <= 0:
		return done
	for m in missions(save):
		if m.id != id or int(m.have) >= int(m.goal):
			continue
		m.have = mini(int(m.goal), int(m.have) + n)
		if int(m.have) >= int(m.goal):
			done.append(m)
	return done


static func claimable(save: Dictionary) -> int:
	var n := 0
	for m in missions(save):
		if int(m.have) >= int(m.goal) and not m.claimed:
			n += 1
	return n


static func claim_mission(save: Dictionary, index: int) -> int:
	var list := missions(save)
	if index < 0 or index >= list.size():
		return 0
	var m: Dictionary = list[index]
	if int(m.have) < int(m.goal) or m.claimed:
		return 0
	m.claimed = true
	save.coins = int(save.coins) + int(m.coins)
	return int(m.coins)


# ---------- Looks ----------
static func catalog(kind: String) -> Array:
	return HATS if kind == "hat" else FLAGS


static func owns(save: Dictionary, id: String) -> bool:
	return id in save.looks.owned


## Buy (if needed) and wear a hat or flag; returns "" or why not
static func pick_look(save: Dictionary, kind: String, id: String) -> String:
	for item in catalog(kind):
		if item.id != id:
			continue
		if not owns(save, id):
			if int(save.coins) < int(item.cost):
				return "coins"
			save.coins = int(save.coins) - int(item.cost)
			save.looks.owned.append(id)
		save.looks[kind] = id
		return ""
	return "unknown"
