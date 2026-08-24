extends RefCounted

## Ported from the original Python `tests/test_encounter.py`.

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
			"weapons":
			{
				"Heavy Pistol":
				{
					"range_type": "pistol",
					"skill": "Handgun",
					"damage_dice": 3,
					"magazine": 8,
					"rof": 2,
					"hands": 1,
					"concealable": true,
					"autofire_rating": -1,
					"page": 341,
				}
			},
			"critical_injuries": {"body": body, "head": head},
		}
	)


static func _solo() -> Dictionary:
	return {
		"name": "Rache",
		"max_hp": 40,
		"attack_base": 12,
		"evasion_base": 10,
		"weapons":
		{
			"Heavy Pistol":
			{"ammo": 8, "weapon_type": "pistol", "damage_dice": 3, "magazine": 8}
		},
	}


## The solo with stats on the sheet: REF to win initiative outright and MOVE 6,
## so one Move Action reaches 12 m.
static func _runner(ammo := 8) -> Dictionary:
	var solo := _solo()
	solo["stats"] = {"MOVE": 6, "REF": 7}
	(solo["weapons"]["Heavy Pistol"] as Dictionary)["ammo"] = ammo
	return solo


static func _goon() -> Dictionary:
	return {
		"name": "Booster",
		"max_hp": 40,
		"hp": 30,
		"armor": {"body": 7, "head": 7},
		"evasion_base": 8,
		"weapons": {},
	}


static func _encounter(rolls: Array[int] = [], dv := 13, actors := {}) -> Encounter:
	var cast := actors if not actors.is_empty() else {"solo": _solo(), "goon": _goon()}
	return Encounter.new(_tables(dv), cast, Dice.FixedRandom.new(rolls))


static func _strike(session: Encounter, overrides := {}) -> Dictionary:
	var command := {
		"attacker_id": "solo",
		"target_id": "goon",
		"weapon": "Heavy Pistol",
		"distance_m": 5.0,
	}
	command.merge(overrides, true)
	session.attack(command)
	return session.snapshot()


static func _shot() -> Dictionary:
	return {
		"attacker_id": "solo",
		"target_id": "goon",
		"weapon": "Heavy Pistol",
		"distance_m": 5.0,
	}


## Roll initiative with the solo ahead of the goon on REF, and no dice left over.
static func _in_combat(rolls: Array[int] = [5, 5], solo := {}) -> Encounter:
	var session := _encounter(rolls, 13, {"solo": _runner() if solo.is_empty() else solo, "goon": _goon()})
	session.roll_initiative()
	return session


static func _actor(snapshot: Dictionary, id: String) -> Dictionary:
	for entry in snapshot["actors"]:
		if String(entry["id"]) == id:
			return entry
	return {}


