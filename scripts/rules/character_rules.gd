class_name CharacterRules
extends RefCounted

## Character creation catalogs and the checks made from a character sheet.
##
## The data here is intentionally mechanical: names, linked STATs, x2 costs,
## Role Ability state, and roll formulas. It does not reproduce sourcebook prose.

const ROLES: Array[Dictionary] = [
	{
		"key": "rockerboy",
		"name": "Rockerboy",
		"ability": "Charismatic Impact",
		"summary": "Influence fans and turn an audience into support."
	},
	{
		"key": "solo",
		"name": "Solo",
		"ability": "Combat Awareness",
		"summary": "Allocate combat focus before or during a fight."
	},
	{
		"key": "netrunner",
		"name": "Netrunner",
		"ability": "Interface",
		"summary": "Take NET Actions and make Interface checks."
	},
	{
		"key": "tech",
		"name": "Tech",
		"ability": "Maker",
		"summary": "Repair, upgrade, fabricate, and invent technology."
	},
	{
		"key": "medtech",
		"name": "Medtech",
		"ability": "Medicine",
		"summary": "Specialize in surgery, pharmaceuticals, and cryosystems."
	},
	{
		"key": "media",
		"name": "Media",
		"ability": "Credibility",
		"summary": "Develop sources, discover rumors, and publish convincing stories."
	},
	{
		"key": "exec",
		"name": "Exec",
		"ability": "Teamwork",
		"summary": "Gain corporate benefits and lead loyal Team Members."
	},
	{
		"key": "lawman",
		"name": "Lawman",
		"ability": "Backup",
		"summary": "Call law-enforcement backup while in danger."
	},
	{
		"key": "fixer",
		"name": "Fixer",
		"ability": "Operator",
		"summary": "Use contacts, reach, grease, and leverage in a deal."
	},
	{
		"key": "nomad",
		"name": "Nomad",
		"ability": "Moto",
		"summary": "Use family vehicles and add Moto to vehicle checks."
	},
]

const BASIC_SKILLS: PackedStringArray = [
	"Athletics",
	"Brawling",
	"Concentration",
	"Conversation",
	"Education",
	"Evasion",
	"First Aid",
	"Human Perception",
	"Language (Streetslang)",
	"Local Expert (Your Home)",
	"Perception",
	"Persuasion",
	"Stealth",
]

# Complete Package character generation limits and Improvement Point costs.
const STAT_POINT_BUDGET := 62
const SKILL_POINT_BUDGET := 86
const CREATION_STAT_MIN := 2
const CREATION_STAT_MAX := 8
const CREATION_SKILL_MAX := 6
const SKILL_IP_MULTIPLIER := 20
const ROLE_IP_MULTIPLIER := 60

# Skills whose name needs a player-supplied subject. The saved name is written
# as "Language (Japanese)", for example, while retaining Language's INT link.
const SPECIALIZED_SKILLS: PackedStringArray = [
	"Language",
	"Local Expert",
	"Science",
	"Martial Arts",
	"Play Instrument",
]

