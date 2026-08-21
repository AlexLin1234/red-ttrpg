extends Node

## Application-wide item database. Built-ins live in res://data and workshop
## variants live in user://; neither is embedded in a campaign save.
##
## No book data ships with Redline. [constant BUILTIN_PATH] holds homebrew
## placeholders so the app boots with a usable catalog, exactly as [Tables] boots
## on [TablesDefault]. A GM who owns the rulebook runs
## `scripts/extract_items.py` to build [constant LOCAL_PATH], which is
## git-ignored and, when present, replaces the placeholders wholesale rather than
## sitting alongside them as near-duplicates.

signal catalog_changed

const BUILTIN_PATH := "res://data/items.json"
const LOCAL_PATH := "res://data/items_local.json"
const CUSTOM_PATH := "user://item_variants.json"

## Weapon types the shipped range tables can resolve. An entry outside this list
## would assert inside [method Tables.ranged_dv] at the moment of an attack, so
## it is rejected at load instead.
const RANGED_TYPES: PackedStringArray = [
	"pistol", "smg", "shotgun", "assault_rifle", "sniper_rifle", "bow", "thrown", "melee"
]

## Only these carry an autofire range band, so only these may set a rating.
const AUTOFIRE_TYPES: PackedStringArray = ["smg", "assault_rifle"]

var _builtins: Array[Dictionary] = []
var _local: Array[Dictionary] = []
var _custom: Array[Dictionary] = []


func _ready() -> void:
	reload()


func reload() -> void:
	_builtins = _read_items(BUILTIN_PATH)
	_local = _read_items(LOCAL_PATH)
	_custom = _read_items(CUSTOM_PATH)
	catalog_changed.emit()


## True when a rulebook-derived catalog replaced the shipped placeholders.
func has_local_catalog() -> bool:
	return not _local.is_empty()


## Human-readable provenance for the market and workshop headers.
func source_label() -> String:
	if has_local_catalog():
		return "Local rulebook catalog · %d items" % _local.size()
	return "Homebrew placeholders · %d items" % _builtins.size()


func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in (_local if has_local_catalog() else _builtins):
		result.append(entry.duplicate(true))
	for entry in _custom:
		result.append(entry.duplicate(true))
	return result


func builtins() -> Array[Dictionary]:
	return _builtins.duplicate(true)


func create_variant(base_id: String, changes: Dictionary) -> Dictionary:
	var base := find_item(base_id)
	if base.is_empty():
		return {"ok": false, "error": "Choose an item to use as a template."}
	var variant := base.duplicate(true)
	variant["id"] = "custom-%d" % Time.get_ticks_usec()
	variant["base_id"] = base_id
	for key in changes:
		if key == "weapon" and changes[key] is Dictionary:
			var weapon: Dictionary = variant.get("weapon", {}).duplicate(true)
			weapon.merge(changes[key], true)
			variant["weapon"] = weapon
		else:
			variant[key] = changes[key]
	var problems := validate_item(variant)
	if not problems.is_empty():
		return {"ok": false, "error": problems[0]}
	_custom.append(variant)
	if not _write_custom():
		_custom.pop_back()
		return {"ok": false, "error": "Could not save the item database."}
	catalog_changed.emit()
	return {"ok": true, "item": variant}


func find_item(item_id: String) -> Dictionary:
	for source in [_local, _builtins, _custom]:
		for entry in source:
			if String(entry.get("id", "")) == item_id:
				return entry
	return {}


## Check one catalog row against everything the rules engine later assumes.
## Returns the list of problems; empty means the entry is safe to offer.
static func validate_item(entry: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(entry) != TYPE_DICTIONARY:
		problems.append("item is not a JSON object")
		return problems
	var item: Dictionary = entry
	var label := String(item.get("name", item.get("id", "item")))

	if String(item.get("id", "")).is_empty():
		problems.append("%s: missing id" % label)
	if String(item.get("name", "")).is_empty():
		problems.append("%s: missing name" % label)
	if int(item.get("price", -1)) < 0:
		problems.append("%s: price must be zero or more" % label)

	if item.has("weapon"):
		if typeof(item["weapon"]) != TYPE_DICTIONARY:
			problems.append("%s: weapon profile is not an object" % label)
		else:
			var weapon: Dictionary = item["weapon"]
			var weapon_type := String(weapon.get("weapon_type", ""))
			if not RANGED_TYPES.has(weapon_type):
				problems.append("%s: unknown weapon type %s" % [label, weapon_type])
			if int(weapon.get("damage_dice", 0)) <= 0:
				problems.append("%s: damage_dice must be positive" % label)
			if int(weapon.get("rof", 0)) <= 0:
				problems.append("%s: rof must be positive" % label)
			if int(weapon.get("magazine", 0)) <= 0:
				problems.append("%s: magazine must be positive" % label)
			var autofire := int(weapon.get("autofire_rating", -1))
			if autofire != -1 and autofire <= 0:
				problems.append("%s: autofire_rating must be -1 or positive" % label)
			if autofire > 0 and not AUTOFIRE_TYPES.has(weapon_type):
				problems.append("%s: %s has no autofire range band" % [label, weapon_type])

	if item.has("armor"):
		if typeof(item["armor"]) != TYPE_DICTIONARY:
			problems.append("%s: armor profile is not an object" % label)
		else:
			var armor: Dictionary = item["armor"]
			var location := String(armor.get("location", ""))
			if not Resolver.HIT_LOCATIONS.has(location):
				problems.append("%s: unknown armor location %s" % [label, location])
			if int(armor.get("sp", -1)) < 0:
				problems.append("%s: sp must be zero or more" % label)

	if String(item.get("kind", "")) == "cyberware":
		if int(item.get("humanity_cost", -1)) < 0:
			problems.append("%s: humanity_cost must be zero or more" % label)
		var listed: Variant = item.get("body_parts", [])
		if typeof(listed) != TYPE_ARRAY:
			problems.append("%s: body_parts is not a list" % label)
		else:
			var parts: Array = listed
			if parts.is_empty():
				problems.append("%s: cyberware needs at least one body part" % label)
			for part in parts:
				if GearMarket.body_part(String(part)).is_empty():
					problems.append("%s: unknown body part %s" % [label, part])

	return problems


func _read_items(path: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("%s is not a JSON object; ignoring it." % path)
		return []
	var result: Array[Dictionary] = []
	var seen := {}
	for value in (parsed as Dictionary).get("items", []):
		if not (value is Dictionary):
			continue
		var problems := validate_item(value)
		if not problems.is_empty():
			push_warning("%s: skipped %s" % [path, problems[0]])
			continue
		var id := String((value as Dictionary)["id"])
		if seen.has(id):
			push_warning("%s: skipped duplicate id %s" % [path, id])
			continue
		seen[id] = true
		result.append(value)
	return result


func _write_custom() -> bool:
	var file := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "items": _custom}, "  "))
	return true
