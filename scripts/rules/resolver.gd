class_name Resolver
extends RefCounted

## Pure Cyberpunk RED combat resolution.
##
## Performs no I/O and mutates neither the request nor the table provider. Every
## state change is described as an event for [Events] to apply, which is what
## makes the GM's undo exact rather than approximate.
##
## The constants below are working values, each carrying the page it was checked
## against. They are not a substitute for checking a licensed copy of the book.

const RULES := {
	"hit_requires_meeting_dv": false,  # core rulebook p. 172: defender wins a tie
	"opposed_hit_requires_exceeding_dv": true,  # core rulebook p. 129: defender wins a tie
	"ablate_on_stopped_hit": false,  # core rulebook p. 186: ablate only after damage
	"crit_injury_bonus_damage": 5,  # core rulebook p. 187
	"critical_trigger_sixes": 2,  # core rulebook p. 187
	"headshot_multiplier": 2,  # core rulebook p. 170: after head SP
	"min_damage_through_armor": 0,  # core rulebook p. 186
	"aimed_shot_modifier": -8,  # core rulebook p. 170
	"autofire_ammo_cost": 10,  # core rulebook p. 173
	"autofire_damage_dice": 2,  # core rulebook p. 173
	"cover_blocks_overflow": true,  # core rulebook p. 182
	"poor_quality_jams_on_one": true,  # core rulebook p. 342
	"excellent_quality_attack_bonus": 1,  # core rulebook p. 342
}

## The original resolver modelled body and head only. Limb locations were added
## for the character sheet's per-location SP; they use their own armour value
## and take no damage multiplier.
const HIT_LOCATIONS: PackedStringArray = [
	"head", "body", "left_arm", "right_arm", "left_leg", "right_leg"
]


class Weapon extends RefCounted:
	var name: String
	var weapon_type: String
	var damage_dice: int
	var rof: int
	var magazine: int
	## -1 means the weapon cannot autofire.
	var autofire_rating: int
	var quality: String
	var damage_bonus: int

	func _init(
		p_name: String,
		p_weapon_type: String,
		p_damage_dice: int,
		p_rof := 1,
		p_magazine := 1,
		p_autofire_rating := -1,
		p_quality := "standard",
		p_damage_bonus := 0,
	) -> void:
		assert(p_damage_dice > 0, "damage_dice must be positive")
		assert(p_rof > 0, "rof must be positive")
		assert(p_magazine > 0, "magazine must be positive")
		assert(p_autofire_rating == -1 or p_autofire_rating > 0, "autofire_rating must be positive")
		name = p_name
		weapon_type = p_weapon_type
		damage_dice = p_damage_dice
		rof = p_rof
		magazine = p_magazine
		autofire_rating = p_autofire_rating
		quality = p_quality
		damage_bonus = p_damage_bonus

	func can_autofire() -> bool:
		return autofire_rating > 0


class TargetState extends RefCounted:
	var target_id: String
	var hp: int
	var max_hp: int
	## Location name to SP. Missing locations count as 0.
	var armor: Dictionary
	var cover_hp: int

	func _init(
		p_target_id: String, p_hp: int, p_max_hp: int, p_armor := {}, p_cover_hp := 0
	) -> void:
		assert(p_max_hp > 0, "max_hp must be positive")
		assert(p_hp <= p_max_hp, "hp cannot exceed max_hp")
		assert(p_cover_hp >= 0, "cover HP cannot be negative")
		for value in p_armor.values():
			assert(int(value) >= 0, "SP cannot be negative")
		target_id = p_target_id
		hp = p_hp
		max_hp = p_max_hp
		armor = p_armor.duplicate()
		cover_hp = p_cover_hp

	func sp_at(location: String) -> int:
		return int(armor.get(location, 0))


class AttackRequest extends RefCounted:
	var attacker_id: String
	var target: TargetState
	var weapon: Weapon
	var attack_base: int
	var distance_m: float
	var ammo: int
	var location: String
	var mode: String
	## -1 means the defender is not making an opposed check.
	var defender_evasion_base: int
	var modifiers: int

	func _init(
		p_attacker_id: String,
		p_target: TargetState,
		p_weapon: Weapon,
		p_attack_base: int,
		p_distance_m: float,
		p_ammo: int,
		p_location := "body",
		p_mode := "single",
		p_defender_evasion_base := -1,
		p_modifiers := 0,
	) -> void:
		assert(p_distance_m >= 0.0, "distance_m cannot be negative")
		assert(p_ammo >= 0, "ammo cannot be negative")
		assert(p_location == "body" or p_mode == "aimed", "a called shot must use aimed mode")
		assert(p_mode != "autofire" or p_weapon.can_autofire(), "weapon does not support autofire")
		attacker_id = p_attacker_id
		target = p_target
		weapon = p_weapon
		attack_base = p_attack_base
		distance_m = p_distance_m
		ammo = p_ammo
		location = p_location
		mode = p_mode
		defender_evasion_base = p_defender_evasion_base
		modifiers = p_modifiers

	func is_contested() -> bool:
		return defender_evasion_base >= 0


