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
	await _drive_sessions(app)

	app.call("_show", "city")
	await _settle(30)
	await _shoot("1b-city")
	await _drive_city(app)

	var opening := Store.add_beat()
	opening["title"] = "The client lies"
	opening["status"] = "active"
	Store.move_beat(String(opening["id"]), Vector2(80, 90))
	var ambush := Store.add_beat()
	ambush["title"] = "Container-yard ambush"
	Store.move_beat(String(ambush["id"]), Vector2(390, 220))
	var fallout := Store.add_beat()
	fallout["title"] = "Choose who gets the evidence"
	Store.move_beat(String(fallout["id"]), Vector2(700, 90))
	Store.connect_beats(String(opening["id"]), String(ambush["id"]))
	Store.connect_beats(String(ambush["id"]), String(fallout["id"]))
	app.call("open_gm_notes_window")
	await _settle(30)
	var gm_window: Window = app.get("_gm_window")
	if gm_window == null:
		_errors.append("GM Notes / Beats did not open a separate window")
	else:
		if not gm_window.force_native:
			_errors.append("GM Notes / Beats window was not forced native")
		if not gm_window.exclude_from_capture:
			_errors.append("GM Notes / Beats did not request capture exclusion")
		if gm_window.is_embedded():
			_errors.append("GM Notes / Beats was still embedded in the streamed viewport")
		gm_window.hide()

	app.call("_show", "location")
	await _settle(30)
	await _shoot("1c-location")
	await _drive_combat(app)

	app.call("_show", "netrun")
	await _settle(30)
	await _drive_netrun(app)

	app.call("_show", "vehicles")
	await _settle(30)
	await _drive_chase(app)

	await _drive_search(app)

	app.call("_show", "forge")
	await _settle(30)
	await _shoot("1d-forge")

	# The markets render arbitrary catalog text, which is exactly where a row can
	# grow wider than the viewport, so both are drawn. The Night Market needs a
	# Fixer of Operator Rank 5 to have any stock at all.
	app.call("_show", "market")
	await _settle(30)
	await _shoot("1e-market")

	var shopper := Store.active_character()
	if shopper.is_empty():
		_errors.append("no active character to shop with")
	else:
		CharacterRules.select_role(shopper, "fixer")
		(shopper["role_ability"] as Dictionary)["rank"] = 7
		shopper["cash"] = 25000
	app.call("_show", "night_market")
	await _settle(30)
	await _shoot("1f-night-market")

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

	await _drive_backdrop(screen)
	await _drive_reshape(screen)
	await _drive_pins(app, screen)

	# _drive_pins navigates away and back, which frees the old screen node.
	screen = app.get("_screen")
	if screen != null and screen.has_method("set_tab"):
		screen.call("set_tab", "map")
	await _settle(10)
	await _drive_downtime(screen)


## The other things a week off is for, one of which actually heals somebody.
func _drive_downtime(screen: Node) -> void:
	if screen == null or not screen.has_method("open_downtime_dialog"):
		_errors.append("city screen did not expose the downtime path")
		return
	screen.call("open_downtime_dialog", "recover")
	await _settle(14)
	await _shoot("1b-downtime")

	var dialog: Node = screen.get("_downtime_dialog")
	if dialog == null:
		_errors.append("the downtime dialog was not built")
		return
	var patient := Store.active_character()
	var before := int(patient.get("hp", 0))
	var result: Dictionary = dialog.call("perform")
	await _settle(10)
	if not bool(result.get("ok", false)):
		_errors.append("downtime failed: %s" % String(result.get("error", "")))
	elif int(patient.get("hp", 0)) <= before and before < int(patient.get("max_hp", 1)):
		_errors.append("resting did not restore any HP")
	dialog.call("hide")
	await _settle(6)


