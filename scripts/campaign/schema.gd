class_name CampaignSchema
extends RefCounted

## The shape of everything inside a `.red` campaign file, and the small
## calculations the sheets and headers share.

const SAVE_FORMAT := "redline-campaign"
const SAVE_VERSION := "0.6"

const STAT_KEYS: PackedStringArray = [
	"INT", "REF", "DEX", "TECH", "COOL", "WILL", "LUCK", "MOVE", "BODY", "EMP"
]

const LOCATION_LABELS := {
	"head": "Head",
	"body": "Torso",
	"left_arm": "L Arm",
	"right_arm": "R Arm",
	"left_leg": "L Leg",
	"right_leg": "R Leg",
}

const MONTHS: PackedStringArray = [
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
]
const WEEKDAYS: PackedStringArray = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]


## The HP at or below which an actor is Seriously Wounded.
##
## Shared by the character sheet and the resolver so the sheet can never
## disagree with the combat math. Change it here and both follow.
static func serious_wound_threshold(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return (max_hp - 1) / 2


static func empty_armor() -> Dictionary:
	var armor := {}
	for location in Resolver.HIT_LOCATIONS:
		armor[location] = {"sp": 0, "ablated": false}
	return armor


static func empty_stats() -> Dictionary:
	var stats := {}
	for key in STAT_KEYS:
		stats[key] = 4
	return stats


static func points_spent(stats: Dictionary) -> int:
	var total := 0
	for key in STAT_KEYS:
		total += int(stats.get(key, 0))
	return total


## Cyberware humanity cost, summed off the gear list.
static func humanity_spent(gear: Array) -> int:
	var total := 0
	for item in gear:
		total += int((item as Dictionary).get("humanity_cost", 0))
	return total


static func skill_total(stats: Dictionary, skill: Dictionary) -> int:
	return int(stats.get(String(skill["stat"]), 0)) + int(skill["level"])


static func format_clock(clock: Dictionary) -> String:
	return "%02d:%02d" % [int(clock["hour"]), int(clock["minute"])]


static func format_date(clock: Dictionary) -> String:
	var unix := Time.get_unix_time_from_datetime_dict(
		{
			"year": int(clock["year"]),
			"month": int(clock["month"]),
			"day": int(clock["day"]),
			"hour": 12,
			"minute": 0,
			"second": 0,
		}
	)
	var parts := Time.get_datetime_dict_from_unix_time(unix)
	return (
		"%s %d %s %d"
		% [
			WEEKDAYS[int(parts["weekday"])],
			int(clock["day"]),
			MONTHS[int(clock["month"]) - 1],
			int(clock["year"]),
		]
	)


## Night City runs three shifts; the header names the one the clock is in.
static func shift_of(clock: Dictionary) -> Dictionary:
	var hour := int(clock["hour"])
	if hour < 8:
		return {"label": "NIGHT", "shift": 3}
	if hour < 16:
		return {"label": "DAY", "shift": 1}
	return {"label": "EVENING", "shift": 2}


static func advance_clock(clock: Dictionary, minutes: int) -> Dictionary:
	var unix := Time.get_unix_time_from_datetime_dict(
		{
			"year": int(clock["year"]),
			"month": int(clock["month"]),
			"day": int(clock["day"]),
			"hour": int(clock["hour"]),
			"minute": int(clock["minute"]),
			"second": 0,
		}
	)
	var moved := Time.get_datetime_dict_from_unix_time(unix + minutes * 60)
	return {
		"year": int(moved["year"]),
		"month": int(moved["month"]),
		"day": int(moved["day"]),
		"hour": int(moved["hour"]),
		"minute": int(moved["minute"]),
	}


## `blackwall_sunrise.red` from "Blackwall Sunrise".
static func suggest_file_name(campaign_name: String) -> String:
	var slug := ""
	for character in campaign_name.to_lower():
		if character.is_valid_identifier() or (character >= "0" and character <= "9"):
			slug += character
		elif not slug.ends_with("_"):
			slug += "_"
	slug = slug.strip_edges().trim_prefix("_").trim_suffix("_")
	return "%s.red" % (slug if slug != "" else "campaign")
