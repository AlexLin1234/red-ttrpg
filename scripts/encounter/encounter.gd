class_name Encounter
extends RefCounted

## Live encounter state.
##
## Owns no rules arithmetic of its own: it reads actor state, hands the numbers
## to [Resolver], records the resulting events through the reversible [Events]
## session, and renders a snapshot the board can draw. Initiative, rounds and the
## per-turn action list live here too.
##
## Nothing here crashes on an illegal order. Every mutator asks [method
## check_action] first and, when the answer is no, records a refusal the screen
## can print instead of changing state — so the reason a shot did not happen
## reaches the GM rather than an assertion.

## What each recorded action costs from the actor's turn. Cyberpunk RED gives a
## character one Action and one Move Action per turn (core rulebook p. 168), and
## reloading spends the Action (p. 183) — which is why a character who reloads
## does not also shoot that turn.
const ACTION_COSTS := {
	"Attack": "action",
	"Aimed Shot": "action",
	"Autofire": "action",
	"Reload": "action",
	"Clear Jam": "action",
	"Move": "move",
}

## How each cost reads on the screen.
const COST_LABELS := {"action": "Action", "move": "Move Action"}

## Terse forms of every refusal, for the places on screen too narrow for the
## whole sentence — a budget row keeps the short form and puts the sentence on
## its tooltip.
const SHORT_REASONS := {
	"unknown_actor": "No unit",
	"actor_down": "Down",
	"not_your_turn": "Not their turn",
	"action_spent": "Action spent",
	"move_spent": "Move spent",
	"no_weapon": "No weapon",
	"unknown_weapon": "Not carried",
	"no_attack_base": "No skill",
	"weapon_jammed": "Jammed",
	"no_autofire": "No autofire",
	"no_ammo": "Empty",
	"not_enough_ammo": "Low ammo",
	"self_target": "Itself",
	"unknown_target": "No target",
	"no_evasion_base": "No Evasion",
	"target_down": "Target down",
	"magazine_full": "Full",
	"not_jammed": "Not jammed",
	"out_of_reach": "Too far",
	"already_there": "Same cell",
}

## Metres a Move Action covers per point of MOVE (core rulebook p. 168).
const METRES_PER_MOVE := 2.0

var tables: Tables
var session: Events.Session
var revision := 0
var card: Dictionary = {}
var events: Array[Dictionary] = []
var result: Dictionary = {}
## The last refusal, empty once anything succeeds. See [method check_action].
var warning: Dictionary = {}

var round_number := 0
var initiative: Array[Dictionary] = []
var turn_index := 0
## Actor id to the list of actions already spent this turn.
var actions_taken: Dictionary = {}

var _rng: Dice.RandomSource
## Turn bookkeeping is not part of the event state, so it rides alongside the
## session log: one entry pushed per recorded action, popped back on undo. That
## is what gives an actor their Action back when the attack that spent it is
## taken off the board.
var _turn_undo: Array[Dictionary] = []
var _turn_redo: Array[Dictionary] = []


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
	var cell: Dictionary = actor.get("position", {})
	actor["position"] = {
		"x": int(cell.get("x", 0)),
		"z": int(cell.get("z", 0)),
		"layer": int(cell.get("layer", 0)),
	}
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
	warning = {}
	round_number = 0
	initiative = []
	turn_index = 0
	actions_taken = {}
	_turn_undo = []
	_turn_redo = []


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
	# Recorded with no state event of its own, so rolling can be taken back the
	# same way a shot can: the turn snapshot below is what undo restores.
	_record({"kind": "roll_initiative", "round": 1}, [{"kind": "noop"}])
	initiative = entries
	round_number = 1
	turn_index = 0
	actions_taken = {}
	return entries


func current_turn() -> Dictionary:
	if turn_index < 0 or turn_index >= initiative.size():
		return {}
	return initiative[turn_index]


func end_turn() -> void:
	if initiative.is_empty():
		return
	var current := current_turn()
	_record(
		{
			"kind": "end_turn",
			"actor_id": String(current.get("actor_id", "")),
			"round": round_number,
		},
		[{"kind": "noop"}],
	)
	if not current.is_empty():
		actions_taken.erase(String(current["actor_id"]))
	turn_index += 1
	if turn_index >= initiative.size():
		turn_index = 0
		round_number += 1


