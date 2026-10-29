class_name Tutorial
extends RefCounted
## The first three levels teach the game one step at a time. Each step says what to do and
## shows it with the hand; a step waiting for you to act holds the battle still until you do,
## so nothing happens while you read (and gives up after a while, so nobody gets stuck).
##   level 1: build a road, take a gray tower, take another (the label shows if you have
##            enough), then the enemy
##   level 2: cheap towers first, gather soldiers into one army, cut a road, the 💡 hint
##   level 3: bigger towers hold more roads (two attacks at once), Bunkers count double
## Steps: {text, guide: "cheap" | "enemy" | "own" | "", wait: what you do, hold: the battle waits}
## wait: "road" (a road to a building that isn't yours), "own_road" (between your own),
## "capture", "cut", "hint", or "time:N" (seconds).

const MAX_WAIT := 30.0

var main
var steps: Array = []
var i := -1
var waited := 0.0
var done := {}          # what you've done since this step began
var shown := ""         # this step's text (so finishing doesn't wipe a hint shown meanwhile)


static func steps_for(n: int) -> Array:
	match n:
		1:
			return [
				{"text": "Drag from your blue tower to the gray one. Your soldiers march there.", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "Each soldier that arrives takes one away. At 0, the tower is yours!", "wait": "capture"},
				{"text": "Every tower you own trains soldiers, so take the other gray one too. While you drag, the label shows if you have enough: green means yes.", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "An attack road sends just the soldiers it needs, then stops by itself.", "wait": "capture"},
				{"text": "Now the red tower. Drag to it and check the label: when it turns green, let go!", "guide": "enemy", "wait": "road"},
			]
		2:
			return [
				{"text": "Take the small gray tower first: cheap towers are the best start.", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "More towers, more soldiers!", "wait": "capture"},
				{"text": "Drag from one of your towers to another to move soldiers there, and gather one big army.", "guide": "own", "wait": "own_road", "hold": true},
				{"text": "That road keeps moving soldiers until you cut it. Swipe across it to cut it.", "wait": "cut", "hold": true},
				{"text": "Stuck? Tap 💡 Hint any time: it shows a good move.", "wait": "hint", "hold": true},
			]
		3:
			return [
				{"text": "Bigger towers hold more roads: 1 below 10 soldiers, 2 from 10, 3 from 30. Attack a gray tower...", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "...and another one at the same time!", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "The Bunker in the middle takes half damage, so it needs twice the soldiers. The label counts that for you.", "wait": "time:9"},
			]
	return []


func _init(m, n: int) -> void:
	main = m
	steps = steps_for(n)


func active() -> bool:
	return i >= 0 and i < steps.size()


## The battle waits while a step asks you to do something
func holding() -> bool:
	return active() and steps[i].get("hold", false)


func waiting_for() -> String:
	return steps[i].wait if active() else ""


func start() -> void:
	i = -1
	_next()


## Something you did: road, own_road, capture, cut, hint
func event(what: String) -> void:
	if active():
		done[what] = true


func tick(dt: float) -> void:
	if not active():
		return
	waited += dt
	var w: String = steps[i].wait
	var ok: bool = done.has(w) or (w.begins_with("time:") and waited >= float(w.substr(5)))
	if ok or waited >= MAX_WAIT:
		_next()


func _next() -> void:
	i += 1
	waited = 0.0
	done.clear()
	if not active():
		# The end: clear the last step's words, unless a hint is showing now
		if main.hint_text == shown:
			main.set_hint("")
		if not main.guide.is_empty() and main.guide.life >= MAX_WAIT * 10:
			main.guide = {}   # the lesson's hand (a hint's stays)
		return
	var st: Dictionary = steps[i]
	shown = main.tr(st.text)
	main.set_hint(shown, 999.0)
	main.guide = {}
	var mv := _move(st.get("guide", ""))
	if not mv.is_empty():
		main.guide = {"from": mv[0], "to": mv[1], "others": [], "life": MAX_WAIT * 100, "attack": mv[1].owner != Battle.PLAYER}


## The move a step shows: [from, to], or [] if there isn't one
func _move(kind: String) -> Array:
	var b: Battle = main.battle
	var mine: Array = b.towers.filter(func(t): return t.owner == Battle.PLAYER)
	if kind == "" or mine.is_empty():
		return []
	mine.sort_custom(func(x, y): return x.units > y.units)
	if kind == "own":
		# From a small tower of yours to your biggest
		var big = mine[0]
		for s in mine.slice(1):
			if s.units >= 1 and b.can_link(s, big, Battle.PLAYER) is bool:
				return [s, big]
		return []
	# An attack: the cheapest building that still needs soldiers (gray first), from your
	# biggest tower that can reach it
	var best: Array = []
	var cost := INF
	for t in b.towers:
		if t.owner == Battle.PLAYER or (kind == "cheap" and t.owner != Battle.NEUTRAL) or (kind == "enemy" and t.owner < 2):
			continue
		for s in mine:
			if b.can_link(s, t, Battle.PLAYER) is bool:
				var need := b.attack_need(s, t, Battle.PLAYER)
				if need > 0 and need < cost:
					cost = need
					best = [s, t]
				break
	return best
