class_name GearMarket
extends RefCounted

## The Forge's built-in, rules-light equipment catalog.
##
## These are original placeholder profiles rather than reproduced sourcebook
## tables.  A catalog entry is the single source used by both Market screens
## and is copied onto the character when bought.

const CATALOG: Array[Dictionary] = [
	{"id": "agent", "name": "Pocket Agent", "kind": "electronics", "detail": "Personal communicator", "price": 100},
	{"id": "audio_recorder", "name": "Audio Recorder", "kind": "electronics", "detail": "Pocket field recorder", "price": 50},
	{"id": "binoculars", "name": "Smart Binoculars", "kind": "gear", "detail": "Low-light optics", "price": 100},
	{"id": "carryall", "name": "Carryall", "kind": "gear", "detail": "Weatherproof equipment bag", "price": 20},
	{"id": "flashlight", "name": "Tactical Flashlight", "kind": "gear", "detail": "Rechargeable utility light", "price": 20},
	{"id": "medscanner", "name": "Medscanner", "kind": "medical", "detail": "Portable diagnostic scanner", "price": 500},
	{"id": "tech_tool", "name": "Tech Tool", "kind": "tool", "detail": "Electronic and mechanical toolkit", "price": 100},
	{"id": "grapple", "name": "Grapple Launcher", "kind": "gear", "detail": "Line and powered launcher", "price": 500},
	{"id": "light_sidearm", "name": "Light Sidearm", "kind": "weapon", "detail": "2d6 · pistol · 12 rounds", "price": 100, "weapon": {"weapon_type": "pistol", "damage_dice": 2, "rof": 2, "ammo": 12, "magazine": 12, "autofire_rating": -1}},
	{"id": "heavy_sidearm", "name": "Heavy Sidearm", "kind": "weapon", "detail": "3d6 · pistol · 8 rounds", "price": 500, "weapon": {"weapon_type": "pistol", "damage_dice": 3, "rof": 2, "ammo": 8, "magazine": 8, "autofire_rating": -1}},
	{"id": "compact_smg", "name": "Compact SMG", "kind": "weapon", "detail": "2d6 · SMG · autofire 3", "price": 500, "weapon": {"weapon_type": "smg", "damage_dice": 2, "rof": 1, "ammo": 30, "magazine": 30, "autofire_rating": 3}},
	{"id": "assault_carbine", "name": "Assault Carbine", "kind": "weapon", "detail": "4d6 · rifle · autofire 4", "price": 1000, "weapon": {"weapon_type": "assault_rifle", "damage_dice": 4, "rof": 1, "ammo": 25, "magazine": 25, "autofire_rating": 4}},
	{"id": "precision_rifle", "name": "Precision Rifle", "kind": "weapon", "detail": "5d6 · sniper rifle", "price": 5000, "weapon": {"weapon_type": "sniper_rifle", "damage_dice": 5, "rof": 1, "ammo": 4, "magazine": 4, "autofire_rating": -1}},
	{"id": "light_armor", "name": "Light Armor Jacket", "kind": "armor", "detail": "11 SP · body", "price": 500, "armor": {"location": "body", "sp": 11}},
	{"id": "helmet", "name": "Ballistic Helmet", "kind": "armor", "detail": "11 SP · head", "price": 500, "armor": {"location": "head", "sp": 11}},
	{"id": "neural_link", "name": "Neural Link", "kind": "cyberware", "detail": "Neural interface foundation", "price": 500, "humanity_cost": 7, "body_parts": ["head"]},
	{"id": "cybereye", "name": "Cybereye", "kind": "cyberware", "detail": "Optical implant platform", "price": 500, "humanity_cost": 7, "body_parts": ["eyes"]},
	{"id": "cyberaudio", "name": "Cyberaudio Suite", "kind": "cyberware", "detail": "Auditory implant platform", "price": 500, "humanity_cost": 7, "body_parts": ["ears"]},
	{"id": "reflex_booster", "name": "Reflex Booster", "kind": "cyberware", "detail": "Experimental reaction implant", "price": 5000, "humanity_cost": 14, "body_parts": ["torso"]},
	{"id": "cyberarm", "name": "Cyberarm", "kind": "cyberware", "detail": "Full replacement arm", "price": 500, "humanity_cost": 7, "body_parts": ["left_arm", "right_arm"]},
	{"id": "subdermal_grip", "name": "Subdermal Grip", "kind": "cyberware", "detail": "Neural weapon link", "price": 500, "humanity_cost": 3, "body_parts": ["left_hand", "right_hand"]},
	{"id": "cyberleg", "name": "Cyberleg", "kind": "cyberware", "detail": "Full replacement leg", "price": 500, "humanity_cost": 7, "body_parts": ["left_leg", "right_leg"]},
]

