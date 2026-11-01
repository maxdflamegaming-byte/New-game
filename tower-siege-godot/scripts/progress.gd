class_name Progress
extends RefCounted
## Things that bring you back each day, kept in the save: a daily reward that grows over a
## 7-day streak, 3 daily quests (the same for everyone each day) whose points open chests, the
## daily challenge, and
## Looks (hats for your soldiers and flags for your buildings, bought with coins).
## Days are counted in UTC, so a new day starts at the same moment everywhere.

const STREAK_COINS := [20, 30, 40, 50, 60, 80, 150]
## Quest points: collecting the daily reward and each finished quest adds points for the day,
## and chests along the quests' track open at set points
const REWARD_POINTS := 10
const QUEST_POINTS := 20
const CHESTS := [{"at": 10, "coins": 15}, {"at": 30, "coins": 30}, {"at": 50, "coins": 50}, {"at": 70, "coins": 100}]
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

## Weekly quests: bigger goals that last a week (4 a week, the same for everyone)
const WEEKLY := [
	{"id": "win", "goal": 15, "coins": 200},
	{"id": "capture", "goal": 150, "coins": 200},
	{"id": "beat", "goal": 1500, "coins": 150},
	{"id": "stars3", "goal": 6, "coins": 200},
	{"id": "roads", "goal": 120, "coins": 150},
	{"id": "strike", "goal": 10, "coins": 150, "need": 3},
	{"id": "upgrade", "goal": 15, "coins": 150, "need": 8},
	{"id": "pvp", "goal": 5, "coins": 200},
	{"id": "daily", "goal": 3, "coins": 250, "need": 8, "text": "Win %d daily challenges"},
]
const WEEKLY_COUNT := 4

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
		"quest": {"day": -1, "points": 0, "opened": []},
		"weekly": {"week": -1, "list": []},
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
	_life(save, "streak", n, true)
	var coins: int = STREAK_COINS[n - 1]
	save.coins = int(save.coins) + coins
	add_points(save, REWARD_POINTS, day)
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
	if str(m.get("text", "")) != "":
		return I18n.t(m.text) % m.goal
	for d in MISSIONS:
		if d.id == m.id:
			return I18n.t(d.text) % m.goal if d.text.contains("%d") else I18n.t(d.text)
	return m.id


## Count progress; returns the missions this finished
static func add(save: Dictionary, id: String, n := 1) -> Array:
	var done := []
	if n <= 0:
		return done
	for m in missions(save) + weekly(save):
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
	add_points(save, QUEST_POINTS)
	_life(save, "quest", 1)
	return int(m.coins)


## A lifetime number for the achievements: added to, or kept at its best
static func _life(save: Dictionary, id: String, n: int, best := false) -> void:
	var life: Dictionary = save.get("life", {})
	life[id] = maxi(int(life.get(id, 0)), n) if best else int(life.get(id, 0)) + n
	save.life = life


# ---------- Weekly quests ----------
## Weeks start on Monday (day 0, 1 January 1970, was a Thursday)
static func week(day := today()) -> int:
	return (day + 3) / 7


static func days_left_in_week(day := today()) -> int:
	return 7 - (day + 3) % 7


static func weekly(save: Dictionary, day := today()) -> Array:
	var w := week(day)
	if not save.has("weekly") or int(save.weekly.week) != w:
		var rng := Levels.Rng.new(w * 53 + 11)
		var pool := WEEKLY.filter(func(m): return int(save.level) >= m.get("need", 0))
		var list := []
		while list.size() < WEEKLY_COUNT and not pool.is_empty():
			var m: Dictionary = pool[floori(rng.next() * pool.size())]
			pool.erase(m)
			list.append({"id": m.id, "goal": m.goal, "coins": m.coins, "have": 0, "claimed": false, "weekly": true, "text": m.get("text", "")})
		save.weekly = {"week": w, "list": list}
	return save.weekly.list


static func weekly_claimable(save: Dictionary) -> int:
	return weekly(save).filter(func(m): return int(m.have) >= int(m.goal) and not m.claimed).size()


static func claim_weekly(save: Dictionary, index: int) -> int:
	var list := weekly(save)
	if index < 0 or index >= list.size():
		return 0
	var m: Dictionary = list[index]
	if int(m.have) < int(m.goal) or m.claimed:
		return 0
	m.claimed = true
	save.coins = int(save.coins) + int(m.coins)
	_life(save, "quest", 1)
	return int(m.coins)


# ---------- Quest points and chests ----------
## Today's points and the chests opened (a new day starts again from 0)
static func quest(save: Dictionary, day := today()) -> Dictionary:
	if not save.has("quest") or int(save.quest.day) != day:
		save.quest = {"day": day, "points": 0, "opened": []}
	return save.quest


static func add_points(save: Dictionary, n: int, day := today()) -> void:
	var q := quest(save, day)
	q.points = int(q.points) + n


static func chest_ready(save: Dictionary, i: int) -> bool:
	var q := quest(save)
	return int(q.points) >= int(CHESTS[i].at) and not (i in q.opened.map(func(x): return int(x)))


static func chests_ready(save: Dictionary) -> int:
	return range(CHESTS.size()).filter(func(i): return chest_ready(save, i)).size()


## Open a chest; returns its coins (0 if it isn't ready)
static func open_chest(save: Dictionary, i: int) -> int:
	if i < 0 or i >= CHESTS.size() or not chest_ready(save, i):
		return 0
	quest(save).opened.append(i)
	_life(save, "chest", 1)
	var coins := int(CHESTS[i].coins)
	save.coins = int(save.coins) + coins
	return coins


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
