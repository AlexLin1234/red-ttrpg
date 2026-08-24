extends Control

## The app shell: the header bar, screen routing, and the keyboard shortcuts a
## GM reaches for mid-session.

const LibraryScreen := preload("res://scripts/screens/library.gd")
const CityScreen := preload("res://scripts/screens/city.gd")
const NotesBeatsScreen := preload("res://scripts/screens/notes_beats.gd")
const LocationScreen := preload("res://scripts/screens/location.gd")
const ForgeScreen := preload("res://scripts/screens/forge.gd")
const MarketScreen := preload("res://scripts/screens/market.gd")
const ItemWorkshopScreen := preload("res://scripts/screens/item_workshop.gd")
const AssistantScreen := preload("res://scripts/screens/assistant.gd")
const NetrunScreen := preload("res://scripts/screens/netrun.gd")
const VehiclesScreen := preload("res://scripts/screens/vehicles.gd")
const PlayerDisplayScreen := preload("res://scripts/screens/player_display.gd")

## The keys, in one place, so the overlay that lists them cannot drift from
## what they do.
const SHORTCUTS: Array[Dictionary] = [
	{"keys": "1 … 0", "does": "Jump to a screen, in the order of the tabs"},
	{"keys": "Ctrl + K", "does": "Find anything in the campaign"},
	{"keys": "Ctrl + S", "does": "Save"},
	{"keys": "M", "does": "Show or hide the uploaded map, on the City screen"},
	{"keys": "?  or  F1", "does": "This panel"},
	{"keys": "Escape", "does": "Close whatever is open over the screen"},
]

const SCREENS := [
	{"id": "library", "label": "Library"},
	{"id": "workshop", "label": "Item Workshop"},
	{"id": "city", "label": "City"},
	{"id": "location", "label": "Location"},
	{"id": "netrun", "label": "Netrun"},
	{"id": "vehicles", "label": "Garage"},
	{"id": "forge", "label": "Forge"},
	{"id": "market", "label": "Market"},
	{"id": "night_market", "label": "Night Market"},
	{"id": "assistant", "label": "Assistant"},
]

var _current := "library"
var _nav_buttons: Dictionary = {}
var _screens: Dictionary = {}
var _screen_revisions: Dictionary = {}
var _content: Control
var _screen: Control
var _title_label: Label
var _dirty_label: Label
var _status_label: Label
var _save_button: Button
var _gm_window_button: Button
var _gm_window: Window
var _gm_notes_screen: Control
var _gm_notes_campaign_path := ""
var _recovery_dialog: ConfirmationDialog
var _search: SearchPalette
var _shortcuts: ShortcutsOverlay
var _player_window_button: Button
var _player_window: Window
var _player_screen: Control


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
	Store.player_view_changed.connect(_on_player_view)

	_search = SearchPalette.new()
	_search.chosen.connect(_go_to)
	add_child(_search)

	_shortcuts = ShortcutsOverlay.new()
	add_child(_shortcuts)
	AppSettings.apply(get_tree())

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

	# The campaign title takes the slack and gives it back: it expands to fill
	# what the bar has spare and elides when it has none, so a long campaign name
	# beside a full set of header buttons cannot push the whole app wider than
	# the window and clip the Save button off the right-hand edge.
	_title_label = UI.elide(UI.micro("GM Console · Build 0.5.0"))
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Enough to read a few words of the campaign name once the nav strip has
	# taken its share, and no more: this is the half of the bar that gives way.
	_title_label.custom_minimum_size.x = 116
	UI.expand(_title_label, true, false)
	row.add_child(_title_label)

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

	_gm_window_button = UI.plain_button("GM Window")
	_gm_window_button.tooltip_text = "Open private Notes / Beats in a separate native window"
	_gm_window_button.visible = false
	_gm_window_button.pressed.connect(open_gm_notes_window)
	row.add_child(_gm_window_button)

	_player_window_button = UI.plain_button("Player Display")
	_player_window_button.tooltip_text = (
		"Open the table's board in a separate window, for the second screen"
	)
	_player_window_button.visible = false
	_player_window_button.pressed.connect(toggle_player_display)
	row.add_child(_player_window_button)

	# A downtime report or a Hustle result can be a whole sentence, and the bar
	# has ten tabs on it. It elides rather than pushing the Save button off the
	# edge of the window.
	_status_label = UI.elide(UI.micro("", UI.GOOD))
	_status_label.custom_minimum_size.x = 180
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


