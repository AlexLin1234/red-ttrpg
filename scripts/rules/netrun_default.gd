class_name NetrunDefault
extends RefCounted

## Homebrew placeholder NET architecture content.
##
## These are NOT book data, exactly as [TablesDefault] is not. The ICE below is
## invented so a fresh install can run an architecture immediately; the names are
## deliberately generic descriptions of what a program does rather than the
## printed roster, and every number is a working value a GM who owns the book
## replaces in the architecture editor.

const HOMEBREW_PAGE := 0

## What a floor can be. The runner walks down through these.
const FLOOR_KINDS: Array[Dictionary] = [
	{
		"kind": "password",
		"label": "Password",
		"summary": "A locked door. Backdoor it, or find the key elsewhere.",
		"dv": 6,
	},
	{
		"kind": "file",
		"label": "File",
		"summary": "Something worth taking. Eye-Dee it first if its contents matter.",
		"dv": 6,
	},
	{
		"kind": "control_node",
		"label": "Control Node",
		"summary": "A hook into the building: doors, cameras, turrets, lights.",
		"dv": 6,
	},
	{
		"kind": "ice",
		"label": "ICE",
		"summary": "Something that fights back. Zap it, or slide past and hope.",
		"dv": 0,
	},
]

## Placeholder ICE. "black" ICE damages the netrunner rather than their deck.
const ICE: Dictionary = {
	"Watchdog":
	{
		"black": false,
		"rez": 15,
		"max_rez": 15,
		"attack": 4,
		"damage_dice": 1,
		"effect": "Raises the alarm: every later floor of this run is at +2 DV.",
		"page": HOMEBREW_PAGE,
	},
	"Tracer":
	{
		"black": false,
		"rez": 20,
		"max_rez": 20,
		"attack": 5,
		"damage_dice": 1,
		"effect": "Advances the trace by 2 every turn it survives.",
		"page": HOMEBREW_PAGE,
	},
	"Shutter":
	{
		"black": false,
		"rez": 25,
		"max_rez": 25,
		"attack": 6,
		"damage_dice": 2,
		"effect": "Closes the floor behind the runner; sliding up costs two actions.",
		"page": HOMEBREW_PAGE,
	},
	"Mauler":
	{
		"black": true,
		"rez": 25,
		"max_rez": 25,
		"attack": 7,
		"damage_dice": 3,
		"effect": "Damage goes to the netrunner, not the deck.",
		"page": HOMEBREW_PAGE,
	},
	"Sentinel":
	{
		"black": true,
		"rez": 30,
		"max_rez": 30,
		"attack": 8,
		"damage_dice": 3,
		"effect": "Damage goes to the netrunner. Cannot be slid past while rezzed.",
		"page": HOMEBREW_PAGE,
	},
	"Nightmare":
	{
		"black": true,
		"rez": 35,
		"max_rez": 35,
		"attack": 9,
		"damage_dice": 4,
		"effect": "Damage goes to the netrunner, and a hit ends their turn.",
		"page": HOMEBREW_PAGE,
	},
}

## How deep an architecture of each difficulty tends to run, and how hard its
## doors are. Used when the GM asks for a generated one.
const DIFFICULTIES: Array[Dictionary] = [
	{"key": "basic", "label": "Basic", "floors": 3, "dv": 6, "ice": ["Watchdog"]},
	{"key": "standard", "label": "Standard", "floors": 5, "dv": 8, "ice": ["Watchdog", "Tracer"]},
	{
		"key": "uncommon",
		"label": "Uncommon",
		"floors": 7,
		"dv": 10,
		"ice": ["Tracer", "Shutter", "Mauler"],
	},
	{
		"key": "advanced",
		"label": "Advanced",
		"floors": 9,
		"dv": 12,
		"ice": ["Shutter", "Mauler", "Sentinel", "Nightmare"],
	},
]


static func difficulty(key: String) -> Dictionary:
	for entry in DIFFICULTIES:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return DIFFICULTIES[1]


static func floor_kind(kind: String) -> Dictionary:
	for entry in FLOOR_KINDS:
		if String((entry as Dictionary)["kind"]) == kind:
			return entry
	return FLOOR_KINDS[0]


static func ice_names() -> Array:
	var names := ICE.keys()
	names.sort()
	return names


static func ice(name: String) -> Dictionary:
	var profile: Dictionary = (ICE.get(name, ICE["Watchdog"]) as Dictionary).duplicate(true)
	profile["name"] = name
	return profile


## Everything a campaign that has never seen the Netrun screen needs to have one.
## The whole of what a campaign may replace: the ICE, the floor kinds, and the
## difficulty bands a rolled architecture is built from.
static func document() -> Dictionary:
	return {
		"ice": ICE.duplicate(true),
		"floor_kinds": FLOOR_KINDS.duplicate(true),
		"difficulties": DIFFICULTIES.duplicate(true),
		"source": "homebrew placeholder — not book data",
	}


## Roll an architecture the GM can then edit.
##
## A generated ladder is a starting point, not a result: it alternates doors and
## defenders so the shape is immediately playable, and every floor is editable
## afterwards. The last floor is always worth reaching.
## Kept for the campaigns that never replaced anything; the reader's own
## generator is what the screen calls, so a rolled ladder uses whichever
## difficulty bands and floor kinds are actually in force.
static func generate_architecture(name: String, difficulty_key: String, rng: Dice.RandomSource) -> Dictionary:
	return NetrunTables.new(document()).generate_architecture(name, difficulty_key, rng)


static func _generate(
	name: String, spec: Dictionary, rng: Dice.RandomSource, kind_label: Callable
) -> Dictionary:
	var depth := int(spec["floors"])
	var dv := int(spec["dv"])
	var pool: Array = spec["ice"]
	var floors: Array = []
	var stamp := Time.get_ticks_usec()

	for level in range(1, depth + 1):
		var floor_id := "floor-%d-%d" % [stamp, level]
		if level == depth:
			floors.append(
				{
					"id": floor_id,
					"kind": "file",
					"name": "The thing worth the run",
					"level": level,
					"branch": 0,
					"dv": dv + 2,
				}
			)
			continue
		# Doors on the odd floors, defenders on the even ones.
		if level % 2 == 1:
			var doors := PackedStringArray(["password", "control_node"])
			var kind := "password" if level == 1 else String(doors[rng.randint(0, 1)])
			floors.append(
				{
					"id": floor_id,
					"kind": kind,
					"name": String(kind_label.call(kind)),
					"level": level,
					"branch": 0,
					"dv": dv,
				}
			)
		else:
			var pick := String(pool[rng.randint(0, pool.size() - 1)])
			floors.append(
				{
					"id": floor_id,
					"kind": "ice",
					"ice_id": pick,
					"name": pick,
					"level": level,
					"branch": 0,
				}
			)

	return {
		"id": "arch-%d" % stamp,
		"name": name,
		"difficulty": String(spec["key"]),
		"notes": "",
		"floors": floors,
	}
