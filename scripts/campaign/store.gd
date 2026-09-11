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
## Raised when the screen driving the table has new material for the
## player-facing window. The payload travels with the signal rather than being
## fetched, so nothing that listens can read more than it was sent.
signal player_view_changed(payload: Dictionary)

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
var active_architecture_id := ""
var active_vehicle_id := ""
# One snapshot stack for the campaign-level actions that are not part of an
# encounter. Closing a month, awarding IP and awarding Reputation all rewrite
# several sheets at once, which is exactly the shape that is miserable to put
# back by hand; each pushes the whole campaign and roster before it acts. An
# encounter has its own event-based undo and does not come through here.
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _player_view: Dictionary = {}
var _autosave_seconds := 0.0
var _recovery: Dictionary = {}
## Off only for tests and for a GM who wants the disk left alone.
var autosave_enabled := true
var last_autosave := 0
## Bumped on every edit. Screens are kept alive between visits, and this is how
## one of them knows whether what it drew is still what the campaign says.
var edit_revision := 0


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
	_undo_stack.clear()
	_redo_stack.clear()
	edit_revision += 1
	_autosave_seconds = 0.0
	# An autosave newer than the file is the residue of a session that did not
	# end cleanly. It is offered rather than applied: a GM who saved and then
	# crashed would not thank an app that silently reverted them.
	var found := Autosave.summary(path)
	_recovery = found if bool(found.get("newer", false)) else {}
	# Never carry one campaign's board onto the table's screen while another one
	# is being opened.
	publish_player_view({})
	campaign_opened.emit()
	return true


## Hand the player window something new to draw.
##
## Anything but a screen actively running the table should be publishing {},
## which blanks the display rather than leaving the last fight on the TV.
func publish_player_view(payload: Dictionary) -> void:
	_player_view = payload
	player_view_changed.emit(payload)


func player_view() -> Dictionary:
	return _player_view


func close() -> void:
	edit_revision += 1
	publish_player_view({})
	path = ""
	manifest = {}
	campaign = {}
	roster = {"characters": []}
	locations = []
	dirty = false
	active_location_id = ""
	active_character_id = ""
	active_architecture_id = ""
	active_vehicle_id = ""
	_recovery = {}
	_undo_stack.clear()
	_redo_stack.clear()


func mark_dirty() -> void:
	dirty = true
	edit_revision += 1
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
	_snapshot("Month close")
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


## Record where the campaign stands before an action that rewrites sheets.
##
## [param label] is what the undo button will offer to take back, so it names
## the action rather than describing it — "Month close", "IP award".
func _snapshot(label: String) -> void:
	_undo_stack.append(
		{
			"label": label,
			"campaign": campaign.duplicate(true),
			"roster": roster.duplicate(true),
		}
	)
	_redo_stack.clear()


func can_undo_campaign() -> bool:
	return not _undo_stack.is_empty()


func can_redo_campaign() -> bool:
	return not _redo_stack.is_empty()


## What undo would take back, for the button that offers it.
func undo_label() -> String:
	if _undo_stack.is_empty():
		return ""
	return String((_undo_stack.back() as Dictionary).get("label", ""))


func redo_label() -> String:
	if _redo_stack.is_empty():
		return ""
	return String((_redo_stack.back() as Dictionary).get("label", ""))


func undo_campaign() -> bool:
	if not can_undo_campaign():
		return false
	var snapshot: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(
		{
			"label": String(snapshot.get("label", "")),
			"campaign": campaign.duplicate(true),
			"roster": roster.duplicate(true),
		}
	)
	campaign = snapshot["campaign"]
	roster = snapshot["roster"]
	mark_dirty()
	set_status("%s undone" % String(snapshot.get("label", "Action")))
	return true


func redo_campaign() -> bool:
	if not can_redo_campaign():
		return false
	var snapshot: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(
		{
			"label": String(snapshot.get("label", "")),
			"campaign": campaign.duplicate(true),
			"roster": roster.duplicate(true),
		}
	)
	campaign = snapshot["campaign"]
	roster = snapshot["roster"]
	mark_dirty()
	set_status("%s redone" % String(snapshot.get("label", "Action")))
	return true


