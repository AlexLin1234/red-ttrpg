extends Node3D

const TOKEN_SCENE := preload("res://scenes/token.tscn")
const CARD_SCENE := preload("res://scenes/resolution_card.tscn")
const INSPECTOR_SCENE := preload("res://scenes/inspector_panel.tscn")
const DAMAGE_FLOAT_SCENE := preload("res://scenes/damage_float.tscn")
const GUNSHOT_SCENE := preload("res://scenes/gunshot_vfx.tscn")
const SOLO_PORTRAIT := preload("res://assets/token_solo.svg")
const GOON_PORTRAIT := preload("res://assets/token_goon.svg")

const TILE_METERS := 2.0
const BOARD_HALF_SIZE := 10
const ATTACK_ACTIONS := ["Fire", "Aimed", "Autofire"]

var hud: Control
var inspector: TokenInspector
var resolution_card: ResolutionCard
var service_status: Label
var instruction_label: Label
var action_buttons: Dictionary = {}

var session_state: Dictionary = {}
var tokens: Dictionary = {}
var selected_token: CombatToken
var current_action := "Fire"
var dragging_token: CombatToken
var dragging_cover: CoverBody
var dragging_cover_height := 0.0
var evading: Dictionary = {}
var cover_for_target: Dictionary = {}
var cover_by_id: Dictionary = {}
var pending_shot: Dictionary = {}

@onready var camera: Camera3D = %Camera
@onready var grid: GridMap = %AlleyGrid
@onready var token_layer: Node3D = %Tokens
@onready var cover_layer: Node3D = %Cover
@onready var effects_layer: Node3D = %Effects
@onready var api: GMApiClient = %ApiClient


func _ready() -> void:
	camera.look_at(Vector3.ZERO, Vector3.UP)
	_build_board()
	_build_hud()
	_spawn_demo_tokens()
	api.request_succeeded.connect(_on_api_success)
	api.request_failed.connect(_on_api_failure)
	_select_token(tokens["solo"])
	service_status.text = "CONNECTING TO RULES SERVICE…"
	api.fetch_session()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("redo", true):
		api.redo()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("undo", true):
		api.undo()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_WHEEL_UP
		and event.pressed
	):
		camera.size = maxf(12.0, camera.size - 1.5)
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		and event.pressed
	):
		camera.size = minf(42.0, camera.size + 1.5)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_board_press(event.position, event.shift_pressed)
		else:
			dragging_token = null
			dragging_cover = null
		return
	if event is InputEventMouseMotion and dragging_token:
		_move_dragged_token(event.position)
	elif event is InputEventMouseMotion and dragging_cover:
		_move_dragged_cover(event.position)


func _build_board() -> void:
	var library := MeshLibrary.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(1.48, 0.08, 1.48)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("101827")
	floor_material.metallic = 0.45
	floor_material.roughness = 0.68
	floor_material.emission_enabled = true
	floor_material.emission = Color("071222")
	floor_mesh.material = floor_material
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(1.48, 0.08, 1.48)
	library.create_item(0)
	library.set_item_name(0, "Street Tile")
	library.set_item_mesh(0, floor_mesh)
	library.set_item_shapes(0, [floor_shape, Transform3D.IDENTITY])
	grid.mesh_library = library
	grid.cell_size = Vector3(1.5, 0.2, 1.5)
	for x in range(-BOARD_HALF_SIZE, BOARD_HALF_SIZE):
		for z in range(-BOARD_HALF_SIZE, BOARD_HALF_SIZE):
			grid.set_cell_item(Vector3i(x, 0, z), 0)

	# The built-in blockout is deliberately modular: these nodes can be replaced
	# with matching pieces from a licensed MeshLibrary without touching gameplay.
	for x in range(-9, 10, 3):
		_spawn_cover(
			Vector3(x * 1.5, 1.5, -14.2),
			Vector3(4.35, 3.0, 0.45),
			Color("15233c"),
			"concrete",
			30,
			"NorthWall"
		)
		_spawn_cover(
			Vector3(x * 1.5, 1.5, 14.2),
			Vector3(4.35, 3.0, 0.45),
			Color("24142d"),
			"concrete",
			30,
			"SouthWall"
		)
	_spawn_cover(
		Vector3(-3.2, 0.65, 0.3),
		Vector3(2.7, 1.3, 0.8),
		Color("284965"),
		"steel",
		25,
		"BlueBarrier"
	)
	_spawn_cover(
		Vector3(3.1, 0.55, -1.2), Vector3(2.3, 1.1, 0.8), Color("6a252d"), "steel", 25, "RedBarrier"
	)
	_spawn_cover(
		Vector3(0.2, 1.1, 4.1),
		Vector3(0.75, 2.2, 3.0),
		Color("333c45"),
		"concrete",
		30,
		"ConcreteColumn"
	)
	_spawn_cover(
		Vector3(-6.2, 0.95, -3.8),
		Vector3(1.8, 1.9, 1.8),
		Color("6a431e"),
		"wood",
		15,
		"MarketCrate"
	)

	for light_data in [
		[Vector3(-9, 3.0, -5), Color("00dffc")],
		[Vector3(8, 3.0, -1), Color("ff2ca8")],
		[Vector3(-1, 3.0, 9), Color("ff6a24")],
	]:
		var light := OmniLight3D.new()
		light.position = light_data[0]
		light.light_color = light_data[1]
		light.light_energy = 4.2
		light.omni_range = 9.0
		light.shadow_enabled = true
		add_child(light)


