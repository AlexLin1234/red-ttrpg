class_name Autosave
extends RefCounted

## The copy that survives the power cut.
##
## Everything a GM does lives in memory until they press Save, which is fine
## right up until it is not: a session's worth of notes, clock and combat can be
## an hour old and entirely unwritten.
##
## An autosave is a complete `.red` beside the real one, with a suffix that keeps
## it out of the library listing. It is never opened automatically — a GM who
## saved deliberately and then crashed would not thank an app that silently
## reverted them to a stale copy — but it is offered, with its age, so the choice
## is theirs.

const SUFFIX := ".autosave"

## How often the app writes one while the campaign is dirty.
const INTERVAL_SECONDS := 60.0

## Written into the autosaved campaign: the checksum of the saved campaign this
## copy was taken from.
##
## Timestamps cannot answer "is this unsaved work, or residue". Both the file
## system and the manifest record time to the second, so a save followed
## immediately by an autosave is indistinguishable from the reverse. The
## checksum of what was on disk at the time is exact and clock-free.
const BASE_KEY := "autosave_base"


static func path_for(save_path: String) -> String:
	return save_path + SUFFIX


static func exists(save_path: String) -> bool:
	return save_path != "" and FileAccess.file_exists(path_for(save_path))


## Write the bundle beside the save, stamped with the save version it came from.
static func write(save_path: String, bundle: Dictionary) -> Dictionary:
	if save_path == "":
		return {"ok": false, "error": "this campaign has no path yet"}
	var copy := bundle.duplicate(true)
	var campaign: Dictionary = copy.get("campaign", {})
	# The bundle's manifest is the one the last save wrote, so the identity of
	# what is on disk is already in hand and costs no file read.
	campaign[BASE_KEY] = CampaignContainer.entry_digest(copy.get("manifest", {}))
	copy["campaign"] = campaign
	return CampaignContainer.save(path_for(save_path), copy)


static func discard(save_path: String) -> void:
	if exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(save_path)))


static func _identity_of(save_path: String) -> String:
	if not FileAccess.file_exists(save_path):
		return ""
	return CampaignContainer.entry_digest(CampaignContainer.read_manifest(save_path))


## What there is to recover, and whether it is worth offering.
##
## An autosave whose base is not the save's current version is residue: the GM
## saved after it was written, and offering it would invite them to undo their
## own save. One that will not load is not offered either — a recovery the app
## cannot open is worse than none, because the GM stops looking for the work
## somewhere else.
static func summary(save_path: String) -> Dictionary:
	var blank := {"available": false, "newer": false, "modified": 0, "age_seconds": 0}
	if not exists(save_path):
		return blank

	var autosave := path_for(save_path)
	var loaded := CampaignContainer.load_file(autosave)
	if not bool(loaded.get("ok", false)):
		var broken := blank.duplicate()
		broken["available"] = true
		broken["error"] = String(loaded.get("error", "unreadable"))
		return broken

	var base := String((loaded["campaign"] as Dictionary).get(BASE_KEY, ""))
	var modified := FileAccess.get_modified_time(autosave)
	return {
		"available": true,
		"newer": base != "" and base == _identity_of(save_path),
		"modified": modified,
		"age_seconds": maxi(0, int(Time.get_unix_time_from_system()) - modified),
		"path": autosave,
	}


## How old the recovery is, in the words a GM reads it in.
static func describe(save_path: String) -> String:
	var state := summary(save_path)
	if not bool(state.get("newer", false)):
		return ""
	return age_phrase(int(state["age_seconds"]))


static func age_phrase(age_seconds: int) -> String:
	if age_seconds < 90:
		return "Autosave from moments ago"
	if age_seconds < 3600:
		return "Autosave from %d minutes ago" % (age_seconds / 60)
	if age_seconds < 86400:
		return "Autosave from %d hours ago" % (age_seconds / 3600)
	return "Autosave from %d days ago" % (age_seconds / 86400)


## Load the autosave rather than the save. The caller keeps the original path,
## so the next deliberate Save writes back to the real file.
static func load_file(save_path: String) -> Dictionary:
	if not exists(save_path):
		return {"ok": false, "error": "no autosave to recover"}
	var loaded := CampaignContainer.load_file(path_for(save_path))
	if bool(loaded.get("ok", false)):
		# The marker is bookkeeping about the file, not part of the campaign.
		(loaded["campaign"] as Dictionary).erase(BASE_KEY)
	return loaded