## Bring actors into a fight that is already running.
##
## Recorded through the session rather than dropped into the state, so undo
## takes the reinforcements away again. Anyone arriving after initiative was
## rolled goes to the back of the order: they came in late.
func add_actors(actors: Dictionary) -> void:
	assert(not actors.is_empty(), "nothing to add")
	var added: Array[Dictionary] = []
	var arrivals: Array[String] = []
	for actor_id in actors:
		var id := String(actor_id)
		if has_actor(id):
			continue
		added.append(
			{"kind": "actor_added", "actor_id": id, "actor": _normalise_actor(id, actors[actor_id])}
		)
		arrivals.append(id)
	if added.is_empty():
		return

	_record({"kind": "reinforce", "actor_ids": arrivals}, added)
	events = added.duplicate(true)

	if round_number > 0:
		for id in arrivals:
			var entry := actor(id)
			var stats: Dictionary = entry.get("stats", {})
			var ref := int(entry.get("ref", stats.get("REF", 0)))
			var roll := Dice.roll_check(_rng)
			initiative.append(
				{
					"actor_id": id,
					"name": String(entry["name"]),
					"score": ref + int(roll["total"]),
					"roll": int(roll["total"]),
					"ref": ref,
				}
			)

	card = {
		"kind": "reinforce",
		"title": "REINFORCEMENTS",
		"lines": PackedStringArray(["%d arrived." % arrivals.size()]),
		"tone": "neutral",
	}


## Drop initiative rows for actors the state no longer has.
##
## Undoing past the arrival of a squad removes the actors; the order they were
## appended to is not part of the reversible state, so it is reconciled here.
func _prune_initiative() -> void:
	var kept: Array[Dictionary] = []
	for entry in initiative:
		if has_actor(String((entry as Dictionary)["actor_id"])):
			kept.append(entry)
	if kept.size() == initiative.size():
		return
	initiative = kept
	turn_index = clampi(turn_index, 0, maxi(0, initiative.size() - 1))


func _note_action(actor_id: String, action: String) -> void:
	if not actions_taken.has(actor_id):
		actions_taken[actor_id] = []
	(actions_taken[actor_id] as Array).append(action)


# -- turn economy ---------------------------------------------------------------


## The labels of everything [param actor_id] has already spent this turn.
func spent_labels(actor_id: String) -> Array:
	return (actions_taken.get(actor_id, []) as Array).duplicate()


## The label an actor spent [param cost] on this turn, or "" if they still have
## it. Cyberpunk RED budgets one Action and one Move Action per turn.
func spent_on(actor_id: String, cost: String) -> String:
	for label in spent_labels(actor_id):
		if String(ACTION_COSTS.get(String(label), "action")) == cost:
			return String(label)
	return ""


## Metres one Move Action covers for this actor: MOVE x 2.
func move_allowance(actor_id: String) -> float:
	var stats: Dictionary = actor(actor_id).get("stats", {})
	return float(int(stats.get("MOVE", 0))) * METRES_PER_MOVE


## What one action kind is called on the card and in the spent list.
static func action_label(kind: String, options := {}) -> String:
	if kind == "attack":
		var mode := String(options.get("mode", "single"))
		if mode == "autofire":
			return "Autofire"
		if mode == "aimed":
			return "Aimed Shot"
		return "Attack"
	if kind == "reload":
		return "Reload"
	if kind == "clear_jam":
		return "Clear Jam"
	if kind == "move":
		return "Move"
	return kind.capitalize()


static func _ok() -> Dictionary:
	return {"ok": true, "code": "", "reason": "", "short": "", "hint": "", "override": false}


static func _blocked(code: String, reason: String, hint := "", override := false) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"reason": reason,
		"short": String(SHORT_REASONS.get(code, "Blocked")),
		"hint": hint,
		"override": override,
	}


func _display_name(actor_id: String) -> String:
	if not has_actor(actor_id):
		return actor_id
	return String(actor(actor_id)["name"])


