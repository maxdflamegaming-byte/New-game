extends SceneTree
## Prints every level and a few PvP maps as JSON, to compare with the web version:
##   godot --headless --path tower-siege-godot -s tests/dump_levels.gd -- OUT.json

func _initialize() -> void:
	var out := {}
	for n in range(1, 61):
		var d := Levels.data(n)
		out["L%d" % n] = {"towers": d.towers.map(func(t): return [t[0], t[1], t[2], t[3], t[4] if t.size() > 4 else "barracks"]), "rocks": d.rocks}
	for s in [1, 7, 12345, 987654321, 555555555]:
		var d := Levels.gen(14, true, s)
		out["P%d" % s] = {"towers": d.towers, "rocks": d.rocks}
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()
