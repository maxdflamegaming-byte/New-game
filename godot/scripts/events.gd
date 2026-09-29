class_name Events
extends RefCounted
## The weekly event: one special rule for everyone, changing every Monday. It's worked out
## from the date, so it needs no internet and everyone has the same event on the same day.

const ALL := {
	"coins": {"name": "Double Coins", "desc": "Every game pays twice the coins", "color": "#ffb84d"},
	"speed": {"name": "Speed Week", "desc": "Everyone moves 20% faster", "color": "#ff5d73"},
	"power": {"name": "Power Frenzy", "desc": "Power-ups show up twice as often", "color": "#4f8cff"},
	"coinrain": {"name": "Coin Rain", "desc": "Twice as many coins on the map", "color": "#e0a800"},
	"giants": {"name": "Giant Bosses", "desc": "Bosses have 2 more hearts and pay double", "color": "#b06bff"},
}

## Set in tests (or for a preview) to force an event: "" means the date decides, and
## "none" switches events off
static var forced := ""


## Days since 1 January 1970 (a Thursday), for the date `today` ("YYYY-MM-DD")
static func _day_number(today: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(today) / 86400)


## This week's event id
static func current(today: String = "") -> String:
	if forced != "":
		return forced
	if today == "":
		today = Time.get_date_string_from_system()
	# Weeks start on Monday: day 0 was a Thursday, so shift by 3
	var week := floori((_day_number(today) + 3) / 7.0)
	var ids := ALL.keys()
	return ids[posmod(week, ids.size())]


## Whole days left of this week's event, counting today
static func days_left(today: String = "") -> int:
	if today == "":
		today = Time.get_date_string_from_system()
	return 7 - posmod(_day_number(today) + 3, 7)


## An event's name, description and colour ({} when there's no event)
static func info(id: String = "") -> Dictionary:
	return ALL.get(id if id != "" else current(), {})
