extends SceneTree
## The Color Claim online server. Run it with Godot (no screen needed):
##   godot --headless --path godot -s server/run.gd            (port 9080, or $PORT)
##   godot --headless --path godot -s server/run.gd -- 9090
## Phones connect with a WebSocket to ws://<host>:<port> (wss:// behind a host that adds
## HTTPS, like Render or Fly.io). See SERVER.md at the top of the repository.

var peer: WebSocketMultiplayerPeer


func _initialize() -> void:
	var port := 9080
	if OS.has_environment("PORT"):
		port = int(OS.get_environment("PORT"))
	var args := OS.get_cmdline_user_args()
	var round_time := 300.0
	for a in args:
		if a.begins_with("--round="):
			round_time = float(a.substr(8)) # shorter rounds, for testing
		elif a.is_valid_int():
			port = int(a)
	peer = WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1 << 16
	peer.outbound_buffer_size = 1 << 22
	peer.max_queued_packets = 4096
	var err := peer.create_server(port, "*")
	if err != OK:
		printerr("Couldn't open port %d (error %d)" % [port, err])
		quit(1)
		return
	get_multiplayer().multiplayer_peer = peer
	var net := preload("res://scripts/net/net.gd").new()
	net.name = "Net"
	root.add_child(net)
	var rooms := preload("res://scripts/net/rooms.gd").new()
	rooms.name = "Rooms"
	rooms.net = net
	rooms.ROUND_TIME = round_time
	root.add_child(rooms)
	print("[server] Color Claim server on port %d, protocol %d" % [port, net.PROTOCOL])
