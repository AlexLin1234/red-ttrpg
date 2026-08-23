extends RefCounted

## Downtime past the Hustle.
##
## What a week off is actually for: staring someone down, healing up, buying
## Humanity back, building something, and leaning on a Fixer.

const Harness := preload("res://tests/harness.gd")


static func _character(overrides := {}) -> Dictionary:
	var character := {
		"id": "spike",
		"name": "Spike Adebayo",
		"kind": "pc",
		"role": "Solo",
		"role_key": "solo",
		"role_ability": {"rank": 6},
		"stats": {"BODY": 8, "COOL": 6, "WILL": 7, "TECH": 4, "REF": 7, "INT": 6},
		"skills": [],
		"gear": [],
		"cash": 2000,
		"hp": 20,
		"max_hp": 45,
		"humanity": 30,
		"max_humanity": 50,
		"reputation": 4,
	}
	character.merge(overrides, true)
	return character


static func _medic() -> Dictionary:
	return _character(
		{
			"id": "doc",
			"name": "Doc Tallow",
			"role": "Medtech",
			"role_key": "medtech",
			"stats": {"BODY": 5, "COOL": 4, "WILL": 6, "TECH": 8},
			"skills": [{"name": "First Aid", "stat": "TECH", "level": 6}],
		}
	)


static func run(h: Harness) -> void:
	h.describe("downtime")

	_reputation(h)
	_facedowns(h)
	_recovery(h)
	_therapy(h)
	_fabrication(h)
	_sourcing(h)


static func _reputation(h: Harness) -> void:
	h.it("moves reputation within its bounds")
	var character := _character()
	var up := Downtime.adjust_reputation(character, 3, "walked out of the Parkade")
	h.equal(up["after"], 7, "raised")
	h.equal(character["reputation"], 7, "written to the sheet")
	var over := Downtime.adjust_reputation(character, 9, "")
	h.equal(over["after"], 10, "capped at ten")
	h.equal(over["delta"], 3, "and reports only what actually moved")
	var under := Downtime.adjust_reputation(character, -20, "")
	h.equal(under["after"], 0, "floored at zero")

	h.it("gives every sheet a reputation whether or not the GM set one")
	var blank := {"name": "Nobody"}
	CharacterRules.ensure_character(blank)
	h.equal(blank["reputation"], 0, "default")


static func _facedowns(h: Harness) -> void:
	h.it("opposes COOL and reputation")
	# Challenger COOL 6 + Rep 4 + a d10 of 7 = 17; opponent COOL 6 + Rep 0 + 3 = 9.
	var challenger := _character()
	var opponent := _character({"id": "goon", "name": "Booster", "reputation": 0})
	var result := Downtime.facedown(challenger, opponent, Dice.FixedRandom.new([7, 3]))
	h.equal(result["winner_id"], "spike", "winner")
	h.equal(result["loser_id"], "goon", "loser")
	h.equal(result["challenger_total"], 17, "challenger total")
	h.equal(result["opponent_total"], 9, "opponent total")
	h.equal(result["margin"], 8, "margin")

	h.it("gives a tie to whoever did not start it")
	var tied := Downtime.facedown(
		_character(), _character({"id": "goon", "name": "Booster"}), Dice.FixedRandom.new([5, 5])
	)
	h.equal(tied["winner_id"], "goon", "the challenger has to beat them, not match them")

	h.it("costs no time")
	h.equal(int(tied["days"]), 0, "days")


static func _recovery(h: Harness) -> void:
	h.it("heals BODY per day of rest")
	var character := _character()
	var rested := Downtime.recover(character, 3, {}, Dice.FixedRandom.new([]))
	h.equal(rested["healed"], 24, "BODY 8 for three days")
	h.equal(character["hp"], 44, "hp")
	h.equal(character["wound_state"], "lightly_wounded", "wound state follows the HP")

	h.it("never heals past the maximum")
	var topped := _character({"hp": 44})
	Downtime.recover(topped, 5, {}, Dice.FixedRandom.new([]))
	h.equal(topped["hp"], 45, "hp")
	h.equal(topped["wound_state"], "unhurt", "wound state")

	h.it("doubles the days when a medic makes the DV")
	var patient := _character()
	# First Aid 8 + 6 = 14 base, plus a d10 of 4 = 18, over the DV 15.
	var treated := Downtime.recover(patient, 2, _medic(), Dice.FixedRandom.new([4]))
	h.equal(treated["assisted"], true, "treated")
	h.equal(treated["healed"], 25, "BODY 8, doubled, for two days, capped by max HP")
	h.equal(treated["cost"], 100, "and billed for it")
	h.equal(patient["cash"], 1900, "cash")

	h.it("still charges for treatment that did not take")
	var unlucky := _character()
	var failed := Downtime.recover(unlucky, 1, _medic(), Dice.FixedRandom.new([1, 9]))
	h.equal(failed["assisted"], false, "not treated")
	h.equal(failed["healed"], 8, "rest alone")
	h.equal(unlucky["cash"], 1950, "the medic still charged")

	h.it("refuses to rest a character who is still dying")
	var dying := _character({"hp": 0})
	var refused := Downtime.recover(dying, 3, {}, Dice.FixedRandom.new([]))
	h.equal(refused["ok"], false, "refused")
	h.contains(String(refused["error"]), "Stabilise", "and says why")


