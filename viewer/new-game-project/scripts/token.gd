class_name CombatToken
extends Area3D

@export var token_id := "actor"
@export var display_name := "Actor"
@export var portrait: Texture2D
@export var accent := Color("00e5ff")

var actor_state: Dictionary = {}

@onready var base: MeshInstance3D = $Base
@onready var portrait_mesh: MeshInstance3D = $Portrait
@onready var selection: MeshInstance3D = $Selection
@onready var name_label: Label3D = $NameLabel


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	input_ray_pickable = true
	_apply_materials()
	name_label.text = display_name.to_upper()
	set_selected(false)


func configure(id: String, label: String, texture: Texture2D, color: Color) -> void:
	token_id = id
	display_name = label
	portrait = texture
	accent = color
	if is_node_ready():
		_apply_materials()
		name_label.text = display_name.to_upper()


func apply_state(state: Dictionary) -> void:
	actor_state = state.duplicate(true)


func set_selected(value: bool) -> void:
	selection.visible = value
	name_label.modulate = accent
	name_label.outline_modulate = Color("02040a")


func _apply_materials() -> void:
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color("08131e")
	base_material.metallic = 0.75
	base_material.roughness = 0.22
	base_material.emission_enabled = true
	base_material.emission = accent * 0.35
	base.material_override = base_material

	var portrait_material := StandardMaterial3D.new()
	portrait_material.albedo_texture = portrait
	portrait_material.albedo_color = Color.WHITE.lerp(accent, 0.2)
	portrait_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portrait_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	portrait_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	portrait_mesh.material_override = portrait_material

	var selection_material := StandardMaterial3D.new()
	selection_material.albedo_color = accent
	selection_material.emission_enabled = true
	selection_material.emission = accent * 2.5
	selection.material_override = selection_material