## An uploaded map goes behind the plates, not instead of them, so this checks a
## real image loads and the zones still draw over it.
func _drive_backdrop(screen: Node) -> void:
	var source := Image.create(640, 448, false, Image.FORMAT_RGBA8)
	source.fill(Color("1d2b1f"))
	for x in range(0, 640, 32):
		for y in 448:
			source.set_pixel(x, y, Color("3f6b4a"))
	var path := ProjectSettings.globalize_path("user://backdrop.png")
	if source.save_png(path) != OK:
		_errors.append("could not write the test backdrop")
		return

	screen.call("set_tab", "map")
	screen.call("_on_map_selected", path)
	await _settle(14)
	var gm_map: Dictionary = Store.campaign.get("gm_map", {})
	if not gm_map.has("png_base64"):
		_errors.append("uploading a map did not store it in the campaign")
	if (screen.call("area_ids") as PackedStringArray).is_empty():
		_errors.append("the backdrop replaced the zones instead of sitting behind them")
	await _shoot("1b-backdrop")

	# Clear it again so the remaining shots show the built-in diagram.
	Store.campaign["gm_map"] = {}
	screen.call("_refresh")
	await _settle(10)
	DirAccess.remove_absolute(path)


## Reshaping is the other half of editing a zone: not just what it says, but
## where it sits. Drag a corner, slide the plate, and check the outline moved.
func _drive_reshape(screen: Node) -> void:
	if not screen.has_method("start_reshape"):
		_errors.append("city screen did not expose the reshape path")
		return

	screen.call("start_reshape", "pacifica")
	await _settle(10)
	await _shoot("1b-reshape")

	var corners: int = screen.call("reshape_corner_count")
	if corners < 3:
		_errors.append("pacifica should have at least three corners, has %d" % corners)
		return

	var before: PackedVector2Array = NightCity.points_of(Store.area_by_id("pacifica"))
	screen.call("drag_corner", 1, Vector2(910, 330))
	await _settle(8)
	var after: PackedVector2Array = NightCity.points_of(Store.area_by_id("pacifica"))
	if after[1] == before[1]:
		_errors.append("dragging a corner did not move it")
	await _shoot("1b-reshape-dragged")

	var label_before := NightCity.label_of(Store.area_by_id("pacifica"))
	screen.call("nudge_zone", Vector2(0, -30))
	await _settle(8)
	var label_after := NightCity.label_of(Store.area_by_id("pacifica"))
	if label_after == label_before:
		_errors.append("moving the zone did not carry its label")

	screen.call("finish_reshape")
	await _settle(10)
	await _shoot("1b-reshaped")


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
	await _drive_condition(screen)
	await _drive_player_display(app, screen)
	await _drive_spawn(screen)
	await _drive_screen_cache(app)


## The fight has to survive the GM looking something up.
##
## This is the whole point of keeping screens alive between visits, so it is
## checked rather than assumed: leave mid-encounter, come back, and the round
## number and the initiative order are still the ones that were rolled.
func _drive_screen_cache(app: Control) -> void:
	var before: Node = app.get("_screen")
	var round_before: int = int((before.get("_snapshot") as Dictionary).get("round", 0))
	if round_before <= 0:
		_errors.append("expected an encounter in progress before leaving the screen")
		return

	app.call("_show", "market")
	await _settle(12)
	app.call("_show", "location")
	await _settle(12)

	var after: Node = app.get("_screen")
	if after != before:
		_errors.append("the location screen was rebuilt rather than kept")
		return
	var snapshot: Dictionary = after.get("_snapshot")
	if int(snapshot.get("round", 0)) != round_before:
		_errors.append(
			"the fight did not survive the trip: round %d became %d"
			% [round_before, int(snapshot.get("round", 0))]
		)
	if (snapshot.get("initiative", []) as Array).is_empty():
		_errors.append("the initiative order did not survive the trip")


## An ambush arrives as one click rather than a dozen trips to the Forge.
func _drive_spawn(screen: Node) -> void:
	if not screen.has_method("spawn_squad"):
		_errors.append("location screen did not expose the squad spawner")
		return
	var before: int = (screen.call("unit_ids") as PackedStringArray).size()
	var placed: Array = screen.call("spawn_squad", "corp_security", 3)
	await _settle(14)
	if placed.size() != 3:
		_errors.append("spawning three placed %d" % placed.size())
	var after: int = (screen.call("unit_ids") as PackedStringArray).size()
	if after != before + placed.size():
		_errors.append("the squad did not reach the board (%d -> %d)" % [before, after])
	var cells := {}
	for unit in Store.active_location().get("units", []):
		var entry: Dictionary = unit
		var key := "%d,%d,%d" % [int(entry["x"]), int(entry["z"]), int(entry.get("layer", 0))]
		if cells.has(key):
			_errors.append("two units were spawned onto the same cell")
		cells[key] = true
	await _shoot("1c-squad")


