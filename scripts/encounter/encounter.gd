class_name Encounter
extends RefCounted

## Live encounter state.
##
## Owns no rules arithmetic of its own: it reads actor state, hands the numbers
## to [Resolver], records the resulting events through the reversible [Events]
## session, and renders a snapshot the board can draw. Initiative, rounds and the
## per-turn action list live here too.

var tables: Tables
var session: Events.Session
var revision := 0
var card: Dictionary = {}
var events: Array[Dictionary] = []
var result: Dictionary = {}

var round_number := 0
var initiative: Array[Dictionary] = []
var turn_index := 0
## Actor id to the list of actions already spent this turn.
var actions_taken: Dictionary = {}

var _rng: Dice.RandomSource


func _init(p_tables: Tables, actors := {}, rng: Dice.RandomSource = null) -> void:
	tables = p_tables
	_rng = rng if rng != null else Dice.SeededRandom.new(randi())
	session = Events.Session.new({"actors": {}, "covers": {}})
	if not actors.is_empty():
		load_actors(actors)


static func _normalise_actor(actor_id: String, entry: Dictionary) -> Dictionary:
	var actor := entry.duplicate(true)
	var max_hp := int(actor.get("max_hp", 0))
	assert(max_hp > 0, "%s: max_hp must be positive" % actor_id)
	var hp := int(actor.get("hp", max_hp))
	assert(hp <= max_hp, "%s: hp cannot exceed max_hp" % actor_id)

	var armor := {}
	var supplied: Dictionary = actor.get("armor", {})
	for location in Resolver.HIT_LOCATIONS:
		if supplied.has(location):
			var value := int(supplied[location])
			assert(value >= 0, "%s: SP cannot be negative" % actor_id)
			armor[location] = value

	var cover_hp := int(actor.get("cover_hp", 0))
	assert(cover_hp >= 0, "%s: cover HP cannot be negative" % actor_id)

	var weapons := {}
	var supplied_weapons: Dictionary = actor.get("weapons", {})
	for name in supplied_weapons:
		var weapon: Dictionary = (supplied_weapons[name] as Dictionary).duplicate(true)
		var ammo := int(weapon.get("ammo", 0))
		assert(ammo >= 0, "ammo cannot be negative")
		weapon["ammo"] = ammo
		weapon["jammed"] = bool(weapon.get("jammed", false))
		weapons[name] = weapon

	actor["name"] = String(actor.get("name", actor_id))
	actor["max_hp"] = max_hp
	actor["hp"] = hp
	actor["armor"] = armor
	actor["cover_hp"] = cover_hp
	# Wound state is read off the HP an actor arrives with rather than assumed to
	# be "unhurt": a character who walked into the room at 3 HP is already
	# Seriously Wounded, and one at zero already owes a Death Save.
	actor["wound_state"] = String(actor.get("wound_state", Mortality.state_for(hp, max_hp)))
	actor["death_save_due"] = bool(actor.get("death_save_due", hp <= 0))
	actor["death_save_penalty"] = maxi(0, int(actor.get("death_save_penalty", 0)))
	actor["critical_injuries"] = actor.get("critical_injuries", [])
	actor["weapons"] = weapons
	return actor


## Replace the encounter. Loading clears undo history by design.
func load_actors(actors: Dictionary) -> void:
	assert(not actors.is_empty(), "an encounter needs at least one actor")
	var state := {"actors": {}, "covers": {}}
	for actor_id in actors:
		state["actors"][String(actor_id)] = _normalise_actor(String(actor_id), actors[actor_id])
	session = Events.Session.new(state)
	revision += 1
	card = {}
	events = []
	result = {}
	round_number = 0
	initiative = []
	turn_index = 0
	actions_taken = {}


func actor(actor_id: String) -> Dictionary:
	var actors: Dictionary = session.state["actors"]
	assert(actors.has(actor_id), "unknown actor: %s" % actor_id)
	return actors[actor_id]


func has_actor(actor_id: String) -> bool:
	return (session.state["actors"] as Dictionary).has(actor_id)


