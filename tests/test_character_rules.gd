extends RefCounted

## Role selection, Role Ability state, Skill choice, and sheet checks.

const Harness := preload("res://tests/harness.gd")


static func _character() -> Dictionary:
	return {
		"name": "Test Runner",
		"role": "Unset",
		"stats":
		{
			"INT": 7,
			"REF": 6,
			"DEX": 5,
			"TECH": 8,
			"COOL": 4,
			"WILL": 6,
			"LUCK": 5,
			"MOVE": 5,
			"BODY": 5,
			"EMP": 5
		},
		"skills": [],
	}


static func run(h: Harness) -> void:
	h.describe("character roles and checks")

	h.it("offers all ten Roles and starts a chosen Role Ability at Rank 4")
	h.equal(CharacterRules.ROLES.size(), 10, "Role count")
	var character := _character()
	CharacterRules.select_role(character, "netrunner")
	h.equal(character["role"], "Netrunner", "Role name")
	h.equal(character["role_ability"]["name"], "Interface", "Role Ability")
	h.equal(character["role_ability"]["rank"], 4, "starting Rank")
	h.equal(
		CharacterRules.role_effects(character)[0], "3 NET Actions per Turn", "Rank 4 NET Actions"
	)

	h.it("seeds all required Basic Skills at Level 2")
	var basics := CharacterRules.new_character_skills()
	h.equal(basics.size(), 13, "Basic Skill count")
	for entry in basics:
		h.equal((entry as Dictionary)["level"], 2, "%s Level" % (entry as Dictionary)["name"])

	h.it("adds catalog and specialized Skills without duplicates")
	h.equal(CharacterRules.add_skill(character, "Handgun", 5), true, "Handgun added")
	h.equal(CharacterRules.add_skill(character, "Handgun", 2), false, "duplicate rejected")
	h.equal(CharacterRules.add_skill(character, "Language", 4, "Japanese"), true, "Language added")
	h.equal(character["skills"][0]["stat"], "REF", "linked STAT")
	h.equal(character["skills"][1]["name"], "Language (Japanese)", "specialized name")

	h.it("rolls a Skill with STAT, Level, modifier, DV, and defender-wins ties")
	var skill_result := CharacterRules.roll_skill(
		character, "Handgun", -2, 16, Dice.FixedRandom.new([7])
	)
	h.equal(skill_result["base"], 11, "REF plus Handgun")
	h.equal(skill_result["total"], 16, "Check total")
	h.equal(skill_result["success"], false, "tie fails")

	h.it("rolls rank-based Role Abilities with critical dice")
	CharacterRules.select_role(character, "rockerboy")
	var impact_option: Dictionary = CharacterRules.role_roll_options(character)[1]
	var impact := CharacterRules.roll_role(
		character, impact_option, 1, 0, Dice.FixedRandom.new([10, 4])
	)
	h.equal(impact["rolls"], PackedInt32Array([10, 4]), "exploding roll")
	h.equal(impact["total"], 19, "Charismatic Impact total")
	h.equal(impact["success"], true, "beats built-in DV")

	h.it("uses the Lawman roll-under rule without critical dice")
	CharacterRules.select_role(character, "lawman")
	var backup_option: Dictionary = CharacterRules.role_roll_options(character)[0]
	var backup := CharacterRules.roll_role(
		character, backup_option, -1, 0, Dice.FixedRandom.new([4])
	)
	h.equal(backup["dv"], 3, "modified target")
	h.equal(backup["success"], false, "roll over target fails")

	h.it("rolls arrival and a higher tier after a successful Backup call of 6")
	var answered := CharacterRules.roll_role(
		character, backup_option, 0, 0, Dice.FixedRandom.new([3, 6])
	)
	h.equal(answered["success"], true, "call answered")
	h.equal(answered["arrival_rounds"], 6, "arrival")
	h.equal(answered["upgraded_backup"], true, "higher tier")

	h.it("adds Moto to a linked vehicle Skill Check")
	CharacterRules.select_role(character, "nomad")
	CharacterRules.add_skill(character, "Drive Land Vehicle", 3)
	var moto_option: Dictionary = CharacterRules.role_roll_options(character)[0]
	var moto := CharacterRules.roll_role(character, moto_option, 2, 15, Dice.FixedRandom.new([5]))
	h.equal(moto["base"], 13, "REF plus Skill plus Moto")
	h.equal(moto["total"], 20, "Moto Check total")
	h.equal(moto["success"], true, "Moto Check succeeds")

	h.it("enforces Role Ability allocation budgets")
	CharacterRules.select_role(character, "solo")
	h.equal(
		CharacterRules.set_role_option(character, "initiative_reaction", 2),
		true,
		"valid Solo allocation"
	)
	h.equal(
		CharacterRules.set_role_option(character, "precision_attack", 3),
		false,
		"over-budget allocation"
	)
	CharacterRules.select_role(character, "tech")
	var budget := CharacterRules.role_option_budget(character)
	h.equal(budget["spent"], 8, "Maker specialties assigned")
	h.equal(budget["maximum"], 8, "Maker budget")

	h.it("keeps required Basic Skills on the sheet")
	character["skills"] = CharacterRules.new_character_skills()
	h.equal(CharacterRules.remove_skill(character, "Athletics"), false, "Basic Skill retained")
	h.equal(CharacterRules.remove_skill(character, "Stealth"), false, "Basic Skill retained")

	h.it("enforces Complete Package creation budgets and limits")
	var recruit := _character()
	recruit["creation_complete"] = false
	recruit["stats"] = CampaignSchema.empty_stats()
	recruit["skills"] = CharacterRules.new_character_skills()
	h.equal(CharacterRules.set_stat(recruit, "INT", 8), true, "creation STAT raised")
	for key in ["REF", "DEX", "TECH", "COOL"]:
		h.equal(CharacterRules.set_stat(recruit, key, 8), true, "%s raised" % key)
	h.equal(CharacterRules.set_stat(recruit, "WILL", 6), true, "62nd point assigned")
	h.equal(CharacterRules.set_stat(recruit, "LUCK", 8), false, "62-point ceiling enforced")
	h.equal(CharacterRules.add_skill(recruit, "Handgun", 7), true, "new Skill added")
	h.equal(CharacterRules.selected_skill(recruit, "Handgun")["level"], 6, "creation Level capped")

	h.it("spends IP at rules-as-written Skill and Role Ability costs")
	var veteran := _character()
	veteran["creation_complete"] = true
	veteran["improvement_points"] = 1000
	CharacterRules.select_role(veteran, "solo")
	CharacterRules.add_skill(veteran, "Handgun", 5)
	h.equal(CharacterRules.skill_ip_cost(CharacterRules.selected_skill(veteran, "Handgun")), 120, "Level 6 cost")
	h.equal(CharacterRules.set_skill_level(veteran, "Handgun", 6), true, "Skill improved")
	h.equal(veteran["improvement_points"], 880, "Skill IP deducted")
	h.equal(CharacterRules.role_ip_cost(veteran), 300, "Role Rank 5 cost")
	h.equal(CharacterRules.improve_role(veteran), true, "Role improved")
	h.equal(veteran["role_ability"]["rank"], 5, "Role rank raised")
	h.equal(veteran["improvement_points"], 580, "Role IP deducted")
	h.equal(CharacterRules.set_stat(veteran, "INT", 8), false, "STAT cannot improve with IP")