const SKILLS: Array[Dictionary] = [
	{"name": "Concentration", "stat": "WILL"},
	{"name": "Conceal/Reveal Object", "stat": "INT"},
	{"name": "Lip Reading", "stat": "INT"},
	{"name": "Perception", "stat": "INT"},
	{"name": "Tracking", "stat": "INT"},
	{"name": "Athletics", "stat": "DEX"},
	{"name": "Contortionist", "stat": "DEX"},
	{"name": "Dance", "stat": "DEX"},
	{"name": "Endurance", "stat": "WILL"},
	{"name": "Resist Torture/Drugs", "stat": "WILL"},
	{"name": "Stealth", "stat": "DEX"},
	{"name": "Drive Land Vehicle", "stat": "REF"},
	{"name": "Pilot Air Vehicle", "stat": "REF", "x2": true},
	{"name": "Pilot Sea Vehicle", "stat": "REF"},
	{"name": "Riding", "stat": "REF"},
	{"name": "Accounting", "stat": "INT"},
	{"name": "Animal Handling", "stat": "INT"},
	{"name": "Bureaucracy", "stat": "INT"},
	{"name": "Business", "stat": "INT"},
	{"name": "Composition", "stat": "INT"},
	{"name": "Criminology", "stat": "INT"},
	{"name": "Cryptography", "stat": "INT"},
	{"name": "Deduction", "stat": "INT"},
	{"name": "Education", "stat": "INT"},
	{"name": "Gamble", "stat": "INT"},
	{"name": "Language", "stat": "INT", "specialized": true},
	{"name": "Library Search", "stat": "INT"},
	{"name": "Local Expert", "stat": "INT", "specialized": true},
	{"name": "Science", "stat": "INT", "specialized": true},
	{"name": "Tactics", "stat": "INT"},
	{"name": "Wilderness Survival", "stat": "INT"},
	{"name": "Brawling", "stat": "DEX"},
	{"name": "Evasion", "stat": "DEX"},
	{"name": "Martial Arts", "stat": "DEX", "x2": true, "specialized": true},
	{"name": "Melee Weapon", "stat": "DEX"},
	{"name": "Acting", "stat": "COOL"},
	{"name": "Play Instrument", "stat": "TECH", "specialized": true},
	{"name": "Archery", "stat": "REF"},
	{"name": "Autofire", "stat": "REF", "x2": true},
	{"name": "Handgun", "stat": "REF"},
	{"name": "Heavy Weapons", "stat": "REF", "x2": true},
	{"name": "Shoulder Arms", "stat": "REF"},
	{"name": "Bribery", "stat": "COOL"},
	{"name": "Conversation", "stat": "EMP"},
	{"name": "Human Perception", "stat": "EMP"},
	{"name": "Interrogation", "stat": "COOL"},
	{"name": "Persuasion", "stat": "COOL"},
	{"name": "Personal Grooming", "stat": "COOL"},
	{"name": "Streetwise", "stat": "COOL"},
	{"name": "Trading", "stat": "COOL"},
	{"name": "Wardrobe & Style", "stat": "COOL"},
	{"name": "Air Vehicle Tech", "stat": "TECH"},
	{"name": "Basic Tech", "stat": "TECH"},
	{"name": "Cybertech", "stat": "TECH"},
	{"name": "Demolitions", "stat": "TECH", "x2": true},
	{"name": "Electronics/Security Tech", "stat": "TECH", "x2": true},
	{"name": "First Aid", "stat": "TECH"},
	{"name": "Forgery", "stat": "TECH"},
	{"name": "Land Vehicle Tech", "stat": "TECH"},
	{"name": "Paint/Draw/Sculpt", "stat": "TECH"},
	{"name": "Paramedic", "stat": "TECH", "x2": true},
	{"name": "Photography/Film", "stat": "TECH"},
	{"name": "Pick Lock", "stat": "TECH"},
	{"name": "Pick Pocket", "stat": "TECH"},
	{"name": "Sea Vehicle Tech", "stat": "TECH"},
	{"name": "Weaponstech", "stat": "TECH"},
]

const NOMAD_SKILLS: PackedStringArray = [
	"Drive Land Vehicle",
	"Pilot Air Vehicle",
	"Pilot Sea Vehicle",
	"Air Vehicle Tech",
	"Land Vehicle Tech",
	"Sea Vehicle Tech",
]
const TECH_SKILLS: PackedStringArray = [
	"Basic Tech",
	"Cybertech",
	"Electronics/Security Tech",
	"Weaponstech",
	"Land Vehicle Tech",
	"Sea Vehicle Tech",
	"Air Vehicle Tech",
]
const MAKER_SPECIALTIES := {
	"field": "Field Expertise",
	"upgrade": "Upgrade Expertise",
	"fabrication": "Fabrication Expertise",
	"invention": "Invention Expertise",
}
const SOLO_ALLOCATIONS := {
	"damage_deflection": {"label": "Damage Deflection", "step": 2},
	"fumble_recovery": {"label": "Fumble Recovery", "step": 4},
	"initiative_reaction": {"label": "Initiative Reaction", "step": 1},
	"precision_attack": {"label": "Precision Attack", "step": 3},
	"spot_weakness": {"label": "Spot Weakness", "step": 1},
	"threat_detection": {"label": "Threat Detection", "step": 1},
}


static func role(key: String) -> Dictionary:
	for entry in ROLES:
		if String(entry["key"]) == key:
			return entry
	return {}


static func role_key_from_name(name: String) -> String:
	var normalized := name.strip_edges().to_lower()
	for entry in ROLES:
		var role_name := String(entry["name"]).to_lower()
		if normalized == role_name or normalized.begins_with(role_name + " "):
			return String(entry["key"])
	return ""


