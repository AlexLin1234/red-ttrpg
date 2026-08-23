class_name CampaignContainer
extends RefCounted

## Reading and writing the `.red` campaign container.
##
## A save is a zip so the library screen can tell the truth: the file has a real
## size on disk, a real format version, and a per-entry SHA-256 in the manifest
## that either matches the bytes or does not. "Integrity: verified" is a check,
## not a decoration.

const MANIFEST := "manifest.json"
const CAMPAIGN := "campaign.json"
const ROSTER := "roster.json"
const LOCATION_PREFIX := "locations/"
const MAP_IMAGE := "assets/map.png"


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _encode(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "  ").to_utf8_buffer()


## Read [param key] from [param source] as a Dictionary, or an empty one. A
## hand-edited or truncated save can hold anything at any key, and neither the
## library listing nor a load may crash over it.
static func _dict_of(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _array_of(source: Dictionary, key: String) -> Array:
	var value: Variant = source.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func _decode(bytes: PackedByteArray, what: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		push_error("%s is not valid JSON: %s" % [what, parser.get_error_message()])
		return null
	return parser.data


## Write a bundle to [param path]. [param bundle] holds campaign, roster and
## locations; the manifest is recomputed here.
static func save(path: String, bundle: Dictionary) -> Dictionary:
	var campaign: Dictionary = (bundle["campaign"] as Dictionary).duplicate(true)
	var gm_map: Dictionary = campaign.get("gm_map", {})
	var files := {
		ROSTER: _encode(bundle.get("roster", {"characters": []})),
	}
	var encoded_map := String(gm_map.get("png_base64", ""))
	if encoded_map != "":
		files[MAP_IMAGE] = Marshalls.base64_to_raw(encoded_map)
		gm_map.erase("png_base64")
		gm_map["image_entry"] = MAP_IMAGE
		campaign["gm_map"] = gm_map
	files[CAMPAIGN] = _encode(campaign)
	for location in bundle.get("locations", []):
		files["%s%s.json" % [LOCATION_PREFIX, String((location as Dictionary)["id"])]] = _encode(location)

	var entries := {}
	for name in files:
		var bytes: PackedByteArray = files[name]
		entries[name] = {"sha256": _sha256(bytes), "bytes": bytes.size()}

	var now := Time.get_datetime_string_from_system(true)
	var previous: Dictionary = bundle.get("manifest", {})
	var manifest := {
		"format": CampaignSchema.SAVE_FORMAT,
		"version": CampaignSchema.SAVE_VERSION,
		"created": String(previous.get("created", now)),
		"updated": now,
		"sessions": int((bundle["campaign"] as Dictionary).get("sessions", 0)),
		"entries": entries,
	}

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packer := ZIPPacker.new()
	var error := packer.open(path)
	if error != OK:
		return {"ok": false, "error": "could not write %s (error %d)" % [path, error]}

	packer.start_file(MANIFEST)
	packer.write_file(_encode(manifest))
	packer.close_file()
	for name in files:
		packer.start_file(name)
		packer.write_file(files[name])
		packer.close_file()
	packer.close()

	return {"ok": true, "manifest": manifest, "size": _file_size(path)}


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return int(size)


## Read a `.red` file and check every entry against its manifest.
##
## Returns {"ok", "manifest", "campaign", "roster", "locations", "integrity",
## "size", "path"} or {"ok": false, "error"}.
static func load_file(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"ok": false, "error": "not a readable .red container"}

	var names := reader.get_files()
	if not names.has(MANIFEST):
		reader.close()
		return {"ok": false, "error": "container has no manifest.json"}
	var manifest: Variant = _decode(reader.read_file(MANIFEST), MANIFEST)
	if typeof(manifest) != TYPE_DICTIONARY:
		reader.close()
		return {"ok": false, "error": "manifest.json is unreadable"}
	if String((manifest as Dictionary).get("format", "")) != CampaignSchema.SAVE_FORMAT:
		reader.close()
		return {"ok": false, "error": "unsupported save format"}
	if not names.has(CAMPAIGN):
		reader.close()
		return {"ok": false, "error": "container has no campaign.json"}

	var campaign: Variant = _decode(reader.read_file(CAMPAIGN), CAMPAIGN)
	if typeof(campaign) == TYPE_DICTIONARY:
		var gm_map: Dictionary = _dict_of(campaign as Dictionary, "gm_map")
		var image_entry := String(gm_map.get("image_entry", ""))
		if image_entry != "" and names.has(image_entry):
			gm_map["png_base64"] = Marshalls.raw_to_base64(reader.read_file(image_entry))
			(campaign as Dictionary)["gm_map"] = gm_map
	var roster: Variant = (
		_decode(reader.read_file(ROSTER), ROSTER) if names.has(ROSTER) else {"characters": []}
	)
	if typeof(campaign) != TYPE_DICTIONARY or typeof(roster) != TYPE_DICTIONARY:
		reader.close()
		return {"ok": false, "error": "campaign state is unreadable"}
	# GDScript evaluates a get() default eagerly, so the clock is only read when
	# the save predates current_month — and only when it is a usable clock.
	var current_month: Variant = (campaign as Dictionary).get("current_month", null)
	if current_month == null:
		var clock: Dictionary = _dict_of(campaign as Dictionary, "clock")
		if not clock.has("year") or not clock.has("month"):
			reader.close()
			return {"ok": false, "error": "campaign has neither current_month nor a clock"}
		current_month = Lifestyle.month_key(clock)
	if not Lifestyle.is_month(current_month):
		reader.close()
		return {"ok": false, "error": "campaign current_month must use YYYY-MM"}
	(campaign as Dictionary)["current_month"] = current_month
	for value in _array_of(roster as Dictionary, "characters"):
		if typeof(value) != TYPE_DICTIONARY:
			reader.close()
			return {"ok": false, "error": "roster holds an entry that is not a character"}
		var character: Dictionary = value
		CharacterRules.ensure_character(character)
		if String(character.get("kind", "npc")) == "pc" or character.has("lifestyle"):
			Lifestyle.ensure_character(character)
			var problem := Lifestyle.validate_character(character)
			if problem != "":
				reader.close()
				return {"ok": false, "error": "%s: %s" % [character.get("name", "character"), problem]}

	var locations: Array = []
	for name in names:
		if name.begins_with(LOCATION_PREFIX) and name.ends_with(".json"):
			var location: Variant = _decode(reader.read_file(name), name)
			if typeof(location) == TYPE_DICTIONARY:
				locations.append(location)
	locations.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")) < String(b.get("name", ""))
	)

	var problems := PackedStringArray()
	var entries: Dictionary = _dict_of(manifest as Dictionary, "entries")
	for name in entries:
		if not names.has(name):
			problems.append("%s is listed in the manifest but missing from the file" % name)
			continue
		var expected: Dictionary = _dict_of(entries, name)
		if expected.is_empty():
			problems.append("%s has no usable manifest entry" % name)
			continue
		var bytes := reader.read_file(name)
		if bytes.size() != int(expected.get("bytes", -1)):
			problems.append(
				"%s is %d bytes, manifest says %d"
				% [name, bytes.size(), int(expected.get("bytes", -1))]
			)
		elif _sha256(bytes) != String(expected.get("sha256", "")):
			problems.append("%s does not match its manifest checksum" % name)
	for name in names:
		# ZIPPacker emits a directory entry for each nested path; those carry no
		# bytes and are not manifest entries.
		if name.ends_with("/"):
			continue
		if name != MANIFEST and not entries.has(name):
			problems.append("%s is in the file but not listed in the manifest" % name)

	reader.close()
	return {
		"ok": true,
		"path": path,
		"manifest": manifest,
		"campaign": campaign,
		"roster": roster,
		"locations": locations,
		"size": _file_size(path),
		"integrity": {"verified": problems.is_empty(), "problems": problems},
	}


## The library list needs a card per save, not a whole campaign, so this reads
## only the small index entries and skips the location payloads.
## Just the manifest, without paying for the rest of the container.
##
## The index alone answers questions about which version of a save something
## else was derived from, which is a good deal cheaper than opening a container
## that may be carrying a megabyte of map behind it.
static func read_manifest(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {}
	var names := reader.get_files()
	if not names.has(MANIFEST):
		reader.close()
		return {}
	var value: Variant = _decode(reader.read_file(MANIFEST), MANIFEST)
	reader.close()
	return value if typeof(value) == TYPE_DICTIONARY else {}


## The sha256 the manifest recorded for one entry, or "" when there is none.
static func entry_digest(manifest: Dictionary, entry := CAMPAIGN) -> String:
	var entries: Dictionary = manifest.get("entries", {})
	var entry_row: Dictionary = entries.get(entry, {})
	return String(entry_row.get("sha256", ""))


static func read_summary(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"ok": false, "error": "not a readable .red container"}
	var names := reader.get_files()
	if not names.has(MANIFEST) or not names.has(CAMPAIGN):
		reader.close()
		return {"ok": false, "error": "container is missing its index entries"}

	var manifest_value: Variant = _decode(reader.read_file(MANIFEST), MANIFEST)
	var campaign_value: Variant = _decode(reader.read_file(CAMPAIGN), CAMPAIGN)
	var roster_value: Variant = (
		_decode(reader.read_file(ROSTER), ROSTER) if names.has(ROSTER) else {"characters": []}
	)
	reader.close()
	# A card is drawn from whatever survives: a save with a corrupt entry still
	# lists, as the unreadable card the library already knows how to draw.
	if typeof(manifest_value) != TYPE_DICTIONARY or typeof(campaign_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "container index entries are unreadable"}
	var manifest: Dictionary = manifest_value
	var campaign: Dictionary = campaign_value
	var roster: Dictionary = roster_value if typeof(roster_value) == TYPE_DICTIONARY else {}

	var location_count := 0
	for name in _dict_of(manifest, "entries"):
		if String(name).begins_with(LOCATION_PREFIX):
			location_count += 1

	var characters := _array_of(roster, "characters")
	var npcs := 0
	for character in characters:
		if typeof(character) != TYPE_DICTIONARY:
			continue
		if String((character as Dictionary).get("kind", "npc")) != "pc":
			npcs += 1

	var open_hooks := 0
	for hook in _array_of(campaign, "hooks"):
		if typeof(hook) != TYPE_DICTIONARY:
			continue
		if String((hook as Dictionary).get("status", "open")) != "closed":
			open_hooks += 1

	return {
		"ok": true,
		"path": path,
		"name": String(campaign.get("name", path.get_file())),
		"arc": String(campaign.get("arc", "")),
		"city": String(campaign.get("city", "")),
		"players": int(campaign.get("players", 0)),
		"sessions": int(campaign.get("sessions", 0)),
		"version": String(manifest.get("version", "?")),
		"created": String(manifest.get("created", "")),
		"updated": String(manifest.get("updated", "")),
		"locations": location_count,
		"npcs": npcs,
		"characters": characters.size(),
		"hooks": open_hooks,
		"size": _file_size(path),
	}
