class_name GMTools
extends RefCounted

## What a GM does between the rules: watches the party, counts down to trouble,
## and invents people and pockets on the spot.
##
## None of this is in the book's machinery. A fight is the resolver's and a
## month's rent is Lifestyle's; this is the layer above, where the GM wants to
## know who would have noticed the tail without asking five players to roll
## Perception and telling them all something is up.
##
## The tables are homebrew placeholders, exactly as [EncounterTables]'s are.

# -- the party at a glance ---------------------------------------------------------


## One row per player character, in the numbers a GM asks for mid-scene.
static func party_overview(characters: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in characters:
		var character: Dictionary = entry
		if String(character.get("kind", "")) != "pc":
			continue
		var armor: Dictionary = character.get("armor", {})
		var state := String(
			character.get(
				"wound_state",
				Mortality.state_for(int(character.get("hp", 0)), int(character.get("max_hp", 1)))
			)
		)
		rows.append(
			{
				"id": String(character.get("id", "")),
				"name": String(character.get("name", "")),
				"role": String(character.get("role", "")),
				"hp": int(character.get("hp", 0)),
				"max_hp": int(character.get("max_hp", 0)),
				"wound_state": state,
				"wound_label": Mortality.label(state),
				"head_sp": _sp_at(armor, "head"),
				"body_sp": _sp_at(armor, "body"),
				"humanity": int(character.get("humanity", 0)),
				"max_humanity": int(character.get("max_humanity", 0)),
				"luck": Luck.available(character),
				"luck_pool": Luck.pool(character),
				"cash": int(character.get("cash", 0)),
				"ip": int(character.get("improvement_points", 0)),
				"reputation": int(character.get("reputation", 0)),
			}
		)
	return rows


static func _sp_at(armor: Dictionary, location: String) -> int:
	var worn: Variant = armor.get(location, {})
	return int((worn as Dictionary).get("sp", 0)) if worn is Dictionary else 0


## Every skill a group check can be called on, by name.
static func skill_names() -> PackedStringArray:
	var names := PackedStringArray()
	for entry in CharacterRules.SKILLS:
		if not bool((entry as Dictionary).get("specialized", false)):
			names.append(String((entry as Dictionary)["name"]))
	names.sort()
	return names


## Roll one skill for every player character, behind the screen.
##
## Someone without the skill rolls the bare stat behind it rather than being
## skipped: "you have no Perception" is not the same as "you cannot look".
##
## Returns {"ok", "skill", "dv", "results", "passed", "summary"}; a result is
## {"id", "name", "total", "base", "trained", "success", "text"}.
static func group_check(
	characters: Array, skill: String, modifier: int, dv: int, rng: Dice.RandomSource
) -> Dictionary:
	var definition := CharacterRules.skill_definition(skill)
	if definition.is_empty():
		return {"ok": false, "error": "%s is not a skill." % skill}
	var stat_key := String(definition.get("stat", ""))

	var results: Array[Dictionary] = []
	var passed := PackedStringArray()
	for entry in characters:
		var character: Dictionary = entry
		if String(character.get("kind", "")) != "pc":
			continue
		var stat_value := int((character.get("stats", {}) as Dictionary).get(stat_key, 0))
		var owned := CharacterRules.selected_skill(character, skill)
		var level := int(owned.get("level", 0))
		var roll := Dice.roll_check(rng)
		var total := stat_value + level + modifier + int(roll["total"])
		var faces: PackedInt32Array = roll["rolls"]
		var dice_text := str(faces[0])
		if faces.size() > 1:
			dice_text = "%d%s%d" % [faces[0], "+" if faces[0] == 10 else "−", faces[1]]
		var success: Variant = total > dv if dv > 0 else null
		if success == true:
			passed.append(String(character.get("name", "")))
		results.append(
			{
				"id": String(character.get("id", "")),
				"name": String(character.get("name", "")),
				"total": total,
				"base": stat_value + level,
				"trained": not owned.is_empty(),
				"critical": faces[0] == 10,
				"fumble": faces[0] == 1,
				"success": success,
				"text":
				(
					"%s %d + %s %d%s + d10 %s = %d"
					% [
						stat_key,
						stat_value,
						skill,
						level,
						"" if modifier == 0 else " %+d" % modifier,
						dice_text,
						total,
					]
				),
			}
		)
	if results.is_empty():
		return {"ok": false, "error": "There are no player characters to roll for."}

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["total"]) > int(b["total"]))
	var summary := "%s: best %s with %d" % [skill, results[0]["name"], int(results[0]["total"])]
	if dv > 0:
		summary = (
			"%s vs DV %d: %s"
			% [skill, dv, "nobody made it" if passed.is_empty() else ", ".join(passed) + " made it"]
		)
	return {
		"ok": true,
		"skill": skill,
		"dv": dv,
		"results": results,
		"passed": passed,
		"summary": summary,
	}


# -- countdown clocks ---------------------------------------------------------------