## Show a screen, building it the first time and keeping it afterwards.
##
## Screens used to be freed and reconstructed on every press of the nav bar,
## which threw away scroll position, selection, the City's pan and zoom, the
## Assistant's answer, and — worst of it — a fight in progress, so a GM who
## looked something up in the Market came back to an encounter that had never
## happened. They are kept alive and hidden instead.
##
## A kept screen can go stale, so each one is offered the chance to catch up:
## [code]wants_rebuild()[/code] says it cannot, [code]on_shown()[/code] says how
## it does, and a screen with neither is rebuilt whenever the campaign has been
## edited since it was last drawn.
func _show(screen_id: String) -> void:
	# The Assistant opens without a campaign so its library and key can be set up
	# before the first save exists; its Ask tab is the part that needs one.
	if screen_id not in ["library", "workshop", "assistant"] and not Store.is_open():
		return
	_current = screen_id
	for id in _nav_buttons:
		(_nav_buttons[id] as Button).button_pressed = id == screen_id

	if is_instance_valid(_screen) and _screen != _screens.get(screen_id):
		_screen.visible = false
		if _screen.has_method("on_hidden"):
			_screen.call("on_hidden")

	var cached: Control = _screens.get(screen_id)
	if is_instance_valid(cached) and _is_stale(screen_id, cached):
		_forget(screen_id)
		cached = null

	if not is_instance_valid(cached):
		cached = _build_screen(screen_id)
		cached.set_anchors_preset(Control.PRESET_FULL_RECT)
		cached.grow_horizontal = Control.GROW_DIRECTION_BOTH
		cached.grow_vertical = Control.GROW_DIRECTION_BOTH
		_screens[screen_id] = cached
		_content.add_child(cached)
	elif cached.has_method("on_shown"):
		cached.call("on_shown")

	cached.visible = true
	_screen_revisions[screen_id] = Store.edit_revision
	_screen = cached
	_refresh_header()


## Whether a kept screen has to be thrown away rather than caught up.
func _is_stale(screen_id: String, screen: Control) -> bool:
	if screen.has_method("wants_rebuild") and bool(screen.call("wants_rebuild")):
		return true
	if int(_screen_revisions.get(screen_id, -1)) == Store.edit_revision:
		return false
	# Nothing has changed for a screen that can catch itself up.
	return not screen.has_method("on_shown")


func _forget(screen_id: String) -> void:
	var screen: Control = _screens.get(screen_id)
	if is_instance_valid(screen):
		# queue_free defers to the end of the frame, so a screen being replaced
		# by its own rebuild would draw underneath it for one frame.
		screen.visible = false
		screen.queue_free()
	_screens.erase(screen_id)
	_screen_revisions.erase(screen_id)


## Throw every kept screen away.
##
## A screen built against one campaign must never be shown for another, so this
## runs whenever the open campaign changes rather than being reasoned about
## screen by screen.
func _drop_screens() -> void:
	for id in _screens.keys():
		_forget(String(id))
	_screen = null


func _build_screen(screen_id: String) -> Control:
	match screen_id:
		"library":
			return LibraryScreen.new()
		"workshop":
			return ItemWorkshopScreen.new()
		"city":
			return CityScreen.new()
		"location":
			return LocationScreen.new()
		"netrun":
			return NetrunScreen.new()
		"vehicles":
			return VehiclesScreen.new()
		"forge":
			return ForgeScreen.new()
		"market":
			return MarketScreen.new()
		"night_market":
			var night := MarketScreen.new()
			night.set("night", true)
			return night
		"assistant":
			return AssistantScreen.new()
		_:
			return Control.new()


