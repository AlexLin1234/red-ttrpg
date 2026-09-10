class_name CityMapView
extends Control

## The Night City map: zone plates, pins, drawing and reshaping.
##
## Lifted out of city.gd, which was the largest file in the project by a wide
## margin and is a screen rather than a renderer. This half knows about polygons
## and the pointer; the screen half knows about the campaign. They meet at the
## signals below, which is the seam that was already there — it was simply
## inside one file.

signal hovered(area_id: String)
signal picked(area_id: String)
signal zone_drawn(points: PackedVector2Array)
signal draft_changed
signal poi_hovered(poi_id: String)
signal poi_picked(poi_id: String)
signal poi_placed(point: Vector2)
signal poi_moved(poi_id: String, point: Vector2, finished: bool)
## delta is the movement when the whole zone was dragged, zero otherwise.
signal reshape_changed(area_id: String, points: PackedVector2Array, delta: Vector2)

## How close, in map units, the pointer has to be to hit a pin.
const PIN_RADIUS := 14.0
## Pointer travel required before a press becomes a relocation rather than a click.
const PIN_DRAG_THRESHOLD := 4.0
## Grab radius for a corner handle while reshaping.
const HANDLE_RADIUS := 13.0
## Clicking within this many map units of the first vertex closes the polygon.
##
## It lives here rather than on the screen because it is a fact about the
## pointer, and this is the half that owns the pointer.
const CLOSE_RADIUS := 18.0

var _areas: Array = []
var _pois: Array = []
var _focus := ""
var _focus_poi := ""
var _hooked: PackedStringArray = []
var _drawing := false
var _pinning := false
var _reshape_id := ""
var _pressed_poi := ""
var _poi_dragged := false
var _poi_press_screen := Vector2.ZERO
var _drag_corner := -1
var _dragging_body := false
var _drag_last := Vector2.ZERO
var _draft := PackedVector2Array()
var _cursor := Vector2.ZERO
var _scale := 1.0
var _origin := Vector2.ZERO
var _backdrop: ImageTexture
var _backdrop_signature := 0
var _backdrop_opacity := 0.72
var _backdrop_visible := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

## The GM's own map, drawn behind the zone plates. An empty dictionary falls
## back to the optional map installed under data/maps, and failing that to the
## bare grid.
func set_custom_map(data: Dictionary) -> void:
	_backdrop_opacity = clampf(float(data.get("opacity", 0.72)), 0.2, 1.0)
	var encoded := String(data.get("png_base64", ""))
	if encoded == "":
		if _backdrop_signature != 0 or _backdrop == null:
			var external := MapAsset.load_external()
			if bool(external.get("ok", false)):
				_adopt(external["image"])
			else:
				_backdrop = null
			_backdrop_signature = 0
		queue_redraw()
		return
	var signature := encoded.hash()
	if signature != _backdrop_signature or _backdrop == null:
		var image := MapAsset.decode(data)
		if image == null:
			_backdrop = null
		else:
			_adopt(image)
		_backdrop_signature = signature
	queue_redraw()

func _adopt(image: Image) -> void:
	_backdrop = ImageTexture.create_from_image(image)

func toggle_map() -> void:
	_backdrop_visible = not _backdrop_visible
	queue_redraw()

func set_areas(areas: Array, hooked: PackedStringArray) -> void:
	_areas = areas
	_hooked = hooked
	queue_redraw()

func set_pois(pois: Array) -> void:
	_pois = pois
	queue_redraw()

func set_focus(area_id: String) -> void:
	if _focus == area_id:
		return
	_focus = area_id
	queue_redraw()

func set_focus_poi(poi_id: String) -> void:
	if _focus_poi == poi_id:
		return
	_focus_poi = poi_id
	queue_redraw()

func set_pin_mode(on: bool) -> void:
	_pinning = on
	queue_redraw()

func set_reshape_target(area_id: String) -> void:
	_reshape_id = area_id
	_drag_corner = -1
	_dragging_body = false
	queue_redraw()

func _reshape_area() -> Dictionary:
	for area in _areas:
		if String((area as Dictionary)["id"]) == _reshape_id:
			return area
	return {}

