extends Control

## Screen 1B — the Night City district map.
##
## Zones are campaign data, not a fixed list. Hover a plate to inspect it, draw a
## new one straight onto the map, edit every field it carries, or delete it. The
## header clock is campaign state too, so advancing an hour edits the save.

const TABS: PackedStringArray = ["map", "areas", "places", "control", "jobs", "net"]

const EconomyRules := preload("res://scripts/rules/economy.gd")

var _tab := "map"
## "inspect", "edit", "draw", "pin" or "reshape".
var _mode := "inspect"
## Whether the rail is showing a zone or a point of interest.
var _focus_kind := "area"
var _focus_poi := ""
## A clicked place remains selected while the pointer travels to its detail rail.
## _focus_poi may temporarily follow hover, then returns to this id.
var _selected_poi := ""
var _focus_id := "pacifica"
var _pinned_id := "pacifica"
var _map: CityMapView
var _rail: VBoxContainer
var _tab_buttons: Dictionary = {}
var _count_label: Label
var _map_dialog: FileDialog
var _month_dialog: ConfirmationDialog
var _hustle_dialog: ConfirmationDialog
var _downtime_dialog: DowntimeDialog
var _hustle_all: CheckBox
var _hustle_list: VBoxContainer
var _hustle_checks: Dictionary = {}
var _campaign_dialog: ConfirmationDialog
var _campaign_name: LineEdit
var _campaign_city: LineEdit
var _campaign_gm: LineEdit
var _closing_month := false
var _lifestyle_queue: Array = []
var _lifestyle_prompt_index := 0
var _after_lifestyle_confirmation := Callable()


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

	_map = CityMapView.new()
	_map.hovered.connect(_on_hovered)
	_map.picked.connect(_on_picked)
	_map.zone_drawn.connect(_on_zone_drawn)
	_map.draft_changed.connect(_refresh_rail)
	_map.poi_hovered.connect(_on_poi_hovered)
	_map.poi_picked.connect(_on_poi_picked)
	_map.poi_placed.connect(_on_poi_placed)
	_map.poi_moved.connect(_on_poi_moved)
	_map.reshape_changed.connect(_on_reshape_changed)
	map_shell.add_child(_map)

	# Keep hover-driven content swaps from feeding a new minimum width back into
	# the HBox. Otherwise a long place/zone value makes the map narrower, moves
	# the polygon out from under the pointer, and starts a hover flicker loop.
	var rail_clamp := FixedWidthRail.new()
	UI.expand(rail_clamp, false, true)
	body.add_child(rail_clamp)

	var rail_shell := UI.panel()
	rail_clamp.add_child(rail_shell)

	_rail = UI.vbox(0)
	rail_shell.add_child(_rail)

	if Store.areas().is_empty():
		_focus_id = ""
	elif Store.area_by_id(_focus_id).is_empty():
		_focus_id = String((Store.areas()[0] as Dictionary)["id"])
	_pinned_id = _focus_id

	_map_dialog = FileDialog.new()
	_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_map_dialog.title = "Choose a map image"
	_map_dialog.filters = PackedStringArray(
		["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg ; Map images", "*.* ; All files"]
	)
	_map_dialog.file_selected.connect(_on_map_selected)
	add_child(_map_dialog)

	_month_dialog = ConfirmationDialog.new()
	_month_dialog.confirmed.connect(_confirm_lifestyle_player)
	_month_dialog.canceled.connect(_cancel_lifestyle_prompts)
	add_child(_month_dialog)

	_build_hustle_dialog()
	_build_downtime_dialog()

	_build_campaign_dialog()
	_refresh()


