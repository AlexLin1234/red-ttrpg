class_name Economy
extends RefCounted

## Character-to-character transfers and the weekly Hustle.
##
## A Hustle takes one free seven-day block, rolls a d6, and selects a payout by
## Role Ability Rank band. The table stores only functional numeric data; result
## descriptions are deliberately generic. Time advancement belongs to Store.

const HUSTLE_DAYS := 7

const HUSTLES := {
	"rockerboy": [
		[200, 300, 600], [0, 100, 300], [300, 500, 800],
		[300, 500, 800], [300, 500, 800], [200, 300, 600],
	],
	"solo": [
		[100, 200, 500], [200, 300, 600], [200, 300, 600],
		[100, 200, 500], [0, 100, 300], [100, 200, 500],
	],
	"netrunner": [
		[100, 200, 500], [200, 300, 600], [0, 100, 300],
		[200, 300, 600], [200, 300, 600], [200, 300, 600],
	],
	"tech": [
		[0, 100, 300], [100, 200, 500], [200, 300, 600],
		[100, 200, 500], [100, 200, 500], [100, 200, 500],
	],
	"medtech": [
		[100, 200, 500], [200, 300, 600], [100, 200, 500],
		[0, 100, 300], [200, 300, 600], [100, 200, 500],
	],
	"media": [
		[300, 500, 800], [200, 300, 600], [200, 300, 600],
		[200, 300, 600], [0, 100, 300], [300, 500, 800],
	],
	"lawman": [
		[100, 200, 500], [200, 300, 600], [0, 100, 300],
		[100, 200, 500], [200, 300, 600], [200, 300, 600],
	],
	"exec": [
		[300, 500, 800], [0, 100, 300], [200, 300, 600],
		[300, 500, 800], [300, 500, 800], [200, 300, 600],
	],
	"fixer": [
		[200, 300, 600], [200, 300, 600], [200, 300, 600],
		[0, 100, 300], [200, 300, 600], [300, 500, 800],
	],
	"nomad": [
		[100, 200, 500], [100, 200, 500], [100, 200, 500],
		[200, 300, 600], [100, 200, 500], [0, 100, 300],
	],
}


static func hustle(character: Dictionary, rng: Dice.RandomSource) -> Dictionary:
	var role_key := String(character.get("role_key", ""))
	if not HUSTLES.has(role_key):
		return {"ok": false, "error": "Choose a Role before taking a Hustle."}
	var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
	if rank < 1 or rank > 10:
		return {"ok": false, "error": "A Role Ability Rank from 1 to 10 is required."}
	var band := 0 if rank <= 4 else (1 if rank <= 7 else 2)
	var roll := rng.randint(1, 6)
	var row: Array = HUSTLES[role_key][roll - 1]
	var earned := int(row[band])
	character["cash"] = int(character.get("cash", 0)) + earned
	return {
		"ok": true,
		"roll": roll,
		"rank": rank,
		"earned": earned,
		"work": "%s free-time Hustle · d6 result %d"
		% [String(character.get("role", role_key.capitalize())), roll],
		"days": HUSTLE_DAYS,
	}


## Move cash without allowing either side to be partially changed.
static func transfer_cash(source: Dictionary, recipient: Dictionary, amount: int) -> Dictionary:
	if source.is_empty() or recipient.is_empty():
		return {"ok": false, "error": "Choose two characters."}
	if String(source.get("id", "")) == String(recipient.get("id", "")):
		return {"ok": false, "error": "Choose a different recipient."}
	if amount <= 0:
		return {"ok": false, "error": "Enter a positive amount."}
	if int(source.get("cash", 0)) < amount:
		return {"ok": false, "error": "Not enough cash to make that transfer."}
	source["cash"] = int(source.get("cash", 0)) - amount
	recipient["cash"] = int(recipient.get("cash", 0)) + amount
	return {"ok": true, "amount": amount}


