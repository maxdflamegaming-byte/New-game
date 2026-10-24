extends SceneTree
## The battle rules, without drawing anything:
##   godot --headless --path tower-siege-godot -s tests/sim.gd
## Prints PASS/FAIL lines and "SIM DONE n failed".

var fails := 0


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra != "" else ""))
	if not cond:
		fails += 1


func level1() -> Battle:
	var b := Battle.new()
	b.load_map(Levels.data(1))
	return b


func _initialize() -> void:
	# Roads
	var b := level1()
	var me: Battle.Tower = b.towers[0]
	var g1: Battle.Tower = b.towers[1]
	var g2: Battle.Tower = b.towers[2]
	var foe: Battle.Tower = b.towers[3]
	me.units = 5
	ok("A small tower holds 1 road", b.link(me, g1, 1) == true and b.link(me, g2, 1) == "full")
	me.units = 12
	ok("From 10 soldiers it holds 2", b.link(me, g2, 1) == true)
	ok("You can't build from someone else's tower", b.link(g1, me, 1) == "not yours")
	ok("No double roads", b.link(me, g1, 1) == "exists")
	ok("Road limits: 1, 2, 3, 3", [5, 10, 30, 80].map(func(u): var t := Battle.Tower.new(); t.units = u; return t.max_roads()) == [1, 2, 3, 3])

	# Capturing and reinforcing
	me.roads.clear()
	g1.units = 2
	g1.owner = 0
	for i in 3:
		var u := Battle.Unit.new()
		u.owner = 1
		u.to = g1
		b._arrive(u)
	ok("The third soldier takes a gray tower with 2", g1.owner == 1 and is_equal_approx(g1.units, 1.0))
	var r := Battle.Unit.new()
	r.owner = 1
	r.to = g1
	b._arrive(r)
	ok("Soldiers reinforce their own tower", is_equal_approx(g1.units, 2.0))

	# Bunkers take half damage
	g2.type = "fort"
	g2.owner = 0
	g2.units = 2
	for i in 4:
		var u := Battle.Unit.new()
		u.owner = 1
		u.to = g2
		b._arrive(u)
	ok("A bunker with 2 holds 4 soldiers", g2.owner == 0)
	var last := Battle.Unit.new()
	last.owner = 1
	last.to = g2
	b._arrive(last)
	ok("and falls to the fifth", g2.owner == 1)

	# Armies fight where they meet
	b = level1()
	me = b.towers[0]
	foe = b.towers[3]
	b.spawn_unit(me, foe, 1)
	b.spawn_unit(foe, me, 1)
	for i in 400:
		if b.units.is_empty():
			break
		b.update(0.02, false)
	ok("Soldiers from two armies cancel out when they meet", b.units.is_empty() and foe.owner == 2 and me.owner == 1)

	# Tanks: a factory sends tanks worth 3, and a tank beats a soldier
	b = level1()
	me = b.towers[0]
	g1 = b.towers[1]
	foe = b.towers[3]
	me.type = "factory"
	me.units = 20
	b.link(me, g1, 1)
	b.update(0.02, false)
	ok("Tank factories send tanks worth 3 soldiers", b.units.size() == 1 and b.units[0].power == 3 and absf(me.units - 17) < 0.2)
	b.units.clear()
	me.roads.clear()
	b.spawn_unit(me, foe, 3)
	b.spawn_unit(foe, me, 1)
	for i in 400:
		if b.units.size() < 2:
			break
		b.update(0.02, false)
	ok("A tank beats a soldier and keeps going, weaker", b.units.size() == 1 and b.units[0].owner == 1 and b.units[0].power == 2)

	# Watchtowers
	b = level1()
	g1 = b.towers[1]
	g1.type = "watch"
	g1.owner = 2
	g1.reload = 0
	var shots := [0]
	b.shot.connect(func(_t, _u): shots[0] += 1)
	var s := Battle.Unit.new()
	s.owner = 1
	s.power = 1
	s.x = g1.x + 50
	s.y = g1.y
	var tank := Battle.Unit.new()
	tank.owner = 1
	tank.power = 3
	tank.x = g1.x + 80
	tank.y = g1.y
	b.units.append_array([s, tank])
	b._update_watch(g1, 0.016)
	var soldier_down := s.dead
	g1.reload = 0
	b._update_watch(g1, 0.016)
	ok("Watchtowers shoot enemies in range (tanks take 3 hits)", soldier_down and tank.power == 2 and shots[0] == 2)

	# Walls
	b = level1()
	me = b.towers[0]
	foe = b.towers[3]
	var w := Battle.Wall.new()
	w.x = (me.x + foe.x) / 2
	w.y = (me.y + foe.y) / 2
	w.r = 30
	b.rocks.append(w)
	me.units = 40
	ok("Walls block roads", b.link(me, foe, 1) == "blocked")

	# The enemy attacks on its own
	b = Battle.new()
	var d4 := Levels.data(4)
	b.load_map(d4)
	for t in b.towers:
		if t.owner == 2:
			t.units = 40
	for i in 20:
		b.ai_think(2, d4.ai)
	ok("The enemy builds roads to attack", b.towers.any(func(t): return t.owner == 2 and not t.roads.is_empty()))

	# Airstrike
	b = level1()
	foe = b.towers[3]
	foe.units = 30
	var booms := [0]
	b.bombed.connect(func(_t): booms[0] += 1)
	b.drop_strike(foe)
	for i in 100:
		b.update(0.02, false)
	ok("An airstrike blows up half a building", foe.units < 18 and booms[0] == 1, str(foe.units))

	# Upgrades only count in the campaign
	b = level1()
	b.boost = {"drill": 5, "boots": 3}
	me = b.towers[0]
	var campaign := b.prod_rate(me)
	b.mode = "practice"
	ok("Upgrades only work in the campaign", campaign > b.prod_rate(me))

	# Landscape and the guest's turned-around view
	b = level1()
	b.landscape = true
	b.place()
	ok("On a wide screen your base is on the left", b.towers[0].x < b.towers[3].x)
	b.landscape = false
	b.flipped = true
	b.place()
	ok("An online guest sees the map turned around", b.towers[0].y < b.towers[3].y)

	# This version's extras: castles, camps, upgrades, endless levels and the daily challenge
	b = level1()
	foe = b.towers[3]
	foe.type = "castle"
	var target := Battle.Unit.new()
	target.owner = 1
	target.from = b.towers[0]
	target.to = foe
	target.x = foe.x
	target.y = foe.y + 150
	b.units = [target]
	var fired := [0]
	b.shot.connect(func(_t, _u): fired[0] += 1)
	b._update_watch(foe, 0.1)
	ok("A boss castle shoots soldiers in its circle", fired[0] == 1 and target.dead)
	ok("Castles are tough", Battle.TYPES.castle.defense > Battle.TYPES.barracks.defense)
	var camp := Battle.Tower.new()
	camp.type = "camp"
	camp.units = 20
	camp.owner = 2
	var plain := Battle.Tower.new()
	plain.units = 20
	plain.owner = 2
	ok("Training camps train faster and are easier to take", b.prod_rate(camp) > b.prod_rate(plain) * 1.5 and Battle.TYPES.camp.defense < 1.0)
	me = b.towers[0]
	me.units = 9
	ok("An upgrade needs spare soldiers", b.upgrade(me, 1) == "soldiers")
	me.units = 50
	ok("Upgrades cost 10 then 20 soldiers, two at most", b.upgrade(me, 1) == true and b.upgrade(me, 1) == true and b.upgrade(me, 1) == "max" and is_equal_approx(me.units, 20.0))
	ok("You can't upgrade someone else's building", b.upgrade(b.towers[3], 1) == "not yours")
	b.capture(me, 2)
	ok("A captured building loses its upgrades", me.stars == 0)
	ok("Every chapter ends with a boss castle", [5, 10, 15, 20, 50, 70].all(func(n): return Levels.data(n).towers[1][4] == "castle") and Levels.data(11).towers[1][4] != "castle")
	_missions()
	ok("Levels 1-60 are still made the same way as the web version (only types and soldiers change)", Levels.data(20).towers.map(func(t): return [t[0], t[1]]) == Levels.gen(20).towers.map(func(t): return [t[0], t[1]]))
	var endless_ok := true
	for n in range(61, 160, 7):
		var d := Levels.data(n)
		if d.towers.size() < 8 or not Levels.connected(d.towers, d.rocks):
			endless_ok = false
	ok("Endless levels after 60 are all playable", endless_ok)
	ok("Endless levels get harder", Levels.data(120).towers[1][3] > Levels.data(61).towers[1][3])
	var day := 20000
	ok("The daily challenge is the same all day and different each day", Levels.daily(day).towers == Levels.daily(day).towers and Levels.daily(day).towers != Levels.daily(day + 1).towers)
	ok("The daily challenge can be played", Levels.connected(Levels.daily(day).towers, Levels.daily(day).rocks))

	# Daily reward and missions
	var sv := {"coins": 0, "level": 20}
	sv.merge(Progress.defaults())
	ok("Day 1 of the reward", Progress.claim_reward(sv, 100) == 20 and Progress.claim_reward(sv, 100) == 0)
	Progress.claim_reward(sv, 101)
	ok("The next day pays more", int(sv.streak.count) == 2 and int(sv.coins) == 50)
	ok("Missing a day starts the streak again", Progress.claim_reward(sv, 105) == 20)
	var mlist := Progress.missions(sv, 300)
	ok("3 different missions a day, the same for everyone", mlist.size() == 3 and mlist[0].id != mlist[1].id and mlist[1].id != mlist[2].id and Progress.missions(sv.duplicate(true), 300).map(func(m): return m.id) == mlist.map(func(m): return m.id))
	var sv2 := {"coins": 0, "level": 1}
	sv2.merge(Progress.defaults())
	ok("New players don't get missions for things they haven't unlocked", Progress.missions(sv2, 300).all(func(m): return m.id not in ["strike", "upgrade", "daily"]))

	# Whole games between computer players finish, and both sides win sometimes
	var wins := {1: 0, 2: 0}
	var started := Time.get_ticks_msec()
	for n in [5, 10, 20]:
		for k in 2:
			b = Battle.new()
			var data := Levels.data(n)
			b.load_map(data)
			b.ai_sides = [{"side": 1, "timer": 0.5, "cfg": data.ai}]
			for side in [2, 3, 4]:
				if b.towers.any(func(t): return t.owner == side):
					b.ai_sides.append({"side": side, "timer": 1.0, "cfg": data.ai})
			var t := 0.0
			while t < 600:
				b.update(0.05)
				t += 0.05
				if not b.alive(1) or b.ai_sides.slice(1).all(func(a): return not b.alive(a.side)):
					break
			if b.alive(1) and not b.alive(2):
				wins[1] += 1
			elif not b.alive(1):
				wins[2] += 1
	ok("Computer-vs-computer games finish with winners", wins[1] + wins[2] >= 4, str(wins))
	var ms := Time.get_ticks_msec() - started
	ok("The battle runs fast enough", ms < 60000, "%d ms for 6 games" % ms)

	_pace()

	print("SIM DONE %d failed" % fails)
	quit(1 if fails else 0)


