class_name IsoBoard
extends Node3D

## The isometric board.
##
## Knows about grid cells rather than world units, so the screen only ever deals
## in `{x, z, layer}`. It owns picking, the line-of-sight raycast that drives the
## cover prompt, and the shot and blast effects.

signal cell_hovered(cell: Dictionary)

const LAYER_HEIGHT := 1.2
const GROUND_LAYER := 1
const PROP_LAYER := 2
const UNIT_LAYER := 3

const SIDE_COLORS := {
	"party": Color("93bce2"),
	"hostile": Color("bb5451"),
	"neutral": Color("d9b45c"),
}

var camera: Camera3D
var _tiles: MultiMeshInstance3D
var _props := Node3D.new()
var _units := Node3D.new()
var _effects := Node3D.new()
var _overlay := Node3D.new()
var _ground_body: StaticBody3D

var _location: Dictionary = {}
var _covers: Dictionary = {}
var _unit_nodes: Dictionary = {}
var _selection: MeshInstance3D
var _hover: MeshInstance3D
var _blast_ring: MeshInstance3D
var _zoom := 26.0


## Built in _init rather than _ready: the screen configures the board straight
## after constructing it, before the SubViewport it lives in has entered the
## tree, so waiting for _ready would leave every node null at that point.
func _init() -> void:
	add_child(_props)
	add_child(_units)
	add_child(_effects)
	add_child(_overlay)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom
	camera.far = 400.0
	# A true isometric view: equal angles down all three axes. Aimed before the
	# node enters the tree, so look_at_from_position rather than look_at.
	camera.look_at_from_position(Vector3(60, 60, 60), Vector3.ZERO, Vector3.UP)
	add_child(camera)

	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = UI.PANEL_INSET
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("8fa8c4")
	world.ambient_light_energy = 1.6
	environment.environment = world
	add_child(environment)

	var key := DirectionalLight3D.new()
	key.light_color = Color("d6e6f7")
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-52, -38, 0)
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("bb5451")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-20, 140, 0)
	add_child(rim)

	_selection = _make_ring(0.62, 0.78, UI.ACCENT)
	_selection.visible = false
	_overlay.add_child(_selection)

	_hover = MeshInstance3D.new()
	var hover_mesh := PlaneMesh.new()
	hover_mesh.size = Vector2(1, 1)
	_hover.mesh = hover_mesh
	_hover.material_override = _unshaded(UI.ACCENT, 0.16)
	_hover.visible = false
	_overlay.add_child(_hover)


static func _unshaded(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _unshaded(color)
	return node


# -- geometry -------------------------------------------------------------------


func _half() -> Vector2:
	return Vector2(
		float(_location.get("grid_width", 20)) / 2.0 - 0.5,
		float(_location.get("grid_height", 20)) / 2.0 - 0.5,
	)


## Grid cell to world position, centred on the cell.
func world_of(cell: Dictionary) -> Vector3:
	var half := _half()
	return Vector3(
		float(cell["x"]) - half.x, float(cell.get("layer", 0)) * LAYER_HEIGHT, float(cell["z"]) - half.y
	)


func _cell_of(point: Vector3, layer := 0) -> Dictionary:
	var half := _half()
	return {"x": roundi(point.x + half.x), "z": roundi(point.z + half.y), "layer": layer}


func tile_metres() -> float:
	return float(_location.get("tile_metres", 2.0))


## Distance between two cells in metres.
func distance_m(a: Dictionary, b: Dictionary) -> float:
	return (
		Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
		* tile_metres()
	)


# -- building --------------------------------------------------------------------


func set_location(location: Dictionary, cover_palette: Array) -> void:
	_location = location
	_covers = {}
	for cover in cover_palette:
		_covers[String((cover as Dictionary)["id"])] = cover
	_build_ground()
	_build_props()
	_zoom = maxf(float(location.get("grid_width", 20)), float(location.get("grid_height", 20))) * 1.2
	camera.size = _zoom


func _clear(node: Node3D) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _build_ground() -> void:
	if is_instance_valid(_tiles):
		_tiles.queue_free()
	if is_instance_valid(_ground_body):
		_ground_body.queue_free()

	var tiles: Array = _location.get("tiles", [])
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.12, 0.96)

	# The material stays white: the per-instance colour multiplies into it, so a
	# tint here would apply twice and crush the deck to black.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 0.82
	material.metallic = 0.12
	material.vertex_color_use_as_albedo = true
	box.material = material

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = box
	multi.instance_count = tiles.size()

	for index in tiles.size():
		var tile: Dictionary = tiles[index]
		var position := world_of(tile)
		multi.set_instance_transform(
			index, Transform3D(Basis.IDENTITY, position + Vector3(0, -0.06, 0))
		)
		# Elevation shading, plus a faint checker so the grid reads without lines.
		var lift := 1.0 + float(tile.get("layer", 0)) * 0.4
		var base := Color("2b3a4d") if (int(tile["x"]) + int(tile["z"])) % 2 == 0 else Color("25323f")
		multi.set_instance_color(index, base * lift)

	_tiles = MultiMeshInstance3D.new()
	_tiles.multimesh = multi
	add_child(_tiles)

	# One flat body under the deck carries ground picking, rather than a
	# collider per tile.
	var width := float(_location.get("grid_width", 20))
	var height := float(_location.get("grid_height", 20))
	_ground_body = StaticBody3D.new()
	_ground_body.collision_layer = 1 << (GROUND_LAYER - 1)
	_ground_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(width, 0.12, height)
	shape.shape = box_shape
	_ground_body.add_child(shape)
	_ground_body.position = Vector3(0, -0.06, 0)
	add_child(_ground_body)