func _build_hustle_dialog() -> void:
	_hustle_dialog = ConfirmationDialog.new()
	_hustle_dialog.title = "Add free-time Hustle"
	_hustle_dialog.get_ok_button().text = "Roll Hustle"
	var form := UI.vbox(UI.GAP_3)
	form.add_child(UI.body("Choose one, several, or every eligible player. They work concurrently during the same free-time week.", 12, UI.MUTED))
	form.add_child(UI.micro("Players"))
	_hustle_all = CheckBox.new()
	_hustle_all.text = "All eligible players"
	_hustle_all.toggled.connect(_toggle_all_hustlers)
	form.add_child(_hustle_all)
	form.add_child(UI.rule_line())
	_hustle_list = UI.vbox(UI.GAP_1)
	form.add_child(_hustle_list)
	form.add_child(UI.micro("The selected players each roll once; campaign time advances 7 days total.", UI.WARN))
	_hustle_dialog.add_child(UI.margins(form, UI.GAP_4))
	_hustle_dialog.confirmed.connect(_confirm_downtime_hustle)
	add_child(_hustle_dialog)


## Something happening on this corner, for when the party stops somewhere the
## GM had not prepared. Rolled, logged, and left on screen to read off.
func _build_street_encounter() -> Control:
	var box := UI.vbox(UI.GAP_1)
	var button := UI.plain_button("Roll a street encounter")
	button.pressed.connect(roll_street_encounter)
	box.add_child(button)
	var last := Store.last_street_encounter()
	if last.is_empty():
		return box
	var text := UI.body(String(last["text"]), 11, UI.MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	return box


func roll_street_encounter() -> Dictionary:
	var rolled := Store.roll_street_encounter(Dice.SeededRandom.new(Time.get_ticks_usec()))
	Store.set_status("Street encounter rolled")
	_refresh_rail()
	return rolled


## The other things a week off is for. Its own class, so the clock keeps the
## button and this screen does not keep the form.
func _build_downtime_dialog() -> void:
	_downtime_dialog = DowntimeDialog.new()
	_downtime_dialog.performed.connect(func(_action: String, _result: Dictionary) -> void: _refresh())
	add_child(_downtime_dialog)


func open_downtime_dialog(action_key := "") -> void:
	_downtime_dialog.open(action_key)


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

	var upload_button := UI.plain_button("Upload map")
	upload_button.pressed.connect(func() -> void: _map_dialog.popup_centered_ratio(0.72))
	bar.add_child(upload_button)
	var map_toggle := UI.plain_button("Backdrop [M]")
	map_toggle.pressed.connect(func() -> void: _map.toggle_map())
	bar.add_child(map_toggle)
	var settings_button := UI.plain_button("Campaign")
	settings_button.pressed.connect(_open_campaign_dialog)
	bar.add_child(settings_button)

	var right := UI.micro("GM · %s" % String(Store.campaign.get("gm", "unset")))
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.expand(right, true, false)
	bar.add_child(right)

	return bar


## The GM can drop any raster map in behind the zone plates. It is normalized to
## PNG, stored in the save, and drawn under the polygons rather than instead of
## them, so hovering, drawing and reshaping keep working over a real map.
func _on_map_selected(path: String) -> void:
	var loaded := MapAsset.from_file(path)
	if not bool(loaded.get("ok", false)):
		Store.set_status(String(loaded.get("error", "Map image could not be read")))
		return
	var existing: Dictionary = Store.campaign.get("gm_map", {})
	var uploaded: Dictionary = loaded["map"]
	uploaded["opacity"] = float(existing.get("opacity", 0.72))
	Store.campaign["gm_map"] = uploaded
	Store.mark_dirty()
	Store.set_status("Map uploaded")
	_refresh()


func _build_campaign_dialog() -> void:
	_campaign_dialog = ConfirmationDialog.new()
	_campaign_dialog.title = "Campaign settings"
	_campaign_dialog.get_ok_button().text = "Save changes"
	var form := UI.vbox(UI.GAP_3)
	for pair in [["Campaign name", "name"], ["City / setting", "city"], ["Game master", "gm"]]:
		form.add_child(UI.micro(String(pair[0])))
		var field := LineEdit.new()
		field.custom_minimum_size.y = 38
		form.add_child(field)
		match String(pair[1]):
			"name": _campaign_name = field
			"city": _campaign_city = field
			"gm": _campaign_gm = field
	_campaign_dialog.add_child(UI.margins(form, UI.GAP_4))
	_campaign_dialog.confirmed.connect(_save_campaign_settings)
	add_child(_campaign_dialog)


func _open_campaign_dialog() -> void:
	_campaign_name.text = String(Store.campaign.get("name", ""))
	_campaign_city.text = String(Store.campaign.get("city", ""))
	_campaign_gm.text = String(Store.campaign.get("gm", ""))
	_campaign_dialog.popup_centered(Vector2i(520, 330))


func _save_campaign_settings() -> void:
	if _campaign_name.text.strip_edges() == "":
		Store.set_status("Campaign name is required")
		return
	Store.campaign["name"] = _campaign_name.text.strip_edges()
	Store.campaign["city"] = _campaign_city.text.strip_edges()
	Store.campaign["gm"] = _campaign_gm.text.strip_edges()
	Store.mark_dirty()
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_map.toggle_map()
		get_viewport().set_input_as_handled()


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
	var next_focus := area_id if area_id != "" else _pinned_id
	# Mouse motion is reported continuously while the pointer stays over a plate.
	# Rebuilding the rail for an unchanged target made its controls disappear and
	# reappear every frame, which was especially visible when crossing a POI pin.
	if _focus_id == next_focus:
		return
	_focus_id = next_focus
	_map.set_focus(_focus_id)
	if _tab == "map":
		_refresh_rail()


func _on_picked(area_id: String) -> void:
	_focus_kind = "area"
	_selected_poi = ""
	_focus_poi = ""
	_pinned_id = area_id
	_focus_id = area_id
	_map.set_focus(_focus_id)
	_map.set_focus_poi("")
	_refresh_rail()


func _on_zone_drawn(points: PackedVector2Array) -> void:
	var area := NightCity.new_area(points)
	Store.add_area(area)
	_selected_poi = ""
	_focus_poi = ""
	_focus_kind = "area"
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
		if _selected_poi != "":
			var changed := _focus_kind != "poi" or _focus_poi != _selected_poi
			_focus_kind = "poi"
			_focus_poi = _selected_poi
			_map.set_focus_poi(_selected_poi)
			if changed and _tab == "map":
				_refresh_rail()
		elif _focus_kind == "poi":
			_focus_kind = "area"
			_focus_poi = ""
			_map.set_focus_poi("")
			if _tab == "map":
				_refresh_rail()
		return
	if _focus_kind == "poi" and _focus_poi == poi_id:
		return
	_focus_kind = "poi"
	_focus_poi = poi_id
	_map.set_focus_poi(poi_id)
	if _tab == "map":
		_refresh_rail()


func _on_poi_picked(poi_id: String) -> void:
	_focus_kind = "poi"
	_focus_poi = poi_id
	_selected_poi = poi_id
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
	_selected_poi = _focus_poi
	_mode = "inspect"
	_tab = "map"
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == "map"
	_map.set_pin_mode(false)
	_map.set_focus_poi(_focus_poi)
	_refresh()


## Dragging a place writes its new map coordinates immediately. On drop, the
## detail panel refreshes to show the zone at the new position.
func _on_poi_moved(poi_id: String, point: Vector2, finished: bool) -> void:
	var result := Store.relocate_poi(poi_id, point)
	if not bool(result.get("ok", false)):
		return
	_focus_kind = "poi"
	_focus_poi = poi_id
	_selected_poi = poi_id
	_map.set_pois(Store.points_of_interest())
	_map.set_focus_poi(poi_id)
	if finished:
		Store.set_status("Place relocated")
		_refresh_rail()


## Reshaping writes to the campaign on every drag frame, so the plate follows
## the pointer and the save is honestly marked dirty as it happens.
func _on_reshape_changed(area_id: String, points: PackedVector2Array, delta: Vector2) -> void:
	var area := Store.area_by_id(area_id)
	if area.is_empty():
		return
	if delta != Vector2.ZERO:
		NightCity.move_area(area, delta)
	else:
		NightCity.set_points(area, points)
	Store.mark_dirty()
	_map.set_areas(Store.areas(), _hooked_areas())
	_refresh_rail()


func start_reshape(area_id: String) -> void:
	_pinned_id = area_id
	_focus_id = area_id
	_focus_kind = "area"
	_selected_poi = ""
	_focus_poi = ""
	_mode = "reshape"
	_tab = "map"
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == "map"
	_map.set_focus(area_id)
	_map.set_reshape_target(area_id)
	_refresh_rail()


func finish_reshape() -> void:
	_mode = "inspect"
	_map.set_reshape_target("")
	# A reshaped boundary can leave pins on the wrong side of it.
	var moved := CampaignSchema.rehome_pois(Store.campaign)
	if moved > 0:
		Store.set_status("%d place(s) re-homed" % moved)
	_refresh()


func start_pin() -> void:
	_mode = "pin"
	_map.set_pin_mode(true)
	_refresh_rail()


func start_draw() -> void:
	_selected_poi = ""
	_focus_poi = ""
	_focus_kind = "area"
	_mode = "draw"
	_map.set_draw_mode(true)
	_refresh_rail()


func _cancel_draw() -> void:
	_mode = "inspect"
	_map.set_draw_mode(false)
	_map.set_pin_mode(false)
	_map.set_reshape_target("")
	_refresh_rail()


## Public entry points, so the screenshot harness drives the same paths the GM
## clicks rather than a parallel test-only route.
func edit_area(area_id: String) -> void:
	_pinned_id = area_id
	_focus_id = area_id
	_selected_poi = ""
	_focus_poi = ""
	_focus_kind = "area"
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


func reshape_corner_count() -> int:
	return NightCity.points_of(Store.area_by_id(_pinned_id)).size()


## Same effect as dragging corner [param index] to this point.
func drag_corner(index: int, point: Vector2) -> void:
	if _mode != "reshape":
		return
	var area := Store.area_by_id(_pinned_id)
	var points := NightCity.points_of(area)
	if index < 0 or index >= points.size():
		return
	points[index] = point
	_on_reshape_changed(_pinned_id, points, Vector2.ZERO)


## Same effect as dragging the plate itself.
func nudge_zone(delta: Vector2) -> void:
	if _mode != "reshape":
		return
	_on_reshape_changed(_pinned_id, NightCity.points_of(Store.area_by_id(_pinned_id)), delta)


func poi_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for poi in Store.points_of_interest():
		ids.append(String((poi as Dictionary)["id"]))
	return ids


func select_poi(poi_id: String) -> void:
	_on_poi_picked(poi_id)


## Land on whatever the campaign-wide search found here.
##
## Search hands over what the row is rather than what to click, so a zone, a
## place and a beat each arrive at the tab that actually shows them.
func focus_target(target: Dictionary) -> void:
	if target.has("poi_id") and String(target["poi_id"]) != "":
		set_tab("places")
		select_poi(String(target["poi_id"]))
		return
	if target.has("area_id") and String(target["area_id"]) != "":
		_pinned_id = String(target["area_id"])
		_focus_id = _pinned_id
		_focus_kind = "area"
		_selected_poi = ""
		_focus_poi = ""
		set_tab("map")
		_map.set_focus(_pinned_id)
		_refresh_rail()
		return
	if target.has("beat_id"):
		# Beats live in the private window, which is where the GM is sent.
		Store.set_status("Beats open in the GM Window")


## Same effect as dragging a place and dropping it at [param point].
func relocate_poi(poi_id: String, point: Vector2) -> void:
	_on_poi_moved(poi_id, point, true)


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


## The app keeps this screen alive between visits, so it catches itself up on
## the campaign as it stands rather than being rebuilt.
func on_shown() -> void:
	_refresh()


func _refresh() -> void:
	_refresh_count()
	_map.set_custom_map(Store.campaign.get("gm_map", {}))
	_map.set_areas(Store.areas(), _hooked_areas())
	_map.set_pois(Store.points_of_interest())
	_map.set_focus(_focus_id)
	_map.set_focus_poi(_focus_poi if _focus_kind == "poi" else "")
	_map.set_draw_mode(_mode == "draw")
	_map.set_pin_mode(_mode == "pin")
	_map.set_reshape_target(_pinned_id if _mode == "reshape" else "")
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
		# Detach immediately so two rail layouts never participate in the same
		# container pass while the old controls wait for queue_free().
		_rail.remove_child(child)
		child.queue_free()

	_rail.add_child(_build_clock())
	_rail.add_child(UI.rule_line())

	var backdrop := _build_backdrop_row()
	if backdrop != null:
		_rail.add_child(backdrop)
		_rail.add_child(UI.rule_line())

	if _mode == "draw":
		_rail.add_child(_build_draw_panel())
		return
	if _mode == "pin":
		_rail.add_child(_build_pin_panel())
		return
	if _mode == "reshape":
		_rail.add_child(_build_reshape_panel())
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


## Shown only once a map image is behind the plates: its name and how strongly it
## reads under them.
func _build_backdrop_row() -> Control:
	var gm_map: Dictionary = Store.campaign.get("gm_map", {})
	if not gm_map.has("png_base64"):
		if not FileAccess.file_exists(MapAsset.EXTERNAL_PATH):
			return null
		var installed := UI.vbox(3)
		installed.add_child(UI.micro("Backdrop · installed map"))
		installed.add_child(UI.micro("Press M to hide it", UI.MUTED_DIM))
		return UI.margins(installed, UI.GAP_3)

	var box := UI.vbox(3)
	box.add_child(UI.micro("Backdrop · %s" % String(gm_map.get("name", "Campaign map"))))
	var opacity := HSlider.new()
	opacity.min_value = 0.2
	opacity.max_value = 1.0
	opacity.step = 0.05
	opacity.value = float(gm_map.get("opacity", 0.72))
	opacity.tooltip_text = "Map opacity"
	opacity.value_changed.connect(
		func(value: float) -> void:
			var edited: Dictionary = Store.campaign.get("gm_map", {})
			edited["opacity"] = value
			Store.campaign["gm_map"] = edited
			Store.mark_dirty()
			_map.set_custom_map(edited)
	)
	box.add_child(opacity)
	box.add_child(UI.micro("Press M to hide it", UI.MUTED_DIM))
	return UI.margins(box, UI.GAP_3)


func _build_clock() -> Control:
	var clock: Dictionary = Store.campaign["clock"]
	var weather: Dictionary = Store.campaign["weather"]
	var shift := CampaignSchema.shift_of(clock)

	var box := UI.vbox(3)
	box.add_child(UI.micro("Campaign month · %s" % Lifestyle.month_key(clock)))
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
		button.pressed.connect(_request_time_advance.bind(minutes))
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

	box.add_child(_build_month_close(clock))

	return UI.margins(box, UI.GAP_3)


## Downtime billing. Closing a month pays every character's Lifestyle for the
## month ahead and reports who could not cover it.
func _build_month_close(clock: Dictionary) -> Control:
	var box := UI.vbox(3)
	var month := Lifestyle.month_key(clock)
	var close_button := UI.primary_button("Close month · confirm each Lifestyle")
	close_button.disabled = _closing_month or (Store.campaign.get("closed_months", []) as Array).has(month)
	close_button.pressed.connect(_request_month_close)
	box.add_child(close_button)

	var hustle_button := UI.plain_button("+ Add free-time Hustle")
	hustle_button.disabled = _closing_month
	hustle_button.pressed.connect(_open_hustle_dialog)
	box.add_child(hustle_button)

	var downtime_button := UI.plain_button("Downtime · facedown, recover, build")
	downtime_button.disabled = _closing_month
	downtime_button.pressed.connect(open_downtime_dialog)
	box.add_child(downtime_button)

	box.add_child(_build_street_encounter())

	var report: Dictionary = Store.campaign.get("last_lifestyle_report", {})
	if report.is_empty():
		return box

	var unpaid := int(report.get("unpaid", 0))
	box.add_child(
		UI.micro(
			"Last close · %s billed · %d paid · %d unpaid"
			% [report.get("billed_month", ""), int(report.get("paid", 0)), unpaid],
			UI.WARN if unpaid > 0 else UI.GOOD,
		)
	)
	for value in report.get("results", []):
		var item: Dictionary = value
		var owed := String(item.get("status", "")) == "unpaid"
		var summary := (
			"%s · UNPAID · %deb due · 7-day grace" % [item.get("name", "Character"), int(item.get("balance_due", 0))]
			if owed
			else "%s · -%deb" % [item.get("name", "Character"), int(item.get("deducted", 0))]
		)
		box.add_child(UI.micro(summary, UI.WARN if owed else UI.GOOD))
	return box


func _request_month_close() -> void:
	var month := Lifestyle.month_key(Store.campaign["clock"])
	_begin_lifestyle_prompts(
		func() -> void: Store.close_month(month),
		"Close %s and bill Lifestyles for %s" % [month, Lifestyle.next_month(month)],
	)


func _request_time_advance(minutes: int) -> void:
	var before := Lifestyle.month_key(Store.campaign["clock"])
	var after_clock := CampaignSchema.advance_clock(Store.campaign["clock"], minutes)
	if before != Lifestyle.month_key(after_clock):
		_begin_lifestyle_prompts(
			func() -> void:
				Store.advance_clock(minutes)
				_refresh(),
			"Advance time into %s" % Lifestyle.month_key(after_clock),
		)
	else:
		Store.advance_clock(minutes)
		_refresh_rail()


func _lifestyle_players() -> Array:
	var players: Array = []
	for value in Store.characters():
		var character: Dictionary = value
		if String(character.get("kind", "npc")) != "pc":
			continue
		Lifestyle.ensure_character(character)
		players.append(character)
	return players


func _begin_lifestyle_prompts(action: Callable, reason: String) -> void:
	if _closing_month:
		return
	_lifestyle_queue = _lifestyle_players()
	_lifestyle_prompt_index = 0
	_after_lifestyle_confirmation = action
	_closing_month = true
	_month_dialog.set_meta("reason", reason)
	_refresh_rail()
	if _lifestyle_queue.is_empty():
		_finish_lifestyle_prompts()
	else:
		_show_lifestyle_prompt.call_deferred()


func _show_lifestyle_prompt() -> void:
	if _lifestyle_prompt_index >= _lifestyle_queue.size():
		_finish_lifestyle_prompts()
		return
	var character: Dictionary = _lifestyle_queue[_lifestyle_prompt_index]
	var selected := Lifestyle.profile(String(character.get("lifestyle", "kibble")))
	var cost := int(selected["cost"])
	var cash := int(character.get("cash", 0))
	var result := (
		"Payment will succeed, leaving %deb." % (cash - cost)
		if cash >= cost
		else "Cannot cover the bill: %deb short; a 7-day grace period will begin." % (cost - cash)
	)
	_month_dialog.title = "Lifestyle %d of %d · %s" % [
		_lifestyle_prompt_index + 1,
		_lifestyle_queue.size(),
		String(character.get("name", "Player")),
	]
	_month_dialog.dialog_text = "%s\n\n%s · %deb\nCash on hand · %deb\n\n%s" % [
		String(_month_dialog.get_meta("reason", "Update Lifestyles")),
		String(selected["label"]),
		cost,
		cash,
		result,
	]
	_month_dialog.get_ok_button().text = "Confirm player"
	_month_dialog.popup_centered(Vector2i(540, 280))


func _confirm_lifestyle_player() -> void:
	_lifestyle_prompt_index += 1
	if _lifestyle_prompt_index < _lifestyle_queue.size():
		_show_lifestyle_prompt.call_deferred()
	else:
		_finish_lifestyle_prompts.call_deferred()


func _finish_lifestyle_prompts() -> void:
	var action := _after_lifestyle_confirmation
	_lifestyle_queue.clear()
	_lifestyle_prompt_index = 0
	_after_lifestyle_confirmation = Callable()
	if action.is_valid():
		action.call()
	_closing_month = false
	_refresh()


func _cancel_lifestyle_prompts() -> void:
	_lifestyle_queue.clear()
	_lifestyle_prompt_index = 0
	_after_lifestyle_confirmation = Callable()
	_closing_month = false
	Store.set_status("Lifestyle update canceled")
	_refresh()


func _open_hustle_dialog() -> void:
	for child in _hustle_list.get_children():
		child.queue_free()
	_hustle_checks.clear()
	_hustle_all.set_pressed_no_signal(false)
	for value in Store.characters():
		var character: Dictionary = value
		if String(character.get("kind", "npc")) != "pc":
			continue
		if not EconomyRules.HUSTLES.has(String(character.get("role_key", ""))):
			continue
		var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
		var check := CheckBox.new()
		check.text = "%s · %s Rank %d" % [
			String(character.get("name", "Character")),
			String(character.get("role", "Role")),
			rank,
		]
		check.toggled.connect(_sync_hustle_selection.unbind(1))
		_hustle_list.add_child(check)
		_hustle_checks[String(character["id"])] = check
	_hustle_all.disabled = _hustle_checks.is_empty()
	_sync_hustle_selection()
	if _hustle_checks.is_empty():
		Store.set_status("No player character with a Role can take a Hustle")
	_hustle_dialog.popup_centered(
		Vector2i(560, mini(680, 260 + _hustle_checks.size() * 38))
	)


func _toggle_all_hustlers(pressed: bool) -> void:
	for value in _hustle_checks.values():
		(value as CheckBox).set_pressed_no_signal(pressed)
	_sync_hustle_selection()


func _sync_hustle_selection() -> void:
	var selected := _selected_hustlers().size()
	_hustle_all.set_pressed_no_signal(
		selected > 0 and selected == _hustle_checks.size()
	)
	_hustle_dialog.get_ok_button().disabled = selected == 0
	_hustle_dialog.get_ok_button().text = (
		"Roll %d Hustles" % selected if selected != 1 else "Roll Hustle"
	)


func _selected_hustlers() -> Array:
	var selected: Array = []
	for id in _hustle_checks:
		if (_hustle_checks[id] as CheckBox).button_pressed:
			selected.append(String(id))
	return selected


func _confirm_downtime_hustle() -> void:
	var character_ids := _selected_hustlers()
	if character_ids.is_empty():
		return
	var after_clock := CampaignSchema.advance_clock(
		Store.campaign["clock"], EconomyRules.HUSTLE_DAYS * 24 * 60
	)
	if Lifestyle.month_key(Store.campaign["clock"]) != Lifestyle.month_key(after_clock):
		_begin_lifestyle_prompts(
			_execute_downtime_hustles.bind(character_ids.duplicate()),
			"These Hustles advance time into %s" % Lifestyle.month_key(after_clock),
		)
	else:
		_execute_downtime_hustles(character_ids)


func _execute_downtime_hustles(character_ids: Array) -> void:
	var result := Store.perform_hustles(character_ids, Dice.SeededRandom.new(randi()))
	if not bool(result.get("ok", false)):
		Store.set_status(String(result.get("error", "Hustles failed")))
	elif int(result["participants"]) == 1:
		var line: Dictionary = result["results"][0]
		Store.set_status("%s earned %deb · %s" % [
			String(line["name"]), int(line["earned"]), String(line["work"]),
		])
	else:
		Store.set_status(
			"%d players completed Hustles · %deb total"
			% [int(result["participants"]), int(result["total_earned"])]
		)
	_refresh()


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
	box.add_child(_stat_tile("Control", String(area.get("control", "—"))))

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

	var reshape_button := UI.plain_button("Reshape on the map")
	reshape_button.pressed.connect(start_reshape.bind(_focus_id))
	box.add_child(reshape_button)

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
	# Wrapped text asks for no width of its own, so the tile has to claim its
	# share of the grid itself; otherwise the column shrinks to a single letter.
	UI.expand(tile, true, false)
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
	var set_opacity := func(value: float) -> void:
		area["opacity"] = value
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
	box.add_child(_opacity_field(float(area.get("opacity", 1.0)), set_opacity))
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

	var reshape_button := UI.plain_button("Reshape on the map")
	reshape_button.pressed.connect(start_reshape.bind(_pinned_id))
	box.add_child(reshape_button)

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


func _opacity_field(value: float, on_change: Callable) -> Control:
	var box := UI.vbox(2)
	var label := UI.micro("Zone fill · %d%%" % roundi(value * 100.0))
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.tooltip_text = "Set to 0% to make the zone fill transparent"
	slider.value_changed.connect(
		func(new_value: float) -> void:
			label.text = "Zone fill · %d%%" % roundi(new_value * 100.0)
			on_change.call(new_value)
	)
	box.add_child(slider)
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
	select.pressed.connect(_on_picked.bind(id))
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
	edit_button.pressed.connect(edit_area.bind(id))
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



func _build_reshape_panel() -> Control:
	var area := Store.area_by_id(_pinned_id)
	if area.is_empty():
		_mode = "inspect"
		return UI.margins(UI.micro("That zone is gone."), UI.GAP_3)

	var points := NightCity.points_of(area)
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.micro("Reshaping zone"))
	box.add_child(UI.display(String(area["name"]), 26))

	var instructions := UI.body(
		(
			"Drag a corner to move it. Click a cross on an edge to add a corner there. "
			+ "Right-click a corner to remove it. Drag inside the shape to move the whole zone."
		),
		11,
		UI.MUTED,
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.clip_text = false
	box.add_child(instructions)

	box.add_child(UI.rule_line())
	box.add_child(UI.field_row("Corners", str(points.size())))
	box.add_child(
		UI.field_row(
			"Can remove one", "Yes" if points.size() > 3 else "No, three is the minimum",
			UI.TEXT if points.size() > 3 else UI.MUTED
		)
	)
	var pins := Store.pois_in_area(_pinned_id).size()
	box.add_child(UI.field_row("Places inside", str(pins)))
	box.add_child(
		UI.micro("Places are re-checked against the new boundary when you finish.", UI.MUTED_DIM)
	)

	box.add_child(UI.rule_line())
	var recentre := UI.plain_button("Recentre the name")
	recentre.pressed.connect(
		func() -> void:
			var label := NightCity.suggest_label(NightCity.points_of(area))
			area["label"] = [label.x, label.y]
			Store.mark_dirty()
			_map.set_areas(Store.areas(), _hooked_areas())
	)
	box.add_child(recentre)

	var done := UI.primary_button("Done reshaping")
	done.pressed.connect(finish_reshape)
	box.add_child(done)

	return _scrolled(box)


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
	box.add_child(
		UI.micro("Click to keep these details open · drag the pin to relocate it", UI.ACCENT)
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
		if _focus_poi == poi_id or _selected_poi == poi_id:
			_focus_poi = ""
			_selected_poi = ""
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
