extends RefCounted

## Wound states, Death Saves, stabilization and healing.
##
## The rule these cases exist to protect: a character at zero HP is on a clock,
## and every step of that clock is undoable.

const Harness := preload("res://tests/harness.gd")


static func _tables(dv := 13) -> Tables:
	var band := [{"min_m": 0.0, "max_m": 1000.0, "dv": dv}]
	var body := {}
	var head := {}
	for roll in range(2, 13):
		body[str(roll)] = {"name": "Test body injury %d" % roll, "page": 187}
		head[str(roll)] = {"name": "Test head injury %d" % roll, "page": 187}
	return Tables.new(
		{
			"ranged_dv": {"pistol": band},
			"autofire_dv": {"pistol": band},
			"weapons": {},
			"critical_injuries": {"body": body, "head": head},
		}
	)


static func _cast() -> Dictionary:
	return {
		"solo":
		{
			"name": "Rache",
			"max_hp": 40,
			"attack_base": 12,
			"evasion_base": 10,
			"stats": {"BODY": 8, "REF": 8},
			"skills": {"First Aid": 12, "Surgery": 14},
			"weapons":
			{
				"Heavy Pistol":
				{"ammo": 8, "weapon_type": "pistol", "damage_dice": 3, "magazine": 8}
			},
		},
		"medtech":
		{
			"name": "Doc Tallow",
			"max_hp": 30,
			"attack_base": 4,
			"evasion_base": 6,
			"stats": {"BODY": 5},
			"skills": {"First Aid": 14, "Surgery": 16},
			"weapons": {},
		},
		"downed":
		{
			"name": "Booster",
			"max_hp": 40,
			"hp": 0,
			"stats": {"BODY": 7},
			"evasion_base": 8,
			"weapons": {},
		},
	}


static func _encounter(rolls: Array[int] = [], dv := 13) -> Encounter:
	return Encounter.new(_tables(dv), _cast(), Dice.FixedRandom.new(rolls))


static func _actor(session: Encounter, id: String) -> Dictionary:
	for entry in session.snapshot()["actors"]:
		if String((entry as Dictionary)["id"]) == id:
			return entry
	return {}


static func run(h: Harness) -> void:
	h.describe("mortality")

	_states(h)
	_death_saves(h)
	_stabilizing(h)
	_healing(h)
	_injuries(h)
	_penalties(h)


static func _states(h: Harness) -> void:
	h.it("reads a wound state off HP")
	h.equal(Mortality.state_for(40, 40), "unhurt", "full")
	h.equal(Mortality.state_for(39, 40), "lightly_wounded", "one short")
	# The threshold is (max - 1) / 2, so 19 of 40 is the first seriously wounded HP.
	h.equal(Mortality.state_for(20, 40), "lightly_wounded", "above the threshold")
	h.equal(Mortality.state_for(19, 40), "seriously_wounded", "at the threshold")
	h.equal(Mortality.state_for(1, 40), "seriously_wounded", "one HP left")
	h.equal(Mortality.state_for(0, 40), "mortally_wounded", "zero")
	h.equal(Mortality.state_for(-8, 40), "mortally_wounded", "below zero")

	h.it("puts a penalty on every action a wounded character takes")
	h.equal(Mortality.action_penalty({"wound_state": "unhurt"}), 0, "unhurt")
	h.equal(Mortality.action_penalty({"wound_state": "lightly_wounded"}), 0, "lightly")
	h.equal(Mortality.action_penalty({"wound_state": "seriously_wounded"}), -2, "seriously")
	h.equal(Mortality.action_penalty({"wound_state": "mortally_wounded"}), -4, "mortally")
	h.equal(Mortality.action_penalty({"wound_state": "dead"}), 0, "dead")

	h.it("loads an actor already at zero as mortally wounded and owing a save")
	var session := _encounter()
	var downed := _actor(session, "downed")
	h.equal(downed["wound_state"], "mortally_wounded", "wound state")
	h.equal(downed["death_save_due"], true, "death save due")
	h.equal(downed["death_save_penalty"], 0, "no saves attempted yet")
	h.equal(downed["action_penalty"], -4, "action penalty")