func actor_ids() -> Array:
	return (session.state["actors"] as Dictionary).keys()


func _weapon_state(actor_id: String, weapon_name: String) -> Dictionary:
	var weapons: Dictionary = actor(actor_id)["weapons"]
	assert(weapons.has(weapon_name), "%s is not carrying %s" % [actor_id, weapon_name])
	return weapons[weapon_name]


## Weapon stats come from the actor's inline override, else the tables.
func weapon(actor_id: String, weapon_name: String) -> Resolver.Weapon:
	var entry := _weapon_state(actor_id, weapon_name)
	var quality := String(entry.get("quality", "standard"))
	if entry.has("damage_dice"):
		return Resolver.Weapon.new(
			weapon_name,
			String(entry.get("weapon_type", "unknown")),
			int(entry["damage_dice"]),
			int(entry.get("rof", 1)),
			maxi(1, int(entry.get("magazine", 1))),
			int(entry.get("autofire_rating", -1)),
			quality,
			int(entry.get("damage_bonus", 0)),
		)
	var profile := tables.weapon(weapon_name)
	return Resolver.Weapon.new(
		weapon_name,
		String(profile["range_type"]),
		int(profile["damage_dice"]),
		int(profile["rof"]),
		maxi(1, int(profile.get("magazine", 1))),
		int(profile.get("autofire_rating", -1)),
		quality,
		int(profile.get("damage_bonus", 0)),
	)


# -- initiative ----------------------------------------------------------------


## Roll 1d10 + REF for everyone and start round 1. Ties break by REF, then name.
func roll_initiative() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for actor_id in actor_ids():
		var entry := actor(String(actor_id))
		var stats: Dictionary = entry.get("stats", {})
		var ref := int(entry.get("ref", stats.get("REF", 0)))
		var roll := Dice.roll_check(_rng)
		entries.append(
			{
				"actor_id": String(actor_id),
				"name": String(entry["name"]),
				"score": ref + int(roll["total"]),
				"roll": int(roll["total"]),
				"ref": ref,
			}
		)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["score"] != b["score"]:
				return a["score"] > b["score"]
			if a["ref"] != b["ref"]:
				return a["ref"] > b["ref"]
			return String(a["name"]) < String(b["name"])
	)
	initiative = entries
	round_number = 1
	turn_index = 0
	actions_taken = {}
	revision += 1
	return entries


func current_turn() -> Dictionary:
	if turn_index < 0 or turn_index >= initiative.size():
		return {}
	return initiative[turn_index]


func end_turn() -> void:
	if initiative.is_empty():
		return
	var current := current_turn()
	if not current.is_empty():
		actions_taken.erase(String(current["actor_id"]))
	turn_index += 1
	if turn_index >= initiative.size():
		turn_index = 0
		round_number += 1
	revision += 1


func _note_action(actor_id: String, action: String) -> void:
	if not actions_taken.has(actor_id):
		actions_taken[actor_id] = []
	(actions_taken[actor_id] as Array).append(action)


# -- actions -------------------------------------------------------------------


