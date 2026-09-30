extends SceneTree
## Google Play Games without a phone: a stand-in for the Android plugin sends the same
## signals and JSON the real one does, and records what the game asks it to do.
## Run: godot --headless --path godot -s tests/playgames.gd

const SAVE := "user://save.cfg"

var main
var fake: FakePlugin
var fails := 0
var _backup := ""


## Answers like GodotPlayGameServices does on Android
class FakePlugin extends Object:
	signal userAuthenticated(ok: bool)
	signal currentPlayerLoaded(json: String)
	signal gameLoaded(json: String)
	signal gameSaved(ok: bool, name: String, description: String)
	signal conflictEmitted(json: String)
	var calls: Array[String] = []
	var saved := PackedByteArray()
	var saved_progress := 0
	var scores := {}

	func initialize() -> void:
		calls.append("initialize")

	func isAuthenticated() -> void:
		calls.append("isAuthenticated")

	func signIn() -> void:
		calls.append("signIn")

	func loadCurrentPlayer(_force: bool) -> void:
		calls.append("loadCurrentPlayer")

	func loadGame(_file: String, _create: bool) -> void:
		calls.append("loadGame")

	func saveGame(file: String, description: String, data: PackedByteArray, _time: int, progress: int) -> void:
		calls.append("saveGame")
		saved = data
		saved_progress = progress
		gameSaved.emit(true, file, description)

	func submitScore(id: String, value: int) -> void:
		scores[id] = value

	func showAllLeaderboards() -> void:
		calls.append("showAllLeaderboards")


func _initialize() -> void:
	if FileAccess.file_exists(SAVE):
		_backup = FileAccess.get_file_as_string(SAVE)
	fake = FakePlugin.new()
	Engine.register_singleton("GodotPlayGameServices", fake)
	# A brand-new phone: a little progress and its own settings
	var c := ConfigFile.new()
	c.set_value("player", "welcomed", true)
	c.set_value("player", "coins", 5)
	c.set_value("progress", "data", {"level": 1, "xp": 10, "stats": {"games": 1}, "tutorial": true})
	c.set_value("settings", "controls", "tap")
	c.set_value("settings", "lang", "en")
	c.save(SAVE)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func ok(name: String, cond: bool, extra := "") -> void:
	print(("PASS " if cond else "FAIL ") + name + ("  " + extra if extra else ""))
	if not cond:
		fails += 1


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## The save as the plugin sends it: bytes as numbers from -128 to 127
func _as_plugin_json(c: ConfigFile) -> String:
	var list := []
	for b in c.encode_to_text().to_utf8_buffer():
		list.append(b - 256 if b > 127 else b)
	return JSON.stringify({"content": list, "metadata": {"uniqueName": "colorclaim-save"}})


func _cloud_save(level: int, coins: int, name: String) -> ConfigFile:
	var c := ConfigFile.new()
	c.set_value("player", "welcomed", true)
	c.set_value("player", "coins", coins)
	c.set_value("player", "name", name)
	c.set_value("progress", "data", {"level": level, "xp": 5, "stats": {"games": 40, "wins": 12}, "tutorial": true})
	c.set_value("settings", "controls", "stick")
	c.set_value("settings", "lang", "hi")
	return c


func _settings_text() -> String:
	var out := []
	var todo: Array[Node] = [main.settings_screen]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n is Label or n is Button:
			out.append(n.text)
		todo.append_array(n.get_children())
	return " | ".join(out)


