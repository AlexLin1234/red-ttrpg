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

	for pair in [["city", "1b-city"], ["location", "1c-location"], ["forge", "1d-forge"]]:
		app.call("_show", String(pair[0]))
		await _settle(30)
		await _shoot(String(pair[1]))

	if _errors.is_empty():
		print("\nall screens rendered to %s" % ProjectSettings.globalize_path(OUT_DIR))
		get_tree().quit(0)
	else:
		print("\nPROBLEMS:")
		for error in _errors:
			print(" - " + error)
		get_tree().quit(1)


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
