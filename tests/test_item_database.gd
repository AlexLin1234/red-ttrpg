extends RefCounted

## The catalog is data, so the contract it has to satisfy is checked here rather
## than trusted: every shipped row must survive validation, and every weapon,
## armor location, and body part must be one the rules engine can actually
## resolve. A bad row would otherwise surface as a hard assert mid-combat.

const Harness := preload("res://tests/harness.gd")

const ItemDatabase := preload("res://scripts/rules/item_database.gd")


static func _catalog() -> Array:
	var document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://catalog/items.json")
	)
	return document["items"]


static func _weapon_item(weapon_type: String, overrides := {}) -> Dictionary:
	var weapon := {
		"weapon_type": weapon_type,
		"damage_dice": 2,
		"damage_bonus": 0,
		"rof": 1,
		"ammo": 10,
		"magazine": 10,
		"autofire_rating": -1,
	}
	weapon.merge(overrides, true)
	return {"id": "probe", "name": "Probe", "kind": "weapon", "price": 100, "weapon": weapon}


static func run(h: Harness) -> void:
	var catalog := _catalog()
	var tables := Tables.new(TablesDefault.document())

	h.describe("item database")

	h.it("ships a catalog whose every row passes validation")
	var rejected := PackedStringArray()
	var ids := {}
	var duplicates := 0
	for value in catalog:
		var entry: Dictionary = value
		for problem in ItemDatabase.validate_item(entry):
			rejected.append(problem)
		var id := String(entry.get("id", ""))
		if ids.has(id):
			duplicates += 1
		ids[id] = true
	h.equal(rejected, PackedStringArray(), "no invalid rows")
	h.equal(duplicates, 0, "no duplicate ids")

	h.it("resolves every catalog weapon against the shipped range tables")
	var weapon_count := 0
	for value in catalog:
		var entry: Dictionary = value
		if not entry.has("weapon"):
			continue
		weapon_count += 1
		var weapon: Dictionary = entry["weapon"]
		var weapon_type := String(weapon["weapon_type"])
		h.check(
			tables.data["ranged_dv"].has(weapon_type),
			"%s: %s has a range band" % [entry["name"], weapon_type],
		)
		if int(weapon["autofire_rating"]) > 0:
			h.check(
				tables.data["autofire_dv"].has(weapon_type),
				"%s: %s has an autofire band" % [entry["name"], weapon_type],
			)
		h.check(tables.has_weapon(String(entry["name"])), "%s has a table row" % entry["name"])
	h.equal(weapon_count, 13, "every weapon checked")

	h.it("stocks every kind of goods a Night Market can roll")
	for goods in GearMarket.NIGHT_MARKET_GOODS:
		var available := 0
		for value in catalog:
			if (goods["kinds"] as Array).has(String((value as Dictionary).get("kind", ""))):
				available += 1
		h.check(available > 0, "%s has stock to draw" % goods["label"])

	h.it("covers every range band and every installable body part")
	var seen_types := {}
	var seen_parts := {}
	for value in catalog:
		var entry: Dictionary = value
		if entry.has("weapon"):
			seen_types[String((entry["weapon"] as Dictionary)["weapon_type"])] = true
		if String(entry.get("kind", "")) == "cyberware":
			for part in entry.get("body_parts", []):
				seen_parts[String(part)] = true
	for weapon_type in ItemDatabase.RANGED_TYPES:
		h.check(seen_types.has(weapon_type), "catalog offers a %s" % weapon_type)
	for part in GearMarket.BODY_PARTS:
		h.check(seen_parts.has(String(part["id"])), "catalog offers %s cyberware" % part["id"])

	h.it("rejects rows the rules engine could not resolve")
	h.check(
		not ItemDatabase.validate_item(_weapon_item("railgun")).is_empty(),
		"unknown weapon type rejected",
	)
	h.check(
		not ItemDatabase.validate_item(_weapon_item("pistol", {"autofire_rating": 3})).is_empty(),
		"autofire without a range band rejected",
	)
	h.check(
		not ItemDatabase.validate_item(_weapon_item("pistol", {"damage_dice": 0})).is_empty(),
		"non-positive damage rejected",
	)
	h.check(
		not ItemDatabase.validate_item(_weapon_item("pistol", {"magazine": 0})).is_empty(),
		"empty magazine rejected",
	)
	h.equal(ItemDatabase.validate_item(_weapon_item("smg", {"autofire_rating": 3})).size(), 0,
		"autofire on a supported type accepted")

	var bad_armor := {
		"id": "a", "name": "A", "kind": "armor", "price": 10,
		"armor": {"location": "left_hand", "sp": 7},
	}
	h.check(not ItemDatabase.validate_item(bad_armor).is_empty(), "unknown armor location rejected")

	var bad_implant := {
		"id": "c", "name": "C", "kind": "cyberware", "price": 10,
		"humanity_cost": 2, "body_parts": ["tail"],
	}
	h.check(not ItemDatabase.validate_item(bad_implant).is_empty(), "unknown body part rejected")
	h.check(
		not ItemDatabase.validate_item(
			{"id": "c", "name": "C", "kind": "cyberware", "price": 10, "humanity_cost": 2, "body_parts": []}
		).is_empty(),
		"cyberware without a body part rejected",
	)
	h.check(
		not ItemDatabase.validate_item({"id": "p", "name": "P", "kind": "gear", "price": -1}).is_empty(),
		"negative price rejected",
	)
	# One malformed row must be reported, not throw: the reader skips the row it
	# names and keeps the rest of the operator's catalog.
	h.contains(
		ItemDatabase.validate_item(
			{
				"id": "c", "name": "C", "kind": "cyberware", "price": 10,
				"humanity_cost": 2, "body_parts": "left_arm",
			}
		),
		"C: body_parts is not a list",
		"body_parts holding a string reported",
	)

	h.it("keeps a bought weapon identical to its table row")
	var buyer := {
		"cash": 20000, "gear": [], "weapons": [],
		"armor": CampaignSchema.empty_armor(), "humanity": 40, "max_humanity": 50,
	}
	for value in catalog:
		var entry: Dictionary = value
		if not entry.has("weapon"):
			continue
		var profile := tables.weapon(String(entry["name"]))
		var weapon: Dictionary = entry["weapon"]
		h.equal(
			int(weapon["damage_dice"]), int(profile["damage_dice"]),
			"%s damage matches the table" % entry["name"],
		)
		h.equal(
			String(weapon["weapon_type"]), String(profile["range_type"]),
			"%s range type matches the table" % entry["name"],
		)
		h.equal(
			int(weapon["autofire_rating"]), int(profile["autofire_rating"]),
			"%s autofire matches the table" % entry["name"],
		)
	GearMarket.buy(buyer, catalog, "frag_grenade")
	h.equal(buyer["weapons"][0]["weapon_type"], "thrown", "thrown weapon equipped")

	h.it("layers a local rulebook catalog over the shipped placeholders")
	var database: Node = ItemDatabase.new()
	database.reload()
	var local_path := ""
	for candidate in ItemDatabase.LOCAL_PATHS:
		if FileAccess.file_exists(candidate):
			local_path = candidate
			break
	if not local_path.is_empty():
		# Only present for a GM who ran scripts/extract_items.py against their
		# own book, so this arm is skipped on a fresh clone.
		h.equal(database.has_local_catalog(), true, "local catalog detected")
		h.equal(
			database.catalog().size() == database.builtins().size(), false,
			"local catalog replaces the placeholders",
		)
		var local: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(local_path)
		)
		var local_problems := PackedStringArray()
		for value in local["items"]:
			for problem in ItemDatabase.validate_item(value):
				local_problems.append(problem)
		h.equal(local_problems, PackedStringArray(), "every extracted row is resolvable")
	else:
		h.equal(database.has_local_catalog(), false, "no local catalog on a clean checkout")
		h.equal(database.catalog().size(), catalog.size(), "placeholders are served")
	database.free()
