class_name NetrunSession
extends RefCounted

## A live run down a NET architecture.
##
## The same shape as [Encounter], for the same reason: it owns no arithmetic of
## its own, hands the numbers to [Netrun], records the resulting events through a
## reversible [Events] session, and renders a snapshot the screen draws. The
## turn structure is different — a budget of NET Actions rather than initiative —
## but undo works the same way and for the same reason.

var revision := 0
var session: Events.Session
var card: Dictionary = {}
var events: Array[Dictionary] = []
var turn := 1
var order: Array[String] = []

var _rng: Dice.RandomSource


func _init(architecture: Dictionary, runner: Dictionary, rng: Dice.RandomSource = null) -> void:
	_rng = rng if rng != null else Dice.SeededRandom.new(randi())
	load_architecture(architecture, runner)


## Replace the run. Loading clears undo history by design, exactly as loading a
## new encounter does.
func load_architecture(architecture: Dictionary, runner: Dictionary) -> void:
	var floors := {}
	order = []
	var entries: Array = architecture.get("floors", [])
	for entry in entries:
		var floor_entry := _normalize_floor(entry)
		floors[String(floor_entry["id"])] = floor_entry
		order.append(String(floor_entry["id"]))

	var interface_rank := int(runner.get("interface", 0))
	var max_hp := maxi(1, int(runner.get("max_hp", 1)))
	var state := {
		"floors": floors,
		"runner":
		{
			"character_id": String(runner.get("character_id", "")),
			"name": String(runner.get("name", "Netrunner")),
			"interface": interface_rank,
			"actions_left": Netrun.actions_per_turn(interface_rank),
			"hp": mini(max_hp, int(runner.get("hp", max_hp))),
			"max_hp": max_hp,
			"floor_id": "",
			"level": int(Netrun.RULES["lobby_level"]),
			"trace": maxi(0, int(runner.get("trace", 0))),
			"alerted": false,
			"jacked_out": false,
		},
	}
	session = Events.Session.new(state)
	revision += 1
	turn = 1
	card = {}
	events = []


## A saved floor may predate any given field, and an ICE floor's fighting stats
## come from the catalogue rather than being copied onto every architecture.
static func _normalize_floor(entry: Variant) -> Dictionary:
	var floor_entry: Dictionary = (entry as Dictionary).duplicate(true)
	var kind := String(floor_entry.get("kind", "password"))
	floor_entry["kind"] = kind
	floor_entry["level"] = maxi(1, int(floor_entry.get("level", 1)))
	floor_entry["branch"] = maxi(0, int(floor_entry.get("branch", 0)))
	floor_entry["state"] = String(floor_entry.get("state", Netrun.INTACT))
	floor_entry["revealed"] = bool(floor_entry.get("revealed", false))
	if kind == "ice":
		var profile := NetrunDefault.ice(String(floor_entry.get("ice_id", "Watchdog")))
		floor_entry["name"] = String(floor_entry.get("name", profile["name"]))
		floor_entry["black"] = bool(floor_entry.get("black", profile["black"]))
		floor_entry["max_rez"] = int(floor_entry.get("max_rez", profile["max_rez"]))
		floor_entry["rez"] = int(floor_entry.get("rez", floor_entry["max_rez"]))
		floor_entry["damage_dice"] = int(floor_entry.get("damage_dice", profile["damage_dice"]))
		floor_entry["effect"] = String(floor_entry.get("effect", profile["effect"]))
	else:
		floor_entry["name"] = String(
			floor_entry.get("name", NetrunDefault.floor_kind(kind)["label"])
		)
		floor_entry["dv"] = int(floor_entry.get("dv", NetrunDefault.floor_kind(kind)["dv"]))
	return floor_entry


func runner() -> Dictionary:
	return session.state["runner"]


func floors() -> Dictionary:
	return session.state["floors"]


func floor_by_id(floor_id: String) -> Dictionary:
	var all := floors()
	return all.get(floor_id, {})


## The floor the runner is standing on, or {} in the lobby.
func current_floor() -> Dictionary:
	return floor_by_id(String(runner()["floor_id"]))


func deepest_level() -> int:
	var deepest := 0
	for floor_id in order:
		deepest = maxi(deepest, int((floors()[floor_id] as Dictionary)["level"]))
	return deepest


