extends Control

## Screen 1B — the Night City district map.
##
## Hover a plate to inspect it. The header clock is campaign state, so advancing
## an hour or rolling weather edits the save.

const TABS: PackedStringArray = ["map", "control", "jobs", "net"]

var _tab := "map"
var _focus_id := "pacifica"
var _pinned_id := "pacifica"
var _map: _MapView
var _rail: VBoxContainer
var _clock_box: VBoxContainer
var _tab_buttons: Dictionary = {}
var _upload_button: Button
var _zone_button: Button
var _clear_zones_button: Button
var _map_dialog: FileDialog


func _ready() -> void:
	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_3))

	column.add_child(_build_bar())

	var body := UI.hbox(UI.GAP_3)
	UI.expand(body)
	column.add_child(body)

	var map_shell := UI.panel(UI.PANEL_INSET)
	UI.expand(map_shell)
	body.add_child(map_shell)

	_map = _MapView.new()
	_map.hovered.connect(_on_hovered)
	_map.picked.connect(_on_picked)
	map_shell.add_child(_map)

	var rail_shell := UI.panel()
	rail_shell.custom_minimum_size = Vector2(320, 0)
	UI.expand(rail_shell, false, true)
	body.add_child(rail_shell)

	_rail = UI.vbox(0)
	rail_shell.add_child(_rail)

	_map_dialog = FileDialog.new()
	_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_map_dialog.title = "Choose a map image"
	_map_dialog.filters = PackedStringArray(
		["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg ; Map images", "*.* ; All files"]
	)
	_map_dialog.file_selected.connect(_on_map_selected)
	add_child(_map_dialog)
	_map.zones_changed.connect(_on_zones_changed)

	_refresh()


func _build_bar() -> Control:
	var bar := UI.hbox(UI.GAP_4)

	var left := UI.micro(
		"%s · %s · %d locations"
		% [Store.campaign["city"], Store.campaign["arc"], Store.locations.size()]
	)
	UI.expand(left, true, false)
	bar.add_child(left)

	var tabs := UI.hbox(1)
	bar.add_child(tabs)
	for tab in TABS:
		var button := UI.tab_button(tab, tab == _tab)
		button.pressed.connect(
			func() -> void:
				_tab = tab
				for id in _tab_buttons:
					(_tab_buttons[id] as Button).button_pressed = id == tab
				_refresh()
		)
		tabs.add_child(button)
		_tab_buttons[tab] = button

	_upload_button = UI.plain_button("Upload map")
	_upload_button.pressed.connect(func() -> void: _map_dialog.popup_centered_ratio(0.72))
	bar.add_child(_upload_button)
	_zone_button = UI.plain_button("Draw zone")
	_zone_button.pressed.connect(_start_zone)
	bar.add_child(_zone_button)
	_clear_zones_button = UI.plain_button("Clear zones")
	_clear_zones_button.pressed.connect(_clear_zones)
	bar.add_child(_clear_zones_button)

	var right := UI.micro("GM · %s" % String(Store.campaign.get("gm", "unset")))
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.expand(right, true, false)
	bar.add_child(right)

	return bar


func _on_hovered(district_id: String) -> void:
	_focus_id = district_id if district_id != "" else _pinned_id
	if _tab == "map":
		_refresh_rail()


func _on_picked(district_id: String) -> void:
	_pinned_id = district_id
	_focus_id = district_id
	_refresh_rail()


func _refresh() -> void:
	_map.set_custom_map(Store.campaign.get("gm_map", {}))
	_map.set_overrides(Store.campaign.get("districts", {}), _hooked_districts())
	_map.set_focus(_focus_id)
	_refresh_rail()
	var gm_map: Dictionary = Store.campaign.get("gm_map", {})
	_zone_button.disabled = not gm_map.has("png_base64")
	_clear_zones_button.disabled = (gm_map.get("zones", []) as Array).is_empty()


func _on_map_selected(path: String) -> void:
	var loaded := MapAsset.from_file(path)
	if not bool(loaded.get("ok", false)):
		Store.set_status(String(loaded.get("error", "Map image could not be read")))
		return
	Store.campaign["gm_map"] = loaded["map"]
	Store.mark_dirty()
	Store.set_status("Map uploaded")
	_refresh()