static func _therapy(h: Harness) -> void:
	h.it("buys Humanity back a week at a time")
	var character := _character()
	# WILL 7 + a d10 of 8 = 15, over the DV 13; then 7 + 2 = 9, under it.
	var result := Downtime.therapy(character, 2, Dice.FixedRandom.new([8, 2]))
	h.equal(result["restored"], 3, "one week of the two paid off")
	h.equal(character["humanity"], 33, "humanity")
	h.equal(result["cost"], 1000, "two weeks at 500eb")
	h.equal(character["cash"], 1000, "cash")
	h.equal(int(result["days"]), 14, "days")

	h.it("refuses what the character cannot pay for")
	var broke := _character({"cash": 100})
	var refused := Downtime.therapy(broke, 1, Dice.FixedRandom.new([]))
	h.equal(refused["ok"], false, "refused")
	h.equal(broke["humanity"], 30, "and nothing happened")

	h.it("refuses when there is nothing to recover")
	var whole := _character({"humanity": 50})
	h.equal(Downtime.therapy(whole, 1, Dice.FixedRandom.new([]))["ok"], false, "refused")


static func _fabrication(h: Harness) -> void:
	var item := {"name": "Heavy Sidearm", "kind": "weapon", "price": 500}

	h.it("builds the item when the check lands")
	var maker := _character({"skills": [{"name": "Basic Tech", "stat": "TECH", "level": 8}]})
	# Basic Tech 4 + 8 = 12, plus a d10 of 4 = 16, against a DV of 13 + 1.
	var built := Downtime.fabricate(maker, item, Dice.FixedRandom.new([4]))
	h.equal(built["success"], true, "built")
	h.equal(built["dv"], 14, "the DV scales with what is being built")
	h.equal(built["cost"], 250, "materials are half the price")
	h.equal(maker["cash"], 1750, "cash")
	h.equal((maker["gear"] as Array).size(), 1, "the item is on the sheet")

	h.it("keeps the materials when the build fails")
	var clumsy := _character()
	var failed := Downtime.fabricate(clumsy, item, Dice.FixedRandom.new([1, 9]))
	h.equal(failed["success"], false, "failed")
	h.equal(clumsy["cash"], 1750, "the materials are gone either way")
	h.equal((clumsy["gear"] as Array).size(), 0, "and there is nothing to show for it")

	h.it("refuses what the maker cannot buy materials for")
	var broke := _character({"cash": 10})
	h.equal(Downtime.fabricate(broke, item, Dice.FixedRandom.new([]))["ok"], false, "refused")


static func _sourcing(h: Harness) -> void:
	h.it("turns a Fixer's rank into stock")
	var fixer := _character(
		{"role": "Fixer", "role_key": "fixer", "role_ability": {"rank": 7}}
	)
	# Operator 7 + COOL 6 = 13, plus a d10 of 6 = 19, six over the DV 15.
	var sourced := Downtime.source_gear(fixer, Dice.FixedRandom.new([6]))
	h.equal(sourced["pieces"], 2, "pieces")
	h.equal(sourced["discount"], 8, "discount")
	h.equal(int(sourced["days"]), 7, "days")

	h.it("turns up nothing on a bad week")
	var unlucky := _character(
		{"role": "Fixer", "role_key": "fixer", "role_ability": {"rank": 1}}
	)
	var nothing := Downtime.source_gear(unlucky, Dice.FixedRandom.new([1, 9]))
	h.equal(nothing["pieces"], 0, "pieces")

	h.it("refuses anyone who is not a Fixer")
	var solo := _character()
	h.equal(Downtime.source_gear(solo, Dice.FixedRandom.new([]))["ok"], false, "refused")
