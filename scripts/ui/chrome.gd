class_name Chrome
extends RefCounted

## The drawn parts of the visual system: chamfered frames, glowing rules, and
## the small geometric marks the panels are trimmed with.
##
## A StyleBoxFlat can only ever be a rectangle with rounded corners, which is
## why the console read as a stack of boxes. Everything here draws its own
## geometry instead — cut corners, corner brackets, diagonal fill patterns and
## the halo passes that make a line look lit — so the chrome can carry angles
## the engine's own styleboxes have no way to express.
##
## The glow is faked, deliberately. A real bloom pass would mean a second
## viewport and an environment on a 2D UI, and would light up the text as well
## as the lines. Stacking two or three progressively wider, progressively
## fainter strokes under the bright one costs nothing and reads the same at the
## sizes the console is drawn at.

## Which corners of a frame are cut away. Combined as flags.
const CUT_TOP_LEFT := 1
const CUT_TOP_RIGHT := 2
const CUT_BOTTOM_RIGHT := 4
const CUT_BOTTOM_LEFT := 8

## The house cut: opposite corners, so a panel reads as a parallelogram hint
## rather than a rounded box.
const CUT_DIAGONAL := CUT_TOP_LEFT | CUT_BOTTOM_RIGHT
const CUT_ALL := CUT_TOP_LEFT | CUT_TOP_RIGHT | CUT_BOTTOM_RIGHT | CUT_BOTTOM_LEFT

## How much of a rect the corner cuts may eat before they are scaled back. Two
## cuts meeting in the middle of a short edge would erase the edge entirely, so
## a 40px-tall row gets a proportionally smaller cut than a full-height panel.
const CUT_LIMIT := 0.36


## The outline of a chamfered rect, clockwise from the top-left corner.
static func outline(rect: Rect2, cut: float, corners: int) -> PackedVector2Array:
	var left := rect.position.x
	var top := rect.position.y
	var right := left + rect.size.x
	var bottom := top + rect.size.y
	var size := fit_cut(rect, cut)
	var points := PackedVector2Array()
	if size <= 0.5:
		points.append(Vector2(left, top))
		points.append(Vector2(right, top))
		points.append(Vector2(right, bottom))
		points.append(Vector2(left, bottom))
		return points

	if corners & CUT_TOP_LEFT:
		points.append(Vector2(left + size, top))
	else:
		points.append(Vector2(left, top))
	if corners & CUT_TOP_RIGHT:
		points.append(Vector2(right - size, top))
		points.append(Vector2(right, top + size))
	else:
		points.append(Vector2(right, top))
	if corners & CUT_BOTTOM_RIGHT:
		points.append(Vector2(right, bottom - size))
		points.append(Vector2(right - size, bottom))
	else:
		points.append(Vector2(right, bottom))
	if corners & CUT_BOTTOM_LEFT:
		points.append(Vector2(left + size, bottom))
		points.append(Vector2(left, bottom - size))
	else:
		points.append(Vector2(left, bottom))
	if corners & CUT_TOP_LEFT:
		points.append(Vector2(left, top + size))
	return points


## The cut a rect can actually afford, which is not always the one asked for.
static func fit_cut(rect: Rect2, cut: float) -> float:
	return minf(cut, minf(rect.size.x, rect.size.y) * CUT_LIMIT)


## Add a closed run of points to a canvas item as a single stroke.
static func stroke(item: RID, points: PackedVector2Array, colour: Color, width: float) -> void:
	if points.size() < 2 or colour.a <= 0.0:
		return
	var colours := PackedColorArray()
	colours.resize(points.size())
	colours.fill(colour)
	RenderingServer.canvas_item_add_polyline(item, points, colours, width, true)


## The same run, drawn as a bright core over two fainter, wider passes.
##
## The order matters: widest and faintest first, so the core lands on top of its
## own halo rather than being washed out by it.
static func glow_stroke(
	item: RID, points: PackedVector2Array, colour: Color, width: float, strength := 1.0
) -> void:
	if strength > 0.0:
		stroke(item, points, Color(colour, colour.a * 0.10 * strength), width + 5.0)
		stroke(item, points, Color(colour, colour.a * 0.18 * strength), width + 2.0)
	stroke(item, points, colour, width)


