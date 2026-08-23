extends Node

## Focused smoke test for the private GM window. This avoids the screenshot
## runner's renderer dependency and verifies the streaming privacy boundary.


func _ready() -> void:
	var app: Control = preload("res://scenes/app.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame

	var path := "user://test_gm_window.red"
	if not bool(CampaignContainer.save(path, CampaignFixtures.blackwall_sunrise()).get("ok", false)):
		_fail("could not create smoke-test campaign")
		return
	if not Store.open(path):
		_fail("could not open smoke-test campaign")
		return
	await get_tree().process_frame
	var city: Node = app.get("_screen")
	city.call("_open_hustle_dialog")
	await get_tree().process_frame
	var hustle_checks: Dictionary = city.get("_hustle_checks")
	if hustle_checks.size() < 2:
		_fail("multi-player Hustle selector did not list eligible PCs")
		return
	city.call("_toggle_all_hustlers", true)
	var selected_hustlers: Array = city.call("_selected_hustlers")
	if selected_hustlers.size() != hustle_checks.size():
		_fail("All eligible players did not select the full Hustle roster")
		return
	(city.get("_hustle_dialog") as ConfirmationDialog).hide()

	app.call("open_gm_notes_window")
	await get_tree().process_frame
	var window: Window = app.get("_gm_window")
	if window == null:
		_fail("GM window was not created")
		return
	if not window.force_native:
		_fail("GM window is not forced native")
		return
	if _supports_capture_exclusion() and not window.exclude_from_capture:
		_fail("GM window did not request OS capture exclusion")
		return
	if window.is_embedded():
		_fail("GM window is embedded in the main viewport")
		return
	if not window.visible:
		_fail("GM window did not become visible")
		return

	window.close_requested.emit()
	await get_tree().process_frame
	if window.visible:
		_fail("closing the GM window did not hide it")
		return

	if not await _check_player_display(app):
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("App smoke passed: multi-player Hustles, private GM window, player display")
	get_tree().quit(0)


## The other native window, and the opposite privacy requirement: this one is
## meant to be seen, and captured, so it must not ask to be excluded.
func _check_player_display(app: Control) -> bool:
	app.call("toggle_player_display")
	await get_tree().process_frame
	var window: Window = app.get("_player_window")
	if window == null:
		_fail("player display window was not created")
		return false
	if not window.force_native or window.is_embedded():
		_fail("player display is not a separate native window")
		return false
	if window.exclude_from_capture:
		_fail("player display asked for capture exclusion; it is meant to be shown")
		return false
	if not window.visible:
		_fail("player display did not become visible")
		return false

	app.call("_show", "location")
	await get_tree().process_frame
	var location: Node = app.get("_screen")
	var units: Array = Store.active_location().get("units", [])
	if units.is_empty():
		_fail("the seeded location has no units to publish")
		return false
	var hidden_id := String((units[0] as Dictionary)["id"])
	location.call("set_unit_hidden", hidden_id, true)
	await get_tree().process_frame

	var payload: Dictionary = Store.player_view()
	if payload.is_empty():
		_fail("the location screen published nothing to the player display")
		return false
	for unit in payload.get("units", []):
		if String((unit as Dictionary)["id"]) == hidden_id:
			_fail("a unit hidden from players still reached the player display")
			return false
	location.call("set_unit_hidden", hidden_id, false)

	app.call("toggle_player_display")
	await get_tree().process_frame
	if window.visible:
		_fail("toggling the player display again did not hide it")
		return false
	return true


## Whether this platform can honour a request not to be captured.
##
## Windows and macOS can; X11 and Wayland have no equivalent, which the README
## already says. Asserting it everywhere makes the suite red on the one platform
## where the answer is "the OS cannot", which teaches nobody anything.
static func _supports_capture_exclusion() -> bool:
	return OS.get_name() in ["Windows", "macOS"]


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