class AttackResult extends RefCounted:
	var hit := false
	var attack_rolls := PackedInt32Array()
	var attack_total := 0
	var defense := 0
	var defense_kind := "range"
	var damage_rolls := PackedInt32Array()
	var raw_damage := 0
	var armor_sp := 0
	var armor_damage := 0
	var hp_damage := 0
	var critical_injury := ""
	var events: Array[Dictionary] = []
	var card_lines: PackedStringArray = []

	func to_dict() -> Dictionary:
		return {
			"hit": hit,
			"attack_rolls": attack_rolls,
			"attack_total": attack_total,
			"defense": defense,
			"defense_kind": defense_kind,
			"damage_rolls": damage_rolls,
			"raw_damage": raw_damage,
			"armor_sp": armor_sp,
			"armor_damage": armor_damage,
			"hp_damage": hp_damage,
			"critical_injury": critical_injury,
		}


## Critical injury tables are printed for the body and the head only.
static func injury_table_for(location: String) -> String:
	return "head" if location == "head" else "body"


static func _meets_defense(total: int, defense: int, kind: String) -> bool:
	if kind == "evasion":
		return total > defense if RULES["opposed_hit_requires_exceeding_dv"] else total >= defense
	return total >= defense if RULES["hit_requires_meeting_dv"] else total > defense


