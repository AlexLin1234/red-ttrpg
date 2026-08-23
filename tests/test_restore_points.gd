extends RefCounted

## Named copies of a campaign, kept beside it.
##
## The library drew this list from the demo fixture and the button beside it was
## connected to nothing. These cases cover the other end: taking one, reading it
## back, going to it, and the one rule that is easy to get wrong — restoring a
## point must not delete every point taken since.

const Harness := preload("res://tests/harness.gd")


static func _bundle(name := "Restore Test") -> Dictionary:
	var bundle := CampaignFixtures.blackwall_sunrise()
	var campaign: Dictionary = bundle["campaign"]
	campaign["name"] = name
	campaign["restore_points"] = []
	return bundle


static func _clean(save_path: String) -> void:
	var dir := RestorePoints.dir_for(save_path)
	var access := DirAccess.open(dir)
	if access != null:
		for file_name in access.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(file_name)))
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


static func run(h: Harness) -> void:
	h.describe("restore points")

	var save_path := "user://test_restore.red"
	_clean(save_path)

	h.it("keeps them in a folder named for the save")
	h.contains(RestorePoints.dir_for(save_path), "restore", "under a restore folder")
	h.contains(RestorePoints.dir_for(save_path), "test_restore", "named for the campaign")
	h.contains(RestorePoints.path_for(save_path, "restore-1"), "restore-1.red", "a whole .red")

	h.it("takes one and records it")
	var bundle := _bundle("Before the Parkade")
	CampaignContainer.save(save_path, bundle)
	var entry := RestorePoints.create(save_path, bundle, "Before the Parkade")
	h.equal(bool(entry.get("ok", false)), true, "taken")
	h.equal(String(entry["label"]), "Before the Parkade", "label")
	h.equal(RestorePoints.entries(bundle["campaign"]).size(), 1, "recorded on the campaign")
	h.equal(
		FileAccess.file_exists(RestorePoints.path_for(save_path, String(entry["id"]))),
		true,
		"and written to disk"
	)

	h.it("names an unnamed one rather than leaving it blank")
	var unnamed := RestorePoints.create(save_path, bundle, "   ")
	h.equal(String(unnamed["label"]), "Restore point", "label")

	h.it("lists the newest first")
	var listed := RestorePoints.entries(bundle["campaign"])
	h.equal(String((listed[0] as Dictionary)["id"]), String(unnamed["id"]), "newest first")

	h.it("reads one back, checksums and all")
	var loaded := RestorePoints.load_point(save_path, String(entry["id"]))
	h.equal(bool(loaded.get("ok", false)), true, "loaded")
	h.equal(String((loaded["campaign"] as Dictionary)["name"]), "Before the Parkade", "contents")
	h.equal(bool((loaded["integrity"] as Dictionary)["verified"]), true, "verified")

	h.it("says so when the file is not on this machine")
	var missing := RestorePoints.load_point(save_path, "restore-never")
	h.equal(bool(missing.get("ok", false)), false, "refused")
	h.contains(String(missing["error"]), "not on this machine", "and says why")

	h.it("keeps the live list when restoring, not the restored one")
	# A point is written before it is recorded, so it never contains itself. The
	# first one therefore carries an empty list, and by now there are two.
	# Restoring it must not delete both.
	var restored: Dictionary = loaded["campaign"]
	h.equal(RestorePoints.entries(restored).size(), 0, "the copy carries the list of its own moment")
	RestorePoints.merge_lists(restored, RestorePoints.entries(bundle["campaign"]))
	h.equal(RestorePoints.entries(restored).size(), 2, "and the live list wins")

	h.it("deletes one, file and entry together")
	var doomed_id := String(unnamed["id"])
	h.equal(RestorePoints.remove(save_path, bundle["campaign"], doomed_id), true, "removed")
	h.equal(RestorePoints.entries(bundle["campaign"]).size(), 1, "entry gone")
	h.equal(
		FileAccess.file_exists(RestorePoints.path_for(save_path, doomed_id)), false, "file gone"
	)
	h.equal(RestorePoints.remove(save_path, bundle["campaign"], "restore-never"), false, "no-op")

	h.it("drops the oldest once there are too many")
	var campaign: Dictionary = bundle["campaign"]
	for index in RestorePoints.KEEP + 3:
		RestorePoints.create(save_path, bundle, "Point %d" % index)
	h.equal(RestorePoints.entries(campaign).size(), RestorePoints.KEEP, "capped")
	# The oldest of the batch is the first one taken, and its file goes with it.
	var oldest: Dictionary = RestorePoints.entries(campaign)[RestorePoints.KEEP - 1]
	h.equal(String(oldest["label"]), "Point 3", "the three oldest were dropped")

	h.it("refuses a campaign with no path yet")
	h.equal(bool(RestorePoints.create("", bundle, "x").get("ok", false)), false, "refused")

	_clean(save_path)
