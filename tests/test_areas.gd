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

	h.describe("points of interest")

	h.it("ships pins with the demo campaign, one linked to a board")
	var demo: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	var pins := CampaignSchema.points_of_interest(demo)
	h.equal(pins.size(), 5, "seeded pin count")
	var parkade := CampaignSchema.poi_by_id(demo, "poi-parkade")
	h.equal(parkade["location_id"], "kabuki-parkade", "parkade links to its board")
	h.equal(CampaignSchema.poi_by_id(demo, "poi-clinic")["location_id"], "", "clinic is only a note")

	h.it("groups pins by the zone they sit in")
	h.equal(CampaignSchema.pois_in_area(demo, "watson").size(), 2, "watson pins")
	h.equal(CampaignSchema.pois_in_area(demo, "westbrook").size(), 1, "westbrook pins")
	h.equal(CampaignSchema.pois_in_area(demo, "north-oak").size(), 0, "empty zone")

	h.it("gives a campaign with no pins an empty list rather than failing")
	var bare: Dictionary = CampaignFixtures.new_campaign("Bare")["campaign"]
	h.equal(CampaignSchema.points_of_interest(bare), [], "empty list")

	h.it("places a new pin in whichever zone it lands in")
	CampaignSchema.migrate_areas(demo)
	var inside := NightCity.new_poi(Vector2(150, 500), NightCity.area_at(demo["areas"], Vector2(150, 500)))
	h.equal(inside["area_id"], "watson", "landed in Watson")
	h.equal(inside["location_id"], "", "starts unlinked")
	var outside := NightCity.new_poi(Vector2(5, 5), NightCity.area_at(demo["areas"], Vector2(5, 5)))
	h.equal(outside["area_id"], "", "bare ground has no zone")

	h.it("round trips pins through the .red container")
	var pin_bundle := CampaignFixtures.blackwall_sunrise()
	var pin_path := "user://test_pois.red"
	h.equal(CampaignContainer.save(pin_path, pin_bundle)["ok"], true, "saved")
	var reopened := CampaignContainer.load_file(pin_path)
	h.equal(reopened["integrity"]["verified"], true, "integrity verified")
	var restored_pin := CampaignSchema.poi_by_id(reopened["campaign"], "poi-parkade")
	h.equal(restored_pin["name"], "Kabuki Parkade", "name survived")
	h.equal(restored_pin["location_id"], "kabuki-parkade", "link survived")
	h.equal(NightCity.poi_position(restored_pin), Vector2(150, 470), "position survived")

	h.it("keeps pins when their zone is deleted, re-homing them")
	var doomed_pins: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	CampaignSchema.migrate_areas(doomed_pins)
	h.equal(CampaignSchema.pois_in_area(doomed_pins, "watson").size(), 2, "watson pins before")
	CampaignSchema.remove_area(doomed_pins, "watson")
	h.equal(CampaignSchema.points_of_interest(doomed_pins).size(), 5, "no pins lost")
	h.equal(CampaignSchema.pois_in_area(doomed_pins, "watson").size(), 0, "none still claim Watson")
	h.equal(
		String(CampaignSchema.poi_by_id(doomed_pins, "poi-parkade")["area_id"]),
		"",
		"re-homed to no zone",
	)
	h.equal(
		String(CampaignSchema.poi_by_id(doomed_pins, "poi-parkade")["location_id"]),
		"kabuki-parkade",
		"its board is untouched",
	)

	h.it("deletes a single pin without touching the others")
	h.equal(CampaignSchema.remove_poi(doomed_pins, "poi-clinic"), true, "removed")
	h.equal(CampaignSchema.points_of_interest(doomed_pins).size(), 4, "one fewer")
	h.equal(CampaignSchema.remove_poi(doomed_pins, "poi-clinic"), false, "already gone")

	h.it("builds a workable blank board for a pin")
	var board := CampaignFixtures.new_location("Ross Clinic", "watson")
	h.equal(board["name"], "Ross Clinic", "name")
	h.equal(board["district_id"], "watson", "district")
	h.equal((board["tiles"] as Array).size(), 256, "16 x 16 of deck")
	h.equal((board["units"] as Array), [], "starts empty")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pin_path))
