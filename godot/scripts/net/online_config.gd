class_name OnlineConfig
extends RefCounted
## Where the online server is (see SERVER.md). For testing, start the game with
## -- --server=ws://127.0.0.1:9080 to use another one, or -- --server= to switch online off.

const SERVER_URL := "wss://color-claim-server.onrender.com"

## Tests that shouldn't touch the real server set this
static var off := false


static func server_url() -> String:
	if off:
		return ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.substr(9)
	return SERVER_URL
