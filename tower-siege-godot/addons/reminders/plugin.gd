@tool
extends EditorPlugin
## Puts the game's Android library (Reminders.aar: scheduled notifications, the screen's refresh
## rate, rewarded ads) into Android builds, and the Google Mobile Ads library it uses (the version
## build_aar.sh compiled against, in ads_version.txt). Only Gradle builds can take them; build
## the library first with android/reminders/build_aar.sh.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = RemindersExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class RemindersExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "Reminders"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		var f := FileAccess.open("res://addons/reminders/ads_version.txt", FileAccess.READ)
		if f == null:
			return PackedStringArray()
		var v := f.get_as_text().strip_edges()
		return PackedStringArray(["com.google.android.gms:play-services-ads:" + v]) if v != "" else PackedStringArray()

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if FileAccess.file_exists("res://addons/reminders/Reminders.aar"):
			return PackedStringArray(["reminders/Reminders.aar"])
		return PackedStringArray()