func _build_props() -> void:
	_clear(_props)
	for prop in _location.get("props", []):
		var entry: Dictionary = prop
		var cover: Dictionary = _covers.get(String(entry["cover_id"]), {})
		if cover.is_empty():
			continue
		var scale := tile_metres()
		var extents := Vector3(
			float(cover["width"]) / scale, float(cover["height"]) / scale, float(cover["depth"]) / scale
		)

		var body := StaticBody3D.new()
		body.collision_layer = 1 << (PROP_LAYER - 1)
		body.collision_mask = 0
		body.set_meta("kind", "prop")
		body.set_meta("id", String(entry["id"]))
		body.set_meta("cover_id", String(entry["cover_id"]))
		body.set_meta("cell", {"x": int(entry["x"]), "z": int(entry["z"]), "layer": int(entry.get("layer", 0))})

		# A model stands in for the block visually only. The collision box below
		# is left exactly as it was, because cover_between() raycasts against it
		# and line of sight must not change with the art.
		var model := _resolve_model(
			String(entry.get("model_id", cover.get("model_id", ""))),
			false,
			float(cover["height"]),
		)
		if model.is_empty():
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = extents
			mesh.mesh = box
			var material := StandardMaterial3D.new()
			material.albedo_color = _material_color(String(cover["material"]))
			material.roughness = 0.7
			material.metallic = 0.25
			mesh.material_override = material
			body.add_child(mesh)
		else:
			# The body is seated at the block's centre, so a model whose feet sit
			# at its own origin has to drop by half the block's height to stand
			# on the ground rather than hover at the block's midpoint.
			var node: Node3D = model["node"]
			node.position = Vector3(0, -extents.y * 0.5, 0)
			body.add_child(node)

		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = extents
		shape.shape = box_shape
		body.add_child(shape)

		var position := world_of(entry)
		body.position = position + Vector3(0, extents.y * 0.5, 0)
		body.rotation_degrees = Vector3(0, float(entry.get("rotation", 0)), 0)
		_props.add_child(body)


static func _material_color(material: String) -> Color:
	match material:
		"Concrete":
			return Color("3b434c")
		"Steel Plate":
			return Color("4a5666")
		"Glass":
			return Color("2f5566")
		"Sheet Metal":
			return Color("5a5f66")
		"Wood Crate":
			return Color("6a4a26")
		"Vehicle Hulk":
			return Color("63343a")
		_:
			return Color("39414b")


## Resolve a model id into a board-ready node, or an empty Dictionary when the
## id is blank or the library cannot supply it. Returns {node, height, radius}
## with both measurements already in board units.
func _resolve_model(model_id: String, prone := false, height_m := 0.0) -> Dictionary:
	if model_id.is_empty():
		return {}
	return ModelDB.instantiate(model_id, tile_metres(), prone, height_m)


