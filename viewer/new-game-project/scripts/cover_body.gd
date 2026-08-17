class_name CoverBody
extends StaticBody3D

signal cover_changed(cover: CoverBody)

@export var cover_material := "steel"
@export var hp := 20
@export var max_hp := 20

var _mesh: MeshInstance3D
var _collision: CollisionShape3D


func configure(size: Vector3, color: Color, material_name: String, starting_hp: int) -> void:
	cover_material = material_name
	hp = starting_hp
	max_hp = starting_hp
	collision_layer = 2
	collision_mask = 0

	_mesh = MeshInstance3D.new()
	_mesh.name = "CoverMesh"
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.metallic = 0.72 if material_name == "steel" else 0.08
	surface.roughness = 0.28 if material_name == "steel" else 0.78
	surface.emission_enabled = true
	surface.emission = color * 0.18
	_mesh.material_override = surface
	add_child(_mesh)

	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	_collision.shape = shape
	add_child(_collision)


func apply_damage(amount: int) -> int:
	var previous := hp
	hp = maxi(0, hp - amount)
	_update_visual()
	cover_changed.emit(self)
	return previous - hp


func repair(amount: int) -> int:
	var previous := hp
	hp = mini(max_hp, hp + amount)
	_update_visual()
	cover_changed.emit(self)
	return hp - previous


func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	_update_visual()
	cover_changed.emit(self)


func _update_visual() -> void:
	if not _mesh:
		return
	var ratio := float(hp) / maxf(1.0, float(max_hp))
	_mesh.scale.y = maxf(0.12, ratio)
	_mesh.position.y = -(1.0 - ratio) * 0.5
	if _collision:
		_collision.disabled = hp <= 0
	_mesh.visible = hp > 0
