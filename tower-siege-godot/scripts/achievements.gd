class_name Achievements
extends RefCounted
## Achievements and ranks, kept in the save. An achievement is earned when one of your
## lifetime numbers reaches its goal (a toast says so), and pays its coins when you collect it
## on the Achievements screen. Your rank comes from the stars you've earned in the story.
## Lifetime numbers (save.life) are counted by main.count(); a few are worked out from the
## rest of the save (levels beaten, stars, bosses, looks owned, upgrades maxed).

## [group, id, icon, name, what to do (%d = the goal), number, goal, coins]
const LIST := [
	["Campaign", "win1", "🎖", "First Victory", "Win your first battle", "win", 1, 20],
	["Campaign", "lv10", "🏜", "Into the Desert", "Beat level %d", "level", 10, 60],
	["Campaign", "lv30", "🗺", "Halfway Home", "Beat level %d", "level", 30, 150],
	["Campaign", "lv60", "👑", "Grumble's Downfall", "Beat level %d and finish the story", "level", 60, 400],
	["Campaign", "lv80", "♾", "Beyond the Hills", "Beat level %d in the endless levels", "level", 80, 250],
	["Campaign", "boss3", "🏰", "Castle Breaker", "Beat %d boss levels", "bosses", 3, 80],
	["Campaign", "boss12", "🏯", "Siege Master", "Beat all %d boss levels of the story", "bosses", 12, 300],
	["Campaign", "star30", "⭐", "Rising Star", "Earn %d stars in the story", "stars", 30, 60],
	["Campaign", "star100", "🌟", "Star Collector", "Earn %d stars in the story", "stars", 100, 150],
	["Campaign", "star180", "💫", "Perfect Campaign", "Earn all %d stars of the story", "stars", 180, 500],
	["Combat", "cap100", "🚩", "Conqueror", "Capture %d buildings", "capture", 100, 50],
	["Combat", "cap1000", "🚩", "Warlord", "Capture %d buildings", "capture", 1000, 150],
	["Combat", "cap5000", "🚩", "Emperor", "Capture %d buildings", "capture", 5000, 400],
	["Combat", "beat1000", "⚔", "Veteran", "Beat %d enemy soldiers", "beat", 1000, 60],
	["Combat", "beat10000", "⚔", "Legend of the Field", "Beat %d enemy soldiers", "beat", 10000, 250],
	["Combat", "roads500", "🛣", "Road Builder", "Build %d roads", "roads", 500, 60],
	["Combat", "strike25", "✈", "Air Commander", "Call in %d airstrikes", "strike", 25, 80],
	["Combat", "upg20", "⬆", "Engineer", "Upgrade buildings %d times in battle", "upgrade", 20, 60],
	["Combat", "perfect1", "🛡", "Flawless", "Win a battle without losing a single building", "perfect", 1, 40],
	["Combat", "perfect20", "🛡", "Untouchable", "Win %d battles without losing a building", "perfect", 20, 200],
	["Combat", "fast1", "⚡", "Lightning Strike", "Win a battle in under 30 seconds", "fast", 1, 40],
	["Combat", "fast20", "⚡", "Speed Demon", "Win %d battles in under 30 seconds", "fast", 20, 200],
	["Modes", "daily1", "📅", "Daily Soldier", "Win a daily challenge", "daily", 1, 40],
	["Modes", "daily15", "📅", "Never Miss a Day", "Win %d daily challenges", "daily", 15, 250],
	["Modes", "event1", "🎪", "Weekend Warrior", "Win a weekend event", "event", 1, 150],
	["Modes", "pvp1", "🏆", "Duelist", "Win a PvP match", "pvp_win", 1, 50],
	["Modes", "pvp25", "🏆", "Champion", "Win %d PvP matches", "pvp_win", 25, 300],
	["Modes", "streak7", "🔥", "Loyal Commander", "Collect the daily reward %d days in a row", "streak", 7, 150],
	["Modes", "quests30", "📜", "Quest Master", "Collect %d quests", "quest", 30, 120],
	["Modes", "chest20", "🎁", "Treasure Hunter", "Open %d quest chests", "chest", 20, 100],
	["Collection", "looks5", "🎨", "Dressed to Impress", "Own %d looks (hats and flags)", "looks", 5, 60],
	["Collection", "looks12", "🎩", "Fashion General", "Own %d looks (hats and flags)", "looks", 16, 300],
	["Collection", "upmax1", "🔨", "Fully Equipped", "Max out an upgrade in the Shop", "upmax", 1, 100],
	["Collection", "upmax4", "🧰", "Armed to the Teeth", "Max out every upgrade in the Shop", "upmax", 4, 400],
]
const GROUPS := ["Campaign", "Combat", "Modes", "Collection"]