func _run() -> void:
	await _wait(0.5)
	var pg: PlayGames = main.pg
	ok("The plugin is found and started", pg.is_on() and fake.calls.has("initialize") and fake.calls.has("isAuthenticated"), str(fake.calls))
	ok("Nothing is uploaded before signing in", not fake.calls.has("saveGame"))
	main.settings_screen.open()
	await process_frame
	var text := _settings_text()
	ok("Settings offers the sign-in button", text.contains("GOOGLE PLAY GAMES") and text.contains("Sign in with Google Play Games"), text.left(200))
	for n in main.settings_screen.find_children("*", "Button", true, false):
		if n.text == "Sign in with Google Play Games":
			n.pressed.emit()
	ok("The button asks Play Games to sign in", fake.calls.has("signIn"))

	# Signed in: the name arrives and the cloud save is read
	fake.userAuthenticated.emit(true)
	fake.currentPlayerLoaded.emit(JSON.stringify({"displayName": "AcePlayer", "playerId": "123"}))
	await process_frame
	ok("Signing in reads the player and the cloud save", pg.signed_in and fake.calls.has("loadCurrentPlayer") and fake.calls.has("loadGame"))
	ok("The Play Games name is known", pg.display_name == "AcePlayer", pg.display_name)
	text = _settings_text()
	ok("Settings says who is signed in", text.contains("Signed in as AcePlayer"), text.left(200))
	main.settings_screen.close()
	await process_frame

	# A new phone: the cloud has more progress (and a name with non-English letters)
	fake.gameLoaded.emit(_as_plugin_json(_cloud_save(9, 4321, "मैक्स")))
	await process_frame
	ok("The cloud save replaces the new phone's save", main.prog.level == 9 and main.wallet == 4321, "level %d coins %d" % [main.prog.level, main.wallet])
	ok("Names in any language survive the trip", main.player_name == "मैक्स", main.player_name)
	ok("This phone keeps its own settings", main.controls == "tap" and I18n.lang == "en", "%s %s" % [main.controls, I18n.lang])
	ok("It's still on the menu", main.state == "menu" and main.menu.visible)
	ok("Nothing went up yet: the save just came down", not fake.calls.has("saveGame"))

	# Playing and saving sends the save up (after the upload gap, or at once when paused)
	main._save()
	pg.flush()
	var up := ConfigFile.new()
	ok("A save goes up to the cloud", fake.calls.has("saveGame") and up.parse(fake.saved.get_string_from_utf8()) == OK)
	ok("It's the whole save", up.get_value("player", "coins", 0) == 4321 and up.get_value("player", "name", "") == "मैक्स")
	ok("Its progress value is the XP earned", fake.saved_progress == PlayGames.total_xp(up) and fake.saved_progress > 1000, str(fake.saved_progress))
	var n_up := pg.uploads
	pg.saved()
	await _wait(0.2)
	ok("Uploads wait for the gap between them", pg.uploads == n_up)

	# A cloud save with less progress never replaces this one
	fake.gameLoaded.emit(_as_plugin_json(_cloud_save(2, 1, "Old")))
	await process_frame
	ok("An older cloud save is ignored", main.prog.level == 9 and main.wallet == 4321 and pg.pending == null)

	# A newer cloud save that arrives mid-game waits for the menu
	main.mode_id = "classic"
	main.start_game()
	main.countdown = 0.0
	await process_frame
	fake.gameLoaded.emit(_as_plugin_json(_cloud_save(15, 9999, "Maxi")))
	await process_frame
	ok("Mid-game it waits", main.state != "menu" and pg.pending != null and main.prog.level == 9, main.state)
	main._to_menu()
	await _wait(0.8)
	ok("Back at the menu it's applied", main.state == "menu" and main.prog.level == 15 and main.wallet == 9999 and pg.pending == null,
		"%s level %d" % [main.state, main.prog.level])

	# No cloud save yet: this phone's goes up
	pg.cloud_checked = false
	fake.gameLoaded.emit("null")
	await process_frame
	ok("With no cloud save, ours goes up", pg.cloud_checked and pg._dirty)

	# Leaderboards
	pg.submit("CgkLeader", 123)
	ok("Scores go to Play Games", fake.scores.get("CgkLeader", 0) == 123)
	ok("Leaderboards stay off without their IDs", not Services.leaderboards_ready())

	# Signed out: nothing goes up
	fake.userAuthenticated.emit(false)
	await process_frame
	var calls_before := fake.calls.size()
	pg.saved()
	pg.flush()
	ok("Signed out, nothing is uploaded", fake.calls.size() == calls_before)

	# Bytes the plugin sends back
	var round_trip := PlayGames.to_bytes([-1, 0, 127, -128, 65])
	ok("Signed bytes are read correctly", round_trip == PackedByteArray([255, 0, 127, 128, 65]))

	print("PLAYGAMES %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	if _backup != "":
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(_backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main.queue_free()
	Engine.unregister_singleton("GodotPlayGameServices")
	await process_frame
	fake.free()
	quit(1 if fails else 0)