func _start_zone() -> void:
	_map.start_zone()
	_zone_button.disabled = true
	Store.set_status("Zone draw: left-click vertices · right-click to finish")


func _clear_zones() -> void:
	var gm_map: Dictionary = Store.campaign.get("gm_map", {})
	gm_map["zones"] = []
	Store.campaign["gm_map"] = gm_map
	Store.mark_dirty()
	_refresh()
	Store.set_status("Map zones cleared")


func _on_zones_changed(zones: Array) -> void:
	var gm_map: Dictionary = Store.campaign.get("gm_map", {})
	gm_map["zones"] = zones.duplicate(true)
	Store.campaign["gm_map"] = gm_map
	Store.mark_dirty()
	_zone_button.disabled = false
	_refresh()
	Store.set_status("Map zone saved")


func _hooked_districts() -> PackedStringArray:
	var ids := PackedStringArray()
	for hook in Store.campaign.get("hooks", []):
		var entry: Dictionary = hook
		if String(entry.get("status", "open")) == "closed":
			continue
		var id := String(entry["district_id"])
		if not ids.has(id):
			ids.append(id)
	return ids


func _refresh_rail() -> void:
	for child in _rail.get_children():
		child.queue_free()

	_rail.add_child(_build_clock())
	_rail.add_child(UI.rule_line())

	match _tab:
		"map":
			_rail.add_child(_build_district_panel())
		"control":
			_rail.add_child(_build_simple_list("Who holds what", "control"))
		"jobs":
			_rail.add_child(_build_jobs())
		"net":
			_rail.add_child(_build_simple_list("Net density", "net_density"))


func _build_clock() -> Control:
	var clock: Dictionary = Store.campaign["clock"]
	var weather: Dictionary = Store.campaign["weather"]
	var shift := CampaignSchema.shift_of(clock)

	var box := UI.vbox(3)
	box.add_child(UI.micro("In-world clock"))
	box.add_child(UI.display(CampaignSchema.format_clock(clock), 40))
	box.add_child(UI.micro("%s · Shift %d" % [shift["label"], int(shift["shift"])]))
	box.add_child(UI.micro(CampaignSchema.format_date(clock), UI.MUTED_DIM))
	box.add_child(
		UI.micro(
			"%s · %d°C · Vis %d%%"
			% [weather["condition"], int(weather["temperature_c"]), int(weather["visibility_pct"])]
		)
	)

	var actions := UI.hbox(UI.GAP_2)
	for pair in [["+1 hour", 60], ["+1 day", 1440]]:
		var button := UI.plain_button(String(pair[0]))
		UI.expand(button, true, false)
		var minutes := int(pair[1])
		button.pressed.connect(
			func() -> void:
				Store.advance_clock(minutes)
				_refresh_rail()
		)
		actions.add_child(button)
	var weather_button := UI.plain_button("Weather")
	UI.expand(weather_button, true, false)
	weather_button.pressed.connect(
		func() -> void:
			Store.campaign["weather"] = NightCity.roll_weather()
			Store.mark_dirty()
			_refresh_rail()
	)
	actions.add_child(weather_button)
	box.add_child(actions)

	var close_button := UI.primary_button("Close month · auto-pay Lifestyles")
	close_button.pressed.connect(
		func() -> void:
			Store.close_month()
			_refresh()
	)
	box.add_child(close_button)
	var report: Dictionary = Store.campaign.get("last_lifestyle_report", {})
	if not report.is_empty():
		box.add_child(
			UI.micro(
				"Last close · %s billed · %d paid · %d unpaid"
				% [report.get("billed_month", ""), report.get("paid", 0), report.get("unpaid", 0)],
				UI.WARN if int(report.get("unpaid", 0)) > 0 else UI.GOOD,
			)
		)

	return UI.margins(box, UI.GAP_3)