## Resolve one attack. [param command] accepts attacker_id, target_id, weapon,
## distance_m, and optionally location, mode, modifiers, contested, cover_hp and
## cover_id.
func attack(command: Dictionary) -> void:
	var attacker_id := String(command["attacker_id"])
	var target_id := String(command["target_id"])
	var weapon_name := String(command["weapon"])
	var distance_m := float(command["distance_m"])
	var location := String(command.get("location", "body"))
	var mode := String(command.get("mode", "single"))
	var modifiers := int(command.get("modifiers", 0))
	var contested := bool(command.get("contested", false))
	var cover_id: Variant = command.get("cover_id", null)
	var cover_hp: Variant = command.get("cover_hp", null)
	assert(cover_id == null or cover_hp != null, "cover_id requires cover_hp")

	var attacker := actor(attacker_id)
	var weapon_state := _weapon_state(attacker_id, weapon_name)
	assert(not bool(weapon_state["jammed"]), "%s is jammed and must be cleared first" % weapon_name)
	assert(attacker.has("attack_base"), "%s has no attack_base" % attacker_id)
	assert(Mortality.can_act(attacker), "%s is dead and cannot act" % attacker_id)

	var defender_evasion_base := -1
	var defender_wound_penalty := 0
	if contested:
		var defender := actor(target_id)
		assert(defender.has("evasion_base"), "%s has no evasion_base" % target_id)
		defender_evasion_base = int(defender["evasion_base"])
		defender_wound_penalty = Mortality.action_penalty(defender)

	var target_actor := actor(target_id)
	var effective_cover_hp := int(target_actor["cover_hp"])
	var cover_events: Array[Dictionary] = []

	if cover_hp != null:
		var requested := int(cover_hp)
		assert(requested >= 0, "cover HP cannot be negative")
		var covers: Dictionary = session.state.get("covers", {})
		if cover_id != null and covers.has(String(cover_id)):
			requested = int(covers[String(cover_id)])
		effective_cover_hp = requested
		var changed: bool = (
			requested != int(target_actor["cover_hp"])
			or cover_id != target_actor.get("cover_id", null)
			or (cover_id != null and not covers.has(String(cover_id)))
		)
		if changed:
			cover_events.append(
				{"kind": "cover_set", "target_id": target_id, "hp": requested, "cover_id": cover_id}
			)

	var target_state := Resolver.TargetState.new(
		target_id,
		int(target_actor["hp"]),
		int(target_actor["max_hp"]),
		target_actor["armor"],
		effective_cover_hp,
	)

	var request := Resolver.AttackRequest.new(
		attacker_id,
		target_state,
		weapon(attacker_id, weapon_name),
		int(attacker["attack_base"]),
		distance_m,
		int(weapon_state["ammo"]),
		location,
		mode,
		defender_evasion_base,
		modifiers,
	)
	request.wound_penalty = Mortality.action_penalty(attacker)
	request.defender_wound_penalty = defender_wound_penalty
	var attack_result := Resolver.resolve_attack(request, tables, _rng)

	var applied: Array[Dictionary] = []
	applied.append_array(cover_events)
	for event in attack_result.events:
		var copy := event.duplicate(true)
		if cover_id != null and String(copy["kind"]) == "cover_damaged":
			copy["cover_id"] = cover_id
		applied.append(copy)

	session.record(
		{
			"kind": "attack",
			"attacker_id": attacker_id,
			"target_id": target_id,
			"weapon": weapon_name,
			"distance_m": distance_m,
			"location": location,
			"mode": mode,
			"modifiers": modifiers,
			"contested": contested,
			"cover_hp": cover_hp,
			"cover_id": cover_id,
		},
		applied,
	)
	revision += 1
	card = _attack_card(attacker_id, target_id, weapon_name, mode, location, attack_result)
	events = applied.duplicate(true)
	result = attack_result.to_dict()
	var label := "Attack"
	if mode == "autofire":
		label = "Autofire"
	elif mode == "aimed":
		label = "Aimed Shot"
	_note_action(attacker_id, label)


func reload(actor_id: String, weapon_name: String, amount := -1) -> void:
	var state := _weapon_state(actor_id, weapon_name)
	var magazine := int(state.get("magazine", 0))
	if magazine <= 0:
		magazine = weapon(actor_id, weapon_name).magazine
	var missing := magazine - int(state["ammo"])
	var refill := missing if amount < 0 else amount
	assert(refill > 0, "%s does not need a reload" % weapon_name)
	assert(refill <= missing, "%s can accept at most %d rounds" % [weapon_name, missing])
	var reload_events: Array[Dictionary] = [
		{"kind": "ammo_restored", "actor_id": actor_id, "weapon": weapon_name, "amount": refill}
	]
	session.record(
		{"kind": "reload", "actor_id": actor_id, "weapon": weapon_name, "amount": refill},
		reload_events,
	)
	revision += 1
	card = {
		"kind": "reload",
		"title": "RELOAD",
		"attacker": String(actor(actor_id)["name"]),
		"lines": PackedStringArray(
			[
				"%s: +%d rounds" % [weapon_name, refill],
				"Ammo: %d" % int(_weapon_state(actor_id, weapon_name)["ammo"]),
			]
		),
		"tone": "neutral",
	}
	events = reload_events.duplicate(true)
	_note_action(actor_id, "Reload")