func _spawn_cover(
	position_value: Vector3,
	size: Vector3,
	color: Color,
	material_name: String,
	hit_points: int,
	label: String,
) -> CoverBody:
	var cover := CoverBody.new()
	cover.name = label
	cover.position = position_value
	cover_layer.add_child(cover)
	cover.configure(size, color, material_name, hit_points)
	cover_by_id[cover.name] = cover
	cover.cover_changed.connect(_on_cover_changed)
	return cover


func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(hud)

	var brand := Label.new()
	brand.position = Vector2(28, 24)
	brand.text = "NIGHT//OPS\nREDLINE GM VIEW"
	brand.add_theme_font_size_override("font_size", 25)
	brand.add_theme_color_override("font_color", Color("00e5ff"))
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(brand)

	service_status = Label.new()
	service_status.position = Vector2(30, 104)
	service_status.add_theme_font_size_override("font_size", 17)
	service_status.add_theme_color_override("font_color", Color("ffe45c"))
	hud.add_child(service_status)

	resolution_card = CARD_SCENE.instantiate() as ResolutionCard
	hud.add_child(resolution_card)

	inspector = INSPECTOR_SCENE.instantiate() as TokenInspector
	hud.add_child(inspector)

	var action_panel := PanelContainer.new()
	action_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_panel.position = Vector2(-590, -116)
	action_panel.size = Vector2(1180, 86)
	action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var action_style := StyleBoxFlat.new()
	action_style.bg_color = Color(0.01, 0.016, 0.038, 0.96)
	action_style.border_color = Color("243b62")
	action_style.set_border_width_all(2)
	action_style.corner_radius_top_left = 15
	action_style.corner_radius_top_right = 15
	action_style.content_margin_left = 18
	action_style.content_margin_right = 18
	action_style.content_margin_top = 14
	action_style.content_margin_bottom = 14
	action_panel.add_theme_stylebox_override("panel", action_style)
	hud.add_child(action_panel)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	action_panel.add_child(actions)
	for action_name in ["Fire", "Aimed", "Autofire", "Reload", "Move", "Take Cover", "Dodge"]:
		var button := Button.new()
		button.text = action_name.to_upper()
		button.toggle_mode = action_name != "Reload"
		button.custom_minimum_size = Vector2(145, 54)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_action_pressed.bind(action_name))
		actions.add_child(button)
		action_buttons[action_name] = button

	instruction_label = Label.new()
	instruction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instruction_label.position = Vector2(-470, -154)
	instruction_label.size = Vector2(940, 30)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 19)
	instruction_label.add_theme_color_override("font_color", Color("dce9ff"))
	instruction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(instruction_label)
	_set_action("Fire")


