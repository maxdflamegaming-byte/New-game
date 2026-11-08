class_name Analytics
extends Node
## Anonymous gameplay statistics for Google Analytics, sent straight to Google over HTTPS
## (GA4's Measurement Protocol: no plugin and nothing extra inside the app).
##
## Each phone gets a random ID made here (only once something is really sent); nothing personal
## is sent (no name, no advertising ID). Players can switch it off in Settings -> Privacy. Where
## the law asks for consent first (Europe, the UK, Switzerland: see Ads.consent_region), it stays
## off unless the player switches it on there themselves. Events wait in a queue and go out in
## small batches every FLUSH_EVERY seconds and when the game goes to the background.
## Only sends from a phone: on a computer (tests, the editor) events are only counted.

const ENDPOINT := "https://www.google-analytics.com/mp/collect?measurement_id=%s&api_secret=%s"
const ID_FILE := "user://analytics.cfg"
const FLUSH_EVERY := 15.0 # seconds
const MAX_BATCH := 25 # Google's limit per request
const MAX_QUEUE := 200

static var me: Analytics
static var test_mode := false # tests: record events as if configured (never sent: not a phone)
static var test_region := -2 # tests: pretend Ads.consent_region() said this (-2: ask Ads)

var enabled := true # the switch in Settings (saved with the game's settings)
var chosen := false # the player set that switch themselves (also saved)
var client_id := ""
var session_id := ""
var queue: Array[Dictionary] = []
var sent := 0 # events sent (or, off the phone, that would have been sent)
var _http: HTTPRequest
var _busy := false
var _clock := 0.0
var _last_flush := 0.0
var _last_event_ms := 0


func _ready() -> void:
	me = self
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(func(_result, _code, _headers, _body): _busy = false)
	session_id = str(int(Time.get_unix_time_from_system()))
	_last_event_ms = Time.get_ticks_msec()


func _exit_tree() -> void:
	if me == self:
		me = null


## Is analytics configured in this build? (The Measurement ID and API secret are in Services)
static func configured() -> bool:
	return test_mode or (Services.CONFIG.ga_measurement_id != "" and Services.CONFIG.ga_api_secret != "")


## Only a phone really sends (the tests and the editor never touch Google)
static func can_send() -> bool:
	return OS.get_name() == "Android" and not test_mode and configured()


func _load_id() -> String:
	var c := ConfigFile.new()
	if c.load(ID_FILE) == OK:
		var saved := str(c.get_value("analytics", "client_id", ""))
		if saved != "":
			return saved
	# Like Google's own IDs: a random number and the time it was made
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := "%d.%d" % [rng.randi(), int(Time.get_unix_time_from_system())]
	c.set_value("analytics", "client_id", id)
	c.save(ID_FILE)
	return id


## May stats be sent? 1: yes, 0: no, -1: not known yet (waiting to hear from Google whether
## this is a country that asks for consent first)
func allowed() -> int:
	if not enabled:
		return 0
	if chosen:
		return 1
	var region := Ads.consent_region() if test_region < -1 else test_region
	if region < 0:
		return -1
	return 0 if region == 1 else 1


## What the switch in Settings shows
func shows_on() -> bool:
	return allowed() != 0


## The player flipped the switch in Settings
func choose(on: bool) -> void:
	chosen = true
	set_enabled(on)


## Records an event. Names and params follow GA4's rules: letters, digits and _, at most 40
## characters; values are numbers or short strings.
func track(name: String, params := {}) -> void:
	if allowed() == 0 or not configured():
		return
	var now := Time.get_ticks_msec()
	var p := params.duplicate()
	p["session_id"] = session_id
	# Time since the last event counts as engaged time (so Google counts active users)
	p["engagement_time_msec"] = clampi(now - _last_event_ms, 1, 300000)
	p["app_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	_last_event_ms = now
	for k in p:
		if p[k] is String:
			p[k] = (p[k] as String).left(100)
	queue.append({"name": name.left(40), "params": p})
	if queue.size() > MAX_QUEUE:
		queue.pop_front()


## The player switched analytics on or off
func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		queue.clear()


func _process(dt: float) -> void:
	_clock += dt
	if _clock - _last_flush >= FLUSH_EVERY:
		flush()


## Sends what's waiting (one batch at a time)
func flush() -> void:
	_last_flush = _clock
	if queue.is_empty() or _busy:
		return
	var ok := allowed()
	if ok == 0:
		queue.clear()
		return
	if ok < 0:
		return # still waiting to hear from Google; the events wait (up to MAX_QUEUE)
	var batch := queue.slice(0, MAX_BATCH)
	if not can_send():
		# Off the phone: count them and drop them
		sent += batch.size()
		queue = queue.slice(batch.size())
		return
	if client_id == "":
		client_id = _load_id()
	var body := JSON.stringify({"client_id": client_id, "events": batch})
	var url := ENDPOINT % [Services.CONFIG.ga_measurement_id, Services.CONFIG.ga_api_secret]
	if _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) == OK:
		_busy = true
		sent += batch.size()
		queue = queue.slice(batch.size())