func clear_jam(actor_id: String, weapon_name: String) -> void:
	var state := _weapon_state(actor_id, weapon_name)
	assert(bool(state["jammed"]), "%s is not jammed" % weapon_name)
	var jam_events: Array[Dictionary] = [
		{"kind": "weapon_unjammed", "actor_id": actor_id, "weapon": weapon_name}
	]
	session.record({"kind": "clear_jam", "actor_id": actor_id, "weapon": weapon_name}, jam_events)
	revision += 1
	card = {
		"kind": "clear_jam",
		"title": "JAM CLEARED",
		"attacker": String(actor(actor_id)["name"]),
		"lines": PackedStringArray(["%s is ready to fire" % weapon_name]),
		"tone": "neutral",
	}
	events = jam_events.duplicate(true)


# -- mortality -----------------------------------------------------------------


## The finished total of one actor's skill check, ready to compare with a DV.
##
## The encounter carries skill totals rather than sheets, so the medic's roll is
## made here and only the number goes to [Mortality].
func roll_skill(actor_id: String, skill_name: String, modifier := 0) -> Dictionary:
	var skills: Dictionary = actor(actor_id).get("skills", {})
	var base := int(skills.get(skill_name, 0))
	var check := Dice.roll_check(_rng)
	var penalty := Mortality.action_penalty(actor(actor_id))
	return {
		"skill": skill_name,
		"base": base,
		"modifier": modifier,
		"wound_penalty": penalty,
		"rolls": check["rolls"],
		"total": base + modifier + penalty + int(check["total"]),
	}


## Roll the Death Save [param actor_id] owes, which either buys them another turn
## of dying or kills them.
func death_save(actor_id: String) -> void:
	var entry := actor(actor_id)
	assert(Mortality.owes_death_save(entry), "%s does not owe a Death Save" % actor_id)
	var outcome := Mortality.death_save(actor_id, entry, _rng)
	var save_events: Array[Dictionary] = outcome["events"]
	session.record({"kind": "death_save", "actor_id": actor_id}, save_events)
	revision += 1
	card = {
		"kind": "death_save",
		"title": "SURVIVED" if bool(outcome["survived"]) else "DEAD",
		"attacker": String(entry["name"]),
		"lines": outcome["card_lines"],
		"tone": "neutral" if bool(outcome["survived"]) else "hit",
	}
	events = save_events.duplicate(true)
	result = {}
	_note_action(actor_id, "Death Save")


## Stop [param patient_id] dying. [param medic_id] makes the check; pass it as
## the same actor to have a character stabilise themselves.
func stabilize(patient_id: String, medic_id: String, skill_name := "First Aid", dv := -1) -> void:
	var patient := actor(patient_id)
	var rolled := roll_skill(medic_id, skill_name)
	var outcome := Mortality.stabilize(patient_id, patient, int(rolled["total"]), dv)
	var stabilize_events: Array[Dictionary] = outcome["events"]
	session.record(
		{
			"kind": "stabilize",
			"actor_id": medic_id,
			"target_id": patient_id,
			"skill": skill_name,
			"dv": int(outcome["dv"]),
		},
		stabilize_events,
	)
	revision += 1
	var lines := PackedStringArray([_check_line(rolled)])
	lines.append_array(outcome["card_lines"])
	card = {
		"kind": "stabilize",
		"title": "STABILIZED" if bool(outcome["success"]) else "STILL DYING",
		"attacker": String(actor(medic_id)["name"]),
		"target": String(patient["name"]),
		"lines": lines,
		"tone": "neutral" if bool(outcome["success"]) else "miss",
	}
	events = stabilize_events.duplicate(true)
	result = {}
	if medic_id != patient_id:
		_note_action(medic_id, "Stabilize")