func _spawn_demo_tokens() -> void:
	var solo := TOKEN_SCENE.instantiate() as CombatToken
	solo.configure("solo", "Rogue Signal", SOLO_PORTRAIT, Color("00e5ff"))
	solo.position = Vector3(-6.0, 0.12, 5.8)
	token_layer.add_child(solo)
	tokens[solo.token_id] = solo

	var goon := TOKEN_SCENE.instantiate() as CombatToken
	goon.configure("goon", "Booster", GOON_PORTRAIT, Color("ff5a1f"))
	goon.position = Vector3(6.0, 0.12, -5.2)
	token_layer.add_child(goon)
	tokens[goon.token_id] = goon

	var lookout := TOKEN_SCENE.instantiate() as CombatToken
	lookout.configure("lookout", "Lookout", GOON_PORTRAIT, Color("ffe45c"))
	lookout.position = Vector3(7.2, 0.12, 5.8)
	token_layer.add_child(lookout)
	tokens[lookout.token_id] = lookout


func _initial_session_state() -> Dictionary:
	return {
		"actors":
		{
			"solo":
			{
				"name": "Rogue Signal",
				"hp": 40,
				"max_hp": 40,
				"armor": {"body": 11, "head": 11},
				"cover_hp": 0,
				"wound_state": "ready",
				"attack_base": 14,
				"evasion_base": 12,
				"selected_weapon": "Heavy Pistol",
				"skills": {"Handgun": 14, "Evasion": 12, "Athletics": 11, "Perception": 13},
				"weapons":
				{
					"Heavy Pistol":
					{
						"ammo": 8,
						"magazine": 8,
						"weapon_type": "pistol",
						"damage_dice": 3,
						"rof": 2,
						"autofire_rating": null,
						"quality": "standard",
					}
				},
			},
			"goon":
			{
				"name": "Booster",
				"hp": 30,
				"max_hp": 30,
				"armor": {"body": 7, "head": 7},
				"cover_hp": 0,
				"wound_state": "ready",
				"attack_base": 11,
				"evasion_base": 10,
				"selected_weapon": "SMG",
				"skills": {"Handgun": 11, "Evasion": 10, "Athletics": 8, "Perception": 9},
				"weapons":
				{
					"SMG":
					{
						"ammo": 30,
						"magazine": 30,
						"weapon_type": "smg",
						"damage_dice": 2,
						"rof": 1,
						"autofire_rating": 3,
						"quality": "standard",
					}
				},
			},
			"lookout":
			{
				"name": "Lookout",
				"hp": 25,
				"max_hp": 25,
				"armor": {"body": 4, "head": 4},
				"cover_hp": 0,
				"wound_state": "ready",
				"attack_base": 10,
				"evasion_base": 9,
				"selected_weapon": "Medium Pistol",
				"skills": {"Handgun": 10, "Evasion": 9, "Athletics": 8, "Perception": 10},
				"weapons":
				{
					"Medium Pistol":
					{
						"ammo": 12,
						"magazine": 12,
						"weapon_type": "pistol",
						"damage_dice": 2,
						"rof": 2,
						"autofire_rating": null,
						"quality": "standard",
					}
				},
			},
		},
	}


func _handle_board_press(mouse_position: Vector2, shift_pressed := false) -> void:
	var hit := _raycast_mouse(mouse_position)
	if hit.is_empty():
		return
	var collider: Variant = hit.get("collider")
	if collider is CombatToken:
		var clicked := collider as CombatToken
		if current_action in ATTACK_ACTIONS and selected_token and clicked != selected_token:
			_resolve_attack(clicked)
		elif current_action in ["Move", "Take Cover"] and clicked == selected_token:
			dragging_token = clicked
		else:
			_select_token(clicked)
	elif collider is CoverBody and current_action == "Move" and shift_pressed:
		dragging_cover = collider as CoverBody
		dragging_cover_height = dragging_cover.global_position.y
		instruction_label.text = "ARRANGE SCENE • dragging %s" % dragging_cover.name


