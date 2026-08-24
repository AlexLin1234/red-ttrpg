extends RefCounted

## Ported from the original Python `tests/test_events.py`.
##
## The contract: applying an event sequence and then applying its inverse must
## restore the previous state exactly, for any attack the resolver can produce.
## The GM's undo button depends on it.

const Harness := preload("res://tests/harness.gd")


static func _tables() -> Tables:
	var body := {}
	var head := {}
	for roll in range(2, 13):
		body[str(roll)] = {"name": "Injury body %d" % roll, "page": 187}
		head[str(roll)] = {"name": "Injury head %d" % roll, "page": 187}
	return Tables.new(
		{
			"ranged_dv": {"pistol": [{"min_m": 0.0, "max_m": 1000.0, "dv": 13}]},
			"autofire_dv": {"pistol": [{"min_m": 0.0, "max_m": 1000.0, "dv": 17}]},
			"weapons": {},
			"critical_injuries": {"body": body, "head": head},
		}
	)


static func _world(target: Resolver.TargetState, weapon_name: String, ammo: int) -> Dictionary:
	return {
		"actors":
		{
			"solo":
			{
				"hp": 40,
				"max_hp": 40,
				"armor": {},
				"cover_hp": 0,
				"wound_state": "unhurt",
				"death_save_due": false,
				"critical_injuries": [],
				"weapons": {weapon_name: {"ammo": ammo, "jammed": false}},
			},
			"goon":
			{
				"hp": target.hp,
				"max_hp": target.max_hp,
				"armor": {"body": target.sp_at("body"), "head": target.sp_at("head")},
				"cover_hp": target.cover_hp,
				"critical_injuries": [],
				"wound_state": "lightly_wounded",
				"death_save_due": false,
				"weapons": {},
			},
		}
	}


