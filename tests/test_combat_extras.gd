extends RefCounted

## Ammunition types, melee, suppressive fire and area attacks.
##
## The rule these cases exist to protect: every one of these is still an attack,
## so it still spends ammunition, still records an exact inverse, and still puts
## a character on Death Saves by the same arithmetic a bullet does.

const Harness := preload("res://tests/harness.gd")


static func _tables(dv := 13) -> Tables:
	var band := [{"min_m": 0.0, "max_m": 1000.0, "dv": dv}]
	var body := {}
	var head := {}
	for roll in range(2, 13):
		body[str(roll)] = {"name": "Test body injury %d" % roll, "page": 187}
		head[str(roll)] = {"name": "Test head injury %d" % roll, "page": 187}
	return Tables.new(
		{
			"ranged_dv": {"pistol": band, "melee": band, "thrown": band, "smg": band},
			"autofire_dv": {"smg": band},
			"weapons": {},
			"critical_injuries": {"body": body, "head": head},
		}
	)


static func _target(sp := 0, hp := 40) -> Resolver.TargetState:
	return Resolver.TargetState.new("mook", hp, 40, {"body": sp}, 0)


static func _pistol() -> Resolver.Weapon:
	return Resolver.Weapon.new("Heavy Pistol", "pistol", 3, 2, 8, -1)


static func _request(
	weapon: Resolver.Weapon, target: Resolver.TargetState, mode := "single", distance := 5.0
) -> Resolver.AttackRequest:
	return Resolver.AttackRequest.new(
		"solo", target, weapon, 14, distance, 30, "body", mode, -1, 0
	)


static func run(h: Harness) -> void:
	h.describe("combat extras")

	_ammunition(h)
	_melee(h)
	_suppression(h)
	_area(h)
	_through_the_encounter(h)