static func skill_definition(name: String) -> Dictionary:
	for entry in SKILLS:
		var base_name := String(entry["name"])
		if (
			name == base_name
			or (bool(entry.get("specialized", false)) and name.begins_with(base_name + " ("))
		):
			return entry
	return {}


static func selected_skill(character: Dictionary, name: String) -> Dictionary:
	for entry in character.get("skills", []):
		if String((entry as Dictionary).get("name", "")) == name:
			return entry
	return {}


static func ensure_character(character: Dictionary) -> void:
	character["improvement_points"] = maxi(0, int(character.get("improvement_points", 0)))
	# Old sheets predate the creation workflow and remain completed rather than
	# unexpectedly becoming locked behind a point-allocation screen.
	character["creation_complete"] = bool(character.get("creation_complete", true))
	# The board token falls back to the default cylinder when this is blank, so
	# sheets written before model support stay valid.
	character["model_id"] = String(character.get("model_id", ""))
	var key := String(character.get("role_key", ""))
	if role(key).is_empty():
		key = role_key_from_name(String(character.get("role", "")))
	character["role_key"] = key
	var profile := role(key)
	var ability: Dictionary = character.get("role_ability", {})
	if profile.is_empty():
		character["role_ability"] = {
			"name": String(ability.get("name", "")),
			"rank": clampi(int(ability.get("rank", 0)), 0, 10),
			"options": (ability.get("options", {}) as Dictionary).duplicate(true),
		}
	else:
		var options: Dictionary = (ability.get("options", {}) as Dictionary).duplicate(true)
		character["role_ability"] = {
			"name": String(profile["ability"]),
			"rank": clampi(int(ability.get("rank", character.get("role_rank", 4))), 1, 10),
			"options": options,
		}
		_normalize_role_options(character)

	if not character.has("skills") or not character["skills"] is Array:
		character["skills"] = []
	for value in character["skills"]:
		var entry: Dictionary = value
		var definition := skill_definition(String(entry.get("name", "")))
		if not definition.is_empty():
			entry["stat"] = String(definition["stat"])
			entry["x2"] = bool(definition.get("x2", false))
		entry["level"] = clampi(int(entry.get("level", 0)), 0, 10)


static func new_character_skills() -> Array:
	var skills: Array = []
	for name in BASIC_SKILLS:
		var definition := skill_definition(name)
		skills.append({"name": name, "stat": definition["stat"], "level": 2, "x2": false})
	return skills


static func select_role(character: Dictionary, key: String) -> void:
	var profile := role(key)
	if profile.is_empty():
		character["role"] = "Unset"
		character["role_key"] = ""
		character["role_ability"] = {"name": "", "rank": 0, "options": {}}
		return
	character["role"] = String(profile["name"])
	character["role_key"] = key
	character["role_ability"] = {"name": profile["ability"], "rank": 4, "options": {}}
	_normalize_role_options(character)


static func set_role_rank(character: Dictionary, rank: int) -> void:
	ensure_character(character)
	(character["role_ability"] as Dictionary)["rank"] = clampi(rank, 1, 10)
	_normalize_role_options(character)


static func _normalize_role_options(character: Dictionary) -> void:
	var key := String(character.get("role_key", ""))
	var ability: Dictionary = character.get("role_ability", {})
	var rank := int(ability.get("rank", 0))
	var options: Dictionary = ability.get("options", {})
	if key == "solo":
		for option in SOLO_ALLOCATIONS:
			options[option] = maxi(0, int(options.get(option, 0)))
		if _option_total(options) > rank:
			options = {"initiative_reaction": rank}
	elif key == "tech":
		for option in MAKER_SPECIALTIES:
			options[option] = clampi(int(options.get(option, 0)), 0, rank)
		if _option_total(options) == 0:
			options["field"] = rank
			options["upgrade"] = rank
		elif _option_total(options) > rank * 2:
			options = {"field": rank, "upgrade": rank, "fabrication": 0, "invention": 0}
	elif key == "medtech":
		for option in ["surgery", "pharmaceuticals", "cryosystems"]:
			options[option] = clampi(int(options.get(option, 0)), 0, 5)
		if _option_total(options) == 0:
			options["surgery"] = mini(rank, 4)
		if _option_total(options) > rank:
			options = {"surgery": mini(rank, 5), "pharmaceuticals": 0, "cryosystems": 0}
	ability["options"] = options
	character["role_ability"] = ability


