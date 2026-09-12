class_name NetrunTables
extends RefCounted

## The NET content a campaign runs against, read from a document.
##
## The same split [Tables] makes for combat, and for the same reason: the ICE,
## the floor kinds and the difficulty bands that ship with Redline are homebrew
## placeholders, and a GM who owns the book replaces them. Reading them through
## a document rather than off [NetrunDefault]'s constants is what makes that
## replacement possible at all.
##
## Every lookup falls back to the built-in placeholder rather than failing: a
## campaign that replaces the ICE and not the floor kinds is a normal thing for
## a GM to do halfway through an evening.

var data: Dictionary


func _init(p_data: Dictionary) -> void:
	data = p_data


func difficulties() -> Array:
	var carried: Variant = data.get("difficulties", [])
	if carried is Array and not (carried as Array).is_empty():
		return carried
	return NetrunDefault.DIFFICULTIES


func difficulty(key: String) -> Dictionary:
	for entry in difficulties():
		var spec: Dictionary = entry
		if String(spec.get("key", "")) == key:
			return spec
	return NetrunDefault.difficulty(key)


func floor_kinds() -> Array:
	var carried: Variant = data.get("floor_kinds", [])
	if carried is Array and not (carried as Array).is_empty():
		return carried
	return NetrunDefault.FLOOR_KINDS


func floor_kind(kind: String) -> Dictionary:
	for entry in floor_kinds():
		var spec: Dictionary = entry
		if String(spec.get("kind", "")) == kind:
			return spec
	return NetrunDefault.floor_kind(kind)


func ice_table() -> Dictionary:
	var carried: Variant = data.get("ice", {})
	if carried is Dictionary and not (carried as Dictionary).is_empty():
		return carried
	return NetrunDefault.ICE


func ice_names() -> Array:
	var names := ice_table().keys()
	names.sort()
	return names


func ice(name: String) -> Dictionary:
	var table := ice_table()
	if table.has(name):
		return table[name]
	return NetrunDefault.ice(name)


## Roll an architecture the GM can then edit.
##
## A generated ladder is a starting point, not a result: it alternates doors and
## defenders so the shape is immediately playable, and every floor is editable
## afterwards. The last floor is always worth reaching.
##
## It builds from whichever difficulty bands and floor kinds are in force, so a
## GM who replaced the ICE gets their own ICE in the ladder rather than the
## placeholders the app shipped with.
func generate_architecture(
	name: String, difficulty_key: String, rng: Dice.RandomSource
) -> Dictionary:
	return NetrunDefault._generate(
		name,
		difficulty(difficulty_key),
		rng,
		func(kind: String) -> String: return String(floor_kind(kind).get("label", kind)),
	)
