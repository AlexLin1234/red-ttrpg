class_name Netrun
extends RefCounted

## NET architecture rules.
##
## Pure like [Resolver] and [Mortality]: no I/O, nothing mutated, every state
## change returned as an [Events] event so a run undoes exactly.
##
## A run is a ladder. The runner enters at the lobby, moves down a floor at a
## time, and each floor either opens, fights back, or does both. What separates
## it from a firefight is the budget: a Netrunner gets a fixed number of NET
## Actions per turn and every single thing they do costs one.
##
## The constants here are working values with no page citation, for the same
## reason [Mortality]'s are. The ICE they act on is [NetrunDefault]'s homebrew.

const RULES := {
	## NET Actions per turn, per rank of Interface.
	"actions_per_interface_rank": 1,
	## The floor the runner is standing on when they have not moved yet.
	"lobby_level": 0,
	## An alerted architecture is harder the rest of the way down.
	"alert_dv_penalty": 2,
	## Zap does this many d6 to a rezzed program.
	"zap_damage_dice": 2,
	## Sliding back up past live ICE is the risky direction.
	"slide_dv": 8,
	## The trace total at which the architecture knows where the runner is.
	"trace_ceiling": 10,
}

const INTACT := "intact"
const DEFEATED := "defeated"
const BYPASSED := "bypassed"

## Every NET Action, what it costs, and what it is for.
##
## These are the rules' own names for them. The stats they roll against are
## homebrew; the vocabulary is what a GM says at the table.
const ACTIONS: Array[Dictionary] = [
	{
		"key": "pathfinder",
		"label": "Pathfinder",
		"summary": "Read what is on the floors below.",
		"kinds": [],
		"checked": false,
	},
	{
		"key": "move",
		"label": "Move down",
		"summary": "Step onto the next floor.",
		"kinds": [],
		"checked": false,
	},
	{
		"key": "slide",
		"label": "Slide",
		"summary": "Retreat one floor, past whatever is watching.",
		"kinds": [],
		"checked": true,
	},
	{
		"key": "backdoor",
		"label": "Backdoor",
		"summary": "Open a Password.",
		"kinds": ["password"],
		"checked": true,
	},
	{
		"key": "eye_dee",
		"label": "Eye-Dee",
		"summary": "Read what a File actually is before taking it.",
		"kinds": ["file"],
		"checked": true,
	},
	{
		"key": "control",
		"label": "Control",
		"summary": "Work a Control Node: doors, cameras, turrets.",
		"kinds": ["control_node"],
		"checked": true,
	},
	{
		"key": "virus",
		"label": "Virus",
		"summary": "Leave something behind in a File or Node.",
		"kinds": ["file", "control_node"],
		"checked": true,
	},
	{
		"key": "zap",
		"label": "Zap",
		"summary": "Attack a rezzed program.",
		"kinds": ["ice"],
		"checked": true,
	},
	{
		"key": "cloak",
		"label": "Cloak",
		"summary": "Push the trace back down.",
		"kinds": [],
		"checked": true,
	},
	{
		"key": "jack_out",
		"label": "Jack out",
		"summary": "Leave. Live ICE gets one parting shot.",
		"kinds": [],
		"checked": false,
	},
]


static func action(key: String) -> Dictionary:
	for entry in ACTIONS:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return {}


## Which actions make sense on the floor the runner is standing on.
static func actions_for(floor_entry: Dictionary) -> Array[Dictionary]:
	var kind := String(floor_entry.get("kind", ""))
	var live := is_live_ice(floor_entry)
	var available: Array[Dictionary] = []
	for entry in ACTIONS:
		var candidate: Dictionary = entry
		var kinds: Array = candidate["kinds"]
		if not kinds.is_empty() and not kinds.has(kind):
			continue
		# Nothing else works while a rezzed program is standing on the floor.
		if live and String(candidate["key"]) not in ["zap", "slide", "jack_out", "pathfinder"]:
			continue
		available.append(candidate)
	return available


static func is_ice(floor_entry: Dictionary) -> bool:
	return String(floor_entry.get("kind", "")) == "ice"


## Rezzed, undefeated, and therefore in the way.
static func is_live_ice(floor_entry: Dictionary) -> bool:
	return is_ice(floor_entry) and int(floor_entry.get("rez", 0)) > 0


