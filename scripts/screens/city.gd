extends Control

## Screen 1B — the Night City district map.
##
## Zones are campaign data, not a fixed list. Hover a plate to inspect it, draw a
## new one straight onto the map, edit every field it carries, or delete it. The
## header clock is campaign state too, so advancing an hour edits the save.

const TABS: PackedStringArray = ["map", "areas", "places", "control", "jobs", "net"]

## Clicking within this many map units of the first vertex closes the polygon.
const CLOSE_RADIUS := 18.0

var _tab := "map"
## "inspect", "edit", "draw" or "pin".
var _mode := "inspect"
## Whether the rail is showing a zone or a point of interest.
var _focus_kind := "area"
var _focus_poi := ""
var _focus_id := "pacifica"
var _pinned_id := "pacifica"
var _map: _MapView
var _rail: VBoxContainer
var _tab_buttons: Dictionary = {}
var _count_label: Label


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
	_map.zone_drawn.connect(_on_zone_drawn)
	_map.draft_changed.connect(_refresh_rail)
	_map.poi_hovered.connect(_on_poi_hovered)
	_map.poi_picked.connect(_on_poi_picked)
	_map.poi_placed.connect(_on_poi_placed)
	map_shell.add_child(_map)

	var rail_shell := UI.panel()
	rail_shell.custom_minimum_size = Vector2(320, 0)
	UI.expand(rail_shell, false, true)
	body.add_child(rail_shell)

	_rail = UI.vbox(0)
	rail_shell.add_child(_rail)

	if Store.areas().is_empty():
		_focus_id = ""
	elif Store.area_by_id(_focus_id).is_empty():
		_focus_id = String((Store.areas()[0] as Dictionary)["id"])
	_pinned_id = _focus_id
	_refresh()


func _build_bar() -> Control:
	var bar := UI.hbox(UI.GAP_4)

	_count_label = UI.micro("")
	UI.expand(_count_label, true, false)
	bar.add_child(_count_label)

	var tabs := UI.hbox(1)
	bar.add_child(tabs)
	for tab in TABS:
		var button := UI.tab_button(tab, tab == _tab)
		button.pressed.connect(set_tab.bind(String(tab)))
		tabs.add_child(button)
		_tab_buttons[tab] = button

	var right := UI.micro("GM · %s" % String(Store.campaign.get("gm", "unset")))
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.expand(right, true, false)
	bar.add_child(right)

	return bar


func set_tab(tab: String) -> void:
	_tab = tab
	if _mode == "edit":
		_mode = "inspect"
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).button_pressed = id == tab
	_refresh_rail()


func _on_hovered(area_id: String) -> void:
	if _mode != "inspect" or _focus_kind == "poi":
		return
	_focus_id = area_id if area_id != "" else _pinned_id
	_map.set_focus(_focus_id)
	if _tab == "map":
		_refresh_rail()


func _on_picked(area_id: String) -> void:
	_focus_kind = "area"
	_pinned_id = area_id
	_focus_id = area_id
	_map.set_focus(_focus_id)
	_refresh_rail()


func _on_zone_drawn(points: PackedVector2Array) -> void:
	var area := NightCity.new_area(points)
	Store.add_area(area)
	_focus_id = String(area["id"])
	_pinned_id = _focus_id
	# Straight into the form: a zone with no name or faction is not useful yet.
	_mode = "edit"
	_tab = "map"
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).button_pressed = id == _tab
	_refresh()


func _on_poi_hovered(poi_id: String) -> void:
	if _mode != "inspect":
		return
	if poi_id == "":
		if _focus_kind == "poi":
			_focus_kind = "area"
			_map.set_focus_poi("")
			if _tab == "map":
				_refresh_rail()
		return
	_focus_kind = "poi"
	_focus_poi = poi_id
	_map.set_focus_poi(poi_id)
	if _tab == "map":
		_refresh_rail()


func _on_poi_picked(poi_id: String) -> void:
	_focus_kind = "poi"
	_focus_poi = poi_id
	_map.set_focus_poi(poi_id)
	_tab = "map"
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == "map"
	_refresh_rail()


func _on_poi_placed(point: Vector2) -> void:
	var poi := NightCity.new_poi(point, NightCity.area_at(Store.areas(), point))
	Store.add_poi(poi)
	_focus_kind = "poi"
	_focus_poi = String(poi["id"])
	_mode = "inspect"
	_tab = "map"
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == "map"
	_map.set_pin_mode(false)
	_map.set_focus_poi(_focus_poi)
	_refresh()


