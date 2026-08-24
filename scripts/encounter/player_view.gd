class_name PlayerView
extends RefCounted

## What the table is allowed to see.
##
## The player display is a second window pointed at a TV, so the interesting
## question is not how it draws but what reaches it. That decision lives here,
## in one pure function, rather than in the window: a screen that is handed a
## payload can only draw the payload, and a screen that is handed the whole
## campaign is one careless label away from showing the room a secret.
##
## Everything the GM keeps back is dropped from the payload rather than marked
## hidden inside it. A hidden unit has no entry at all — not a blanked one.

const HIDDEN_KEY := "hidden"

## The default posture: names and positions yes, exact enemy numbers no.
const DEFAULTS := {
	"show_enemy_hp": false,
	"show_math": false,
}


static func options_for(location: Dictionary) -> Dictionary:
	var stored: Dictionary = location.get("player_display", {})
	var options := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if stored.has(key):
			options[key] = bool(stored[key])
	return options


## A word for how badly hurt something is, for when the number is not the
## table's business.
static func condition_word(ratio: float, wound_state: String) -> String:
	if wound_state == Mortality.DEAD:
		return "Dead"
	if ratio <= 0.0:
		return "Down"
	if ratio >= 1.0:
		return "Untouched"
	if ratio > 0.5:
		return "Steady"
	if ratio > 0.25:
		return "Hurt"
	return "Badly hurt"


static func _actor_in(snapshot: Dictionary, unit_id: String) -> Dictionary:
	for candidate in snapshot.get("actors", []):
		if String((candidate as Dictionary)["id"]) == unit_id:
			return candidate
	return {}


## Build the payload the player window draws.
##
## [param characters] maps character id to the saved character, which is where
## side, model and name come from. [param snapshot] may be empty: a location
## being set up has units on the board and no encounter behind them yet.
static func compose(
	snapshot: Dictionary,
	location: Dictionary,
	characters: Dictionary,
	covers := [],
	options := {}
) -> Dictionary:
	var settings := DEFAULTS.duplicate()
	settings.merge(options, true)
	var show_enemy_hp := bool(settings["show_enemy_hp"])

	var units: Array[Dictionary] = []
	var visuals := {}
	var conditions := {}
	for unit in location.get("units", []):
		var entry: Dictionary = unit
		if bool(entry.get(HIDDEN_KEY, false)):
			continue
		var character: Dictionary = characters.get(String(entry["character_id"]), {})
		if character.is_empty():
			continue
		var unit_id := String(entry["id"])
		var actor := _actor_in(snapshot, unit_id)
		var hp := int(actor.get("hp", character.get("hp", 0)))
		var max_hp := maxi(1, int(actor.get("max_hp", character.get("max_hp", 1))))
		var wound_state := String(
			actor.get("wound_state", character.get("wound_state", Mortality.UNHURT))
		)
		var side := String(character.get("side", "neutral"))
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var party := side == "party"

		units.append(
			{
				"id": unit_id,
				"x": int(entry["x"]),
				"z": int(entry["z"]),
				"layer": int(entry.get("layer", 0)),
				"name": String(character.get("name", "")),
				"side": side,
			}
		)
		visuals[unit_id] = {
			"side": side,
			# A ratio is a bar, not a number. Rounding an enemy's to quarters keeps
			# the bar honest about "nearly down" without printing their HP.
			"hp_ratio": ratio if (party or show_enemy_hp) else snappedf(ratio, 0.25),
			"down": hp <= 0 or wound_state == Mortality.DEAD,
			"model_id": String(character.get("model_id", "")),
		}
		conditions[unit_id] = (
			"%d / %d" % [hp, max_hp]
			if (party or show_enemy_hp)
			else condition_word(ratio, wound_state)
		)

	var order: Array[Dictionary] = []
	var current_id := String(snapshot.get("current_actor_id", ""))
	for row in snapshot.get("initiative", []):
		var entry: Dictionary = row
		var actor_id := String(entry["actor_id"])
		# An initiative rail that lists a unit the board does not draw tells the
		# table there is something out there. Both drop together.
		if not conditions.has(actor_id):
			continue
		order.append(
			{
				"id": actor_id,
				"name": String(entry["name"]),
				"score": int(entry["score"]),
				"current": actor_id == current_id,
				"condition": String(conditions[actor_id]),
				"side": String((visuals[actor_id] as Dictionary)["side"]),
			}
		)

	return {
		"title": String(location.get("name", "")),
		"round": int(snapshot.get("round", 0)),
		"board": _board(location, covers),
		"units": units,
		"visuals": visuals,
		"initiative": order,
		"headline": _headline(snapshot, bool(settings["show_math"])),
	}


## The terrain, and nothing else the location dictionary happens to carry.
##
## Rebuilt rather than passed through, so a key added to a saved location later —
## a GM note, a hook, a flag — cannot reach the display by default.
static func _board(location: Dictionary, covers: Array) -> Dictionary:
	return {
		"id": String(location.get("id", "")),
		"grid_width": int(location.get("grid_width", 20)),
		"grid_height": int(location.get("grid_height", 20)),
		"tile_metres": float(location.get("tile_metres", 2.0)),
		"layers": int(location.get("layers", 1)),
		"tiles": location.get("tiles", []),
		"props": location.get("props", []),
		"covers": covers,
	}


## The resolution card, cut down to the part the table watches.
##
## The longhand arithmetic is the GM's working — how a DV was reached says what
## the cover was worth and what the target's armour is — so it travels only when
## the GM asks for it.
static func _headline(snapshot: Dictionary, show_math: bool) -> Dictionary:
	var card: Dictionary = snapshot.get("card", {})
	if card.is_empty():
		return {}
	var headline := {
		"title": String(card.get("title", "")),
		"tone": String(card.get("tone", "neutral")),
		"attacker": String(card.get("attacker", "")),
		"target": String(card.get("target", "")),
		"weapon": String(card.get("weapon", "")),
		"lines": PackedStringArray(),
	}
	if show_math:
		headline["lines"] = card.get("lines", PackedStringArray())
	return headline