func _build_district_panel() -> Control:
	var district := NightCity.by_id(_focus_id)
	if district.is_empty():
		return UI.margins(UI.micro("Hover a district to inspect it."), UI.GAP_3)

	var overrides: Dictionary = (Store.campaign.get("districts", {}) as Dictionary).get(_focus_id, {})
	var danger := int(overrides.get("danger", district["danger"]))
	var control := String(overrides.get("control", district["control"]))
	var is_combat_zone := String(district["zone_type"]) == "combat"

	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Hovered district"))
	box.add_child(UI.display(String(district["name"]), 30))

	var zone_text := String(NightCity.ZONE_LABELS[district["zone_type"]])
	if String(district["law_response"]) == "Never":
		zone_text += " · No NCPD presence"
	box.add_child(UI.micro(zone_text, UI.ALERT_BRIGHT if is_combat_zone else UI.MUTED))

	var description := UI.body(String(district["description"]), 11)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs the full width, so clipping has to come back off.
	description.clip_text = false
	box.add_child(description)

	if overrides.has("note"):
		var note_panel := UI.panel(UI.PANEL_INSET)
		var note_style := UI.flat(UI.PANEL_INSET, UI.HAIRLINE, 1)
		note_style.border_color = UI.ACCENT_FILL
		note_style.border_width_left = 2
		note_panel.add_theme_stylebox_override("panel", note_style)
		var note := UI.body(String(overrides["note"]), 11, UI.ACCENT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Autowrap needs the full width, so clipping has to come back off.
		note.clip_text = false
		note_panel.add_child(UI.margins(note, UI.GAP_2))
		box.add_child(note_panel)

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", UI.GAP_2)
	stats.add_theme_constant_override("v_separation", UI.GAP_2)
	box.add_child(stats)
	stats.add_child(_stat_tile("Danger", "%d/5" % danger, UI.ALERT_BRIGHT if danger >= 4 else UI.TEXT_DISPLAY))
	stats.add_child(_stat_tile("Population", "~%s" % _thousands(int(district["population"]))))
	stats.add_child(_stat_tile("Law response", String(district["law_response"])))
	stats.add_child(_stat_tile("Net density", String(district["net_density"])))

	var control_tile := _stat_tile("Control", control)
	UI.expand(control_tile, true, false)
	box.add_child(control_tile)

	box.add_child(UI.micro("Job hooks here"))
	var found := 0
	for hook in Store.campaign.get("hooks", []):
		var entry: Dictionary = hook
		if String(entry["district_id"]) != _focus_id or String(entry.get("status", "open")) == "closed":
			continue
		found += 1
		var hook_box := UI.vbox(1)
		hook_box.add_child(UI.value("◇ %s" % String(entry["title"]), 11, UI.ACCENT))
		var detail := UI.body(String(entry["detail"]), 11, UI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Autowrap needs the full width, so clipping has to come back off.
		detail.clip_text = false
		hook_box.add_child(detail)
		box.add_child(hook_box)
	if found == 0:
		box.add_child(UI.micro("None flagged."))

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var wrapper := UI.margins(box, UI.GAP_3)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)
	return scroll


func _stat_tile(label: String, text: String, color := UI.TEXT_DISPLAY) -> Control:
	var tile := UI.panel(UI.PANEL_INSET)
	var box := UI.vbox(1)
	tile.add_child(UI.margins(box, UI.GAP_2))
	box.add_child(UI.micro(label))
	var value := UI.display(text, 15, color)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs the full width, so clipping has to come back off.
	value.clip_text = false
	box.add_child(value)
	return tile


func _build_simple_list(title: String, key: String) -> Control:
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro(title))
	var overrides: Dictionary = Store.campaign.get("districts", {})
	for district in NightCity.districts():
		var entry: Dictionary = district
		var value := String(entry[key])
		if key == "control":
			value = String((overrides.get(entry["id"], {}) as Dictionary).get("control", value))
		box.add_child(UI.rule_line())
		box.add_child(UI.field_row(String(entry["name"]), value))
	return UI.margins(box, UI.GAP_3)


