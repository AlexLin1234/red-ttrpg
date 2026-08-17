extends RefCounted

## Adapted from the original Python `tests/test_tables.py`.
##
## That suite skipped unless the operator had promoted a book-derived
## `tables.json`. Redline ships homebrew placeholders instead, so these always
## run: they check the adapter and that the shipped defaults hold together well
## enough to resolve a fight.

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("tables")
	var tables := TablesDefault.tables()

	h.it("reads a DV out of the band containing the distance")
	h.equal(tables.ranged_dv("pistol", 5.0), 11, "pistol at 5 m")
	h.equal(tables.ranged_dv("pistol", 20.0), 15, "pistol at 20 m")
	h.equal(tables.ranged_dv("sniper_rifle", 75.0), 15, "sniper at 75 m")

	h.it("reads autofire bands and caps the multiplier by rating")
	h.equal(tables.autofire_dv("smg", 10.0), 17, "smg autofire at 10 m")
	h.equal(tables.autofire_dv("assault_rifle", 20.0), 19, "rifle autofire at 20 m")
	h.equal(tables.autofire_multiplier(7, 4), 4, "capped by rating")
	h.equal(tables.autofire_multiplier(2, 4), 2, "capped by margin")

	h.it("is labelled as homebrew rather than book data")
	h.contains(String(tables.data["source"]), "homebrew", "source note")

	h.it("gives every weapon positive damage and rof")
	var bad_weapons := 0
	for name in tables.weapon_names():
		var profile := tables.weapon(String(name))
		if int(profile["damage_dice"]) <= 0 or int(profile["rof"]) <= 0:
			bad_weapons += 1
	h.equal(bad_weapons, 0, "weapons with impossible stats")

	h.it("covers every critical injury roll for both tables")
	var missing := 0
	for location in ["body", "head"]:
		for roll in range(2, 13):
			if String(tables.critical_injury(location, roll)["name"]) == "":
				missing += 1
	h.equal(missing, 0, "missing injury rows")

	h.it("exposes the cover materials the builder offers")
	h.equal(tables.cover("Concrete")["sp"], 15, "concrete SP")
	h.equal(tables.cover("Concrete")["hp"], 30, "concrete HP")
	h.equal(tables.cover("Vehicle Hulk")["hp"], 50, "vehicle hulk HP")
	h.equal(tables.aimed_shot("head")["modifier"], -8, "aimed shot modifier")

	h.it("passes its own validator")
	h.equal(Tables.validate(tables.data), PackedStringArray(), "problems in the shipped defaults")

	h.it("rejects a non-object and reports missing sections")
	h.equal(Tables.validate("nope"), PackedStringArray(["file is not a JSON object"]), "non-object")
	var empty := Tables.validate({})
	h.contains(empty, 'missing "ranged_dv" section', "missing ranged_dv")
	h.contains(empty, 'missing "critical_injuries" section', "missing injuries")

	h.it("reports a gap in a critical injury table")
	var gapped := TablesDefault.document()
	(gapped["critical_injuries"]["body"] as Dictionary).erase("7")
	h.contains(Tables.validate(gapped), "body critical injuries missing roll 7", "gap")

	h.it("reports a weapon with impossible stats")
	var broken := TablesDefault.document()
	broken["weapons"]["Heavy Sidearm"]["damage_dice"] = 0
	h.contains(
		Tables.validate(broken), "Heavy Sidearm: damage_dice must be positive", "bad weapon"
	)

	h.it("resolves an attack end to end against the shipped tables")
	var result := Resolver.resolve_attack(
		Resolver.AttackRequest.new(
			"solo",
			Resolver.TargetState.new("goon", 30, 40, {"body": 7}),
			Resolver.Weapon.new("Heavy Sidearm", "pistol", 3, 1, 8),
			9,
			5.0,
			8
		),
		tables,
		Dice.FixedRandom.new([5, 4, 4, 4]),
	)
	h.equal(result.hit, true, "hit")
	h.equal(result.defense, 11, "defense")
	h.equal(result.hp_damage, 5, "hp damage")