## Every floor sitting at one depth. More than one means the ladder branches.
func floors_at(level: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for floor_id in order:
		var entry: Dictionary = floors()[floor_id]
		if int(entry["level"]) == level:
			found.append(entry)
	return found


func run_state() -> String:
	return Netrun.run_state(runner())


func is_over() -> bool:
	return run_state() != "running"


## Whether this action can be taken right now, and why not when it cannot.
func availability(action_key: String) -> Dictionary:
	if is_over():
		return {"ok": false, "reason": Netrun.run_state_label(run_state())}
	if int(runner()["actions_left"]) <= 0:
		return {"ok": false, "reason": "No NET Actions left this turn"}
	var here := current_floor()
	if action_key == "move":
		if _next_floors().is_empty():
			return {"ok": false, "reason": "Nothing below this floor"}
		if Netrun.is_live_ice(here):
			return {"ok": false, "reason": "%s is in the way" % String(here["name"])}
		if not here.is_empty() and String(here["state"]) == Netrun.INTACT:
			return {"ok": false, "reason": "%s is still closed" % String(here["name"])}
		return {"ok": true, "reason": ""}
	if action_key == "slide" and int(runner()["level"]) <= int(Netrun.RULES["lobby_level"]):
		return {"ok": false, "reason": "Already in the lobby"}
	if here.is_empty() and action_key not in ["move", "pathfinder", "cloak", "jack_out"]:
		return {"ok": false, "reason": "Nothing to do in the lobby"}
	for entry in Netrun.actions_for(here):
		if String((entry as Dictionary)["key"]) == action_key:
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "Not available on this floor"}


func can(action_key: String) -> bool:
	return bool(availability(action_key)["ok"])


## The floors one level below the runner.
func _next_floors() -> Array[Dictionary]:
	return floors_at(int(runner()["level"]) + 1)


# -- actions -------------------------------------------------------------------


## Take one NET Action. [param floor_id] picks the branch for a move, and is
## ignored otherwise.
func perform(action_key: String, floor_id := "") -> void:
	var check := availability(action_key)
	assert(bool(check["ok"]), "%s: %s" % [action_key, String(check["reason"])])

	var here := current_floor()
	var applied: Array[Dictionary] = [
		{"kind": "net_action_spent", "amount": 1}
	]
	var outcome := {}
	match action_key:
		"move":
			outcome = _move(floor_id)
		"pathfinder":
			outcome = _pathfinder()
		"jack_out":
			outcome = Netrun.jack_out(here, _rng)
		"slide":
			outcome = _slide()
		_:
			outcome = Netrun.resolve(action_key, runner(), here, _rng)

	applied.append_array(outcome["events"] as Array[Dictionary])
	session.record(
		{"kind": "net_action", "action": action_key, "floor_id": floor_id}, applied
	)
	revision += 1
	events = applied.duplicate(true)
	card = {
		"kind": "net_action",
		"title": String(outcome.get("title", String(Netrun.action(action_key)["label"]).to_upper())),
		"attacker": String(runner()["name"]),
		"target": String(here.get("name", "Lobby")),
		"lines": outcome["card_lines"],
		"tone": "hit" if not bool(outcome.get("success", true)) else "neutral",
	}


func _move(floor_id: String) -> Dictionary:
	var candidates := _next_floors()
	assert(not candidates.is_empty(), "nothing below this floor")
	var target: Dictionary = candidates[0]
	if floor_id != "":
		for entry in candidates:
			if String(entry["id"]) == floor_id:
				target = entry
	var events_out: Array[Dictionary] = [
		{
			"kind": "netrun_moved",
			"floor_id": String(target["id"]),
			"level": int(target["level"]),
		},
		{"kind": "floor_revealed", "floor_id": String(target["id"])},
	]
	var lines := PackedStringArray(
		["Moved to level %d — %s." % [int(target["level"]), String(target["name"])]]
	)
	if Netrun.is_live_ice(target):
		lines.append("%s is rezzed and in the way." % String(target["name"]))
	return {"events": events_out, "card_lines": lines, "title": "MOVED", "success": true}


## Read the floors below without stepping onto them.
func _pathfinder() -> Dictionary:
	var events_out: Array[Dictionary] = []
	var lines := PackedStringArray()
	var below := _next_floors()
	if below.is_empty():
		lines.append("Nothing below. This is the bottom of the architecture.")
		return {"events": events_out, "card_lines": lines, "title": "PATHFINDER", "success": true}
	for entry in below:
		if not bool(entry["revealed"]):
			events_out.append({"kind": "floor_revealed", "floor_id": String(entry["id"])})
		lines.append(
			"Level %d: %s (%s)"
			% [
				int(entry["level"]),
				String(entry["name"]),
				String(NetrunDefault.floor_kind(String(entry["kind"]))["label"]),
			]
		)
	return {"events": events_out, "card_lines": lines, "title": "PATHFINDER", "success": true}


func _slide() -> Dictionary:
	var here := current_floor()
	var outcome := Netrun.resolve("slide", runner(), here, _rng)
	if not bool(outcome["success"]):
		return outcome
	var level := int(runner()["level"]) - 1
	var above := floors_at(level)
	var target_id := String((above[0] as Dictionary)["id"]) if not above.is_empty() else ""
	var events_out: Array[Dictionary] = outcome["events"]
	events_out.append({"kind": "netrun_moved", "floor_id": target_id, "level": level})
	var lines: PackedStringArray = outcome["card_lines"]
	lines.append("Back to level %d." % level)
	return {"events": events_out, "card_lines": lines, "title": "SLIDE", "success": true}


