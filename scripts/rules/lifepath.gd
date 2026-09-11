class_name Lifepath
extends RefCounted

## Where a character came from, and what has happened to them since.
##
## The Forge could build a mechanically complete sheet — stats, skills, gear,
## chrome — and hand back somebody with no history. This is the other half of
## making a character, and it is the half a GM steals from: a lifepath is the
## fastest way to turn "Booster 3" into someone the table remembers.
##
## Pure like [Resolver], [Mortality] and [Netrun]: performs no I/O, mutates
## nothing it is handed, and returns every state change as an [Events] event so
## a rolled lifepath undoes exactly like a rolled attack.
##
## The tables it reads are supplied, not built in. [LifepathDefault] is a
## homebrew placeholder in the same sense [TablesDefault] is; a GM who owns the
## book replaces it. Nothing here assumes a table is ten rows long, or that a
## role has a path at all.

## The general questions, in the order the Forge asks them.
##
## [code]group[/code] is only for presentation — the roller and the store do not
## care — but it is what keeps a sheet from reading as twelve unrelated fields.
const GENERAL: Array[Dictionary] = [
	{"key": "cultural_origin", "label": "Cultural origin", "group": "origin"},
	{"key": "personality", "label": "Personality", "group": "self"},
	{"key": "clothing", "label": "Clothing", "group": "self"},
	{"key": "hairstyle", "label": "Hairstyle", "group": "self"},
	{"key": "affectation", "label": "Affectation", "group": "self"},
	{"key": "value_most", "label": "Values most", "group": "motivations"},
	{"key": "feel_about_people", "label": "Feels that people are", "group": "motivations"},
	{"key": "valued_person", "label": "Valued person", "group": "motivations"},
	{"key": "valued_possession", "label": "Valued possession", "group": "motivations"},
	{"key": "family_background", "label": "Family background", "group": "family"},
	{"key": "childhood_environment", "label": "Childhood", "group": "family"},
	{"key": "family_crisis", "label": "Family crisis", "group": "family"},
]

## The table life events are drawn from. Kept out of [constant GENERAL] because
## it is rolled many times rather than once.
const LIFE_EVENT_KEY := "life_event"

## How many life events a character may carry. A lifepath is a history, not a
## novel; past this the Forge stops offering another year.
const MAX_LIFE_EVENTS := 12

var data: Dictionary


func _init(p_data: Dictionary) -> void:
	data = p_data


## The rows of one general table, or an empty array when the document has none.
func general_rows(key: String) -> Array:
	var general: Dictionary = data.get("general", {})
	var rows: Variant = general.get(key, [])
	return rows if rows is Array else []


## The extra questions this role asks, as [code]{key: rows}[/code].
##
## A role with no path in the document returns nothing, which is a complete
## answer rather than an error: a campaign may well add a role before it writes
## a lifepath for it.
func role_tables(role_key: String) -> Dictionary:
	var roles: Dictionary = data.get("roles", {})
	var table: Variant = roles.get(role_key, {})
	return table if table is Dictionary else {}


