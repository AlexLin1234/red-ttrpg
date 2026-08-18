extends Node

## The one place the loaded campaign lives.
##
## Registered as the `Store` autoload. Screens read from here and call the edit
## helpers; nothing else holds campaign state. Saving is explicit, and `dirty`
## drives the header indicator so the GM can see whether the file on disk matches
## what is on screen.

signal campaign_opened
signal campaign_changed
signal campaign_saved
signal status_changed(message: String)

var path := ""
var manifest: Dictionary = {}
var campaign: Dictionary = {}
var roster: Dictionary = {"characters": []}
var locations: Array = []
var integrity: Dictionary = {"verified": true, "problems": PackedStringArray()}
var size_on_disk := 0
var dirty := false
var status := ""

var active_location_id := ""
var active_character_id := ""


func is_open() -> bool:
	return not campaign.is_empty()


## `~/Documents/Redline/saves`, or the user data directory when the system has no
## Documents folder (which is the case on a headless test runner).
func library_dir() -> String:
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var dir := "user://saves" if documents == "" else documents.path_join("Redline/saves")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


func list_saves() -> Array:
	var dir := library_dir()
	var access := DirAccess.open(dir)
	if access == null:
		return []
	var entries: Array = []
	for file_name in access.get_files():
		if not file_name.ends_with(".red"):
			continue
		var full := dir.path_join(file_name)
		var summary := CampaignContainer.read_summary(full)
		if bool(summary.get("ok", false)):
			summary["modified"] = FileAccess.get_modified_time(full)
			entries.append(summary)
		else:
			entries.append(
				{
					"ok": false,
					"path": full,
					"name": file_name,
					"error": String(summary.get("error", "unreadable")),
					"size": 0,
					"modified": FileAccess.get_modified_time(full),
				}
			)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("modified", 0)) > int(b.get("modified", 0))
	)
	return entries


## Write the demo campaigns into an empty library, so a fresh install has
## something to open.
func seed_library_if_empty() -> void:
	if not list_saves().is_empty():
		return
	var bundles: Array = [CampaignFixtures.blackwall_sunrise()]
	bundles.append_array(CampaignFixtures.library_fillers())
	for bundle in bundles:
		var name := String((bundle as Dictionary)["campaign"]["name"])
		CampaignContainer.save(library_dir().path_join(CampaignSchema.suggest_file_name(name)), bundle)


func open(save_path: String) -> bool:
	var loaded := CampaignContainer.load_file(save_path)
	if not bool(loaded.get("ok", false)):
		set_status("Could not open: %s" % String(loaded.get("error", "unknown error")))
		return false
	path = String(loaded["path"])
	manifest = loaded["manifest"]
	campaign = loaded["campaign"]
	roster = loaded["roster"]
	locations = loaded["locations"]
	integrity = loaded["integrity"]
	size_on_disk = int(loaded["size"])
	dirty = false
	active_location_id = String(locations[0]["id"]) if not locations.is_empty() else ""
	var characters: Array = roster.get("characters", [])
	active_character_id = String((characters[0] as Dictionary)["id"]) if not characters.is_empty() else ""
	campaign_opened.emit()
	return true


func close() -> void:
	path = ""
	manifest = {}
	campaign = {}
	roster = {"characters": []}
	locations = []
	dirty = false
	active_location_id = ""
	active_character_id = ""


func mark_dirty() -> void:
	dirty = true
	campaign_changed.emit()


func save() -> bool:
	if not is_open():
		return false
	var result := CampaignContainer.save(
		path,
		{"manifest": manifest, "campaign": campaign, "roster": roster, "locations": locations},
	)
	if not bool(result.get("ok", false)):
		set_status(String(result.get("error", "save failed")))
		return false
	manifest = result["manifest"]
	size_on_disk = int(result["size"])
	dirty = false
	set_status("Saved")
	campaign_saved.emit()
	return true


func set_status(message: String) -> void:
	status = message
	status_changed.emit(message)


# -- accessors -------------------------------------------------------------------


func active_location() -> Dictionary:
	for location in locations:
		if String((location as Dictionary)["id"]) == active_location_id:
			return location
	return {}


func characters() -> Array:
	return roster.get("characters", [])


func character_by_id(id: String) -> Dictionary:
	for character in characters():
		if String((character as Dictionary)["id"]) == id:
			return character
	return {}


func active_character() -> Dictionary:
	return character_by_id(active_character_id)


func cover_palette() -> Array:
	return campaign.get("cover_palette", [])


func cover_by_id(id: String) -> Dictionary:
	for cover in cover_palette():
		if String((cover as Dictionary)["id"]) == id:
			return cover
	return {}


func add_character(character: Dictionary) -> void:
	(roster["characters"] as Array).insert(0, character)
	active_character_id = String(character["id"])
	mark_dirty()


func add_cover(cover: Dictionary) -> void:
	(campaign["cover_palette"] as Array).append(cover)
	mark_dirty()


# -- areas ---------------------------------------------------------------------
#
# Map zones are campaign data, not a fixed list. A campaign saved before areas
# existed is migrated on open: the built-in districts become editable records,
# with any per-district overrides it already carried folded in.


func _ensure_areas() -> void:
	CampaignSchema.migrate_areas(campaign)


func areas() -> Array:
	if not is_open():
		return []
	_ensure_areas()
	return campaign["areas"]


func area_by_id(id: String) -> Dictionary:
	return CampaignSchema.area_by_id(campaign, id) if is_open() else {}


func add_area(area: Dictionary) -> void:
	areas().append(area)
	mark_dirty()


func remove_area(id: String) -> int:
	var dropped := CampaignSchema.remove_area(campaign, id)
	mark_dirty()
	return dropped


func hooks_for_area(id: String) -> Array:
	return CampaignSchema.hooks_for_area(campaign, id)