## Close a run of points so a stroke over it comes back to where it started.
static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop := points.duplicate()
	if loop.size() > 1:
		loop.append(loop[0])
	return loop


## A diamond: the console's punctuation mark, used wherever a run of geometry
## needs a node on the end of it.
static func diamond(centre: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array(
		[
			centre + Vector2(0, -radius),
			centre + Vector2(radius, 0),
			centre + Vector2(0, radius),
			centre + Vector2(-radius, 0),
		]
	)


## A flat-topped hexagon, for the marks that want more than four sides.
static func hexagon(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 6:
		var angle := PI / 3.0 * float(step)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func fill(item: RID, points: PackedVector2Array, colour: Color) -> void:
	if points.size() < 3 or colour.a <= 0.0:
		return
	var colours := PackedColorArray()
	colours.resize(points.size())
	colours.fill(colour)
	RenderingServer.canvas_item_add_polygon(item, points, colours)


## Diagonal hatching inside a rect, at 45 degrees, right to left.
##
## Used at very low alpha as the texture of a panel, so a large empty frame has
## something in it other than its own background colour.
static func weave(item: RID, rect: Rect2, colour: Color, step: float) -> void:
	if colour.a <= 0.0 or step <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var extent := rect.size.x + rect.size.y
	var offset := 0.0
	while offset < extent:
		var from := rect.position + Vector2(offset, 0)
		var to := rect.position + Vector2(offset - rect.size.y, rect.size.y)
		# The pass above walks the diagonal off the right-hand edge before it is
		# done; the segments that land entirely outside are simply skipped.
		if from.x - rect.size.y < rect.position.x + rect.size.x:
			stroke(item, PackedVector2Array([from, to]), colour, 1.0)
		offset += step


## A frame with cut corners, a lit outline and optional corner brackets.
##
## Written as a StyleBox rather than a decorating node so it can be dropped into
## any control that already takes one — every panel, button and tab in the app —
## without changing a single node tree.
class ChamferBox:
	extends StyleBox

	var bg := Color.TRANSPARENT
	## When set, the fill runs from this colour at the top edge to [member bg]
	## at the bottom, so a panel has a direction to it.
	var bg_top := Color.TRANSPARENT
	var border := Color.TRANSPARENT
	var border_width := 1.0
	## The halo under the outline. Fainter and wider than the outline itself.
	var glow := Color.TRANSPARENT
	var glow_strength := 0.0
	var cut := 10.0
	var corners := Chrome.CUT_DIAGONAL
	## L-shaped marks on the corners the cut left square.
	var bracket := Color.TRANSPARENT
	var bracket_length := 14.0
	var bracket_width := 2.0
	## A short bright bar riding the top edge, next to the top-left cut.
	var edge := Color.TRANSPARENT
	var edge_length := 0.0
	## The same along the bottom edge, which is how an active tab is marked.
	var foot := Color.TRANSPARENT
	var foot_width := 2.0
	## Faint diagonal texture across the middle of the fill.
	var weave := Color.TRANSPARENT
	var weave_step := 9.0

	## Keep content off the frame line, the way a bordered StyleBoxFlat does.
	##
	## Without this a panel with no content margin of its own would let a label
	## sit on top of its own border, which is a one-pixel bug that reads as a
	## typo across a whole screen.
	func _get_style_margin(_side: Side) -> float:
		return border_width

	func _draw(item: RID, rect: Rect2) -> void:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		var shape := Chrome.outline(rect, cut, corners)
		if bg.a > 0.0:
			RenderingServer.canvas_item_add_polygon(item, shape, _fill_colours(shape, rect))
		if weave.a > 0.0:
			var inner := rect.grow(-Chrome.fit_cut(rect, cut) - 1.0)
			if inner.size.x > 0.0 and inner.size.y > 0.0:
				Chrome.weave(item, inner, weave, weave_step)
		if border.a > 0.0 and border_width > 0.0:
			var loop := Chrome.closed(shape)
			Chrome.glow_stroke(item, loop, border, border_width, _halo_strength())
			if glow.a > 0.0 and glow_strength > 0.0:
				Chrome.stroke(item, loop, Color(glow, glow.a * 0.22 * glow_strength), 3.0)
		_draw_edge(item, rect)
		_draw_foot(item, rect)
		_draw_brackets(item, rect)

	## The halo is the border's own colour unless a brighter one was named.
	func _halo_strength() -> float:
		return glow_strength if glow.a > 0.0 else 0.0

	func _fill_colours(shape: PackedVector2Array, rect: Rect2) -> PackedColorArray:
		var colours := PackedColorArray()
		colours.resize(shape.size())
		if bg_top.a <= 0.0 or rect.size.y <= 0.0:
			colours.fill(bg)
			return colours
		for index in shape.size():
			var ratio := clampf((shape[index].y - rect.position.y) / rect.size.y, 0.0, 1.0)
			colours[index] = bg_top.lerp(bg, ratio)
		return colours

	func _draw_edge(item: RID, rect: Rect2) -> void:
		if edge.a <= 0.0 or edge_length <= 0.0:
			return
		var size := Chrome.fit_cut(rect, cut)
		var start := rect.position + Vector2(size + 2.0, border_width * 0.5)
		var span := minf(edge_length, maxf(rect.size.x - size - 6.0, 0.0))
		if span <= 1.0:
			return
		Chrome.glow_stroke(
			item,
			PackedVector2Array([start, start + Vector2(span, 0)]),
			edge,
			maxf(border_width, 1.5),
			1.0
		)

	## The bottom edge, lit end to end between the corner cuts.
	func _draw_foot(item: RID, rect: Rect2) -> void:
		if foot.a <= 0.0 or foot_width <= 0.0:
			return
		var size := Chrome.fit_cut(rect, cut)
		var y := rect.position.y + rect.size.y - foot_width * 0.5
		var from := Vector2(
			rect.position.x + (size if corners & Chrome.CUT_BOTTOM_LEFT else 0.0), y
		)
		var span := (
			rect.size.x
			- (size if corners & Chrome.CUT_BOTTOM_RIGHT else 0.0)
			- (from.x - rect.position.x)
		)
		if span <= 1.0:
			return
		Chrome.glow_stroke(
			item, PackedVector2Array([from, from + Vector2(span, 0)]), foot, foot_width
		)

	## Brackets go on the corners the chamfer did not take, so every frame reads
	## as two cut corners and two clasped ones rather than four of anything.
	func _draw_brackets(item: RID, rect: Rect2) -> void:
		if bracket.a <= 0.0 or bracket_length <= 0.0:
			return
		# A bracket has to read as a corner mark, not as a border: on a small
		# tile it shrinks with the tile, and below a certain size it is left off
		# entirely rather than closing up into a box.
		var shortest := minf(rect.size.x, rect.size.y)
		if shortest < 22.0:
			return
		var arm := minf(bracket_length, shortest * 0.3)
		if arm <= 3.0:
			return
		var inset := border_width * 0.5 + 1.0
		var left := rect.position.x + inset
		var top := rect.position.y + inset
		var right := rect.position.x + rect.size.x - inset
		var bottom := rect.position.y + rect.size.y - inset
		if not (corners & Chrome.CUT_TOP_LEFT):
			_arm(item, Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top))
		if not (corners & Chrome.CUT_TOP_RIGHT):
			_arm(item, Vector2(right - arm, top), Vector2(right, top), Vector2(right, top + arm))
		if not (corners & Chrome.CUT_BOTTOM_RIGHT):
			_arm(
				item,
				Vector2(right, bottom - arm),
				Vector2(right, bottom),
				Vector2(right - arm, bottom)
			)
		if not (corners & Chrome.CUT_BOTTOM_LEFT):
			_arm(
				item,
				Vector2(left + arm, bottom),
				Vector2(left, bottom),
				Vector2(left, bottom - arm)
			)

	func _arm(item: RID, from: Vector2, corner: Vector2, to: Vector2) -> void:
		Chrome.glow_stroke(
			item, PackedVector2Array([from, corner, to]), bracket, bracket_width, 0.7
		)


## A horizontal rule that is lit at one end and fades out along its length.
##
## The app has seventy-odd of these separating one block of a panel from the
## next. As flat hairlines they were the most repeated rectangle in the console;
## lit from the left with a diamond on the end, they are the thing that makes a
## dense panel look like an instrument.
class GlowRule:
	extends Control

	var core := Color("8fd0ff")
	var tail := Color("243044")
	var node := Color("ffd166")
	## How much of the width the lit part covers, and the length it stops at.
	##
	## The cap is what keeps the rule consistent: a separator in a 200px rail
	## and one across a 900px sheet get the same length of filament rather than
	## the wide one turning into a bar.
	var lit := 0.34
	var lit_cap := 58.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 3)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := 1.5
		var span := maxf(size.x, 0.0)
		if span <= 2.0:
			return
		var break_x := minf(span * clampf(lit, 0.0, 1.0), lit_cap)
		var item := get_canvas_item()
		Chrome.stroke(item, PackedVector2Array([Vector2(0, y), Vector2(span, y)]), tail, 1.0)
		Chrome.glow_stroke(
			item, PackedVector2Array([Vector2(0, y), Vector2(break_x, y)]), core, 1.0
		)
		# The tail does not simply stop: it steps down to the dim rule through a
		# short diagonal, which is what keeps the line from reading as a bar.
		Chrome.stroke(
			item,
			PackedVector2Array(
				[Vector2(break_x, y), Vector2(break_x + 5.0, y + 1.5), Vector2(span, y + 1.5)]
			),
			Color(tail, tail.a * 0.85),
			1.0
		)
		Chrome.fill(item, Chrome.diamond(Vector2(1.5, y), 2.5), node)