## The role questions in a stable order, so two rolls of the same role produce
## the same fields in the same places.
func role_fields(role_key: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var tables := role_tables(role_key)
	var keys := tables.keys()
	keys.sort()
	for value in keys:
		var key := String(value)
		fields.append({"key": key, "label": _label_for(key)})
	return fields


## Turn a table key into something printable, since the document supplies keys
## rather than labels and a GM's own table may add keys this file never saw.
static func _label_for(key: String) -> String:
	var words := key.replace("_", " ").strip_edges()
	if words.is_empty():
		return key
	return words.substr(0, 1).to_upper() + words.substr(1)


## Roll one row out of a table.
##
## Returns the row's text, or "" when the table is missing or empty.
##
## The die is the table's own size rather than a fixed d10, so a GM's twenty-row
## table is read whole instead of having half of it be unreachable. A row may
## also claim a band — [code]{"roll": 1, "to": 3}[/code] — because real tables
## bunch several results under one range, and a table that uses bands sets the
## die from the highest number it mentions rather than from how many rows it has.
static func roll_row(rows: Array, rng: Dice.RandomSource) -> String:
	if rows.is_empty():
		return ""
	var top := 0
	for value in rows:
		var row: Dictionary = value
		top = maxi(top, maxi(int(row.get("roll", 0)), int(row.get("to", 0))))
	if top <= 0:
		top = rows.size()
	var rolled := rng.randint(1, top)
	for value in rows:
		var row: Dictionary = value
		var low := int(row.get("roll", 0))
		if low <= 0:
			continue
		var high := maxi(low, int(row.get("to", low)))
		if rolled >= low and rolled <= high:
			return String(row.get("text", ""))
	# A table whose rows never declared a number at all is read positionally,
	# which is what an imported list of ten strings amounts to.
	var index := clampi(rolled - 1, 0, rows.size() - 1)
	return String((rows[index] as Dictionary).get("text", ""))


## Roll every general question, plus this role's own.
##
## The result is the lifepath as it is stored on a sheet: flat keys for the
## answers, [code]role[/code] for which role's path was walked, and an empty
## event list ready to be added to.
func roll(role_key: String, rng: Dice.RandomSource) -> Dictionary:
	var lifepath := {"role": role_key, "events": []}
	for entry in GENERAL:
		var field: Dictionary = entry
		var key := String(field["key"])
		lifepath[key] = roll_row(general_rows(key), rng)
	for entry in role_fields(role_key):
		var field: Dictionary = entry
		var key := String(field["key"])
		lifepath[key] = roll_row(role_tables(role_key).get(key, []), rng)
	return lifepath


## Roll one more year onto an existing history.
func roll_life_event(rng: Dice.RandomSource) -> String:
	return roll_row(general_rows(LIFE_EVENT_KEY), rng)


## Whether a sheet has been given a lifepath at all.
##
## A sheet carrying the key but no answers does not count: a lifepath rolled
## against an empty document would otherwise read as done.
static func is_written(character: Dictionary) -> bool:
	var lifepath: Variant = character.get("lifepath", {})
	if not lifepath is Dictionary:
		return false
	for entry in GENERAL:
		if String((lifepath as Dictionary).get(String((entry as Dictionary)["key"]), "")) != "":
			return true
	return false


## Everything on a sheet's lifepath, in display order, as
## [code]{key, label, text}[/code].
##
## Built from the sheet rather than from the tables, so a lifepath written under
## one role still prints in full after the character changes role — the answers
## a character already gave do not stop being true because they took a new job.
func entries(character: Dictionary) -> Array[Dictionary]:
	var lifepath: Dictionary = character.get("lifepath", {})
	var rows: Array[Dictionary] = []
	for entry in GENERAL:
		var field: Dictionary = entry
		var key := String(field["key"])
		rows.append(
			{
				"key": key,
				"label": String(field["label"]),
				"group": String(field["group"]),
				"text": String(lifepath.get(key, "")),
			}
		)
	var role_key := String(lifepath.get("role", character.get("role_key", "")))
	for entry in role_fields(role_key):
		var field: Dictionary = entry
		var key := String(field["key"])
		rows.append(
			{
				"key": key,
				"label": String(field["label"]),
				"group": "role",
				"text": String(lifepath.get(key, "")),
			}
		)
	return rows


static func life_events(character: Dictionary) -> Array:
	var lifepath: Dictionary = character.get("lifepath", {})
	var events: Variant = lifepath.get("events", [])
	return events if events is Array else []


# -- events ---------------------------------------------------------------------


## Replace a sheet's whole lifepath.
##
## The event carries the lifepath that was there before, so undo restores a
## hand-written history rather than clearing it — re-rolling somebody's past by
## accident is exactly the mistake this has to survive.
static func write_event(character_id: String, before: Dictionary, after: Dictionary) -> Dictionary:
	return {
		"kind": "lifepath_written",
		"character_id": character_id,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}


static func set_field_event(
	character_id: String, key: String, before: String, after: String
) -> Dictionary:
	return {
		"kind": "lifepath_field_set",
		"character_id": character_id,
		"key": key,
		"before": before,
		"after": after,
	}


static func add_event_event(character_id: String, text: String) -> Dictionary:
	return {"kind": "lifepath_event_added", "character_id": character_id, "text": text}


## Apply one lifepath event to a sheet, returning the sheet.
##
## Mutates the character it is given, like every other applier in the app; the
## caller owns whether that character is a scratch copy or the campaign's own.
static func apply(character: Dictionary, event: Dictionary) -> Dictionary:
	match String(event.get("kind", "")):
		"lifepath_written":
			character["lifepath"] = (event["after"] as Dictionary).duplicate(true)
		"lifepath_field_set":
			var lifepath: Dictionary = character.get("lifepath", {})
			lifepath[String(event["key"])] = String(event["after"])
			character["lifepath"] = lifepath
		"lifepath_event_added":
			var carrying: Dictionary = character.get("lifepath", {})
			var events: Array = carrying.get("events", [])
			events.append(String(event["text"]))
			carrying["events"] = events
			character["lifepath"] = carrying
	return character


static func undo(character: Dictionary, event: Dictionary) -> Dictionary:
	match String(event.get("kind", "")):
		"lifepath_written":
			character["lifepath"] = (event["before"] as Dictionary).duplicate(true)
		"lifepath_field_set":
			var lifepath: Dictionary = character.get("lifepath", {})
			lifepath[String(event["key"])] = String(event["before"])
			character["lifepath"] = lifepath
		"lifepath_event_added":
			var carrying: Dictionary = character.get("lifepath", {})
			var events: Array = carrying.get("events", [])
			if not events.is_empty():
				events.pop_back()
			carrying["events"] = events
			character["lifepath"] = carrying
	return character


## Make sure a sheet's lifepath is shaped the way every reader assumes.
##
## Called from [method CharacterRules.ensure_character], so a sheet written
## before lifepaths existed gains an empty one rather than a missing key.
static func ensure(character: Dictionary) -> void:
	var lifepath: Variant = character.get("lifepath", {})
	if not lifepath is Dictionary:
		lifepath = {}
	var carrying: Dictionary = lifepath
	var events: Variant = carrying.get("events", [])
	carrying["events"] = events if events is Array else []
	carrying["role"] = String(carrying.get("role", character.get("role_key", "")))
	character["lifepath"] = carrying
