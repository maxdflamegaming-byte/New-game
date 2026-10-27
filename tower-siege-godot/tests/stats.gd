extends SceneTree
## Level stats from the app reach the server: plays level 1 (won), starts level 2 and leaves it,
## then sends the stats to the server given (used by online_match.sh, which checks the report).
##   godot --headless --path tower-siege-godot -s tests/stats.gd -- --server=ws://127.0.0.1:PORT

var main


func _initialize() -> void:
	for f in ["user://tower_siege.json", "user://tower_siege.json.bak", "user://tower_siege.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.cinematics = false
	_run()


func _run() -> void:
	for i in 5:
		await process_frame
	# Send to the test server (the tests don't send anywhere unless told where)
	main.analytics.url = main.net.server_url().replace("ws://", "http://") + "/stats"
	main.analytics._last_sent = Time.get_ticks_msec() / 1000.0   # hold the batch until the end
	main.start_level(1)
	await process_frame
	for t in main.battle.towers:
		if t.owner == 2:
			t.owner = 1
	main.battle.units.clear()
	for i in 5:
		await process_frame
	main.start_level(2)
	await process_frame
	main.open_menu()
	print("GD STATS ROWS ", JSON.stringify(main.save.stats_rows))
	await main.analytics.flush(true)
	print("GD STATS LEFT ", main.save.stats_rows.size())
	quit()