## Why [param actor_id] cannot take [param kind] right now.
##
## Answers {"ok": true} when nothing is in the way. Otherwise it is a refusal
## written to be printed as it stands: a machine-readable "code", the "reason" a
## GM reads, a "hint" naming the way out, and "override" — which separates a
## ruling the table can waive, like turn order, from one the dice cannot be
## rolled around, like an empty magazine.
func check_action(actor_id: String, kind: String, options := {}) -> Dictionary:
	if not has_actor(actor_id):
		return _blocked("unknown_actor", "No unit is selected.", "Click a unit on the board first.")

	var entry := actor(actor_id)
	var who := String(entry["name"])
	if Mortality.is_dead(entry):
		return _blocked(
			"actor_dead",
			"%s is dead." % who,
			"A failed Death Save is not undone by healing. Undo the save itself to take it back.",
		)
	if int(entry["hp"]) <= 0:
		return _blocked(
			"actor_down",
			"%s is down at %d HP and cannot act." % [who, int(entry["hp"])],
			"Undo the hit that dropped them, or leave them out of the round.",
		)

	var turn_check := _check_turn(actor_id, kind, options)
	if not bool(turn_check["ok"]):
		return turn_check

	if kind == "attack":
		return _check_attack(actor_id, options)
	if kind == "reload":
		return _check_reload(actor_id, options)
	if kind == "clear_jam":
		return _check_clear_jam(actor_id, options)
	if kind == "move":
		return _check_move(actor_id, options)
	return _ok()


## Turn order and the Action/Move Action budget. Both are waivable: the GM at the
## table is the one who decides a held action or an out-of-order interrupt.
func _check_turn(actor_id: String, kind: String, options: Dictionary) -> Dictionary:
	if round_number == 0:
		return _ok()

	var who := _display_name(actor_id)
	var current := current_turn()
	var acting := String(current.get("actor_id", ""))
	if acting != "" and acting != actor_id:
		return _blocked(
			"not_your_turn",
			"It is %s's turn, not %s's." % [_display_name(acting), who],
			"End the turn to come round to %s, or resolve it anyway as a held action." % who,
			true,
		)

	var label := action_label(kind, options)
	var cost := String(ACTION_COSTS.get(label, "action"))
	var already := spent_on(actor_id, cost)
	if already != "":
		var cost_name := String(COST_LABELS.get(cost, cost))
		var hint := "End the turn to get it back."
		if already != label:
			hint = "%s spends this turn's %s too. %s" % [label, cost_name, hint]
		return _blocked(
			"%s_spent" % cost,
			"%s already spent this turn's %s on %s." % [who, cost_name, already],
			hint,
			true,
		)
	return _ok()


func _check_weapon(actor_id: String, options: Dictionary) -> Dictionary:
	var who := _display_name(actor_id)
	var weapon_name := String(options.get("weapon", ""))
	if weapon_name == "":
		return _blocked(
			"no_weapon",
			"%s has no weapon selected." % who,
			"Give them one in the Forge, or pick a weapon on their sheet.",
		)
	if not (actor(actor_id)["weapons"] as Dictionary).has(weapon_name):
		return _blocked("unknown_weapon", "%s is not carrying %s." % [who, weapon_name])
	return _ok()


