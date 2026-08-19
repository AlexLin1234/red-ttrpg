class_name TablesDefault
extends RefCounted

## Homebrew placeholder tables.
##
## These are NOT book data. They exist so a fresh install can resolve a fight
## immediately and every screen has something to draw. Weapon names are
## deliberately generic categories rather than a printed catalogue; a GM who owns
## the book replaces these in the table editor or imports their own JSON.

const HOMEBREW_PAGE := 0

const _BODY_INJURIES: PackedStringArray = [
	"Cracked Ribs",
	"Broken Ribs",
	"Torn Muscle",
	"Punctured Lung",
	"Foreign Object",
	"Broken Arm",
	"Dislocated Shoulder",
	"Spinal Bruise",
	"Ruptured Organ",
	"Shattered Pelvis",
	"Crushed Chest",
]

const _HEAD_INJURIES: PackedStringArray = [
	"Split Lip",
	"Broken Nose",
	"Concussion",
	"Damaged Ear",
	"Damaged Eye",
	"Cracked Skull",
	"Fractured Jaw",
	"Whiplash",
	"Lost Eye",
	"Brain Trauma",
	"Crushed Skull",
]


## `[max_metres, dv]` pairs read as "out to this distance, this DV".
static func _bands(pairs: Array) -> Array:
	var bands: Array = []
	var minimum := 0.0
	for pair in pairs:
		bands.append({"min_m": minimum, "max_m": float(pair[0]), "dv": int(pair[1])})
		minimum = float(pair[0])
	return bands


static func _injuries(names: PackedStringArray) -> Dictionary:
	var table := {}
	for index in names.size():
		table[str(index + 2)] = {"name": names[index], "page": HOMEBREW_PAGE}
	return table


static func _weapon(
	range_type: String,
	skill: String,
	damage_dice: int,
	magazine: int,
	rof: int,
	hands: int,
	concealable: bool,
	autofire_rating: int,
) -> Dictionary:
	return {
		"range_type": range_type,
		"skill": skill,
		"damage_dice": damage_dice,
		"magazine": magazine,
		"rof": rof,
		"hands": hands,
		"concealable": concealable,
		"autofire_rating": autofire_rating,
		"page": HOMEBREW_PAGE,
	}


static func document() -> Dictionary:
	return {
		"source": "homebrew placeholder — not book data",
		"ranged_dv":
		{
			"pistol": _bands([[6, 11], [12, 13], [25, 15], [50, 20], [100, 25]]),
			"smg": _bands([[6, 11], [12, 12], [25, 15], [50, 18], [100, 22]]),
			"shotgun": _bands([[6, 11], [12, 14], [25, 18], [50, 24]]),
			"assault_rifle": _bands([[6, 15], [12, 13], [25, 13], [50, 15], [100, 18], [200, 22]]),
			"sniper_rifle":
			_bands([[6, 20], [12, 17], [25, 15], [50, 15], [100, 15], [200, 17], [400, 21]]),
			"bow": _bands([[6, 13], [12, 14], [25, 16], [50, 20], [100, 24]]),
			"thrown": _bands([[6, 12], [12, 14], [25, 18], [50, 24]]),
			"melee": _bands([[2, 10]]),
		},
		"autofire_dv":
		{
			"smg": _bands([[6, 15], [12, 17], [25, 20], [50, 25]]),
			"assault_rifle": _bands([[6, 17], [12, 17], [25, 19], [50, 22], [100, 26]]),
		},
		"weapons":
		{
			"Light Sidearm": _weapon("pistol", "Handgun", 1, 12, 2, 1, true, -1),
			"Service Sidearm": _weapon("pistol", "Handgun", 2, 12, 2, 1, true, -1),
			"Heavy Sidearm": _weapon("pistol", "Handgun", 3, 8, 2, 1, true, -1),
			"Hand Cannon": _weapon("pistol", "Handgun", 4, 8, 1, 2, false, -1),
			"Compact SMG": _weapon("smg", "Handgun", 2, 30, 1, 1, true, 3),
			"Heavy SMG": _weapon("smg", "Shoulder Arms", 3, 40, 1, 2, false, 3),
			"Combat Shotgun": _weapon("shotgun", "Shoulder Arms", 5, 4, 1, 2, false, -1),
			"Service Rifle": _weapon("assault_rifle", "Shoulder Arms", 5, 25, 1, 2, false, 4),
			"Marksman Rifle": _weapon("sniper_rifle", "Shoulder Arms", 5, 4, 1, 2, false, -1),
			"Hunting Bow": _weapon("bow", "Archery", 4, 1, 1, 2, false, -1),
			"Frag Grenade": _weapon("thrown", "Athletics", 6, 1, 1, 1, true, -1),
			"Monoblade": _weapon("melee", "Melee Weapon", 2, 1, 2, 1, true, -1),
			"Heavy Melee": _weapon("melee", "Melee Weapon", 3, 1, 2, 2, false, -1),
		},
		"armor":
		{
			"Kevlar Weave": {"sp": 7, "penalty": {}, "page": HOMEBREW_PAGE},
			"Light Plate": {"sp": 11, "penalty": {}, "page": HOMEBREW_PAGE},
			"Heavy Plate": {"sp": 13, "penalty": {"REF": -2, "DEX": -2, "MOVE": -2}, "page": HOMEBREW_PAGE},
			"Exoshell": {"sp": 18, "penalty": {"REF": -4, "DEX": -4, "MOVE": -4}, "page": HOMEBREW_PAGE},
		},
		"aimed_shots":
		{
			"head": {"modifier": -8, "page": HOMEBREW_PAGE},
			"left_arm": {"modifier": -8, "page": HOMEBREW_PAGE},
			"right_arm": {"modifier": -8, "page": HOMEBREW_PAGE},
			"left_leg": {"modifier": -8, "page": HOMEBREW_PAGE},
			"right_leg": {"modifier": -8, "page": HOMEBREW_PAGE},
		},
		# Materials and values come from the cover builder in the UI mockups.
		"cover":
		{
			"Concrete": {"hp": 30, "sp": 15, "page": HOMEBREW_PAGE},
			"Steel Plate": {"hp": 40, "sp": 20, "page": HOMEBREW_PAGE},
			"Glass": {"hp": 10, "sp": 2, "page": HOMEBREW_PAGE},
			"Sheet Metal": {"hp": 15, "sp": 7, "page": HOMEBREW_PAGE},
			"Wood Crate": {"hp": 12, "sp": 5, "page": HOMEBREW_PAGE},
			"Vehicle Hulk": {"hp": 50, "sp": 12, "page": HOMEBREW_PAGE},
		},
		"critical_injuries": {"body": _injuries(_BODY_INJURIES), "head": _injuries(_HEAD_INJURIES)},
	}


static func tables() -> Tables:
	return Tables.new(document())