## A campaign level's battle with its enemies and its mission's goal: [battle, mission]
func mission_battle(n: int) -> Array:
	var b := Battle.new()
	b.mode = "campaign"
	var d := Levels.data(n)
	b.load_map(d)
	for side in [2, 3, 4]:
		if b.towers.any(func(t): return t.owner == side):
			b.ai_sides.append({"side": side, "timer": 2.5, "cfg": d.ai})
	return [b, Missions.setup(n, b)]


func _missions() -> void:
	var chapters_ok := true
	for c in range(2, 14):
		var first := (c - 1) * 5 + 1
		var kinds := {}
		for n in range(first, first + 4):
			kinds[Missions.goal_for(n)] = true
		if kinds.size() < 3 or Missions.goal_for(first + 4) != "hq" or kinds.has("hq"):
			chapters_ok = false
	ok("Every chapter has at least three kinds of mission, then the boss", chapters_ok)
	ok("Every mission has a goal, a code name and a briefing", range(1, 80).all(func(n): return Missions.GOALS.has(Missions.goal_for(n)) and Missions.title(n).begins_with("Operation ") and Missions.brief(n).length() > 20))
	ok("The first levels teach the basics with plain battles", range(1, 4).all(func(n): return Missions.goal_for(n) == "conquer"))

	var r := mission_battle(4)
	var b: Battle = r[0]
	var m: Dictionary = r[1]
	ok("Defend: your HQ is one of your buildings", m.goal == "defend" and m.hq != null and m.hq.owner == Battle.PLAYER and Missions.result(m, b) == "")
	ok("Defend: Grumble's army goes for it", b.ai_sides[0].cfg.focus == m.hq.id)
	b.time = m.time
	ok("Defend: holding out until the clock runs out wins", Missions.result(m, b) == "won")
	b.time = 1.0
	b.capture(m.hq, 2)
	ok("Defend: losing the HQ loses", Missions.result(m, b) == "hq")

	r = mission_battle(6)
	b = r[0]
	m = r[1]
	var ids := {}
	for t in m.targets:
		ids[t.id] = true
	ok("Capture: two or three radar stations, none of them yours yet", m.goal == "capture" and m.targets.size() >= 2 and ids.size() == m.targets.size() and m.targets.all(func(t): return t.owner != Battle.PLAYER))
	for t in m.targets.slice(1):
		t.owner = Battle.PLAYER
	ok("Capture: not all of them isn't enough", Missions.result(m, b) == "")
	m.targets[0].owner = Battle.PLAYER
	ok("Capture: holding them all at once wins", Missions.result(m, b) == "won")

	r = mission_battle(7)
	b = r[0]
	m = r[1]
	var before: Array = b.totals()
	b.update(2.0, false)
	ok("No reinforcements: nobody trains", m.goal == "puzzle" and b.frozen and b.totals() == before)
	ok("No reinforcements: you get enough soldiers to win", before[1] >= m.start - 2 and m.start > 0)
	for t in b.towers:
		if t.owner == Battle.PLAYER:
			t.units = 1
	ok("No reinforcements: too few soldiers left loses", Missions.result(m, b) == "soldiers")

	r = mission_battle(9)
	b = r[0]
	m = r[1]
	ok("Blitz: a clock", m.goal == "blitz" and m.time > 30 and Missions.result(m, b) == "")
	b.time = m.time + 0.1
	ok("Blitz: running out of time loses", Missions.result(m, b) == "time")

	r = mission_battle(10)
	b = r[0]
	m = r[1]
	ok("Boss: the target is Grumble's castle", m.goal == "hq" and m.hq != null and m.hq.type == "castle" and m.hq.owner == 2)
	b.capture(m.hq, Battle.PLAYER)
	ok("Boss: taking the castle wins", Missions.result(m, b) == "won")
	b.time = 5.0
	ok("A quick win earns 3 stars", Missions.stars(m, b) == 3)
	b.time = 1000.0
	ok("A slow one fewer", Missions.stars(m, b) == 1)

	r = mission_battle(12)
	b = r[0]
	m = r[1]
	for t in b.towers:
		if t.owner >= 2:
			t.owner = Battle.PLAYER
	b.units.clear()
	ok("Conquer: taking every enemy building wins", Missions.result(m, b) == "won")