func _check_attack(actor_id: String, options: Dictionary) -> Dictionary:
	var carried := _check_weapon(actor_id, options)
	if not bool(carried["ok"]):
		return carried

	var who := _display_name(actor_id)
	var entry := actor(actor_id)
	if not entry.has("attack_base"):
		return _blocked(
			"no_attack_base",
			"%s has no attack skill on their sheet." % who,
			"Add Handgun, Shoulder Arms or Melee Weapon in the Forge.",
		)

	var weapon_name := String(options["weapon"])
	var state := _weapon_state(actor_id, weapon_name)
	if bool(state["jammed"]):
		return _blocked(
			"weapon_jammed",
			"%s is jammed." % weapon_name,
			"Clearing the jam costs this turn's Action.",
		)

	var mode := String(options.get("mode", "single"))
	if mode == "autofire" and _autofire_rating(actor_id, weapon_name) <= 0:
		return _blocked(
			"no_autofire",
			"%s has no autofire rating." % weapon_name,
			"Fire it single shot, or pick a weapon that sprays.",
		)

	var ammo := int(state["ammo"])
	var needed: int = int(Resolver.RULES["autofire_ammo_cost"]) if mode == "autofire" else 1
	if ammo < needed:
		var short_reason := (
			"%s is empty." % weapon_name
			if ammo == 0
			else "%s holds %d rounds and autofire needs %d." % [weapon_name, ammo, needed]
		)
		return _blocked(
			"no_ammo" if ammo == 0 else "not_enough_ammo",
			short_reason,
			"Reloading costs this turn's Action, so the shot lands next turn.",
		)

	var target_id := String(options.get("target_id", ""))
	if target_id != "":
		if target_id == actor_id:
			return _blocked("self_target", "%s cannot shoot themselves." % who)
		if not has_actor(target_id):
			return _blocked("unknown_target", "That unit is not in this encounter.")
		var target := actor(target_id)
		if bool(options.get("contested", false)) and not target.has("evasion_base"):
			return _blocked(
				"no_evasion_base",
				"%s has no Evasion on their sheet to dodge with." % String(target["name"]),
			)
		if int(target["hp"]) <= 0:
			return _blocked(
				"target_down",
				"%s is already down at %d HP." % [String(target["name"]), int(target["hp"])],
				"Shoot them anyway only if the table is finishing them off.",
				true,
			)
	return _ok()


func _check_reload(actor_id: String, options: Dictionary) -> Dictionary:
	var carried := _check_weapon(actor_id, options)
	if not bool(carried["ok"]):
		return carried
	var weapon_name := String(options["weapon"])
	var state := _weapon_state(actor_id, weapon_name)
	var magazine := _magazine_of(actor_id, weapon_name)
	if int(state["ammo"]) >= magazine:
		return _blocked(
			"magazine_full",
			"%s is already loaded, %d of %d." % [weapon_name, int(state["ammo"]), magazine],
		)
	return _ok()


func _check_clear_jam(actor_id: String, options: Dictionary) -> Dictionary:
	var carried := _check_weapon(actor_id, options)
	if not bool(carried["ok"]):
		return carried
	var weapon_name := String(options["weapon"])
	if not bool(_weapon_state(actor_id, weapon_name)["jammed"]):
		return _blocked("not_jammed", "%s is not jammed." % weapon_name)
	return _ok()


func _check_move(actor_id: String, options: Dictionary) -> Dictionary:
	# Before initiative the GM is arranging the scene, not spending anyone's
	# Move Action, so distance is not policed.
	if round_number == 0:
		return _ok()
	var distance := float(options.get("distance_m", -1.0))
	if distance < 0.0:
		return _ok()
	var allowance := move_allowance(actor_id)
	if allowance <= 0.0 or distance <= allowance + 0.001:
		return _ok()
	return _blocked(
		"out_of_reach",
		(
			"That cell is %s m away and one Move Action covers %s m."
			% [String.num(distance, 1), String.num(allowance, 1)]
		),
		"Move partway now, or run it as a double Move and take the rest of the turn.",
		true,
	)


# -- recording ------------------------------------------------------------------


## The turn bookkeeping as it stands, so undo can put it back verbatim.
func _turn_state() -> Dictionary:
	return {
		"round_number": round_number,
		"turn_index": turn_index,
		"initiative": initiative.duplicate(true),
		"actions_taken": actions_taken.duplicate(true),
	}


func _restore_turn_state(state: Dictionary) -> void:
	round_number = int(state["round_number"])
	turn_index = int(state["turn_index"])
	var restored: Array[Dictionary] = []
	for entry in (state["initiative"] as Array):
		restored.append((entry as Dictionary).duplicate(true))
	initiative = restored
	actions_taken = (state["actions_taken"] as Dictionary).duplicate(true)


## Apply one action's events and stack the turn state that undoes it.
func _record(action: Dictionary, action_events: Array) -> void:
	_turn_undo.append(_turn_state())
	_turn_redo.clear()
	session.record(action, action_events)
	revision += 1
	warning = {}