func _on_campaign_opened() -> void:
	# Never carry private GM material visibly from one opened save into another.
	if is_instance_valid(_gm_window):
		_gm_window.hide()
	_drop_screens()
	_gm_notes_campaign_path = ""
	_show("city")
	_offer_recovery()


## A campaign that did not close cleanly leaves an autosave newer than its file.
##
## Applying it silently would be worse than losing it: a GM who saved on purpose
## and then crashed would find themselves quietly reverted. So it is a question,
## asked once, with the age of what is on offer.
func _offer_recovery() -> void:
	var found := Store.recovery()
	if found.is_empty():
		return
	if is_instance_valid(_recovery_dialog):
		_recovery_dialog.queue_free()
	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.title = "Unsaved work found"
	_recovery_dialog.theme = UI.build_theme()
	_recovery_dialog.get_ok_button().text = "Recover it"
	_recovery_dialog.get_cancel_button().text = "Keep the saved version"
	var box := UI.vbox(UI.GAP_2)
	box.add_child(UI.display(Autosave.describe(Store.path), 18))
	var body := UI.body(
		(
			"This campaign was left with work that had not been saved. Recovering "
			+ "loads it as unsaved changes, so the file on disk is untouched until "
			+ "you save. Keeping the saved version throws the autosave away."
		),
		13,
		UI.MUTED
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(430, 0)
	box.add_child(body)
	_recovery_dialog.add_child(UI.margins(box, UI.GAP_4))
	_recovery_dialog.confirmed.connect(
		func() -> void:
			Store.recover()
			_drop_screens()
			_show("city")
	)
	_recovery_dialog.canceled.connect(Store.discard_recovery)
	add_child(_recovery_dialog)
	_recovery_dialog.popup_centered(Vector2i(500, 260))


## Opens private campaign material outside the main app viewport. Streamers can
## capture Redline's main window while keeping this native OS window off-stream.
func open_gm_notes_window() -> void:
	if not Store.is_open():
		return
	if not is_instance_valid(_gm_window):
		_build_gm_window()
	if _gm_notes_campaign_path != Store.path or not is_instance_valid(_gm_notes_screen):
		_rebuild_gm_window_content()
	_gm_window.show()
	_gm_window.grab_focus()


## Show or hide the table's screen.
##
## Unlike the GM window this one is meant to be seen — and, for a streaming
## table, captured — so it asks for no capture exclusion. It is a separate OS
## window rather than a mode of the main one so it can be dragged onto the TV
## and left there while the GM keeps working.
func toggle_player_display() -> void:
	if not Store.is_open():
		return
	if is_instance_valid(_player_window) and _player_window.visible:
		_player_window.hide()
		_refresh_header()
		return
	if not is_instance_valid(_player_window):
		_build_player_window()
	_player_window.show()
	_player_screen.call("present", Store.player_view())
	_refresh_header()


func player_display_visible() -> bool:
	return is_instance_valid(_player_window) and _player_window.visible


func _build_player_window() -> void:
	_player_window = Window.new()
	_player_window.name = "PlayerDisplay"
	_player_window.title = "Redline · Player Display"
	_player_window.visible = false
	_player_window.force_native = true
	_player_window.size = Vector2i(1280, 800)
	_player_window.min_size = Vector2i(800, 520)
	_player_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_player_window.theme = UI.build_theme()
	_player_window.close_requested.connect(
		func() -> void:
			_player_window.hide()
			_refresh_header()
	)
	add_child(_player_window)

	var background := ColorRect.new()
	background.color = UI.BG_DEEP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_window.add_child(background)

	_player_screen = PlayerDisplayScreen.new()
	_player_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_screen.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_player_screen.grow_vertical = Control.GROW_DIRECTION_BOTH
	_player_window.add_child(_player_screen)


func _on_player_view(payload: Dictionary) -> void:
	if is_instance_valid(_player_screen):
		_player_screen.call("present", payload)


func _build_gm_window() -> void:
	_gm_window = Window.new()
	_gm_window.name = "PrivateGMNotes"
	_gm_window.title = "Redline · Private GM Notes / Beats"
	_gm_window.visible = false
	_gm_window.force_native = true
	_gm_window.exclude_from_capture = true
	_gm_window.size = Vector2i(1400, 860)
	_gm_window.min_size = Vector2i(1040, 680)
	_gm_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_gm_window.theme = UI.build_theme()
	_gm_window.close_requested.connect(_gm_window.hide)
	add_child(_gm_window)


func _rebuild_gm_window_content() -> void:
	if is_instance_valid(_gm_notes_screen):
		_gm_notes_screen.queue_free()
	for child in _gm_window.get_children():
		if child != _gm_notes_screen:
			child.queue_free()

	var background := ColorRect.new()
	background.color = UI.BG_PAGE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gm_window.add_child(background)

	_gm_notes_screen = NotesBeatsScreen.new()
	_gm_notes_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gm_notes_screen.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gm_notes_screen.grow_vertical = Control.GROW_DIRECTION_BOTH
	_gm_window.add_child(_gm_notes_screen)
	_gm_notes_campaign_path = Store.path


## Show the keys, and the two display preferences that answer the same
## question. Public so a test can reach it the way the key does.
func open_shortcuts() -> void:
	_shortcuts.present(SHORTCUTS)


## Open the campaign-wide search. Public so a shortcut, a button and a test can
## all reach it the same way.
func open_search() -> void:
	if not Store.is_open():
		return
	_search.open()


## Go wherever a search result lives, and select it once there.
##
## The palette hands back what the row is rather than a screen to show, so the
## selection and the navigation stay together: finding a character and landing
## on someone else's sheet would be worse than not finding them.
func _go_to(row: Dictionary) -> void:
	var target: Dictionary = row.get("target", {})
	if target.has("character_id"):
		Store.active_character_id = String(target["character_id"])
	if target.has("location_id"):
		Store.active_location_id = String(target["location_id"])
	if target.has("architecture_id"):
		Store.active_architecture_id = String(target["architecture_id"])
	if target.has("vehicle_id"):
		Store.active_vehicle_id = String(target["vehicle_id"])
	_show(String(row.get("screen", "library")))
	if target.has("area_id") or target.has("poi_id") or target.has("beat_id"):
		var screen := _screens.get("city") as Control
		if is_instance_valid(screen) and screen.has_method("focus_target"):
			screen.call("focus_target", target)


func _on_status(message: String) -> void:
	_status_label.text = UI._letterspace(message.to_upper())
	_status_label.visible = message != ""


func _refresh_header() -> void:
	if Store.is_open():
		_title_label.text = UI._letterspace(
			("%s / %s" % [Store.campaign["name"], Store.campaign["city"]]).to_upper()
		)
		var dirty_text := "Saved"
		if Store.dirty:
			dirty_text = (
				"Unsaved · autosaved" if Store.last_autosave > 0 else "Unsaved changes"
			)
		_dirty_label.text = UI._letterspace(dirty_text)
		_dirty_label.add_theme_color_override("font_color", UI.WARN if Store.dirty else UI.MUTED)
		_save_button.visible = true
		_gm_window_button.visible = true
		_player_window_button.visible = true
		_player_window_button.text = UI._letterspace(
			("Player Display ✓" if player_display_visible() else "Player Display").to_upper()
		)
	else:
		_title_label.text = UI._letterspace("GM CONSOLE · BUILD 0.5.0")
		_dirty_label.text = UI._letterspace("Local library")
		_save_button.visible = false
		_gm_window_button.visible = false
		_player_window_button.visible = false
		if is_instance_valid(_gm_window):
			_gm_window.hide()
		if is_instance_valid(_player_window):
			_player_window.hide()

	for id in _nav_buttons:
		(_nav_buttons[id] as Button).disabled = id not in ["library", "workshop"] and not Store.is_open()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey

	if key.keycode == KEY_QUESTION or key.keycode == KEY_F1:
		open_shortcuts()
		get_viewport().set_input_as_handled()
		return

	if key.ctrl_pressed and key.keycode == KEY_K:
		open_search()
		get_viewport().set_input_as_handled()
		return

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
