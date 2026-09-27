extends SceneTree
## Headless check of the rules and bots: plays bots-only games and checks the board stays
## consistent. Run: godot --headless --path godot -s tests/sim.gd

func _init() -> void:
	var World = load("res://scripts/world.gd")
	var w = World.new()
	var issues := {}
	var knockouts := {"self": 0, "other": 0}
	w.knocked_out.connect(func(v, k, _how, _lost): knockouts["self" if k == v else "other"] += 1)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var picked := {}
	w.picked.connect(func(_p, kind, _at): picked[kind] = picked.get(kind, 0) + 1)
	for game in 5:
		var map: String = w.MAPS.keys()[game % w.MAPS.size()]
		w.setup(game, "", true, map)
		for f in 60 * 60:
			w.update(1.0 / 60)
			frames += 1
			if not w.me.alive:
				w.spawn(w.me)
			if f % 30:
				continue
			var played := 0
			for i in w.N * w.N:
				if w.wall[i] == 0:
					played += 1
			if played != w.play_cells:
				issues["play cells wrong"] = issues.get("play cells wrong", 0) + 1
			var cnt := PackedInt32Array()
			cnt.resize(16)
			for i in w.N * w.N:
				if w.land[i]:
					cnt[w.land[i]] += 1
				if w.wall[i] and (w.land[i] or w.trail[i]):
					issues["land or trail on a wall"] = issues.get("land or trail on a wall", 0) + 1
				if w.trail[i] and not w.players[w.trail[i]].alive:
					issues["orphan trail"] = issues.get("orphan trail", 0) + 1
			for p in w.players:
				if p == null:
					continue
				if cnt[p.id] != w.counts[p.id]:
					issues["counts mismatch"] = issues.get("counts mismatch", 0) + 1
				if p.alive and w.wall[p.cell.y * w.N + p.cell.x] != 0:
					issues["inside a wall"] = issues.get("inside a wall", 0) + 1
				if p.alive and w.counts[p.id] == 0:
					issues["alive with no land"] = issues.get("alive with no land", 0) + 1
				if p.alive:
					for i in p.trail:
						if w.trail[i] != p.id and w.trail[i] != 0:
							issues["trail list mismatch"] = issues.get("trail list mismatch", 0) + 1
	var ms := Time.get_ticks_msec() - t0
	var sizes := []
	for p in w.players:
		if p:
			sizes.append("%s %.1f%%" % [p.name, w.pct(p)])
	print("frames=%d time=%dms (%.2f ms/frame) knockouts=%s" % [frames, ms, float(ms) / frames, knockouts])
	print("sizes: ", ", ".join(sizes))
	print("power-ups grabbed: ", picked, "  coins left: ", w.coins.size())
	print("ISSUES: ", issues if issues else "none")
	w.free()
	quit(1 if issues else 0)