## A run of angled marks, drawn at the size a label is.
##
## Three shapes, one class: which one it draws is the [member kind] it was made
## with. They exist to break up rows of text — a heading with a diamond on it
## reads as a heading without needing another rectangle behind it.
class Mark:
	extends Control

	enum Kind { DIAMOND, HEXAGON, CHEVRON, STACK }

	var kind := Kind.DIAMOND
	var colour := Color("8fd0ff")
	var glow_strength := 1.0
	var filled := true

	func _init(mark_kind := Kind.DIAMOND, mark_colour := Color("8fd0ff"), extent := 10.0) -> void:
		kind = mark_kind
		colour = mark_colour
		custom_minimum_size = Vector2(extent, extent)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var item := get_canvas_item()
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		if radius <= 0.5:
			return
		match kind:
			Kind.DIAMOND:
				_shape(item, Chrome.diamond(centre, radius))
			Kind.HEXAGON:
				_shape(item, Chrome.hexagon(centre, radius))
			Kind.CHEVRON:
				(
					Chrome
					. glow_stroke(
						item,
						PackedVector2Array(
							[
								centre + Vector2(-radius * 0.6, -radius),
								centre + Vector2(radius * 0.6, 0),
								centre + Vector2(-radius * 0.6, radius),
							]
						),
						colour,
						1.5,
						glow_strength
					)
				)
			Kind.STACK:
				# Three shortening bars, the shape a signal meter makes.
				for step in 3:
					var y := centre.y - radius + float(step) * radius
					var width := radius * (2.0 - float(step) * 0.6)
					Chrome.stroke(
						item,
						PackedVector2Array(
							[Vector2(centre.x - radius, y), Vector2(centre.x - radius + width, y)]
						),
						Color(colour, colour.a * (1.0 - float(step) * 0.28)),
						1.5
					)

	func _shape(item: RID, points: PackedVector2Array) -> void:
		if filled:
			Chrome.fill(item, points, colour)
		Chrome.glow_stroke(item, Chrome.closed(points), colour, 1.0, glow_strength)