static func run(h: Harness) -> void:
	h.describe("events")

	h.it("restores exact state after applying an inverse")
	var target := Resolver.TargetState.new("goon", 30, 40, {"body": 7})
	var weapon := Resolver.Weapon.new("Heavy Pistol", "pistol", 3, 1, 8)
	var before := _world(target, weapon.name, 8)
	var pristine := before.duplicate(true)
	var result := Resolver.resolve_attack(
		Resolver.AttackRequest.new("solo", target, weapon, 14, 5.0, 8),
		_tables(),
		Dice.SeededRandom.new(7),
	)
	var applied := Events.apply(before, result.events)
	var restored := Events.apply(applied["state"], applied["inverse"])
	h.equal(restored["state"], pristine, "restored state")
	h.equal(before, pristine, "apply must not mutate its input")

	h.it("reverses a cover assignment and its damage as one action")
	var bare := Resolver.TargetState.new("goon", 30, 40)
	var cover_before := _world(bare, weapon.name, 8)
	var cover_pristine := cover_before.duplicate(true)
	var cover_events: Array[Dictionary] = [
		{"kind": "cover_set", "target_id": "goon", "hp": 20, "cover_id": "crate"},
		{"kind": "cover_damaged", "target_id": "goon", "amount": 12, "cover_id": "crate"},
	]
	var cover_applied := Events.apply(cover_before, cover_events)
	h.equal(cover_applied["state"]["actors"]["goon"]["cover_hp"], 8, "cover HP after damage")
	var cover_restored := Events.apply(cover_applied["state"], cover_applied["inverse"])
	h.equal(cover_restored["state"], cover_pristine, "restored state")
	var inverse: Array = cover_applied["inverse"]
	h.equal(inverse[0]["cover_id"], "crate", "first inverse cover id")
	h.equal(inverse[1]["affected_cover_id"], "crate", "second inverse cover id")

	h.it("round trips one thousand random attacks")
	var generator := RandomNumberGenerator.new()
	generator.seed = 20260815
	var tables := _tables()
	var mismatches := 0
	var cover_options := [0, 0, 0, 5, 10, 20]
	for iteration in 1000:
		var max_hp := generator.randi_range(20, 60)
		var fuzz_target := Resolver.TargetState.new(
			"goon",
			generator.randi_range(1, max_hp),
			max_hp,
			{"body": generator.randi_range(0, 15), "head": generator.randi_range(0, 15)},
			cover_options[generator.randi_range(0, cover_options.size() - 1)],
		)
		var fuzz_weapon := Resolver.Weapon.new("Test Gun", "pistol", generator.randi_range(2, 6), 1, 20)
		var fuzz_before := _world(fuzz_target, fuzz_weapon.name, 20)
		var fuzz_pristine := fuzz_before.duplicate(true)
		var fuzz_result := Resolver.resolve_attack(
			Resolver.AttackRequest.new(
				"solo",
				fuzz_target,
				fuzz_weapon,
				generator.randi_range(5, 20),
				float(generator.randi_range(0, 6)),
				20
			),
			tables,
			Dice.SeededRandom.new(generator.randi()),
		)
		var fuzz_applied := Events.apply(fuzz_before, fuzz_result.events)
		var fuzz_restored := Events.apply(fuzz_applied["state"], fuzz_applied["inverse"])
		if not Harness._deep_equal(fuzz_restored["state"], fuzz_pristine):
			mismatches += 1
	h.equal(mismatches, 0, "round-trip mismatches over 1000 attacks")

	h.it("undoes, redoes, and clears redo on a new action")
	var session_target := Resolver.TargetState.new("goon", 30, 40, {"body": 0})
	var initial := _world(session_target, weapon.name, 8)
	var session_result := Resolver.resolve_attack(
		Resolver.AttackRequest.new("solo", session_target, weapon, 20, 5.0, 8),
		_tables(),
		Dice.SeededRandom.new(3),
	)
	var session := Events.Session.new(initial.duplicate(true))
	var resolved := session.record({"kind": "attack"}, session_result.events)
	h.equal(session.undo(), initial, "state after undo")
	h.equal(session.redo(), resolved, "state after redo")
	session.undo()
	session.record({"kind": "miss"}, [{"kind": "attack_missed", "target_id": "goon"}])
	h.equal(session.redo_log.size(), 0, "redo log cleared by a new action")

	h.it("does not cap undo depth")
	var deep_target := Resolver.TargetState.new("goon", 30, 40)
	var deep_initial := _world(deep_target, "Heavy Pistol", 200)
	var deep_session := Events.Session.new(deep_initial.duplicate(true))
	for index in 100:
		deep_session.record(
			{"index": index},
			[{"kind": "ammo_spent", "actor_id": "solo", "weapon": "Heavy Pistol", "amount": 1}],
		)
	for index in 100:
		deep_session.undo()
	h.equal(deep_session.state, deep_initial, "state after 100 undos")

	h.it("moves an actor and puts them back exactly")
	var board := {"actors": {"solo": {"position": {"x": 2, "z": 3, "layer": 0}}}}
	var walked := Events.apply(
		board, [{"kind": "actor_moved", "actor_id": "solo", "to": {"x": 7, "z": 1, "layer": 1}}]
	)
	h.equal(
		walked["state"]["actors"]["solo"]["position"], {"x": 7, "z": 1, "layer": 1}, "position"
	)
	h.equal(
		Events.apply(walked["state"], walked["inverse"])["state"], board, "state after the inverse"
	)

	h.it("clears a position the actor never had")
	var placeless := {"actors": {"solo": {}}}
	var placed := Events.apply(
		placeless, [{"kind": "actor_moved", "actor_id": "solo", "to": {"x": 1, "z": 1, "layer": 0}}]
	)
	h.equal(placed["inverse"][0]["to"], null, "the inverse carries no destination")
	h.equal(Events.apply(placed["state"], placed["inverse"])["state"], placeless, "state restored")

	h.it("reports when there is nothing to undo")
	var empty := Events.Session.new({"actors": {}})
	h.equal(empty.can_undo(), false, "can undo")
	h.equal(empty.can_redo(), false, "can redo")
