extends Node

const EconomyRules := preload("res://scripts/rules/economy.gd")
const CampaignFlowRules := preload("res://scripts/rules/campaign_flow.gd")

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
## Raised when a map pin asks for its board to be opened.
signal open_location_requested(location_id: String)

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
var _month_undo: Array[Dictionary] = []
var _month_redo: Array[Dictionary] = []


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
	_normalize_downtime_state()
	# A month snapshot only means anything against the campaign it was taken
	# from, so neither stack survives a change of campaign.
	_month_undo.clear()
	_month_redo.clear()
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
	_month_undo.clear()
	_month_redo.clear()


func mark_dirty() -> void:
	dirty = true
	campaign_changed.emit()


func _normalize_downtime_state() -> void:
	CampaignFlowRules.ensure_campaign(campaign)
	if not campaign.has("lifestyle_closed_months"):
		campaign["lifestyle_closed_months"] = []
	if not campaign.has("night_market") or not campaign["night_market"] is Dictionary:
		campaign["night_market"] = {}
	if not campaign.has("gm_map"):
		campaign["gm_map"] = {}
	Rulebooks.ensure_campaign(campaign)
	campaign["current_month"] = Lifestyle.month_key(campaign["clock"])
	if not campaign.has("closed_months"):
		campaign["closed_months"] = campaign["lifestyle_closed_months"]
	for value in characters():
		var character: Dictionary = value
		CharacterRules.ensure_character(character)
		if String(character.get("kind", "npc")) == "pc" or character.has("lifestyle"):
			Lifestyle.ensure_character(character)


func advance_clock(minutes: int) -> void:
	var before: Dictionary = campaign["clock"].duplicate(true)
	var after := CampaignSchema.advance_clock(before, minutes)
	campaign["clock"] = after
	if Lifestyle.month_key(before) != Lifestyle.month_key(after):
		_process_month_end(Lifestyle.month_key(before), Lifestyle.month_key(after))
	else:
		mark_dirty()


func close_month(requested_month: String = "") -> Dictionary:
	var before: Dictionary = campaign["clock"].duplicate(true)
	var closing := Lifestyle.month_key(before)
	if requested_month != "" and requested_month != closing:
		return {"ok": false, "error": "requested month is not the current month"}
	if (campaign.get("lifestyle_closed_months", []) as Array).has(closing):
		set_status("Month %s is already closed" % closing)
		return {"ok": false, "error": "month already closed", "month": closing}
	_month_undo.append({"campaign": campaign.duplicate(true), "roster": roster.duplicate(true)})
	_month_redo.clear()
	var after := Lifestyle.next_month_clock(before)
	campaign["clock"] = after
	return _process_month_end(closing, Lifestyle.month_key(after))


func _process_month_end(closing_month: String, billed_month: String) -> Dictionary:
	var closed: Array = campaign.get("lifestyle_closed_months", [])
	if closed.has(closing_month):
		mark_dirty()
		return campaign.get("last_lifestyle_report", {})
	var report := Lifestyle.settle(characters(), billed_month)
	report["closed_month"] = closing_month
	report["new_month"] = billed_month
	report["ok"] = true
	closed.append(closing_month)
	campaign["lifestyle_closed_months"] = closed
	campaign["closed_months"] = closed.duplicate()
	campaign["current_month"] = billed_month
	campaign["last_lifestyle_report"] = report
	(campaign.get("session_log", []) as Array).push_front(
		{
			"session": int(campaign.get("sessions", 0)),
			"text": "Closed %s: %d Lifestyle payments, %d unpaid."
			% [closing_month, int(report["paid"]), int(report["unpaid"])],
		}
	)
	mark_dirty()
	set_status(
		"Lifestyle: %d paid · %d unpaid" % [int(report["paid"]), int(report["unpaid"])]
	)
	return report


func can_undo_month() -> bool:
	return not _month_undo.is_empty()


func can_redo_month() -> bool:
	return not _month_redo.is_empty()


func undo_month() -> bool:
	if not can_undo_month():
		return false
	_month_redo.append({"campaign": campaign.duplicate(true), "roster": roster.duplicate(true)})
	var snapshot: Dictionary = _month_undo.pop_back()
	campaign = snapshot["campaign"]
	roster = snapshot["roster"]
	mark_dirty()
	set_status("Month close undone")
	return true


func redo_month() -> bool:
	if not can_redo_month():
		return false
	_month_undo.append({"campaign": campaign.duplicate(true), "roster": roster.duplicate(true)})
	var snapshot: Dictionary = _month_redo.pop_back()
	campaign = snapshot["campaign"]
	roster = snapshot["roster"]
	mark_dirty()
	set_status("Month close redone")
	return true


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


# -- GM notes and campaign beats --------------------------------------------------


func beats() -> Array:
	if not is_open():
		return []
	CampaignFlowRules.ensure_campaign(campaign)
	return campaign["beats"]


