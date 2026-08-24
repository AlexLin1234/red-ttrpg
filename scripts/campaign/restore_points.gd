class_name RestorePoints
extends RefCounted

## Named copies of a campaign, kept beside it.
##
## The library has always drawn a list of restore points and a Snapshots button.
## Nothing ever created one: the list came from the demo fixture and the button
## was wired to nothing. This is the other end of it.
##
## A restore point is a whole `.red`, not a diff. A campaign is small, the format
## already verifies itself entry by entry, and a GM restoring "before the
## Parkade" wants the campaign as it was, not a reconstruction of it.

const DIR := "restore"

## How many are kept per campaign before the oldest is dropped.
const KEEP := 12


## Where a campaign's restore points live: a folder beside the save, named after
## it, so two campaigns in one library never mix theirs up.
static func dir_for(save_path: String) -> String:
	return save_path.get_base_dir().path_join(DIR).path_join(save_path.get_file().get_basename())


static func path_for(save_path: String, id: String) -> String:
	return dir_for(save_path).path_join("%s.red" % id)


static func entries(campaign: Dictionary) -> Array:
	if not campaign.has("restore_points") or not campaign["restore_points"] is Array:
		campaign["restore_points"] = []
	return campaign["restore_points"]


static func entry_by_id(campaign: Dictionary, id: String) -> Dictionary:
	for entry in entries(campaign):
		if String((entry as Dictionary)["id"]) == id:
			return entry
	return {}


## Take a restore point. Returns the entry it recorded, or {"ok": false}.
static func create(save_path: String, bundle: Dictionary, label: String) -> Dictionary:
	if save_path == "":
		return {"ok": false, "error": "this campaign has no path yet"}
	var campaign: Dictionary = bundle.get("campaign", {})
	var id := "restore-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_for(save_path)))
	var written := CampaignContainer.save(path_for(save_path, id), bundle)
	if not bool(written.get("ok", false)):
		return {"ok": false, "error": String(written.get("error", "could not write"))}

	var entry := {
		"id": id,
		"label": label if label.strip_edges() != "" else "Restore point",
		"session": int(campaign.get("sessions", 0)),
		"created_at": Time.get_datetime_string_from_system(true),
		"size": int(written.get("size", 0)),
	}
	entries(campaign).push_front(entry)
	prune(save_path, campaign)
	var result := entry.duplicate()
	result["ok"] = true
	return result


## Drop the oldest beyond [constant KEEP], file and entry together.
static func prune(save_path: String, campaign: Dictionary) -> int:
	var kept := entries(campaign)
	var dropped := 0
	while kept.size() > KEEP:
		var oldest: Dictionary = kept.pop_back()
		_delete_file(save_path, String(oldest["id"]))
		dropped += 1
	return dropped


static func _delete_file(save_path: String, id: String) -> void:
	var path := path_for(save_path, id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func remove(save_path: String, campaign: Dictionary, id: String) -> bool:
	var kept := entries(campaign)
	for index in kept.size():
		if String((kept[index] as Dictionary)["id"]) == id:
			kept.remove_at(index)
			_delete_file(save_path, id)
			return true
	return false


## Read one back. Returns [CampaignContainer]'s own result, so integrity travels
## with it: a restore point whose checksums no longer match is reported rather
## than opened.
static func load_point(save_path: String, id: String) -> Dictionary:
	var path := path_for(save_path, id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "that restore point is not on this machine"}
	return CampaignContainer.load_file(path)


## The list a restored campaign should carry.
##
## A restore point holds the list of restore points that existed when it was
## taken, so restoring one would quietly delete every point made since —
## including, usually, the one taken on the way in. The live list wins.
static func merge_lists(restored: Dictionary, live: Array) -> void:
	restored["restore_points"] = live.duplicate(true)