const CLOCK_MIN_SEGMENTS := 2
const CLOCK_MAX_SEGMENTS := 12


## Make sure the campaign carries a well-formed list of clocks.
static func ensure_clocks(campaign: Dictionary) -> Array:
	var raw: Variant = campaign.get("clocks", [])
	var clean: Array = []
	if raw is Array:
		for value in raw as Array:
			if not value is Dictionary:
				continue
			var clock: Dictionary = value
			clock["id"] = String(clock.get("id", "clock-%d" % clean.size()))
			clock["name"] = String(clock.get("name", "Clock"))
			clock["segments"] = clampi(
				int(clock.get("segments", 4)), CLOCK_MIN_SEGMENTS, CLOCK_MAX_SEGMENTS
			)
			clock["filled"] = clampi(int(clock.get("filled", 0)), 0, int(clock["segments"]))
			clean.append(clock)
	campaign["clocks"] = clean
	return clean


## Start a clock: a name for what is coming, and how many ticks until it does.
static func add_clock(campaign: Dictionary, name: String, segments: int) -> Dictionary:
	var clocks := ensure_clocks(campaign)
	var label := name.strip_edges()
	if label == "":
		label = "Clock %d" % (clocks.size() + 1)
	var serial := int(campaign.get("clock_serial", 0)) + 1
	campaign["clock_serial"] = serial
	var clock := {
		"id": "clock-%d" % serial,
		"name": label,
		"segments": clampi(segments, CLOCK_MIN_SEGMENTS, CLOCK_MAX_SEGMENTS),
		"filled": 0,
	}
	clocks.append(clock)
	return clock


static func clock_by_id(campaign: Dictionary, id: String) -> Dictionary:
	for clock in ensure_clocks(campaign):
		if String((clock as Dictionary)["id"]) == id:
			return clock
	return {}


## Move a clock, bounded at both ends, and say whether this is what filled it.
static func tick_clock(campaign: Dictionary, id: String, delta: int) -> Dictionary:
	var clock := clock_by_id(campaign, id)
	if clock.is_empty():
		return {"ok": false, "error": "That clock is gone."}
	var before := int(clock["filled"])
	var after := clampi(before + delta, 0, int(clock["segments"]))
	clock["filled"] = after
	return {
		"ok": true,
		"clock": clock,
		"moved": after - before,
		"just_filled": after == int(clock["segments"]) and before < after,
	}


static func remove_clock(campaign: Dictionary, id: String) -> bool:
	var clocks := ensure_clocks(campaign)
	for index in clocks.size():
		if String((clocks[index] as Dictionary)["id"]) == id:
			clocks.remove_at(index)
			return true
	return false


# -- people, on the spot ------------------------------------------------------------

const NPC_FIRST: PackedStringArray = [
	"Ada", "Bao", "Cass", "Dmitri", "Esi", "Farid", "Greta", "Hiro", "Imani", "Joss",
	"Kaz", "Lupe", "Mako", "Nour", "Oleg", "Priya", "Quinn", "Rosa", "Sef", "Tomas",
]
const NPC_LAST: PackedStringArray = [
	"Abara", "Brandt", "Castillo", "Dao", "Eze", "Fontaine", "Guerrero", "Havel", "Ito",
	"Jansen", "Kowal", "Lindqvist", "Mbeki", "Navarro", "Orlov", "Pham", "Reyes", "Sato",
	"Tran", "Volkov",
]
const NPC_HANDLES: PackedStringArray = [
	"Glitch", "Ratchet", "Halo", "Zero", "Moth", "Dime", "Static", "Brick", "Vex", "Sunny",
	"Ghost", "Patch",
]
const NPC_JOBS: PackedStringArray = [
	"street vendor", "ripperdoc's assistant", "courier", "bartender", "corporate clerk",
	"scavenger", "mechanic", "braindance editor", "security guard", "freelance journalist",
	"taxi driver", "fixer's runner", "tech scavenger", "club promoter", "street medic",
	"data broker",
]
const NPC_LOOKS: PackedStringArray = [
	"a chrome jaw that does not quite close", "mirrored optics, one of them cracked",
	"a rain poncho over a very good suit", "burn scars up one arm", "luminous tattoos, half dead",
	"a cheap cyberarm in the wrong skin tone", "a shaved head and a barcode behind the ear",
	"hand-painted body armour", "a medical mask and tired eyes", "too many rings",
	"a coat three sizes too big", "last year's corporate haircut",
]
const NPC_WANTS: PackedStringArray = [
	"to get out of the city", "to pay off someone dangerous", "to be noticed by the right people",
	"revenge for a sibling", "one clean night's sleep", "to keep a secret buried",
	"a replacement for failing chrome", "to sell what they are carrying", "to find someone who vanished",
	"to be left alone", "a better deal than the one they have", "to impress their crew",
]
const NPC_QUIRKS: PackedStringArray = [
	"never sits with their back to a door", "talks to their agent out loud", "counts everything twice",
	"laughs at the wrong moments", "is always eating", "quotes an old ad jingle",
	"will not shake hands", "keeps checking the sky", "answers questions with questions",
	"hums when nervous", "calls everyone 'choom' and means it", "is visibly coming down from something",
]
const NPC_SECRETS: PackedStringArray = [
	"is informing for a corp", "owes a gang more than they can pay", "is not who their ID says",
	"saw something they should not have", "is carrying stolen data", "is being followed right now",
	"already sold the party out once", "is dying, and knows it", "has a tracker they do not know about",
	"is related to someone the party hurt", "used to be somebody important", "has nothing to hide at all",
]
## What a walk-on is made of when the GM decides they matter enough for a sheet.
const NPC_PROFILE := {
	"label": "NPC",
	"stat": [3, 6],
	"hp": [20, 35],
	"sp": [0, 7],
	"skill": [2, 5],
	"weapon": "",
	"side": "neutral",
}