const BODY_PARTS: Array[Dictionary] = [
	{"id": "head", "label": "Head"},
	{"id": "eyes", "label": "Eyes"},
	{"id": "ears", "label": "Ears"},
	{"id": "torso", "label": "Torso"},
	{"id": "left_arm", "label": "Left arm"},
	{"id": "right_arm", "label": "Right arm"},
	{"id": "left_hand", "label": "Left hand"},
	{"id": "right_hand", "label": "Right hand"},
	{"id": "left_leg", "label": "Left leg"},
	{"id": "right_leg", "label": "Right leg"},
]


static func item(item_id: String) -> Dictionary:
	for value in CATALOG:
		if String(value["id"]) == item_id:
			return value
	return {}


## Operator controls what a Fixer can reliably source in the limited market.
static func night_market(character: Dictionary) -> Array[Dictionary]:
	if String(character.get("role_key", "")) != "fixer":
		return []
	var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
	var ceiling := 100
	if rank >= 9:
		ceiling = 10000
	elif rank >= 7:
		ceiling = 5000
	elif rank >= 4:
		ceiling = 1000
	var result: Array[Dictionary] = []
	for value in CATALOG:
		if int(value["price"]) <= ceiling:
			result.append(value)
	return result


## Pays for an item and immediately puts its inventory/combat profile on the
## character. Returns a UI-friendly result and never partially changes state.
static func buy(character: Dictionary, item_id: String) -> Dictionary:
	var product := item(item_id)
	if product.is_empty():
		return {"ok": false, "error": "That item is not in the market."}
	var price := int(product["price"])
	if int(character.get("cash", 0)) < price:
		return {"ok": false, "error": "Not enough cash for %s." % product["name"]}
	character["cash"] = int(character.get("cash", 0)) - price
	if not character.has("gear"):
		character["gear"] = []
	var owned := product.duplicate(true)
	owned.erase("id")
	owned.erase("price")
	owned.erase("weapon")
	owned.erase("armor")
	(character["gear"] as Array).append(owned)
	if product.has("weapon"):
		if not character.has("weapons"):
			character["weapons"] = []
		var weapon: Dictionary = (product["weapon"] as Dictionary).duplicate(true)
		weapon["name"] = product["name"]
		(character["weapons"] as Array).append(weapon)
	if product.has("armor"):
		if not character.has("armor"):
			character["armor"] = CampaignSchema.empty_armor()
		var armor_profile: Dictionary = product["armor"]
		var location := String(armor_profile["location"])
		(character["armor"] as Dictionary)[location] = {"sp": int(armor_profile["sp"]), "ablated": false}
	return {"ok": true, "item": product["name"], "price": price}


static func installed_at(character: Dictionary, body_part: String) -> int:
	var gear: Array = character.get("gear", [])
	for index in gear.size():
		if String((gear[index] as Dictionary).get("installed_on", "")) == body_part:
			return index
	return -1


static func can_install(entry: Dictionary, body_part: String) -> bool:
	if String(entry.get("kind", "")) != "cyberware":
		return false
	var compatible: Array = entry.get("body_parts", [])
	return compatible.has(body_part) and String(entry.get("installed_on", "")) == ""


## Installation, rather than purchase, causes Humanity loss. The loss is
## permanent when an implant is detached; recovery belongs to therapy rather
## than inventory management.
static func install_cyberware(
	character: Dictionary, gear_index: int, body_part: String
) -> Dictionary:
	var gear: Array = character.get("gear", [])
	if gear_index < 0 or gear_index >= gear.size():
		return {"ok": false, "error": "Choose an owned piece of cyberware."}
	if installed_at(character, body_part) >= 0:
		return {"ok": false, "error": "That body part already has cyberware attached."}
	var implant: Dictionary = gear[gear_index]
	if not can_install(implant, body_part):
		return {"ok": false, "error": "That cyberware cannot be attached there."}
	implant["installed_on"] = body_part
	var loss := maxi(0, int(implant.get("humanity_cost", 0)))
	character["humanity"] = maxi(0, int(character.get("humanity", 0)) - loss)
	return {"ok": true, "item": implant.get("name", "Cyberware"), "humanity_loss": loss}


static func detach_cyberware(character: Dictionary, body_part: String) -> Dictionary:
	var index := installed_at(character, body_part)
	if index < 0:
		return {"ok": false, "error": "No cyberware is attached there."}
	var implant: Dictionary = (character.get("gear", []) as Array)[index]
	implant.erase("installed_on")
	return {"ok": true, "item": implant.get("name", "Cyberware")}