func set_draw_mode(on: bool) -> void:
	_drawing = on
	if not on:
		_draft.clear()
	queue_redraw()

func draft_size() -> int:
	return _draft.size()

## Same effect as clicking the map at this point, in map coordinates.
func add_draft_corner(point: Vector2) -> void:
	if not _drawing:
		return
	_draft.append(point.snapped(Vector2(10, 10)))
	_cursor = point
	queue_redraw()
	draft_changed.emit()

func close_draft() -> void:
	if _draft.size() < 3:
		return
	var points := _draft.duplicate()
	_draft.clear()
	_drawing = false
	queue_redraw()
	zone_drawn.emit(points)

func _recompute_transform() -> void:
	# Letterbox the 1000 × 700 diagram into whatever space the panel gives us.
	_scale = minf(size.x / NightCity.MAP_SIZE.x, size.y / NightCity.MAP_SIZE.y)
	_origin = (size - NightCity.MAP_SIZE * _scale) * 0.5

func _to_screen(point: Vector2) -> Vector2:
	return _origin + point * _scale

func _to_map(point: Vector2) -> Vector2:
	return (point - _origin) / maxf(_scale, 0.0001)

## Dragging corners, inserting them on an edge, and sliding the whole plate.
func _reshape_input(event: InputEvent) -> void:
	var area := _reshape_area()
	if area.is_empty():
		return
	var points := NightCity.points_of(area)

	if event is InputEventMouseMotion:
		var at := _to_map((event as InputEventMouseMotion).position)
		_cursor = at
		if _drag_corner >= 0 and _drag_corner < points.size():
			points[_drag_corner] = at.snapped(Vector2(5, 5))
			reshape_changed.emit(_reshape_id, points, Vector2.ZERO)
		elif _dragging_body:
			var delta := (at - _drag_last).snapped(Vector2(5, 5))
			if delta != Vector2.ZERO:
				_drag_last += delta
				reshape_changed.emit(_reshape_id, points, delta)
		queue_redraw()
		return

	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	var at := _to_map(button.position)

	if not button.pressed:
		_drag_corner = -1
		_dragging_body = false
		return

	if button.button_index == MOUSE_BUTTON_RIGHT:
		var doomed := _corner_at(points, at)
		if doomed >= 0:
			reshape_changed.emit(_reshape_id, NightCity.remove_corner(points, doomed), Vector2.ZERO)
			queue_redraw()
		return

	if button.button_index != MOUSE_BUTTON_LEFT:
		return

	var corner := _corner_at(points, at)
	if corner >= 0:
		_drag_corner = corner
		return

	var edge := _edge_at(points, at)
	if edge >= 0:
		var grown := NightCity.insert_corner(points, edge, at.snapped(Vector2(5, 5)))
		_drag_corner = edge + 1
		reshape_changed.emit(_reshape_id, grown, Vector2.ZERO)
		queue_redraw()
		return

	if Geometry2D.is_point_in_polygon(at, points):
		_dragging_body = true
		_drag_last = at

func _corner_at(points: PackedVector2Array, at: Vector2) -> int:
	var radius := HANDLE_RADIUS / maxf(_scale, 0.0001)
	for index in points.size():
		if at.distance_to(points[index]) <= radius:
			return index
	return -1

func _edge_at(points: PackedVector2Array, at: Vector2) -> int:
	var radius := HANDLE_RADIUS / maxf(_scale, 0.0001)
	var mids := NightCity.edge_midpoints(points)
	for index in mids.size():
		if at.distance_to(mids[index]) <= radius:
			return index
	return -1

## Pins sit on top of zones, so they are hit-tested first.
func _poi_at(at: Vector2) -> String:
	var best := ""
	var best_distance := PIN_RADIUS
	for poi in _pois:
		var entry: Dictionary = poi
		var distance := at.distance_to(NightCity.poi_position(entry))
		if distance <= best_distance:
			best_distance = distance
			best = String(entry["id"])
	return best

