class_name GunshotVFX
extends Node3D

const IMPACT_TEXTURE := preload("res://assets/impact.svg")


func play(from: Vector3, to: Vector3, hit: bool) -> void:
	global_position = Vector3.ZERO
	var direction := to - from
	var distance := direction.length()

	var muzzle := OmniLight3D.new()
	muzzle.light_color = Color("7df9ff")
	muzzle.light_energy = 12.0
	muzzle.omni_range = 4.5
	muzzle.position = from
	add_child(muzzle)

	var tracer := MeshInstance3D.new()
	var tracer_mesh := CylinderMesh.new()
	tracer_mesh.top_radius = 0.025
	tracer_mesh.bottom_radius = 0.025
	tracer_mesh.height = distance
	tracer.mesh = tracer_mesh
	var tracer_material := StandardMaterial3D.new()
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color("fff4a8")
	tracer_material.emission_enabled = true
	tracer_material.emission = Color("ff6a24") * 5.0
	tracer.material_override = tracer_material
	tracer.position = from + direction * 0.5
	tracer.quaternion = Quaternion(Vector3.UP, direction.normalized())
	add_child(tracer)

	if hit:
		var sparks := GPUParticles3D.new()
		sparks.amount = 18
		sparks.lifetime = 0.45
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.position = to
		var particle_material := ParticleProcessMaterial.new()
		particle_material.direction = -direction.normalized()
		particle_material.spread = 65.0
		particle_material.initial_velocity_min = 2.0
		particle_material.initial_velocity_max = 6.0
		particle_material.gravity = Vector3(0, -7.0, 0)
		particle_material.color = Color("ff9c3a")
		sparks.process_material = particle_material
		var spark_mesh := QuadMesh.new()
		spark_mesh.size = Vector2(0.055, 0.22)
		sparks.draw_pass_1 = spark_mesh
		add_child(sparks)
		sparks.restart()

		var impact := Sprite3D.new()
		impact.texture = IMPACT_TEXTURE
		impact.pixel_size = 0.004
		impact.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		impact.position = to
		add_child(impact)

	var tween := create_tween()
	tween.tween_interval(0.035)
	tween.tween_callback(func() -> void: muzzle.visible = false)
	tween.tween_interval(0.09)
	tween.tween_property(tracer, "transparency", 1.0, 0.08)
	tween.tween_interval(0.55)
	tween.tween_callback(queue_free)
