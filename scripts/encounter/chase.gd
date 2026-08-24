class_name Chase
extends RefCounted

## A live chase.
##
## The third session in the same family as [Encounter] and [NetrunSession]: it
## owns no arithmetic, hands the numbers to [Vehicles], records the events
## through a reversible [Events] session, and renders a snapshot the screen
## draws.
##
## Its state is {actors, chase}. The two cars are actors — SDP where a person has
## HP — so the damage they take rides the same event kinds a firefight uses, and
## only the road between them needed a kind of its own.

var revision := 0
var session: Events.Session
var card: Dictionary = {}
var events: Array[Dictionary] = []

var _rng: Dice.RandomSource


func _init(pursuer: Dictionary, quarry: Dictionary, rng: Dice.RandomSource = null, gap := -1) -> void:
	_rng = rng if rng != null else Dice.SeededRandom.new(randi())
	start(pursuer, quarry, gap)


## Begin a chase. [param pursuer] and [param quarry] are each a vehicle plus the
## driver behind it: {vehicle, driver_name, driver_skill}.
func start(pursuer: Dictionary, quarry: Dictionary, gap := -1) -> void:
	var state := {
		"actors": {"pursuer": _side(pursuer), "quarry": _side(quarry)},
		"chase":
		{
			"gap": gap if gap >= 0 else int(Vehicles.RULES["opening_gap"]),
			"round": 1,
			"outcome": Vehicles.RUNNING,
		},
	}
	session = Events.Session.new(state)
	revision += 1
	card = {}
	events = []


static func _side(entry: Dictionary) -> Dictionary:
	var vehicle: Dictionary = entry.get("vehicle", {})
	var actor := Vehicles.as_actor(vehicle)
	actor["vehicle_id"] = String(vehicle.get("id", ""))
	actor["driver_name"] = String(entry.get("driver_name", "Driver"))
	actor["driver_skill"] = int(entry.get("driver_skill", 0))
	return actor


func side(key: String) -> Dictionary:
	return (session.state["actors"] as Dictionary)[key]


func chase_state() -> Dictionary:
	return session.state["chase"]


func gap() -> int:
	return int(chase_state()["gap"])


func outcome() -> String:
	return String(chase_state()["outcome"])


func is_over() -> bool:
	return outcome() != Vehicles.RUNNING


## The manoeuvres available to each side at the current gap.
func maneuvers() -> Array[Dictionary]:
	return Vehicles.maneuvers_at(gap())


func can_run(maneuver_key: String) -> bool:
	if is_over():
		return false
	for entry in maneuvers():
		if String((entry as Dictionary)["key"]) == maneuver_key:
			return true
	return false


## Run one exchange. Both sides commit their manoeuvre before either rolls,
## which is the whole tension of a chase.
func exchange(pursuer_move := "steady", quarry_move := "steady") -> void:
	assert(not is_over(), "this chase is already decided")
	assert(can_run(pursuer_move), "the pursuer cannot %s at gap %d" % [pursuer_move, gap()])
	assert(can_run(quarry_move), "the quarry cannot %s at gap %d" % [quarry_move, gap()])

	var outcome_before := outcome()
	var result := Vehicles.exchange(
		side("pursuer"),
		side("quarry"),
		{"pursuer": pursuer_move, "quarry": quarry_move},
		gap(),
		_rng,
	)
	var applied: Array[Dictionary] = result["events"]
	applied.append({"kind": "chase_round_advanced"})

	# Whether it ended is read off the state the exchange produces, not the one
	# it started from, so the decision is recorded in the same reversible step.
	var preview: Dictionary = Events.apply(session.state, applied)["state"]
	var decided := Vehicles.outcome_for(
		int((preview["chase"] as Dictionary)["gap"]),
		(preview["actors"] as Dictionary)["pursuer"],
		(preview["actors"] as Dictionary)["quarry"],
	)
	if decided != outcome_before:
		applied.append({"kind": "chase_outcome_set", "outcome": decided})

	session.record(
		{"kind": "exchange", "pursuer": pursuer_move, "quarry": quarry_move}, applied
	)
	revision += 1
	events = applied.duplicate(true)

	var lines: PackedStringArray = result["card_lines"]
	if decided != Vehicles.RUNNING:
		lines.append(Vehicles.outcome_label(decided).to_upper() + ".")
	card = {
		"kind": "exchange",
		"title": (
			Vehicles.outcome_label(decided).to_upper()
			if decided != Vehicles.RUNNING
			else String(result["title"])
		),
		"attacker": String(side("pursuer")["driver_name"]),
		"target": String(side("quarry")["driver_name"]),
		"lines": lines,
		"tone": "hit" if decided != Vehicles.RUNNING else "neutral",
	}


func can_undo() -> bool:
	return session.can_undo()


func can_redo() -> bool:
	return session.can_redo()


func undo() -> void:
	assert(can_undo(), "nothing to undo")
	var inverse := session.log[session.log.size() - 1].inverse.duplicate(true)
	session.undo()
	revision += 1
	events = inverse
	card = {
		"kind": "undo",
		"title": "UNDO",
		"lines": PackedStringArray(["Previous exchange reversed."]),
		"tone": "undo",
	}


func redo() -> void:
	assert(can_redo(), "nothing to redo")
	var replayed := session.redo_log[session.redo_log.size() - 1].events.duplicate(true)
	session.redo()
	revision += 1
	events = replayed
	card = {
		"kind": "redo",
		"title": "REDO",
		"lines": PackedStringArray(["Previous exchange applied again."]),
		"tone": "neutral",
	}


func _side_view(key: String) -> Dictionary:
	var entry := side(key)
	return {
		"key": key,
		"name": String(entry["name"]),
		"driver_name": String(entry["driver_name"]),
		"driver_skill": int(entry["driver_skill"]),
		"handling": int(entry["handling"]),
		"sdp": int(entry["hp"]),
		"max_sdp": int(entry["max_hp"]),
		"sp": int((entry["armor"] as Dictionary).get("body", 0)),
		"wrecked": Vehicles.is_wrecked(entry),
	}


## Everything the road, the two cars and the card draw.
func snapshot() -> Dictionary:
	var moves: Array[Dictionary] = []
	for entry in Vehicles.MANEUVERS:
		var candidate: Dictionary = entry
		moves.append(
			{
				"key": String(candidate["key"]),
				"label": String(candidate["label"]),
				"summary": String(candidate["summary"]),
				"enabled": can_run(String(candidate["key"])),
			}
		)
	return {
		"revision": revision,
		"gap": gap(),
		"round": int(chase_state()["round"]),
		"outcome": outcome(),
		"outcome_label": Vehicles.outcome_label(outcome()),
		"escape_gap": int(Vehicles.RULES["escape_gap"]),
		"caught_gap": int(Vehicles.RULES["caught_gap"]),
		"pursuer": _side_view("pursuer"),
		"quarry": _side_view("quarry"),
		"maneuvers": moves,
		"can_undo": can_undo(),
		"can_redo": can_redo(),
		"card": card.duplicate(true),
		"events": events.duplicate(true),
	}
