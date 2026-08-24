class_name EncounterTables
extends RefCounted

## Squads to drop on a board, and the street to roll one out of.
##
## The Forge could already roll a single mook, one at a time, and then the GM
## placed it by hand. A fight is rarely one mook. This rolls a whole squad off an
## archetype and hands back sheets ready to stand on the deck.
##
## Homebrew placeholders, like [TablesDefault] and [NetrunDefault]: the archetype
## names describe what a group is rather than reproducing a printed roster, and
## every band is a working value the GM can edit on the sheets afterwards.
##
## Everything rolls through a [Dice.RandomSource] rather than the global
## generator, so a squad can be rolled identically twice in a test.

const HOMEBREW_PAGE := 0

const MOOK_FIRST: PackedStringArray = [
	"Wire", "Chrome", "Sixer", "Rat", "Coil", "Dregs", "Static", "Hatch"
]
const MOOK_LAST: PackedStringArray = [
	"Vasquez", "Okoro", "Petrov", "Ng", "Hale", "Duarte", "Sable", "Kovac"
]

## What a squad is, in the only terms the board cares about: how many, how tough,
## and what they are shooting.
const SQUADS: Array[Dictionary] = [
	{
		"key": "boostergang",
		"label": "Boostergang",
		"summary": "Numerous, badly armoured, and entirely willing.",
		"count": [3, 6],
		"stat": [3, 6],
		"hp": [20, 30],
		"sp": [4, 7],
		"skill": [2, 5],
		"weapon": "Service Sidearm",
		"side": "hostile",
	},
	{
		"key": "corp_security",
		"label": "Corp Security",
		"summary": "Fewer, plated, and drilled.",
		"count": [2, 4],
		"stat": [5, 7],
		"hp": [30, 40],
		"sp": [11, 15],
		"skill": [4, 7],
		"weapon": "Assault Rifle",
		"side": "hostile",
	},
	{
		"key": "street_cops",
		"label": "Street Cops",
		"summary": "Two of them, and a radio.",
		"count": [2, 3],
		"stat": [4, 6],
		"hp": [25, 35],
		"sp": [7, 11],
		"skill": [3, 6],
		"weapon": "Heavy Sidearm",
		"side": "hostile",
	},
	{
		"key": "scavengers",
		"label": "Scavengers",
		"summary": "Desperate, close-in, and not shooting first.",
		"count": [3, 5],
		"stat": [3, 5],
		"hp": [18, 26],
		"sp": [2, 5],
		"skill": [2, 4],
		"weapon": "Light Sidearm",
		"side": "hostile",
	},
	{
		"key": "bystanders",
		"label": "Bystanders",
		"summary": "Nobody's enemy, and in the way of everything.",
		"count": [2, 5],
		"stat": [2, 4],
		"hp": [15, 22],
		"sp": [0, 2],
		"skill": [1, 2],
		"weapon": "",
		"side": "neutral",
	},
]

## Three rolls make a street encounter: who it is, what they want, and what is
## wrong with the situation.
const STREET_WHO: PackedStringArray = [
	"A Maelstrom crew arguing over a split",
	"A lone Trauma Team medic, off the clock",
	"Two NCPD officers running plates",
	"A Scav van idling with its doors open",
	"A Nomad convoy taking on water",
	"A street doc's queue spilling onto the pavement",
	"A corp courier who has stopped moving",
	"A Media with a drone and no permit",
	"A Fixer's runner, waiting for someone",
	"A crowd forming around something on the ground",
]

const STREET_WANTS: PackedStringArray = [
	"wants directions somewhere nobody goes",
	"wants a witness, and picked the party",
	"wants to sell something they should not have",
	"wants the party gone before something arrives",
	"wants help, and cannot say what with",
	"wants to know who the party works for",
	"wants payment for something the party did not do",
	"wants to hand something over and leave",
	"wants a ride out of the zone",
	"wants nothing, which is the problem",
]