func _area_at(at: Vector2) -> String:
	for area in _areas:
		var entry: Dictionary = area
		if Geometry2D.is_point_in_polygon(at, NightCity.points_of(entry)):
			return String(entry["id"])
	return ""

func _gui_input(event: InputEvent) -> void:
	if _reshape_id != "":
		_reshape_input(event)
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var at := _to_map(motion.position)
		if _pressed_poi != "":
			if motion.position.distance_to(_poi_press_screen) >= PIN_DRAG_THRESHOLD:
				_poi_dragged = true
			if _poi_dragged:
				mouse_default_cursor_shape = Control.CURSOR_MOVE
				poi_moved.emit(_pressed_poi, at.snapped(Vector2(5, 5)), false)
				queue_redraw()
			return
		if _drawing or _pinning:
			_cursor = at
			queue_redraw()
			return
		var pin := _poi_at(at)
		mouse_default_cursor_shape = (
			Control.CURSOR_DRAG if pin != "" else Control.CURSOR_ARROW
		)
		poi_hovered.emit(pin)
		if pin == "":
			hovered.emit(_area_at(at))
		return

	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	var at := _to_map(button.position)

	if not button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT and _pressed_poi != "":
			var released_poi := _pressed_poi
			var was_dragged := _poi_dragged
			_pressed_poi = ""
			_poi_dragged = false
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			if was_dragged:
				poi_moved.emit(released_poi, at.snapped(Vector2(5, 5)), true)
			else:
				poi_picked.emit(released_poi)
			queue_redraw()
		return

	if _pinning:
		if button.button_index == MOUSE_BUTTON_LEFT:
			poi_placed.emit(at)
		return

	if not _drawing:
		if button.button_index == MOUSE_BUTTON_LEFT:
			var pin := _poi_at(at)
			if pin != "":
				_pressed_poi = pin
				_poi_dragged = false
				_poi_press_screen = button.position
				_focus_poi = pin
				mouse_default_cursor_shape = Control.CURSOR_DRAG
				queue_redraw()
				return
			var id := _area_at(at)
			if id != "":
				picked.emit(id)
		return

	if button.button_index == MOUSE_BUTTON_RIGHT:
		if not _draft.is_empty():
			_draft.remove_at(_draft.size() - 1)
			queue_redraw()
			draft_changed.emit()
		return

	if button.button_index != MOUSE_BUTTON_LEFT:
		return

	# Clicking the first corner again closes the shape.
	if _draft.size() >= 3 and at.distance_to(_draft[0]) <= CLOSE_RADIUS:
		close_draft()
		return
	_draft.append(at.snapped(Vector2(10, 10)))
	queue_redraw()
	draft_changed.emit()