func start_pin() -> void:
	_mode = "pin"
	_map.set_pin_mode(true)
	_refresh_rail()


func start_draw() -> void:
	_mode = "draw"
	_map.set_draw_mode(true)
	_refresh_rail()


func _cancel_draw() -> void:
	_mode = "inspect"
	_map.set_draw_mode(false)
	_map.set_pin_mode(false)
	_refresh_rail()


## Public entry points, so the screenshot harness drives the same paths the GM
## clicks rather than a parallel test-only route.
func edit_area(area_id: String) -> void:
	_pinned_id = area_id
	_focus_id = area_id
	_tab = "map"
	_mode = "edit"
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == "map"
	_map.set_focus(area_id)
	_refresh_rail()


func place_draft_corner(point: Vector2) -> void:
	_map.add_draft_corner(point)


func draft_corner_count() -> int:
	return _map.draft_size()


func close_draft() -> void:
	_map.close_draft()


func poi_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for poi in Store.points_of_interest():
		ids.append(String((poi as Dictionary)["id"]))
	return ids


func select_poi(poi_id: String) -> void:
	_on_poi_picked(poi_id)


## Same effect as clicking the map at this point while in pin mode.
func place_pin(point: Vector2) -> void:
	if _mode != "pin":
		return
	_on_poi_placed(point)


func area_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for area in Store.areas():
		ids.append(String((area as Dictionary)["id"]))
	return ids


func _refresh() -> void:
	_refresh_count()
	_map.set_areas(Store.areas(), _hooked_areas())
	_map.set_pois(Store.points_of_interest())
	_map.set_focus(_focus_id)
	_map.set_focus_poi(_focus_poi if _focus_kind == "poi" else "")
	_map.set_draw_mode(_mode == "draw")
	_map.set_pin_mode(_mode == "pin")
	_refresh_rail()


## The zone count in the header changes as zones are drawn and deleted.
func _refresh_count() -> void:
	if _count_label == null:
		return
	var total := Store.areas().size()
	_count_label.text = UI._letterspace(
		(
			"%s · %s · %d %s"
			% [
				Store.campaign["city"],
				Store.campaign["arc"],
				total,
				"zone" if total == 1 else "zones",
			]
		).to_upper()
	)


func _hooked_areas() -> PackedStringArray:
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

	if _mode == "draw":
		_rail.add_child(_build_draw_panel())
		return
	if _mode == "pin":
		_rail.add_child(_build_pin_panel())
		return

	match _tab:
		"map":
			if _mode == "edit":
				_rail.add_child(_build_editor())
			elif _focus_kind == "poi":
				_rail.add_child(_build_poi_panel())
			else:
				_rail.add_child(_build_area_panel())
		"areas":
			_rail.add_child(_build_areas_list())
		"places":
			_rail.add_child(_build_places_list())
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
				Store.campaign["clock"] = CampaignSchema.advance_clock(Store.campaign["clock"], minutes)
				Store.mark_dirty()
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

	return UI.margins(box, UI.GAP_3)


# -- inspect -------------------------------------------------------------------


