class_name GearMarket
extends RefCounted

## Purchase and cyberware rules for entries supplied by the global ItemDB.
##
## The catalog deliberately lives outside campaign saves; these helpers accept
## it as input so rules tests and imported databases remain deterministic.

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


## Returns the body part row, or an empty Dictionary when the id is unknown.
static func body_part(part_id: String) -> Dictionary:
	for part in BODY_PARTS:
		if String(part["id"]) == part_id:
			return part
	return {}


static func item(catalog: Array, item_id: String) -> Dictionary:
	for value in catalog:
		if String(value["id"]) == item_id:
			return value
	return {}


## Operator controls what a Fixer can reliably source in the limited market.
static func night_market(character: Dictionary, catalog: Array) -> Array[Dictionary]:
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
	for value in catalog:
		if int(value["price"]) <= ceiling:
			result.append(value)
	return result


## Pays for an item and immediately puts its inventory/combat profile on the
## character. Returns a UI-friendly result and never partially changes state.
static func buy(character: Dictionary, catalog: Array, item_id: String) -> Dictionary:
	var product := item(catalog, item_id)
	if product.is_empty():
		return {"ok": false, "error": "That item is not in the market."}
	var price := int(product["price"])
	if int(character.get("cash", 0)) < price:
		return {"ok": false, "error": "Not enough cash for %s." % product["name"]}
	character["cash"] = int(character.get("cash", 0)) - price
	if not character.has("gear"):
		character["gear"] = []
	var owned := product.duplicate(true)
	owned["detail"] = String(product.get("description", product.get("detail", "")))
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
