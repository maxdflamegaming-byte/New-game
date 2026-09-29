extends Node
## The messages between the game and the online server. The same script runs on both sides
## (Godot matches remote calls by the script's list of @rpc functions, so they must be
## identical); each side hands what it receives to its own handler.
##
## The phone sends only its name and looks when it joins, its steering, and "respawn". The
## server runs the real game and sends the round (map and everyone in it) and ~15 snapshots a
## second: where everyone is, which cells changed, and what happened.

const PROTOCOL := 1

## Whoever handles incoming messages: the room manager on the server, the online client on
## a phone. It gets on_<message>(peer_id, data).
var handler: Object


func _call(what: String, data) -> void:
	if handler and handler.has_method(what):
		handler.call(what, multiplayer.get_remote_sender_id(), data)


# ---------- Phone -> server ----------

@rpc("any_peer", "call_remote", "reliable")
func c_join(info: Dictionary) -> void:
	_call("on_join", info)


@rpc("any_peer", "call_remote", "reliable")
func c_input(angle: float) -> void:
	_call("on_input", angle)


@rpc("any_peer", "call_remote", "reliable")
func c_respawn(_x: int) -> void:
	_call("on_respawn", 0)


# ---------- Server -> phone ----------

@rpc("authority", "call_remote", "reliable")
func s_welcome(data: Dictionary) -> void:
	_call("on_welcome", data)


@rpc("authority", "call_remote", "reliable")
func s_round(data: Dictionary) -> void:
	_call("on_round", data)


@rpc("authority", "call_remote", "reliable")
func s_snap(data: Dictionary) -> void:
	_call("on_snap", data)


@rpc("authority", "call_remote", "reliable")
func s_round_over(data: Dictionary) -> void:
	_call("on_round_over", data)


@rpc("authority", "call_remote", "reliable")
func s_error(data: Dictionary) -> void:
	_call("on_error", data)
