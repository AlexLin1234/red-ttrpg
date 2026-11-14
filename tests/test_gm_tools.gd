extends RefCounted

## The GM's own tools: the party board, group checks, clocks and generators.
##
## The rules these cases protect: a group check rolls for every player character
## and nobody else, a clock cannot run past either end and fills exactly once,
## and found loot never exceeds the budget it was rolled against.

const Harness := preload("res://tests/harness.gd")


static func _party() -> Array:
	return [
		{
			"id": "a", "name": "Ana", "role": "Solo", "kind": "pc", "hp": 20, "max_hp": 40,
			"stats": {"INT": 6, "LUCK": 5}, "luck_available": 2, "cash": 300,
			"skills": [{"name": "Perception", "stat": "INT", "level": 4}],
			"armor": {"head": {"sp": 7}, "body": {"sp": 11}},
		},
		{
			"id": "b", "name": "Bo", "role": "Tech", "kind": "pc", "hp": 35, "max_hp": 35,
			"stats": {"INT": 5, "LUCK": 3}, "skills": [],
		},
		{"id": "c", "name": "Cy", "kind": "npc", "hp": 10, "max_hp": 10, "stats": {"INT": 9}},
	]


static func _catalog() -> Array:
	var document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://catalog/items.json")
	)
	return document["items"]


