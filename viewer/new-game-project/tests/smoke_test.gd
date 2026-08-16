extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
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

	var tokens: Dictionary = scene.get("tokens")
	var solo := tokens["solo"] as CombatToken
	var goon := tokens["goon"] as CombatToken
	var cover := CoverDetector.classify(scene.get_world_3d(), solo, goon)
	assert(cover.has("classification"), "Cover raycast did not return a classification")
	assert(not solo.actor_state.is_empty(), "Encounter snapshot did not populate token state")

	scene.call("_resolve_attack", goon)
	await _wait_for_api(scene)
	var weapon: Dictionary = solo.actor_state["weapons"]["Heavy Pistol"]
	assert(int(weapon["ammo"]) == 7, "Resolved attack did not spend ammo through the API")

	var api := scene.get("api") as GMApiClient
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