func _build_jobs() -> Control:
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Open hooks"))
	var found := 0
	for hook in Store.campaign.get("hooks", []):
		var entry: Dictionary = hook
		if String(entry.get("status", "open")) == "closed":
			continue
		found += 1
		var card := UI.panel(UI.PANEL_INSET)
		var inner := UI.vbox(1)
		card.add_child(UI.margins(inner, UI.GAP_2))
		var head := UI.hbox()
		var title := UI.value(String(entry["title"]))
		UI.expand(title, true, false)
		head.add_child(title)
		head.add_child(UI.micro(String(entry["status"])))
		inner.add_child(head)
		inner.add_child(UI.micro(String(entry["district_id"]), UI.MUTED_DIM))
		var detail := UI.body(String(entry["detail"]), 11, UI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Autowrap needs the full width, so clipping has to come back off.
		detail.clip_text = false
		inner.add_child(detail)
		box.add_child(card)
	if found == 0:
		box.add_child(UI.micro("Nothing running."))
	return UI.margins(box, UI.GAP_3)


static func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for index in range(text.length() - 1, -1, -1):
		out = text[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return out


## The map itself: polygons drawn to fit, with point-in-polygon hover.
class _MapView extends Control:
	signal hovered(district_id: String)
	signal picked(district_id: String)
	signal zones_changed(zones: Array)

	var _focus := ""
	var _overrides: Dictionary = {}
	var _hooked: PackedStringArray = []
	var _scale := 1.0
	var _origin := Vector2.ZERO
	var _custom_texture: ImageTexture
	var _custom_size := Vector2.ONE
	var _custom_zones: Array = []
	var _custom_signature := 0
	var _drawing_zone := false
	var _draft_points: Array[Vector2] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_focus(district_id: String) -> void:
		if _focus == district_id:
			return
		_focus = district_id
		queue_redraw()

	func set_overrides(overrides: Dictionary, hooked: PackedStringArray) -> void:
		_overrides = overrides
		_hooked = hooked
		queue_redraw()

	func set_custom_map(data: Dictionary) -> void:
		_custom_zones = (data.get("zones", []) as Array).duplicate(true)
		var encoded := String(data.get("png_base64", ""))
		var signature := encoded.hash()
		if encoded == "":
			_custom_texture = null
			_custom_signature = 0
			queue_redraw()
			return
		if signature != _custom_signature or _custom_texture == null:
			var image := MapAsset.decode(data)
			if image == null:
				_custom_texture = null
				queue_redraw()
				return
			_custom_texture = ImageTexture.create_from_image(image)
			_custom_size = Vector2(image.get_width(), image.get_height())
			_custom_signature = signature
		queue_redraw()

	func start_zone() -> void:
		if _custom_texture == null:
			return
		_drawing_zone = true
		_draft_points.clear()
		queue_redraw()

	func _custom_rect() -> Rect2:
		var fit := minf(size.x / _custom_size.x, size.y / _custom_size.y)
		var drawn := _custom_size * fit
		return Rect2((size - drawn) * 0.5, drawn)

	func _to_normalized(point: Vector2) -> Vector2:
		var rect := _custom_rect()
		if not rect.has_point(point):
			return Vector2(-1, -1)
		return (point - rect.position) / rect.size

	func _custom_to_screen(point: Variant) -> Vector2:
		var rect := _custom_rect()
		return rect.position + Vector2(float(point[0]), float(point[1])) * rect.size

	func _finish_zone() -> void:
		if _draft_points.size() < 3:
			return
		var points: Array = []
		for point in _draft_points:
			points.append([point.x, point.y])
		_custom_zones.append(
			{
				"id": "zone-%d" % Time.get_ticks_usec(),
				"label": "Zone %d" % (_custom_zones.size() + 1),
				"color": "#00E5FF",
				"opacity": 0.24,
				"points": points,
			}
		)
		_drawing_zone = false
		_draft_points.clear()
		zones_changed.emit(_custom_zones.duplicate(true))
		queue_redraw()

	func _recompute_transform() -> void:
		# Letterbox the 1000 × 700 diagram into whatever space the panel gives us.
		_scale = minf(size.x / NightCity.MAP_SIZE.x, size.y / NightCity.MAP_SIZE.y)
		_origin = (size - NightCity.MAP_SIZE * _scale) * 0.5

	func _to_screen(point: Vector2) -> Vector2:
		return _origin + point * _scale

	func _to_map(point: Vector2) -> Vector2:
		return (point - _origin) / maxf(_scale, 0.0001)

	func _gui_input(event: InputEvent) -> void:
		if _custom_texture != null:
			if not _drawing_zone:
				return
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				var mouse := event as InputEventMouseButton
				if mouse.button_index == MOUSE_BUTTON_LEFT:
					var normalized := _to_normalized(mouse.position)
					if normalized.x >= 0:
						_draft_points.append(normalized)
						queue_redraw()
					accept_event()
				elif mouse.button_index == MOUSE_BUTTON_RIGHT:
					_finish_zone()
					accept_event()
			return
		if event is InputEventMouseMotion:
			var at := _to_map((event as InputEventMouseMotion).position)
			for district in NightCity.districts():
				var entry: Dictionary = district
				if Geometry2D.is_point_in_polygon(at, entry["polygon"]):
					if _focus != String(entry["id"]):
						hovered.emit(String(entry["id"]))
					return
			hovered.emit("")
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var at := _to_map((event as InputEventMouseButton).position)
			for district in NightCity.districts():
				var entry: Dictionary = district
				if Geometry2D.is_point_in_polygon(at, entry["polygon"]):
					picked.emit(String(entry["id"]))
					return

	func _draw() -> void:
		_recompute_transform()

		# A faint grid behind the plates, as in the mockup.
		var step := 20.0 * _scale
		var grid_colour := Color("141c26")
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), grid_colour, 1.0)
			x += step
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), grid_colour, 1.0)
			y += step

		if _custom_texture != null:
			var rect := _custom_rect()
			draw_texture_rect(_custom_texture, rect, false)
			_draw_custom_zones()
			return

		for district in NightCity.districts():
			var entry: Dictionary = district
			var id := String(entry["id"])
			var focused := id == _focus
			var colors := NightCity.zone_colors(String(entry["zone_type"]), focused)

			var points := PackedVector2Array()
			for point in entry["polygon"]:
				points.append(_to_screen(point))

			draw_colored_polygon(points, colors["fill"])
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, colors["stroke"], 2.0 if focused else 1.5)

			var label_at := _to_screen(entry["label"])
			var name_size := int(maxf(13.0, 19.0 * _scale))
			draw_string(
				UI.DISPLAY_FONT,
				label_at,
				String(entry["name"]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				name_size,
				UI.TEXT_DISPLAY,
			)
			var subtitle := String((_overrides.get(id, {}) as Dictionary).get("control", entry["subtitle"]))
			draw_string(
				UI.BODY_BOLD_FONT,
				label_at + Vector2(0, 14),
				UI._letterspace(subtitle.to_upper()),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				UI.MUTED,
			)

			if _hooked.has(id):
				var marker := _to_screen(NightCity.centroid(entry))
				var diamond := PackedVector2Array([
					marker + Vector2(0, -8), marker + Vector2(8, 0),
					marker + Vector2(0, 8), marker + Vector2(-8, 0),
					marker + Vector2(0, -8),
				])
				draw_polyline(diamond, UI.ACCENT, 1.5)

	func _draw_custom_zones() -> void:
		for value in _custom_zones:
			var zone: Dictionary = value
			var polygon := PackedVector2Array()
			for point in zone.get("points", []):
				polygon.append(_custom_to_screen(point))
			if polygon.size() < 3:
				continue
			var color := Color(String(zone.get("color", "#00E5FF")))
			color.a = float(zone.get("opacity", 0.24))
			draw_colored_polygon(polygon, color)
			var outline := color
			outline.a = 0.95
			var closed := polygon.duplicate()
			closed.append(polygon[0])
			draw_polyline(closed, outline, 2.5, true)
			var center := Vector2.ZERO
			for point in polygon:
				center += point
			center /= polygon.size()
			draw_string(
				UI.BODY_BOLD_FONT,
				center,
				String(zone.get("label", "Zone")),
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				12,
				UI.TEXT_DISPLAY,
			)
		if _draft_points.is_empty():
			return
		var draft := PackedVector2Array()
		for point in _draft_points:
			draft.append(_custom_to_screen([point.x, point.y]))
		for point in draft:
			draw_circle(point, 4, UI.WARN)
		if draft.size() > 1:
			draw_polyline(draft, UI.WARN, 2.5, true)