## The campaign plays faster than PvP, and an army that's winning finishes the job
func _pace() -> void:
	var pvp := Battle.new()
	ok("PvP keeps the web version's speed and rules", pvp.pace == 1.0 and pvp.march == 1.0 and not pvp.momentum and not pvp.frozen)
	var b := Battle.new()
	b.mode = "campaign"
	b.load_map(Levels.data(12))
	var mine: Battle.Tower = b.towers.filter(func(t): return t.owner == Battle.PLAYER)[0]
	var slow := b.prod_rate(mine)
	b.pace = 1.5
	ok("Campaign buildings train faster", is_equal_approx(b.prod_rate(mine), slow * 1.5))
	b.momentum = true
	for t in b.towers:
		if t.owner == Battle.NEUTRAL:
			t.owner = Battle.PLAYER
	b._update_momentum()
	var foe: Battle.Tower = b.towers.filter(func(t): return t.owner == 2)[0]
	ok("Momentum: holding more buildings than the enemy trains faster", b.prod_rate(mine) > slow * 1.5 * 1.1)
	ok("Momentum: an enemy holding fewer trains slower", b.prod_rate(foe) < 1.5 * (0.55 + 0.2 * foe.level()) * Battle.TYPES[foe.type].prod)
	for t in b.towers:
		if t != mine and t.owner == Battle.PLAYER:
			t.owner = 2
	b._update_momentum()
	ok("Momentum never works against you", is_equal_approx(b.prod_rate(mine), slow * 1.5) and is_equal_approx(b.prod_rate(foe), 1.5 * (0.55 + 0.2 * foe.level()) * Battle.TYPES[foe.type].prod * (1 + Battle.STAR_BONUS * foe.stars)))
