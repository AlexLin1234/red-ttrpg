extends RefCounted

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("board surfaces")

	h.it("maps every location tile to its generated texture")
	for tile_id in ["deck", "grate", "rubble", "ramp", "water"]:
		var profile := BoardSurfaces.profile_for_tile(tile_id)
		h.equal(profile, tile_id, "%s profile" % tile_id)
		var texture := BoardSurfaces.texture_for(profile)
		h.equal(texture.get_width(), BoardSurfaces.SIZE, "%s texture width" % tile_id)
		h.equal(texture.get_height(), BoardSurfaces.SIZE, "%s texture height" % tile_id)

	h.it("gives location surfaces distinct base colors")
	var seen := {}
	for tile_id in ["deck", "grate", "rubble", "ramp", "water"]:
		var color := BoardSurfaces.color_for_tile(tile_id).to_html()
		h.check(not seen.has(color), "%s has a unique color" % tile_id)
		seen[color] = true

	h.it("maps object materials to an appropriate finish")
	h.equal(BoardSurfaces.profile_for_material("Concrete"), "concrete", "concrete")
	h.equal(BoardSurfaces.profile_for_material("Wood Crate"), "grain", "wood grain")
	h.equal(BoardSurfaces.profile_for_material("Vehicle Hulk"), "corroded", "vehicle corrosion")
	h.equal(BoardSurfaces.profile_for_material("unknown"), "concrete", "safe default")