## Put HP back on an actor, from a medic, a drug, or the GM's own hand.
func heal(actor_id: String, amount: int, note := "Treatment") -> void:
	var entry := actor(actor_id)
	var outcome := Mortality.heal(actor_id, entry, amount)
	var heal_events: Array[Dictionary] = outcome["events"]
	session.record(
		{"kind": "heal", "actor_id": actor_id, "amount": amount, "note": note}, heal_events
	)
	revision += 1
	card = {
		"kind": "heal",
		"title": "HEALED" if int(outcome["healed"]) > 0 else "NO EFFECT",
		"attacker": String(entry["name"]),
		"lines": outcome["card_lines"],
		"tone": "neutral",
	}
	events = heal_events.duplicate(true)
	result = {}


## Try to take one Critical Injury off [param patient_id]'s sheet.
func treat_injury(
	patient_id: String, medic_id: String, injury: String, skill_name := "First Aid", dv := -1
) -> void:
	var patient := actor(patient_id)
	var rolled := roll_skill(medic_id, skill_name)
	var outcome := Mortality.treat_injury(
		patient_id, patient, injury, int(rolled["total"]), dv
	)
	var treat_events: Array[Dictionary] = outcome["events"]
	session.record(
		{
			"kind": "treat_injury",
			"actor_id": medic_id,
			"target_id": patient_id,
			"injury": injury,
			"skill": skill_name,
			"dv": int(outcome["dv"]),
		},
		treat_events,
	)
	revision += 1
	var lines := PackedStringArray([_check_line(rolled)])
	lines.append_array(outcome["card_lines"])
	card = {
		"kind": "treat_injury",
		"title": "TREATED" if bool(outcome["success"]) else "NO CHANGE",
		"attacker": String(actor(medic_id)["name"]),
		"target": String(patient["name"]),
		"lines": lines,
		"tone": "neutral",
	}
	events = treat_events.duplicate(true)
	result = {}
	if medic_id != patient_id:
		_note_action(medic_id, "Treat injury")


static func _check_line(rolled: Dictionary) -> String:
	var pieces := PackedStringArray()
	for value in rolled.get("rolls", PackedInt32Array()):
		pieces.append(str(value))
	var line := (
		"%s: base %d + d10 [%s]"
		% [String(rolled["skill"]), int(rolled["base"]), ", ".join(pieces)]
	)
	if int(rolled["modifier"]) != 0:
		line += " %+d mod" % int(rolled["modifier"])
	if int(rolled["wound_penalty"]) != 0:
		line += " %+d wounds" % int(rolled["wound_penalty"])
	return line + " = %d" % int(rolled["total"])


func can_undo() -> bool:
	return session.can_undo()


func can_redo() -> bool:
	return session.can_redo()


func undo() -> void:
	assert(can_undo(), "nothing to undo")
	var inverse := session.log[session.log.size() - 1].inverse.duplicate(true)
	session.undo()
	revision += 1
	card = {
		"kind": "undo",
		"title": "UNDO",
		"lines": PackedStringArray(["Previous action reversed."]),
		"tone": "undo",
	}
	events = inverse
	result = {}


func redo() -> void:
	assert(can_redo(), "nothing to redo")
	var replayed := session.redo_log[session.redo_log.size() - 1].events.duplicate(true)
	session.redo()
	revision += 1
	card = {
		"kind": "redo",
		"title": "REDO",
		"lines": PackedStringArray(["Previous action applied again."]),
		"tone": "neutral",
	}
	events = replayed


# -- presentation ---------------------------------------------------------------