static func run(h: Harness) -> void:
	h.describe("GM tools")

	h.it("lists the player characters, and only them")
	var rows := GMTools.party_overview(_party())
	h.equal(rows.size(), 2, "two PCs")
	h.equal(rows[0]["name"], "Ana", "in roster order")
	h.equal(rows[0]["body_sp"], 11, "body armor read off the sheet")
	h.equal(rows[0]["luck"], 2, "Luck left")
	h.equal(rows[0]["luck_pool"], 5, "out of the stat")
	h.not_equal(rows[0]["wound_state"], Mortality.UNHURT, "half HP is not unhurt")
	h.equal(rows[1]["wound_state"], Mortality.UNHURT, "full HP is")
	h.equal(rows[1]["head_sp"], 0, "a sheet with no armor reads zero")

	h.it("rolls one skill for every PC, untrained on the bare stat")
	var check := GMTools.group_check(_party(), "Perception", 1, 15, Dice.FixedRandom.new([7, 3]))
	h.equal(check["ok"], true, "rolled")
	h.equal((check["results"] as Array).size(), 2, "the NPC does not roll")
	h.equal(check["results"][0]["name"], "Ana", "best first")
	h.equal(check["results"][0]["total"], 18, "INT 6 + Perception 4 + 1 + 7")
	h.equal(check["results"][0]["success"], true, "beats DV 15")
	h.equal(check["results"][1]["total"], 9, "INT 5 + nothing + 1 + 3")
	h.equal(check["results"][1]["trained"], false, "flagged untrained")
	h.equal(Array(check["passed"]), ["Ana"], "who made it")
	h.contains(String(check["summary"]), "Ana made it", "summary names them")

	h.it("ranks without judging when there is no DV")
	var open := GMTools.group_check(_party(), "Perception", 0, 0, Dice.FixedRandom.new([2, 9]))
	h.equal(open["results"][0]["success"], null, "no verdict")
	h.equal(open["results"][0]["name"], "Bo", "5 + 9 beats 10 + 2")

	h.it("explodes and fumbles like any other check")
	var wild := GMTools.group_check(_party(), "Perception", 0, 0, Dice.FixedRandom.new([10, 4, 1, 6]))
	h.equal(wild["results"][0]["total"], 24, "10 + 10 + 4")
	h.equal(wild["results"][0]["critical"], true, "flagged")
	h.equal(wild["results"][1]["total"], 0, "5 + 1 − 6")
	h.equal(wild["results"][1]["fumble"], true, "flagged")

	h.it("refuses a skill that does not exist, and an empty table")
	h.equal(GMTools.group_check(_party(), "Juggling", 0, 0, Dice.FixedRandom.new([]))["ok"], false, "no such skill")
	h.equal(GMTools.group_check([], "Perception", 0, 0, Dice.FixedRandom.new([]))["ok"], false, "nobody to roll")
	h.contains(GMTools.skill_names(), "Perception", "the picker offers Perception")

	h.it("starts, ticks and bounds a clock")
	var campaign := {}
	var clock := GMTools.add_clock(campaign, "  Response team ", 4)
	h.equal(clock["name"], "Response team", "trimmed")
	h.equal(GMTools.add_clock(campaign, "", 99)["segments"], GMTools.CLOCK_MAX_SEGMENTS, "segments capped")
	h.not_equal(campaign["clocks"][0]["id"], campaign["clocks"][1]["id"], "ids differ")
	var id := String(clock["id"])
	h.equal(GMTools.tick_clock(campaign, id, 3)["just_filled"], false, "3 of 4 is not full")
	var last := GMTools.tick_clock(campaign, id, 5)
	h.equal(last["just_filled"], true, "the tick that fills it says so")
	h.equal(last["moved"], 1, "and only moves what was left")
	h.equal(GMTools.tick_clock(campaign, id, 1)["just_filled"], false, "a full clock does not fill twice")
	GMTools.tick_clock(campaign, id, -99)
	h.equal(clock["filled"], 0, "cannot go below empty")
	h.equal(GMTools.tick_clock(campaign, "nope", 1)["ok"], false, "a missing clock is refused")

	h.it("removes a clock without reusing its id")
	h.equal(GMTools.remove_clock(campaign, id), true, "removed")
	h.equal(GMTools.remove_clock(campaign, id), false, "only once")
	h.not_equal(GMTools.add_clock(campaign, "Next", 4)["id"], id, "a new clock gets a new id")

	h.it("repairs clocks loaded from a hand-edited save")
	var damaged := {"clocks": [{"name": "Odd", "segments": 50, "filled": 70}, "junk"]}
	var repaired := GMTools.ensure_clocks(damaged)
	h.equal(repaired.size(), 1, "the junk entry is dropped")
	h.equal(repaired[0]["filled"], GMTools.CLOCK_MAX_SEGMENTS, "filled clamped to segments")

	h.it("rolls a whole person, and a sheet for them")
	var rng := Dice.SeededRandom.new(7)
	var npc := GMTools.roll_npc(rng)
	for key in ["name", "job", "look", "wants", "quirk", "secret", "text"]:
		h.check(String(npc.get(key, "")) != "", "%s is filled in" % key)
	var sheet := GMTools.npc_sheet(npc, rng)
	h.equal(sheet["name"], npc["name"], "the sheet carries the name")
	h.equal(sheet["kind"], "npc", "an NPC, not a mook")
	h.equal(sheet["side"], "neutral", "not hostile until the GM says so")
	h.check(int(sheet["max_hp"]) > 0, "with HP to lose")
	h.contains(String(sheet["notes"]), String(npc["secret"]), "the secret is kept on the sheet")

	h.it("never rolls loot worth more than the budget")
	var catalog := _catalog()
	for seed_value in 25:
		var loot := GMTools.roll_loot(catalog, 500, Dice.SeededRandom.new(seed_value))
		h.check(int(loot["worth"]) <= 500, "seed %d stays inside 500" % seed_value)
		h.check((loot["items"] as Array).size() <= GMTools.LOOT_MAX_ITEMS, "seed %d carries at most four things" % seed_value)
	h.equal(GMTools.roll_loot(catalog, 0, Dice.SeededRandom.new(1))["ok"], false, "no budget is refused")

	h.it("puts loot on a sheet with its profiles")
	var finder := {"name": "Ana", "cash": 10, "gear": []}
	var pistol: Dictionary = GearMarket.item(catalog, "heavy_sidearm")
	GMTools.give_loot(finder, {"cash": 40, "items": [pistol]})
	h.equal(finder["cash"], 50, "cash added")
	h.equal(finder["gear"][0]["name"], "Heavy Sidearm", "item carried")
	h.equal(finder["weapons"][0]["damage_dice"], 3, "and usable")
	h.equal(GMTools.give_loot({}, {"cash": 5})["ok"], false, "nobody to give it to is refused")
