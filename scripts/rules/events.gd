class_name Events
extends RefCounted

## Reversible event application and session history.
##
## Every event knows how to undo itself: [method apply] returns the new state
## together with a ready-to-run inverse sequence. That is what makes the GM's
## undo exact rather than a snapshot approximation.


static func _actor(state: Dictionary, actor_id: String) -> Dictionary:
	var actors: Dictionary = state["actors"]
	assert(actors.has(actor_id), "unknown actor: %s" % actor_id)
	return actors[actor_id]


static func _weapon(actor: Dictionary, name: String) -> Dictionary:
	var weapons: Dictionary = actor["weapons"]
	assert(weapons.has(name), "unknown weapon: %s" % name)
	return weapons[name]


static func _runner(state: Dictionary) -> Dictionary:
	assert(state.has("runner"), "this state carries no netrunner")
	return state["runner"]


static func _floor(state: Dictionary, floor_id: String) -> Dictionary:
	var floors: Dictionary = state.get("floors", {})
	assert(floors.has(floor_id), "unknown floor: %s" % floor_id)
	return floors[floor_id]


## Apply one event in place and return the event that undoes it.
static func _apply_one(state: Dictionary, event: Dictionary) -> Dictionary:
	var kind := String(event.get("kind", ""))
	if kind == "noop" or kind == "attack_missed":
		return {"kind": "noop"}

	if kind == "ammo_spent" or kind == "ammo_restored":
		var actor := _actor(state, String(event["actor_id"]))
		var weapon := _weapon(actor, String(event["weapon"]))
		var amount := int(event["amount"])
		var delta := -amount if kind == "ammo_spent" else amount
		assert(int(weapon["ammo"]) + delta >= 0, "event would make ammo negative")
		weapon["ammo"] = int(weapon["ammo"]) + delta
		var inverse := event.duplicate(true)
		inverse["kind"] = "ammo_restored" if kind == "ammo_spent" else "ammo_spent"
		return inverse

	if kind == "weapon_jammed" or kind == "weapon_unjammed":
		var actor := _actor(state, String(event["actor_id"]))
		var weapon := _weapon(actor, String(event["weapon"]))
		var previous := bool(weapon.get("jammed", false))
		weapon["jammed"] = kind == "weapon_jammed"
		return {
			"kind": "weapon_jammed" if previous else "weapon_unjammed",
			"actor_id": event["actor_id"],
			"weapon": event["weapon"],
		}

	# -- netrun --------------------------------------------------------------
	#
	# A run is not a fight, but it wants the same thing a fight wants: an undo
	# that is a real inverse rather than a restored snapshot. These kinds reuse
	# this machinery over a state of {"floors", "runner"} rather than {"actors"},
	# which is why they are answered before the actor lookup below.
	if kind == "netrun_moved":
		var runner := _runner(state)
		var previous_floor := String(runner.get("floor_id", ""))
		var previous_level := int(runner.get("level", 0))
		runner["floor_id"] = String(event["floor_id"])
		runner["level"] = int(event["level"])
		return {
			"kind": "netrun_moved", "floor_id": previous_floor, "level": previous_level
		}

	if kind == "net_action_spent" or kind == "net_action_restored":
		var runner := _runner(state)
		var amount := int(event["amount"])
		var previous := int(runner.get("actions_left", 0))
		var next: int = (
			maxi(0, previous - amount) if kind == "net_action_spent" else previous + amount
		)
		runner["actions_left"] = next
		var actual: int = previous - next if kind == "net_action_spent" else next - previous
		return {
			"kind": "net_action_restored" if kind == "net_action_spent" else "net_action_spent",
			"amount": actual,
		}

	if kind == "floor_state_set":
		var floor_entry := _floor(state, String(event["floor_id"]))
		var previous := String(floor_entry.get("state", "intact"))
		floor_entry["state"] = String(event["state"])
		return {"kind": "floor_state_set", "floor_id": event["floor_id"], "state": previous}

	if kind == "floor_revealed" or kind == "floor_concealed":
		var floor_entry := _floor(state, String(event["floor_id"]))
		var previous := bool(floor_entry.get("revealed", false))
		floor_entry["revealed"] = kind == "floor_revealed"
		return {
			"kind": "floor_revealed" if previous else "floor_concealed",
			"floor_id": event["floor_id"],
		}

	if kind == "ice_damaged" or kind == "ice_repaired":
		var floor_entry := _floor(state, String(event["floor_id"]))
		var amount := int(event["amount"])
		var previous := int(floor_entry.get("rez", 0))
		var ceiling := int(floor_entry.get("max_rez", previous))
		var next: int = (
			maxi(0, previous - amount) if kind == "ice_damaged" else mini(ceiling, previous + amount)
		)
		floor_entry["rez"] = next
		var actual: int = previous - next if kind == "ice_damaged" else next - previous
		return {
			"kind": "ice_repaired" if kind == "ice_damaged" else "ice_damaged",
			"floor_id": event["floor_id"],
			"amount": actual,
		}

	if kind == "runner_damaged" or kind == "runner_healed":
		var runner := _runner(state)
		var amount := int(event["amount"])
		var previous := int(runner.get("hp", 0))
		var next: int = (
			previous - amount
			if kind == "runner_damaged"
			else mini(int(runner.get("max_hp", previous)), previous + amount)
		)
		runner["hp"] = next
		var actual: int = previous - next if kind == "runner_damaged" else next - previous
		return {
			"kind": "runner_healed" if kind == "runner_damaged" else "runner_damaged",
			"amount": actual,
		}

	if kind == "trace_advanced" or kind == "trace_reduced":
		var runner := _runner(state)
		var amount := int(event["amount"])
		var previous := int(runner.get("trace", 0))
		var next: int = (
			previous + amount if kind == "trace_advanced" else maxi(0, previous - amount)
		)
		runner["trace"] = next
		var actual: int = next - previous if kind == "trace_advanced" else previous - next
		return {
			"kind": "trace_reduced" if kind == "trace_advanced" else "trace_advanced",
			"amount": actual,
		}

	if kind == "alert_raised" or kind == "alert_cleared":
		var runner := _runner(state)
		var previous := bool(runner.get("alerted", false))
		runner["alerted"] = kind == "alert_raised"
		return {"kind": "alert_raised" if previous else "alert_cleared"}

	if kind == "runner_jacked_out" or kind == "runner_jacked_in":
		var runner := _runner(state)
		var previous := bool(runner.get("jacked_out", false))
		runner["jacked_out"] = kind == "runner_jacked_out"
		return {"kind": "runner_jacked_out" if previous else "runner_jacked_in"}

	var target := _actor(state, String(event.get("target_id", "")))

	if kind == "cover_set":
		var previous_hp := int(target.get("cover_hp", 0))
		var target_cover_id_existed := target.has("cover_id")
		var previous_id: Variant = target.get("cover_id", null)
		var cover_id: Variant = event.get("cover_id", null)
		var covers_existed := state.has("covers")
		if not covers_existed:
			state["covers"] = {}
		var covers: Dictionary = state["covers"]
		var cover_existed := cover_id != null and covers.has(String(cover_id))
		var previous_cover_hp: Variant = covers.get(String(cover_id), null) if cover_existed else null

		var next_hp := int(event["hp"])
		assert(next_hp >= 0, "cover HP cannot be negative")
		target["cover_hp"] = next_hp
		target["cover_id"] = cover_id
		if cover_id != null:
			covers[String(cover_id)] = next_hp

		return {
			"kind": "cover_restored",
			"target_id": event["target_id"],
			"hp": previous_hp,
			"cover_id": previous_id,
			"target_cover_id_existed": target_cover_id_existed,
			"affected_cover_id": cover_id,
			"cover_existed": cover_existed,
			"previous_cover_hp": previous_cover_hp,
			"covers_existed": covers_existed,
		}

	if kind == "cover_restored":
		target["cover_hp"] = int(event["hp"])
		if bool(event.get("target_cover_id_existed", false)):
			target["cover_id"] = event.get("cover_id", null)
		else:
			target.erase("cover_id")
		if not state.has("covers"):
			state["covers"] = {}
		var covers: Dictionary = state["covers"]
		var affected: Variant = event.get("affected_cover_id", null)
		if affected != null:
			var key := String(affected)
			if bool(event.get("cover_existed", false)):
				covers[key] = int(event["previous_cover_hp"])
			else:
				covers.erase(key)
		if not bool(event.get("covers_existed", true)) and covers.is_empty():
			state.erase("covers")
		return {"kind": "noop"}

	if kind == "cover_damaged" or kind == "cover_repaired":
		var amount := int(event["amount"])
		var cover_id: Variant = event.get("cover_id", null)
		if cover_id != null and not state.has("covers"):
			state["covers"] = {}
		var covers: Dictionary = state.get("covers", {})
		var previous := int(target.get("cover_hp", 0))
		if cover_id != null and covers.has(String(cover_id)):
			previous = int(covers[String(cover_id)])
		var next := maxi(0, previous - amount) if kind == "cover_damaged" else previous + amount
		target["cover_hp"] = next
		if cover_id != null:
			covers[String(cover_id)] = next
		var actual := previous - next if kind == "cover_damaged" else amount
		var inverse := {
			"kind": "cover_repaired" if kind == "cover_damaged" else "cover_damaged",
			"target_id": event["target_id"],
			"amount": actual,
		}
		if cover_id != null:
			inverse["cover_id"] = cover_id
		return inverse

	if kind == "armor_ablated" or kind == "armor_restored":
		var location := String(event["location"])
		var amount := int(event.get("amount", 1))
		if not target.has("armor"):
			target["armor"] = {}
		var armor: Dictionary = target["armor"]
		# Track whether the location was on the sheet at all, so restoring a limb
		# that carried no armour entry leaves the sheet exactly as it was found.
		var existed := armor.has(location)
		var previous := int(armor.get(location, 0))
		var next := maxi(0, previous - amount) if kind == "armor_ablated" else previous + amount
		if not existed and next == 0:
			return {"kind": "noop"}
		armor[location] = next
		var actual := previous - next if kind == "armor_ablated" else amount
		return {
			"kind": "armor_restored" if kind == "armor_ablated" else "armor_ablated",
			"target_id": event["target_id"],
			"location": location,
			"amount": actual,
			"location_existed": existed,
		}

	if kind == "damage_taken" or kind == "damage_healed":
		var amount := int(event["amount"])
		var previous := int(target["hp"])
		if kind == "damage_taken":
			target["hp"] = previous - amount
		else:
			target["hp"] = mini(int(target["max_hp"]), previous + amount)
		var actual: int = (
			previous - int(target["hp"]) if kind == "damage_taken" else int(target["hp"]) - previous
		)
		return {
			"kind": "damage_healed" if kind == "damage_taken" else "damage_taken",
			"target_id": event["target_id"],
			"amount": actual,
		}

	if kind == "critical_injury" or kind == "critical_injury_removed":
		if not target.has("critical_injuries"):
			target["critical_injuries"] = []
		var injuries: Array = target["critical_injuries"]
		var injury := String(event["injury"])
		if kind == "critical_injury":
			injuries.append(injury)
			return {
				"kind": "critical_injury_removed",
				"target_id": event["target_id"],
				"injury": injury,
			}
		var index := injuries.find(injury)
		assert(index != -1, "target is not carrying injury: %s" % injury)
		injuries.remove_at(index)
		return {
			"kind": "critical_injury",
			"target_id": event["target_id"],
			"location": event.get("location", "body"),
			"injury": injury,
			"rolls": event.get("rolls", PackedInt32Array()),
		}

	# "seriously_wounded" is the one transition the resolver names outright; every
	# other move between states — mortally wounded, dead, or climbing back after
	# healing — arrives as wound_state_set carrying the state it wants.
	if (
		kind == "seriously_wounded"
		or kind == "wound_state_set"
		or kind == "wound_state_restored"
	):
		var previous := String(target.get("wound_state", "unhurt"))
		if kind == "seriously_wounded":
			target["wound_state"] = "seriously_wounded"
		else:
			target["wound_state"] = String(event["state"])
		return {
			"kind": "wound_state_restored",
			"target_id": event["target_id"],
			"state": previous,
		}

	if kind == "death_save_penalty_increased" or kind == "death_save_penalty_decreased":
		var amount := int(event["amount"])
		var previous := int(target.get("death_save_penalty", 0))
		var next: int = (
			previous + amount if kind == "death_save_penalty_increased" else maxi(0, previous - amount)
		)
		target["death_save_penalty"] = next
		var actual: int = (
			next - previous if kind == "death_save_penalty_increased" else previous - next
		)
		return {
			"kind": (
				"death_save_penalty_decreased"
				if kind == "death_save_penalty_increased"
				else "death_save_penalty_increased"
			),
			"target_id": event["target_id"],
			"amount": actual,
		}

	if kind == "death_save_due" or kind == "death_save_cleared":
		var previous := bool(target.get("death_save_due", false))
		target["death_save_due"] = kind == "death_save_due"
		return {
			"kind": "death_save_due" if previous else "death_save_cleared",
			"target_id": event["target_id"],
		}

	push_error("unsupported event kind: %s" % kind)
	return {"kind": "noop"}


