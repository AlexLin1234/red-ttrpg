extends RefCounted

## The copy that survives the power cut.
##
## What these cases protect: an autosave is a real campaign file, it stays out
## of the library listing, and it is only ever offered when it is actually
## newer than the save it sits beside.

const Harness := preload("res://tests/harness.gd")


static func _bundle(name := "Autosave Test") -> Dictionary:
	var bundle := CampaignFixtures.blackwall_sunrise()
	(bundle["campaign"] as Dictionary)["name"] = name
	return bundle


static func _temp(file_name: String) -> String:
	return "user://%s" % file_name


static func _clean(save_path: String) -> void:
	for candidate in [save_path, Autosave.path_for(save_path)]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


static func run(h: Harness) -> void:
	h.describe("autosave")

	var save_path := _temp("test_autosave.red")
	_clean(save_path)

	h.it("sits beside the save under a suffix")
	h.equal(Autosave.path_for(save_path), save_path + ".autosave", "path")
	h.equal(Autosave.exists(save_path), false, "nothing there yet")
	h.equal(Autosave.summary(save_path)["available"], false, "and nothing to offer")

	h.it("writes a campaign file a reader can open")
	var saved := CampaignContainer.save(save_path, _bundle("Saved"))
	h.equal(bool(saved.get("ok", false)), true, "save")
	# The working bundle carries the manifest the last save wrote, which is how
	# the autosave knows which version of the file it is the unsaved work of.
	var working := _bundle("Autosaved")
	working["manifest"] = saved["manifest"]
	var written := Autosave.write(save_path, working)
	h.equal(bool(written.get("ok", false)), true, "autosave written")
	h.equal(Autosave.exists(save_path), true, "and it is there")
	var loaded := Autosave.load_file(save_path)
	h.equal(bool(loaded.get("ok", false)), true, "and it loads")
	h.equal(String((loaded["campaign"] as Dictionary)["name"]), "Autosaved", "with its own contents")

	h.it("carries the save version it was taken from")
	h.not_contains((loaded["campaign"] as Dictionary).keys(), Autosave.BASE_KEY, "recovered clean")
	var raw := CampaignContainer.load_file(Autosave.path_for(save_path))
	h.contains((raw["campaign"] as Dictionary).keys(), Autosave.BASE_KEY, "but stamped on disk")

	h.it("offers itself while it is the unsaved work of the current save")
	var state := Autosave.summary(save_path)
	h.equal(state["available"], true, "available")
	h.equal(state["newer"], true, "newer")
	h.check(String(Autosave.describe(save_path)) != "", "and says how old it is")

	h.it("stays quiet once the save has caught up")
	# Saving again is what makes the autosave residue. Offering it then would
	# invite a GM to undo their own save — and modification times are recorded
	# to the second, so the stamp rather than the clock is what decides.
	CampaignContainer.save(save_path, _bundle("Saved again"))
	var caught_up := Autosave.summary(save_path)
	h.equal(caught_up["available"], true, "the file is still on disk")
	h.equal(caught_up["newer"], false, "but it is not this save's unsaved work")
	h.equal(Autosave.describe(save_path), "", "so there is nothing to say")

	h.it("throws itself away when asked")
	Autosave.discard(save_path)
	h.equal(Autosave.exists(save_path), false, "gone")
	h.equal(bool(Autosave.load_file(save_path).get("ok", false)), false, "and unloadable")

	h.it("refuses to write for a campaign with no path yet")
	h.equal(bool(Autosave.write("", _bundle()).get("ok", false)), false, "refused")

	h.it("does not offer a copy that was never stamped")
	# A bundle with no manifest has never been saved, so there is no version for
	# the copy to be the unsaved work of.
	Autosave.write(save_path, _bundle("Unstamped"))
	h.equal(Autosave.summary(save_path)["newer"], false, "not offered")
	Autosave.discard(save_path)

	h.it("describes its age in the words a GM reads it in")
	h.equal(Autosave.age_phrase(5), "Autosave from moments ago", "seconds")
	h.equal(Autosave.age_phrase(600), "Autosave from 10 minutes ago", "minutes")
	h.equal(Autosave.age_phrase(7200), "Autosave from 2 hours ago", "hours")
	h.equal(Autosave.age_phrase(172800), "Autosave from 2 days ago", "days")

	h.it("stays out of the library listing")
	h.equal(Autosave.SUFFIX, ".autosave", "not a .red")
	h.check(Autosave.INTERVAL_SECONDS > 0.0, "and it writes on an interval")

	_clean(save_path)