## [param visuals] maps unit id to {side, hp_ratio, down, model_id}.
func set_units(units: Array, visuals: Dictionary) -> void:
	_clear(_units)
	_unit_nodes = {}

	for unit in units:
		var entry: Dictionary = unit
		var id := String(entry["id"])
		var visual: Dictionary = visuals.get(id, {})
		if visual.is_empty():
			continue
		var side := String(visual.get("side", "neutral"))
		var down := bool(visual.get("down", false))
		var ratio := float(visual.get("hp_ratio", 1.0))
		var color: Color = SIDE_COLORS.get(side, SIDE_COLORS["neutral"])

		var body := StaticBody3D.new()
		body.collision_layer = 1 << (UNIT_LAYER - 1)
		body.collision_mask = 0
		body.set_meta("kind", "unit")
		body.set_meta("id", id)
		body.set_meta("cell", {"x": int(entry["x"]), "z": int(entry["z"]), "layer": int(entry.get("layer", 0))})
		body.position = world_of(entry)

		var height := 0.24 if down else 1.05
		var radius := 0.46

		# A character may carry its own model. It replaces the token's body but
		# not its footprint: the base disc, health pip, selection ring and
		# collision shape all keep working off whatever height it normalizes to.
		var model := _resolve_model(String(visual.get("model_id", "")), down)
		if model.is_empty():
			var mesh := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.36
			cylinder.bottom_radius = 0.42
			cylinder.height = height
			mesh.mesh = cylinder
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.1 if down else 0.35
			material.roughness = 0.5
			mesh.material_override = material
			mesh.position = Vector3(0, height * 0.5, 0)
			body.add_child(mesh)
		else:
			height = float(model["height"])
			radius = maxf(0.46, float(model["radius"]))
			body.add_child(model["node"])

		var shape := CollisionShape3D.new()
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = 0.42
		cylinder_shape.height = maxf(height, 0.6)
		shape.shape = cylinder_shape
		shape.position = Vector3(0, height * 0.5, 0)
		body.add_child(shape)

		# A base disc reading as the unit's footprint on the grid.
		var base := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.02
		base.mesh = disc
		base.material_override = _unshaded(color, 0.3)
		base.position = Vector3(0, 0.02, 0)
		body.add_child(base)

		# A health pip floating over the token.
		var pip := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(maxf(0.08, 0.8 * ratio), 0.08)
		pip.mesh = quad
		var pip_color := UI.GOOD if ratio > 0.5 else (UI.WARN if ratio > 0.25 else UI.ALERT)
		var pip_material := _unshaded(pip_color)
		pip_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pip.material_override = pip_material
		pip.position = Vector3(0, height + 0.35, 0)
		body.add_child(pip)

		_units.add_child(body)
		_unit_nodes[id] = body


func set_selection(unit_id: String) -> void:
	var node: Node3D = _unit_nodes.get(unit_id)
	if node == null:
		_selection.visible = false
		return
	_selection.visible = true
	_selection.position = node.position + Vector3(0, 0.05, 0)


func set_hover_cell(cell: Dictionary) -> void:
	if cell.is_empty():
		_hover.visible = false
		return
	_hover.visible = true
	_hover.position = world_of(cell) + Vector3(0, 0.08, 0)


func set_zoom_delta(delta: float) -> void:
	_zoom = clampf(_zoom + delta, 10.0, 60.0)
	camera.size = _zoom


# -- picking ---------------------------------------------------------------------


func _raycast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