static func run(h: Harness) -> void:
	h.describe("encounter")

	h.it("fills defaults and reports a drawable snapshot")
	var fresh := _encounter().snapshot()
	var goon := _actor(fresh, "goon")
	h.equal(goon["name"], "Booster", "name")
	# Read off the HP it was loaded with, 30 of 40, rather than assumed unhurt.
	h.equal(goon["wound_state"], "lightly_wounded", "wound state")
	h.equal(goon["death_save_due"], false, "death save")
	h.equal(goon["critical_injuries"], [], "injuries")
	var solo := _actor(fresh, "solo")
	h.equal(solo["hp"], 40, "hp defaults to max_hp")
	h.equal(solo["attack_base"], 12, "attack base")
	h.equal(solo["selected_weapon"], "Heavy Pistol", "selected weapon")
	var first_weapon: Dictionary = solo["weapons"][0]
	h.equal(first_weapon["name"], "Heavy Pistol", "weapon name")
	h.equal(first_weapon["ammo"], 8, "weapon ammo")
	h.equal(first_weapon["jammed"], false, "weapon jammed")
	h.equal(first_weapon["magazine"], 8, "weapon magazine")
	h.equal(first_weapon["autofire_rating"], -1, "weapon autofire")
	h.equal(fresh["card"], {}, "card")
	h.equal(fresh["can_undo"], false, "can undo")

	h.it("spends ammo, applies damage and renders a card")
	var hit_session := _encounter([8, 4, 4, 4])
	var hit := _strike(hit_session)
	h.equal(_actor(hit, "goon")["hp"], 25, "target hp")
	h.equal(_actor(hit, "solo")["weapons"][0]["ammo"], 7, "ammo")
	h.equal(hit["card"]["title"], "HIT", "card title")
	h.equal(hit["card"]["attacker"], "Rache", "card attacker")
	h.equal(hit["card"]["target"], "Booster", "card target")
	h.equal(hit["card"]["hp_damage"], 5, "card damage")
	h.equal(hit["events"][0]["kind"], "ammo_spent", "first event")
	h.equal(hit["result"]["hit"], true, "result hit")
	h.equal(hit["can_undo"], true, "can undo")

	h.it("titles a miss and costs only ammo")
	var miss := _strike(_encounter([2], 20))
	h.equal(miss["card"]["title"], "MISS", "card title")
	h.equal(_actor(miss, "goon")["hp"], 30, "target hp")
	h.equal(_actor(miss, "solo")["weapons"][0]["ammo"], 7, "ammo")

	h.it("names a critical injury on the card")
	var crit := _strike(_encounter([8, 6, 6, 2, 3, 4]))
	h.equal(crit["card"]["title"], "CRITICAL INJURY", "card title")
	h.equal(crit["card"]["critical_injury"], "Test body injury 7", "injury")
	h.equal(_actor(crit, "goon")["critical_injuries"], ["Test body injury 7"], "injury list")

	h.it("reports wound state and death saves")
	var downed := _strike(
		_encounter(
			[8, 4, 4, 4],
			13,
			{"solo": _solo(), "goon": {"name": "Booster", "max_hp": 20, "hp": 10, "weapons": {}}},
		)
	)
	var hurt := _actor(downed, "goon")
	h.equal(hurt["hp"], -2, "hp")
	# The hit crosses the serious threshold and carries on past zero, so the
	# state it settles on is the worse of the two the shot passed through.
	h.equal(hurt["wound_state"], "mortally_wounded", "wound state")
	h.equal(hurt["death_save_due"], true, "death save")

	h.it("takes reinforcements without restarting the fight")
	var reinforced := _encounter([5, 5, 9])
	reinforced.roll_initiative()
	reinforced.end_turn()
	var round_before := reinforced.round_number
	var order_before := reinforced.initiative.size()
	reinforced.add_actors({"backup": _goon()})
	h.equal(reinforced.round_number, round_before, "the round did not restart")
	h.equal(reinforced.initiative.size(), order_before + 1, "and the arrival is in the order")
	h.equal(reinforced.has_actor("backup"), true, "the actor exists")
	h.equal(reinforced.can_undo(), true, "the arrival is on the undo stack")

	h.it("undoes an arrival, order and all")
	reinforced.undo()
	h.equal(reinforced.has_actor("backup"), false, "the actor is gone")
	h.equal(reinforced.initiative.size(), order_before, "and so is its initiative row")

	h.it("ignores an actor it already has")
	var twice := _encounter()
	twice.add_actors({"goon": _goon()})
	h.equal(twice.can_undo(), false, "nothing was recorded")

	h.it("lets cover absorb the hit instead of the target")
	var shielded_session := _encounter(
		[8, 4, 4, 4],
		13,
		{
			"solo": _solo(),
			"goon": {"name": "Booster", "max_hp": 40, "hp": 30, "cover_hp": 10, "weapons": {}},
		},
	)
	var shielded := _strike(shielded_session)
	h.equal(_actor(shielded, "goon")["cover_hp"], 0, "cover hp")
	h.equal(_actor(shielded, "goon")["hp"], 30, "target hp")
	h.equal(shielded["card"]["title"], "STOPPED", "card title")

	h.it("falls back to the table profile when the actor has no inline stats")
	var table_backed := _strike(
		_encounter(
			[8, 4, 4, 4],
			13,
			{
				"solo": {"max_hp": 40, "attack_base": 12, "weapons": {"Heavy Pistol": {"ammo": 8}}},
				"goon": {"max_hp": 40, "hp": 30, "armor": {"body": 7, "head": 7}, "weapons": {}},
			},
		)
	)
	h.equal(_actor(table_backed, "goon")["hp"], 25, "three d6 from the table profile")

	h.it("is event sourced and reversible for cover")
	var cover_session := _encounter([8, 4, 4, 4])
	var covered := _strike(cover_session, {"cover_hp": 20, "cover_id": "BlueBarrier"})
	h.equal(_actor(covered, "goon")["cover_hp"], 8, "cover hp")
	h.equal(covered["covers"], {"BlueBarrier": 8}, "covers")
	h.equal(_actor(covered, "goon")["hp"], 30, "target hp")
	var kinds := PackedStringArray()
	for event in covered["events"]:
		kinds.append(String(event["kind"]))
	h.equal(kinds, PackedStringArray(["cover_set", "ammo_spent", "cover_damaged"]), "events")

	cover_session.undo()
	var undone := cover_session.snapshot()
	h.equal(_actor(undone, "goon")["cover_hp"], 0, "cover hp after undo")
	h.equal(undone["covers"], {}, "covers after undo")

	cover_session.redo()
	var redone := cover_session.snapshot()
	h.equal(redone["covers"], {"BlueBarrier": 8}, "covers after redo")

	h.it("restores the previous state on undo and replays it on redo")
	var history := _encounter([8, 4, 4, 4])
	_strike(history)
	history.undo()
	var back := history.snapshot()
	h.equal(_actor(back, "goon")["hp"], 30, "hp after undo")
	h.equal(_actor(back, "solo")["weapons"][0]["ammo"], 8, "ammo after undo")
	h.equal(back["card"]["title"], "UNDO", "card title")
	h.equal(back["can_redo"], true, "can redo")
	history.redo()
	var forward := history.snapshot()
	h.equal(_actor(forward, "goon")["hp"], 25, "hp after redo")
	h.equal(forward["card"]["title"], "REDO", "card title")

	h.it("refills the magazine reversibly")
	var reload_session := _encounter([2], 20)
	_strike(reload_session)
	reload_session.reload("solo", "Heavy Pistol")
	h.equal(_actor(reload_session.snapshot(), "solo")["weapons"][0]["ammo"], 8, "ammo after reload")
	reload_session.undo()
	h.equal(_actor(reload_session.snapshot(), "solo")["weapons"][0]["ammo"], 7, "ammo after undo")

	h.it("keeps an uncosted homebrew weapon drawable")
	var homebrew := _encounter([], 13, {"solo": {"max_hp": 40, "weapons": {"Homebrew": {"ammo": 3}}}})
	var drawn: Dictionary = _actor(homebrew.snapshot(), "solo")["weapons"][0]
	h.equal(drawn["name"], "Homebrew", "name")
	h.equal(drawn["ammo"], 3, "ammo")
	h.equal(drawn["weapon_type"], "unknown", "weapon type")

	h.it("orders initiative by 1d10 + REF and cycles turns into the next round")
	var order_session := _encounter(
		[3, 9],
		13,
		{
			"slow": {"name": "Slow", "max_hp": 20, "ref": 2, "weapons": {}},
			"fast": {"name": "Fast", "max_hp": 20, "ref": 8, "weapons": {}},
		},
	)
	var order := order_session.roll_initiative()
	h.equal(order[0]["actor_id"], "fast", "first in order")
	h.equal(order[1]["actor_id"], "slow", "second in order")
	h.equal(order_session.round_number, 1, "round")
	h.equal(order_session.current_turn()["actor_id"], "fast", "current turn")
	order_session.end_turn()
	h.equal(order_session.current_turn()["actor_id"], "slow", "next turn")
	h.equal(order_session.round_number, 1, "still round 1")
	order_session.end_turn()
	h.equal(order_session.current_turn()["actor_id"], "fast", "wrapped turn")
	h.equal(order_session.round_number, 2, "round advanced")

	h.it("records the actions an actor has spent this turn")
	var action_session := _in_combat([5, 5, 8, 4, 4, 4])
	_strike(action_session)
	h.equal(action_session.snapshot()["actions_taken"]["solo"], ["Attack"], "actions")
	h.equal(_actor(action_session.snapshot(), "solo")["spent"]["action"], "Attack", "spent Action")
	h.equal(_actor(action_session.snapshot(), "solo")["spent"]["move"], "", "Move Action untouched")

	h.it("refuses an attack out of turn and names whose turn it is")
	var out_of_turn := _in_combat()
	out_of_turn.end_turn()
	var refused := out_of_turn.attack(_shot())
	h.equal(refused["ok"], false, "refused")
	h.equal(refused["code"], "not_your_turn", "code")
	h.contains(String(refused["reason"]), "Booster", "reason names who is up")
	h.equal(refused["override"], true, "the table may waive turn order")
	h.equal(out_of_turn.snapshot()["card"]["title"], "CANNOT", "card title")
	h.equal(_actor(out_of_turn.snapshot(), "solo")["weapons"][0]["ammo"], 8, "no ammo spent")
	h.equal(out_of_turn.can_undo(), true, "the refusal did not enter the log")
	h.equal(out_of_turn.snapshot()["warning"]["code"], "not_your_turn", "warning on the snapshot")

	h.it("resolves anyway once the GM waives the turn order")
	var waived := _in_combat([5, 5, 8, 4, 4, 4])
	waived.end_turn()
	var command := _shot()
	command["override"] = true
	var forced := waived.attack(command)
	h.equal(forced["ok"], true, "resolved")
	h.equal(_actor(waived.snapshot(), "goon")["hp"], 25, "damage applied")
	h.equal(waived.snapshot()["warning"], {}, "warning cleared")

	h.it("keeps an empty magazine impossible however the GM rules")
	var dry := _in_combat([5, 5], _runner(0))
	var empty_command := _shot()
	empty_command["override"] = true
	var blocked := dry.attack(empty_command)
	h.equal(blocked["ok"], false, "still refused")
	h.equal(blocked["code"], "no_ammo", "code")
	h.equal(blocked["override"], false, "not a ruling the table can waive")
	h.contains(String(blocked["hint"]), "Action", "hint names what a reload costs")

	h.it("spends the whole Action on a reload, so that turn cannot also shoot")
	var reloading := _in_combat([5, 5], _runner(2))
	h.equal(reloading.reload("solo", "Heavy Pistol")["ok"], true, "reload allowed")
	h.equal(_actor(reloading.snapshot(), "solo")["weapons"][0]["ammo"], 8, "magazine filled")
	var after_reload := reloading.attack(_shot())
	h.equal(after_reload["ok"], false, "the shot is refused")
	h.equal(after_reload["code"], "action_spent", "code")
	h.contains(String(after_reload["reason"]), "Reload", "reason names the reload")
	h.equal(reloading.check_action("solo", "move", {})["ok"], true, "the Move Action survives")
	reloading.end_turn()
	reloading.end_turn()
	h.equal(reloading.round_number, 2, "round advanced")
	var next_turn := reloading.check_action("solo", "attack", {"weapon": "Heavy Pistol"})
	h.equal(next_turn["ok"], true, "the reloaded weapon fires next turn")

	h.it("refuses a reload the weapon does not need")
	var full := _in_combat()
	var pointless := full.reload("solo", "Heavy Pistol")
	h.equal(pointless["code"], "magazine_full", "code")
	h.contains(String(pointless["reason"]), "8 of 8", "reason names the count")

	h.it("records a move as a Move Action and walks it back on undo")
	var walk := _in_combat()
	h.equal(walk.move("solo", {"x": 3, "z": 4, "layer": 0}, {"distance_m": 10.0})["ok"], true, "moved")
	h.equal(walk.position("solo"), {"x": 3, "z": 4, "layer": 0}, "position")
	h.equal(walk.snapshot()["actions_taken"]["solo"], ["Move"], "spent the Move Action")
	h.equal(walk.check_action("solo", "attack", {"weapon": "Heavy Pistol"})["ok"], true, "Action left")
	h.equal(walk.move("solo", {"x": 5, "z": 5, "layer": 0}, {"distance_m": 4.0})["code"], "move_spent", "second move")
	h.contains(String(walk.snapshot()["undo_label"]), "move to (3, 4)", "undo label")
	walk.undo()
	h.equal(walk.position("solo"), {"x": 0, "z": 0, "layer": 0}, "position after undo")
	h.equal((walk.snapshot()["actions_taken"] as Dictionary).has("solo"), false, "Move Action handed back")
	walk.redo()
	h.equal(walk.position("solo"), {"x": 3, "z": 4, "layer": 0}, "position after redo")
	h.equal(walk.snapshot()["actions_taken"]["solo"], ["Move"], "spent again after redo")

	h.it("refuses a move past MOVE x 2 and offers it as a ruling")
	var overrun := _in_combat()
	var too_far := overrun.move("solo", {"x": 20, "z": 0, "layer": 0}, {"distance_m": 30.0})
	h.equal(too_far["code"], "out_of_reach", "code")
	h.equal(too_far["override"], true, "waivable")
	h.contains(String(too_far["reason"]), "12.0 m", "reason names the allowance")
	h.equal(overrun.position("solo"), {"x": 0, "z": 0, "layer": 0}, "the token did not move")
	var run := overrun.move(
		"solo", {"x": 20, "z": 0, "layer": 0}, {"distance_m": 30.0, "override": true}
	)
	h.equal(run["ok"], true, "the GM can waive the distance")
	h.equal(overrun.position("solo"), {"x": 20, "z": 0, "layer": 0}, "position after the ruling")

	h.it("hands the Action back when the attack that spent it is undone")
	var refund := _in_combat([5, 5, 8, 4, 4, 4])
	_strike(refund)
	h.equal(refund.snapshot()["actions_taken"]["solo"], ["Attack"], "spent")
	refund.undo()
	h.equal((refund.snapshot()["actions_taken"] as Dictionary).has("solo"), false, "handed back")
	h.equal(refund.check_action("solo", "attack", {"weapon": "Heavy Pistol"})["ok"], true, "available again")

	h.it("undoes the end of a turn and the initiative roll itself")
	var rewind := _in_combat()
	rewind.end_turn()
	h.equal(rewind.current_turn()["actor_id"], "goon", "the goon is up")
	rewind.undo()
	h.equal(rewind.current_turn()["actor_id"], "solo", "back to the solo")
	h.equal(rewind.round_number, 1, "still round 1")
	rewind.undo()
	h.equal(rewind.round_number, 0, "back to setup")
	h.equal(rewind.initiative, [], "the order is cleared")
	h.equal(rewind.can_undo(), false, "nothing left to undo")

	h.it("refuses a jammed weapon and charges an Action to clear it")
	var jammed_solo := _runner()
	(jammed_solo["weapons"]["Heavy Pistol"] as Dictionary)["jammed"] = true
	var jam := _in_combat([5, 5], jammed_solo)
	var stuck := jam.attack(_shot())
	h.equal(stuck["code"], "weapon_jammed", "code")
	h.equal(stuck["override"], false, "not waivable")
	h.equal(jam.clear_jam("solo", "Heavy Pistol")["ok"], true, "cleared")
	h.equal(jam.snapshot()["actions_taken"]["solo"], ["Clear Jam"], "clearing costs the Action")
	h.equal(jam.attack(_shot())["code"], "action_spent", "no shot left this turn")
	h.equal(jam.clear_jam("solo", "Heavy Pistol")["code"], "action_spent", "and no second clear")

	h.it("publishes every action's availability with the snapshot")
	var advertised := _in_combat([5, 5], _runner(0))
	var view := _actor(advertised.snapshot(), "solo")
	h.equal(view["available"]["attack"]["ok"], false, "attack unavailable")
	h.equal(view["available"]["attack"]["code"], "no_ammo", "attack code")
	h.equal(view["available"]["autofire"]["code"], "no_autofire", "autofire code")
	h.equal(view["available"]["reload"]["ok"], true, "reload available")
	h.equal(view["available"]["clear_jam"]["code"], "not_jammed", "jam code")
	h.equal(view["available"]["move"]["ok"], true, "move available")
	h.equal(view["move_allowance"], 12.0, "move allowance")
	h.equal(view["position"], {"x": 0, "z": 0, "layer": 0}, "position")
	h.equal(advertised.snapshot()["warning"], {}, "no warning yet")

	h.it("refuses to act with a downed unit")
	var downed_solo := _runner()
	downed_solo["hp"] = 0
	var corpse := _in_combat([5, 5], downed_solo)
	var lifeless := corpse.attack(_shot())
	h.equal(lifeless["code"], "actor_down", "code")
	h.equal(corpse.check_action("solo", "move", {})["code"], "actor_down", "move too")

	h.it("leaves setup unpoliced, because there is no turn to spend yet")
	var setup := _encounter([8, 4, 4, 4], 13, {"solo": _runner(), "goon": _goon()})
	h.equal(setup.check_action("solo", "attack", {"weapon": "Heavy Pistol"})["ok"], true, "attack")
	h.equal(setup.move("solo", {"x": 9, "z": 9, "layer": 0}, {"distance_m": 99.0})["ok"], true, "move")