## Refuse an action: nothing changes, and the reason becomes the card the GM
## sees. Returns the refusal so a caller can branch on it too.
func _refuse(check: Dictionary) -> Dictionary:
	warning = check.duplicate(true)
	revision += 1
	var lines := PackedStringArray([String(check["reason"])])
	if String(check.get("hint", "")) != "":
		lines.append(String(check["hint"]))
	card = {
		"kind": "blocked",
		"title": "CANNOT",
		"code": String(check["code"]),
		"lines": lines,
		"override": bool(check.get("override", false)),
		"tone": "blocked",
	}
	events = []
	result = {}
	return check


static func _allowed(check: Dictionary, override: bool) -> bool:
	return bool(check["ok"]) or (override and bool(check["override"]))


## True when the weapon has numbers to read, inline or from the tables. An
## uncosted homebrew name still has to answer the turn-budget checks, so nothing
## below may reach for a profile that was never written.
func _has_profile(actor_id: String, weapon_name: String) -> bool:
	var state := _weapon_state(actor_id, weapon_name)
	return state.has("damage_dice") or tables.has_weapon(weapon_name)


func _magazine_of(actor_id: String, weapon_name: String) -> int:
	var state := _weapon_state(actor_id, weapon_name)
	var magazine := int(state.get("magazine", 0))
	if magazine <= 0 and _has_profile(actor_id, weapon_name):
		magazine = weapon(actor_id, weapon_name).magazine
	if magazine <= 0:
		magazine = int(state["ammo"])
	return maxi(1, magazine)


func _autofire_rating(actor_id: String, weapon_name: String) -> int:
	if _has_profile(actor_id, weapon_name):
		return weapon(actor_id, weapon_name).autofire_rating
	return int(_weapon_state(actor_id, weapon_name).get("autofire_rating", -1))


# -- actions -------------------------------------------------------------------


## Where an actor stands, in board cells.
func position(actor_id: String) -> Dictionary:
	return (actor(actor_id).get("position", {}) as Dictionary).duplicate(true)


## Put an actor on a cell without recording it. This is the setup-phase drag:
## before initiative there is no turn to spend and nothing to take back.
func place(actor_id: String, cell: Dictionary) -> void:
	actor(actor_id)["position"] = {
		"x": int(cell.get("x", 0)),
		"z": int(cell.get("z", 0)),
		"layer": int(cell.get("layer", 0)),
	}


## Move an actor to [param cell] as a Move Action.
##
## [param options] accepts distance_m — checked against MOVE x 2 — and override,
## which pushes past a waivable refusal. Recorded, so undo walks them back to the
## cell they left rather than to an approximation of it.
func move(actor_id: String, cell: Dictionary, options := {}) -> Dictionary:
	var distance := float(options.get("distance_m", -1.0))
	# A refusal is returned as-is so the caller can print it; an action that goes
	# ahead — including one the GM waived — answers plain ok.
	var check := check_action(actor_id, "move", {"distance_m": distance})
	if not _allowed(check, bool(options.get("override", false))):
		return _refuse(check)

	var destination := {
		"x": int(cell.get("x", 0)),
		"z": int(cell.get("z", 0)),
		"layer": int(cell.get("layer", 0)),
	}
	var previous := position(actor_id)
	if previous == destination:
		return _refuse(
			_blocked("already_there", "%s is already on that cell." % _display_name(actor_id))
		)

	var move_events: Array[Dictionary] = [
		{"kind": "actor_moved", "actor_id": actor_id, "to": destination}
	]
	_record(
		{"kind": "move", "actor_id": actor_id, "from": previous, "to": destination},
		move_events,
	)
	card = {
		"kind": "move",
		"title": "MOVE",
		"attacker": _display_name(actor_id),
		"lines": PackedStringArray(
			[
				"(%d, %d) to (%d, %d)" % [previous["x"], previous["z"], destination["x"], destination["z"]],
				(
					"%s m of %s m"
					% [String.num(maxf(distance, 0.0), 1), String.num(move_allowance(actor_id), 1)]
					if distance >= 0.0
					else "Move Action spent"
				),
			]
		),
		"tone": "neutral",
	}
	events = move_events.duplicate(true)
	result = {}
	_note_action(actor_id, "Move")
	return _ok()