func beat_by_id(id: String) -> Dictionary:
	return CampaignFlowRules.beat_by_id(campaign, id) if is_open() else {}


func add_beat() -> Dictionary:
	var beat := CampaignFlowRules.new_beat(beats().size())
	beats().append(beat)
	mark_dirty()
	return beat


func move_beat(id: String, point: Vector2) -> bool:
	var beat := beat_by_id(id)
	if beat.is_empty():
		return false
	CampaignFlowRules.set_beat_position(beat, point)
	mark_dirty()
	return true


func connect_beats(from_id: String, to_id: String) -> bool:
	var changed := CampaignFlowRules.link_beats(campaign, from_id, to_id)
	if changed:
		mark_dirty()
	return changed


func disconnect_beats(from_id: String, to_id: String) -> bool:
	var changed := CampaignFlowRules.unlink_beats(campaign, from_id, to_id)
	if changed:
		mark_dirty()
	return changed


func remove_beat(id: String) -> bool:
	var changed := CampaignFlowRules.remove_beat(campaign, id)
	if changed:
		mark_dirty()
	return changed


# -- rulebook assistant -----------------------------------------------------------


## The rulebooks this campaign asks its questions against.
##
## Only IDs live in the save. The books themselves are installed once per machine
## through the Assistant screen, so a campaign can be handed to another GM
## without carrying a byte of anyone's sourcebook.
func active_rulebook_ids() -> Array:
	return Rulebooks.active_ids(campaign) if is_open() else []


func is_rulebook_active(book_id: String) -> bool:
	return is_open() and Rulebooks.is_active(campaign, book_id)


func set_rulebook_active(book_id: String, active: bool) -> bool:
	if not is_open() or not Rulebooks.set_active(campaign, book_id, active):
		return false
	mark_dirty()
	return true


func move_rulebook(book_id: String, delta: int) -> bool:
	if not is_open() or not Rulebooks.move(campaign, book_id, delta):
		return false
	mark_dirty()
	return true


## The active books that this installation holds and has finished indexing.
func searchable_rulebook_ids(installed: Array) -> Array:
	return Rulebooks.searchable_ids(campaign, installed) if is_open() else []


## Names the campaign's assistant history file. It is a local convenience, kept
## in application data rather than in the portable save.
func assistant_campaign_id() -> String:
	return String(campaign.get("id", "")) if is_open() else ""


# -- shared economy ---------------------------------------------------------------


## The active Night Market is campaign state, not character or screen state.
## Once a Fixer organizes it, every character can visit the same stalls.
func night_market() -> Dictionary:
	if not is_open():
		return {}
	if not campaign.has("night_market") or not campaign["night_market"] is Dictionary:
		campaign["night_market"] = {}
	return campaign["night_market"]


func organize_night_market(
	organizer: Dictionary, rng: Dice.RandomSource, catalog: Array = []
) -> Dictionary:
	var available := catalog
	if available.is_empty():
		var item_db := get_node_or_null("/root/ItemDB")
		if item_db == null:
			return {"ok": false, "error": "The item database is not available."}
		available = item_db.call("catalog")
	var rolled := GearMarket.night_market(organizer, available, rng)
	if not bool(rolled.get("ok", false)):
		return rolled
	var shared := {
		"organizer_id": String(organizer.get("id", "")),
		"organizer_name": String(organizer.get("name", "Fixer")),
		"opened_at": campaign.get("clock", {}).duplicate(true),
		"stock": (rolled.get("stock", []) as Array).duplicate(true),
		"categories": Array(rolled.get("categories", PackedStringArray())),
		"midnight": bool(rolled.get("midnight", false)),
	}
	campaign["night_market"] = shared
	(campaign.get("session_log", []) as Array).push_front(
		{
			"session": int(campaign.get("sessions", 0)),
			"text": "%s organized a Night Market for the crew."
			% String(organizer.get("name", "A Fixer")),
		}
	)
	mark_dirty()
	return {"ok": true, "market": shared}


func transfer_cash(source_id: String, recipient_id: String, amount: int) -> Dictionary:
	var source := character_by_id(source_id)
	var recipient := character_by_id(recipient_id)
	var result := EconomyRules.transfer_cash(source, recipient, amount)
	if bool(result.get("ok", false)):
		(campaign.get("session_log", []) as Array).push_front(
			{
				"session": int(campaign.get("sessions", 0)),
				"text": "%s gave %s %deb."
				% [source.get("name", "A character"), recipient.get("name", "someone"), amount],
			}
		)
		mark_dirty()
	return result


func transfer_item(source_id: String, recipient_id: String, gear_index: int) -> Dictionary:
	var source := character_by_id(source_id)
	var recipient := character_by_id(recipient_id)
	var result := EconomyRules.transfer_item(source, recipient, gear_index)
	if bool(result.get("ok", false)):
		(campaign.get("session_log", []) as Array).push_front(
			{
				"session": int(campaign.get("sessions", 0)),
				"text": "%s gave %s to %s."
				% [source.get("name", "A character"), result["item"], recipient.get("name", "someone")],
			}
		)
		mark_dirty()
	return result


