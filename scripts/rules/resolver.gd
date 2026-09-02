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

## Working values for the mechanics the first version of this resolver did not
## cover: ammunition types, melee and brawling, and suppressive fire.
##
## Unlike [constant RULES] these carry no page citation, because they were not
## checked line by line against a licensed copy. Treat them the way
## [TablesDefault] is treated: something a GM who owns the book confirms before
## leaning on it at the table.
const EXTENDED_RULES := {
	## Armour-piercing trades damage for penetration. It halves the SP it meets
	## and then halves what gets through.
	"armor_piercing_sp_divisor": 2,
	"armor_piercing_damage_divisor": 2,
	## Expansive rounds double what reaches flesh and never mark armour, which
	## makes them worse than basic against anyone wearing any.
	"expansive_unarmored_multiplier": 2,
	"expansive_ablates": false,
	## Incendiary sets the target alight instead of hitting harder.
	"incendiary_burn_damage": 2,
	"incendiary_burn_rounds": 3,
	## Suppressive fire spends a burst to pin rather than to wound.
	"suppressive_ammo_cost": 10,
	"suppressive_dv": 15,
	## Melee is close enough that the defender always gets to move.
	"melee_max_distance_m": 2.0,
	## A thrown weapon that misses still lands somewhere.
	"area_scatter_max_m": 4,
	## Anyone who beats the blast DV throws themselves clear of half of it.
	"area_evasion_dv": 15,
	"area_evasion_damage_divisor": 2,
}

## What a round does on the way through armour. "basic" is the default and
## changes nothing, so an attack that never names a type resolves as before.
const AMMO_TYPES: PackedStringArray = ["basic", "armor_piercing", "expansive", "incendiary"]

## Attack modes. "melee" is contested at conversational range; "suppressive"
## spends a burst to pin a target rather than to damage them.
const MODES: PackedStringArray = ["single", "aimed", "autofire", "melee", "suppressive"]


## The ammunition cost of one attack in [param mode].
static func ammo_cost_for(mode: String) -> int:
	if mode == "autofire":
		return int(RULES["autofire_ammo_cost"])
	if mode == "suppressive":
		return int(EXTENDED_RULES["suppressive_ammo_cost"])
	return 1


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
	## Wound-state penalties, set after construction rather than passed in: they
	## are read off the actor's state by whoever owns it, not chosen per shot.
	var wound_penalty := 0
	var defender_wound_penalty := 0
	## What is loaded. See [constant AMMO_TYPES]; "basic" changes nothing.
	var ammo_type := "basic"
	## The damage a strong arm adds to a melee or brawling hit. Set by whoever
	## owns the attacker's BODY, for the same reason the wound penalties are.
	var melee_bonus := 0

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
		assert(
			p_mode != "suppressive" or p_weapon.can_autofire(),
			"suppressive fire needs a weapon that can autofire"
		)
		assert(
			p_mode != "melee" or p_distance_m <= float(EXTENDED_RULES["melee_max_distance_m"]),
			"a melee attack must be made within reach"
		)
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


## What the round does to the damage that got past armour.
##
## Armour-piercing gives up half of what it let through; expansive doubles
## against a target wearing nothing and does nothing at all against one who is.
static func _apply_ammo_to_damage(ammo_type: String, after_armor: int, armor_sp: int) -> int:
	if after_armor <= 0:
		return after_armor
	if ammo_type == "armor_piercing":
		@warning_ignore("integer_division")
		return after_armor / int(EXTENDED_RULES["armor_piercing_damage_divisor"])
	if ammo_type == "expansive" and armor_sp <= 0:
		return after_armor * int(EXTENDED_RULES["expansive_unarmored_multiplier"])
	return after_armor


