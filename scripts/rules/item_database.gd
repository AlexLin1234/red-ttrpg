extends Node

## Application-wide item database. Built-ins live in res://data and workshop
## variants live in user://; neither is embedded in a campaign save.

signal catalog_changed

const BUILTIN_PATH := "res://data/items.json"
const CUSTOM_PATH := "user://item_variants.json"

var _builtins: Array[Dictionary] = []
var _custom: Array[Dictionary] = []


func _ready() -> void:
	reload()


func reload() -> void:
	_builtins = _read_items(BUILTIN_PATH)
	_custom = _read_items(CUSTOM_PATH)
	catalog_changed.emit()


func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _builtins:
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
	_custom.append(variant)
	if not _write_custom():
		_custom.pop_back()
		return {"ok": false, "error": "Could not save the item database."}
	catalog_changed.emit()
	return {"ok": true, "item": variant}


func find_item(item_id: String) -> Dictionary:
	for entry in _builtins:
		if String(entry.get("id", "")) == item_id:
			return entry
	for entry in _custom:
		if String(entry.get("id", "")) == item_id:
			return entry
	return {}


func _read_items(path: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return []
	var result: Array[Dictionary] = []
	for value in (parsed as Dictionary).get("items", []):
		if value is Dictionary:
			result.append(value)
	return result


func _write_custom() -> bool:
	var file := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "items": _custom}, "  "))
	return true