func _move_dragged_token(mouse_position: Vector2) -> void:
	var origin := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	var point: Variant = Plane(Vector3.UP, 0.12).intersects_ray(origin, direction)
	if point == null:
		return
	var position_value := point as Vector3
	position_value.x = clampf(snappedf(position_value.x, 0.75), -13.3, 13.3)
	position_value.z = clampf(snappedf(position_value.z, 0.75), -13.3, 13.3)
	dragging_token.global_position = position_value
	_refresh_inspector()


func _move_dragged_cover(mouse_position: Vector2) -> void:
	var origin := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	var point: Variant = Plane(Vector3.UP, dragging_cover_height).intersects_ray(origin, direction)
	if point == null:
		return
	var position_value := point as Vector3
	position_value.x = clampf(snappedf(position_value.x, 0.75), -13.3, 13.3)
	position_value.z = clampf(snappedf(position_value.z, 0.75), -13.3, 13.3)
	dragging_cover.global_position = position_value
	_refresh_inspector()


func _raycast_mouse(mouse_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(mouse_position)
	var end := origin + camera.project_ray_normal(mouse_position) * 200.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 3)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _select_token(token: CombatToken) -> void:
	if selected_token:
		selected_token.set_selected(false)
	selected_token = token
	selected_token.set_selected(true)
	var dodge_button := action_buttons.get("Dodge") as Button
	if dodge_button:
		dodge_button.button_pressed = bool(evading.get(selected_token.token_id, false))
		dodge_button.text = "DODGE ON" if dodge_button.button_pressed else "DODGE"
	_refresh_inspector()
	instruction_label.text = "%s selected • choose an action" % selected_token.display_name


func _set_action(action_name: String) -> void:
	current_action = action_name
	for name in action_buttons:
		if name not in ["Reload", "Dodge"]:
			action_buttons[name].button_pressed = name == action_name
	var instructions := {
		"Fire": "FIRE • click an opposing token",
		"Aimed": "AIMED SHOT • click an opposing token (head, -8)",
		"Autofire": "AUTOFIRE • click an opposing token (10 rounds)",
		"Move": "MOVE • drag tokens; Shift-drag cover props to arrange the alley",
		"Take Cover": "TAKE COVER • drag behind an obstacle; raycasts update live",
	}
	instruction_label.text = str(instructions.get(action_name, action_name.to_upper()))


func _on_action_pressed(action_name: String) -> void:
	if not selected_token:
		instruction_label.text = "Select a token first."
		return
	if action_name == "Reload":
		_reload_selected()
		return
	if action_name == "Dodge":
		var now_evading := not bool(evading.get(selected_token.token_id, false))
		evading[selected_token.token_id] = now_evading
		var dodge_button := action_buttons["Dodge"] as Button
		dodge_button.button_pressed = now_evading
		dodge_button.text = "DODGE ON" if now_evading else "DODGE"
		instruction_label.text = (
			"%s %s dodging." % [selected_token.display_name, "is now" if now_evading else "stopped"]
		)
		_refresh_inspector()
		return
	_set_action(action_name)


func _resolve_attack(target: CombatToken) -> void:
	if api.is_busy():
		instruction_label.text = "Rules service is busy."
		return
	var attacker_state: Dictionary = selected_token.actor_state
	var target_state: Dictionary = target.actor_state
	var weapon_name := str(attacker_state.get("selected_weapon", ""))
	var weapon: Dictionary = attacker_state.get("weapons", {}).get(weapon_name, {})
	if weapon.is_empty():
		instruction_label.text = "Selected token has no configured weapon."
		return
	if current_action == "Autofire" and weapon.get("autofire_rating") == null:
		instruction_label.text = "%s does not support Autofire." % weapon_name
		return
	var cover_info := CoverDetector.classify(get_world_3d(), selected_token, target)
	var cover: CoverBody = cover_info.get("cover") as CoverBody
	if cover:
		cover_for_target[target.token_id] = cover
	var mode := "single"
	var location := "body"
	if current_action == "Aimed":
		mode = "aimed"
		location = "head"
	elif current_action == "Autofire":
		mode = "autofire"
	var target_evades := bool(evading.get(target.token_id, false))
	var payload := {
		"attacker_id": selected_token.token_id,
		"target_id": target.token_id,
		"weapon": weapon_name,
		"distance_m":
		snappedf(
			selected_token.global_position.distance_to(target.global_position) * TILE_METERS, 0.1
		),
		"location": location,
		"mode": mode,
		"contested": target_evades,
		"modifiers": 0,
		"cover_hp": int(cover_info.get("hp", 0)),
		"cover_id": str(cover.name) if cover else null,
	}
	pending_shot = {
		"attacker": selected_token,
		"target": target,
		"cover": cover,
	}
	instruction_label.text = "Resolving %s…" % current_action
	api.resolve_attack(payload)


