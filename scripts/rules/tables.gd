class_name Tables
extends RefCounted

## Rules tables, and the JSON document they are read from.
##
## No book data ships with Redline. The app boots on the homebrew placeholders in
## [TablesDefault]; a GM who owns the book edits any value in the table editor or
## imports a JSON document in this same shape.

var data: Dictionary


func _init(p_data: Dictionary) -> void:
	data = p_data


func _band(group_key: String, weapon_type: String, distance_m: float, missing: String, no_band: String) -> int:
	assert(distance_m >= 0.0, "distance_m cannot be negative")
	var group: Dictionary = data.get(group_key, {})
	assert(group.has(weapon_type), "%s: %s" % [missing, weapon_type])
	for entry in group[weapon_type]:
		var band: Dictionary = entry
		if float(band["min_m"]) <= distance_m and distance_m <= float(band["max_m"]):
			return int(band["dv"])
	push_error("%s %s at %s m" % [weapon_type, no_band, distance_m])
	return 0


func ranged_dv(weapon_type: String, distance_m: float) -> int:
	return _band("ranged_dv", weapon_type, distance_m, "unknown weapon type", "has no valid range band")


func autofire_dv(weapon_type: String, distance_m: float) -> int:
	return _band(
		"autofire_dv",
		weapon_type,
		distance_m,
		"weapon type does not support autofire",
		"has no autofire range band",
	)


func autofire_multiplier(margin: int, rating: int) -> int:
	assert(margin >= 1, "autofire margin must be positive")
	assert(rating >= 1, "autofire rating must be positive")
	return mini(margin, rating)


## Returns {"name": String, "page": int}.
func critical_injury(location: String, roll: int) -> Dictionary:
	assert(location == "body" or location == "head", "invalid injury location: %s" % location)
	assert(roll >= 2 and roll <= 12, "critical injury roll must be between 2 and 12")
	var table: Dictionary = data["critical_injuries"][location]
	assert(table.has(str(roll)), "missing %s critical injury roll %d" % [location, roll])
	return table[str(roll)]


func has_weapon(name: String) -> bool:
	return (data.get("weapons", {}) as Dictionary).has(name)


## Returns the weapon profile row, with "name" filled in.
func weapon(name: String) -> Dictionary:
	var weapons: Dictionary = data.get("weapons", {})
	assert(weapons.has(name), "unknown weapon: %s" % name)
	var profile: Dictionary = (weapons[name] as Dictionary).duplicate(true)
	profile["name"] = name
	return profile


func weapon_names() -> Array:
	var names := (data.get("weapons", {}) as Dictionary).keys()
	names.sort()
	return names


func armor(name: String) -> Dictionary:
	var rows: Dictionary = data.get("armor", {})
	assert(rows.has(name), "unknown armor: %s" % name)
	return rows[name]


func aimed_shot(location: String) -> Dictionary:
	var rows: Dictionary = data.get("aimed_shots", {})
	assert(rows.has(location), "unknown aimed-shot location: %s" % location)
	return rows[location]


func cover(example: String) -> Dictionary:
	var rows: Dictionary = data.get("cover", {})
	assert(rows.has(example), "unknown cover example: %s" % example)
	return rows[example]


func cover_names() -> Array:
	return (data.get("cover", {}) as Dictionary).keys()


## Check an imported document before it replaces the active tables.
## Returns the list of problems; empty means the file is usable.
static func validate(value: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		problems.append("file is not a JSON object")
		return problems
	var doc: Dictionary = value

	for key in ["ranged_dv", "autofire_dv", "weapons", "critical_injuries"]:
		if not doc.has(key) or typeof(doc[key]) != TYPE_DICTIONARY:
			problems.append('missing "%s" section' % key)

	if doc.has("critical_injuries") and typeof(doc["critical_injuries"]) == TYPE_DICTIONARY:
		var injuries: Dictionary = doc["critical_injuries"]
		for location in ["body", "head"]:
			if not injuries.has(location):
				problems.append('missing "%s" critical injury table' % location)
				continue
			var table: Dictionary = injuries[location]
			for roll in range(2, 13):
				if not table.has(str(roll)):
					problems.append("%s critical injuries missing roll %d" % [location, roll])

	if doc.has("weapons") and typeof(doc["weapons"]) == TYPE_DICTIONARY:
		var weapons: Dictionary = doc["weapons"]
		for name in weapons:
			var profile: Dictionary = weapons[name]
			if int(profile.get("damage_dice", 0)) <= 0:
				problems.append("%s: damage_dice must be positive" % name)
			if int(profile.get("rof", 0)) <= 0:
				problems.append("%s: rof must be positive" % name)

	return problems
