class_name Net
extends Node
## PvP, the leaderboard and clans. (Coming in the next stage; for now online play says so.)

const PVP_TIME := 180.0

var main
var role := ""


func is_guest() -> bool:
	return main != null and main.mode == "online" and role == "guest"


func event(_e: Array) -> void:
	pass


func check_end() -> void:
	pass


func host_tick(_dt: float) -> void:
	pass


func guest_update(_dt: float) -> void:
	pass


func send(_msg: Dictionary) -> void:
	pass


func leave() -> void:
	role = ""


func restart() -> void:
	main.open_menu()


func open_pvp() -> void:
	main.ui.toast("PvP is coming soon in this version")


func open_board() -> void:
	main.ui.toast("The leaderboard is coming soon in this version")


func open_clans() -> void:
	main.ui.toast("Clans are coming soon in this version")
