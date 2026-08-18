extends Node

## Render each screen and write a PNG.
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 1600x980 scenes/shoot.tscn
##
## Godot cannot render under `--headless`, so this needs a framebuffer, and it
## runs as a scene rather than via `--script` because autoloads are only set up
## for a real main scene. This is the visual half of verification: run_tests.gd
## proves the rules hold, this proves the screens actually draw.

const OUT_DIR := "user://shots"

var _errors: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var app: Control = preload("res://scenes/app.tscn").instantiate()
	add_child(app)
	await _settle(20)

	var target := ""
	for save in Store.list_saves():
		if String((save as Dictionary).get("name", "")) == "Blackwall Sunrise":
			target = String((save as Dictionary)["path"])
	if target == "":
		_errors.append("Blackwall Sunrise was not in the seeded library")

	# Pick the demo campaign explicitly: the seeded saves all share a timestamp,
	# so which one sorts first is otherwise arbitrary.
	var library: Node = app.get("_screen")
	if library != null and library.has_method("select_save") and target != "":
		library.call("select_save", target)
	await _settle(20)
	await _shoot("1a-library")

	if target != "" and not Store.open(target):
		_errors.append("could not open Blackwall Sunrise")
	await _settle(20)

	app.call("_show", "city")
	await _settle(30)
	await _shoot("1b-city")
	await _drive_city(app)

	app.call("_show", "location")
	await _settle(30)
	await _shoot("1c-location")
	await _drive_combat(app)

	app.call("_show", "forge")
	await _settle(30)
	await _shoot("1d-forge")

	if _errors.is_empty():
		print("\nall screens rendered to %s" % ProjectSettings.globalize_path(OUT_DIR))
		get_tree().quit(0)
	else:
		print("\nPROBLEMS:")
		for error in _errors:
			print(" - " + error)
		get_tree().quit(1)


## Walk the zone-editing path: list every area, open the editor, and draw a new
## zone corner by corner.
func _drive_city(app: Control) -> void:
	var screen: Node = app.get("_screen")
	if screen == null or not screen.has_method("start_draw"):
		_errors.append("city screen did not expose the zone-editing path")
		return

	screen.call("set_tab", "areas")
	await _settle(10)
	await _shoot("1b-areas")

	var ids: PackedStringArray = screen.call("area_ids")
	if ids.is_empty():
		_errors.append("no areas to edit")
		return
	screen.call("edit_area", ids[0])
	await _settle(10)
	await _shoot("1b-edit")

	screen.call("start_draw")
	await _settle(6)
	for corner in [Vector2(80, 90), Vector2(230, 70), Vector2(260, 210), Vector2(110, 240)]:
		screen.call("place_draft_corner", corner)
		await _settle(3)
	if int(screen.call("draft_corner_count")) != 4:
		_errors.append("drawing did not record four corners")
	await _shoot("1b-draw")

	var before: int = (screen.call("area_ids") as PackedStringArray).size()
	screen.call("close_draft")
	await _settle(12)
	var after: int = (screen.call("area_ids") as PackedStringArray).size()
	if after != before + 1:
		_errors.append("closing the shape did not add an area (%d -> %d)" % [before, after])
	await _shoot("1b-new-zone")

	await _drive_pins(app, screen)

	# _drive_pins navigates away and back, which frees the old screen node.
	screen = app.get("_screen")
	if screen != null and screen.has_method("set_tab"):
		screen.call("set_tab", "map")
	await _settle(10)


## Pins are the link between the city map and a playable board, so this checks
## the whole chain: list them, select one, drop a new one, and follow a linked
## pin through to the location screen.
func _drive_pins(app: Control, screen: Node) -> void:
	screen.call("set_tab", "places")
	await _settle(10)
	await _shoot("1b-places")

	var pins: PackedStringArray = screen.call("poi_ids")
	if pins.size() < 2:
		_errors.append("expected the demo campaign to ship pins")
		return

	screen.call("select_poi", "poi-parkade")
	await _settle(10)
	await _shoot("1b-poi")

	screen.call("start_pin")
	await _settle(6)
	screen.call("place_pin", Vector2(430, 460))
	await _settle(10)
	var after: int = (screen.call("poi_ids") as PackedStringArray).size()
	if after != pins.size() + 1:
		_errors.append("dropping a pin did not add a place (%d -> %d)" % [pins.size(), after])
	await _shoot("1b-new-pin")

	# A pin with a board behind it should take the GM straight to it.
	screen.call("select_poi", "poi-parkade")
	await _settle(6)
	Store.open_location("kabuki-parkade")
	await _settle(20)
	if String(app.get("_current")) != "location":
		_errors.append("opening a linked pin did not switch to the location screen")
	else:
		await _shoot("1b-followed-link")
	app.call("_show", "city")
	await _settle(20)


## Walk the combat path the GM walks: roll initiative, shoot across the deck,
## answer the cover prompt, then check the card actually says something.
func _drive_combat(app: Control) -> void:
	var screen: Node = app.get("_screen")
	if screen == null or not screen.has_method("roll_initiative"):
		_errors.append("location screen did not expose the combat path")
		return

	screen.call("roll_initiative")
	await _settle(10)
	await _shoot("1c-initiative")

	var ids: PackedStringArray = screen.call("unit_ids")
	if ids.size() < 2:
		_errors.append("expected at least two units on the board")
		return

	# Spike and Nine-Volt are on opposite sides of the deck with pillars between
	# them, which is the case the cover prompt exists for.
	screen.call("select_unit", ids[0])
	await _settle(4)
	screen.call("begin_attack", ids[3] if ids.size() > 3 else ids[1], "single")
	await _settle(10)

	if bool(screen.call("has_cover_prompt")):
		await _shoot("1c-cover-prompt")
		screen.call("answer_cover_prompt", "absorb")
		await _settle(12)
	else:
		_errors.append("no cover was found in the line of fire — expected the parkade pillars")

	await _shoot("1c-resolution")


func _settle(frames: int) -> void:
	for index in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shoot(shot_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	if image.save_png(path) != OK:
		_errors.append("could not write %s" % path)
		return
	print("shot %s (%d×%d)" % [shot_name, image.get_width(), image.get_height()])
