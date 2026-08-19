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

	h.it("relocates a pin and assigns the zone under its new position")
	var destination := NightCity.new_area(
		PackedVector2Array([
			Vector2(200, 200), Vector2(400, 200), Vector2(400, 400), Vector2(200, 400)
		])
	)
	destination["id"] = "destination"
	var moved_to := NightCity.relocate_poi(outside, Vector2(300, 300), [destination])
	h.equal(moved_to, Vector2(300, 300), "new position")
	h.equal(NightCity.poi_position(outside), Vector2(300, 300), "coordinates updated")
	h.equal(outside["area_id"], "destination", "new zone assigned")

	h.it("keeps a relocated pin inside the map bounds")
	h.equal(
		NightCity.relocate_poi(outside, Vector2(-50, 900), [destination]),
		Vector2(0, 700),
		"position clamped",
	)
	h.equal(outside["area_id"], "", "clamped position re-homed")

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

	h.describe("reshaping zones")

	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
	])

	h.it("writes moved corners back onto the zone")
	var shaped := NightCity.new_area(square)
	var pulled := square.duplicate()
	pulled[2] = Vector2(160, 140)
	NightCity.set_points(shaped, pulled)
	h.equal(NightCity.points_of(shaped), pulled, "corner moved")
	h.equal(shaped["polygon"].size(), 8, "still stored flat")

	h.it("moves the whole zone with its name")
	var slid := NightCity.new_area(square)
	slid["label"] = [10.0, 90.0]
	NightCity.move_area(slid, Vector2(50, -20))
	h.equal(NightCity.points_of(slid)[0], Vector2(50, -20), "first corner slid")
	h.equal(NightCity.points_of(slid)[2], Vector2(150, 80), "third corner slid")
	h.equal(NightCity.label_of(slid), Vector2(60, 70), "label came along")

	h.it("adds a corner on the edge that was clicked")
	var grown := NightCity.insert_corner(square, 0, Vector2(50, -30))
	h.equal(grown.size(), 5, "one more corner")
	h.equal(grown[1], Vector2(50, -30), "inserted after the clicked edge")
	h.equal(grown[2], Vector2(100, 0), "the rest shifted along")

	h.it("removes a corner but never drops below three")
	var trimmed := NightCity.remove_corner(square, 1)
	h.equal(trimmed.size(), 3, "one fewer")
	h.equal(trimmed[1], Vector2(100, 100), "the right corner went")
	h.equal(NightCity.remove_corner(trimmed, 0).size(), 3, "held at three")
	h.equal(NightCity.remove_corner(square, 99).size(), 4, "out of range is a no-op")

	h.it("offers a midpoint per edge for adding corners")
	var mids := NightCity.edge_midpoints(square)
	h.equal(mids.size(), 4, "one per edge")
	h.equal(mids[0], Vector2(50, 0), "first edge")
	h.equal(mids[3], Vector2(0, 50), "closing edge wraps around")

	h.it("re-homes places when a boundary is redrawn under them")
	var redrawn: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	CampaignSchema.migrate_areas(redrawn)
	h.equal(CampaignSchema.pois_in_area(redrawn, "watson").size(), 2, "watson pins before")
	# Shrink Watson to a corner that contains neither of its pins.
	var watson_area := CampaignSchema.area_by_id(redrawn, "watson")
	NightCity.set_points(
		watson_area,
		PackedVector2Array([Vector2(40, 380), Vector2(70, 380), Vector2(70, 410), Vector2(40, 410)])
	)
	var rehomed := CampaignSchema.rehome_pois(redrawn)
	h.equal(rehomed, 2, "both pins re-checked")
	h.equal(CampaignSchema.pois_in_area(redrawn, "watson").size(), 0, "neither is inside now")
	h.equal(CampaignSchema.points_of_interest(redrawn).size(), 5, "no pins lost")

	h.it("re-homes a place into a zone that grew over it")
	# Stretch Heywood across the clinic's position.
	var heywood := CampaignSchema.area_by_id(redrawn, "heywood")
	NightCity.set_points(
		heywood,
		PackedVector2Array([Vector2(40, 500), Vector2(560, 500), Vector2(560, 660), Vector2(40, 660)])
	)
	CampaignSchema.rehome_pois(redrawn)
	h.equal(
		String(CampaignSchema.poi_by_id(redrawn, "poi-clinic")["area_id"]),
		"heywood",
		"clinic picked up by the grown zone",
	)

	h.it("survives a reshape through the container")
	var shape_bundle := CampaignFixtures.blackwall_sunrise()
	CampaignSchema.migrate_areas(shape_bundle["campaign"])
	var target := CampaignSchema.area_by_id(shape_bundle["campaign"], "pacifica")
	NightCity.move_area(target, Vector2(15, 25))
	var expected := NightCity.points_of(target)
	var shape_path := "user://test_reshape.red"
	h.equal(CampaignContainer.save(shape_path, shape_bundle)["ok"], true, "saved")
	var shape_loaded := CampaignContainer.load_file(shape_path)
	h.equal(shape_loaded["integrity"]["verified"], true, "integrity verified")
	h.equal(
		NightCity.points_of(CampaignSchema.area_by_id(shape_loaded["campaign"], "pacifica")),
		expected,
		"moved outline survived",
	)

	h.it("adopts label-only backdrop zones into areas")
	# An earlier build kept map annotations in gm_map.zones, in 0..1 image
	# coordinates and with no district fields. They are the same thing the zone
	# tool now draws, so opening a campaign converts them once.
	var legacy: Dictionary = CampaignFixtures.blackwall_sunrise()["campaign"]
	legacy["gm_map"] = {
		"name": "night-city.png",
		"png_base64": "stub",
		"zones":
		[
			{
				"id": "zone-1",
				"label": "The Glen",
				"points": [[0.1, 0.1], [0.4, 0.1], [0.4, 0.5], [0.1, 0.5]],
			},
			{"id": "zone-short", "label": "Too few corners", "points": [[0.1, 0.1], [0.2, 0.2]]},
		],
	}
	CampaignSchema.migrate_areas(legacy)
	h.equal((legacy["areas"] as Array).size(), 9, "the drawn zone joined the districts")
	var adopted := CampaignSchema.area_by_id(legacy, "zone-1")
	h.equal(adopted["name"], "The Glen", "its label became the area name")
	h.equal(adopted["control"], "Unclaimed", "it gained the district fields")
	h.equal(
		NightCity.points_of(adopted)[0], Vector2(0.1, 0.1) * NightCity.MAP_SIZE, "scaled into map units"
	)
	h.equal(CampaignSchema.area_by_id(legacy, "zone-short").is_empty(), true, "a 2-point zone is skipped")
	h.equal(((legacy["gm_map"] as Dictionary)["zones"] as Array).is_empty(), true, "the old list is cleared")
	h.equal(String((legacy["gm_map"] as Dictionary)["png_base64"]), "stub", "the backdrop image is kept")

	h.it("does not re-adopt on a second open")
	CampaignSchema.migrate_areas(legacy)
	h.equal((legacy["areas"] as Array).size(), 9, "area count unchanged")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pin_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(shape_path))
