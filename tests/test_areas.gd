extends RefCounted

## Map zones are campaign data the GM edits, draws and deletes, so they have to
## survive a save round trip and migrate cleanly from a campaign that predates
## them.

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("map areas")

	h.it("seeds the built-in districts as editable records")
	var campaign: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	CampaignSchema.migrate_areas(campaign)
	var areas: Array = campaign["areas"]
	h.equal(areas.size(), 8, "seeded area count")
	var watson := CampaignSchema.area_by_id(campaign, "watson")
	h.equal(watson["name"], "Watson", "name")
	h.equal(watson["control"], "Maelstrom", "control")
	h.equal(watson["custom"], false, "built-ins are not marked custom")

	h.it("folds an old campaign's district overrides onto the seed")
	# Blackwall carries heat 4 and a note on Watson from before areas existed.
	h.equal(watson["heat"], 4, "override merged")
	h.equal(watson.has("note"), true, "note merged")
	var pacifica := CampaignSchema.area_by_id(campaign, "pacifica")
	h.equal(pacifica["note"], "Pier generator dark since session 12.", "second override merged")

	h.it("does not re-seed a campaign that already has areas")
	(campaign["areas"] as Array).remove_at(0)
	CampaignSchema.migrate_areas(campaign)
	h.equal((campaign["areas"] as Array).size(), 7, "left alone once populated")

	h.it("stores polygons flat so they survive a JSON round trip")
	var points := PackedVector2Array([Vector2(10, 20), Vector2(30, 40), Vector2(50, 60)])
	var area := NightCity.new_area(points)
	h.equal(area["polygon"], [10.0, 20.0, 30.0, 40.0, 50.0, 60.0], "flattened polygon")
	var parsed: Variant = JSON.parse_string(JSON.stringify(area))
	h.equal(typeof(parsed), TYPE_DICTIONARY, "parses back as an object")
	h.equal(NightCity.points_of(parsed), points, "points survive the round trip")
	h.equal(area["custom"], true, "drawn zones are marked custom")
	h.equal(area["danger"], 2, "starts at a neutral danger")

	h.it("places a new zone's label inside its own shape")
	var label := NightCity.label_of(area)
	h.check(label.y <= 60.0, "label sits at or above the lowest corner")

	h.it("round trips a drawn zone through the .red container")
	var bundle := CampaignFixtures.blackwall_sunrise()
	CampaignSchema.migrate_areas(bundle["campaign"])
	var drawn := NightCity.new_area(
		PackedVector2Array([Vector2(100, 100), Vector2(220, 120), Vector2(180, 260)])
	)
	drawn["name"] = "The Sprawl"
	drawn["control"] = "Nobody yet"
	(bundle["campaign"]["areas"] as Array).append(drawn)

	var path := "user://test_areas.red"
	h.equal(CampaignContainer.save(path, bundle)["ok"], true, "saved")
	var loaded := CampaignContainer.load_file(path)
	h.equal(loaded["ok"], true, "loaded")
	h.equal(loaded["integrity"]["verified"], true, "integrity still verified")
	var reloaded: Dictionary = loaded["campaign"]
	h.equal((reloaded["areas"] as Array).size(), 9, "area count after round trip")
	var restored := CampaignSchema.area_by_id(reloaded, String(drawn["id"]))
	h.equal(restored["name"], "The Sprawl", "name survived")
	h.equal(restored["control"], "Nobody yet", "control survived")
	h.equal(NightCity.points_of(restored).size(), 3, "polygon survived")

	h.it("deletes a zone and the hooks that pointed at it")
	var doomed: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	CampaignSchema.migrate_areas(doomed)
	h.equal(CampaignSchema.hooks_for_area(doomed, "watson").size(), 2, "watson hooks before")
	var dropped := CampaignSchema.remove_area(doomed, "watson")
	h.equal(dropped, 2, "hooks dropped with the zone")
	h.equal(CampaignSchema.area_by_id(doomed, "watson"), {}, "zone gone")
	h.equal((doomed["areas"] as Array).size(), 7, "area count after delete")
	h.equal(CampaignSchema.hooks_for_area(doomed, "watson").size(), 0, "no orphan hooks")
	# Hooks in other districts are untouched.
	h.equal(CampaignSchema.hooks_for_area(doomed, "pacifica").size(), 2, "other hooks kept")

	h.it("deleting an unknown zone is a no-op")
	h.equal(CampaignSchema.remove_area(doomed, "nowhere"), 0, "nothing dropped")
	h.equal((doomed["areas"] as Array).size(), 7, "area count unchanged")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