static func actions_per_turn(interface_rank: int) -> int:
	return maxi(1, interface_rank * int(RULES["actions_per_interface_rank"]))


## The DV of a floor, with the architecture's alert state folded in.
static func floor_dv(floor_entry: Dictionary, alerted: bool) -> int:
	var base := int(floor_entry.get("dv", NetrunDefault.floor_kind(
		String(floor_entry.get("kind", "password"))
	)["dv"]))
	return base + (int(RULES["alert_dv_penalty"]) if alerted else 0)


## One Interface check: rank + d10, exploding and fumbling like every other
## check in the game.
static func interface_check(runner: Dictionary, rng: Dice.RandomSource, modifier := 0) -> Dictionary:
	var rank := int(runner.get("interface", 0))
	var check := Dice.roll_check(rng)
	return {
		"rank": rank,
		"modifier": modifier,
		"rolls": check["rolls"],
		"total": rank + modifier + int(check["total"]),
	}


static func _check_line(check: Dictionary, dv: int) -> String:
	var pieces := PackedStringArray()
	for value in check.get("rolls", PackedInt32Array()):
		pieces.append(str(value))
	var line := "Interface %d + d10 [%s]" % [int(check["rank"]), ", ".join(pieces)]
	if int(check["modifier"]) != 0:
		line += " %+d" % int(check["modifier"])
	return line + " = %d vs DV %d" % [int(check["total"]), dv]