static func _option_total(options: Dictionary) -> int:
	var total := 0
	for value in options.values():
		total += int(value)
	return total


static func role_option_budget(character: Dictionary) -> Dictionary:
	ensure_character(character)
	var key := String(character.get("role_key", ""))
	var ability: Dictionary = character["role_ability"]
	var rank := int(ability["rank"])
	var spent := _option_total(ability["options"])
	if key == "solo" or key == "medtech":
		return {"spent": spent, "maximum": rank}
	if key == "tech":
		return {"spent": spent, "maximum": rank * 2}
	return {"spent": 0, "maximum": 0}


static func set_role_option(character: Dictionary, option: String, value: int) -> bool:
	ensure_character(character)
	var key := String(character.get("role_key", ""))
	var ability: Dictionary = character["role_ability"]
	var options: Dictionary = ability["options"]
	var previous := int(options.get(option, 0))
	var adjusted := maxi(0, value)
	if key == "solo":
		if not SOLO_ALLOCATIONS.has(option):
			return false
		var step := int((SOLO_ALLOCATIONS[option] as Dictionary)["step"])
		adjusted = int(adjusted / step) * step
	elif key == "tech":
		if not MAKER_SPECIALTIES.has(option):
			return false
		adjusted = mini(adjusted, int(ability["rank"]))
	elif key == "medtech":
		if not ["surgery", "pharmaceuticals", "cryosystems"].has(option):
			return false
		adjusted = mini(adjusted, 5)
	else:
		return false
	options[option] = adjusted
	var maximum := int(ability["rank"])
	if key == "tech":
		maximum *= 2
	if _option_total(options) > maximum:
		options[option] = previous
		return false
	return true


static func role_effects(character: Dictionary) -> PackedStringArray:
	ensure_character(character)
	var key := String(character.get("role_key", ""))
	var ability: Dictionary = character.get("role_ability", {})
	var rank := int(ability.get("rank", 0))
	var options: Dictionary = ability.get("options", {})
	match key:
		"rockerboy":
			return PackedStringArray(["Fan checks: single DV8 · up to 6 DV10 · huge group DV12"])
		"solo":
			return PackedStringArray(
				["%d of %d Combat Awareness points assigned" % [_option_total(options), rank]]
			)
		"netrunner":
			var actions := 2 if rank <= 3 else (3 if rank <= 6 else (4 if rank <= 9 else 5))
			return PackedStringArray(["%d NET Actions per Turn" % actions])
		"tech":
			return PackedStringArray(
				["%d of %d Maker specialty ranks assigned" % [_option_total(options), rank * 2]]
			)
		"medtech":
			return PackedStringArray(
				[
					(
						"Surgery %d · Medical Tech %d"
						% [
							mini(10, int(options.get("surgery", 0)) * 2),
							(
								int(options.get("pharmaceuticals", 0))
								+ int(options.get("cryosystems", 0))
							)
						]
					),
				]
			)
		"media":
			return PackedStringArray(["Passive rumor check: Credibility + 1d10"])
		"exec":
			var members := 0 if rank < 3 else (1 if rank < 5 else (2 if rank < 9 else 3))
			return PackedStringArray(
				["%d Team Members · corporate benefits unlock by rank" % members]
			)
		"lawman":
			return PackedStringArray(["Call Backup: roll 1d10 equal to or under Rank %d" % rank])
		"fixer":
			return PackedStringArray(["Haggle: COOL + Trading + Operator + 1d10"])
		"nomad":
			return PackedStringArray(
				["Add Moto %d to driving, piloting, and vehicle-tech checks" % rank]
			)
	return PackedStringArray()