## The condition rail: whoever came out of that exchange worst, and the buttons
## the GM reaches for when they are on the floor.
func _drive_condition(screen: Node) -> void:
	var snapshot: Dictionary = screen.get("_snapshot")
	var worst := ""
	var worst_ratio := INF
	for actor in snapshot.get("actors", []):
		var entry: Dictionary = actor
		var ratio := float(entry["hp"]) / maxf(1.0, float(entry["max_hp"]))
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst = String(entry["id"])
	if worst == "":
		_errors.append("no actors to read a condition off")
		return
	screen.call("select_unit", worst)
	await _settle(10)
	await _shoot("1c-condition")


## The table's own screen, captured from the window itself rather than the main
## viewport — which is the whole point of it being a separate window.
func _drive_player_display(app: Control, screen: Node) -> void:
	# Something on the board the players are not meant to know about yet.
	var ids: PackedStringArray = screen.call("unit_ids")
	if not ids.is_empty():
		screen.call("set_unit_hidden", ids[ids.size() - 1], true)
	await _settle(6)

	app.call("toggle_player_display")
	await _settle(30)
	var window: Window = app.get("_player_window")
	if window == null:
		_errors.append("the player display did not open")
		return
	if window.exclude_from_capture:
		_errors.append("the player display asked to be excluded from capture")
	var payload: Dictionary = Store.player_view()
	if payload.is_empty():
		_errors.append("the location screen published nothing to the player display")
	elif int(payload.get("units", []).size()) >= ids.size():
		_errors.append("the hidden unit still reached the player display")
	await _shoot_window("1c-player-display", window)
	window.hide()
	if not ids.is_empty():
		screen.call("set_unit_hidden", ids[ids.size() - 1], false)
	await _settle(6)


## Roll an architecture and walk the first two floors of it, which is the whole
## loop: a door, then whatever was waiting behind it.
func _drive_netrun(app: Control) -> void:
	var screen: Node = app.get("_screen")
	if screen == null or not screen.has_method("jack_in"):
		_errors.append("netrun screen did not expose the run path")
		return

	screen.call("generate_architecture", "standard")
	await _settle(12)
	if Store.architectures().is_empty():
		_errors.append("rolling an architecture did not add one to the campaign")
		return
	await _shoot("1g-architecture")

	var netrunner := ""
	for character in Store.characters():
		if String((character as Dictionary).get("role", "")).to_lower() == "netrunner":
			netrunner = String((character as Dictionary)["id"])
	if netrunner == "":
		_errors.append("the demo campaign has no Netrunner to run with")
		return

	screen.call("jack_in", netrunner, 6)
	await _settle(12)
	screen.call("perform", "pathfinder", "")
	await _settle(8)
	screen.call("perform", "move", "")
	await _settle(8)
	screen.call("perform", "backdoor", "")
	await _settle(12)
	await _shoot("1g-netrun")

	var snapshot: Dictionary = screen.get("_snapshot")
	if snapshot.is_empty():
		_errors.append("the run produced no snapshot")
		return
	var runner: Dictionary = snapshot["runner"]
	if int(runner["level"]) != 1:
		_errors.append("the runner did not reach the first floor")
	if int(runner["actions_left"]) != 3:
		_errors.append(
			"three NET Actions should have been spent, %d left of 6" % int(runner["actions_left"])
		)


