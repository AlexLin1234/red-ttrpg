class_name CampaignFlow
extends RefCounted

## JSON-safe GM notes and a lightweight directed graph of campaign beats.

const STATUSES: PackedStringArray = ["planned", "active", "complete", "skipped"]
const CANVAS_SIZE := Vector2(1400, 900)


static func ensure_campaign(campaign: Dictionary) -> void:
	campaign["gm_notes"] = String(campaign.get("gm_notes", ""))
	if not campaign.has("beats") or not campaign["beats"] is Array:
		campaign["beats"] = []
	var valid_ids := PackedStringArray()
	for index in (campaign["beats"] as Array).size():
		var beat: Dictionary = (campaign["beats"] as Array)[index]
		beat["id"] = String(beat.get("id", "beat-%d-%d" % [Time.get_ticks_usec(), index]))
		beat["title"] = String(beat.get("title", "Untitled beat"))
		beat["notes"] = String(beat.get("notes", ""))
		var status := String(beat.get("status", "planned"))
		beat["status"] = status if STATUSES.has(status) else "planned"
		beat["x"] = clampf(float(beat.get("x", 60.0)), 0.0, CANVAS_SIZE.x)
		beat["y"] = clampf(float(beat.get("y", 60.0)), 0.0, CANVAS_SIZE.y)
		if not beat.has("next_ids") or not beat["next_ids"] is Array:
			beat["next_ids"] = []
		valid_ids.append(String(beat["id"]))
	for value in campaign["beats"]:
		var beat: Dictionary = value
		var cleaned: Array = []
		for next_id in beat["next_ids"]:
			var id := String(next_id)
			if id != String(beat["id"]) and valid_ids.has(id) and not cleaned.has(id):
				cleaned.append(id)
		beat["next_ids"] = cleaned


static func beat_by_id(campaign: Dictionary, id: String) -> Dictionary:
	ensure_campaign(campaign)
	for value in campaign["beats"]:
		var beat: Dictionary = value
		if String(beat["id"]) == id:
			return beat
	return {}


static func new_beat(index: int) -> Dictionary:
	return {
		"id": "beat-%d-%d" % [Time.get_ticks_usec(), index],
		"title": "New beat",
		"notes": "",
		"status": "planned",
		"x": 60.0 + float(index % 4) * 230.0,
		"y": 60.0 + floorf(float(index) / 4.0) * 130.0,
		"next_ids": [],
	}


static func beat_position(beat: Dictionary) -> Vector2:
	return Vector2(float(beat.get("x", 0.0)), float(beat.get("y", 0.0)))


static func set_beat_position(beat: Dictionary, point: Vector2) -> Vector2:
	var bounded := Vector2(
		clampf(point.x, 0.0, CANVAS_SIZE.x), clampf(point.y, 0.0, CANVAS_SIZE.y)
	)
	beat["x"] = bounded.x
	beat["y"] = bounded.y
	return bounded


static func link_beats(campaign: Dictionary, from_id: String, to_id: String) -> bool:
	if from_id == to_id:
		return false
	var source := beat_by_id(campaign, from_id)
	if source.is_empty() or beat_by_id(campaign, to_id).is_empty():
		return false
	var next_ids: Array = source["next_ids"]
	if next_ids.has(to_id):
		return false
	next_ids.append(to_id)
	return true


static func unlink_beats(campaign: Dictionary, from_id: String, to_id: String) -> bool:
	var source := beat_by_id(campaign, from_id)
	if source.is_empty():
		return false
	var next_ids: Array = source["next_ids"]
	var index := next_ids.find(to_id)
	if index < 0:
		return false
	next_ids.remove_at(index)
	return true


static func remove_beat(campaign: Dictionary, id: String) -> bool:
	ensure_campaign(campaign)
	var beats: Array = campaign["beats"]
	var removed := false
	for index in range(beats.size() - 1, -1, -1):
		if String((beats[index] as Dictionary)["id"]) == id:
			beats.remove_at(index)
			removed = true
	if not removed:
		return false
	for value in beats:
		var next_ids: Array = (value as Dictionary)["next_ids"]
		while next_ids.has(id):
			next_ids.erase(id)
	return true
