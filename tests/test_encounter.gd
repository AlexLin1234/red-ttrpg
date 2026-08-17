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
	h.equal(goon["wound_state"], "unhurt", "wound state")
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
	h.equal(hurt["wound_state"], "seriously_wounded", "wound state")
	h.equal(hurt["death_save_due"], true, "death save")

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
	var action_session := _encounter([5, 5, 8, 4, 4, 4])
	action_session.roll_initiative()
	_strike(action_session)
	h.equal(action_session.snapshot()["actions_taken"]["solo"], ["Attack"], "actions")
