class_name Downtime
extends RefCounted

## What a crew does between jobs.
##
## The Hustle in [Economy] was the only downtime Redline had, and it is only one
## of the things a week off is for. These are the rest: staring someone down,
## the reputation that makes that work, healing up, getting the Humanity back,
## building something, and leaning on a Fixer for stock.
##
## Follows [Economy]'s convention rather than [Resolver]'s: these mutate the
## character they are handed and return a report. Downtime is not undoable at the
## action level — the campaign's month undo is the granularity that matters — so
## there is nothing for an event list to buy here.
##
## The constants are working values with no page citation, as [Mortality]'s are.

const RULES := {
	## A week of downtime, in days, matching the Hustle's block.
	"week_days": Economy.HUSTLE_DAYS,
	"reputation_min": 0,
	"reputation_max": 10,
	## HP back per day of rest, per point of BODY.
	"rest_hp_per_body": 1,
	## A successful Medtech check doubles what a day of rest is worth.
	"medical_dv": 15,
	"medical_multiplier": 2,
	"medical_cost_per_day": 50,
	## Therapy restores Humanity slowly and is never free.
	"therapy_humanity_per_week": 3,
	"therapy_cost_per_week": 500,
	"therapy_dv": 13,
	## Fabrication: DV scales with what is being built.
	"fabrication_dv_per_500eb": 1,
	"fabrication_base_dv": 13,
	"fabrication_days": 7,
	## What a Fixer's contacts turn up in a week.
	"sourcing_dv": 15,
}

## Everything on offer, for the screen to draw without knowing the rules.
const ACTIONS: Array[Dictionary] = [
	{
		"key": "facedown",
		"label": "Facedown",
		"summary": "Stare someone down. COOL and Reputation against theirs.",
		"days": 0,
	},
	{
		"key": "recover",
		"label": "Recover",
		"summary": "Rest up. A Medtech makes the days count double.",
		"days": 1,
	},
	{
		"key": "therapy",
		"label": "Therapy",
		"summary": "Buy some Humanity back, a week and 500eb at a time.",
		"days": 7,
	},
	{
		"key": "fabricate",
		"label": "Fabricate",
		"summary": "Build something. TECH and a workshop week.",
		"days": 7,
	},
	{
		"key": "source",
		"label": "Source gear",
		"summary": "Lean on a Fixer for what the street has this week.",
		"days": 7,
	},
]


static func action(key: String) -> Dictionary:
	for entry in ACTIONS:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return {}


static func reputation(character: Dictionary) -> int:
	return clampi(
		int(character.get("reputation", 0)),
		int(RULES["reputation_min"]),
		int(RULES["reputation_max"]),
	)


## Move a character's Reputation, bounded, and report what actually moved.
static func adjust_reputation(character: Dictionary, delta: int, reason := "") -> Dictionary:
	var before := reputation(character)
	var after := clampi(
		before + delta, int(RULES["reputation_min"]), int(RULES["reputation_max"])
	)
	character["reputation"] = after
	return {
		"ok": true,
		"before": before,
		"after": after,
		"delta": after - before,
		"work": (
			"Reputation %d → %d%s" % [before, after, ": " + reason if reason != "" else ""]
		),
		"days": 0,
	}


static func _stat(character: Dictionary, key: String) -> int:
	return int((character.get("stats", {}) as Dictionary).get(key, 0))


static func _check_line(label: String, base: int, check: Dictionary) -> String:
	var pieces := PackedStringArray()
	for value in check["rolls"]:
		pieces.append(str(value))
	return "%s: %d + d10 [%s] = %d" % [label, base, ", ".join(pieces), base + int(check["total"])]


