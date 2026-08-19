extends Node

## Application-wide 3D model library for board tokens and cover.
##
## Models are user-supplied glTF files in [constant LIBRARY_DIR]. Like [ItemDB],
## the library lives outside campaign saves: a character stores only a
## `model_id`, so a `.red` stays small and portable and two GMs can point the
## same campaign at different art.
##
## Loading goes through [GLTFDocument] rather than [method @GDScript.load]
## because `load()` only resolves assets the editor imported into `res://`. A
## file the user dropped in at runtime has no import record, so `load()` would
## work in the editor and fail in an exported build.
##
## Normalization is the same convention the board already uses for cover: sizes
## are authored in real metres and divided by the location's `tile_metres` to
## reach board units. A model is scaled uniformly so its bounding box height
## matches the declared real-world height, then seated so its feet rest on the
## tile and its footprint centres on the cell.

signal library_changed

const LIBRARY_DIR := "user://models"
const MANIFEST_PATH := "user://models/models.json"

## Height of an average adult, used when a model declares none.
const DEFAULT_HEIGHT_M := 1.8

## Models are drawn once per unit rather than batched, so an over-detailed
## sculpt is rejected instead of quietly stalling the board.
const MAX_TRIANGLES := 200000

const KINDS: PackedStringArray = ["character", "cover"]

var _models: Array[Dictionary] = []
var _cache: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_cache.clear()
	_models = _read_library()
	library_changed.emit()


