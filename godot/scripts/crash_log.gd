class_name CrashLog
extends RefCounted
## Finding out why the game closed. The game notes what it's doing in its log (Godot keeps the
## last few logs on the phone), and leaves a marker file while it's open. If the marker is
## still there at the next start, the game closed without saying goodbye: a crash. Settings
## can then copy the logs, so the player can send them to the developer.

const FLAG := "user://running.flag"
const LOGS := "user://logs"


## Call once at start: true if the last session crashed
static func started() -> bool:
	var crashed := FileAccess.file_exists(FLAG)
	running()
	note("start  %s" % device())
	return crashed


## The game is open (again): leave the marker
static func running() -> void:
	var f := FileAccess.open(FLAG, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())


## The game is closing or going to the background on purpose: no crash
static func stopped() -> void:
	if FileAccess.file_exists(FLAG):
		DirAccess.remove_absolute(FLAG)


## A line in the log, so a crash report shows what was happening
static func note(text: String) -> void:
	print("[cc] ", text)


static func device() -> String:
	var mem: Dictionary = OS.get_memory_info()
	return "%s %s | Android/OS %s | %s | %.1f GB | %s | gfx %s %d fps | v%s" % [
		OS.get_model_name(), OS.get_name(), OS.get_version(), RenderingServer.get_video_adapter_name(),
		mem.get("physical", 0) / 1073741824.0, OS.get_locale(), Gfx.LEVELS[mini(Gfx.level, Gfx.LEVELS.size() - 1)], Gfx.fps,
		ProjectSettings.get_setting("application/config/version", "")]


## Device details and the end of the last few logs, newest first, for pasting into a message
static func report() -> String:
	var out := "Color Claim log\n" + device() + "\n"
	var files: Array = []
	var dir := DirAccess.open(LOGS)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".log"):
				files.append(f)
	# godot.log is this session; the dated ones are older sessions (newest name last)
	files.sort()
	files.reverse()
	if files.has("godot.log"):
		files.erase("godot.log")
		files.insert(0, "godot.log")
	for f in files.slice(0, 3):
		var text := FileAccess.get_file_as_string(LOGS + "/" + f)
		var lines := text.split("\n")
		out += "\n--- %s (last %d lines) ---\n" % [f, mini(lines.size(), 60)]
		out += "\n".join(lines.slice(maxi(0, lines.size() - 60)))
	if files.is_empty():
		out += "\n(no logs on this phone yet)"
	return out