## A Facedown: COOL and Reputation, opposed, and the loser backs off.
##
## Nothing is spent and no time passes. It is here rather than in the Forge
## because it is a scene between two people, not a number on a sheet.
static func facedown(
	challenger: Dictionary, opponent: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var challenger_base := _stat(challenger, "COOL") + reputation(challenger)
	var opponent_base := _stat(opponent, "COOL") + reputation(opponent)
	var challenger_check := Dice.roll_check(rng)
	var opponent_check := Dice.roll_check(rng)
	var challenger_total := challenger_base + int(challenger_check["total"])
	var opponent_total := opponent_base + int(opponent_check["total"])

	# A tie goes to the one who did not start it, the same way a tied defence
	# goes to the defender everywhere else in the rules.
	var challenger_wins := challenger_total > opponent_total
	var winner: Dictionary = challenger if challenger_wins else opponent
	var loser: Dictionary = opponent if challenger_wins else challenger

	return {
		"ok": true,
		"winner_id": String(winner.get("id", "")),
		"loser_id": String(loser.get("id", "")),
		"challenger_total": challenger_total,
		"opponent_total": opponent_total,
		"margin": absi(challenger_total - opponent_total),
		"lines":
		PackedStringArray(
			[
				_check_line(
					"%s (COOL %d + Rep %d)"
					% [
						String(challenger.get("name", "Challenger")),
						_stat(challenger, "COOL"),
						reputation(challenger),
					],
					challenger_base,
					challenger_check
				),
				_check_line(
					"%s (COOL %d + Rep %d)"
					% [
						String(opponent.get("name", "Opponent")),
						_stat(opponent, "COOL"),
						reputation(opponent),
					],
					opponent_base,
					opponent_check
				),
				(
					"%s backs down."
					% String(loser.get("name", "The loser"))
				),
			]
		),
		"work": (
			"%s faced down %s"
			% [String(winner.get("name", "One")), String(loser.get("name", "the other"))]
		),
		"days": 0,
	}


## Rest, optionally with someone competent looking after them.
##
## [param medic] may be empty, in which case the character simply sleeps it off.
## A Mortally Wounded character has to be stabilised before rest is worth
## anything, which is [Mortality]'s job and not this one's.
static func recover(
	character: Dictionary, days: int, medic: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	assert(days > 0, "resting takes at least a day")
	if int(character.get("hp", 0)) <= 0:
		return {
			"ok": false,
			"error": "%s is Mortally Wounded. Stabilise them first."
			% String(character.get("name", "The patient")),
		}

	var body := maxi(1, _stat(character, "BODY"))
	var per_day := body * int(RULES["rest_hp_per_body"])
	var lines := PackedStringArray(
		["Rest: BODY %d × %d days = %d HP" % [body, days, per_day * days]]
	)
	var cost := 0
	var assisted := false

	if not medic.is_empty():
		var base := _medical_base(medic)
		var check := Dice.roll_check(rng)
		var total := base + int(check["total"])
		var dv := int(RULES["medical_dv"])
		lines.append(
			_check_line("%s (First Aid)" % String(medic.get("name", "Medic")), base, check)
			+ " vs DV %d" % dv
		)
		assisted = total >= dv
		cost = int(RULES["medical_cost_per_day"]) * days
		if assisted:
			per_day *= int(RULES["medical_multiplier"])
			lines.append("Treated: the days count double.")
		else:
			lines.append("The treatment did not take. Rest alone, then.")

	var before := int(character.get("hp", 0))
	var max_hp := maxi(1, int(character.get("max_hp", 1)))
	var healed := mini(per_day * days, max_hp - before)
	character["hp"] = before + healed
	character["wound_state"] = Mortality.state_for(before + healed, max_hp)
	if cost > 0:
		character["cash"] = maxi(0, int(character.get("cash", 0)) - cost)
	lines.append("%d → %d of %d." % [before, before + healed, max_hp])

	return {
		"ok": true,
		"healed": healed,
		"assisted": assisted,
		"cost": cost,
		"lines": lines,
		"work": "%s rested %d days and recovered %d HP"
		% [String(character.get("name", "A character")), days, healed],
		"days": days,
	}


static func _medical_base(medic: Dictionary) -> int:
	var stats: Dictionary = medic.get("stats", {})
	var best := int(stats.get("TECH", 0))
	for entry in medic.get("skills", []):
		var row: Dictionary = entry
		if String(row["name"]) in ["First Aid", "Paramedic", "Surgery"]:
			best = maxi(best, CampaignSchema.skill_total(stats, row))
	return best


## A week of therapy: expensive, slow, and the only way Humanity comes back.
static func therapy(character: Dictionary, weeks: int, rng: Dice.RandomSource) -> Dictionary:
	assert(weeks > 0, "therapy takes at least a week")
	var cost := int(RULES["therapy_cost_per_week"]) * weeks
	var cash := int(character.get("cash", 0))
	if cash < cost:
		return {
			"ok": false,
			"error": "%s cannot cover %deb of therapy." % [
				String(character.get("name", "The patient")), cost
			],
		}

	var max_humanity := maxi(1, int(character.get("max_humanity", 1)))
	var before := int(character.get("humanity", 0))
	if before >= max_humanity:
		return {"ok": false, "error": "There is nothing to recover."}

	var lines := PackedStringArray()
	var restored := 0
	for week in weeks:
		var base := int((character.get("stats", {}) as Dictionary).get("WILL", 0))
		var check := Dice.roll_check(rng)
		var total := base + int(check["total"])
		var dv := int(RULES["therapy_dv"])
		var gained: int = (
			int(RULES["therapy_humanity_per_week"]) if total >= dv else 0
		)
		lines.append(
			_check_line("Week %d (WILL)" % (week + 1), base, check)
			+ " vs DV %d — %s" % [dv, "+%d Humanity" % gained if gained > 0 else "no progress"]
		)
		restored += gained

	restored = mini(restored, max_humanity - before)
	character["humanity"] = before + restored
	character["cash"] = cash - cost
	lines.append("Humanity %d → %d of %d, for %deb." % [before, before + restored, max_humanity, cost])

	return {
		"ok": true,
		"restored": restored,
		"cost": cost,
		"lines": lines,
		"work": "%s spent %d weeks in therapy and recovered %d Humanity"
		% [String(character.get("name", "A character")), weeks, restored],
		"days": int(RULES["week_days"]) * weeks,
	}


## Build something in a workshop week.
##
## The DV scales with what is being built, which is the only honest way to make
## a Tech's week mean something different from a Solo's.
static func fabricate(
	character: Dictionary, item: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var price := maxi(0, int(item.get("price", 0)))
	var materials: int = price / 2
	var cash := int(character.get("cash", 0))
	if cash < materials:
		return {
			"ok": false,
			"error": "%s cannot cover %deb of materials." % [
				String(character.get("name", "The maker")), materials
			],
		}

	var stats: Dictionary = character.get("stats", {})
	var base := int(stats.get("TECH", 0))
	for entry in character.get("skills", []):
		var row: Dictionary = entry
		if String(row["name"]) in ["Basic Tech", "Weaponstech", "Cybertech", "Electronics/Security Tech"]:
			base = maxi(base, CampaignSchema.skill_total(stats, row))

	var dv: int = (
		int(RULES["fabrication_base_dv"])
		+ (price / 500) * int(RULES["fabrication_dv_per_500eb"])
	)
	var check := Dice.roll_check(rng)
	var total := base + int(check["total"])
	var success := total >= dv
	var lines := PackedStringArray(
		[
			_check_line("Fabrication", base, check) + " vs DV %d" % dv,
			"Materials: %deb." % materials,
		]
	)

	character["cash"] = cash - materials
	if success:
		var gear: Array = character.get("gear", [])
		var built := (item as Dictionary).duplicate(true)
		built["detail"] = "fabricated"
		gear.append(built)
		character["gear"] = gear
		lines.append("%s is finished." % String(item.get("name", "The item")))
	else:
		lines.append("The build failed. The materials are gone.")

	return {
		"ok": true,
		"success": success,
		"cost": materials,
		"dv": dv,
		"lines": lines,
		"work": (
			"%s fabricated %s" % [String(character.get("name", "A maker")), String(item.get("name", "an item"))]
			if success
			else "%s failed to fabricate %s"
			% [String(character.get("name", "A maker")), String(item.get("name", "an item"))]
		),
		"days": int(RULES["fabrication_days"]),
	}


## What a Fixer's contacts can turn up this week.
##
## Returns how many pieces they can source and what they can shave off the
## price; the Night Market is where the stock itself is rolled.
static func source_gear(character: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
	if String(character.get("role_key", "")) != "fixer" or rank < 1:
		return {"ok": false, "error": "Sourcing gear takes a Fixer with an Operator Rank."}

	var stats: Dictionary = character.get("stats", {})
	var base := rank + int(stats.get("COOL", 0))
	var check := Dice.roll_check(rng)
	var total := base + int(check["total"])
	var dv := int(RULES["sourcing_dv"])
	var margin := total - dv
	var pieces: int = maxi(0, 1 + margin / 4) if margin >= 0 else 0
	var discount: int = mini(30, maxi(0, margin) * 2)

	var lines := PackedStringArray(
		[
			_check_line("Operator %d + COOL %d" % [rank, int(stats.get("COOL", 0))], base, check)
			+ " vs DV %d" % dv
		]
	)
	if pieces > 0:
		lines.append("%d pieces available this week, at %d%% off." % [pieces, discount])
	else:
		lines.append("Nothing worth having came up.")

	return {
		"ok": true,
		"pieces": pieces,
		"discount": discount,
		"lines": lines,
		"work": (
			"%s sourced %d pieces at %d%% off"
			% [String(character.get("name", "A Fixer")), pieces, discount]
		),
		"days": int(RULES["week_days"]),
	}
