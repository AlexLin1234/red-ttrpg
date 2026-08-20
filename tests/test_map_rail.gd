extends RefCounted

const Harness := preload("res://tests/harness.gd")


## The map rail sits beside the map in an HBox, so anything it reports as a
## minimum width is taken out of the map. Letting a hovered zone or place widen
## the rail rescales the map, slides the polygon out from under the pointer and
## starts a hover flicker loop, so the clamp has to hold a constant width no
## matter what is put inside it.
static func run(h: Harness) -> void:
	h.describe("map detail rail")

	var wide := Control.new()
	wide.custom_minimum_size = Vector2(900, 40)

	h.it("keeps one width whatever its contents ask for")
	var rail: Container = FixedWidthRail.new()
	rail.add_child(wide)
	h.equal(rail.get_combined_minimum_size().x, FixedWidthRail.WIDTH, "clamped width")
	h.check(rail.clip_contents, "overflow is clipped rather than pushed onto the map")

	h.it("does not let its contents drive its height either")
	h.equal(rail.get_combined_minimum_size().y, 0.0, "no minimum height")

	h.it("clamps a width the engine's own containers would have propagated")
	var loose := PanelContainer.new()
	var same := Control.new()
	same.custom_minimum_size = Vector2(900, 40)
	loose.add_child(same)
	h.check(
		loose.get_combined_minimum_size().x > FixedWidthRail.WIDTH,
		"a plain PanelContainer really would have widened the rail"
	)
	loose.free()

	rail.free()
