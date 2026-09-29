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
	while main.state != "play" and waited < 10.0:
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
	while t < seconds:
		await create_timer(0.1).timeout
		t += 0.1
		turn -= 0.1
		var me: Player = w.me
		if me and me.alive and turn <= 0:
			me.desired = randf() * TAU
			turn = randf_range(0.4, 1.5)
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
	print("RESULT %s room=%d id=%d people_seen=%s max_people=%d my_land=%.1f%% deaths=%d respawns=%d count_mismatches=%d players=%d snapshots=%d board_mismatches=%d rounds=%d" % [
		tester, main.online.room, me.id if me else -1, names.keys(), max_people, w.pct(me) if me else 0.0, deaths, respawns, mismatches,
		w.players.filter(func(p): return p != null).size(), main.online.snaps, main.online.desyncs, main.online.round_no])
	main._to_menu()
	await create_timer(0.3).timeout
	# A failure if the board ever differed from the server's, or nothing arrived
	quit(1 if main.online.desyncs > 0 or mismatches > 0 or main.online.snaps < 10 else 0)
