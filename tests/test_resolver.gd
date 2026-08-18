extends RefCounted

## Ported from the original Python `tests/test_resolver.py`. Every case here pins
## a rule the resolver must keep.

const Harness := preload("res://tests/harness.gd")


## Flat DVs and predictable injuries, so a case tests one rule at a time.
static func _tables(dv := 13) -> Tables:
	var band := [{"min_m": 0.0, "max_m": 1000.0, "dv": dv}]
	var body := {}
	var head := {}
	for roll in range(2, 13):
		body[str(roll)] = {"name": "Test body injury %d" % roll, "page": 187}
		head[str(roll)] = {"name": "Test head injury %d" % roll, "page": 187}
	return Tables.new(
		{
			"ranged_dv": {"pistol": band, "assault_rifle": band},
			"autofire_dv": {"pistol": band, "assault_rifle": band},
			"weapons": {},
			"critical_injuries": {"body": body, "head": head},
		}
	)


static func _target(overrides := {}) -> Resolver.TargetState:
	return Resolver.TargetState.new(
		"goon",
		int(overrides.get("hp", 30)),
		int(overrides.get("max_hp", 40)),
		overrides.get("armor", {"body": 7, "head": 7}),
		int(overrides.get("cover_hp", 0)),
	)


static func _request(overrides := {}) -> Resolver.AttackRequest:
	var weapon: Resolver.Weapon = overrides.get(
		"weapon", Resolver.Weapon.new("Heavy Pistol", "pistol", 3, 1, 8)
	)
	return Resolver.AttackRequest.new(
		"solo",
		overrides.get("target", _target()),
		weapon,
		int(overrides.get("attack_base", 12)),
		float(overrides.get("distance_m", 5.0)),
		int(overrides.get("ammo", 8)),
		String(overrides.get("location", "body")),
		String(overrides.get("mode", "single")),
		int(overrides.get("defender_evasion_base", -1)),
		int(overrides.get("modifiers", 0)),
	)


static func _kinds(result: Resolver.AttackResult) -> PackedStringArray:
	var kinds := PackedStringArray()
	for event in result.events:
		kinds.append(String(event["kind"]))
	return kinds


static func _rng(values: Array[int]) -> Dice.FixedRandom:
	return Dice.FixedRandom.new(values)


