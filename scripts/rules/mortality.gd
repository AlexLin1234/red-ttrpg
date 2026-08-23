class_name Mortality
extends RefCounted

## Wound state, Death Saves, stabilization, healing and injury treatment.
##
## Pure like [Resolver]: performs no I/O, mutates nothing it is handed, and
## returns every state change as an [Events] event so the GM's undo stays exact
## rather than approximate.
##
## The constants below are working values. Unlike [Resolver]'s they carry no page
## citation, because they were not checked line by line against a licensed copy —
## treat them the way [TablesDefault] is treated, as something a GM who owns the
## book confirms before leaning on it at the table.

const RULES := {
	## Wound-state penalties apply to every Action, attack and defence alike.
	"seriously_wounded_penalty": -2,
	"mortally_wounded_penalty": -4,
	## A Death Save is a flat d10 against BODY: no exploding 10 and no fumbling 1.
	"death_save_auto_fail_roll": 10,
	## Every save attempted makes the next one harder, survived or not.
	"death_save_penalty_step": 1,
	"stabilize_dv": 15,
	"quick_fix_dv": 15,
	"treatment_dv": 17,
}

const UNHURT := "unhurt"
const LIGHTLY_WOUNDED := "lightly_wounded"
const SERIOUSLY_WOUNDED := "seriously_wounded"
const MORTALLY_WOUNDED := "mortally_wounded"
const DEAD := "dead"

const LABELS := {
	UNHURT: "Unhurt",
	LIGHTLY_WOUNDED: "Lightly wounded",
	SERIOUSLY_WOUNDED: "Seriously wounded",
	MORTALLY_WOUNDED: "Mortally wounded",
	DEAD: "Dead",
}


## The wound state HP alone implies. Death is not in here: a dead character is
## dead because a Death Save said so, not because of a number.
static func state_for(hp: int, max_hp: int) -> String:
	if hp <= 0:
		return MORTALLY_WOUNDED
	if hp <= CampaignSchema.serious_wound_threshold(max_hp):
		return SERIOUSLY_WOUNDED
	if hp < max_hp:
		return LIGHTLY_WOUNDED
	return UNHURT


static func label(state: String) -> String:
	return String(LABELS.get(state, state.capitalize()))


## The modifier a wound state puts on every Action the actor takes.
static func action_penalty(actor: Dictionary) -> int:
	match String(actor.get("wound_state", UNHURT)):
		SERIOUSLY_WOUNDED:
			return int(RULES["seriously_wounded_penalty"])
		MORTALLY_WOUNDED:
			return int(RULES["mortally_wounded_penalty"])
		_:
			return 0


static func is_dead(actor: Dictionary) -> bool:
	return String(actor.get("wound_state", UNHURT)) == DEAD


## Being Mortally Wounded does not take a character out of the fight — it costs
## them [code]mortally_wounded_penalty[/code] on everything they try. Death does.
static func can_act(actor: Dictionary) -> bool:
	return not is_dead(actor)


## True while the actor is down and unstabilized, so a save is owed at the start
## of each of their turns until someone stops the bleeding.
static func owes_death_save(actor: Dictionary) -> bool:
	return bool(actor.get("death_save_due", false)) and not is_dead(actor)


static func death_save_penalty(actor: Dictionary) -> int:
	return int(actor.get("death_save_penalty", 0))


static func _body_of(actor: Dictionary) -> int:
	var stats: Dictionary = actor.get("stats", {})
	return int(actor.get("body", stats.get("BODY", 0)))


