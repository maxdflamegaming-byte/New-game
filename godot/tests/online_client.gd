extends SceneTree
## A test player for the online server: runs the real game, joins online and steers at
## random, then prints what it saw. Start the server first, then one or more of these:
##   godot --headless --path godot -s tests/online_client.gd -- --server=ws://127.0.0.1:9080 --name=Tester --seconds=30

var main
var seconds := 30.0
var tester := "Tester"
var shot := "" # a screenshot after 12 seconds (run under xvfb-run with rendering)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a.begins_with("--name="):
			tester = a.substr(7)
		elif a.begins_with("--shot="):
			shot = a.substr(7)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _run() -> void:
	await create_timer(0.5).timeout
	main.welcomed = true
	main.welcome.visible = false
	main.crash_box.visible = false
	main.prog.tutorial_done = true
	main.player_name = tester
	main.mode_id = "online"
	main.start_game()
	var waited := 0.0
	while main.state != "play" and waited < 80.0:
		await create_timer(0.1).timeout
		waited += 0.1
	if main.state != "play":
		print("RESULT %s could not join: state=%s status=%s" % [tester, main.state, main.online.status])
		quit(1)
		return
	var w = main.world
	var snaps := 0
	var deaths := 0
	var respawns := 0
	var mismatches := 0
	var max_people := 0
	var names := {}
	var t := 0.0
	var turn := 0.0
	# Steering must reach the server: a second after each turn, the server's own report of
	# our heading should match it
	var steer_ok := 0
	var steer_bad := 0
	var check_at := -1.0
	# How fast the server's game runs compared with real time (1.0 = full speed)
	var start_ms := Time.get_ticks_msec()
	var game_time := 0.0 # summed over rounds
	var last_time: float = w.time
	var start_snaps: int = main.online.snaps
	while t < seconds:
		await create_timer(0.1).timeout
		t += 0.1
		turn -= 0.1
		var gt: float = w.time - last_time
		if gt > 0.0 and gt < 1.0:
			game_time += gt
		last_time = w.time
		var me: Player = w.me
		if check_at > 0 and t >= check_at:
			check_at = -1.0
			var list: Array = main.online._samples.get(me.id, []) if me and me.alive else []
			if not list.is_empty():
				if absf(wrapf(list.back()[2] - me.desired, -PI, PI)) < 0.35:
					steer_ok += 1
				else:
					steer_bad += 1
		if me and me.alive and turn <= 0:
			me.desired = randf() * TAU
			turn = randf_range(1.2, 2.0)
			check_at = t + 1.0
		if main.state == "over":
			deaths += 1
			main.start_game() # Play again
			respawns += 1
		# The board stays consistent: counts match the land
		var cnt := {}
		for i in w.N * w.N:
			if w.land[i]:
				cnt[w.land[i]] = cnt.get(w.land[i], 0) + 1
		for p in w.players:
			if p and cnt.get(p.id, 0) != w.counts[p.id]:
				mismatches += 1
			if p and not p.is_bot:
				names[p.name] = true
		max_people = maxi(max_people, w.humans_in_room())
		snaps += 1
		if shot != "" and absf(t - 12.0) < 0.05:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot)
	var me: Player = w.me
	var wall_s := (Time.get_ticks_msec() - start_ms) / 1000.0
	var game_rate: float = game_time / wall_s
	print("SPEED %s server_game_speed=%.2f snapshots_per_s=%.1f steering_ok=%d steering_missed=%d snapbacks=%d avg_drift=%.2f" % [
		tester, game_rate, (main.online.snaps - start_snaps) / wall_s, steer_ok, steer_bad, main.online.snapbacks,
		main.online.drift_sum / maxi(1, main.online.drift_frames)])
	print("RESULT %s room=%d id=%d people_seen=%s max_people=%d my_land=%.1f%% deaths=%d respawns=%d count_mismatches=%d players=%d snapshots=%d board_mismatches=%d rounds=%d" % [
		tester, main.online.room, me.id if me else -1, names.keys(), max_people, w.pct(me) if me else 0.0, deaths, respawns, mismatches,
		w.players.filter(func(p): return p != null).size(), main.online.snaps, main.online.desyncs, main.online.round_no])
	main._to_menu()
	await create_timer(0.3).timeout
	# A failure if the board ever differed from the server's, or nothing arrived
	quit(1 if main.online.desyncs > 0 or mismatches > 0 or main.online.snaps < 10 or steer_ok < steer_bad else 0)