## Whether a round marks the armour it went through. Expansive does not, which
## is the cost of what it does to anyone not wearing any.
static func _ammo_ablates(ammo_type: String) -> bool:
	if ammo_type == "expansive":
		return bool(EXTENDED_RULES["expansive_ablates"])
	return true


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
	var ammo_cost := ammo_cost_for(request.mode)
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
		request.attack_base
		+ request.modifiers
		+ aimed_modifier
		+ quality_modifier
		+ request.wound_penalty
		+ check_total
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
	if request.mode == "suppressive" and not request.is_contested():
		# Pinning someone is a fixed problem: the burst goes where they are, and
		# what matters is whether they keep their head up, not how far away it is.
		defense = int(EXTENDED_RULES["suppressive_dv"])
		defense_kind = "suppression"
		defense_card = "DV %d (suppression)" % defense
	elif not request.is_contested():
		if request.mode == "autofire":
			defense = tables.autofire_dv(request.weapon.weapon_type, request.distance_m)
		else:
			defense = tables.ranged_dv(request.weapon.weapon_type, request.distance_m)
		defense_card = "DV %d (range)" % defense
	else:
		defense_kind = "evasion"
		var defense_roll := Dice.roll_check(rng)
		defense = (
			request.defender_evasion_base
			+ request.defender_wound_penalty
			+ int(defense_roll["total"])
		)
		defense_card = "Defense %d (evasion)" % defense
		if request.defender_wound_penalty != 0:
			defense_card += ", wounds %d" % request.defender_wound_penalty

	var attack_card := (
		"Attack: base %d + d10 %d + modifiers %d = %d"
		% [
			request.attack_base,
			check_total,
			request.modifiers + aimed_modifier + quality_modifier + request.wound_penalty,
			attack_total,
		]
	)
	if request.wound_penalty != 0:
		attack_card += " (wounds %d)" % request.wound_penalty

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

	# Suppressive fire never rolls damage. A burst that lands pins the target for
	# a round instead of wounding them, which is the whole reason to spend the
	# ammunition on it.
	if request.mode == "suppressive":
		events.append(
			{
				"kind": "suppressed",
				"target_id": request.target.target_id,
				"attacker_id": request.attacker_id,
			}
		)
		result.hit = true
		result.events = events
		result.card_lines = PackedStringArray(
			[attack_card, defense_card, "SUPPRESSED — pinned until their next turn."]
		)
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
	var melee_bonus: int = request.melee_bonus if request.mode == "melee" else 0
	var raw_damage := base_damage * multiplier + request.weapon.damage_bonus + melee_bonus

	var pieces := PackedStringArray()
	for value in damage_rolls:
		pieces.append(str(value))
	var damage_text := "Damage: %s = %d" % [" + ".join(pieces), base_damage]
	if multiplier != 1:
		damage_text += "; x %d = %d" % [multiplier, base_damage * multiplier]
	if melee_bonus != 0:
		damage_text += "; BODY %+d = %d" % [melee_bonus, raw_damage]
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

	var worn_sp := request.target.sp_at(request.location)
	var armor_sp := worn_sp
	if request.ammo_type == "armor_piercing":
		# Armour-piercing meets half the plate. Rounded up, so a single point of
		# SP is not simply ignored.
		var divisor := int(EXTENDED_RULES["armor_piercing_sp_divisor"])
		armor_sp = int(ceili(float(worn_sp) / float(divisor)))
	var penetrates := raw_damage > armor_sp
	var after_armor := 0
	if penetrates:
		after_armor = maxi(int(RULES["min_damage_through_armor"]), raw_damage - armor_sp)
	after_armor = _apply_ammo_to_damage(request.ammo_type, after_armor, armor_sp)
	var location_multiplier: int = (
		int(RULES["headshot_multiplier"]) if request.location == "head" else 1
	)
	var armor_damage := after_armor * location_multiplier

	if (penetrates or RULES["ablate_on_stopped_hit"]) and _ammo_ablates(request.ammo_type):
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

	if request.ammo_type == "incendiary" and armor_damage > 0:
		events.append(
			{
				"kind": "ignited",
				"target_id": request.target.target_id,
				"amount": int(EXTENDED_RULES["incendiary_burn_damage"]),
				"rounds": int(EXTENDED_RULES["incendiary_burn_rounds"]),
			}
		)
		card_lines.append(
			"Incendiary: burning for %d damage a round, %d rounds."
			% [
				int(EXTENDED_RULES["incendiary_burn_damage"]),
				int(EXTENDED_RULES["incendiary_burn_rounds"]),
			]
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

	# Dropping to zero a second time re-arms the save, which is how a stabilised
	# character who is shot again goes back on the clock.
	events.append_array(wound_events(request.target, hp_damage))

	if armor_sp != worn_sp:
		card_lines.append(
			"Armour-piercing: SP %d halved to %d" % [worn_sp, armor_sp]
		)
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


class AreaTarget extends RefCounted:
	## One body inside the blast, and how far from the centre it stands.
	var target: TargetState
	var distance_m: float
	## -1 means this target does not get a check to dive clear.
	var evasion_base: int
	var wound_penalty: int

	func _init(
		p_target: TargetState, p_distance_m: float, p_evasion_base := -1, p_wound_penalty := 0
	) -> void:
		assert(p_distance_m >= 0.0, "distance_m cannot be negative")
		target = p_target
		distance_m = p_distance_m
		evasion_base = p_evasion_base
		wound_penalty = p_wound_penalty


class AreaResult extends RefCounted:
	var on_target := false
	var attack_rolls := PackedInt32Array()
	var attack_total := 0
	var defense := 0
	var scatter_m := 0
	var damage_rolls := PackedInt32Array()
	var raw_damage := 0
	## One entry per target caught, each {"target_id", "hp_damage", "evaded"}.
	var hits: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var card_lines: PackedStringArray = []

	func to_dict() -> Dictionary:
		return {
			"on_target": on_target,
			"attack_rolls": attack_rolls,
			"attack_total": attack_total,
			"defense": defense,
			"scatter_m": scatter_m,
			"damage_rolls": damage_rolls,
			"raw_damage": raw_damage,
			"hits": hits.duplicate(true),
		}


## Resolve one thrown or launched area attack.
##
## The throw is checked against the range table like any other, but a miss does
## not end the attack: the weapon lands short by [constant EXTENDED_RULES]'s
## scatter and still catches whoever is standing near where it fell. Every
## target inside [param radius_m] rolls once against the blast; beating it means
## diving clear of half the damage, not all of it.
##
## Damage is rolled once and shared, because it is one explosion.
static func resolve_area_attack(
	request: AttackRequest,
	targets: Array[AreaTarget],
	radius_m: float,
	tables: Tables,
	rng: Dice.RandomSource
) -> AreaResult:
	assert(radius_m > 0.0, "an area attack needs a radius")
	assert(request.ammo >= 1, "cannot throw what is not carried")

	var result := AreaResult.new()
	var events: Array[Dictionary] = [
		{
			"kind": "ammo_spent",
			"actor_id": request.attacker_id,
			"weapon": request.weapon.name,
			"amount": 1,
		}
	]

	var check := Dice.roll_check(rng)
	var attack_total: int = (
		request.attack_base + request.modifiers + request.wound_penalty + int(check["total"])
	)
	var defense := tables.ranged_dv(request.weapon.weapon_type, request.distance_m)
	var on_target := _meets_defense(attack_total, defense, "range")

	var scatter := 0
	if not on_target:
		scatter = rng.randint(1, int(EXTENDED_RULES["area_scatter_max_m"]))
		events.append(
			{
				"kind": "area_scattered",
				"actor_id": request.attacker_id,
				"amount": scatter,
			}
		)

	var card_lines := PackedStringArray(
		[
			"Throw: base %d + d10 %d = %d vs DV %d"
			% [request.attack_base, int(check["total"]), attack_total, defense]
		]
	)
	card_lines.append(
		"ON TARGET" if on_target else "SCATTERED %dm — it still went off." % scatter
	)

	var damage := Dice.damage_roll(request.weapon.damage_dice, rng)
	var raw_damage: int = int(damage["total"]) + request.weapon.damage_bonus
	var pieces := PackedStringArray()
	for value in damage["rolls"]:
		pieces.append(str(value))
	card_lines.append("Blast: %s = %d" % [" + ".join(pieces), raw_damage])

	result.on_target = on_target
	result.attack_rolls = check["rolls"]
	result.attack_total = attack_total
	result.defense = defense
	result.scatter_m = scatter
	result.damage_rolls = damage["rolls"]
	result.raw_damage = raw_damage

	for caught in targets:
		# Scatter moves the blast, so a target who was inside the radius can end
		# up outside it. Distance is measured from where the weapon actually landed.
		var reach := caught.distance_m + float(scatter)
		if reach > radius_m:
			card_lines.append("%s: outside the blast." % caught.target.target_id)
			continue

		var evaded := false
		if caught.evasion_base >= 0:
			var dive := Dice.roll_check(rng)
			var dive_total: int = caught.evasion_base + caught.wound_penalty + int(dive["total"])
			evaded = dive_total >= int(EXTENDED_RULES["area_evasion_dv"])

		var reaching := raw_damage
		if evaded:
			@warning_ignore("integer_division")
			reaching = raw_damage / int(EXTENDED_RULES["area_evasion_damage_divisor"])

		var armor_sp := caught.target.sp_at("body")
		var after_armor := maxi(
			int(RULES["min_damage_through_armor"]), reaching - armor_sp
		) if reaching > armor_sp else 0

		if after_armor > 0:
			events.append(
				{
					"kind": "armor_ablated",
					"target_id": caught.target.target_id,
					"location": "body",
					"amount": 1,
				}
			)
			events.append(
				{
					"kind": "damage_taken",
					"target_id": caught.target.target_id,
					"amount": after_armor,
				}
			)
			events.append_array(wound_events(caught.target, after_armor))

		result.hits.append(
			{
				"target_id": caught.target.target_id,
				"hp_damage": after_armor,
				"evaded": evaded,
			}
		)
		card_lines.append(
			"%s: %d - SP %d = %d%s"
			% [
				caught.target.target_id,
				reaching,
				armor_sp,
				after_armor,
				" (dived clear)" if evaded else "",
			]
		)

	result.events = events
	result.card_lines = card_lines
	return result


## The wound-state events a given amount of HP damage causes.
##
## Shared by the single-target and area paths so a grenade puts someone on Death
## Saves by exactly the rule a bullet does.
static func wound_events(target: TargetState, hp_damage: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var new_hp := target.hp - hp_damage
	@warning_ignore("integer_division")
	var serious_threshold := (target.max_hp - 1) / 2
	if target.hp > serious_threshold and serious_threshold >= new_hp:
		events.append({"kind": "seriously_wounded", "target_id": target.target_id})
	if new_hp <= 0:
		events.append(
			{
				"kind": "wound_state_set",
				"target_id": target.target_id,
				"state": "mortally_wounded",
			}
		)
		events.append({"kind": "death_save_due", "target_id": target.target_id})
	return events
