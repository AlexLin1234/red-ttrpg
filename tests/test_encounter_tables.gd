extends RefCounted

## Squads and street encounters.
##
## The point of these tables is that a GM does not have to invent an ambush at
## the table, so the cases here are about what comes out being immediately
## usable: a sheet the encounter engine accepts, and a squad of them.

const Harness := preload("res://tests/harness.gd")


static func _rng(values: Array[int]) -> Dice.FixedRandom:
	return Dice.FixedRandom.new(values)


static func run(h: Harness) -> void:
	h.describe("encounter tables")

	_mooks(h)
	_squads(h)
	_street(h)


static func _mooks(h: Harness) -> void:
	h.it("rolls a mook inside its archetype's bands")
	var profile := EncounterTables.squad("corp_security")
	# Ten stats, then hp, sp, skill, then the two name picks.
	var rolls: Array[int] = [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 35, 13, 5, 0, 0]
	var mook := EncounterTables.roll_mook(profile, _rng(rolls))
	h.equal(mook["kind"], "mook", "kind")
	h.equal(mook["side"], "hostile", "side")
	h.equal(mook["max_hp"], 35, "hp")
	h.equal(mook["hp"], 35, "starts undamaged")
	h.equal((mook["armor"] as Dictionary)["body"]["sp"], 13, "sp")
	h.equal(mook["name"], "Wire Vasquez", "name")
	h.contains(mook["tags"], "MOOK", "tags")

	h.it("gives it a weapon the encounter engine can resolve")
	var weapons: Array = mook["weapons"]
	h.equal(weapons.size(), 1, "one weapon")
	var weapon: Dictionary = weapons[0]
	h.equal(weapon["name"], "Assault Rifle", "name")
	h.check(int(weapon["damage_dice"]) > 0, "damage dice")
	h.check(int(weapon["ammo"]) > 0, "loaded")
	h.equal(weapon["ammo"], weapon["magazine"], "and full")

	h.it("stands a rolled mook up in a real encounter")
	var tables := Tables.new(TablesDefault.document())
	var session := Encounter.new(tables, {"goon": CampaignFixtures.actor_input(mook)})
	var actor := session.actor("goon")
	h.equal(int(actor["max_hp"]), 35, "hp survived the trip")
	h.equal(String(actor["wound_state"]), "unhurt", "and it is unhurt")

	h.it("rolls an unarmed archetype without a weapon")
	var bystander := EncounterTables.roll_mook(
		EncounterTables.squad("bystanders"), _rng([3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 18, 1, 1, 2, 2])
	)
	h.equal((bystander["weapons"] as Array).size(), 0, "no weapon")
	h.equal(bystander["side"], "neutral", "and not hostile")


static func _squads(h: Harness) -> void:
	h.it("rolls the number asked for")
	# Fifteen values per mook: ten stats, hp, sp, skill, and the two name picks.
	var rolls: Array[int] = []
	for index in 3:
		rolls.append_array([4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 25, 5, 3, 1, 1])
	var squad := EncounterTables.roll_squad("boostergang", 3, _rng(rolls))
	h.equal(squad.size(), 3, "size")

	h.it("gives every member its own id")
	var ids := PackedStringArray()
	for member in squad:
		h.not_contains(ids, String(member["id"]), "ids are unique")
		ids.append(String(member["id"]))

	h.it("rolls the archetype's own size when asked for none")
	var sized: Array[int] = [4]
	for index in 4:
		sized.append_array([4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 25, 5, 3, 1, 1])
	# The first value is the size roll: four, inside the boostergang's 3..6.
	var rolled := EncounterTables.roll_squad("boostergang", 0, _rng(sized))
	h.equal(rolled.size(), 4, "size")

	h.it("keeps an unknown archetype from crashing the board")
	var fallback := EncounterTables.squad("no-such-gang")
	h.equal(fallback["key"], "boostergang", "falls back to the first archetype")


static func _street(h: Harness) -> void:
	h.it("rolls who, what they want, and what is wrong with it")
	var rolled := EncounterTables.roll_street(_rng([0, 0, 0]))
	h.equal(rolled["who"], EncounterTables.STREET_WHO[0], "who")
	h.equal(rolled["wants"], EncounterTables.STREET_WANTS[0], "wants")
	h.equal(rolled["complication"], EncounterTables.STREET_COMPLICATIONS[0], "complication")
	h.contains(String(rolled["text"]), String(rolled["who"]), "the sentence carries all three")
	h.contains(String(rolled["text"]), String(rolled["complication"]), "including the last")

	h.it("reaches the end of every table")
	var last := EncounterTables.roll_street(
		_rng(
			[
				EncounterTables.STREET_WHO.size() - 1,
				EncounterTables.STREET_WANTS.size() - 1,
				EncounterTables.STREET_COMPLICATIONS.size() - 1,
			]
		)
	)
	h.equal(
		last["complication"],
		EncounterTables.STREET_COMPLICATIONS[EncounterTables.STREET_COMPLICATIONS.size() - 1],
		"the last row is reachable"
	)
