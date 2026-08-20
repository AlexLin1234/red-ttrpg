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

	h.it("wraps what it is given rather than letting it run off the edge")
	var column := VBoxContainer.new()
	var name_label := UI.display("Northside Industrial Reclamation District", 30)
	column.add_child(name_label)
	var action := UI.primary_button("Close month · confirm each Lifestyle")
	column.add_child(action)
	var summary := UI.elide(UI.micro("Combat zone · Maelstrom and the Voodoo Boys"))
	column.add_child(summary)
	var row := UI.hbox()
	var heading := UI.micro("Areas")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var count := UI.micro("8 drawn")
	row.add_child(count)
	column.add_child(row)

	var wrapping: Container = FixedWidthRail.new()
	wrapping.add_child(column)
	wrapping.notification(Container.NOTIFICATION_SORT_CHILDREN)

	h.equal(name_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "a long name wraps")
	h.equal(action.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "a long button caption wraps")
	h.check(
		column.get_combined_minimum_size().x <= FixedWidthRail.WIDTH,
		"the wrapped column no longer asks for more room than the rail has"
	)

	h.it("leaves alone the captions that wrapping would not help")
	h.equal(summary.autowrap_mode, TextServer.AUTOWRAP_OFF, "a label set to elide still elides")
	h.equal(heading.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the expanding half of a row wraps")
	h.equal(
		count.autowrap_mode,
		TextServer.AUTOWRAP_OFF,
		"the short caption beside it keeps its one line instead of a column of letters"
	)
	wrapping.free()

	h.it("letterspaces without opening a place to break inside a word")
	var word := UI._letterspace("RECLAMATION")
	var phrase := UI._letterspace("SELECTED ZONE")
	var unbroken := UI.BODY_BOLD_FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).y
	# Narrow enough that the word cannot fit: it has to stay on one line anyway,
	# because the spaces holding its letters apart are not breakable.
	h.equal(
		UI.BODY_BOLD_FONT.get_multiline_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, 40.0, 11).y,
		unbroken,
		"a letterspaced word stays whole"
	)
	h.equal(
		UI.BODY_BOLD_FONT.get_multiline_string_size(phrase, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 11).y,
		unbroken * 2.0,
		"two letterspaced words still wrap onto two lines"
	)

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