## Resolve one NET Action.
##
## Returns {"events", "card_lines", "title", "success"}. The caller has already
## paid the action; what comes back is only what the action did.
static func resolve(
	action_key: String, runner: Dictionary, floor_entry: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var alerted := bool(runner.get("alerted", false))
	match action_key:
		"backdoor", "control", "eye_dee", "virus":
			return _open_floor(action_key, runner, floor_entry, alerted, rng)
		"zap":
			return _zap(runner, floor_entry, rng)
		"slide":
			return _slide(runner, floor_entry, rng)
		"cloak":
			return _cloak(runner, rng)
		_:
			return {
				"events": [] as Array[Dictionary],
				"card_lines": PackedStringArray(),
				"title": "",
				"success": true,
			}


## Backdoor, Control, Eye-Dee and Virus are the same shape: one check against
## the floor's DV, and on success the floor stops being in the way.
static func _open_floor(
	action_key: String,
	runner: Dictionary,
	floor_entry: Dictionary,
	alerted: bool,
	rng: Dice.RandomSource
) -> Dictionary:
	var dv := floor_dv(floor_entry, alerted)
	var check := interface_check(runner, rng)
	var success := int(check["total"]) >= dv
	var label := String(action(action_key)["label"])
	var events: Array[Dictionary] = []
	var lines := PackedStringArray([_check_line(check, dv)])

	if success:
		events.append(
			{"kind": "floor_state_set", "floor_id": String(floor_entry["id"]), "state": DEFEATED}
		)
		events.append({"kind": "floor_revealed", "floor_id": String(floor_entry["id"])})
		lines.append("%s succeeded — %s is open." % [label, String(floor_entry.get("name", "the floor"))])
	else:
		# A failed attempt is noise on the wire.
		events.append({"kind": "trace_advanced", "amount": 1})
		lines.append("%s failed. The trace creeps up." % label)

	return {
		"events": events,
		"card_lines": lines,
		"title": label.to_upper() if success else "%s FAILED" % label.to_upper(),
		"success": success,
	}


## Zap a rezzed program, and take whatever it does back.
static func _zap(
	runner: Dictionary, floor_entry: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var events: Array[Dictionary] = []
	var lines := PackedStringArray()
	if not is_live_ice(floor_entry):
		return {
			"events": events,
			"card_lines": PackedStringArray(["There is nothing rezzed here to attack."]),
			"title": "NO TARGET",
			"success": false,
		}

	var floor_id := String(floor_entry["id"])
	var damage := Dice.damage_roll(int(RULES["zap_damage_dice"]), rng)
	var dealt := int(damage["total"]) + int(runner.get("interface", 0))
	var pieces := PackedStringArray()
	for value in damage["rolls"]:
		pieces.append(str(value))
	var rez := int(floor_entry.get("rez", 0))
	var remaining := maxi(0, rez - dealt)
	events.append({"kind": "ice_damaged", "floor_id": floor_id, "amount": dealt})
	lines.append(
		"Zap: %s + Interface %d = %d — REZ %d → %d"
		% [" + ".join(pieces), int(runner.get("interface", 0)), dealt, rez, remaining]
	)

	if remaining == 0:
		events.append({"kind": "floor_state_set", "floor_id": floor_id, "state": DEFEATED})
		lines.append("%s is derezzed." % String(floor_entry.get("name", "The program")))
		return {"events": events, "card_lines": lines, "title": "DEREZZED", "success": true}

	# Still standing, so it hits back.
	var strike := _ice_strike(floor_entry, rng)
	events.append_array(strike["events"] as Array[Dictionary])
	lines.append_array(strike["card_lines"])
	return {"events": events, "card_lines": lines, "title": "TRADED", "success": true}


## What a surviving program does to whoever is standing in front of it.
static func _ice_strike(floor_entry: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var events: Array[Dictionary] = []
	var dice := int(floor_entry.get("damage_dice", 1))
	var damage := Dice.damage_roll(dice, rng)
	var dealt := int(damage["total"])
	var pieces := PackedStringArray()
	for value in damage["rolls"]:
		pieces.append(str(value))
	var name := String(floor_entry.get("name", "The program"))
	var lines := PackedStringArray()
	if bool(floor_entry.get("black", false)):
		events.append({"kind": "runner_damaged", "amount": dealt})
		lines.append("%s bites back: %s = %d to the netrunner." % [name, " + ".join(pieces), dealt])
	else:
		events.append({"kind": "trace_advanced", "amount": dice})
		lines.append("%s answers: the trace advances %d." % [name, dice])
	return {"events": events, "card_lines": lines}


## Retreating one floor while something is watching.
static func _slide(
	runner: Dictionary, floor_entry: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	if not is_live_ice(floor_entry):
		return {
			"events": [] as Array[Dictionary],
			"card_lines": PackedStringArray(["The way back is clear."]),
			"title": "SLIDE",
			"success": true,
		}
	var dv := int(RULES["slide_dv"])
	var check := interface_check(runner, rng)
	var success := int(check["total"]) >= dv
	var lines := PackedStringArray([_check_line(check, dv)])
	var events: Array[Dictionary] = []
	if success:
		lines.append("Slid past %s." % String(floor_entry.get("name", "it")))
		return {"events": events, "card_lines": lines, "title": "SLIDE", "success": true}
	var strike := _ice_strike(floor_entry, rng)
	events.append_array(strike["events"] as Array[Dictionary])
	lines.append_array(strike["card_lines"])
	return {"events": events, "card_lines": lines, "title": "CAUGHT", "success": false}


static func _cloak(runner: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var check := interface_check(runner, rng)
	var reduced := maxi(1, int(check["total"]) / 4)
	var trace := int(runner.get("trace", 0))
	var actual := mini(reduced, trace)
	var lines := PackedStringArray([_check_line(check, 0)])
	var events: Array[Dictionary] = []
	if actual <= 0:
		lines.append("Nothing is following yet.")
		return {"events": events, "card_lines": lines, "title": "CLOAK", "success": true}
	events.append({"kind": "trace_reduced", "amount": actual})
	lines.append("Trace %d → %d." % [trace, trace - actual])
	return {"events": events, "card_lines": lines, "title": "CLOAK", "success": true}


## The parting shot every live program on the ladder takes as the runner leaves.
static func jack_out(floor_entry: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var events: Array[Dictionary] = [{"kind": "runner_jacked_out"}]
	var lines := PackedStringArray()
	if is_live_ice(floor_entry):
		var strike := _ice_strike(floor_entry, rng)
		events.append_array(strike["events"] as Array[Dictionary])
		lines.append_array(strike["card_lines"])
	lines.append("Jacked out.")
	return {"events": events, "card_lines": lines, "title": "JACKED OUT", "success": true}


## Whether the run is over, and why.
static func run_state(runner: Dictionary) -> String:
	if bool(runner.get("jacked_out", false)):
		return "jacked_out"
	if int(runner.get("hp", 1)) <= 0:
		return "flatlined"
	if int(runner.get("trace", 0)) >= int(RULES["trace_ceiling"]):
		return "traced"
	return "running"


static func run_state_label(state: String) -> String:
	match state:
		"jacked_out":
			return "Jacked out"
		"flatlined":
			return "Flatlined"
		"traced":
			return "Traced"
		_:
			return "On the ladder"