# The month keeps its own names because the City screen asks about the month
# rather than about the stack.
func can_undo_month() -> bool:
	return can_undo_campaign()


func can_redo_month() -> bool:
	return can_redo_campaign()


func undo_month() -> bool:
	return undo_campaign()


func redo_month() -> bool:
	return redo_campaign()


func save() -> bool:
	if not is_open():
		return false
	var result := CampaignContainer.save(path, _bundle())
	if not bool(result.get("ok", false)):
		set_status(String(result.get("error", "save failed")))
		return false
	manifest = result["manifest"]
	size_on_disk = int(result["size"])
	dirty = false
	# The autosave existed only to cover the gap between edits and this moment.
	Autosave.discard(path)
	_autosave_seconds = 0.0
	set_status("Saved")
	campaign_saved.emit()
	return true


## Write the working copy beside the save, on a timer, while there is anything
## to lose.
##
## Runs from the autoload's own process loop rather than a Timer node so it is
## impossible to lose by rebuilding a screen.
func _process(delta: float) -> void:
	if not autosave_enabled or not is_open() or not dirty or path == "":
		return
	_autosave_seconds += delta
	if _autosave_seconds < Autosave.INTERVAL_SECONDS:
		return
	autosave_now()


func autosave_now() -> bool:
	_autosave_seconds = 0.0
	if not is_open() or path == "":
		return false
	var result := Autosave.write(path, _bundle())
	if not bool(result.get("ok", false)):
		# A failed autosave is not worth interrupting a session over, but it is
		# worth saying once rather than failing silently.
		set_status("Autosave failed: %s" % String(result.get("error", "unknown error")))
		return false
	last_autosave = int(Time.get_unix_time_from_system())
	return true


## What the open campaign could be rolled forward to, if anything.
func recovery() -> Dictionary:
	return _recovery


## Load the autosave in place of what is open, keeping the real save's path so
## the next deliberate Save writes back to the file the GM thinks they are in.
func recover() -> bool:
	var save_path := path
	var loaded := Autosave.load_file(save_path)
	if not bool(loaded.get("ok", false)):
		set_status("Could not recover: %s" % String(loaded.get("error", "unknown error")))
		return false
	manifest = loaded["manifest"]
	campaign = loaded["campaign"]
	roster = loaded["roster"]
	locations = loaded["locations"]
	integrity = loaded["integrity"]
	path = save_path
	dirty = true
	_recovery = {}
	_normalize_downtime_state()
	_undo_stack.clear()
	_redo_stack.clear()
	edit_revision += 1
	publish_player_view({})
	set_status("Recovered from autosave · unsaved")
	campaign_opened.emit()
	return true


## Throw the recovery away and keep what was opened.
func discard_recovery() -> void:
	Autosave.discard(path)
	_recovery = {}
	campaign_changed.emit()


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


# -- sessions and restore points ------------------------------------------------


func _bundle() -> Dictionary:
	return {"manifest": manifest, "campaign": campaign, "roster": roster, "locations": locations}


