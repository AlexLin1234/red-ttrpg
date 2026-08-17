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


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _encode(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "  ").to_utf8_buffer()


static func _decode(bytes: PackedByteArray, what: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		push_error("%s is not valid JSON: %s" % [what, parser.get_error_message()])
		return null
	return parser.data


## Write a bundle to [param path]. [param bundle] holds campaign, roster and
## locations; the manifest is recomputed here.
static func save(path: String, bundle: Dictionary) -> Dictionary:
	var files := {
		CAMPAIGN: _encode(bundle["campaign"]),
		ROSTER: _encode(bundle.get("roster", {"characters": []})),
	}
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
	var roster: Variant = (
		_decode(reader.read_file(ROSTER), ROSTER) if names.has(ROSTER) else {"characters": []}
	)

	var locations: Array = []
	for name in names:
		if name.begins_with(LOCATION_PREFIX) and name.ends_with(".json"):
			var location: Variant = _decode(reader.read_file(name), name)
			if typeof(location) == TYPE_DICTIONARY:
				locations.append(location)
	locations.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"])
	)

	var problems := PackedStringArray()
	var entries: Dictionary = (manifest as Dictionary).get("entries", {})
	for name in entries:
		if not names.has(name):
			problems.append("%s is listed in the manifest but missing from the file" % name)
			continue
		var bytes := reader.read_file(name)
		var expected: Dictionary = entries[name]
		if bytes.size() != int(expected["bytes"]):
			problems.append(
				"%s is %d bytes, manifest says %d" % [name, bytes.size(), int(expected["bytes"])]
			)
		elif _sha256(bytes) != String(expected["sha256"]):
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
static func read_summary(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"ok": false, "error": "not a readable .red container"}
	var names := reader.get_files()
	if not names.has(MANIFEST) or not names.has(CAMPAIGN):
		reader.close()
		return {"ok": false, "error": "container is missing its index entries"}

	var manifest: Dictionary = _decode(reader.read_file(MANIFEST), MANIFEST)
	var campaign: Dictionary = _decode(reader.read_file(CAMPAIGN), CAMPAIGN)
	var roster: Dictionary = (
		_decode(reader.read_file(ROSTER), ROSTER) if names.has(ROSTER) else {"characters": []}
	)
	reader.close()

	var location_count := 0
	for name in (manifest.get("entries", {}) as Dictionary):
		if String(name).begins_with(LOCATION_PREFIX):
			location_count += 1

	var npcs := 0
	for character in roster.get("characters", []):
		if String((character as Dictionary).get("kind", "npc")) != "pc":
			npcs += 1

	var open_hooks := 0
	for hook in campaign.get("hooks", []):
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
		"characters": (roster.get("characters", []) as Array).size(),
		"hooks": open_hooks,
		"size": _file_size(path),
	}