static func _death_saves(h: Harness) -> void:
	h.it("survives a save rolled under BODY and raises the next one")
	# BODY 7, penalty 0, a d10 of 3 is under it.
	var session := _encounter([3])
	session.death_save("downed")
	var after := _actor(session, "downed")
	h.equal(after["wound_state"], "mortally_wounded", "still dying")
	h.equal(after["death_save_due"], true, "still owes the next one")
	h.equal(after["death_save_penalty"], 1, "penalty raised")
	h.equal(String(session.card["title"]), "SURVIVED", "card")
	h.contains(session.snapshot()["actions_taken"]["downed"], "Death Save", "action noted")

	h.it("kills a character whose save meets their BODY")
	var lethal := _encounter([7])
	lethal.death_save("downed")
	var dead := _actor(lethal, "downed")
	h.equal(dead["wound_state"], "dead", "wound state")
	h.equal(dead["death_save_due"], false, "a corpse owes nothing")
	h.equal(String(lethal.card["title"]), "DEAD", "card")

	h.it("fails on a natural 10 whatever the BODY")
	var unlucky := Encounter.new(
		_tables(),
		{"tank": {"name": "Tank", "max_hp": 40, "hp": 0, "stats": {"BODY": 12}, "weapons": {}}},
		Dice.FixedRandom.new([10]),
	)
	unlucky.death_save("tank")
	h.equal(String(unlucky.actor("tank")["wound_state"]), "dead", "a 10 kills a BODY 12")

	h.it("accumulates the penalty across saves until one fails")
	var ladder := _encounter([1, 1, 1, 1, 1, 1, 1])
	for attempt in 7:
		if Mortality.owes_death_save(ladder.actor("downed")):
			ladder.death_save("downed")
	# A d10 of 1 survives at penalties 0..5 and dies at 6, where 1 + 6 >= BODY 7.
	h.equal(int(ladder.actor("downed")["death_save_penalty"]), 7, "seven saves attempted")
	h.equal(String(ladder.actor("downed")["wound_state"]), "dead", "the ladder runs out")

	h.it("undoes a fatal save exactly")
	var undone := _encounter([7])
	undone.death_save("downed")
	undone.undo()
	var restored := _actor(undone, "downed")
	h.equal(restored["wound_state"], "mortally_wounded", "wound state restored")
	h.equal(restored["death_save_due"], true, "save owed again")
	h.equal(restored["death_save_penalty"], 0, "penalty restored")


static func _stabilizing(h: Harness) -> void:
	h.it("stops the saves when the medic makes the DV")
	# First Aid 14 + a d10 of 4 = 18, over the DV 15 default.
	var session := _encounter([4])
	session.stabilize("downed", "medtech")
	var patient := _actor(session, "downed")
	h.equal(patient["death_save_due"], false, "no longer owes a save")
	h.equal(patient["wound_state"], "mortally_wounded", "stabilising heals nothing")
	h.equal(String(session.card["title"]), "STABILIZED", "card")

	h.it("leaves the patient dying when the medic misses")
	var failed := _encounter([1, 8])
	# A d10 of 1 fumbles down by the next roll: 14 + (1 - 8) = 7, under DV 15.
	failed.stabilize("downed", "medtech")
	h.equal(_actor(failed, "downed")["death_save_due"], true, "still owes a save")
	h.equal(String(failed.card["title"]), "STILL DYING", "card")

	h.it("puts a stabilized character back on saves when they are hit again")
	# The stabilise check, then the attack: a d10 of 5, damage 6 6 6, and the
	# critical injury those three sixes trip.
	var shot := _encounter([4, 5, 6, 6, 6, 3, 4])
	shot.stabilize("downed", "medtech")
	h.equal(_actor(shot, "downed")["death_save_due"], false, "stabilized")
	shot.attack(
		{
			"attacker_id": "solo",
			"target_id": "downed",
			"weapon": "Heavy Pistol",
			"distance_m": 5.0,
		}
	)
	h.equal(_actor(shot, "downed")["death_save_due"], true, "back on the clock")

	h.it("undoes a stabilization")
	var undone := _encounter([4])
	undone.stabilize("downed", "medtech")
	undone.undo()
	h.equal(_actor(undone, "downed")["death_save_due"], true, "save owed again")


