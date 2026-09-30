class_name PlayGames
extends Node
## Google Play Games: signing in, the cloud save and the leaderboards.
##
## This only does something in builds made with the Play Games plugin. The build adds the
## plugin by itself once Services.CONFIG has a Play Games ID (see ONLINE-AND-MONEY.md at the
## top of the repository). In every other build is_on() is false and nothing shows.
##
## Signing in is automatic on Android when the player has a Play Games profile; otherwise the
## Settings screen has a "Sign in" button. Once signed in, the save file goes to the player's
## Google account after each game (at most every UPLOAD_GAP seconds, and when the game goes to
## the background). On a new phone the saved progress comes back: when the cloud save has more
## progress than the one on the phone, it replaces it, keeping this phone's settings.

signal changed ## signed in or out, or the player's name arrived
signal cloud_newer ## the cloud save has more progress; main applies it when at the menu

const PLUGIN := "GodotPlayGameServices"
const SLOT := "colorclaim-save" # the save's name in the player's Google account
const UPLOAD_GAP := 30.0 # seconds
const RETRY := 60.0 # seconds before asking for the cloud save again if nothing came back

## The one in the game (for Services)
static var me: PlayGames

var plugin: Object
var save_path := "user://save.cfg"
var signed_in := false
var display_name := ""
## The cloud save was read (or there isn't one): only then is uploading safe, so a new phone's
## empty save can't replace real progress
var cloud_checked := false
## A cloud save with more progress, waiting to be applied
var pending: ConfigFile
var uploads := 0 # for tests
var _dirty := false
var _clock := 0.0
var _last_upload := -1000.0
var _asked_cloud := -1000.0


func _ready() -> void:
	me = self
	if not Engine.has_singleton(PLUGIN):
		return
	plugin = Engine.get_singleton(PLUGIN)
	_hook("userAuthenticated", _on_authenticated)
	_hook("currentPlayerLoaded", _on_player)
	_hook("gameLoaded", _on_game_loaded)
	_hook("gameSaved", func(ok: bool, _name: String, _desc: String):
		CrashLog.note("cloud  saved %s" % ok))
	_hook("conflictEmitted", func(_json: String):
		CrashLog.note("cloud  conflict")
		_asked_cloud = -1000.0
		cloud_checked = false) # read it again; the newer one wins
	plugin.initialize()
	plugin.isAuthenticated()


func _exit_tree() -> void:
	if me == self:
		me = null


func _hook(sig: String, f: Callable) -> void:
	if plugin.has_signal(sig):
		plugin.connect(sig, f)


## Is Play Games in this build?
func is_on() -> bool:
	return plugin != null


## The button in Settings
func sign_in() -> void:
	if plugin:
		plugin.signIn()


func _on_authenticated(ok: bool) -> void:
	CrashLog.note("play games  signed in %s" % ok)
	signed_in = ok
	if ok:
		plugin.loadCurrentPlayer(false)
		_ask_cloud()
	changed.emit()


func _on_player(json: String) -> void:
	var d = JSON.parse_string(json)
	if d is Dictionary:
		display_name = NetCodec.clean_name(str(d.get("displayName", "")))
		changed.emit()


# ---------- The cloud save ----------

func _ask_cloud() -> void:
	_asked_cloud = _clock
	plugin.loadGame(SLOT, false)


func _on_game_loaded(json: String) -> void:
	var d = JSON.parse_string(json)
	var cloud := ConfigFile.new()
	if d is Dictionary and d.get("content") is Array:
		var text := to_bytes(d.content).get_string_from_utf8()
		if text != "" and cloud.parse(text) == OK and score(cloud) > score(_local()):
			CrashLog.note("cloud  newer save found")
			pending = cloud
			cloud_newer.emit()
			return
	# No cloud save yet, or ours has more progress: ours goes up
	cloud_checked = true
	_dirty = true


## Call when the game can swap the save (at the menu). Returns true if it did; the caller
## then reloads the save.
func apply_pending() -> bool:
	if pending == null:
		return false
	var cloud := pending
	pending = null
	cloud_checked = true
	var local := _local()
	if score(cloud) <= score(local):
		_dirty = true # a game finished meanwhile and now this phone is ahead
		return false
	# This phone keeps its own settings (graphics, controls, language and sound)
	if local.has_section("settings"):
		if cloud.has_section("settings"):
			cloud.erase_section("settings")
		for k in local.get_section_keys("settings"):
			cloud.set_value("settings", k, local.get_value("settings", k))
	var tmp := save_path + ".new"
	if cloud.save(tmp) != OK:
		return false
	DirAccess.rename_absolute(tmp, save_path)
	CrashLog.note("cloud  save restored")
	return true


## The game saved: send it up soon
func saved() -> void:
	_dirty = true


## The game is going to the background: send it up now
func flush() -> void:
	if _dirty:
		_upload()


func _process(delta: float) -> void:
	_clock += delta
	if not signed_in:
		return
	if not cloud_checked and pending == null and _clock - _asked_cloud > RETRY:
		_ask_cloud()
	if _dirty and _clock - _last_upload >= UPLOAD_GAP:
		_upload()


func _upload() -> void:
	if not signed_in or not cloud_checked or not FileAccess.file_exists(save_path):
		return
	var c := _local()
	var data := c.encode_to_text().to_utf8_buffer()
	if data.is_empty():
		return
	_dirty = false
	_last_upload = _clock
	uploads += 1
	var p: Dictionary = c.get_value("progress", "data", {})
	var st: Dictionary = p.get("stats", {})
	plugin.saveGame(SLOT, "Level %d" % int(p.get("level", 1)), data,
		int(float(st.get("time", 0.0)) * 1000.0), total_xp(c))


func _local() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(save_path)
	return c


## How far a save has got: all the XP ever earned, then games played
static func score(c: ConfigFile) -> int:
	var p: Dictionary = c.get_value("progress", "data", {})
	var st: Dictionary = p.get("stats", {})
	return total_xp(c) * 100000 + mini(int(st.get("games", c.get_value("stats", "games", 0))), 99999)


static func total_xp(c: ConfigFile) -> int:
	var p: Dictionary = c.get_value("progress", "data", {})
	var level := clampi(int(p.get("level", 1)), 1, 10000)
	var t := int(p.get("xp", 0))
	for l in range(1, level):
		t += Progress.need(l)
	return t


## The plugin sends the save's bytes as a list of numbers from -128 to 127
static func to_bytes(list: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(list.size())
	for i in list.size():
		out[i] = int(list[i]) & 255
	return out


# ---------- Leaderboards ----------

func submit(leaderboard: String, value: int) -> void:
	if signed_in and leaderboard != "":
		plugin.submitScore(leaderboard, value)


func show_leaderboards() -> void:
	if not plugin:
		return
	if signed_in:
		plugin.showAllLeaderboards()
	else:
		sign_in()
