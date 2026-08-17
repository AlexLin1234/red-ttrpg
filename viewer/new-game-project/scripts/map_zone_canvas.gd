class_name MapZoneCanvas
extends Control

signal zones_changed(zones: Array)

var zones: Array = []
var drawing := false
var draft_points: Array[Vector2] = []
var map_size := Vector2(1.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_map_size(width: int, height: int) -> void:
	map_size = Vector2(maxi(width, 1), maxi(height, 1))
	queue_redraw()


func set_zones(value: Array) -> void:
	zones = value.duplicate(true)
	queue_redraw()


func start_drawing() -> void:
	drawing = true
	draft_points.clear()
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func cancel_drawing() -> void:
	drawing = false
	draft_points.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func clear_zones() -> void:
	zones.clear()
	cancel_drawing()
	zones_changed.emit(zones.duplicate(true))


func _gui_input(event: InputEvent) -> void:
	if not drawing or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var normalized := _to_normalized(event.position)
		if normalized.x >= 0.0:
			draft_points.append(normalized)
			queue_redraw()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_finish_zone()
		accept_event()


func _finish_zone() -> void:
	if draft_points.size() < 3:
		return
	var points: Array = []
	for point in draft_points:
		points.append([point.x, point.y])
	var number := zones.size() + 1
	zones.append(
		{
			"id": "zone_%s" % Time.get_ticks_msec(),
			"label": "Zone %s" % number,
			"color": "#00E5FF",
			"opacity": 0.24,
			"points": points,
		}
	)
	cancel_drawing()
	zones_changed.emit(zones.duplicate(true))


func _map_rect() -> Rect2:
	var scale_factor := minf(size.x / map_size.x, size.y / map_size.y)
	var rendered := map_size * scale_factor
	return Rect2((size - rendered) * 0.5, rendered)


func _to_normalized(point: Vector2) -> Vector2:
	var rect := _map_rect()
	if not rect.has_point(point):
		return Vector2(-1.0, -1.0)
	return Vector2((point.x - rect.position.x) / rect.size.x, (point.y - rect.position.y) / rect.size.y)


func _to_screen(point: Variant) -> Vector2:
	var rect := _map_rect()
	return rect.position + Vector2(float(point[0]), float(point[1])) * rect.size


func _draw() -> void:
	for zone_value in zones:
		if not zone_value is Dictionary:
			continue
		var zone: Dictionary = zone_value
		var polygon := PackedVector2Array()
		for point in zone.get("points", []):
			polygon.append(_to_screen(point))
		if polygon.size() < 3:
			continue
		var color := Color(str(zone.get("color", "#00E5FF")))
		color.a = float(zone.get("opacity", 0.24))
		draw_colored_polygon(polygon, color)
		var outline := color
		outline.a = 0.95
		var closed := polygon
		closed.append(polygon[0])
		draw_polyline(closed, outline, 3.0, true)
		var center := Vector2.ZERO
		for point in polygon:
			center += point
		center /= polygon.size()
		draw_string(
			ThemeDB.fallback_font,
			center,
			str(zone.get("label", "Zone")),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1.0,
			18,
			Color.WHITE,
		)
	if draft_points.is_empty():
		return
	var draft := PackedVector2Array()
	for point in draft_points:
		draft.append(_to_screen([point.x, point.y]))
	for point in draft:
		draw_circle(point, 5.0, Color("FFE45C"))
	if draft.size() > 1:
		draw_polyline(draft, Color("FFE45C"), 3.0, true)