## Raise or drop the architecture's alarm, which is a GM call: it is what a
## Watchdog's effect text tells them to do.
func set_alert(raised: bool) -> void:
	if bool(runner()["alerted"]) == raised:
		return
	var alert_events: Array[Dictionary] = [
		{"kind": "alert_raised" if raised else "alert_cleared"}
	]
	session.record({"kind": "set_alert", "raised": raised}, alert_events)
	revision += 1
	events = alert_events.duplicate(true)
	card = {
		"kind": "alert",
		"title": "ALARM" if raised else "ALARM CLEARED",
		"attacker": String(runner()["name"]),
		"lines": PackedStringArray(
			[
				(
					"Every floor from here down is at +%d DV."
					% int(Netrun.RULES["alert_dv_penalty"])
					if raised
					else "The architecture settles."
				)
			]
		),
		"tone": "hit" if raised else "neutral",
	}


## End the runner's turn and hand back a full budget of NET Actions.
func end_turn() -> void:
	var spent := (
		Netrun.actions_per_turn(int(runner()["interface"])) - int(runner()["actions_left"])
	)
	var turn_events: Array[Dictionary] = []
	if spent > 0:
		turn_events.append({"kind": "net_action_restored", "amount": spent})
	session.record({"kind": "end_net_turn"}, turn_events)
	turn += 1
	revision += 1
	events = turn_events.duplicate(true)
	card = {
		"kind": "net_turn",
		"title": "TURN %d" % turn,
		"attacker": String(runner()["name"]),
		"lines": PackedStringArray(
			["%d NET Actions." % Netrun.actions_per_turn(int(runner()["interface"]))]
		),
		"tone": "neutral",
	}


func can_undo() -> bool:
	return session.can_undo()


func can_redo() -> bool:
	return session.can_redo()


func undo() -> void:
	assert(can_undo(), "nothing to undo")
	var last := session.log[session.log.size() - 1]
	# The turn counter is not state the events carry, so it is walked back here.
	if String(last.action.get("kind", "")) == "end_net_turn":
		turn = maxi(1, turn - 1)
	var inverse := last.inverse.duplicate(true)
	session.undo()
	revision += 1
	events = inverse
	card = {
		"kind": "undo",
		"title": "UNDO",
		"lines": PackedStringArray(["Previous action reversed."]),
		"tone": "undo",
	}


func redo() -> void:
	assert(can_redo(), "nothing to redo")
	var entry := session.redo_log[session.redo_log.size() - 1]
	if String(entry.action.get("kind", "")) == "end_net_turn":
		turn += 1
	var replayed := entry.events.duplicate(true)
	session.redo()
	revision += 1
	events = replayed
	card = {
		"kind": "redo",
		"title": "REDO",
		"lines": PackedStringArray(["Previous action applied again."]),
		"tone": "neutral",
	}


# -- presentation ---------------------------------------------------------------


## Everything the ladder, the runner panel and the card draw.
func snapshot() -> Dictionary:
	var ladder: Array[Dictionary] = []
	for floor_id in order:
		var entry: Dictionary = floors()[floor_id]
		ladder.append(
			{
				"id": floor_id,
				"kind": String(entry["kind"]),
				"name": String(entry["name"]),
				"level": int(entry["level"]),
				"branch": int(entry["branch"]),
				"state": String(entry["state"]),
				"revealed": bool(entry["revealed"]),
				"dv": Netrun.floor_dv(entry, bool(runner()["alerted"])),
				"rez": int(entry.get("rez", 0)),
				"max_rez": int(entry.get("max_rez", 0)),
				"black": bool(entry.get("black", false)),
				"effect": String(entry.get("effect", "")),
				"here": floor_id == String(runner()["floor_id"]),
			}
		)

	var available: Array[Dictionary] = []
	for entry in Netrun.ACTIONS:
		var candidate: Dictionary = entry
		var key := String(candidate["key"])
		var check := availability(key)
		available.append(
			{
				"key": key,
				"label": String(candidate["label"]),
				"summary": String(candidate["summary"]),
				"enabled": bool(check["ok"]),
				"reason": String(check["reason"]),
			}
		)

	return {
		"revision": revision,
		"turn": turn,
		"runner": (runner() as Dictionary).duplicate(true),
		"floors": ladder,
		"actions": available,
		"deepest_level": deepest_level(),
		"run_state": run_state(),
		"run_state_label": Netrun.run_state_label(run_state()),
		"can_undo": can_undo(),
		"can_redo": can_redo(),
		"card": card.duplicate(true),
		"events": events.duplicate(true),
	}
