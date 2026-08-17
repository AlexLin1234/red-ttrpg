class_name CoverDetector
extends RefCounted


static func classify(
	world: World3D,
	shooter: CollisionObject3D,
	target: CollisionObject3D,
) -> Dictionary:
	var space := world.direct_space_state
	var origin := shooter.global_position + Vector3(0, 1.25, 0)
	var target_offsets := [Vector3(0, 0.35, 0), Vector3(0, 1.2, 0), Vector3(0, 2.0, 0)]
	var blocked := 0
	var first_cover: CoverBody = null
	for offset in target_offsets:
		var query := PhysicsRayQueryParameters3D.create(origin, target.global_position + offset, 2)
		query.exclude = [shooter.get_rid(), target.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit.get("collider") is CoverBody:
			blocked += 1
			if first_cover == null:
				first_cover = hit["collider"] as CoverBody
	var classification := "none"
	if blocked == target_offsets.size():
		classification = "full"
	elif blocked > 0:
		classification = "partial"
	return {
		"classification": classification,
		"blocked_rays": blocked,
		"cover": first_cover,
		"material": first_cover.cover_material if first_cover else "none",
		"hp": first_cover.hp if first_cover else 0,
	}