func catalog(kind := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _models:
		if kind == "" or String(entry["kind"]) == kind:
			result.append(entry.duplicate(true))
	return result


func find_model(model_id: String) -> Dictionary:
	for entry in _models:
		if String(entry["id"]) == model_id:
			return entry
	return {}


func has_models() -> bool:
	return not _models.is_empty()


func library_path() -> String:
	return ProjectSettings.globalize_path(LIBRARY_DIR)


## Build a board-ready instance of [param model_id].
##
## Returns {"node": Node3D, "height": float} in board units, or an empty
## Dictionary when the model is unknown or unreadable. [param prone] lays the
## model on its side for a downed unit, since a token that only shrinks reads as
## a small character rather than a fallen one.
## [param height_m] overrides the model's declared height, which is how a cover
## model is made to fill the block its palette entry defines rather than
## whatever height the artist happened to author.
func instantiate(
	model_id: String, tile_metres: float, prone := false, height_m := 0.0
) -> Dictionary:
	var entry := find_model(model_id)
	if entry.is_empty():
		return {}
	var source := _load_scene(entry)
	if source == null:
		return {}

	var holder := Node3D.new()
	var model := source.duplicate()
	holder.add_child(model)
	var wanted := height_m if height_m > 0.0 else float(entry["height_m"])
	var height := normalize(model, wanted, tile_metres)
	if height <= 0.0:
		holder.free()
		return {}
	if prone:
		# Tip the model onto its face and reseat it. A downed token that only
		# shrinks reads as a small character rather than a fallen one. The box
		# is measured in the holder's space, because scene_aabb() excludes the
		# model's own transform and so cannot see the rotation.
		model.rotate_x(-PI / 2.0)
		var lying: AABB = model.transform * scene_aabb(model)
		model.position.y -= lying.position.y
		height = maxf(lying.size.y, 0.05)
	return {"node": holder, "height": height, "radius": footprint_radius(model)}


## Union of every mesh bound in [param root]'s subtree, in [param root]'s space.
##
## Node transforms are walked by hand rather than read from `global_transform`,
## because a freshly generated glTF scene has not entered the tree and its
## global transforms are not yet meaningful.
static func scene_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for node in _mesh_nodes(root):
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		var local: AABB = _transform_to(root, node) * mesh.get_aabb()
		if found:
			box = box.merge(local)
		else:
			box = local
			found = true
	return box if found else AABB()


## Scale [param root] so its bounding box stands [param height_m] metres tall in
## board units, then seat it with its feet at y = 0 and its footprint centred.
##
## Returns the resulting height in board units, or 0.0 when the model has no
## measurable volume.
static func normalize(root: Node3D, height_m: float, tile_metres: float) -> float:
	if height_m <= 0.0 or tile_metres <= 0.0:
		return 0.0
	var box := scene_aabb(root)
	if box.size.y <= 0.0:
		return 0.0
	var target := height_m / tile_metres
	var factor := target / box.size.y
	root.scale = Vector3.ONE * factor
	var scaled := box.size * factor
	var origin := box.position * factor
	root.position = Vector3(
		-(origin.x + scaled.x * 0.5), -origin.y, -(origin.z + scaled.z * 0.5)
	)
	return target


## Widest horizontal half-extent, in board units, for sizing a base disc or a
## selection ring around a model that is not as slim as the default cylinder.
##
## Measured in the parent's space so it stays correct once a downed model has
## been rotated onto its side.
static func footprint_radius(root: Node3D) -> float:
	var box: AABB = root.transform * scene_aabb(root)
	return maxf(box.size.x, box.size.z) * 0.5


## Check one library row before it can reach the board.
static func validate_model(entry: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(entry) != TYPE_DICTIONARY:
		problems.append("model is not a JSON object")
		return problems
	var model: Dictionary = entry
	var label := String(model.get("name", model.get("id", "model")))
	if String(model.get("id", "")).is_empty():
		problems.append("%s: missing id" % label)
	if String(model.get("file", "")).is_empty():
		problems.append("%s: missing file" % label)
	if not KINDS.has(String(model.get("kind", ""))):
		problems.append("%s: kind must be one of %s" % [label, ", ".join(KINDS)])
	if float(model.get("height_m", 0.0)) <= 0.0:
		problems.append("%s: height_m must be positive" % label)
	return problems


static func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(_mesh_nodes(child))
	return found


static func _transform_to(root: Node3D, node: Node3D) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			combined = (current as Node3D).transform * combined
		current = current.get_parent()
	return combined


func _load_scene(entry: Dictionary) -> Node3D:
	var id := String(entry["id"])
	if _cache.has(id):
		return _cache[id]
	var path := String(entry["path"])
	if not FileAccess.file_exists(path):
		push_warning("model %s: %s is missing" % [id, path])
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		push_warning("model %s: %s could not be read as glTF" % [id, path])
		return null
	var scene := document.generate_scene(state)
	if not (scene is Node3D):
		push_warning("model %s: %s holds no 3D scene" % [id, path])
		if scene != null:
			scene.free()
		return null
	var triangles := _triangle_count(scene)
	if triangles > MAX_TRIANGLES:
		push_warning(
			"model %s: %d triangles exceeds the %d budget" % [id, triangles, MAX_TRIANGLES]
		)
		scene.free()
		return null
	_cache[id] = scene
	return scene


static func _triangle_count(root: Node3D) -> int:
	var total := 0
	for node in _mesh_nodes(root):
		var mesh: Mesh = node.mesh
		if mesh != null:
			total += mesh.get_faces().size() / 3
	return total


## Read the manifest, then adopt any loose glTF file it does not mention so a
## dropped-in model shows up without hand-editing JSON.
func _read_library() -> Array[Dictionary]:
	DirAccess.make_dir_recursive_absolute(LIBRARY_DIR)
	var result: Array[Dictionary] = []
	var claimed := {}

	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(MANIFEST_PATH)
		)
		if parsed is Dictionary:
			for value in (parsed as Dictionary).get("models", []):
				if not (value is Dictionary):
					continue
				var entry: Dictionary = (value as Dictionary).duplicate(true)
				entry["kind"] = String(entry.get("kind", "character"))
				entry["height_m"] = float(entry.get("height_m", DEFAULT_HEIGHT_M))
				entry["name"] = String(entry.get("name", entry.get("id", "Model")))
				var problems := validate_model(entry)
				if not problems.is_empty():
					push_warning("%s: skipped %s" % [MANIFEST_PATH, problems[0]])
					continue
				entry["path"] = "%s/%s" % [LIBRARY_DIR, entry["file"]]
				claimed[String(entry["file"])] = true
				result.append(entry)

	for file in _library_files():
		if claimed.has(file):
			continue
		var id := file.get_basename().to_snake_case()
		result.append(
			{
				"id": id,
				"name": file.get_basename().capitalize(),
				"file": file,
				"kind": "character",
				"height_m": DEFAULT_HEIGHT_M,
				"path": "%s/%s" % [LIBRARY_DIR, file],
			}
		)
	return result


func _library_files() -> PackedStringArray:
	var files := PackedStringArray()
	var directory := DirAccess.open(LIBRARY_DIR)
	if directory == null:
		return files
	for file in directory.get_files():
		if file.get_extension().to_lower() in ["glb", "gltf"]:
			files.append(file)
	files.sort()
	return files
