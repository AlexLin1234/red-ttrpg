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
	if not window.exclude_from_capture:
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

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("App smoke passed: multi-player Hustles and private native GM window")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