func _build_area_panel() -> Control:
	var area := Store.area_by_id(_focus_id)
	if area.is_empty():
		var empty := UI.vbox(UI.GAP_2)
		empty.add_child(UI.micro("No zone selected."))
		var draw_button := UI.primary_button("+ Draw a zone")
		draw_button.pressed.connect(start_draw)
		empty.add_child(draw_button)
		return UI.margins(empty, UI.GAP_3)

	var danger := int(area.get("danger", 0))
	var is_combat_zone := String(area.get("zone_type", "")) == "combat"

	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Hovered zone" if _focus_id != _pinned_id else "Selected zone"))
	box.add_child(UI.display(String(area["name"]), 30))

	var zone_text := String(NightCity.ZONE_LABELS.get(area.get("zone_type", ""), "Zone"))
	if String(area.get("law_response", "")) == "Never":
		zone_text += " · No NCPD presence"
	box.add_child(UI.micro(zone_text, UI.ALERT_BRIGHT if is_combat_zone else UI.MUTED))

	if String(area.get("description", "")) != "":
		var description := UI.body(String(area["description"]), 11)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.clip_text = false
		box.add_child(description)

	if String(area.get("note", "")) != "":
		box.add_child(_note_panel(String(area["note"])))

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", UI.GAP_2)
	stats.add_theme_constant_override("v_separation", UI.GAP_2)
	box.add_child(stats)
	stats.add_child(
		_stat_tile("Danger", "%d/5" % danger, UI.ALERT_BRIGHT if danger >= 4 else UI.TEXT_DISPLAY)
	)
	stats.add_child(_stat_tile("Population", "~%s" % _thousands(int(area.get("population", 0)))))
	stats.add_child(_stat_tile("Law response", String(area.get("law_response", "—"))))
	stats.add_child(_stat_tile("Net density", String(area.get("net_density", "—"))))
	var control_tile := _stat_tile("Control", String(area.get("control", "—")))
	UI.expand(control_tile, true, false)
	box.add_child(control_tile)

	box.add_child(UI.micro("Job hooks here"))
	var hooks := Store.hooks_for_area(_focus_id)
	for hook in hooks:
		var entry: Dictionary = hook
		var hook_box := UI.vbox(1)
		hook_box.add_child(UI.value("◇ %s" % String(entry["title"]), 11, UI.ACCENT))
		var detail := UI.body(String(entry["detail"]), 11, UI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.clip_text = false
		hook_box.add_child(detail)
		box.add_child(hook_box)
	if hooks.is_empty():
		box.add_child(UI.micro("None flagged."))

	box.add_child(UI.rule_line())
	var actions := UI.hbox(UI.GAP_2)
	var edit_button := UI.primary_button("Edit zone")
	UI.expand(edit_button, true, false)
	edit_button.pressed.connect(
		func() -> void:
			_pinned_id = _focus_id
			_mode = "edit"
			_refresh_rail()
	)
	actions.add_child(edit_button)
	var delete_button := UI.plain_button("Delete")
	UI.expand(delete_button, true, false)
	delete_button.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete_button.pressed.connect(confirm_delete.bind(_focus_id))
	actions.add_child(delete_button)
	box.add_child(actions)

	var add_place := UI.plain_button("+ Add a place here")
	add_place.pressed.connect(start_pin)
	box.add_child(add_place)

	var pins := Store.pois_in_area(_focus_id)
	if not pins.is_empty():
		box.add_child(UI.micro("Places in this zone"))
		for pin in pins:
			var entry: Dictionary = pin
			var linked := Store.location_by_id(String(entry.get("location_id", "")))
			var row := UI.plain_button(
				"%s%s" % [String(entry["name"]), "" if linked.is_empty() else " ▸"]
			)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.pressed.connect(_on_poi_picked.bind(String(entry["id"])))
			box.add_child(row)

	return _scrolled(box)


func _note_panel(text: String) -> Control:
	var panel := UI.panel(UI.PANEL_INSET)
	var style := UI.flat(UI.PANEL_INSET, UI.HAIRLINE, 1)
	style.border_color = UI.ACCENT_FILL
	style.border_width_left = 2
	panel.add_theme_stylebox_override("panel", style)
	var note := UI.body(text, 11, UI.ACCENT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.clip_text = false
	panel.add_child(UI.margins(note, UI.GAP_2))
	return panel


func _stat_tile(label: String, text: String, color := UI.TEXT_DISPLAY) -> Control:
	var tile := UI.panel(UI.PANEL_INSET)
	var box := UI.vbox(1)
	tile.add_child(UI.margins(box, UI.GAP_2))
	box.add_child(UI.micro(label))
	var value := UI.display(text, 15, color)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.clip_text = false
	box.add_child(value)
	return tile


func _scrolled(box: Control) -> Control:
	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var wrapper := UI.margins(box, UI.GAP_3)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)
	return scroll


# -- edit ----------------------------------------------------------------------


func _build_editor() -> Control:
	var area := Store.area_by_id(_pinned_id)
	if area.is_empty():
		_mode = "inspect"
		return UI.margins(UI.micro("That zone is gone."), UI.GAP_3)

	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Editing zone"))
	box.add_child(UI.display(String(area["name"]), 24))

	# Each setter is named rather than inlined: a multi-line lambda inside a
	# wrapped call argument is a parse hazard in GDScript.
	var set_name := func(text: String) -> void:
		area["name"] = text
		_commit()
	var set_subtitle := func(text: String) -> void:
		area["subtitle"] = text
		_commit()
	var set_control := func(text: String) -> void:
		area["control"] = text
		_commit()
	var set_note := func(text: String) -> void:
		area["note"] = text
		_commit()
	var set_zone_type := func(value: String) -> void:
		area["zone_type"] = value
		_commit()
	var set_law := func(value: String) -> void:
		area["law_response"] = value
		_commit()
	var set_net := func(value: String) -> void:
		area["net_density"] = value
		_commit()
	var set_danger := func(value: int) -> void:
		area["danger"] = value
		_commit()
	var set_population := func(value: int) -> void:
		area["population"] = value
		_commit()

	box.add_child(_text_field("Name", String(area.get("name", "")), set_name))
	box.add_child(_text_field("Subtitle", String(area.get("subtitle", "")), set_subtitle))
	box.add_child(_text_field("Control", String(area.get("control", "")), set_control))
	box.add_child(
		_choice_field(
			"What it is", NightCity.ZONE_TYPES, String(area.get("zone_type", "residential")), set_zone_type
		)
	)
	box.add_child(_number_field("Danger", int(area.get("danger", 1)), 1, 5, 1, set_danger))
	box.add_child(
		_number_field("Population", int(area.get("population", 0)), 0, 5000000, 1000, set_population)
	)
	box.add_child(
		_choice_field(
			"Law response", NightCity.LAW_RESPONSES, String(area.get("law_response", "Moderate")), set_law
		)
	)
	box.add_child(
		_choice_field(
			"Net density", NightCity.NET_DENSITIES, String(area.get("net_density", "Medium")), set_net
		)
	)
	box.add_child(_text_field("GM note", String(area.get("note", "")), set_note))

	box.add_child(UI.micro("Description"))
	var description := TextEdit.new()
	description.text = String(area.get("description", ""))
	description.custom_minimum_size = Vector2(0, 96)
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	description.add_theme_font_size_override("font_size", 11)
	description.text_changed.connect(
		func() -> void:
			area["description"] = description.text
			Store.mark_dirty()
	)
	box.add_child(description)

	box.add_child(UI.rule_line())
	var actions := UI.hbox(UI.GAP_2)
	var done := UI.primary_button("Done")
	UI.expand(done, true, false)
	done.pressed.connect(
		func() -> void:
			_mode = "inspect"
			_refresh()
	)
	actions.add_child(done)
	var delete_button := UI.plain_button("Delete")
	UI.expand(delete_button, true, false)
	delete_button.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete_button.pressed.connect(confirm_delete.bind(_pinned_id))
	actions.add_child(delete_button)
	box.add_child(actions)

	return _scrolled(box)


## Field edits write straight into the campaign, so the map redraws as you type.
func _commit() -> void:
	Store.mark_dirty()
	_map.set_areas(Store.areas(), _hooked_areas())


func _text_field(label: String, value: String, on_change: Callable) -> Control:
	var box := UI.vbox(2)
	box.add_child(UI.micro(label))
	var edit := LineEdit.new()
	edit.text = value
	edit.text_changed.connect(on_change)
	box.add_child(edit)
	return box


func _number_field(
	label: String, value: int, minimum: int, maximum: int, step: int, on_change: Callable
) -> Control:
	var box := UI.vbox(2)
	box.add_child(UI.micro(label))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.value_changed.connect(func(new_value: float) -> void: on_change.call(int(new_value)))
	box.add_child(spin)
	return box


func _choice_field(label: String, options: PackedStringArray, value: String, on_change: Callable) -> Control:
	var box := UI.vbox(2)
	box.add_child(UI.micro(label))
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	for index in options.size():
		picker.add_item(String(options[index]).capitalize(), index)
		if String(options[index]) == value:
			picker.select(index)
	picker.item_selected.connect(
		func(index: int) -> void: on_change.call(String(options[index]))
	)
	box.add_child(picker)
	return box


# -- areas list ------------------------------------------------------------------


func _build_areas_list() -> Control:
	var box := UI.vbox(UI.GAP_2)

	var head := UI.hbox()
	var title := UI.micro("Areas")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("%d drawn" % Store.areas().size()))
	box.add_child(head)

	for area in Store.areas():
		box.add_child(_build_area_row(area))

	if Store.areas().is_empty():
		box.add_child(UI.micro("No zones yet. Draw one on the map."))

	box.add_child(UI.rule_line())
	var draw_button := UI.primary_button("+ Draw new zone")
	draw_button.pressed.connect(start_draw)
	box.add_child(draw_button)

	return _scrolled(box)


