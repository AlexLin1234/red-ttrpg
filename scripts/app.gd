extends Control

## The app shell: the header bar, screen routing, and the keyboard shortcuts a
## GM reaches for mid-session.

const LibraryScreen := preload("res://scripts/screens/library.gd")
const CityScreen := preload("res://scripts/screens/city.gd")
const LocationScreen := preload("res://scripts/screens/location.gd")
const ForgeScreen := preload("res://scripts/screens/forge.gd")
const MarketScreen := preload("res://scripts/screens/market.gd")
const ItemWorkshopScreen := preload("res://scripts/screens/item_workshop.gd")

const SCREENS := [
	{"id": "library", "label": "Library"},
	{"id": "workshop", "label": "Item Workshop"},
	{"id": "city", "label": "City"},
	{"id": "location", "label": "Location"},
	{"id": "forge", "label": "Forge"},
	{"id": "market", "label": "Market"},
	{"id": "night_market", "label": "Night Market"},
]

var _current := "library"
var _nav_buttons: Dictionary = {}
var _content: Control
var _screen: Control
var _title_label: Label
var _dirty_label: Label
var _status_label: Label
var _save_button: Button


func _ready() -> void:
	name = "App"
	theme = UI.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = UI.BG_PAGE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := UI.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_header())

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)

	Store.campaign_opened.connect(_on_campaign_opened)
	Store.campaign_changed.connect(_refresh_header)
	Store.campaign_saved.connect(_refresh_header)
	Store.status_changed.connect(_on_status)
	Store.open_location_requested.connect(func(_id: String) -> void: _show("location"))

	Store.seed_library_if_empty()
	_show("library")


func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.flat(UI.PANEL, UI.HAIRLINE, 1))
	bar.custom_minimum_size = Vector2(0, 36)

	var row := UI.hbox(UI.GAP_3)
	row.add_theme_constant_override("margin_left", UI.GAP_3)
	bar.add_child(UI.margins(row, 6))

	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(7, 7)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.add_theme_stylebox_override("panel", UI.flat(UI.ACCENT))
	row.add_child(mark)

	var brand := UI.display("Redline", 15)
	row.add_child(brand)

	_title_label = UI.micro("GM Console · Build 0.5.0")
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title_label)

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_spacer)

	var nav := UI.hbox(1)
	row.add_child(nav)
	for index in SCREENS.size():
		var entry: Dictionary = SCREENS[index]
		var button := UI.tab_button("%s %d" % [entry["label"], index + 1], index == 0)
		button.pressed.connect(_show.bind(String(entry["id"])))
		nav.add_child(button)
		_nav_buttons[String(entry["id"])] = button

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_spacer)

	_status_label = UI.micro("", UI.GOOD)
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status_label)

	_dirty_label = UI.micro("Local library")
	_dirty_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dirty_label)

	_save_button = UI.primary_button("Save")
	_save_button.visible = false
	_save_button.pressed.connect(func() -> void: Store.save())
	row.add_child(_save_button)

	return bar


func _show(screen_id: String) -> void:
	if screen_id not in ["library", "workshop"] and not Store.is_open():
		return
	_current = screen_id
	for id in _nav_buttons:
		(_nav_buttons[id] as Button).button_pressed = id == screen_id

	if is_instance_valid(_screen):
		_screen.queue_free()
	match screen_id:
		"library":
			_screen = LibraryScreen.new()
		"workshop":
			_screen = ItemWorkshopScreen.new()
		"city":
			_screen = CityScreen.new()
		"location":
			_screen = LocationScreen.new()
		"forge":
			_screen = ForgeScreen.new()
		"market":
			_screen = MarketScreen.new()
		"night_market":
			_screen = MarketScreen.new()
			_screen.set("night", true)
		_:
			_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_screen.grow_vertical = Control.GROW_DIRECTION_BOTH
	_content.add_child(_screen)
	_refresh_header()


func _on_campaign_opened() -> void:
	_show("city")


func _on_status(message: String) -> void:
	_status_label.text = UI._letterspace(message.to_upper())
	_status_label.visible = message != ""


func _refresh_header() -> void:
	if Store.is_open():
		_title_label.text = UI._letterspace(
			("%s / %s" % [Store.campaign["name"], Store.campaign["city"]]).to_upper()
		)
		_dirty_label.text = UI._letterspace("Unsaved changes" if Store.dirty else "Saved")
		_dirty_label.add_theme_color_override("font_color", UI.WARN if Store.dirty else UI.MUTED)
		_save_button.visible = true
	else:
		_title_label.text = UI._letterspace("GM CONSOLE · BUILD 0.5.0")
		_dirty_label.text = UI._letterspace("Local library")
		_save_button.visible = false

	for id in _nav_buttons:
		(_nav_buttons[id] as Button).disabled = id not in ["library", "workshop"] and not Store.is_open()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey

	if key.ctrl_pressed and key.keycode == KEY_S:
		if Store.is_open():
			Store.save()
		get_viewport().set_input_as_handled()
		return

	# Number keys jump between screens.
	var index := key.keycode - KEY_1
	if index >= 0 and index < SCREENS.size() and not key.ctrl_pressed and not key.alt_pressed:
		_show(String((SCREENS[index] as Dictionary)["id"]))
		get_viewport().set_input_as_handled()