func _draw() -> void:
	_recompute_transform()

	_draw_grid()

	if _backdrop != null and _backdrop_visible:
		# The backdrop fills exactly the letterboxed rect the zones map into,
		# so a zone drawn over a landmark stays on that landmark. An upload
		# that is not 1000 × 700 is stretched to it rather than fitted by its
		# own aspect: fitting would slide the picture out from under every
		# zone and every click.
		draw_texture_rect(
			_backdrop,
			Rect2(_origin, NightCity.MAP_SIZE * _scale),
			false,
			Color(1, 1, 1, _backdrop_opacity),
		)

	for area in _areas:
		var entry: Dictionary = area
		var id := String(entry["id"])
		var focused := id == _focus and not _drawing
		var colors := NightCity.zone_colors(String(entry.get("zone_type", "")), focused)

		var points := PackedVector2Array()
		for point in NightCity.points_of(entry):
			points.append(_to_screen(point))
		if points.size() < 3:
			continue

		var fill: Color = colors["fill"]
		fill.a *= NightCity.zone_opacity(entry)
		draw_colored_polygon(points, fill)
		# A zone's border is a lit edge rather than a drawn one: the halo under
		# it is what separates two neighbouring districts of nearly the same
		# dark colour without needing a brighter line between them.
		var outline := Chrome.closed(points)
		var stroke: Color = colors["stroke"]
		Chrome.glow_stroke(
			get_canvas_item(),
			outline,
			stroke,
			2.0 if focused else 1.5,
			1.4 if focused else 0.6,
		)
		_draw_zone_corners(points, stroke, focused)

		var label_at := _to_screen(NightCity.label_of(entry))
		draw_string(
			UI.DISPLAY_FONT,
			label_at,
			String(entry["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			int(maxf(13.0, 19.0 * _scale)),
			UI.TEXT_DISPLAY,
		)
		draw_string(
			UI.BODY_BOLD_FONT,
			label_at + Vector2(0, 14),
			UI._letterspace(String(entry.get("subtitle", "")).to_upper()),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			9,
			UI.MUTED,
		)

		if _hooked.has(id):
			# A zone with work waiting in it is marked in amber, not blue: it is
			# the one thing on the map the table put there.
			var marker := _to_screen(NightCity.centroid_of(NightCity.points_of(entry)))
			var item := get_canvas_item()
			Chrome.glow_stroke(
				item, Chrome.closed(Chrome.diamond(marker, 9.0)), UI.AMBER, 1.5, 1.2
			)
			Chrome.fill(item, Chrome.diamond(marker, 3.0), UI.AMBER)

	_draw_pins()

	if _reshape_id != "":
		_draw_handles()
	elif _drawing:
		_draw_draft()
	elif _pinning:
		_draw_pin_cursor()

## The ground the districts sit on: a fine survey grid with every fifth line
## brought up, so the map has a sense of scale even where no zone is drawn.
##
## The bright lines are what a distance is counted in — twenty metres a square,
## a hundred to a heavy one — and the diagonal in the corner is there to keep
## an empty quadrant from reading as a hole in the screen.
func _draw_grid() -> void:
	var step := 20.0 * _scale
	if step <= 1.0:
		return
	var item := get_canvas_item()
	var fine := Color(UI.ACCENT, 0.045)
	var heavy := Color(UI.ACCENT, 0.10)
	var column := 0
	var x := fposmod(_origin.x, step * 5.0) - step * 5.0
	while x < size.x:
		if x >= 0.0:
			var colour := heavy if column % 5 == 0 else fine
			Chrome.stroke(item, PackedVector2Array([Vector2(x, 0), Vector2(x, size.y)]), colour, 1.0)
		x += step
		column += 1
	var row := 0
	var y := fposmod(_origin.y, step * 5.0) - step * 5.0
	while y < size.y:
		if y >= 0.0:
			var colour := heavy if row % 5 == 0 else fine
			Chrome.stroke(item, PackedVector2Array([Vector2(0, y), Vector2(size.x, y)]), colour, 1.0)
		y += step
		row += 1
	for index in 6:
		var reach := 120.0 - float(index) * 10.0
		var offset := float(index) * 18.0
		Chrome.stroke(
			item,
			PackedVector2Array([Vector2(offset, size.y), Vector2(offset + reach, size.y - reach)]),
			Color(UI.AMBER, 0.035),
			1.0,
		)


## Brackets clasping the extremes of a zone's outline.
##
## The polygons are irregular, so a corner mark cannot be put on a corner the
## way a panel's is. These go on the bounding box instead, which is close enough
## to read as "this district is the one selected" without redrawing its shape.
func _draw_zone_corners(points: PackedVector2Array, stroke: Color, focused: bool) -> void:
	if not focused:
		return
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	# Held off the shape by a few pixels. A zone that happens to be rectangular
	# would otherwise have its brackets land exactly on its own outline, which
	# marks nothing.
	bounds = bounds.grow(7.0)
	var arm := minf(26.0, minf(bounds.size.x, bounds.size.y) * 0.3)
	if arm <= 4.0:
		return
	var item := get_canvas_item()
	var left := bounds.position.x
	var top := bounds.position.y
	var right := bounds.position.x + bounds.size.x
	var bottom := bounds.position.y + bounds.size.y
	var corners := [
		[Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top)],
		[Vector2(right - arm, top), Vector2(right, top), Vector2(right, top + arm)],
		[Vector2(right, bottom - arm), Vector2(right, bottom), Vector2(right - arm, bottom)],
		[Vector2(left + arm, bottom), Vector2(left, bottom), Vector2(left, bottom - arm)],
	]
	for corner in corners:
		Chrome.glow_stroke(item, PackedVector2Array(corner), Color(stroke, 0.75), 1.5, 1.0)


## A pin: a filled head on a short stem, with its name beside it. Drawn after
## the plates so it always reads on top of them.
func _draw_pins() -> void:
	for poi in _pois:
		var entry: Dictionary = poi
		var at := _to_screen(NightCity.poi_position(entry))
		var colour: Color = NightCity.poi_color(String(entry.get("kind", "")))
		var focused := String(entry["id"]) == _focus_poi
		var linked := String(entry.get("location_id", "")) != ""

		var item := get_canvas_item()
		Chrome.glow_stroke(
			item, PackedVector2Array([at, at + Vector2(0, 10)]), colour, 1.5, 0.8
		)
		# The head is a hexagon rather than a circle: on a map of straight-edged
		# districts a round pin is the only curve on the screen.
		var head := Chrome.hexagon(at, 7.0 if focused else 6.0)
		Chrome.fill(item, head, colour)
		Chrome.glow_stroke(item, Chrome.closed(head), colour, 1.0, 1.2)
		# A hollow head means the pin is a note; a filled one has a board
		# behind it that the party can walk into.
		if not linked:
			Chrome.fill(item, Chrome.hexagon(at, 3.2), UI.PANEL_INSET)
		if focused:
			Chrome.glow_stroke(
				item, Chrome.closed(Chrome.diamond(at, 13.0)), colour, 1.5, 1.4
			)

		draw_string(
			UI.BODY_BOLD_FONT,
			at + Vector2(10, 4),
			String(entry.get("name", "")).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			9,
			colour if focused else UI.TEXT,
		)

## Square handles on the corners, small crosses on the edge midpoints where a
## new corner would go.
func _draw_handles() -> void:
	var area := _reshape_area()
	if area.is_empty():
		return
	var points := NightCity.points_of(area)

	for mid in NightCity.edge_midpoints(points):
		var at := _to_screen(mid)
		draw_line(at - Vector2(4, 0), at + Vector2(4, 0), UI.ACCENT_FILL, 1.0)
		draw_line(at - Vector2(0, 4), at + Vector2(0, 4), UI.ACCENT_FILL, 1.0)

	for index in points.size():
		var at := _to_screen(points[index])
		var held := index == _drag_corner
		var box := Rect2(at - Vector2(5, 5), Vector2(10, 10))
		draw_rect(box, UI.ACCENT if held else UI.PANEL_INSET, true)
		draw_rect(box, UI.ACCENT, false, 1.5)

func _draw_pin_cursor() -> void:
	var at := _to_screen(_cursor)
	draw_arc(at, 10.0, 0, TAU, 24, UI.ACCENT, 1.5)
	draw_line(at - Vector2(14, 0), at + Vector2(14, 0), UI.ACCENT, 1.0)
	draw_line(at - Vector2(0, 14), at + Vector2(0, 14), UI.ACCENT, 1.0)

func _draw_draft() -> void:
	var screen_points := PackedVector2Array()
	for point in _draft:
		screen_points.append(_to_screen(point))

	if screen_points.size() >= 3:
		var closed := screen_points.duplicate()
		closed.append(screen_points[0])
		draw_colored_polygon(screen_points, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.12))
		draw_polyline(closed, UI.ACCENT, 2.0)
	elif screen_points.size() == 2:
		draw_line(screen_points[0], screen_points[1], UI.ACCENT, 2.0)

	# A rubber band from the last corner to the pointer.
	if not screen_points.is_empty():
		draw_line(
			screen_points[screen_points.size() - 1],
			_to_screen(_cursor),
			Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.5),
			1.0,
		)

	for index in screen_points.size():
		var is_first := index == 0
		draw_circle(screen_points[index], 5.0 if is_first else 3.5, UI.ACCENT)
		if is_first and _draft.size() >= 3:
			draw_arc(screen_points[index], CLOSE_RADIUS * _scale, 0, TAU, 24, UI.ACCENT, 1.0)
