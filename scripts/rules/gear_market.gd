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


## Operator Reach: the highest price category a Fixer can always source
## piece-by-piece, whatever the local supply, by Role Ability rank.
##
## Reach is written in price categories rather than raw eurobucks, so the ladder
## is expressed as the ceiling of each category: Everyday at Ranks 1-2,
## Expensive at 3-6, Very Expensive at 7-8, Luxury at 9, Super Luxury at 10.
## Ranks 5 and 6 spend their entry on organizing a Night Market instead of
## raising the piece-by-piece ceiling, so they share the Rank 3-4 ceiling.
static func reach_ceiling(rank: int) -> int:
	if rank >= 10:
		return 10000
	if rank >= 9:
		return 5000
	if rank >= 7:
		return 1000
	if rank >= 3:
		return 500
	if rank >= 1:
		return 20
	return 0


## Rank needed to gather other Fixers and organize a Night Market at all.
const NIGHT_MARKET_MINIMUM_RANK := 5

## Rank that can additionally seat a Midnight Market inside a Night Market.
const MIDNIGHT_MARKET_RANK := 9

## The six kinds of goods a Night Market can carry, and the catalog kinds each
## one draws from. Two are present at any given market.
const NIGHT_MARKET_GOODS: Array[Dictionary] = [
	{"id": "food_drugs", "label": "Food and Drugs", "kinds": ["drug", "food"]},
	{"id": "electronics", "label": "Personal Electronics", "kinds": ["electronics"]},
	{"id": "weapons_armor", "label": "Weapons and Armor", "kinds": ["weapon", "armor", "ammo"]},
	{"id": "cyberware", "label": "Cyberware", "kinds": ["cyberware"]},
	{"id": "fashion", "label": "Clothing and Fashionware", "kinds": ["fashion"]},
	{"id": "survival", "label": "Survival Gear", "kinds": ["gear", "tool", "medical"]},
]


## Generate a Night Market, rather than filter the catalog by price.
##
## A Night Market is an event a Rank 5+ Fixer organizes with other Fixers, not a
## rank-limited shelf: while at one, every price category up to Super Luxury is
## available. What varies is the stock. Two of the six kinds of goods are rolled
## on 1d6 (rerolling a repeat), and each contributes 1d10 types of item.
##
## Returns {"ok", "error", "stock", "categories", "midnight"}.
static func night_market(
	character: Dictionary, catalog: Array, rng: Dice.RandomSource
) -> Dictionary:
	var empty: Array[Dictionary] = []
	if String(character.get("role_key", "")) != "fixer":
		return {
			"ok": false,
			"error": "Only a Fixer can organize a Night Market.",
			"stock": empty,
			"categories": PackedStringArray(),
			"midnight": false,
		}
	var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
	if rank < NIGHT_MARKET_MINIMUM_RANK:
		return {
			"ok": false,
			"error": (
				"Operator Rank %d is needed to organize a Night Market. Rank %d reaches %deb piece by piece."
				% [NIGHT_MARKET_MINIMUM_RANK, rank, reach_ceiling(rank)]
			),
			"stock": empty,
			"categories": PackedStringArray(),
			"midnight": false,
		}

	var first := rng.randint(1, 6)
	var second := rng.randint(1, 6)
	while second == first:
		second = rng.randint(1, 6)

	var stock: Array[Dictionary] = []
	var labels := PackedStringArray()
	for index in [first - 1, second - 1]:
		var goods: Dictionary = NIGHT_MARKET_GOODS[index]
		labels.append(String(goods["label"]))
		var pool: Array[Dictionary] = []
		for value in catalog:
			var entry: Dictionary = value
			if (goods["kinds"] as Array).has(String(entry.get("kind", ""))):
				pool.append(entry)
		var wanted := rng.randint(1, 10)
		for _draw in mini(wanted, pool.size()):
			var pick := rng.randint(0, pool.size() - 1)
			stock.append(pool[pick])
			pool.remove_at(pick)
	return {
		"ok": true,
		"error": "",
		"stock": stock,
		"categories": labels,
		"midnight": rank >= MIDNIGHT_MARKET_RANK,
	}


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