## The app's ground: a surveyor's grid with a few lit traces run across it.
##
## The console used to sit on one flat colour, so every gap between panels was
## dead space. This gives the gaps a structure to show through them, and the
## two large empty screens — an unopened campaign, a run not yet started —
## something to be empty against.
class Backdrop:
	extends Control

	var base := Color("0e1318")
	var grid := Color("8fd0ff")
	var trace := Color("8fd0ff")
	var spark := Color("ffd166")
	## Distance between the fine grid lines. Every fourth one is drawn brighter.
	var step := 56.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var item := get_canvas_item()
		draw_rect(Rect2(Vector2.ZERO, size), base)
		_draw_grid(item)
		_draw_corners(item)
		_draw_traces(item)

	func _draw_grid(item: RID) -> void:
		var faint := Color(grid, 0.035)
		var strong := Color(grid, 0.075)
		var column := 0
		var x := 0.0
		while x < size.x:
			var colour := strong if column % 4 == 0 else faint
			Chrome.stroke(
				item, PackedVector2Array([Vector2(x, 0), Vector2(x, size.y)]), colour, 1.0
			)
			x += step
			column += 1
		var row := 0
		var y := 0.0
		while y < size.y:
			var colour := strong if row % 4 == 0 else faint
			Chrome.stroke(
				item, PackedVector2Array([Vector2(0, y), Vector2(size.x, y)]), colour, 1.0
			)
			y += step
			row += 1

	## Diagonal fans in the two corners the panels leave most room at.
	func _draw_corners(item: RID) -> void:
		for index in 7:
			var reach := 150.0 - float(index) * 12.0
			var offset := float(index) * 16.0
			Chrome.stroke(
				item,
				PackedVector2Array([Vector2(0, offset), Vector2(reach, offset + reach)]),
				Color(grid, 0.05),
				1.0
			)
			Chrome.stroke(
				item,
				PackedVector2Array(
					[
						Vector2(size.x, size.y - offset),
						Vector2(size.x - reach, size.y - offset - reach)
					]
				),
				Color(spark, 0.045),
				1.0
			)

	## Lit traces with square elbows, the way a circuit board runs a track.
	func _draw_traces(item: RID) -> void:
		var lanes := [
			{"y": size.y * 0.22, "at": 0.18, "drop": 90.0, "colour": trace},
			{"y": size.y * 0.62, "at": 0.55, "drop": -120.0, "colour": spark},
			{"y": size.y * 0.86, "at": 0.31, "drop": 70.0, "colour": trace},
		]
		for entry in lanes:
			var lane: Dictionary = entry
			var y := float(lane["y"])
			var elbow := size.x * float(lane["at"])
			var drop := float(lane["drop"])
			var colour := Color(lane["colour"], 0.16)
			var path := PackedVector2Array(
				[
					Vector2(0, y),
					Vector2(elbow, y),
					Vector2(elbow + absf(drop) * 0.5, y + drop * 0.5),
					Vector2(size.x, y + drop * 0.5),
				]
			)
			Chrome.glow_stroke(item, path, colour, 1.0, 0.8)
			Chrome.fill(item, Chrome.diamond(path[1], 3.0), Color(lane["colour"], 0.34))
			Chrome.fill(item, Chrome.diamond(path[2], 2.0), Color(lane["colour"], 0.22))