## Move one carried item and any combat profile paired with it. Installed
## cyberware must be detached first so a transfer never performs free surgery.
static func transfer_item(
	source: Dictionary, recipient: Dictionary, gear_index: int
) -> Dictionary:
	if source.is_empty() or recipient.is_empty():
		return {"ok": false, "error": "Choose two characters."}
	if String(source.get("id", "")) == String(recipient.get("id", "")):
		return {"ok": false, "error": "Choose a different recipient."}
	var source_gear: Array = source.get("gear", [])
	if gear_index < 0 or gear_index >= source_gear.size():
		return {"ok": false, "error": "Choose an item to give."}
	var entry: Dictionary = source_gear[gear_index]
	if String(entry.get("installed_on", "")) != "":
		return {"ok": false, "error": "Detach installed cyberware before giving it away."}

	if not recipient.has("gear") or not recipient["gear"] is Array:
		recipient["gear"] = []
	(source["gear"] as Array).remove_at(gear_index)
	(recipient["gear"] as Array).append(entry)
	_move_weapon_profile(source, recipient, String(entry.get("name", "")))
	_move_armor_profile(source, recipient, entry)
	return {"ok": true, "item": String(entry.get("name", "Item"))}


static func _move_weapon_profile(
	source: Dictionary, recipient: Dictionary, item_name: String
) -> void:
	var weapons: Array = source.get("weapons", [])
	for index in weapons.size():
		if String((weapons[index] as Dictionary).get("name", "")) != item_name:
			continue
		if not recipient.has("weapons") or not recipient["weapons"] is Array:
			recipient["weapons"] = []
		(recipient["weapons"] as Array).append(weapons[index])
		weapons.remove_at(index)
		return


static func _move_armor_profile(
	source: Dictionary, recipient: Dictionary, entry: Dictionary
) -> void:
	if String(entry.get("kind", "")) != "armor":
		return
	if not recipient.has("armor") or not recipient["armor"] is Dictionary:
		recipient["armor"] = CampaignSchema.empty_armor()
	if not source.has("armor") or not source["armor"] is Dictionary:
		source["armor"] = CampaignSchema.empty_armor()
	var worn_by_source: Dictionary = source["armor"]
	var worn_by_recipient: Dictionary = recipient["armor"]

	var profile := _profile_of(entry)
	if not profile.is_empty():
		var location := String(profile.get("location", ""))
		if location == "":
			return
		# The giver can still be wearing a second piece at that location, so the
		# location is only lowered to whatever is left in their gear.
		var left := _best_carried_sp(source, location)
		var still_worn: Dictionary = _worn_at(worn_by_source, location)
		if int(still_worn.get("sp", 0)) > left:
			worn_by_source[location] = {"sp": left, "ablated": false}
		worn_by_recipient[location] = {"sp": int(profile.get("sp", 0)), "ablated": false}
		return

	# Older saves — and the sample party — carry one armor entry with no profile
	# to say which location it covers, and model it as the whole worn suit. That
	# reading only holds while it is the giver's last armor entry, and it must
	# not strip armor the recipient already wears.
	if _carries_armor(source):
		return
	for location in worn_by_source:
		if int(_worn_at(worn_by_recipient, location).get("sp", 0)) <= 0:
			worn_by_recipient[location] = _worn_at(worn_by_source, location).duplicate(true)
	source["armor"] = CampaignSchema.empty_armor()


static func _worn_at(armor: Dictionary, location: String) -> Dictionary:
	var value: Variant = armor.get(location, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _profile_of(item: Dictionary) -> Dictionary:
	var value: Variant = item.get("armor_profile", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Every armor entry still in the character's gear.
static func _carried_armor(character: Dictionary) -> Array[Dictionary]:
	var carried: Array[Dictionary] = []
	var gear: Variant = character.get("gear", [])
	if typeof(gear) != TYPE_ARRAY:
		return carried
	for value in gear as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		if String((value as Dictionary).get("kind", "")) == "armor":
			carried.append(value as Dictionary)
	return carried


## Does the character still carry an armor entry that stands for a whole suit?
static func _carries_armor(character: Dictionary) -> bool:
	for item in _carried_armor(character):
		if _profile_of(item).is_empty():
			return true
	return false


## The best SP the character's remaining gear still provides at [param location].
static func _best_carried_sp(character: Dictionary, location: String) -> int:
	var best := 0
	for item in _carried_armor(character):
		var profile := _profile_of(item)
		if String(profile.get("location", "")) == location:
			best = maxi(best, int(profile.get("sp", 0)))
	return best