func _build_area_row(area: Dictionary) -> Control:
	var id := String(area["id"])
	var is_selected := id == _pinned_id
	var danger := int(area.get("danger", 0))

	var card := UI.panel(UI.PANEL_INSET, UI.ACCENT if is_selected else UI.HAIRLINE)
	var box := UI.vbox(2)
	card.add_child(UI.margins(box, UI.GAP_2))

	var head := UI.hbox(UI.GAP_2)
	var select := Button.new()
	select.flat = true
	select.focus_mode = Control.FOCUS_NONE
	select.text = String(area["name"]).to_upper()
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.add_theme_font_override("font", UI.DISPLAY_FONT)
	select.add_theme_font_size_override("font_size", 14)
	select.add_theme_color_override("font_color", UI.TEXT_DISPLAY)
	UI.expand(select, true, false)
	select.pressed.connect(
		func() -> void:
			_pinned_id = id
			_focus_id = id
			_map.set_focus(id)
			_refresh_rail()
	)
	head.add_child(select)
	head.add_child(
		UI.micro("Danger %d" % danger, UI.ALERT_BRIGHT if danger >= 4 else UI.MUTED)
	)
	box.add_child(head)

	box.add_child(
		UI.elide(
			UI.micro(
				"%s · %s"
				% [
					String(NightCity.ZONE_LABELS.get(area.get("zone_type", ""), "Zone")),
					String(area.get("control", "—")),
				]
			)
		)
	)
	box.add_child(
		UI.elide(
			UI.micro(
				"Pop ~%s · Law %s · Net %s"
				% [
					_thousands(int(area.get("population", 0))),
					String(area.get("law_response", "—")),
					String(area.get("net_density", "—")),
				],
				UI.MUTED_DIM
			)
		)
	)

	var actions := UI.hbox(UI.GAP_2)
	var edit_button := UI.plain_button("Edit")
	UI.expand(edit_button, true, false)
	edit_button.pressed.connect(
		func() -> void:
			_pinned_id = id
			_focus_id = id
			_tab = "map"
			_mode = "edit"
			for key in _tab_buttons:
				(_tab_buttons[key] as Button).button_pressed = key == "map"
			_map.set_focus(id)
			_refresh_rail()
	)
	actions.add_child(edit_button)
	var delete_button := UI.plain_button("Delete")
	UI.expand(delete_button, true, false)
	delete_button.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete_button.pressed.connect(confirm_delete.bind(id))
	actions.add_child(delete_button)
	box.add_child(actions)

	return card


