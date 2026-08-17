extends RefCounted

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("map assets")

	h.it("normalizes a raster image into a portable campaign value")
	var path := "user://test_map_upload.png"
	var source := Image.create_empty(96, 64, false, Image.FORMAT_RGB8)
	source.fill(Color("16304a"))
	h.equal(source.save_png(path), OK, "fixture saved")
	var loaded := MapAsset.from_file(path)
	h.equal(loaded["ok"], true, "map accepted")
	var map: Dictionary = loaded["map"]
	h.equal(map["name"], "test_map_upload.png", "original name")
	h.equal(map["width"], 96, "width")
	h.equal(map["height"], 64, "height")
	h.check(String(map["png_base64"]).length() > 0, "PNG embedded")
	var decoded := MapAsset.decode(map)
	h.equal(decoded.get_width(), 96, "decoded width")
	h.equal(decoded.get_height(), 64, "decoded height")

	h.it("keeps normalized zones inside the campaign container")
	map["zones"] = [
		{
			"id": "danger-1",
			"label": "Danger",
			"color": "#FF3F67",
			"opacity": 0.3,
			"points": [[0.1, 0.2], [0.8, 0.2], [0.5, 0.9]],
		}
	]
	var bundle := CampaignFixtures.new_campaign("Map Test")
	bundle["campaign"]["gm_map"] = map
	var save_path := "user://test_map.red"
	h.equal(CampaignContainer.save(save_path, bundle)["ok"], true, "campaign saved")
	var zip := ZIPReader.new()
	h.equal(zip.open(save_path), OK, "campaign archive opened")
	h.check(zip.get_files().has(CampaignContainer.MAP_IMAGE), "map stored as its own ZIP entry")
	zip.close()
	var reopened := CampaignContainer.load_file(save_path)
	var saved_map: Dictionary = reopened["campaign"]["gm_map"]
	h.equal(saved_map["zones"][0]["id"], "danger-1", "zone id")
	h.equal(saved_map["zones"][0]["points"][2], [0.5, 0.9], "normalized points")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