func _reload_selected() -> void:
	var actor_state: Dictionary = selected_token.actor_state
	var weapon_name := str(actor_state.get("selected_weapon", ""))
	var weapon: Dictionary = actor_state.get("weapons", {}).get(weapon_name, {})
	if weapon.is_empty():
		instruction_label.text = "Selected token has no configured weapon."
		return
	api.reload({"actor_id": selected_token.token_id, "weapon": weapon_name})


func _on_api_success(kind: String, payload: Dictionary) -> void:
	service_status.text = "RULES SERVICE • ONLINE • LOCALHOST:8000"
	service_status.add_theme_color_override("font_color", Color("68ff9b"))
	if kind == "fetch" and payload.get("actors", []).is_empty():
		instruction_label.text = "No encounter loaded • creating the demo alley"
		api.reset_session(_initial_session_state())
		return
	_consume_snapshot(payload)
	if kind in ["fetch", "reset"]:
		_sync_cover_state(payload.get("covers", {}))
		_refresh_inspector()
		instruction_label.text = "Ready • select an action"
		return
	if kind in ["resolve", "reload", "undo", "redo"]:
		var card: Variant = payload.get("card")
		if card is Dictionary:
			resolution_card.show_card(card)
		_play_events(payload.get("events", []))
		_sync_cover_state(payload.get("covers", {}))
		if kind == "resolve":
			_play_pending_shot(bool(payload.get("result", {}).get("hit", false)))
		instruction_label.text = str(payload.get("card", {}).get("title", kind)).to_upper()
		_refresh_inspector()


func _on_api_failure(kind: String, message: String, transport_failure: bool) -> void:
	service_status.text = (
		"RULES SERVICE • OFFLINE" if transport_failure else "RULES SERVICE • COMMAND REJECTED"
	)
	service_status.add_theme_color_override(
		"font_color", Color("ff3f67") if transport_failure else Color("ffe45c")
	)
	instruction_label.text = message
	var recovery := (
		"Start uvicorn on localhost:8000."
		if transport_failure
		else "No encounter state was changed."
	)
	(
		resolution_card
		. show_card(
			{
				"title": "SERVICE ERROR",
				"lines": [message, recovery],
				"tone": "miss",
				"duration_seconds": 5.0,
			}
		)
	)
	if kind == "resolve":
		pending_shot.clear()


func _consume_snapshot(snapshot: Dictionary) -> void:
	var actor_map: Dictionary = {}
	for actor_value in snapshot.get("actors", []):
		if not actor_value is Dictionary:
			continue
		var actor: Dictionary = actor_value.duplicate(true)
		var weapon_map: Dictionary = {}
		for weapon_value in actor.get("weapons", []):
			if weapon_value is Dictionary:
				var weapon: Dictionary = weapon_value
				weapon_map[str(weapon.get("name", ""))] = weapon
		actor["weapons"] = weapon_map
		actor_map[str(actor.get("id", ""))] = actor
	session_state = {"actors": actor_map}
	_sync_tokens(actor_map)
	_apply_session_state()


