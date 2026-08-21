extends RefCounted

## The `.red` container: it must round-trip, and its integrity check must
## actually catch a tampered file rather than always saying "verified".

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("campaign container")

	var path := "user://test_blackwall.red"
	var bundle := CampaignFixtures.blackwall_sunrise()

	h.it("writes a save and reports its size")
	var saved := CampaignContainer.save(path, bundle)
	h.equal(saved["ok"], true, "save succeeded")
	h.check(int(saved["size"]) > 0, "saved file has a non-zero size")

	h.it("round trips the campaign, roster and locations")
	var loaded := CampaignContainer.load_file(path)
	h.equal(loaded["ok"], true, "load succeeded")
	h.equal(loaded["campaign"]["name"], "Blackwall Sunrise", "campaign name")
	h.equal(loaded["campaign"]["sessions"], 14, "sessions")
	h.equal((loaded["roster"]["characters"] as Array).size(), 21, "roster size")
	h.equal((loaded["locations"] as Array).size(), 1, "locations")
	h.equal(loaded["locations"][0]["name"], "Kabuki Parkade — Level 2", "location name")
	h.equal((loaded["locations"][0]["units"] as Array).size(), 6, "units on the board")

	h.it("verifies integrity against the manifest")
	h.equal(loaded["integrity"]["verified"], true, "integrity verified")
	h.equal(loaded["integrity"]["problems"], PackedStringArray(), "problems")
	h.equal(loaded["manifest"]["format"], CampaignSchema.SAVE_FORMAT, "format")
	h.equal(loaded["manifest"]["version"], CampaignSchema.SAVE_VERSION, "version")

	h.it("catches a tampered entry instead of trusting it")
	# Rewrite campaign.json with different bytes but keep the old manifest, which
	# is exactly what an edited-in-place save would look like.
	var tampered_path := "user://test_tampered.red"
	var packer := ZIPPacker.new()
	h.equal(packer.open(tampered_path), OK, "opened the tampered container")
	packer.start_file(CampaignContainer.MANIFEST)
	packer.write_file(JSON.stringify(loaded["manifest"], "  ").to_utf8_buffer())
	packer.close_file()
	var edited: Dictionary = (loaded["campaign"] as Dictionary).duplicate(true)
	edited["name"] = "Edited By Hand"
	packer.start_file(CampaignContainer.CAMPAIGN)
	packer.write_file(JSON.stringify(edited, "  ").to_utf8_buffer())
	packer.close_file()
	packer.start_file(CampaignContainer.ROSTER)
	packer.write_file(JSON.stringify(loaded["roster"], "  ").to_utf8_buffer())
	packer.close_file()
	packer.close()

	var checked := CampaignContainer.load_file(tampered_path)
	h.equal(checked["ok"], true, "still loads")
	h.equal(checked["integrity"]["verified"], false, "integrity must fail")
	h.check(
		(checked["integrity"]["problems"] as PackedStringArray).size() > 0,
		"reports at least one problem",
	)

	h.it("reads a summary without unpacking the locations")
	var summary := CampaignContainer.read_summary(path)
	h.equal(summary["ok"], true, "summary read")
	h.equal(summary["name"], "Blackwall Sunrise", "name")
	h.equal(summary["players"], 4, "players")
	h.equal(summary["locations"], 1, "location count")
	h.equal(summary["npcs"], 17, "npc count")
	h.equal(summary["hooks"], 5, "open hooks")

	h.it("reports a corrupt save instead of crashing the library listing")
	# A truncated write leaves a real container holding unparseable JSON. The
	# library draws an "unreadable" card for it, which it can only do if the
	# summary comes back as a refusal rather than taking the process down.
	var corrupt_path := "user://test_corrupt.red"
	var corrupt := ZIPPacker.new()
	h.equal(corrupt.open(corrupt_path), OK, "opened the corrupt container")
	corrupt.start_file(CampaignContainer.MANIFEST)
	corrupt.write_file('{"format": "redline", "entr'.to_utf8_buffer())
	corrupt.close_file()
	corrupt.start_file(CampaignContainer.CAMPAIGN)
	corrupt.write_file('{"name": "Half A Sav'.to_utf8_buffer())
	corrupt.close_file()
	corrupt.close()
	var corrupt_summary := CampaignContainer.read_summary(corrupt_path)
	h.equal(corrupt_summary["ok"], false, "corrupt summary refused")
	h.equal(CampaignContainer.load_file(corrupt_path)["ok"], false, "corrupt load refused")

	h.it("summarizes a save whose campaign holds the wrong types")
	# Nothing in a .red is signed, so a hand-edited one can hold anything at any
	# key. The card still has to render.
	var odd_path := "user://test_odd_types.red"
	var odd := ZIPPacker.new()
	h.equal(odd.open(odd_path), OK, "opened the odd container")
	odd.start_file(CampaignContainer.MANIFEST)
	odd.write_file('{"format": "redline", "entries": "not an object"}'.to_utf8_buffer())
	odd.close_file()
	odd.start_file(CampaignContainer.CAMPAIGN)
	odd.write_file('{"name": "Odd", "hooks": "not a list"}'.to_utf8_buffer())
	odd.close_file()
	odd.start_file(CampaignContainer.ROSTER)
	odd.write_file('{"characters": [7, {"kind": "npc"}]}'.to_utf8_buffer())
	odd.close_file()
	odd.close()
	var odd_summary := CampaignContainer.read_summary(odd_path)
	h.equal(odd_summary["ok"], true, "odd summary read")
	h.equal(odd_summary["name"], "Odd", "name")
	h.equal(odd_summary["locations"], 0, "no locations counted")
	h.equal(odd_summary["hooks"], 0, "no hooks counted")
	h.equal(odd_summary["npcs"], 1, "only the one real character counts")

	h.it("refuses a campaign with neither current_month nor a usable clock")
	# The month default used to be computed eagerly, so this indexed a missing
	# clock on every load rather than only on the saves that need it.
	var clockless_path := "user://test_clockless.red"
	var clockless := ZIPPacker.new()
	h.equal(clockless.open(clockless_path), OK, "opened the clockless container")
	clockless.start_file(CampaignContainer.MANIFEST)
	clockless.write_file(
		('{"format": "%s", "entries": {}}' % CampaignSchema.SAVE_FORMAT).to_utf8_buffer()
	)
	clockless.close_file()
	clockless.start_file(CampaignContainer.CAMPAIGN)
	clockless.write_file('{"name": "No Clock"}'.to_utf8_buffer())
	clockless.close_file()
	clockless.close()
	var clockless_loaded := CampaignContainer.load_file(clockless_path)
	h.equal(clockless_loaded["ok"], false, "clockless load refused")
	h.contains(String(clockless_loaded["error"]), "current_month", "names the missing month")

	h.it("rejects a file that is not a container")
	var junk := FileAccess.open("user://not_a_save.red", FileAccess.WRITE)
	junk.store_string("this is not a zip")
	junk.close()
	h.equal(CampaignContainer.load_file("user://not_a_save.red")["ok"], false, "rejected")

	h.it("suggests a file name from the campaign name")
	h.equal(
		CampaignSchema.suggest_file_name("Blackwall Sunrise"), "blackwall_sunrise.red", "slug"
	)
	h.equal(CampaignSchema.suggest_file_name("One-Shot: Pacifica"), "one_shot_pacifica.red", "slug")

	h.it("shares one seriously-wounded threshold with the resolver")
	h.equal(CampaignSchema.serious_wound_threshold(45), 22, "threshold at 45 max HP")
	h.equal(CampaignSchema.serious_wound_threshold(40), 19, "threshold at 40 max HP")

	h.it("advances the clock across a day boundary")
	var clock := {"year": 2045, "month": 9, "day": 14, "hour": 21, "minute": 47}
	var later := CampaignSchema.advance_clock(clock, 60 * 3)
	h.equal(later["day"], 15, "day rolled over")
	h.equal(later["hour"], 0, "hour")
	h.equal(later["minute"], 47, "minute")
	h.equal(CampaignSchema.format_clock(clock), "21:47", "formatted clock")
	h.equal(CampaignSchema.shift_of(clock)["label"], "EVENING", "shift label")

	h.it("totals stats and humanity off a sheet")
	var character: Dictionary = CampaignFixtures.blackwall_sunrise()["roster"]["characters"][0]
	h.check(CampaignSchema.points_spent(character["stats"]) > 0, "points spent")
	h.equal(CampaignSchema.humanity_spent(character["gear"]), 7, "humanity spent")

	h.it("converts a sheet into an encounter actor")
	var actor := CampaignFixtures.actor_input(character)
	h.equal(actor["name"], "Spike Adebayo", "name")
	h.equal(actor["max_hp"], 45, "max hp")
	# Handgun 6 on REF 7 is the best attack skill on the sheet.
	h.equal(actor["attack_base"], 13, "attack base")
	h.equal(actor["armor"]["body"], 11, "body SP")
	h.equal(actor["selected_weapon"], "Heavy Sidearm", "selected weapon")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tampered_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(odd_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(clockless_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://not_a_save.red"))