static func add_skill(
	character: Dictionary, base_name: String, level: int, specialty := ""
) -> bool:
	ensure_character(character)
	var definition := skill_definition(base_name)
	if definition.is_empty():
		return false
	var name := base_name
	if bool(definition.get("specialized", false)):
		if specialty.strip_edges() == "":
			return false
		name = "%s (%s)" % [base_name, specialty.strip_edges()]
	if not selected_skill(character, name).is_empty():
		return false
	var adjusted_level := clampi(level, 0, 10)
	if not bool(character["creation_complete"]):
		adjusted_level = mini(adjusted_level, CREATION_SKILL_MAX)
		var added_cost := adjusted_level * (2 if bool(definition.get("x2", false)) else 1)
		if skill_points(character) + added_cost > SKILL_POINT_BUDGET:
			return false
	var skills: Array = character["skills"]
	skills.append(
		{
			"name": name,
			"stat": definition["stat"],
			"level": adjusted_level,
			"x2": bool(definition.get("x2", false)),
		}
	)
	return true


static func remove_skill(character: Dictionary, name: String) -> bool:
	if BASIC_SKILLS.has(name):
		return false
	var skills: Array = character.get("skills", [])
	for index in skills.size():
		if String((skills[index] as Dictionary).get("name", "")) == name:
			skills.remove_at(index)
			return true
	return false


static func skill_points(character: Dictionary) -> int:
	var total := 0
	for value in character.get("skills", []):
		var entry: Dictionary = value
		total += int(entry.get("level", 0)) * (2 if bool(entry.get("x2", false)) else 1)
	return total


static func creation_status(character: Dictionary) -> Dictionary:
	return {
		"stat_spent": CampaignSchema.points_spent(character.get("stats", {})),
		"stat_maximum": STAT_POINT_BUDGET,
		"skill_spent": skill_points(character),
		"skill_maximum": SKILL_POINT_BUDGET,
		"complete": bool(character.get("creation_complete", true)),
	}


static func set_stat(character: Dictionary, key: String, value: int) -> bool:
	if not CampaignSchema.STAT_KEYS.has(key):
		return false
	ensure_character(character)
	if bool(character["creation_complete"]):
		# In RED, STATs are not purchased with IP after character generation.
		return false
	var stats: Dictionary = character.get("stats", {})
	var adjusted := clampi(value, CREATION_STAT_MIN, CREATION_STAT_MAX)
	var spent_without_this := CampaignSchema.points_spent(stats) - int(stats.get(key, 0))
	if spent_without_this + adjusted > STAT_POINT_BUDGET:
		return false
	stats[key] = adjusted
	return true


static func set_skill_level(character: Dictionary, name: String, value: int) -> bool:
	ensure_character(character)
	var entry := selected_skill(character, name)
	if entry.is_empty():
		return false
	var old_level := int(entry.get("level", 0))
	var minimum := 2 if BASIC_SKILLS.has(name) else 0
	if not bool(character["creation_complete"]):
		var adjusted := clampi(value, minimum, CREATION_SKILL_MAX)
		var multiplier := 2 if bool(entry.get("x2", false)) else 1
		if skill_points(character) + (adjusted - old_level) * multiplier > SKILL_POINT_BUDGET:
			return false
		entry["level"] = adjusted
		return true
	if value != old_level + 1 or old_level >= 10:
		return false
	var cost := value * SKILL_IP_MULTIPLIER * (2 if bool(entry.get("x2", false)) else 1)
	if int(character["improvement_points"]) < cost:
		return false
	character["improvement_points"] = int(character["improvement_points"]) - cost
	entry["level"] = value
	return true


static func skill_ip_cost(skill: Dictionary) -> int:
	return (int(skill.get("level", 0)) + 1) * SKILL_IP_MULTIPLIER * (2 if bool(skill.get("x2", false)) else 1)


static func role_ip_cost(character: Dictionary) -> int:
	ensure_character(character)
	return (int((character["role_ability"] as Dictionary).get("rank", 0)) + 1) * ROLE_IP_MULTIPLIER


static func improve_role(character: Dictionary) -> bool:
	ensure_character(character)
	var rank := int((character["role_ability"] as Dictionary).get("rank", 0))
	if not bool(character["creation_complete"]) or rank < 1 or rank >= 10:
		return false
	var cost := role_ip_cost(character)
	if int(character["improvement_points"]) < cost:
		return false
	character["improvement_points"] = int(character["improvement_points"]) - cost
	# role_ip_cost() runs ensure_character() again, which rebuilds role_ability,
	# so the rank has to be written through a fresh lookup rather than a
	# reference cached before the cost was computed.
	(character["role_ability"] as Dictionary)["rank"] = rank + 1
	_normalize_role_options(character)
	return true