## Resolve one attack. [param tables] must answer ranged_dv, autofire_dv,
## autofire_multiplier and critical_injury.
static func resolve_attack(
	request: AttackRequest, tables: Tables, rng: Dice.RandomSource
) -> AttackResult:
	var ammo_cost: int = int(RULES["autofire_ammo_cost"]) if request.mode == "autofire" else 1
	assert(request.ammo >= ammo_cost, "cannot attack with an empty weapon")

	var result := AttackResult.new()
	var events: Array[Dictionary] = [
		{
			"kind": "ammo_spent",
			"actor_id": request.attacker_id,
			"weapon": request.weapon.name,
			"amount": ammo_cost,
		}
	]

	var check := Dice.roll_check(rng)
	var check_total: int = check["total"]
	var check_rolls: PackedInt32Array = check["rolls"]
	var aimed_modifier: int = int(RULES["aimed_shot_modifier"]) if request.mode == "aimed" else 0
	var quality_modifier: int = (
		int(RULES["excellent_quality_attack_bonus"]) if request.weapon.quality == "excellent" else 0
	)
	var attack_total: int = (
		request.attack_base + request.modifiers + aimed_modifier + quality_modifier + check_total
	)

	if (
		request.weapon.quality == "poor"
		and check_rolls[0] == 1
		and RULES["poor_quality_jams_on_one"]
	):
		events.append(
			{
				"kind": "weapon_jammed",
				"actor_id": request.attacker_id,
				"weapon": request.weapon.name,
			}
		)

	var defense := 0
	var defense_kind := "range"
	var defense_card := ""
	if not request.is_contested():
		if request.mode == "autofire":
			defense = tables.autofire_dv(request.weapon.weapon_type, request.distance_m)
		else:
			defense = tables.ranged_dv(request.weapon.weapon_type, request.distance_m)
		defense_card = "DV %d (range)" % defense
	else:
		defense_kind = "evasion"
		var defense_roll := Dice.roll_check(rng)
		defense = request.defender_evasion_base + int(defense_roll["total"])
		defense_card = "Defense %d (evasion)" % defense

	var attack_card := (
		"Attack: base %d + d10 %d + modifiers %d = %d"
		% [
			request.attack_base,
			check_total,
			request.modifiers + aimed_modifier + quality_modifier,
			attack_total,
		]
	)

	result.attack_rolls = check_rolls
	result.attack_total = attack_total
	result.defense = defense
	result.defense_kind = defense_kind

	if not _meets_defense(attack_total, defense, defense_kind):
		events.append(
			{
				"kind": "attack_missed",
				"actor_id": request.attacker_id,
				"target_id": request.target.target_id,
			}
		)
		result.hit = false
		result.events = events
		result.card_lines = PackedStringArray([attack_card, defense_card, "MISS"])
		return result

	var damage_dice: int = (
		int(RULES["autofire_damage_dice"]) if request.mode == "autofire" else request.weapon.damage_dice
	)
	var damage := Dice.damage_roll(damage_dice, rng)
	var damage_rolls: PackedInt32Array = damage["rolls"]
	var base_damage: int = damage["total"]
	var multiplier := 1
	if request.mode == "autofire":
		multiplier = tables.autofire_multiplier(attack_total - defense, request.weapon.autofire_rating)
	var raw_damage := base_damage * multiplier + request.weapon.damage_bonus

	var pieces := PackedStringArray()
	for value in damage_rolls:
		pieces.append(str(value))
	var damage_text := "Damage: %s = %d" % [" + ".join(pieces), base_damage]
	if multiplier != 1:
		damage_text += "; x %d = %d" % [multiplier, raw_damage]
	var card_lines := PackedStringArray([attack_card, defense_card, damage_text])

	result.hit = true
	result.damage_rolls = damage_rolls
	result.raw_damage = raw_damage

	# Cover is binary in RED: it takes the hit instead of the target, and damage
	# beyond its remaining HP does not pass through on this attack.
	if request.target.cover_hp > 0:
		events.append(
			{
				"kind": "cover_damaged",
				"target_id": request.target.target_id,
				"amount": raw_damage,
			}
		)
		var remaining: int = maxi(0, request.target.cover_hp - raw_damage)
		card_lines.append(
			"Cover: %d HP - %d = %d HP" % [request.target.cover_hp, raw_damage, remaining]
		)
		result.events = events
		result.card_lines = card_lines
		return result

	var armor_sp := request.target.sp_at(request.location)
	var penetrates := raw_damage > armor_sp
	var after_armor := 0
	if penetrates:
		after_armor = maxi(int(RULES["min_damage_through_armor"]), raw_damage - armor_sp)
	var location_multiplier: int = (
		int(RULES["headshot_multiplier"]) if request.location == "head" else 1
	)
	var armor_damage := after_armor * location_multiplier

	if penetrates or RULES["ablate_on_stopped_hit"]:
		events.append(
			{
				"kind": "armor_ablated",
				"target_id": request.target.target_id,
				"location": request.location,
				"amount": 1,
			}
		)

	var critical_injury := ""
	var critical_bonus := 0
	var sixes := 0
	for value in damage_rolls:
		if value == 6:
			sixes += 1
	if sixes >= int(RULES["critical_trigger_sixes"]):
		var injury_roll := Dice.damage_roll(2, rng)
		var injury := tables.critical_injury(injury_table_for(request.location), int(injury_roll["total"]))
		critical_injury = String(injury["name"])
		critical_bonus = int(RULES["crit_injury_bonus_damage"])
		events.append(
			{
				"kind": "critical_injury",
				"target_id": request.target.target_id,
				"location": request.location,
				"injury": critical_injury,
				"rolls": injury_roll["rolls"],
			}
		)

	var hp_damage := armor_damage + critical_bonus
	if hp_damage != 0:
		events.append(
			{
				"kind": "damage_taken",
				"target_id": request.target.target_id,
				"amount": hp_damage,
			}
		)

	var new_hp := request.target.hp - hp_damage
	@warning_ignore("integer_division")
	var serious_threshold := (request.target.max_hp - 1) / 2
	if request.target.hp > serious_threshold and serious_threshold >= new_hp:
		events.append({"kind": "seriously_wounded", "target_id": request.target.target_id})
	if new_hp <= 0:
		events.append({"kind": "death_save_due", "target_id": request.target.target_id})

	card_lines.append("Armor: %d - SP %d = %d" % [raw_damage, armor_sp, after_armor])
	if location_multiplier != 1:
		card_lines.append("Head: %d x %d = %d" % [after_armor, location_multiplier, armor_damage])
	if critical_bonus != 0:
		card_lines.append(
			"Critical Injury (%s): +%d direct HP" % [critical_injury, critical_bonus]
		)
	card_lines.append("HP damage: %d + %d = %d" % [armor_damage, critical_bonus, hp_damage])

	result.armor_sp = armor_sp
	result.armor_damage = armor_damage
	result.hp_damage = hp_damage
	result.critical_injury = critical_injury
	result.events = events
	result.card_lines = card_lines
	return result
