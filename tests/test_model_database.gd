extends RefCounted

## Model normalization is geometry, so it is checked against boxes of known
## size rather than eyeballed on the board.
##
## The glTF round trip is deliberately end to end: a scene is written out as a
## real .glb and read back through the same GLTFDocument path the app uses at
## runtime, because that path — not `load()` — is the one that has to work in an
## exported build.

const Harness := preload("res://tests/harness.gd")

const ModelDatabase := preload("res://scripts/rules/model_database.gd")

const SANDBOX := "user://test_models"


static func _box_scene(size: Vector3, offset := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = offset
	root.add_child(mesh)
	return root


## Write a box out as a real .glb so the runtime loader has something to read.
static func _write_glb(path: String, size: Vector3) -> bool:
	var scene := _box_scene(size)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := document.append_from_scene(scene, state) == OK
	ok = ok and document.write_to_filesystem(state, path) == OK
	scene.free()
	return ok


static func run(h: Harness) -> void:
	h.describe("model database")

	h.it("measures a subtree's bounds in the root's own space")
	var plain := _box_scene(Vector3(1, 2, 3))
	var box := ModelDatabase.scene_aabb(plain)
	h.equal(box.size, Vector3(1, 2, 3), "bounds match the mesh")
	h.equal(box.get_center(), Vector3.ZERO, "centred on the origin")
	plain.free()

	# A child offset from its parent has to widen the bounds, which is what a
	# real glTF looks like: meshes hang off nodes at arbitrary transforms.
	var offset := _box_scene(Vector3(2, 2, 2), Vector3(0, 3, 0))
	var offset_box := ModelDatabase.scene_aabb(offset)
	h.equal(offset_box.position.y, 2.0, "child transform is folded in")
	h.equal(offset_box.size.y, 2.0, "size follows the child, not the origin")
	offset.free()

	h.it("scales a model to a real-world height in board units")
	# A 4-unit-tall model, asked to stand 1.8 m tall on 2 m tiles, has to end up
	# 0.9 board units tall whatever it measured beforehand.
	var tall := _box_scene(Vector3(1, 4, 1))
	var height := ModelDatabase.normalize(tall, 1.8, 2.0)
	h.equal(height, 0.9, "height is metres divided by tile size")
	h.equal(is_equal_approx(tall.scale.y, 0.225), true, "scaled uniformly to fit")
	h.equal(is_equal_approx(tall.scale.x, tall.scale.y), true, "aspect preserved")
	var seated: AABB = tall.transform * ModelDatabase.scene_aabb(tall)
	h.equal(is_zero_approx(seated.position.y), true, "feet rest on the tile")
	h.equal(is_zero_approx(seated.get_center().x), true, "centred across the cell")
	h.equal(is_zero_approx(seated.get_center().z), true, "centred along the cell")
	h.equal(is_equal_approx(seated.size.y, 0.9), true, "occupies the target height")
	tall.free()

	h.it("seats a model whose mesh sits far from its own origin")
	var floating := _box_scene(Vector3(2, 2, 2), Vector3(5, 9, -4))
	ModelDatabase.normalize(floating, 2.0, 2.0)
	var placed: AABB = floating.transform * ModelDatabase.scene_aabb(floating)
	h.equal(is_zero_approx(placed.position.y), true, "still lands on the tile")
	h.equal(is_zero_approx(placed.get_center().x), true, "still centred")
	h.equal(is_equal_approx(placed.size.y, 1.0), true, "still the right height")
	floating.free()

	h.it("reports a footprint wide enough to draw a base under")
	var wide := _box_scene(Vector3(6, 2, 1))
	ModelDatabase.normalize(wide, 2.0, 2.0)
	# 6 wide against 2 tall, scaled so height is 1.0, leaves a 3.0 span.
	h.equal(is_equal_approx(ModelDatabase.footprint_radius(wide), 1.5), true, "half the widest span")
	wide.free()

	h.it("refuses a model with no measurable volume")
	var flat := _box_scene(Vector3(1, 0, 1))
	h.equal(ModelDatabase.normalize(flat, 1.8, 2.0), 0.0, "zero-height model rejected")
	flat.free()
	var empty := Node3D.new()
	h.equal(ModelDatabase.normalize(empty, 1.8, 2.0), 0.0, "model with no mesh rejected")
	h.equal(ModelDatabase.scene_aabb(empty).size, Vector3.ZERO, "empty bounds")
	empty.free()
	var sane := _box_scene(Vector3(1, 1, 1))
	h.equal(ModelDatabase.normalize(sane, 0.0, 2.0), 0.0, "zero height_m rejected")
	h.equal(ModelDatabase.normalize(sane, 1.8, 0.0), 0.0, "zero tile size rejected")
	sane.free()

	h.it("validates library rows before they can reach the board")
	var good := {"id": "punk", "name": "Punk", "file": "punk.glb", "kind": "character", "height_m": 1.8}
	h.equal(ModelDatabase.validate_model(good), PackedStringArray(), "a complete row passes")
	for missing in ["id", "file"]:
		var row := good.duplicate()
		row[missing] = ""
		h.check(not ModelDatabase.validate_model(row).is_empty(), "missing %s rejected" % missing)
	var bad_kind := good.duplicate()
	bad_kind["kind"] = "vehicle"
	h.check(not ModelDatabase.validate_model(bad_kind).is_empty(), "unknown kind rejected")
	var bad_height := good.duplicate()
	bad_height["height_m"] = 0.0
	h.check(not ModelDatabase.validate_model(bad_height).is_empty(), "non-positive height rejected")
	h.check(not ModelDatabase.validate_model("not a row").is_empty(), "non-object rejected")

	h.it("loads a real glTF file through the runtime document path")
	DirAccess.make_dir_recursive_absolute(SANDBOX)
	var glb := "%s/probe.glb" % SANDBOX
	if not _write_glb(glb, Vector3(1, 4, 1)):
		h.check(false, "could not write a test .glb")
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	h.equal(document.append_from_file(glb, state), OK, "glTF parsed at runtime")
	var loaded := document.generate_scene(state)
	h.check(loaded is Node3D, "a 3D scene came back")
	if loaded is Node3D:
		var read := ModelDatabase.scene_aabb(loaded)
		h.equal(is_equal_approx(read.size.y, 4.0), true, "geometry survived the round trip")
		# The whole point: an arbitrary file normalizes to the same board size.
		var normalized := ModelDatabase.normalize(loaded, 1.8, 2.0)
		h.equal(is_equal_approx(normalized, 0.9), true, "a loaded model normalizes like any other")
		loaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(glb))