static func finish_creation(character: Dictionary) -> bool:
	ensure_character(character)
	if bool(character["creation_complete"]):
		return true
	if CampaignSchema.points_spent(character.get("stats", {})) != STAT_POINT_BUDGET:
		return false
	if skill_points(character) != SKILL_POINT_BUDGET:
		return false
	if role(String(character.get("role_key", ""))).is_empty():
		return false
	character["creation_complete"] = true
	return true


static func roll_skill(
	character: Dictionary, name: String, modifier: int, dv: int, rng: Dice.RandomSource
) -> Dictionary:
	ensure_character(character)
	var entry := selected_skill(character, name)
	if entry.is_empty():
		return {"ok": false, "error": "Skill is not on this character sheet."}
	var stat_key := String(entry.get("stat", ""))
	var stat_value := int((character.get("stats", {}) as Dictionary).get(stat_key, 0))
	var skill_level := int(entry.get("level", 0))
	return _check(name, stat_key, stat_value + skill_level, modifier, dv, rng)


static func role_roll_options(character: Dictionary) -> Array[Dictionary]:
	ensure_character(character)
	var key := String(character.get("role_key", ""))
	var options: Array[Dictionary] = []
	match key:
		"rockerboy":
			options = [
				{"label": "Single fan · DV8", "action": "impact", "dv": 8},
				{"label": "Small group · DV10", "action": "impact", "dv": 10},
				{"label": "Huge group · DV12", "action": "impact", "dv": 12}
			]
		"netrunner":
			options = [{"label": "Interface Check", "action": "interface", "dv": 0}]
		"media":
			options = [
				{"label": "Passive Rumor Check", "action": "rumor", "dv": 0},
				{"label": "Publish Story · Believability", "action": "publish", "dv": 0}
			]
		"lawman":
			options = [{"label": "Call Backup", "action": "backup", "dv": 0}]
		"fixer":
			options = [{"label": "Haggle · COOL + Trading + Operator", "action": "haggle", "dv": 0}]
		"nomad":
			for skill_name in NOMAD_SKILLS:
				options.append(
					{
						"label": "%s + Moto" % skill_name,
						"action": "moto",
						"skill": skill_name,
						"dv": 0
					}
				)
		"tech":
			for specialty in MAKER_SPECIALTIES:
				for skill_name in TECH_SKILLS:
					options.append(
						{
							"label": "%s · %s" % [MAKER_SPECIALTIES[specialty], skill_name],
							"action": specialty,
							"skill": skill_name,
							"dv": 0
						}
					)
		"medtech":
			options = [
				{"label": "Surgery Check", "action": "surgery", "dv": 0},
				{"label": "Medical Tech Check", "action": "medical_tech", "dv": 0}
			]
	return options