## The Shop's upgrades and their highest level (main.gd sets it from its UPGRADES)
static var upgrade_max := {"drill": 5, "boots": 5, "garrison": 5, "armory": 2}

## Ranks by the stars you've earned in the story: [name, stars needed]
const RANKS := [["Recruit", 0], ["Private", 10], ["Corporal", 25], ["Sergeant", 45], ["Lieutenant", 70],
	["Captain", 95], ["Major", 120], ["Colonel", 145], ["General", 165], ["Field Marshal", 180]]


static func defaults() -> Dictionary:
	return {"life": {}, "ach": {"done": [], "claimed": []}}


static func info(id: String) -> Array:
	for a in LIST:
		if a[1] == id:
			return a
	return []


## One of your lifetime numbers
static func value(save: Dictionary, stat: String) -> int:
	match stat:
		"level":
			return int(save.level) - 1
		"stars":
			return story_stars(save)
		"bosses":
			var n := 0
			for k in save.stars:
				if int(k) <= Levels.MAX_LEVEL and Levels.is_boss(int(k)) and int(save.stars[k]) > 0:
					n += 1
			return n
		"looks":
			return save.looks.owned.size()
		"upmax":
			var n := 0
			for id in upgrade_max:
				if int(save.up.get(id, 0)) >= int(upgrade_max[id]):
					n += 1
			return n
	return int(save.get("life", {}).get(stat, 0))


static func story_stars(save: Dictionary) -> int:
	var n := 0
	for k in save.stars:
		if int(k) <= Levels.MAX_LEVEL:
			n += int(save.stars[k])
	return n


static func text(a: Array) -> String:
	var t := I18n.t(a[4])
	return t % a[6] if t.contains("%d") else t


static func earned(save: Dictionary, id: String) -> bool:
	return id in save.ach.done


static func claimed(save: Dictionary, id: String) -> bool:
	return id in save.ach.claimed


## Newly earned achievements (marked as earned): their ids
static func check(save: Dictionary) -> Array:
	var out := []
	for a in LIST:
		if not earned(save, a[1]) and value(save, a[5]) >= int(a[6]):
			save.ach.done.append(a[1])
			out.append(a[1])
	return out


static func claimable(save: Dictionary) -> int:
	return LIST.filter(func(a): return earned(save, a[1]) and not claimed(save, a[1])).size()


## Collect an earned achievement's coins; returns them (0 if not earned or already collected)
static func claim(save: Dictionary, id: String) -> int:
	var a := info(id)
	if a.is_empty() or not earned(save, id) or claimed(save, id):
		return 0
	save.ach.claimed.append(id)
	save.coins = int(save.coins) + int(a[7])
	return int(a[7])


## Your rank: {name, i, stars, next (stars for the next rank, or -1 at the top)}
static func rank(save: Dictionary) -> Dictionary:
	var s := story_stars(save)
	var i := 0
	for k in RANKS.size():
		if s >= int(RANKS[k][1]):
			i = k
	return {"name": RANKS[i][0], "i": i, "stars": s, "next": int(RANKS[i + 1][1]) if i + 1 < RANKS.size() else -1}
