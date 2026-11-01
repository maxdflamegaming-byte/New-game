class_name Events
extends RefCounted
## Weekend events: every Saturday and Sunday (UTC) one of four events runs, in turn week by
## week, the same for everyone. Each is three battles with a twist that get harder; each won
## battle pays coins, and winning all three gives the event's own look (hats and flags you
## can't buy), or coins if you have it already. Progress is kept in save.event for the week.

const ORDER := ["tanks", "castles", "blitz", "puzzle"]
const KINDS := {
	"tanks": {"name": "Tank Rush", "icon": "🚜", "goal": "conquer", "prize": ["hat", "goldhelm"],
		"desc": "Every building is a Tank Factory, and every tank is worth 3 soldiers. Take them all!"},
	"castles": {"name": "Castle Storm", "icon": "🏰", "goal": "hq", "prize": ["hat", "knight"],
		"desc": "Three of Grumble's castles, one after another. Storm each one!"},
	"blitz": {"name": "Blitz Weekend", "icon": "⏱", "goal": "blitz", "prize": ["flag", "dragon"],
		"desc": "Beat the clock three times: take every enemy building before time runs out."},
	"puzzle": {"name": "No Supplies", "icon": "🧩", "goal": "puzzle", "prize": ["flag", "golden"],
		"desc": "Nobody trains soldiers. Make every soldier count, three times over."},
}
const STAGES := 3
const STAGE_COINS := [50, 80, 120]
const REPEAT_COINS := 200          # winning an event whose look you already have
const STAGE_LEVEL := [14, 24, 34]  # how hard each battle is, as a story level


## Saturday and Sunday (day 0, 1 January 1970, was a Thursday)
static func live(day := Progress.today()) -> bool:
	return (day + 3) % 7 >= 5


static func days_until(day := Progress.today()) -> int:
	return 0 if live(day) else 5 - (day + 3) % 7


static func kind(day := Progress.today()) -> String:
	return ORDER[Progress.week(day) % ORDER.size()]


static func info(k: String) -> Dictionary:
	return KINDS[k]


## This week's event progress: {week, kind, stage (battles won, 0-3), prize (given)}
static func state(save: Dictionary, day := Progress.today()) -> Dictionary:
	var w := Progress.week(day)
	if not save.has("event") or int(save.event.get("week", -1)) != w:
		save.event = {"week": w, "kind": kind(day), "stage": 0, "prize": false}
	return save.event


## The map for battle `stage` (0-2) of this week's event: a fair, mirrored map (like a PvP
## one) from the week's number, with the event's twist
static func stage_data(k: String, stage: int, day := Progress.today()) -> Dictionary:
	var w := Progress.week(day)
	var n: int = STAGE_LEVEL[clampi(stage, 0, STAGES - 1)]
	var d := Levels.gen(n, true, w * 7919 + stage * 131 + 17)
	var base := Levels.gen(n)
	d.ai = base.ai.duplicate()
	d.ai.think = maxf(float(d.ai.think), 1.7)
	d.ai.margin = maxf(float(d.ai.margin), 3.0)
	d.ai.bold = minf(float(d.ai.bold), 0.75)
	d.ai.upgrade = n >= 25
	var towers: Array = d.towers
	match k:
		"tanks":
			for t in towers:
				t[4] = "factory"
		"castles":
			towers[1][4] = "castle"
			towers[1][3] = int(towers[1][3]) + 6 + stage * 6
		"blitz", "puzzle":
			pass
	for t in towers:
		if int(t[2]) == 2:
			t[3] = int(t[3]) + n / 4
	d.theme = Levels.THEMES[(w + stage) % Levels.THEMES.size()]
	d.hint = KINDS[k].desc
	return d


## The look this event gives: [kind, id, name]
static func prize(k: String) -> Array:
	var p: Array = KINDS[k].prize
	for item in Progress.catalog(p[0]):
		if item.id == p[1]:
			return [p[0], p[1], item.name]
	return p + [""]


## A battle of the event won: moves it on, pays, and gives the look after the last one.
## Returns {coins, look ("" or the look's name), done}
static func won(save: Dictionary, day := Progress.today()) -> Dictionary:
	var st := state(save, day)
	var out := {"coins": 0, "look": "", "done": false}
	if int(st.stage) >= STAGES:
		return out
	out.coins = STAGE_COINS[int(st.stage)]
	st.stage = int(st.stage) + 1
	if int(st.stage) >= STAGES and not st.prize:
		st.prize = true
		out.done = true
		var p := prize(st.kind)
		if Progress.owns(save, p[1]):
			out.coins += REPEAT_COINS
		else:
			save.looks.owned.append(p[1])
			out.look = p[2]
	save.coins = int(save.coins) + int(out.coins)
	return out
