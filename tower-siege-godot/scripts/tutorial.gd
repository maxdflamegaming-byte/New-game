class_name Tutorial
extends RefCounted
## The first five levels teach the game one step at a time. Each step says what to do and
## shows it with the hand; a step waiting for you to act slows the battle right down while you
## read, until you do something (anything: a road, a cut, an airstrike...) or for a few seconds
## at most, so the game never looks stuck. A step gives up after a while too.
##   level 1: build a road, take a gray tower, then the enemy (the label shows if you have enough)
##   level 2: gather soldiers into one tower, it grows a storey at 10, cut a road
##   level 3: cheap towers first, two attacks at once, the 💡 hint
##   level 4: the Airstrike, and the Watchtower's circle
##   level 5: feed small towers into a big one, then storm the castle
## Steps: {text, guide: "cheap" | "enemy" | "own" | "", wait: what you do, hold: the battle waits}
## wait: "road" (a road to a building that isn't yours), "own_road" (between your own),
## "capture", "cut", "hint", "strike" (an airstrike), "level:N" (one of your towers grows to
## level N) or "time:N" (seconds).

const MAX_WAIT := 30.0
const HOLD_MAX := 6.0   # how long a step may slow the battle down
const SLOW := 0.2       # how fast the battle runs meanwhile

var main
var steps: Array = []
var i := -1
var waited := 0.0
var done := {}          # what you've done since this step began
var acted := false      # you did something since this step began (ends the slow motion)
var shown := ""         # this step's text (so finishing doesn't wipe a hint shown meanwhile)


static func steps_for(n: int) -> Array:
	match n:
		1:
			return [
				{"text": "Drag from your blue tower to the gray one. Your soldiers march there.", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "Each soldier that arrives takes one away. At 0, the tower is yours!", "wait": "capture"},
				{"text": "Now the red tower. Drag to it and check the label: when it turns green, let go!", "guide": "enemy", "wait": "road"},
			]
		2:
			return [
				{"text": "Drag from one of your towers to another to move soldiers there, and gather one big army.", "guide": "own", "wait": "own_road", "hold": true},
				{"text": "At 10 soldiers a tower grows a storey and gets a second road: see the dots on top.", "wait": "level:2"},
				{"text": "That road keeps moving soldiers until you cut it. Swipe across it to cut it.", "wait": "cut", "hold": true},
				{"text": "Now take the gray tower and the red one. Walls block roads, so go round them from below.", "guide": "cheap", "wait": "road"},
			]
		3:
			return [
				{"text": "Take the small gray tower first: cheap towers are the best start.", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "...and another one at the same time!", "guide": "cheap", "wait": "road", "hold": true},
				{"text": "More towers, more soldiers!", "wait": "capture"},
				{"text": "Stuck? Tap 💡 Hint any time: it shows a good move.", "wait": "hint", "hold": true},
			]
		4:
			return [
				{"text": "Call in an Airstrike: tap ✈ Airstrike below, then tap the red tower.", "wait": "strike", "hold": true},
				{"text": "The bombs knock out the soldiers inside. Attack it now, before it trains more!", "guide": "enemy", "wait": "road"},
				{"text": "Keep clear of the Watchtower's circle: it shoots soldiers walking inside it.", "wait": "time:8"},
			]
		5:
			return [
				{"text": "Grumble's castle is strong. Send your small towers' soldiers to the big one in the middle.", "guide": "own", "wait": "own_road", "hold": true},
				{"text": "More! Every road feeds the big tower.", "guide": "own", "wait": "own_road", "hold": true},
				{"text": "When it's big, attack the castle from it. Its guns shoot inside the circle, so go in with one big army.", "wait": "time:10"},
			]
	return []


func _init(m, n: int) -> void:
	main = m
	steps = steps_for(n)


func active() -> bool:
	return i >= 0 and i < steps.size()


## The battle runs in slow motion while a step asks you to do something
func holding() -> bool:
	return active() and steps[i].get("hold", false) and not acted and waited < HOLD_MAX


func waiting_for() -> String:
	return steps[i].wait if active() else ""


func start() -> void:
	i = -1
	_next()


## Something you did: road, own_road, capture, cut, hint
func event(what: String) -> void:
	if active():
		done[what] = true
		if what != "capture":
			acted = true


func tick(dt: float) -> void:
	if not active():
		return
	waited += dt
	var w: String = steps[i].wait
	var ok: bool = done.has(w) or (w.begins_with("time:") and waited >= float(w.substr(5))) \
		or (w.begins_with("level:") and main.battle.towers.any(func(t): return t.owner == Battle.PLAYER and t.level() >= int(w.substr(6))))
	if ok or waited >= MAX_WAIT:
		_next()


func _next() -> void:
	i += 1
	waited = 0.0
	done.clear()
	acted = false
	if not active():
		# The end: clear the last step's words, unless a hint is showing now
		if main.hint_text == shown:
			main.set_hint("")
		if not main.guide.is_empty() and main.guide.life >= MAX_WAIT * 10:
			main.guide = {}   # the lesson's hand (a hint's stays)
		return
	var st: Dictionary = steps[i]
	shown = main.tr(st.text)
	main.set_hint(shown, 999.0, true)
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