static func _ammunition(h: Harness) -> void:
	var tables := _tables()

	h.it("leaves a basic round resolving exactly as it always did")
	# Two 6s on the damage roll would trigger a critical, so the sequence below
	# avoids them: this case is about armour arithmetic and nothing else.
	var basic := _request(_pistol(), _target(4))
	var result := Resolver.resolve_attack(
		basic, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	h.check(result.hit, "the attack landed")
	# 15 raw against SP 4 leaves 11.
	h.equal(result.raw_damage, 15, "raw damage")
	h.equal(result.armor_sp, 4, "the SP it met")
	h.equal(result.hp_damage, 11, "damage through armour")

	h.it("halves the armour armour-piercing meets, and halves what gets past it")
	var piercing := _request(_pistol(), _target(4))
	piercing.ammo_type = "armor_piercing"
	var pierced := Resolver.resolve_attack(
		piercing, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	# SP 4 becomes 2, so 15 - 2 = 13, then halved to 6.
	h.equal(pierced.armor_sp, 2, "SP after piercing")
	h.equal(pierced.hp_damage, 6, "damage after the trade")

	h.it("rounds armour-piercing SP up, so one point of plate still counts")
	var one_point := _request(_pistol(), _target(1))
	one_point.ammo_type = "armor_piercing"
	var against_one := Resolver.resolve_attack(
		one_point, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	h.equal(against_one.armor_sp, 1, "SP 1 halves to 1, not 0")

	h.it("doubles expansive against someone wearing nothing")
	var expansive := _request(_pistol(), _target(0))
	expansive.ammo_type = "expansive"
	var opened := Resolver.resolve_attack(
		expansive, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	h.equal(opened.hp_damage, 30, "15 doubled")

	h.it("makes expansive no better than basic against armour, and never ablates it")
	var against_armor := _request(_pistol(), _target(4))
	against_armor.ammo_type = "expansive"
	var stopped := Resolver.resolve_attack(
		against_armor, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	h.equal(stopped.hp_damage, 11, "the same 11 a basic round does")
	var ablated := false
	for event in stopped.events:
		if String((event as Dictionary)["kind"]) == "armor_ablated":
			ablated = true
	h.check(not ablated, "expansive left no mark on the armour")

	h.it("sets a target alight with incendiary rather than hitting harder")
	var incendiary := _request(_pistol(), _target(4))
	incendiary.ammo_type = "incendiary"
	var burning := Resolver.resolve_attack(
		incendiary, tables, Dice.FixedRandom.new([9, 5, 5, 5])
	)
	h.equal(burning.hp_damage, 11, "the hit itself is unchanged")
	var ignited := {}
	for event in burning.events:
		if String((event as Dictionary)["kind"]) == "ignited":
			ignited = event
	h.check(not ignited.is_empty(), "the target caught fire")
	h.equal(int(ignited.get("rounds", 0)), 3, "how long it burns")


static func _melee(h: Harness) -> void:
	var tables := _tables()

	h.it("adds the attacker's BODY to a melee hit")
	var blade := Resolver.Weapon.new("Monoblade", "melee", 2, 2, 1, -1)
	var swing := _request(blade, _target(0), "melee", 1.0)
	swing.melee_bonus = 3
	var cut := Resolver.resolve_attack(swing, tables, Dice.FixedRandom.new([9, 5, 5]))
	h.check(cut.hit, "the swing landed")
	# Two dice of 5 is 10, plus the arm behind it.
	h.equal(cut.raw_damage, 13, "damage with BODY behind it")

	h.it("leaves a ranged attack alone even when the attacker is strong")
	var shot := _request(_pistol(), _target(0), "single")
	shot.melee_bonus = 3
	var fired := Resolver.resolve_attack(shot, tables, Dice.FixedRandom.new([9, 5, 5, 5]))
	h.equal(fired.raw_damage, 15, "no BODY on a trigger pull")


static func _suppression(h: Harness) -> void:
	var tables := _tables()
	var smg := Resolver.Weapon.new("Heavy SMG", "smg", 3, 1, 40, 3)

	h.it("spends a burst to suppress rather than to wound")
	var burst := _request(smg, _target(0), "suppressive")
	var pinned := Resolver.resolve_attack(burst, tables, Dice.FixedRandom.new([9]))
	h.check(pinned.hit, "the burst landed")
	h.equal(pinned.hp_damage, 0, "suppression does no damage")
	var kinds := PackedStringArray()
	for event in pinned.events:
		kinds.append(String((event as Dictionary)["kind"]))
	h.contains(kinds, "suppressed", "the target is pinned")
	h.contains(kinds, "ammo_spent", "the burst was paid for")

	h.it("charges suppressive fire a full burst of ammunition")
	h.equal(Resolver.ammo_cost_for("suppressive"), 10, "suppressive")
	h.equal(Resolver.ammo_cost_for("autofire"), 10, "autofire")
	h.equal(Resolver.ammo_cost_for("single"), 1, "single")
	h.equal(Resolver.ammo_cost_for("melee"), 1, "melee")

	h.it("misses a suppression check without pinning anyone")
	var weak := Resolver.AttackRequest.new(
		"solo", _target(0), smg, 1, 5.0, 30, "body", "suppressive", -1, 0
	)
	var missed := Resolver.resolve_attack(weak, tables, Dice.FixedRandom.new([1]))
	h.check(not missed.hit, "the burst went wide")


static func _area(h: Harness) -> void:
	var tables := _tables()
	var grenade := Resolver.Weapon.new("Frag Grenade", "thrown", 6, 1, 1, -1)

	h.it("catches everyone inside the blast with one damage roll")
	var thrower := Resolver.AttackRequest.new(
		"solo", _target(0), grenade, 14, 10.0, 1, "body", "single", -1, 0
	)
	var caught: Array[Resolver.AreaTarget] = [
		Resolver.AreaTarget.new(Resolver.TargetState.new("near", 40, 40, {"body": 0}, 0), 1.0),
		Resolver.AreaTarget.new(Resolver.TargetState.new("far", 40, 40, {"body": 0}, 0), 9.0),
	]
	# A 9 lands it, then six damage dice.
	var blast := Resolver.resolve_area_attack(
		thrower, caught, 4.0, tables, Dice.FixedRandom.new([9, 3, 3, 3, 3, 3, 3])
	)
	h.check(blast.on_target, "the throw landed where it was aimed")
	h.equal(blast.raw_damage, 18, "one roll, shared")
	h.equal(blast.hits.size(), 1, "only the one standing close enough")
	h.equal(String((blast.hits[0] as Dictionary)["target_id"]), "near", "who it caught")
	h.equal(int((blast.hits[0] as Dictionary)["hp_damage"]), 18, "unarmoured, so all of it")

	h.it("scatters a missed throw and still goes off")
	var short_throw := Resolver.AttackRequest.new(
		"solo", _target(0), grenade, 1, 10.0, 1, "body", "single", -1, 0
	)
	var standing: Array[Resolver.AreaTarget] = [
		Resolver.AreaTarget.new(Resolver.TargetState.new("near", 40, 40, {"body": 0}, 0), 1.0),
	]
	var stray := Resolver.resolve_area_attack(
		short_throw, standing, 4.0, tables, Dice.FixedRandom.new([1, 2, 3, 3, 3, 3, 3, 3])
	)
	h.check(not stray.on_target, "the throw missed")
	h.check(stray.scatter_m > 0, "it landed somewhere else")
	var scattered := false
	for event in stray.events:
		if String((event as Dictionary)["kind"]) == "area_scattered":
			scattered = true
	h.check(scattered, "the scatter was recorded")

	h.it("halves the blast for anyone who dives clear")
	var aimed := Resolver.AttackRequest.new(
		"solo", _target(0), grenade, 14, 10.0, 1, "body", "single", -1, 0
	)
	var nimble: Array[Resolver.AreaTarget] = [
		Resolver.AreaTarget.new(
			Resolver.TargetState.new("quick", 40, 40, {"body": 0}, 0), 1.0, 14
		),
	]
	# 9 to land it, six 3s of damage, then a 9 on the dive: 14 + 9 clears DV 15.
	var dived := Resolver.resolve_area_attack(
		aimed, nimble, 4.0, tables, Dice.FixedRandom.new([9, 3, 3, 3, 3, 3, 3, 9])
	)
	h.equal(dived.hits.size(), 1, "still caught")
	h.check(bool((dived.hits[0] as Dictionary)["evaded"]), "they got clear")
	h.equal(int((dived.hits[0] as Dictionary)["hp_damage"]), 9, "half of 18")

	h.it("puts an area victim on Death Saves by the same rule a bullet does")
	var lethal := Resolver.AttackRequest.new(
		"solo", _target(0), grenade, 14, 10.0, 1, "body", "single", -1, 0
	)
	var frail: Array[Resolver.AreaTarget] = [
		Resolver.AreaTarget.new(Resolver.TargetState.new("frail", 6, 40, {"body": 0}, 0), 1.0),
	]
	var down := Resolver.resolve_area_attack(
		lethal, frail, 4.0, tables, Dice.FixedRandom.new([9, 3, 3, 3, 3, 3, 3])
	)
	var kinds := PackedStringArray()
	for event in down.events:
		kinds.append(String((event as Dictionary)["kind"]))
	h.contains(kinds, "death_save_due", "the blast put them on the clock")
	h.contains(kinds, "wound_state_set", "and mortally wounded them")


static func _through_the_encounter(h: Harness) -> void:
	# The resolver cases above prove the arithmetic. These prove the encounter
	# carries it: a pinned actor cannot act, fire ticks on their turn, and both
	# come back on undo.
	var cast := {
		"solo":
		{
			"name": "Rache",
			"hp": 40,
			"max_hp": 40,
			"attack_base": 14,
			"evasion_base": 10,
			"stats": {"BODY": 8, "REF": 8, "LUCK": 6},
			"luck_available": 6,
			"weapons": {"Heavy SMG": {"ammo": 40}},
		},
		"mook":
		{
			"name": "Mook",
			"hp": 30,
			"max_hp": 30,
			"attack_base": 8,
			"evasion_base": 8,
			"stats": {"BODY": 5, "REF": 5, "LUCK": 2},
			"weapons": {"Heavy Pistol": {"ammo": 8}},
		},
	}

	h.it("refuses an action from someone who is pinned, and lets the table waive it")
	var encounter := Encounter.new(_tables(), cast, Dice.FixedRandom.new([5]))
	var pinned_state := encounter.session.state
	(pinned_state["actors"]["mook"] as Dictionary)["suppressed"] = true
	var refusal := encounter.check_action("mook", "attack", {"weapon": "Heavy Pistol"})
	h.equal(String(refusal["code"]), "suppressed", "the reason")
	h.check(bool(refusal["override"]), "a ruling the table can waive")

	h.it("spends Luck through the encounter and gives it back on undo")
	var luck_fight := Encounter.new(_tables(), cast, Dice.FixedRandom.new([5]))
	luck_fight.spend_luck("solo", 2)
	h.equal(int(luck_fight.actor("solo")["luck_available"]), 4, "spent")
	luck_fight.undo()
	h.equal(int(luck_fight.actor("solo")["luck_available"]), 6, "given back")

	h.it("refuses to spend Luck a character does not have, without recording anything")
	var broke := Encounter.new(_tables(), cast, Dice.FixedRandom.new([5]))
	broke.spend_luck("mook", 9)
	h.equal(int(broke.actor("mook")["luck_available"]), 2, "untouched")
	h.check(not broke.can_undo(), "and nothing to take back")

	h.it("lifts suppression and burns a target at the start of their turn")
	var burning := Encounter.new(_tables(), cast, Dice.FixedRandom.new([9, 2, 5, 5]))
	burning.roll_initiative()
	var state := burning.session.state
	var mook: Dictionary = state["actors"]["mook"]
	mook["suppressed"] = true
	mook["burning"] = {"amount": 2, "rounds": 2}
	var hp_before := int(burning.actor("mook")["hp"])

	# Walk the order round until the mook's turn comes up.
	for _index in 4:
		if String(burning.current_turn().get("actor_id", "")) == "mook":
			break
		burning.end_turn()

	h.check(not bool(burning.actor("mook")["suppressed"]), "the pin lifted")
	h.equal(int(burning.actor("mook")["hp"]), hp_before - 2, "and the fire cost them")
	var still: Dictionary = burning.actor("mook").get("burning", {})
	h.equal(int(still.get("rounds", 0)), 1, "with one round left to burn")

	h.it("takes the burn back with the turn that caused it")
	burning.undo()
	h.equal(int(burning.actor("mook")["hp"]), hp_before, "healed by the undo")
	h.check(bool(burning.actor("mook")["suppressed"]), "and pinned again")