func _attack_card(
	attacker_id: String,
	target_id: String,
	weapon_name: String,
	mode: String,
	location: String,
	attack_result: Resolver.AttackResult,
) -> Dictionary:
	var title := "MISS"
	if attack_result.hit:
		if attack_result.critical_injury != "":
			title = "CRITICAL INJURY"
		elif attack_result.hp_damage != 0:
			title = "HIT"
		else:
			title = "STOPPED"
	return {
		"kind": "attack",
		"title": title,
		"attacker": String(actor(attacker_id)["name"]),
		"target": String(actor(target_id)["name"]),
		"weapon": weapon_name,
		"mode": mode,
		"location": location,
		"hit": attack_result.hit,
		"hp_damage": attack_result.hp_damage,
		"critical_injury": attack_result.critical_injury,
		"lines": attack_result.card_lines,
		"tone": "hit" if attack_result.hit else "miss",
	}


## An uncosted homebrew weapon still has to draw — the GM may have typed a name
## they have not statted yet.
func _weapon_view(actor_id: String, name: String, state: Dictionary) -> Dictionary:
	if state.has("damage_dice") or tables.has_weapon(name):
		var profile := weapon(actor_id, name)
		return {
			"name": name,
			"ammo": int(state["ammo"]),
			"jammed": bool(state["jammed"]),
			"weapon_type": profile.weapon_type,
			"damage_dice": profile.damage_dice,
			"damage_bonus": profile.damage_bonus,
			"rof": profile.rof,
			"magazine": profile.magazine,
			"autofire_rating": profile.autofire_rating,
			"quality": profile.quality,
		}
	return {
		"name": name,
		"ammo": int(state["ammo"]),
		"jammed": bool(state["jammed"]),
		"weapon_type": String(state.get("weapon_type", "unknown")),
		"damage_dice": int(state.get("damage_dice", 0)),
		"damage_bonus": int(state.get("damage_bonus", 0)),
		"rof": int(state.get("rof", 1)),
		"magazine": int(state.get("magazine", state["ammo"])),
		"autofire_rating": int(state.get("autofire_rating", -1)),
		"quality": String(state.get("quality", "standard")),
	}


func _actor_view(actor_id: String, entry: Dictionary) -> Dictionary:
	var weapons: Array[Dictionary] = []
	var selected := ""
	for name in entry["weapons"]:
		if selected == "":
			selected = String(name)
		weapons.append(_weapon_view(actor_id, String(name), entry["weapons"][name]))
	return {
		"id": actor_id,
		"name": String(entry["name"]),
		"hp": int(entry["hp"]),
		"max_hp": int(entry["max_hp"]),
		"armor": (entry["armor"] as Dictionary).duplicate(),
		"cover_hp": int(entry["cover_hp"]),
		"wound_state": String(entry["wound_state"]),
		"death_save_due": bool(entry["death_save_due"]),
		"death_save_penalty": int(entry["death_save_penalty"]),
		"action_penalty": Mortality.action_penalty(entry),
		"critical_injuries": (entry["critical_injuries"] as Array).duplicate(),
		"attack_base": int(entry.get("attack_base", 0)),
		"evasion_base": int(entry.get("evasion_base", 0)),
		"side": String(entry.get("side", "neutral")),
		"stats": (entry.get("stats", {}) as Dictionary).duplicate(),
		"skills": (entry.get("skills", {}) as Dictionary).duplicate(),
		"selected_weapon": String(entry.get("selected_weapon", selected)),
		"weapons": weapons,
	}


## Everything the board, the initiative rail and the inspector draw.
func snapshot() -> Dictionary:
	var actor_views: Array[Dictionary] = []
	for actor_id in actor_ids():
		actor_views.append(_actor_view(String(actor_id), actor(String(actor_id))))
	var current := current_turn()
	return {
		"revision": revision,
		"round": round_number,
		"turn_index": turn_index,
		"initiative": initiative.duplicate(true),
		"current_actor_id": String(current.get("actor_id", "")) if not current.is_empty() else "",
		"actions_taken": actions_taken.duplicate(true),
		"can_undo": can_undo(),
		"can_redo": can_redo(),
		"actors": actor_views,
		"card": card.duplicate(true),
		"events": events.duplicate(true),
		"result": result.duplicate(true),
		"covers": (session.state.get("covers", {}) as Dictionary).duplicate(true),
	}