func _sync_tokens(actors: Dictionary) -> void:
	for token_id in tokens.keys():
		if not actors.has(token_id):
			var removed := tokens[token_id] as CombatToken
			tokens.erase(token_id)
			removed.queue_free()
			if removed == selected_token:
				selected_token = null
	var index := 0
	var accents := [Color("00e5ff"), Color("ff5a1f"), Color("ffe45c"), Color("ff2ca8")]
	for actor_id in actors:
		var actor: Dictionary = actors[actor_id]
		if not tokens.has(actor_id):
			var token := TOKEN_SCENE.instantiate() as CombatToken
			var portrait := SOLO_PORTRAIT if index % 2 == 0 else GOON_PORTRAIT
			token.configure(
				str(actor_id),
				str(actor.get("name", actor_id)),
				portrait,
				accents[index % accents.size()]
			)
			token.position = Vector3(
				-6.0 + float(index % 3) * 6.0, 0.12, 5.8 - float(index / 3) * 6.0
			)
			token_layer.add_child(token)
			tokens[actor_id] = token
		else:
			var token := tokens[actor_id] as CombatToken
			token.display_name = str(actor.get("name", actor_id))
			token.name_label.text = token.display_name.to_upper()
		index += 1
	if not selected_token and not tokens.is_empty():
		_select_token(tokens.values()[0] as CombatToken)


func _sync_cover_state(covers: Dictionary) -> void:
	for cover_id in covers:
		if cover_by_id.has(cover_id):
			var cover := cover_by_id[cover_id] as CoverBody
			cover.set_hp(int(covers[cover_id]))


func _apply_session_state() -> void:
	var actors: Dictionary = session_state.get("actors", {})
	for token_id in tokens:
		if actors.has(token_id):
			tokens[token_id].apply_state(actors[token_id])


func _play_events(events: Array) -> void:
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var kind := str(event.get("kind", ""))
		var target_id := str(event.get("target_id", ""))
		if kind in ["damage_taken", "damage_healed"] and tokens.has(target_id):
			var damage_float := DAMAGE_FLOAT_SCENE.instantiate() as DamageFloat
			damage_float.position = tokens[target_id].global_position + Vector3(0, 2.5, 0)
			effects_layer.add_child(damage_float)
			damage_float.show_amount(int(event.get("amount", 0)), kind == "damage_healed")
		elif kind == "cover_damaged":
			var damaged_cover := _cover_for_event(event, target_id)
			if is_instance_valid(damaged_cover):
				damaged_cover.apply_damage(int(event.get("amount", 0)))
		elif kind == "cover_repaired":
			var repaired_cover := _cover_for_event(event, target_id)
			if is_instance_valid(repaired_cover):
				repaired_cover.repair(int(event.get("amount", 0)))


func _cover_for_event(event: Dictionary, target_id: String) -> CoverBody:
	var cover_id := str(event.get("cover_id", ""))
	if not cover_id.is_empty() and cover_by_id.has(cover_id):
		return cover_by_id[cover_id] as CoverBody
	return cover_for_target.get(target_id) as CoverBody


func _play_pending_shot(hit: bool) -> void:
	if pending_shot.is_empty():
		return
	var attacker: CombatToken = pending_shot.get("attacker") as CombatToken
	var target: CombatToken = pending_shot.get("target") as CombatToken
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		pending_shot.clear()
		return
	var from := attacker.global_position + Vector3(0, 1.35, 0)
	var to := target.global_position + Vector3(0, 1.25, 0)
	var cover: CoverBody = pending_shot.get("cover") as CoverBody
	if hit and is_instance_valid(cover):
		to = cover.global_position + Vector3(0, 0.3, 0)
	var vfx := GUNSHOT_SCENE.instantiate() as GunshotVFX
	effects_layer.add_child(vfx)
	vfx.play(from, to, hit)
	pending_shot.clear()


func _refresh_inspector() -> void:
	if not selected_token or selected_token.actor_state.is_empty():
		inspector.clear()
		return
	var reference: CombatToken
	for token_id in tokens:
		if tokens[token_id] != selected_token:
			reference = tokens[token_id]
			break
	var cover_info := {"classification": "none", "material": "none", "hp": 0}
	if reference:
		cover_info = CoverDetector.classify(get_world_3d(), reference, selected_token)
	(
		inspector
		. show_actor(
			selected_token.display_name,
			selected_token.actor_state,
			cover_info,
			bool(evading.get(selected_token.token_id, false)),
		)
	)


func _on_cover_changed(_cover: CoverBody) -> void:
	_refresh_inspector()
