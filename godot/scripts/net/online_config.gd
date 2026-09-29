class_name OnlineConfig
extends RefCounted
## Where the online server is. Empty until the server is running somewhere (see SERVER.md):
## then this is its address, like "wss://color-claim.onrender.com". For testing, start the
## game with -- --server=ws://127.0.0.1:9080 to use another one.

const SERVER_URL := ""


static func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.substr(9)
	return SERVER_URL