## Apply events to a copy of [param state].
##
## Returns {"state": Dictionary, "inverse": Array[Dictionary]} where the inverse
## list is already in the order needed to undo the whole batch.
static func apply(state: Dictionary, events: Array) -> Dictionary:
	var next_state := state.duplicate(true)
	var inverses: Array[Dictionary] = []
	for event in events:
		inverses.append(_apply_one(next_state, event))
	inverses.reverse()
	return {"state": next_state, "inverse": inverses}


## One reversible action: what the GM did, the events it produced, and how to
## take it back.
class LogEntry extends RefCounted:
	var action: Dictionary
	var events: Array[Dictionary]
	var inverse: Array[Dictionary]

	func _init(p_action: Dictionary, p_events: Array[Dictionary], p_inverse: Array[Dictionary]) -> void:
		action = p_action
		events = p_events
		inverse = p_inverse


## An undo/redo stack over a world state.
class Session extends RefCounted:
	var state: Dictionary
	var log: Array[LogEntry] = []
	var redo_log: Array[LogEntry] = []

	func _init(p_state: Dictionary) -> void:
		state = p_state.duplicate(true)

	func record(action: Dictionary, events: Array) -> Dictionary:
		var event_list: Array[Dictionary] = []
		for event in events:
			event_list.append((event as Dictionary).duplicate(true))
		var applied := Events.apply(state, event_list)
		state = applied["state"]
		log.append(LogEntry.new(action.duplicate(true), event_list, applied["inverse"]))
		redo_log.clear()
		return state.duplicate(true)

	func can_undo() -> bool:
		return not log.is_empty()

	func can_redo() -> bool:
		return not redo_log.is_empty()

	func undo() -> Dictionary:
		assert(can_undo(), "nothing to undo")
		var entry: LogEntry = log.pop_back()
		state = Events.apply(state, entry.inverse)["state"]
		redo_log.append(entry)
		return state.duplicate(true)

	func redo() -> Dictionary:
		assert(can_redo(), "nothing to redo")
		var entry: LogEntry = redo_log.pop_back()
		var applied := Events.apply(state, entry.events)
		state = applied["state"]
		log.append(LogEntry.new(entry.action, entry.events, applied["inverse"]))
		return state.duplicate(true)