## A successful Hustle consumes the full seven free days required by the rule.
func perform_hustle(character_id: String, rng: Dice.RandomSource) -> Dictionary:
	var character := character_by_id(character_id)
	var result := EconomyRules.hustle(character, rng)
	if not bool(result.get("ok", false)):
		return result
	advance_clock(int(result["days"]) * 24 * 60)
	(campaign.get("session_log", []) as Array).push_front(
		{
			"session": int(campaign.get("sessions", 0)),
			"text": "%s hustled for seven days and earned %deb: %s"
			% [character.get("name", "A character"), result["earned"], result["work"]],
		}
	)
	mark_dirty()
	return result


## Several characters can spend the same free-time week Hustling concurrently.
## Every participant rolls and gets paid, but the shared campaign clock advances
## only once for the seven-day downtime block.
func perform_hustles(character_ids: Array, rng: Dice.RandomSource) -> Dictionary:
	var participants: Array[Dictionary] = []
	var seen := {}
	for value in character_ids:
		var id := String(value)
		if seen.has(id):
			continue
		seen[id] = true
		var character := character_by_id(id)
		if character.is_empty():
			return {"ok": false, "error": "A selected character could not be found."}
		var role_key := String(character.get("role_key", ""))
		if not EconomyRules.HUSTLES.has(role_key):
			return {
				"ok": false,
				"error": "%s needs a Role before taking a Hustle."
				% String(character.get("name", "A selected character")),
			}
		var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
		if rank < 1 or rank > 10:
			return {
				"ok": false,
				"error": "%s needs a Role Ability Rank from 1 to 10."
				% String(character.get("name", "A selected character")),
			}
		participants.append(character)
	if participants.is_empty():
		return {"ok": false, "error": "Select at least one character."}

	var results: Array = []
	var total_earned := 0
	for character in participants:
		var result := EconomyRules.hustle(character, rng)
		result["character_id"] = String(character["id"])
		result["name"] = String(character.get("name", "Character"))
		results.append(result)
		total_earned += int(result["earned"])
		(campaign.get("session_log", []) as Array).push_front(
			{
				"session": int(campaign.get("sessions", 0)),
				"text": "%s hustled during the crew's free-time week and earned %deb: %s"
				% [character.get("name", "A character"), result["earned"], result["work"]],
			}
		)

	advance_clock(EconomyRules.HUSTLE_DAYS * 24 * 60)
	mark_dirty()
	return {
		"ok": true,
		"days": EconomyRules.HUSTLE_DAYS,
		"results": results,
		"participants": results.size(),
		"total_earned": total_earned,
	}


func cover_palette() -> Array:
	return campaign.get("cover_palette", [])


func cover_by_id(id: String) -> Dictionary:
	for cover in cover_palette():
		if String((cover as Dictionary)["id"]) == id:
			return cover
	return {}


func add_character(character: Dictionary) -> void:
	CharacterRules.ensure_character(character)
	Lifestyle.ensure_character(character)
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


# -- points of interest ------------------------------------------------------


func points_of_interest() -> Array:
	return CampaignSchema.points_of_interest(campaign) if is_open() else []


func poi_by_id(id: String) -> Dictionary:
	return CampaignSchema.poi_by_id(campaign, id) if is_open() else {}


func pois_in_area(area_id: String) -> Array:
	return CampaignSchema.pois_in_area(campaign, area_id) if is_open() else []


func add_poi(poi: Dictionary) -> void:
	points_of_interest().append(poi)
	mark_dirty()


func relocate_poi(id: String, point: Vector2) -> Dictionary:
	var poi := poi_by_id(id)
	if poi.is_empty():
		return {"ok": false, "error": "Place not found."}
	var before := NightCity.poi_position(poi)
	var after := NightCity.relocate_poi(poi, point, areas())
	if not before.is_equal_approx(after):
		mark_dirty()
	return {
		"ok": true,
		"position": after,
		"area_id": String(poi.get("area_id", "")),
	}


func remove_poi(id: String) -> void:
	CampaignSchema.remove_poi(campaign, id)
	mark_dirty()


func location_by_id(id: String) -> Dictionary:
	for location in locations:
		if String((location as Dictionary)["id"]) == id:
			return location
	return {}


## Build an empty board for a pin and link the two together, so a place on the
## map becomes somewhere the party can actually walk into.
func create_location_for_poi(poi: Dictionary) -> Dictionary:
	var location := CampaignFixtures.new_location(
		String(poi.get("name", "New Location")), String(poi.get("area_id", ""))
	)
	locations.append(location)
	poi["location_id"] = String(location["id"])
	mark_dirty()
	return location


func open_location(location_id: String) -> void:
	if location_by_id(location_id).is_empty():
		return
	active_location_id = location_id
	open_location_requested.emit(location_id)
