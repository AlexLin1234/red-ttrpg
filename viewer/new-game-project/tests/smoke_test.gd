extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await _wait_for_api(scene)
	var api := scene.get("api") as GMApiClient
	api.reset_session(scene.call("_initial_session_state"))
	await _wait_for_api(scene)
	await physics_frame
	await process_frame

	var grid := scene.get_node("AlleyGrid") as GridMap
	var token_layer := scene.get_node("Tokens") as Node3D
	var cover_layer := scene.get_node("Cover") as Node3D
	assert(grid.get_used_cells().size() == 400, "Expected a 20x20 GridMap alley")
	assert(token_layer.get_child_count() == 3, "Expected three demo tokens")
	assert(cover_layer.get_child_count() >= 10, "Expected modular cover and alley walls")
	var action_buttons: Dictionary = scene.get("action_buttons")
	assert(action_buttons.size() == 7, "Expected exactly seven v1 actions")
	assert(scene.get("selected_token") != null, "Expected a selected token")
	var map_overlay := scene.get("map_overlay") as PanelContainer
	assert(map_overlay.visible, "Night City map overlay should start visible")
	scene.call("_toggle_map")
	assert(not map_overlay.visible, "Night City map overlay did not hide")
	scene.call("_toggle_map")
	var zone_canvas := scene.get("map_zone_canvas") as Control
	zone_canvas.call("set_zones", [])
	zone_canvas.set("drawing", true)
	var draft_points: Array[Vector2] = [
		Vector2(0.1, 0.1), Vector2(0.7, 0.15), Vector2(0.45, 0.75)
	]
	zone_canvas.set("draft_points", draft_points)
	zone_canvas.call("_finish_zone")
	await _wait_for_api(scene)
	assert(zone_canvas.get("zones").size() == 1, "Drawn map zone was not saved")
	zone_canvas.call("clear_zones")
	await _wait_for_api(scene)
	assert(zone_canvas.get("zones").is_empty(), "Map zones did not clear")

	var tokens: Dictionary = scene.get("tokens")
	var solo := tokens["solo"] as CombatToken
	var goon := tokens["goon"] as CombatToken
	scene.call("_select_token", solo)
	var cover := CoverDetector.classify(scene.get_world_3d(), solo, goon)
	assert(cover.has("classification"), "Cover raycast did not return a classification")
	assert(not solo.actor_state.is_empty(), "Encounter snapshot did not populate token state")

	scene.call("_resolve_attack", goon)
	await _wait_for_api(scene)
	var weapon: Dictionary = solo.actor_state["weapons"]["Heavy Pistol"]
	assert(int(weapon["ammo"]) == 7, "Resolved attack did not spend ammo through the API")

	api.undo()
	await _wait_for_api(scene)
	assert(
		int(solo.actor_state["weapons"]["Heavy Pistol"]["ammo"]) == 8,
		"Undo did not restore ammo",
	)
	api.redo()
	await _wait_for_api(scene)
	assert(
		int(solo.actor_state["weapons"]["Heavy Pistol"]["ammo"]) == 7,
		"Redo did not spend ammo again",
	)

	scene.call("_on_action_pressed", "Aimed")
	scene.call("_resolve_attack", goon)
	await _wait_for_api(scene)
	assert(
		int(solo.actor_state["weapons"]["Heavy Pistol"]["ammo"]) == 6,
		"Aimed shot did not resolve",
	)

	scene.call("_select_token", goon)
	scene.call("_on_action_pressed", "Autofire")
	scene.call("_resolve_attack", solo)
	await _wait_for_api(scene)
	assert(
		int(goon.actor_state["weapons"]["SMG"]["ammo"]) == 20, "Autofire did not spend ten rounds"
	)
	scene.call("_on_action_pressed", "Reload")
	await _wait_for_api(scene)
	assert(int(goon.actor_state["weapons"]["SMG"]["ammo"]) == 30, "Reload did not refill the SMG")

	scene.call("_on_action_pressed", "Move")
	assert(scene.get("current_action") == "Move", "Move action did not activate")
	scene.call("_on_action_pressed", "Take Cover")
	assert(scene.get("current_action") == "Take Cover", "Take Cover action did not activate")
	scene.call("_on_action_pressed", "Dodge")
	var evading: Dictionary = scene.get("evading")
	assert(bool(evading.get("goon", false)), "Dodge did not toggle evasion")

	api.close_month()
	await _wait_for_api(scene)
	var calendar: Dictionary = scene.get("session_state").get("calendar", {})
	assert(calendar.get("current_month") == "2045-02", "Month end did not advance the calendar")
	assert(int(solo.actor_state["cash"]) == 3500, "Fresh Food Lifestyle was not auto-paid")
	assert(
		str(tokens["lookout"].actor_state["lifestyle_status"]) == "unpaid",
		"Unaffordable Lifestyle was not marked unpaid",
	)
	api.undo()
	await _wait_for_api(scene)
	assert(int(solo.actor_state["cash"]) == 5000, "Undo did not restore Lifestyle cash")
	api.redo()
	await _wait_for_api(scene)
	assert(int(solo.actor_state["cash"]) == 3500, "Redo did not reapply Lifestyle cash")

	(
		api
		. reset_session(
			{
				"actors":
				{
					"custom_actor":
					{
						"name": "Custom Operator",
						"max_hp": 35,
						"attack_base": 12,
						"weapons":
						{
							"Heavy Pistol":
							{
								"ammo": 8,
								"weapon_type": "pistol",
								"damage_dice": 3,
								"magazine": 8,
							}
						},
					}
				},
			}
		)
	)
	await _wait_for_api(scene)
	await process_frame
	var dynamic_tokens: Dictionary = scene.get("tokens")
	assert(dynamic_tokens.size() == 1, "Dynamic roster did not remove stale demo tokens")
	assert(dynamic_tokens.has("custom_actor"), "Dynamic roster did not create the loaded actor")

	print(
		(
			"VIEWER_SMOKE_OK cells=%d tokens=%d cover_nodes=%d cover=%s"
			% [
				grid.get_used_cells().size(),
				3,
				cover_layer.get_child_count(),
				cover["classification"],
			]
		)
	)
	quit(0)


func _wait_for_api(scene: Node) -> void:
	var api := scene.get("api") as GMApiClient
	for _frame in range(180):
		await process_frame
		if not api.is_busy():
			return
	assert(false, "Timed out waiting for the local encounter API")