## Pick whatever is under [param viewport_point], preferring units, then props,
## then the deck. Returns {} when the ray misses everything.
func pick(viewport_point: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(viewport_point)
	var to := from + camera.project_ray_normal(viewport_point) * 400.0

	for layer in [UNIT_LAYER, PROP_LAYER]:
		var hit := _raycast(from, to, 1 << (layer - 1))
		if not hit.is_empty():
			var body: Node = hit["collider"]
			return {
				"kind": String(body.get_meta("kind")),
				"id": String(body.get_meta("id")),
				"cell": body.get_meta("cell"),
			}

	var ground := _raycast(from, to, 1 << (GROUND_LAYER - 1))
	if not ground.is_empty():
		return {"kind": "ground", "id": "", "cell": _cell_of(ground["position"])}

	# Fall back to the y = 0 plane so drops past the deck edge still land.
	var plane := Plane(Vector3.UP, 0.0)
	var point: Variant = plane.intersects_ray(from, camera.project_ray_normal(viewport_point))
	if point != null:
		return {"kind": "ground", "id": "", "cell": _cell_of(point)}
	return {}


## Is anything between these two cells?
##
## Samples several rays across the target's silhouette rather than one down the
## centre, so a barrier clipping the edge of a target reports partial occlusion
## instead of none. Returns {} when the line is clear.
func cover_between(from_cell: Dictionary, to_cell: Dictionary) -> Dictionary:
	var origin := world_of(from_cell) + Vector3(0, 0.9, 0)
	var target := world_of(to_cell) + Vector3(0, 0.9, 0)
	var axis := target - origin
	if axis.length() < 0.001:
		return {}
	var side := Vector3(-axis.z, 0, axis.x).normalized() * 0.34

	var blocked := 0
	var samples := [-1.0, -0.5, 0.0, 0.5, 1.0]
	var nearest: Dictionary = {}
	var nearest_distance := INF

	for factor in samples:
		var shifted: Vector3 = target + side * factor
		var direction := (shifted - origin)
		var span := direction.length()
		direction = direction.normalized()
		# Stop short of the target so the target's own body never counts as cover.
		var hit := _raycast(origin, origin + direction * maxf(0.1, span - 0.45), 1 << (PROP_LAYER - 1))
		if hit.is_empty():
			continue
		blocked += 1
		var distance: float = origin.distance_to(hit["position"])
		if distance < nearest_distance:
			nearest_distance = distance
			var body: Node = hit["collider"]
			nearest = {
				"prop_id": String(body.get_meta("id")),
				"cover_id": String(body.get_meta("cover_id")),
			}

	if nearest.is_empty():
		return {}
	nearest["distance_m"] = snappedf(nearest_distance * tile_metres(), 0.1)
	nearest["occlusion"] = float(blocked) / float(samples.size())
	return nearest


# -- effects -----------------------------------------------------------------------


func play_shot(from_cell: Dictionary, to_cell: Dictionary, hit: bool) -> void:
	var start := world_of(from_cell) + Vector3(0, 0.85, 0)
	var end := world_of(to_cell) + Vector3(0, 0.85, 0)

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
	var tracer := MeshInstance3D.new()
	tracer.mesh = mesh
	var material := _unshaded(Color("ffd88a") if hit else UI.MUTED, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.material_override = material
	_effects.add_child(tracer)
	_fade_and_free(tracer, material, 0.45)

	if hit:
		_play_impact(end)


func _play_impact(at: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	flash.mesh = sphere
	var material := _unshaded(Color("ffb066"), 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = material
	flash.position = at
	_effects.add_child(flash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(flash.queue_free)


func _fade_and_free(node: Node3D, material: StandardMaterial3D, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(node.queue_free)


## An expanding shell plus a ground ring, sized in metres.
func play_blast(centre: Dictionary, radius_m: float) -> void:
	var radius := radius_m / tile_metres()
	var at := world_of(centre)

	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	shell.mesh = sphere
	var shell_material := _unshaded(Color("ff9a4d"), 0.55)
	shell.material_override = shell_material
	shell.position = at + Vector3(0, 0.6, 0)
	shell.scale = Vector3.ONE * 0.25
	_effects.add_child(shell)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE, 0.6)
	tween.tween_property(shell_material, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(shell.queue_free)

	var ring := _make_ring(radius * 0.94, radius, UI.ALERT)
	ring.position = at + Vector3(0, 0.1, 0)
	_effects.add_child(ring)
	var ring_material: StandardMaterial3D = ring.material_override
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_and_free(ring, ring_material, 0.8)


## A persistent ring showing a pending blast radius while the GM aims.
func show_blast_preview(centre: Dictionary, radius_m: float) -> void:
	if is_instance_valid(_blast_ring):
		_blast_ring.queue_free()
		_blast_ring = null
	if centre.is_empty():
		return
	var radius := radius_m / tile_metres()
	_blast_ring = _make_ring(radius * 0.93, radius, UI.ALERT)
	_blast_ring.position = world_of(centre) + Vector3(0, 0.1, 0)
	_overlay.add_child(_blast_ring)