const STREET_COMPLICATIONS: PackedStringArray = [
	"and there is a drone overhead",
	"and the street is about to be closed",
	"and one of them recognises a player",
	"and the rain has knocked the lights out",
	"and somebody is already bleeding",
	"and a rival crew is two minutes away",
	"and it is being recorded",
	"and the local Fixer has already been paid",
	"and the party is on the wrong side of a boundary",
	"and it is the third time this week",
]


static func squad(key: String) -> Dictionary:
	for entry in SQUADS:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return SQUADS[0]


static func _band(range_pair: Array, rng: Dice.RandomSource) -> int:
	return rng.randint(int(range_pair[0]), int(range_pair[1]))


static func _name_for(rng: Dice.RandomSource) -> String:
	return "%s %s" % [
		MOOK_FIRST[rng.randint(0, MOOK_FIRST.size() - 1)],
		MOOK_LAST[rng.randint(0, MOOK_LAST.size() - 1)],
	]


## One sheet, rolled inside an archetype's bands.
##
## [param ordinal] only decides the id, so a squad rolled in one go does not
## collide with itself on a fast machine.
static func roll_mook(profile: Dictionary, rng: Dice.RandomSource, ordinal := 0) -> Dictionary:
	var stats := CampaignSchema.empty_stats()
	for key in CampaignSchema.STAT_KEYS:
		stats[key] = _band(profile["stat"], rng)

	var max_hp := _band(profile["hp"], rng)
	var sp := _band(profile["sp"], rng)
	var armor := CampaignSchema.empty_armor()
	for location in Resolver.HIT_LOCATIONS:
		armor[location] = {"sp": sp, "ablated": false}

	var skill := _band(profile["skill"], rng)
	var weapon_name := String(profile.get("weapon", ""))
	var weapons: Array = []
	var gear: Array = []
	if weapon_name != "":
		var catalogue: Dictionary = TablesDefault.document()["weapons"]
		var stats_for: Dictionary = catalogue.get(weapon_name, {})
		var magazine := int(stats_for.get("magazine", 12))
		weapons.append(
			{
				"name": weapon_name,
				"ammo": magazine,
				"magazine": magazine,
				"weapon_type": String(stats_for.get("range_type", "pistol")),
				"damage_dice": int(stats_for.get("damage_dice", 2)),
				"rof": int(stats_for.get("rof", 2)),
				"autofire_rating": int(stats_for.get("autofire_rating", -1)),
			}
		)
		gear.append({"name": weapon_name, "kind": "weapon", "detail": "rolled"})

	return {
		"id": "mook-%d-%d" % [Time.get_ticks_usec(), ordinal],
		"name": _name_for(rng),
		"role": String(profile.get("label", "Mook")),
		"kind": "mook",
		"side": String(profile.get("side", "hostile")),
		"tags": ["MOOK", String(profile.get("label", "ROLLED")).to_upper()],
		"stats": stats,
		"skills":
		[
			{"name": "Handgun", "stat": "REF", "level": skill},
			{"name": "Evasion", "stat": "DEX", "level": maxi(1, skill - 2)},
		],
		"gear": gear,
		"armor": armor,
		"hp": max_hp,
		"max_hp": max_hp,
		"humanity": 30,
		"max_humanity": 40,
		"weapons": weapons,
	}


## A whole squad. [param count] of zero rolls the archetype's own size.
static func roll_squad(key: String, count: int, rng: Dice.RandomSource) -> Array[Dictionary]:
	var profile := squad(key)
	var size: int = count if count > 0 else _band(profile["count"], rng)
	var squad_members: Array[Dictionary] = []
	for index in size:
		squad_members.append(roll_mook(profile, rng, index))
	return squad_members


## Who is on this corner, what they want, and what is wrong with it.
static func roll_street(rng: Dice.RandomSource) -> Dictionary:
	var who := STREET_WHO[rng.randint(0, STREET_WHO.size() - 1)]
	var wants := STREET_WANTS[rng.randint(0, STREET_WANTS.size() - 1)]
	var complication := STREET_COMPLICATIONS[rng.randint(0, STREET_COMPLICATIONS.size() - 1)]
	return {
		"who": who,
		"wants": wants,
		"complication": complication,
		"text": "%s %s, %s." % [who, wants, complication],
	}