## A segmented meter: ten notches, filled from the left, lit at the head.
##
## The old bar was two nested rectangles and read as a progress bar. Notches
## make it a gauge, and a gauge is what a GM is actually reading — nobody needs
## a character's hit points to the pixel, they need to see at a glance which
## quarter of the track the party is in.
class Meter:
	extends Control

	var ratio := 1.0
	var colour := Color("8fd0ff")
	var track := Color("243044")
	## Notches to divide the track into, or 0 to pick a count from the width.
	##
	## Auto is the useful setting: the same meter is 180px wide in an initiative
	## row and 950px wide across a netrun floor, and a fixed ten notches makes
	## the wide one a row of slabs.
	var segments := 0

	func _init(fill_ratio := 1.0, fill_colour := Color("8fd0ff")) -> void:
		ratio = clampf(fill_ratio, 0.0, 1.0)
		colour = fill_colour
		custom_minimum_size = Vector2(0, 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var item := get_canvas_item()
		if size.x <= 4.0:
			return
		var count := segments
		if count <= 0:
			count = clampi(int(size.x / 17.0), 5, 48)
		var gap := 2.0
		var width := (size.x - gap * float(count - 1)) / float(count)
		if width <= 0.5:
			# Too narrow to notch; a plain lit bar says the same thing.
			Chrome.glow_stroke(
				item, PackedVector2Array([Vector2(0, 2), Vector2(size.x * ratio, 2)]), colour, 2.0
			)
			return
		var lit := ratio * float(count)
		for index in count:
			var x := float(index) * (width + gap)
			# Each notch is a parallelogram: the meter leans, so a row of them
			# never reads as a row of little rectangles.
			var slant := minf(width * 0.45, 3.0)
			var cell := PackedVector2Array(
				[
					Vector2(x + slant, 0),
					Vector2(x + width, 0),
					Vector2(x + width - slant, size.y),
					Vector2(x, size.y),
				]
			)
			var filled := float(index) + 1.0 <= lit
			var partial := not filled and float(index) < lit
			if filled or partial:
				var tint := colour if filled else Color(colour, colour.a * 0.45)
				Chrome.fill(item, cell, tint)
				if float(index) + 1.0 > lit - 1.0:
					Chrome.glow_stroke(item, Chrome.closed(cell), Color(colour, 0.6), 1.0)
			else:
				Chrome.fill(item, cell, Color(track, track.a * 0.7))


## The frame drawn over the board: corner brackets and edge ticks.
##
## The board is a 3D render, so nothing in it can be chamfered or lit the way
## the panels around it are — it would arrive as a rectangle of pixels in the
## middle of a console made of angles. This is drawn on top of it instead, and
## does for the viewport what a bracket does for a panel: says where its edges
## are without putting a border round them.
class Reticle:
	extends Control

	var frame := Color("8fd0ff")
	var tick := Color("ffd166")
	var arm := 30.0
	var inset := 6.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		if size.x < arm * 3.0 or size.y < arm * 3.0:
			return
		var item := get_canvas_item()
		var left := inset
		var top := inset
		var right := size.x - inset
		var bottom := size.y - inset
		var corners := [
			[Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top)],
			[Vector2(right - arm, top), Vector2(right, top), Vector2(right, top + arm)],
			[Vector2(right, bottom - arm), Vector2(right, bottom), Vector2(right - arm, bottom)],
			[Vector2(left + arm, bottom), Vector2(left, bottom), Vector2(left, bottom - arm)],
		]
		for corner in corners:
			Chrome.glow_stroke(item, PackedVector2Array(corner), Color(frame, 0.55), 1.5, 1.0)
		# Amber ticks at the middle of each edge: the four points a GM measures
		# a distance from when they are eyeballing the board.
		var mid_x := (left + right) * 0.5
		var mid_y := (top + bottom) * 0.5
		var ticks := [
			[Vector2(mid_x, top), Vector2(mid_x, top + 9.0)],
			[Vector2(mid_x, bottom), Vector2(mid_x, bottom - 9.0)],
			[Vector2(left, mid_y), Vector2(left + 9.0, mid_y)],
			[Vector2(right, mid_y), Vector2(right - 9.0, mid_y)],
		]
		for line in ticks:
			Chrome.glow_stroke(item, PackedVector2Array(line), Color(tick, 0.6), 1.5, 1.0)
		Chrome.fill(item, Chrome.diamond(Vector2(mid_x, top + 13.0), 2.5), Color(tick, 0.75))
		# A short ladder of diagonals in the top-left, the way a scale bar sits
		# on a plan drawing.
		for index in 4:
			var offset := float(index) * 7.0
			(
				Chrome
				. stroke(
					item,
					PackedVector2Array(
						[
							Vector2(left + arm + 8.0 + offset, top),
							Vector2(left + arm + offset, top + 8.0),
						]
					),
					Color(frame, 0.3),
					1.0
				)
			)