## Two cars, one road: add them, start the chase, and run an exchange.
func _drive_chase(app: Control) -> void:
	var screen: Node = app.get("_screen")
	if screen == null or not screen.has_method("start_chase"):
		_errors.append("garage screen did not expose the chase path")
		return

	screen.call("add_vehicle", "muscle")
	screen.call("add_vehicle", "bike")
	await _settle(12)
	if Store.vehicles().size() < 2:
		_errors.append("adding vehicles did not put them in the campaign")
		return
	await _shoot("1h-garage")

	screen.call("start_chase")
	await _settle(12)
	screen.call("exchange", "push", "shortcut")
	await _settle(12)
	await _shoot("1h-chase")

	var snapshot: Dictionary = screen.get("_snapshot")
	if snapshot.is_empty():
		_errors.append("the chase produced no snapshot")
		return
	if int(snapshot["round"]) != 2:
		_errors.append("the exchange did not advance the round")
	# A vehicle placed on a board is cover, so the garage has to reach the
	# Location screen's palette as well as this one.
	var palette_has_vehicle := false
	for cover in Store.cover_palette():
		if String((cover as Dictionary)["material"]) == "Vehicle Hulk" and String(
			(cover as Dictionary)["id"]
		).begins_with("vehicle-"):
			palette_has_vehicle = true
	if not palette_has_vehicle:
		_errors.append("a garaged vehicle did not reach the cover palette")


## One field over the whole campaign, and the trip it takes you on.
func _drive_search(app: Control) -> void:
	if not app.has_method("open_search"):
		_errors.append("the app did not expose the campaign search")
		return
	app.call("open_search")
	await _settle(10)
	var palette: Node = app.get("_search")
	if palette == null or not bool(palette.get("visible")):
		_errors.append("the search palette did not open")
		return
	var rows: Array = palette.call("search", "tallow")
	await _settle(10)
	if rows.is_empty():
		_errors.append("searching for a character in the demo campaign found nothing")
		return
	await _shoot("1i-search")

	palette.call("accept")
	await _settle(14)
	if bool(palette.get("visible")):
		_errors.append("taking a result did not close the palette")
	var first: Dictionary = rows[0]
	var landed := String(app.get("_current"))
	if landed != String(first["screen"]):
		_errors.append(
			"the result said %s and the app went to %s" % [String(first["screen"]), landed]
		)
	var target: Dictionary = first["target"]
	if target.has("character_id") and Store.active_character_id != String(target["character_id"]):
		_errors.append("the search landed on the wrong sheet")


## Framing the evening, and the copy taken on the way in.
func _drive_sessions(app: Control) -> void:
	app.call("_show", "library")
	await _settle(20)
	var screen: Node = app.get("_screen")
	if screen == null or not screen.has_method("open_snapshots"):
		_errors.append("library screen did not expose the snapshots path")
		return

	var before: int = Store.restore_points().size()
	var session := Store.start_session()
	await _settle(12)
	if session <= 0:
		_errors.append("starting a session did not count one")
	if Store.restore_points().size() != before + 1:
		_errors.append("starting a session did not take a restore point")
	if not Store.log_line("The client lied about the courier."):
		_errors.append("a hand-written log line was refused")
	screen.call("_refresh")
	await _settle(12)
	await _shoot("1a-session")

	screen.call("open_snapshots")
	await _settle(14)
	await _shoot("1a-snapshots")

	var newest: Dictionary = Store.restore_points()[0]
	if not Store.restore_to(String(newest["id"])):
		_errors.append("restoring the newest point failed")
	await _settle(14)
	if Store.restore_points().size() < before + 1:
		_errors.append("restoring threw away the list of restore points")
	var dialog: Node = screen.get("_snapshots_dialog")
	if dialog != null:
		dialog.call("hide")
	await _settle(8)


func _settle(frames: int) -> void:
	for index in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shoot(shot_name: String) -> void:
	await _save_shot(shot_name, get_viewport())


## A separate native window is its own Viewport, so it is captured from itself
## rather than from the main one, which does not contain it.
func _shoot_window(shot_name: String, window: Window) -> void:
	await _save_shot(shot_name, window)


func _save_shot(shot_name: String, viewport: Viewport) -> void:
	var image := viewport.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	if image.save_png(path) != OK:
		_errors.append("could not write %s" % path)
		return
	print("shot %s (%d×%d)" % [shot_name, image.get_width(), image.get_height()])