static func roll_role(
	character: Dictionary,
	option: Dictionary,
	modifier: int,
	dv_override: int,
	rng: Dice.RandomSource
) -> Dictionary:
	ensure_character(character)
	var key := String(character.get("role_key", ""))
	var ability: Dictionary = character.get("role_ability", {})
	var rank := int(ability.get("rank", 0))
	var role_options: Dictionary = ability.get("options", {})
	var action := String(option.get("action", ""))
	var dv := dv_override if dv_override > 0 else int(option.get("dv", 0))
	if key == "" or action == "":
		return {"ok": false, "error": "This Role Ability does not call for a check."}
	if action in ["impact", "interface", "rumor"]:
		return _check(String(ability["name"]), "", rank, modifier, dv, rng)
	if action == "publish":
		var belief_roll := rng.randint(1, 10)
		var belief := (
			2
			if rank <= 2
			else (
				3
				if rank <= 4
				else (4 if rank <= 6 else (5 if rank <= 8 else (6 if rank == 9 else 7)))
			)
		)
		var belief_target := clampi(belief + modifier, 1, 10)
		return {
			"ok": true,
			"label": "Credibility · Believability",
			"rolls": PackedInt32Array([belief_roll]),
			"die_total": belief_roll,
			"base": belief,
			"modifier": modifier,
			"dv": belief_target,
			"total": belief_roll,
			"success": belief_roll <= belief_target,
			"under": true
		}
	if action == "backup":
		var rolled := rng.randint(1, 10)
		var target := clampi(rank + modifier, 1, 10)
		var answered := rolled <= target
		var arrival := rng.randint(1, 6) if answered else 0
		return {
			"ok": true,
			"label": "Backup",
			"rolls": PackedInt32Array([rolled]),
			"die_total": rolled,
			"base": rank,
			"modifier": modifier,
			"dv": target,
			"total": rolled,
			"success": answered,
			"under": true,
			"arrival_rounds": arrival,
			"upgraded_backup": arrival == 6
		}
	if action == "haggle":
		return _stat_skill_role_check(
			character, "Trading", rank, modifier, dv, "Operator · Haggle", rng
		)
	if action == "moto":
		return _stat_skill_role_check(
			character, String(option.get("skill", "")), rank, modifier, dv, "Moto", rng
		)
	if key == "tech" and MAKER_SPECIALTIES.has(action):
		return _stat_skill_role_check(
			character,
			String(option.get("skill", "")),
			int(role_options.get(action, 0)),
			modifier,
			dv,
			String(MAKER_SPECIALTIES[action]),
			rng
		)
	if key == "medtech" and action == "surgery":
		return _check(
			"Medicine · Surgery",
			"TECH",
			(
				int((character.get("stats", {}) as Dictionary).get("TECH", 0))
				+ mini(10, int(role_options.get("surgery", 0)) * 2)
			),
			modifier,
			dv,
			rng
		)
	if key == "medtech" and action == "medical_tech":
		var medical_tech := (
			int(role_options.get("pharmaceuticals", 0)) + int(role_options.get("cryosystems", 0))
		)
		return _check(
			"Medicine · Medical Tech",
			"TECH",
			int((character.get("stats", {}) as Dictionary).get("TECH", 0)) + medical_tech,
			modifier,
			dv,
			rng
		)
	return {"ok": false, "error": "This Role Ability does not call for that check."}


static func _stat_skill_role_check(
	character: Dictionary,
	skill_name: String,
	role_bonus: int,
	modifier: int,
	dv: int,
	label: String,
	rng: Dice.RandomSource
) -> Dictionary:
	var definition := skill_definition(skill_name)
	if definition.is_empty():
		return {"ok": false, "error": "Unknown linked Skill."}
	var entry := selected_skill(character, skill_name)
	var skill_level := int(entry.get("level", 0))
	var stat_key := String(definition["stat"])
	var stat_value := int((character.get("stats", {}) as Dictionary).get(stat_key, 0))
	return _check(
		"%s · %s" % [label, skill_name],
		stat_key,
		stat_value + skill_level + role_bonus,
		modifier,
		dv,
		rng
	)


static func _check(
	label: String, stat: String, base: int, modifier: int, dv: int, rng: Dice.RandomSource
) -> Dictionary:
	var check := Dice.roll_check(rng)
	var total := base + modifier + int(check["total"])
	return {
		"ok": true,
		"label": label,
		"stat": stat,
		"rolls": check["rolls"],
		"die_total": int(check["total"]),
		"base": base,
		"modifier": modifier,
		"dv": dv,
		"total": total,
		"success": total > dv if dv > 0 else null,
		"under": false
	}


static func format_result(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return String(result.get("error", "Check could not be rolled."))
	var rolls: PackedInt32Array = result["rolls"]
	var dice_text := str(result["die_total"])
	if rolls.size() > 1:
		dice_text = "%d%s%d" % [rolls[0], "+" if rolls[0] == 10 else "-", rolls[1]]
	if bool(result.get("under", false)):
		var under_text := (
			"%s · d10 %s vs target %d (base %d %+d mod) · %s"
			% [
				result["label"],
				dice_text,
				result["dv"],
				result["base"],
				result["modifier"],
				"SUCCESS" if bool(result["success"]) else "FAIL",
			]
		)
		if int(result.get("arrival_rounds", 0)) > 0:
			under_text += (
				" · arrives in %d rounds%s"
				% [
					result["arrival_rounds"],
					" at the next tier" if bool(result.get("upgraded_backup", false)) else "",
				]
			)
		return under_text
	var text := (
		"%s · d10 %s + base %d %+d mod = %d"
		% [result["label"], dice_text, result["base"], result["modifier"], result["total"]]
	)
	if result.get("success", null) != null:
		text += (
			" · %s %s%d"
			% [
				"SUCCESS" if bool(result["success"]) else "FAIL",
				"≤" if bool(result.get("under", false)) else "DV",
				int(result["dv"])
			]
		)
	return text