static func _pick(table: PackedStringArray, rng: Dice.RandomSource) -> String:
	return table[rng.randint(0, table.size() - 1)]


## A person: a name, what they do, what you notice, what they want, a habit,
## and the thing they are not saying.
static func roll_npc(rng: Dice.RandomSource) -> Dictionary:
	var name := "%s %s" % [_pick(NPC_FIRST, rng), _pick(NPC_LAST, rng)]
	# One in three goes by a handle, as people here do.
	if rng.randint(1, 3) == 1:
		var parts := name.split(" ")
		name = "%s \"%s\" %s" % [parts[0], _pick(NPC_HANDLES, rng), parts[1]]
	var job := _pick(NPC_JOBS, rng)
	var look := _pick(NPC_LOOKS, rng)
	var wants := _pick(NPC_WANTS, rng)
	var quirk := _pick(NPC_QUIRKS, rng)
	var secret := _pick(NPC_SECRETS, rng)
	return {
		"name": name,
		"job": job,
		"look": look,
		"wants": wants,
		"quirk": quirk,
		"secret": secret,
		"text":
		(
			"%s, %s. You notice %s. Wants %s; %s. Secretly %s."
			% [name, job, look, wants, quirk, secret]
		),
	}


## Give a rolled person a sheet, so they can be placed on a board or shot at.
static func npc_sheet(npc: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var sheet := EncounterTables.roll_mook(NPC_PROFILE, rng)
	sheet["id"] = "npc-%d" % Time.get_ticks_usec()
	sheet["name"] = String(npc.get("name", "Somebody"))
	sheet["role"] = String(npc.get("job", "NPC")).capitalize()
	sheet["kind"] = "npc"
	sheet["side"] = "neutral"
	sheet["tags"] = ["NPC", "ROLLED"]
	sheet["notes"] = (
		"Looks: %s. Wants %s. %s. Secret: %s."
		% [
			npc.get("look", ""),
			npc.get("wants", ""),
			String(npc.get("quirk", "")).substr(0, 1).to_upper() + String(npc.get("quirk", "")).substr(1),
			npc.get("secret", ""),
		]
	)
	return sheet


# -- pockets, on the spot -----------------------------------------------------------

const LOOT_MAX_ITEMS := 4


## What is in the bag: loose eddies and up to four things off the catalog,
## worth no more than [param budget] between them.
static func roll_loot(catalog: Array, budget: int, rng: Dice.RandomSource) -> Dictionary:
	if budget <= 0:
		return {"ok": false, "error": "Set a budget above zero."}
	# Somewhere between a tenth and a third of it is cash, in tens.
	var cash := int(rng.randint(budget / 10, budget / 3) / 10) * 10
	var remaining := budget - cash
	var items: Array[Dictionary] = []
	while items.size() < LOOT_MAX_ITEMS:
		var affordable: Array[Dictionary] = []
		for product in catalog:
			var price := int((product as Dictionary).get("price", 0))
			if price > 0 and price <= remaining:
				affordable.append(product)
		if affordable.is_empty():
			break
		var found: Dictionary = affordable[rng.randint(0, affordable.size() - 1)]
		items.append(found)
		remaining -= int(found["price"])
	var names := PackedStringArray()
	var worth := cash
	for item in items:
		names.append(String(item["name"]))
		worth += int(item["price"])
	var text := "%d eb" % cash
	if not names.is_empty():
		text += ", " + ", ".join(names)
	return {"ok": true, "cash": cash, "items": items, "worth": worth, "text": text}


## Put rolled loot on a sheet: the cash, and every item with its profile.
static func give_loot(character: Dictionary, loot: Dictionary) -> Dictionary:
	if character.is_empty():
		return {"ok": false, "error": "Choose who picks it up."}
	character["cash"] = int(character.get("cash", 0)) + int(loot.get("cash", 0))
	for item in loot.get("items", []):
		GearMarket.grant(character, item)
	return {"ok": true, "name": String(character.get("name", ""))}