## Roll one Death Save for [param actor_id].
##
## Returns {"events", "card_lines", "roll", "penalty", "body", "survived"}. The
## penalty reported is the one that applied to this save; the event list raises
## it for the next one either way.
static func death_save(
	actor_id: String, actor: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var body := _body_of(actor)
	var penalty := death_save_penalty(actor)
	var roll := rng.randint(1, 10)
	var total := roll + penalty
	var auto_fail := roll >= int(RULES["death_save_auto_fail_roll"])
	var survived := not auto_fail and total < body

	var events: Array[Dictionary] = [
		{
			"kind": "death_save_penalty_increased",
			"target_id": actor_id,
			"amount": int(RULES["death_save_penalty_step"]),
		}
	]
	var lines := PackedStringArray(
		["Death Save: d10 %d + penalty %d = %d vs BODY %d" % [roll, penalty, total, body]]
	)
	if auto_fail:
		lines.append("A natural %d fails whatever the BODY." % roll)
	if survived:
		lines.append("SURVIVED — still Mortally Wounded, next save at penalty %d" % (penalty + 1))
	else:
		lines.append("FAILED — the character is dead.")
		events.append({"kind": "wound_state_set", "target_id": actor_id, "state": DEAD})
		events.append({"kind": "death_save_cleared", "target_id": actor_id})

	return {
		"events": events,
		"card_lines": lines,
		"roll": roll,
		"penalty": penalty,
		"body": body,
		"survived": survived,
	}


## Stop the Death Saves without healing anything.
##
## [param check_total] is the medic's finished First Aid or Paramedic check. The
## patient stays Mortally Wounded; taking damage again puts them back on saves,
## which is what [Resolver] emitting death_save_due a second time does.
static func stabilize(
	actor_id: String, actor: Dictionary, check_total: int, dv := -1
) -> Dictionary:
	var target_dv := dv if dv >= 0 else int(RULES["stabilize_dv"])
	var success := check_total >= target_dv
	var events: Array[Dictionary] = []
	var lines := PackedStringArray(["Stabilize: %d vs DV %d" % [check_total, target_dv]])
	if not owes_death_save(actor):
		lines.append("Nothing to stabilize — no Death Save is owed.")
		return {"events": events, "card_lines": lines, "success": false, "dv": target_dv}
	if success:
		events.append({"kind": "death_save_cleared", "target_id": actor_id})
		lines.append("STABILIZED — no further Death Saves until they are hit again.")
	else:
		lines.append("FAILED — the Death Saves continue.")
	return {"events": events, "card_lines": lines, "success": success, "dv": target_dv}


## Put HP back and re-read the wound state from the new total.
##
## Healing never revives the dead and never lowers the state a Death Save set;
## a corpse with its HP topped up is still a corpse.
static func heal(actor_id: String, actor: Dictionary, amount: int) -> Dictionary:
	assert(amount > 0, "healing must be positive")
	var events: Array[Dictionary] = []
	var lines := PackedStringArray()
	if is_dead(actor):
		lines.append("The character is dead. Healing does nothing.")
		return {"events": events, "card_lines": lines, "healed": 0}

	var hp := int(actor.get("hp", 0))
	var max_hp := int(actor.get("max_hp", 1))
	var healed := mini(amount, max_hp - hp)
	if healed <= 0:
		lines.append("Already at %d/%d." % [hp, max_hp])
		return {"events": events, "card_lines": lines, "healed": 0}

	events.append({"kind": "damage_healed", "target_id": actor_id, "amount": healed})
	lines.append("Healed %d — %d/%d." % [healed, hp + healed, max_hp])

	var next_state := state_for(hp + healed, max_hp)
	if next_state != String(actor.get("wound_state", UNHURT)):
		events.append({"kind": "wound_state_set", "target_id": actor_id, "state": next_state})
		lines.append(label(next_state) + ".")
	# Climbing back above 0 ends the dying, and with it the Death Save ladder.
	if hp + healed > 0 and bool(actor.get("death_save_due", false)):
		events.append({"kind": "death_save_cleared", "target_id": actor_id})

	return {"events": events, "card_lines": lines, "healed": healed}


## Treat one Critical Injury off the actor's sheet.
##
## Quick Fix is the field patch — First Aid or Paramedic; Treatment is the real
## repair, Surgery. Both are one check against their own DV here; what a given
## injury needs is the GM's call, which is why the DV is an argument.
static func treat_injury(
	actor_id: String, actor: Dictionary, injury: String, check_total: int, dv := -1
) -> Dictionary:
	var target_dv := dv if dv >= 0 else int(RULES["quick_fix_dv"])
	var injuries: Array = actor.get("critical_injuries", [])
	var lines := PackedStringArray()
	var events: Array[Dictionary] = []
	if not injuries.has(injury):
		lines.append("%s is not carrying that injury." % String(actor.get("name", actor_id)))
		return {"events": events, "card_lines": lines, "success": false, "dv": target_dv}

	var success := check_total >= target_dv
	lines.append("Treat %s: %d vs DV %d" % [injury, check_total, target_dv])
	if success:
		events.append({"kind": "critical_injury_removed", "target_id": actor_id, "injury": injury})
		lines.append("TREATED — %s is off the sheet." % injury)
	else:
		lines.append("FAILED — %s stays." % injury)
	return {"events": events, "card_lines": lines, "success": success, "dv": target_dv}