static func _healing(h: Harness) -> void:
	h.it("heals HP and re-reads the wound state")
	var session := _encounter()
	session.heal("downed", 25)
	var healed := _actor(session, "downed")
	h.equal(healed["hp"], 25, "hp")
	h.equal(healed["wound_state"], "lightly_wounded", "wound state recomputed")
	h.equal(healed["death_save_due"], false, "off the clock")

	h.it("stops at seriously wounded when the healing is thin")
	var thin := _encounter()
	thin.heal("downed", 5)
	h.equal(_actor(thin, "downed")["wound_state"], "seriously_wounded", "wound state")

	h.it("never exceeds max HP")
	var topped := _encounter()
	topped.heal("downed", 500)
	h.equal(_actor(topped, "downed")["hp"], 40, "hp")
	h.equal(_actor(topped, "downed")["wound_state"], "unhurt", "wound state")

	h.it("does nothing for the dead")
	var morgue := _encounter([7])
	morgue.death_save("downed")
	morgue.heal("downed", 20)
	var corpse := _actor(morgue, "downed")
	h.equal(corpse["hp"], 0, "hp unchanged")
	h.equal(corpse["wound_state"], "dead", "still dead")

	h.it("undoes healing exactly")
	var undone := _encounter()
	undone.heal("downed", 25)
	undone.undo()
	var before := _actor(undone, "downed")
	h.equal(before["hp"], 0, "hp")
	h.equal(before["wound_state"], "mortally_wounded", "wound state")
	h.equal(before["death_save_due"], true, "save owed again")


static func _injuries(h: Harness) -> void:
	h.it("treats a critical injury off the sheet")
	var cast := _cast()
	(cast["downed"] as Dictionary)["critical_injuries"] = ["Broken Ribs"]
	var session := Encounter.new(_tables(), cast, Dice.FixedRandom.new([4]))
	session.treat_injury("downed", "medtech", "Broken Ribs", "Surgery", 17)
	h.equal(_actor(session, "downed")["critical_injuries"], [], "injury cleared")
	h.equal(String(session.card["title"]), "TREATED", "card")

	h.it("leaves the injury alone on a failed check")
	var cast_two := _cast()
	(cast_two["downed"] as Dictionary)["critical_injuries"] = ["Broken Ribs"]
	var failed := Encounter.new(_tables(), cast_two, Dice.FixedRandom.new([1, 9]))
	failed.treat_injury("downed", "medtech", "Broken Ribs", "Surgery", 17)
	h.equal(_actor(failed, "downed")["critical_injuries"], ["Broken Ribs"], "injury kept")

	h.it("undoes a treatment")
	var cast_three := _cast()
	(cast_three["downed"] as Dictionary)["critical_injuries"] = ["Broken Ribs"]
	var undone := Encounter.new(_tables(), cast_three, Dice.FixedRandom.new([4]))
	undone.treat_injury("downed", "medtech", "Broken Ribs", "Surgery", 17)
	undone.undo()
	h.equal(_actor(undone, "downed")["critical_injuries"], ["Broken Ribs"], "injury back")


static func _penalties(h: Harness) -> void:
	h.it("puts the attacker's wound penalty on their attack")
	var cast := _cast()
	(cast["solo"] as Dictionary)["hp"] = 10
	# Attack base 12, seriously wounded at -2, a d10 of 5: 12 - 2 + 5 = 15.
	var session := Encounter.new(_tables(), cast, Dice.FixedRandom.new([5, 1, 1, 1]))
	h.equal(String(session.actor("solo")["wound_state"]), "seriously_wounded", "wound state")
	session.attack(
		{
			"attacker_id": "solo",
			"target_id": "downed",
			"weapon": "Heavy Pistol",
			"distance_m": 5.0,
		}
	)
	h.equal(int(session.result["attack_total"]), 15, "attack total carries the penalty")
	h.contains(session.card["lines"][0], "wounds -2", "the card shows the penalty")

	h.it("puts the defender's wound penalty on their evasion")
	var contest := Encounter.new(_tables(), _cast(), Dice.FixedRandom.new([5, 5, 1, 1, 1]))
	contest.attack(
		{
			"attacker_id": "solo",
			"target_id": "downed",
			"weapon": "Heavy Pistol",
			"distance_m": 5.0,
			"contested": true,
		}
	)
	# Evasion base 8, mortally wounded at -4, a d10 of 5: 8 - 4 + 5 = 9.
	h.equal(int(contest.result["defense"]), 9, "defence carries the penalty")

	h.it("refuses to let a dead actor act")
	var morgue := _encounter([7])
	morgue.death_save("downed")
	h.equal(Mortality.can_act(morgue.actor("downed")), false, "the dead do not act")
	h.equal(Mortality.can_act(morgue.actor("solo")), true, "the living do")
