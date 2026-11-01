extends SceneTree
## Plays every story level with a bot, the way a casual player would: every 1.5 seconds it does
## what the 💡 Hint says, drops its Airstrike on the boss castle (or the strongest enemy
## building), and cuts roads between its own buildings after a while. Prints each level's
## result, time and stars, and checks every level 1-60 can be won (in at least one of the
## tries) and none takes more than 200 s.
##   godot --headless --path tower-siege-godot -s tests/levels.gd [-- FROM TO TRIES]

const THINK := 1.5            # seconds between the bot's moves
const LIMIT := 300.0          # a battle still going after this is "stuck"
const SLOW := 200.0           # a win should come before this

var main
var fails := 0


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func _initialize() -> void:
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak", "user://tower_siege.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()


func act() -> void:
	var b: Battle = main.battle
	# Supply roads between your own buildings don't run for ever
	for t in b.towers:
		if t.owner == Battle.PLAYER:
			t.roads = t.roads.filter(func(r): return r.to.owner != Battle.PLAYER or b.time - float(r.born) < 8.0)
	if main.charges.get("strike", 0) > 0 and b.time > 6.0:
		var foe = null
		for t in b.towers:
			if t.owner >= 2 and (foe == null or t.type == "castle" or (foe.type != "castle" and t.units > foe.units)):
				foe = t
		if foe != null and foe.units >= 12:
			main.drop_strike(foe)
	main.show_hint()
	if main.guide.is_empty():
		return
	var g: Dictionary = main.guide
	for s in [g.from] + g.get("others", []):
		if s.owner == Battle.PLAYER:
			main.request_link(s, g.to, Battle.PLAYER)
	main.guide = {}


## The upgrades a player has by level n, buying the cheapest next one with most of the coins
## the earlier wins paid (15 + 2 per level + 5 a star, about 2.5 stars a win)
func typical_upgrades(n: int) -> Dictionary:
	var coins := 0.0
	for k in range(1, n):
		coins += (15 + 2 * k + 12) * 0.8
	var up := {"drill": 0, "boots": 0, "garrison": 0, "armory": 0}
	while true:
		var pick = null
		for u in main.UPGRADES:
			var lv: int = up[u.id]
			if lv < int(u.max) and (pick == null or int(u.cost[lv]) < int(pick.cost[up[pick.id]])):
				pick = u
		if pick == null or coins < int(pick.cost[up[pick.id]]):
			break
		coins -= int(pick.cost[up[pick.id]])
		up[pick.id] += 1
	return up


## Plays level n once: [result, seconds, stars]. Each try has its own fixed random numbers, so a
## run gives the same results every time.
func play(n: int, k := 0) -> Array:
	seed(n * 1009 + k)
	main.save.up = typical_upgrades(n)
	main.save.level = 60
	main.start_level(n)
	main.tutor = null
	main.set_hint("")
	var next := 1.0
	while main.state == "play" and main.battle.time < LIMIT:
		if main.battle.time >= next:
			act()
			next = main.battle.time + THINK
		main.step(0.05)
		main._update_effects(0.05)
	var result: String = "stuck" if main.state == "play" else ("won" if main.lost_why == "" else "lost:" + main.lost_why)
	var stars := Missions.stars(main.goal, main.battle) if result == "won" else 0
	var t: float = main.battle.time
	main.open_menu()
	return [result, t, stars]


func _run() -> void:
	for i in 5:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var from := int(args[0]) if args.size() > 0 else 1
	var to := int(args[1]) if args.size() > 1 else Levels.MAX_LEVEL
	var tries := int(args[2]) if args.size() > 2 else 2
	var bad := []
	var slow := []
	for n in range(from, to + 1):
		var res := []
		for k in tries:
			res.append(play(n, k))
			await process_frame
		var wins := res.filter(func(r): return r[0] == "won")
		var times := wins.map(func(r): return r[1])
		var line := "LV %2d %-8s %-28s" % [n, Missions.goal_for(n), ", ".join(res.map(func(r): return "%s %.0fs %d★" % [r[0], r[1], r[2]]))]
		print(line + "  towers %d  up %s" % [Levels.data(n).towers.size(), str(typical_upgrades(n).values())])
		if wins.is_empty():
			bad.append(n)
		elif times.min() > SLOW:
			slow.append(n)
	ok("The bot wins every level from %d to %d" % [from, to], bad.is_empty(), "lost or stuck: %s" % str(bad))
	ok("No level takes more than %d s to win" % int(SLOW), slow.is_empty(), "slow: %s" % str(slow))
	print("LEVELS DONE %d failed" % fails)
	quit(1 if fails else 0)