# -- draw --------------------------------------------------------------------------


func _build_draw_panel() -> Control:
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Drawing a zone"))
	box.add_child(UI.display("New zone", 26))

	var instructions := UI.body(
		(
			"Click the map to drop corners. Click the first corner again to close the shape. "
			+ "Right-click removes the last corner."
		),
		11,
		UI.MUTED,
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.clip_text = false
	box.add_child(instructions)

	var count := _map.draft_size()
	box.add_child(UI.rule_line())
	box.add_child(UI.field_row("Corners placed", str(count)))
	box.add_child(
		UI.field_row(
			"Ready to close",
			"Yes" if count >= 3 else "Needs %d more" % (3 - count),
			UI.GOOD if count >= 3 else UI.MUTED,
		)
	)

	box.add_child(UI.rule_line())
	var actions := UI.hbox(UI.GAP_2)
	var finish := UI.primary_button("Close shape")
	UI.expand(finish, true, false)
	finish.disabled = count < 3
	finish.pressed.connect(func() -> void: _map.close_draft())
	actions.add_child(finish)
	var cancel := UI.plain_button("Cancel")
	UI.expand(cancel, true, false)
	cancel.pressed.connect(_cancel_draw)
	actions.add_child(cancel)
	box.add_child(actions)

	return UI.margins(box, UI.GAP_3)


# -- delete ---------------------------------------------------------------------------


func confirm_delete(area_id: String) -> void:
	var area := Store.area_by_id(area_id)
	if area.is_empty():
		return
	var hook_count := Store.hooks_for_area(area_id).size()
	var pin_count := Store.pois_in_area(area_id).size()
	var message := "This removes the zone from the map and from every list."
	if hook_count > 0:
		message += (
			" %d job %s here will be removed with it."
			% [hook_count, "hook" if hook_count == 1 else "hooks"]
		)
	if pin_count > 0:
		message += (
			" %d %s here will stay on the map, no longer inside any zone."
			% [pin_count, "place" if pin_count == 1 else "places"]
		)

	_confirm("Delete zone", String(area["name"]), message, func() -> void:
		var dropped := Store.remove_area(area_id)
		if _pinned_id == area_id or _focus_id == area_id:
			var remaining := Store.areas()
			_pinned_id = String((remaining[0] as Dictionary)["id"]) if not remaining.is_empty() else ""
			_focus_id = _pinned_id
		_mode = "inspect"
		_focus_kind = "area"
		Store.set_status(
			"Zone deleted" if dropped == 0 else "Zone and %d hook(s) deleted" % dropped
		)
		_refresh())


## One confirmation dialog for anything destructive on this screen.
func _confirm(kicker: String, subject: String, message: String, on_confirm: Callable) -> void:
	var scrim := ColorRect.new()
	scrim.name = "DeletePrompt"
	scrim.color = Color(0.024, 0.035, 0.051, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scrim.grow_vertical = Control.GROW_DIRECTION_BOTH
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var dialog := UI.panel(UI.PANEL_RAISED, UI.ALERT)
	dialog.custom_minimum_size = Vector2(420, 0)
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	scrim.add_child(dialog)

	var box := UI.vbox(UI.GAP_2)
	dialog.add_child(UI.margins(box, UI.GAP_5))
	box.add_child(UI.micro(kicker))
	box.add_child(UI.display(subject, 26))
	var text := UI.body(message, 12, UI.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.clip_text = false
	box.add_child(text)

	var actions := UI.hbox(UI.GAP_2)
	var confirm := UI.primary_button("Delete")
	UI.expand(confirm, true, false)
	confirm.set_meta("choice", "confirm")
	confirm.pressed.connect(
		func() -> void:
			scrim.queue_free()
			on_confirm.call()
	)
	actions.add_child(confirm)
	var cancel := UI.plain_button("Keep it")
	UI.expand(cancel, true, false)
	cancel.set_meta("choice", "cancel")
	cancel.pressed.connect(scrim.queue_free)
	actions.add_child(cancel)
	box.add_child(actions)


# -- points of interest ------------------------------------------------------------


func _build_pin_panel() -> Control:
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Adding a place"))
	box.add_child(UI.display("New place", 26))
	var text := UI.body(
		"Click anywhere on the map to drop the pin. It picks up whichever zone it lands in.",
		11,
		UI.MUTED,
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.clip_text = false
	box.add_child(text)
	box.add_child(UI.rule_line())
	var cancel := UI.plain_button("Cancel")
	cancel.pressed.connect(_cancel_draw)
	box.add_child(cancel)
	return UI.margins(box, UI.GAP_3)


func _build_poi_panel() -> Control:
	var poi := Store.poi_by_id(_focus_poi)
	if poi.is_empty():
		_focus_kind = "area"
		return _build_area_panel()

	var area := Store.area_by_id(String(poi.get("area_id", "")))
	var linked := Store.location_by_id(String(poi.get("location_id", "")))

	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Point of interest"))
	box.add_child(UI.display(String(poi["name"]), 28, NightCity.poi_color(String(poi.get("kind", "")))))
	box.add_child(
		UI.micro(
			"%s · %s"
			% [
				String(poi.get("kind", "place")).capitalize(),
				String(area["name"]) if not area.is_empty() else "Outside every zone",
			]
		)
	)

	var set_name := func(value: String) -> void:
		poi["name"] = value
		_commit()
	var set_kind := func(value: String) -> void:
		poi["kind"] = value
		_commit()
	box.add_child(_text_field("Name", String(poi.get("name", "")), set_name))
	box.add_child(
		_choice_field("Kind", NightCity.POI_KINDS, String(poi.get("kind", "landmark")), set_kind)
	)

	box.add_child(UI.micro("Notes"))
	var notes := TextEdit.new()
	notes.text = String(poi.get("description", ""))
	notes.custom_minimum_size = Vector2(0, 80)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_theme_font_size_override("font_size", 11)
	notes.text_changed.connect(
		func() -> void:
			poi["description"] = notes.text
			Store.mark_dirty()
	)
	box.add_child(notes)

	box.add_child(UI.rule_line())
	box.add_child(UI.micro("Linked location"))

	if linked.is_empty():
		box.add_child(
			UI.micro("Nothing linked — this pin is a note on the map, not a place to play.", UI.MUTED_DIM)
		)
	else:
		var card := UI.panel(UI.PANEL_INSET)
		var inner := UI.vbox(1)
		card.add_child(UI.margins(inner, UI.GAP_2))
		inner.add_child(UI.value(String(linked["name"]), 12, UI.ACCENT))
		inner.add_child(
			UI.micro(
				"%d × %d grid · %d props · %d units"
				% [
					int(linked.get("grid_width", 0)),
					int(linked.get("grid_height", 0)),
					(linked.get("props", []) as Array).size(),
					(linked.get("units", []) as Array).size(),
				]
			)
		)
		box.add_child(card)

		var open_button := UI.primary_button("▶ Open location")
		open_button.pressed.connect(func() -> void: Store.open_location(String(linked["id"])))
		box.add_child(open_button)

	box.add_child(_build_location_link_row(poi))

	box.add_child(UI.rule_line())
	var delete_button := UI.plain_button("Delete place")
	delete_button.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete_button.pressed.connect(confirm_delete_poi.bind(String(poi["id"])))
	box.add_child(delete_button)

	return _scrolled(box)


## Pick an existing board or build a fresh one for this pin.
func _build_location_link_row(poi: Dictionary) -> Control:
	var box := UI.vbox(UI.GAP_2)

	if not Store.locations.is_empty():
		box.add_child(UI.micro("Link an existing board"))
		var picker := OptionButton.new()
		picker.add_item("— none —", 0)
		var current := String(poi.get("location_id", ""))
		for index in Store.locations.size():
			var location: Dictionary = Store.locations[index]
			picker.add_item(String(location["name"]), index + 1)
			if String(location["id"]) == current:
				picker.select(index + 1)
		picker.item_selected.connect(
			func(index: int) -> void:
				poi["location_id"] = (
					"" if index == 0 else String((Store.locations[index - 1] as Dictionary)["id"])
				)
				Store.mark_dirty()
				_refresh_rail()
		)
		box.add_child(picker)

	var create := UI.plain_button("+ Build a new board here")
	create.pressed.connect(
		func() -> void:
			var location := Store.create_location_for_poi(poi)
			Store.set_status("Created %s" % String(location["name"]))
			_refresh_rail()
	)
	box.add_child(create)
	return box


func _build_places_list() -> Control:
	var box := UI.vbox(UI.GAP_2)

	var head := UI.hbox()
	var title := UI.micro("Places")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("%d pinned" % Store.points_of_interest().size()))
	box.add_child(head)

	for poi in Store.points_of_interest():
		box.add_child(_build_poi_row(poi))

	if Store.points_of_interest().is_empty():
		box.add_child(UI.micro("No places yet. Drop a pin on the map."))

	box.add_child(UI.rule_line())
	var add := UI.primary_button("+ Add place")
	add.pressed.connect(start_pin)
	box.add_child(add)

	return _scrolled(box)


func _build_poi_row(poi: Dictionary) -> Control:
	var id := String(poi["id"])
	var is_selected := _focus_kind == "poi" and id == _focus_poi
	var area := Store.area_by_id(String(poi.get("area_id", "")))
	var linked := Store.location_by_id(String(poi.get("location_id", "")))

	var card := UI.panel(UI.PANEL_INSET, UI.ACCENT if is_selected else UI.HAIRLINE)
	var box := UI.vbox(2)
	card.add_child(UI.margins(box, UI.GAP_2))

	var head := UI.hbox(UI.GAP_2)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UI.flat(NightCity.poi_color(String(poi.get("kind", "")))))
	head.add_child(dot)

	var select := Button.new()
	select.flat = true
	select.focus_mode = Control.FOCUS_NONE
	select.text = String(poi["name"]).to_upper()
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.add_theme_font_override("font", UI.DISPLAY_FONT)
	select.add_theme_font_size_override("font_size", 13)
	select.add_theme_color_override("font_color", UI.TEXT_DISPLAY)
	UI.expand(select, true, false)
	select.pressed.connect(_on_poi_picked.bind(id))
	head.add_child(select)
	head.add_child(UI.micro(String(poi.get("kind", ""))))
	box.add_child(head)

	box.add_child(
		UI.elide(
			UI.micro(
				"%s · %s"
				% [
					String(area["name"]) if not area.is_empty() else "Outside every zone",
					String(linked["name"]) if not linked.is_empty() else "No board linked",
				],
				UI.MUTED if not linked.is_empty() else UI.MUTED_DIM
			)
		)
	)

	var actions := UI.hbox(UI.GAP_2)
	var open_button := UI.plain_button("Open")
	UI.expand(open_button, true, false)
	open_button.disabled = linked.is_empty()
	if not linked.is_empty():
		open_button.pressed.connect(func() -> void: Store.open_location(String(linked["id"])))
	actions.add_child(open_button)
	var delete_button := UI.plain_button("Delete")
	UI.expand(delete_button, true, false)
	delete_button.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete_button.pressed.connect(confirm_delete_poi.bind(id))
	actions.add_child(delete_button)
	box.add_child(actions)

	return card


func confirm_delete_poi(poi_id: String) -> void:
	var poi := Store.poi_by_id(poi_id)
	if poi.is_empty():
		return
	var linked := Store.location_by_id(String(poi.get("location_id", "")))
	var message := "This removes the pin from the map."
	if not linked.is_empty():
		message += " The board \"%s\" stays in the campaign." % String(linked["name"])
	_confirm("Delete place", String(poi["name"]), message, func() -> void:
		Store.remove_poi(poi_id)
		if _focus_poi == poi_id:
			_focus_poi = ""
			_focus_kind = "area"
		Store.set_status("Place deleted")
		_refresh())


# -- other tabs -------------------------------------------------------------------------


func _build_simple_list(title: String, key: String) -> Control:
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro(title))
	for area in Store.areas():
		var entry: Dictionary = area
		box.add_child(UI.rule_line())
		box.add_child(UI.field_row(String(entry["name"]), String(entry.get(key, "—"))))
	if Store.areas().is_empty():
		box.add_child(UI.micro("No zones yet."))
	return _scrolled(box)


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
		var area := Store.area_by_id(String(entry["district_id"]))
		inner.add_child(
			UI.micro(String(area["name"]) if not area.is_empty() else String(entry["district_id"]), UI.MUTED_DIM)
		)
		var detail := UI.body(String(entry["detail"]), 11, UI.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.clip_text = false
		inner.add_child(detail)
		box.add_child(card)
	if found == 0:
		box.add_child(UI.micro("Nothing running."))
	return _scrolled(box)


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


# -- the map ------------------------------------------------------------------------------


## Polygons drawn to fit, with point-in-polygon hover and a vertex-by-vertex
## drawing mode.
class _MapView extends Control:
	signal hovered(area_id: String)
	signal picked(area_id: String)
	signal zone_drawn(points: PackedVector2Array)
	signal draft_changed
	signal poi_hovered(poi_id: String)
	signal poi_picked(poi_id: String)
	signal poi_placed(point: Vector2)

	## How close, in map units, the pointer has to be to hit a pin.
	const PIN_RADIUS := 14.0

	var _areas: Array = []
	var _pois: Array = []
	var _focus := ""
	var _focus_poi := ""
	var _hooked: PackedStringArray = []
	var _drawing := false
	var _pinning := false
	var _draft := PackedVector2Array()
	var _cursor := Vector2.ZERO
	var _scale := 1.0
	var _origin := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

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
		if event is InputEventMouseMotion:
			var at := _to_map((event as InputEventMouseMotion).position)
			if _drawing or _pinning:
				_cursor = at
				queue_redraw()
				return
			var pin := _poi_at(at)
			poi_hovered.emit(pin)
			if pin == "":
				hovered.emit(_area_at(at))
			return

		if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
			return
		var button := event as InputEventMouseButton
		var at := _to_map(button.position)

		if _pinning:
			if button.button_index == MOUSE_BUTTON_LEFT:
				poi_placed.emit(at)
			return

		if not _drawing:
			if button.button_index == MOUSE_BUTTON_LEFT:
				var pin := _poi_at(at)
				if pin != "":
					poi_picked.emit(pin)
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

			draw_colored_polygon(points, colors["fill"])
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, colors["stroke"], 2.0 if focused else 1.5)

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
				var marker := _to_screen(NightCity.centroid_of(NightCity.points_of(entry)))
				draw_polyline(
					PackedVector2Array([
						marker + Vector2(0, -8), marker + Vector2(8, 0),
						marker + Vector2(0, 8), marker + Vector2(-8, 0),
						marker + Vector2(0, -8),
					]),
					UI.ACCENT,
					1.5,
				)

		_draw_pins()

		if _drawing:
			_draw_draft()
		elif _pinning:
			_draw_pin_cursor()

	## A pin: a filled head on a short stem, with its name beside it. Drawn after
	## the plates so it always reads on top of them.
	func _draw_pins() -> void:
		for poi in _pois:
			var entry: Dictionary = poi
			var at := _to_screen(NightCity.poi_position(entry))
			var colour: Color = NightCity.poi_color(String(entry.get("kind", "")))
			var focused := String(entry["id"]) == _focus_poi
			var linked := String(entry.get("location_id", "")) != ""

			draw_line(at, at + Vector2(0, 9), colour, 1.5)
			draw_circle(at, 6.0 if focused else 5.0, colour)
			# A hollow head means the pin is a note; a filled one has a board
			# behind it that the party can walk into.
			if not linked:
				draw_circle(at, 3.0, UI.PANEL_INSET)
			if focused:
				draw_arc(at, 11.0, 0, TAU, 24, colour, 1.5)

			draw_string(
				UI.BODY_BOLD_FONT,
				at + Vector2(10, 4),
				String(entry.get("name", "")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				colour if focused else UI.TEXT,
			)

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