## Add a line to the session log by hand.
##
## Everything else writes to the log as a side effect of doing something. This
## is for what happened at the table, which the app has no way to know about.
func log_line(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed == "" or not is_open():
		return false
	(campaign.get("session_log", []) as Array).push_front(
		{"session": int(campaign.get("sessions", 0)), "text": trimmed}
	)
	mark_dirty()
	return true


## Take a named copy of the campaign as it stands.
func create_restore_point(label: String) -> Dictionary:
	if not is_open():
		return {"ok": false, "error": "no campaign is open"}
	var entry := RestorePoints.create(path, _bundle(), label)
	if not bool(entry.get("ok", false)):
		set_status(String(entry.get("error", "could not take a restore point")))
		return entry
	mark_dirty()
	set_status("Restore point taken")
	return entry


## Put the campaign back to one of them.
##
## Loaded as unsaved changes, exactly as a recovery is: the file on disk is what
## the GM last chose to write, and going back is a decision they should confirm
## with a save rather than have made for them.
func restore_to(id: String) -> bool:
	if not is_open():
		return false
	var loaded := RestorePoints.load_point(path, id)
	if not bool(loaded.get("ok", false)):
		set_status("Could not restore: %s" % String(loaded.get("error", "unknown error")))
		return false

	var live := RestorePoints.entries(campaign).duplicate(true)
	var restored: Dictionary = loaded["campaign"]
	RestorePoints.merge_lists(restored, live)
	campaign = restored
	roster = loaded["roster"]
	locations = loaded["locations"]
	integrity = loaded["integrity"]
	dirty = true
	edit_revision += 1
	active_location_id = String(locations[0]["id"]) if not locations.is_empty() else ""
	var characters_list: Array = roster.get("characters", [])
	active_character_id = (
		String((characters_list[0] as Dictionary)["id"]) if not characters_list.is_empty() else ""
	)
	_normalize_downtime_state()
	_undo_stack.clear()
	_redo_stack.clear()
	publish_player_view({})
	set_status("Restored · unsaved")
	campaign_opened.emit()
	return true


func remove_restore_point(id: String) -> bool:
	if not is_open() or not RestorePoints.remove(path, campaign, id):
		return false
	mark_dirty()
	return true


func restore_points() -> Array:
	return RestorePoints.entries(campaign)


## Start a session: count it, log it, and take the restore point a GM will want
## when the evening goes somewhere they did not plan for.
func start_session() -> int:
	if not is_open():
		return 0
	var number := int(campaign.get("sessions", 0)) + 1
	campaign["sessions"] = number
	create_restore_point("Start of session %d" % number)
	log_line("Session %d started." % number)
	set_status("Session %d" % number)
	return number


func end_session(summary := "") -> int:
	if not is_open():
		return 0
	var number := int(campaign.get("sessions", 0))
	log_line(summary if summary.strip_edges() != "" else "Session %d ended." % number)
	create_restore_point("End of session %d" % number)
	return number


## Roll a squad onto the roster and hand the sheets back.
##
## The board still has to place them; this only makes them exist, which is the
## part the GM was previously doing one mook at a time in the Forge.
func spawn_squad(squad_key: String, count: int, rng: Dice.RandomSource) -> Array[Dictionary]:
	var members := EncounterTables.roll_squad(squad_key, count, rng)
	for member in members:
		add_character(member)
	if not members.is_empty():
		(campaign.get("session_log", []) as Array).push_front(
			{
				"session": int(campaign.get("sessions", 0)),
				"text": "%d %s rolled onto the roster"
				% [members.size(), String(EncounterTables.squad(squad_key)["label"])],
			}
		)
		mark_dirty()
	return members


## Roll what is happening on this corner, and keep it where the GM can read it.
func roll_street_encounter(rng: Dice.RandomSource) -> Dictionary:
	var rolled := EncounterTables.roll_street(rng)
	campaign["last_street_encounter"] = rolled
	(campaign.get("session_log", []) as Array).push_front(
		{"session": int(campaign.get("sessions", 0)), "text": String(rolled["text"])}
	)
	mark_dirty()
	return rolled


func last_street_encounter() -> Dictionary:
	return campaign.get("last_street_encounter", {})


## Run one downtime action, advance the clock by what it took, and log it.
##
## The dispatch lives here rather than in [Downtime] for the same reason the
## Hustle's does: the rules module does not know about a campaign clock or a
## session log, and should not learn.
func perform_downtime(
	action_key: String, params: Dictionary, rng: Dice.RandomSource
) -> Dictionary:
	var character := character_by_id(String(params.get("character_id", "")))
	if character.is_empty():
		return {"ok": false, "error": "That character is not in this campaign."}

	var result := {}
	match action_key:
		"facedown":
			var opponent := character_by_id(String(params.get("opponent_id", "")))
			if opponent.is_empty():
				return {"ok": false, "error": "A Facedown needs someone to face."}
			result = Downtime.facedown(character, opponent, rng)
		"recover":
			result = Downtime.recover(
				character,
				maxi(1, int(params.get("days", 1))),
				character_by_id(String(params.get("medic_id", ""))),
				rng,
			)
		"therapy":
			result = Downtime.therapy(character, maxi(1, int(params.get("weeks", 1))), rng)
		"fabricate":
			result = Downtime.fabricate(character, params.get("item", {}), rng)
		"source":
			result = Downtime.source_gear(character, rng)
		"reputation":
			result = Downtime.adjust_reputation(
				character, int(params.get("delta", 0)), String(params.get("reason", ""))
			)
		_:
			return {"ok": false, "error": "Unknown downtime action: %s" % action_key}

	if not bool(result.get("ok", false)):
		return result

	(campaign.get("session_log", []) as Array).push_front(
		{"session": int(campaign.get("sessions", 0)), "text": String(result.get("work", ""))}
	)
	var days := int(result.get("days", 0))
	if days > 0:
		advance_clock(days * 24 * 60)
	else:
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


## The blocks the Location screen can place, plus every car in the garage.
##
## A vehicle parked on a board is cover with a wreck value, so it belongs in the
## same palette rather than in a system of its own: line of sight, ablation and
## the cover prompt all then work on it unchanged.
# -- lifepath, IP and reputation ------------------------------------------------


## The Lifepath tables this campaign rolls against.
##
## Campaign-held like the combat tables, so a GM running a game somewhere other
## than Night City can replace the questions as well as the answers, and a
## campaign carries its own history-making with it.
func lifepath_tables() -> Lifepath:
	return Lifepath.new(campaign.get("lifepath_tables", LifepathDefault.document()))


## Roll a whole history for one character.
##
## Returns the lifepath written. Snapshotted rather than event-undone because a
## re-roll replaces every field at once, and the thing a GM wants back is the
## sheet as it stood.
func roll_lifepath(character_id: String, rng: Dice.RandomSource) -> Dictionary:
	var character := character_by_id(character_id)
	if character.is_empty():
		return {}
	_snapshot("Lifepath roll")
	var rolled := lifepath_tables().roll(String(character.get("role_key", "")), rng)
	Lifepath.apply(
		character, Lifepath.write_event(character_id, character.get("lifepath", {}), rolled)
	)
	(campaign.get("session_log", []) as Array).push_front(
		{
			"session": int(campaign.get("sessions", 0)),
			"text": "Rolled a lifepath for %s" % String(character.get("name", "a character")),
		}
	)
	mark_dirty()
	set_status("Lifepath rolled for %s" % String(character.get("name", "")))
	return rolled


## Hand-write one answer. The GM overrules the dice more often than they roll.
func set_lifepath_field(character_id: String, key: String, text: String) -> bool:
	var character := character_by_id(character_id)
	if character.is_empty():
		return false
	var lifepath: Dictionary = character.get("lifepath", {})
	var before := String(lifepath.get(key, ""))
	if before == text:
		return false
	Lifepath.apply(character, Lifepath.set_field_event(character_id, key, before, text))
	mark_dirty()
	return true


## Add one more year to a history.
func add_life_event(character_id: String, rng: Dice.RandomSource) -> String:
	var character := character_by_id(character_id)
	if character.is_empty():
		return ""
	if Lifepath.life_events(character).size() >= Lifepath.MAX_LIFE_EVENTS:
		set_status("That is as much history as a sheet holds")
		return ""
	var text := lifepath_tables().roll_life_event(rng)
	if text == "":
		return ""
	Lifepath.apply(character, Lifepath.add_event_event(character_id, text))
	mark_dirty()
	return text


func remove_life_event(character_id: String, index: int) -> bool:
	var character := character_by_id(character_id)
	if character.is_empty():
		return false
	var lifepath: Dictionary = character.get("lifepath", {})
	var events: Array = lifepath.get("events", [])
	if index < 0 or index >= events.size():
		return false
	events.remove_at(index)
	lifepath["events"] = events
	character["lifepath"] = lifepath
	mark_dirty()
	return true


## Give out Improvement Points.
##
## IP had a sink and no source: it could be spent on a skill or a Role rank, but
## the only way to grant it was to type a number into one sheet at a time. This
## is the moment it is actually handed out — end of session, to everyone who was
## at the table — and it goes in the log so a GM can see what they gave and when.
func award_improvement_points(amount: int, character_ids: PackedStringArray) -> Dictionary:
	if amount == 0 or character_ids.is_empty():
		return {"ok": false, "error": "nothing to award"}
	_snapshot("IP award")
	var names := PackedStringArray()
	for character_id in character_ids:
		var character := character_by_id(character_id)
		if character.is_empty():
			continue
		character["improvement_points"] = maxi(
			0, int(character.get("improvement_points", 0)) + amount
		)
		names.append(String(character.get("name", "")))
	if names.is_empty():
		_undo_stack.pop_back()
		return {"ok": false, "error": "none of those characters are on the roster"}
	var text := (
		"Awarded %d IP to %s" % [amount, ", ".join(names)]
		if amount > 0
		else "Took %d IP back from %s" % [-amount, ", ".join(names)]
	)
	(campaign.get("session_log", []) as Array).push_front(
		{"session": int(campaign.get("sessions", 0)), "text": text}
	)
	mark_dirty()
	set_status(text)
	return {"ok": true, "amount": amount, "names": names}


## Move a character's Reputation, and say why.
##
## Reputation was read by a Facedown and written by nothing, so it never moved.
## It moves here, and the reason goes into the session log beside it, because a
## number that changed for a forgotten reason is worse than no number.
func award_reputation(character_id: String, delta: int, reason: String) -> Dictionary:
	var character := character_by_id(character_id)
	if character.is_empty():
		return {"ok": false, "error": "no such character"}
	if delta == 0:
		return {"ok": false, "error": "nothing to award"}
	_snapshot("Reputation award")
	var before := clampi(int(character.get("reputation", 0)), 0, CharacterRules.REPUTATION_MAX)
	var after := clampi(before + delta, 0, CharacterRules.REPUTATION_MAX)
	character["reputation"] = after
	var name := String(character.get("name", ""))
	var text := "%s: Reputation %d → %d" % [name, before, after]
	if reason.strip_edges() != "":
		text += " · %s" % reason.strip_edges()
	(campaign.get("session_log", []) as Array).push_front(
		{"session": int(campaign.get("sessions", 0)), "text": text}
	)
	mark_dirty()
	set_status(text)
	return {"ok": true, "before": before, "after": after}


func cover_palette() -> Array:
	var palette: Array = (campaign.get("cover_palette", []) as Array).duplicate(true)
	for entry in vehicles():
		palette.append(Vehicles.as_cover(entry))
	return palette


func vehicles() -> Array:
	CampaignSchema.ensure_vehicles(campaign)
	return campaign["vehicles"]


func vehicle_by_id(id: String) -> Dictionary:
	return CampaignSchema.vehicle_by_id(campaign, id)


func add_vehicle(vehicle: Dictionary) -> void:
	vehicles().append(vehicle)
	active_vehicle_id = String(vehicle["id"])
	mark_dirty()


func remove_vehicle(id: String) -> bool:
	if not CampaignSchema.remove_vehicle(campaign, id):
		return false
	if active_vehicle_id == id:
		active_vehicle_id = ""
	mark_dirty()
	return true


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


func architectures() -> Array:
	CampaignSchema.ensure_architectures(campaign)
	return campaign["architectures"]


func architecture_by_id(id: String) -> Dictionary:
	return CampaignSchema.architecture_by_id(campaign, id)


func add_architecture(architecture: Dictionary) -> void:
	architectures().append(architecture)
	active_architecture_id = String(architecture["id"])
	mark_dirty()


func remove_architecture(id: String) -> bool:
	if not CampaignSchema.remove_architecture(campaign, id):
		return false
	if active_architecture_id == id:
		active_architecture_id = ""
	mark_dirty()
	return true


func active_architecture() -> Dictionary:
	var found := architecture_by_id(active_architecture_id)
	if not found.is_empty():
		return found
	var all := architectures()
	return all[0] if not all.is_empty() else {}


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
