@tool
extends EditorPlugin
## Puts the reminders library (Reminders.aar: scheduled notifications) into Android builds.
## Only Gradle builds can take it; build it first with android/reminders/build_aar.sh.

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

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if FileAccess.file_exists("res://addons/reminders/Reminders.aar"):
			return PackedStringArray(["reminders/Reminders.aar"])
		return PackedStringArray()
