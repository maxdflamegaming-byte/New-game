class_name PhoneReminders
extends RefCounted
## Reminders on the phone, even when the game is closed: the daily reward (at 6 in the
## evening, local time, once a new one is ready) and the weekend event (Saturday morning, and
## Sunday midday if it isn't won yet). They're set again whenever the game goes to the
## background, so they always match the save; Settings can switch them off.
## The scheduling itself is Android code (android/reminders, added to the app by
## addons/reminders), reached through JavaClassWrapper; anywhere else this does nothing.

const REWARD := 1
const EVENT := 2
const REWARD_HOUR := 18
const EVENT_HOURS := [10, 12]      # Saturday morning, Sunday midday


## The reminders the save calls for now: [[id, unix time, title, text]], soonest first
static func plan(save: Dictionary, now := Time.get_unix_time_from_system(), bias_min: int = Time.get_time_zone_from_system().bias) -> Array:
	var out := []
	var bias: int = bias_min * 60
	var today := int(now / 86400.0)
	# The daily reward: today's if it hasn't been collected, else tomorrow's (UTC days)
	var ready := today * 86400 if Progress.reward_ready(save, today) else (today + 1) * 86400
	var at := _local_hour_after(maxf(ready, now + 3600), REWARD_HOUR, bias)
	out.append([REWARD, at, "Tower Siege", I18n.t("Your daily reward is ready. Come and collect it!")])
	# The weekend event: Saturday morning when it starts, or Sunday midday if it's on and not won
	var sat := today
	while (sat + 3) % 7 != 5:
		sat += 1
	var st: Dictionary = save.get("event", {})
	var won_now := Events.live(today) and int(st.get("week", -1)) == Progress.week(today) and int(st.get("stage", 0)) >= Events.STAGES
	var sat_at := _local_hour_after(sat * 86400, EVENT_HOURS[0], bias)
	var sun_at := _local_hour_after((sat + 1) * 86400, EVENT_HOURS[1], bias)
	if Events.live(today) and not won_now and sun_at > now + 3600 and (today + 3) % 7 == 5:
		out.append([EVENT, sun_at, "Tower Siege", I18n.t("Last day of the weekend event! Win it for a look you can't buy.")])
	elif sat_at > now + 3600:
		out.append([EVENT, sat_at, "Tower Siege", I18n.t("The weekend event has started: %s!") % I18n.t(Events.info(Events.kind(sat)).name)])
	out.sort_custom(func(a, b): return a[1] < b[1])
	return out


## The first moment from `after` (unix time) when the local clock shows `hour`:00
static func _local_hour_after(after: float, hour: int, bias: int) -> int:
	var local := int(after) + bias
	var t := int(local / 86400.0) * 86400 + hour * 3600
	if t < local:
		t += 86400
	return t - bias


static func available() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime")


static func _java() -> Variant:
	if not available():
		return null
	var cls = JavaClassWrapper.wrap("com.towersiege.reminders.Reminders")
	return cls if cls != null and cls.has_method("schedule") else null


## Set the reminders again from the save (or clear them when they're switched off)
static func apply(save: Dictionary) -> void:
	var cls = _java()
	if cls == null:
		return
	var ctx = Engine.get_singleton("AndroidRuntime").getApplicationContext()
	if ctx == null:
		return
	for id in [REWARD, EVENT]:
		cls.cancel(ctx, id)
	if not bool(save.get("reminders", true)):
		return
	for r in plan(save):
		cls.schedule(ctx, int(r[0]), int(r[1]) * 1000, str(r[2]), str(r[3]))


## Android 13 and later ask before an app may show notifications
static func ask() -> void:
	if available():
		OS.request_permission("android.permission.POST_NOTIFICATIONS")
