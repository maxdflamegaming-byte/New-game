class_name Analytics
extends Node
## Anonymous level stats, so we can see where players get stuck: for each campaign level,
## when it's started, won (its time and stars), lost (and why) or left unfinished. Nothing
## identifies the player: no account, no device id, just level numbers and seconds.
## The rows wait in the save and go to the game's own server (POST /stats) in a batch, at most
## every half hour. Only installed builds send (never the editor or the tests, unless a test
## sets `url`), and Settings can switch it off.

const SEND_EVERY := 1800.0     # seconds between batches
const MOST := 300              # rows kept while waiting to send

var main
var url := ""                  # where to send; "" = the game server's /stats (installed builds only)
var _sending := false
var _last_sent := -INF


func enabled() -> bool:
	return bool(main.save.get("stats", true))


## Something happened in campaign level n (0 = the daily challenge)
func track(n: int, what: String, secs := 0.0, extra: Variant = "") -> void:
	if not enabled():
		return
	var rows: Array = main.save.get("stats_rows", [])
	rows.append([n, what, roundi(secs), extra])
	if rows.size() > MOST:
		rows = rows.slice(rows.size() - MOST)
	main.save.stats_rows = rows
	flush()


func _target() -> String:
	if url != "":
		return url
	if not OS.has_feature("template"):
		return ""          # running in the editor or a test: don't send
	return main.net.server_url().replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/") + "/stats"


## Send what's waiting, if it's been long enough since the last batch
func flush(force := false) -> void:
	var rows: Array = main.save.get("stats_rows", [])
	var to := _target()
	if _sending or rows.is_empty() or to == "" or not enabled():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _last_sent < SEND_EVERY:
		return
	_sending = true
	_last_sent = now
	var batch := rows.duplicate()
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var body := JSON.stringify({"v": 1, "app": ProjectSettings.get_setting("application/config/version", ""), "rows": batch})
	if http.request(to, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) == OK:
		var res: Array = await http.request_completed
		if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200:
			# Only what was sent is cleared; rows added meanwhile stay for the next batch
			var left: Array = main.save.get("stats_rows", [])
			main.save.stats_rows = left.slice(mini(batch.size(), left.size()))
			main.write_save()
	http.queue_free()
	_sending = false