## Resolve one attack. [param command] accepts attacker_id, target_id, weapon,
## distance_m, and optionally location, mode, modifiers, contested, cover_hp,
## cover_id and override.
func attack(command: Dictionary) -> Dictionary:
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

	var check := check_action(
		attacker_id,
		"attack",
		{
			"weapon": weapon_name,
			"mode": mode,
			"target_id": target_id,
			"contested": contested,
		},
	)
	if not _allowed(check, bool(command.get("override", false))):
		return _refuse(check)

	var attacker := actor(attacker_id)
	var weapon_state := _weapon_state(attacker_id, weapon_name)

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

	_record(
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
	card = _attack_card(attacker_id, target_id, weapon_name, mode, location, attack_result)
	events = applied.duplicate(true)
	result = attack_result.to_dict()
	_note_action(attacker_id, action_label("attack", {"mode": mode}))
	return _ok()


## Refill a magazine. Reloading is an Action in Cyberpunk RED (core rulebook
## p. 183), so it spends the whole of this turn's Action: a character who
## reloads does not also shoot until the turn comes round again.
func reload(actor_id: String, weapon_name: String, amount := -1, override := false) -> Dictionary:
	var check := check_action(actor_id, "reload", {"weapon": weapon_name})
	if not _allowed(check, override):
		return _refuse(check)

	var state := _weapon_state(actor_id, weapon_name)
	var magazine := _magazine_of(actor_id, weapon_name)
	var missing := magazine - int(state["ammo"])
	var refill := missing if amount < 0 else mini(amount, missing)
	var reload_events: Array[Dictionary] = [
		{"kind": "ammo_restored", "actor_id": actor_id, "weapon": weapon_name, "amount": refill}
	]
	_record(
		{"kind": "reload", "actor_id": actor_id, "weapon": weapon_name, "amount": refill},
		reload_events,
	)
	card = {
		"kind": "reload",
		"title": "RELOAD",
		"attacker": String(actor(actor_id)["name"]),
		"lines": PackedStringArray(
			[
				"%s: +%d rounds, now %d of %d"
				% [weapon_name, refill, int(_weapon_state(actor_id, weapon_name)["ammo"]), magazine],
				"Spends this turn's Action — the next shot is next turn.",
			]
		),
		"tone": "neutral",
	}
	events = reload_events.duplicate(true)
	result = {}
	_note_action(actor_id, "Reload")
	return _ok()


## Clearing a jam is an Action too, so the cleared weapon fires next turn.
func clear_jam(actor_id: String, weapon_name: String, override := false) -> Dictionary:
	var check := check_action(actor_id, "clear_jam", {"weapon": weapon_name})
	if not _allowed(check, override):
		return _refuse(check)

	var jam_events: Array[Dictionary] = [
		{"kind": "weapon_unjammed", "actor_id": actor_id, "weapon": weapon_name}
	]
	_record({"kind": "clear_jam", "actor_id": actor_id, "weapon": weapon_name}, jam_events)
	card = {
		"kind": "clear_jam",
		"title": "JAM CLEARED",
		"attacker": String(actor(actor_id)["name"]),
		"lines": PackedStringArray(
			["%s is ready to fire" % weapon_name, "Spends this turn's Action."]
		),
		"tone": "neutral",
	}
	events = jam_events.duplicate(true)
	result = {}
	_note_action(actor_id, "Clear Jam")
	return _ok()


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
	_record({"kind": "death_save", "actor_id": actor_id}, save_events)
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
	_record(
		{
			"kind": "stabilize",
			"actor_id": medic_id,
			"target_id": patient_id,
			"skill": skill_name,
			"dv": int(outcome["dv"]),
		},
		stabilize_events,
	)
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
	_record(
		{"kind": "heal", "actor_id": actor_id, "amount": amount, "note": note}, heal_events
	)
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
	_record(
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


## What the next undo would take back, as a phrase for a button tooltip.
func undo_label() -> String:
	if not can_undo():
		return ""
	return _action_phrase(session.log[session.log.size() - 1].action)


## What the next redo would put back.
func redo_label() -> String:
	if not can_redo():
		return ""
	return _action_phrase(session.redo_log[session.redo_log.size() - 1].action)


func _action_phrase(action: Dictionary) -> String:
	var kind := String(action.get("kind", ""))
	if kind == "attack":
		return (
			"%s's %s on %s"
			% [
				_display_name(String(action.get("attacker_id", ""))),
				action_label("attack", {"mode": String(action.get("mode", "single"))}).to_lower(),
				_display_name(String(action.get("target_id", ""))),
			]
		)
	if kind == "move":
		var to: Dictionary = action.get("to", {})
		return (
			"%s's move to (%d, %d)"
			% [_display_name(String(action.get("actor_id", ""))), int(to.get("x", 0)), int(to.get("z", 0))]
		)
	if kind == "reload" or kind == "clear_jam":
		return (
			"%s's %s"
			% [
				_display_name(String(action.get("actor_id", ""))),
				action_label(kind).to_lower(),
			]
		)
	if kind == "end_turn":
		return "the end of %s's turn" % _display_name(String(action.get("actor_id", "")))
	if kind == "roll_initiative":
		return "the initiative roll"
	return kind.replace("_", " ")


func undo() -> void:
	assert(can_undo(), "nothing to undo")
	var phrase := undo_label()
	var inverse := session.log[session.log.size() - 1].inverse.duplicate(true)
	session.undo()
	_turn_redo.append(_turn_state())
	_restore_turn_state(_turn_undo.pop_back())
	_prune_initiative()
	revision += 1
	warning = {}
	card = {
		"kind": "undo",
		"title": "UNDO",
		"lines": PackedStringArray(["Reversed %s." % phrase, "The turn it cost is back."]),
		"tone": "undo",
	}
	events = inverse
	result = {}


func redo() -> void:
	assert(can_redo(), "nothing to redo")
	var phrase := redo_label()
	var replayed := session.redo_log[session.redo_log.size() - 1].events.duplicate(true)
	session.redo()
	_turn_undo.append(_turn_state())
	_restore_turn_state(_turn_redo.pop_back())
	_prune_initiative()
	revision += 1
	warning = {}
	card = {
		"kind": "redo",
		"title": "REDO",
		"lines": PackedStringArray(["Reapplied %s." % phrase]),
		"tone": "neutral",
	}
	events = replayed
	result = {}


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


## Every action this actor could take, each already carrying the reason it
## cannot — so the screen greys a button and says why in the same pass, instead
## of finding out only once the GM has clicked it.
func _availability(actor_id: String, weapon_name: String) -> Dictionary:
	return {
		"attack": check_action(actor_id, "attack", {"weapon": weapon_name, "mode": "single"}),
		"aimed": check_action(actor_id, "attack", {"weapon": weapon_name, "mode": "aimed"}),
		"autofire": check_action(actor_id, "attack", {"weapon": weapon_name, "mode": "autofire"}),
		"reload": check_action(actor_id, "reload", {"weapon": weapon_name}),
		"clear_jam": check_action(actor_id, "clear_jam", {"weapon": weapon_name}),
		"move": check_action(actor_id, "move", {}),
	}


func _actor_view(actor_id: String, entry: Dictionary) -> Dictionary:
	var weapons: Array[Dictionary] = []
	var selected := ""
	for name in entry["weapons"]:
		if selected == "":
			selected = String(name)
		weapons.append(_weapon_view(actor_id, String(name), entry["weapons"][name]))
	var chosen := String(entry.get("selected_weapon", selected))
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
		"selected_weapon": chosen,
		"weapons": weapons,
		"position": (entry.get("position", {}) as Dictionary).duplicate(true),
		"spent": {
			"action": spent_on(actor_id, "action"),
			"move": spent_on(actor_id, "move"),
		},
		"move_allowance": move_allowance(actor_id),
		"available": _availability(actor_id, chosen),
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
		"undo_label": undo_label(),
		"redo_label": redo_label(),
		"warning": warning.duplicate(true),
		"actors": actor_views,
		"card": card.duplicate(true),
		"events": events.duplicate(true),
		"result": result.duplicate(true),
		"covers": (session.state.get("covers", {}) as Dictionary).duplicate(true),
	}