static func run(h: Harness) -> void:
	h.describe("resolver")

	h.it("rolls a plain check")
	h.equal(Dice.roll_check(_rng([7]))["total"], 7, "plain roll")

	h.it("explodes upward once on a ten")
	var exploded := Dice.roll_check(_rng([10, 6]))
	h.equal(exploded["rolls"], PackedInt32Array([10, 6]), "rolls")
	h.equal(exploded["total"], 16, "total")

	h.it("fumbles downward once on a one")
	var fumbled := Dice.roll_check(_rng([1, 6]))
	h.equal(fumbled["rolls"], PackedInt32Array([1, 6]), "rolls")
	h.equal(fumbled["total"], -5, "total")

	h.it("misses on a tie against a static DV")
	var tie := Resolver.resolve_attack(_request({"attack_base": 8}), _tables(13), _rng([5, 2, 3, 4]))
	h.equal(tie.hit, false, "hit")

	h.it("hits when the DV is beaten")
	var beat := Resolver.resolve_attack(_request({"attack_base": 9}), _tables(13), _rng([5, 2, 3, 4]))
	h.equal(beat.hit, true, "hit")

	h.it("misses on a tie in an opposed check")
	var opposed := Resolver.resolve_attack(
		_request({"attack_base": 8, "defender_evasion_base": 8}), _tables(), _rng([5, 5])
	)
	h.equal(opposed.hit, false, "hit")
	h.equal(opposed.defense_kind, "evasion", "defense kind")

	h.it("spends ammo on a miss and emits no damage")
	var missed := Resolver.resolve_attack(_request({"attack_base": 0}), _tables(20), _rng([2]))
	h.equal(_kinds(missed), PackedStringArray(["ammo_spent", "attack_missed"]), "events")
	h.equal(missed.hp_damage, 0, "hp damage")

	h.it("lets armor stop a hit without ablating")
	var stopped := Resolver.resolve_attack(_request(), _tables(), _rng([8, 2, 2, 3]))
	h.equal(stopped.raw_damage, 7, "raw damage")
	h.equal(stopped.hp_damage, 0, "hp damage")
	h.not_contains(_kinds(stopped), "armor_ablated", "events")

	h.it("ablates and damages on a penetrating hit")
	var through := Resolver.resolve_attack(_request(), _tables(), _rng([8, 4, 4, 4]))
	h.equal(through.hp_damage, 5, "hp damage")
	var tail := _kinds(through).slice(_kinds(through).size() - 2)
	h.equal(tail, PackedStringArray(["armor_ablated", "damage_taken"]), "trailing events")

	h.it("adds a workshop weapon's flat damage bonus")
	var custom_weapon := Resolver.Weapon.new("Custom Pistol", "pistol", 1, 1, 8, -1, "standard", 5)
	var custom_hit := Resolver.resolve_attack(
		_request({"weapon": custom_weapon, "target": _target({"armor": {"body": 0}})}),
		_tables(),
		_rng([8, 3]),
	)
	h.equal(custom_hit.raw_damage, 8, "1d6 + 5 damage")

	h.it("applies the head multiplier after armor")
	var head_shot := Resolver.resolve_attack(
		_request({"location": "head", "mode": "aimed", "attack_base": 20}),
		_tables(),
		_rng([8, 4, 4, 4]),
	)
	h.equal(head_shot.raw_damage, 12, "raw damage")
	h.equal(head_shot.armor_damage, 10, "armor damage")

	h.it("adds direct damage for a critical injury")
	var crit := Resolver.resolve_attack(_request(), _tables(), _rng([8, 6, 6, 2, 3, 4]))
	h.equal(crit.critical_injury, "Test body injury 7", "injury")
	h.equal(crit.armor_damage, 7, "armor damage")
	h.equal(crit.hp_damage, 12, "hp damage")
	h.contains(_kinds(crit), "critical_injury", "events")

	h.it("lets cover take the full hit and stop resolution")
	var covered := Resolver.resolve_attack(
		_request({"target": _target({"armor": {"body": 7}, "cover_hp": 4})}),
		_tables(),
		_rng([8, 6, 6, 6]),
	)
	h.equal(_kinds(covered), PackedStringArray(["ammo_spent", "cover_damaged"]), "events")
	h.equal(covered.hp_damage, 0, "hp damage")
	h.equal(covered.critical_injury, "", "injury")
	h.equal(covered.card_lines[covered.card_lines.size() - 1], "Cover: 4 HP - 18 = 0 HP", "card")

	h.it("emits seriously wounded when crossing half HP")
	var wounded := Resolver.resolve_attack(
		_request({"target": _target({"hp": 21, "armor": {"body": 0}})}), _tables(), _rng([8, 4, 4, 4])
	)
	h.contains(_kinds(wounded), "seriously_wounded", "events")

	h.it("does not emit seriously wounded when landing exactly on the threshold")
	var edge := Resolver.resolve_attack(
		_request(
			{
				"target": _target({"hp": 21, "armor": {"body": 0}}),
				"weapon": Resolver.Weapon.new("Needler", "pistol", 1),
			}
		),
		_tables(),
		_rng([8, 1]),
	)
	h.equal(edge.hp_damage, 1, "hp damage")
	h.not_contains(_kinds(edge), "seriously_wounded", "events")

	h.it("emits a death save when HP reaches zero")
	var downed := Resolver.resolve_attack(
		_request({"target": _target({"hp": 5, "armor": {"body": 0}})}), _tables(), _rng([8, 4, 4, 4])
	)
	h.contains(_kinds(downed), "death_save_due", "events")

	h.it("caps the autofire multiplier by margin and spends ten rounds")
	var burst := Resolver.resolve_attack(
		_request(
			{
				"weapon": Resolver.Weapon.new("Assault Rifle", "assault_rifle", 5, 1, 25, 4),
				"mode": "autofire",
				"attack_base": 17,
				"ammo": 25,
			}
		),
		_tables(17),
		_rng([5, 3, 4]),
	)
	h.equal(burst.raw_damage, 28, "raw damage")
	h.equal(burst.events[0]["amount"], 10, "ammo spent")

	h.it("jams a poor weapon when the attack check rolls a one")
	var jam := Resolver.resolve_attack(
		_request({"weapon": Resolver.Weapon.new("Junker", "pistol", 2, 1, 1, -1, "poor")}),
		_tables(30),
		_rng([1, 4]),
	)
	h.contains(_kinds(jam), "weapon_jammed", "events")

	h.it("uses the limb armor value and applies no multiplier on a called shot")
	var limb := Resolver.resolve_attack(
		_request(
			{
				"target": _target({"armor": {"body": 7, "head": 7, "left_arm": 2}}),
				"location": "left_arm",
				"mode": "aimed",
				"attack_base": 20,
			}
		),
		_tables(),
		_rng([8, 4, 4, 4]),
	)
	h.equal(limb.armor_sp, 2, "limb SP")
	h.equal(limb.armor_damage, 10, "armor damage")
