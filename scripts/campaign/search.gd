class_name CampaignSearch
extends RefCounted

## One field over everything in the campaign.
##
## A GM mid-session knows the name of the thing they want and not which of nine
## screens it lives on. Everything in a `.red` is already in memory, so the
## search is a pass over dictionaries rather than an index: characters, zones,
## places, beats, the session log, job hooks, boards, architectures, vehicles,
## and the item catalog.
##
## Pure, so it is testable without a screen: it is handed the campaign and hands
## back rows, each carrying where it lives so the caller can go there.

const LIMIT := 40

## What each kind of result is called, and where it lives.
const SOURCES := {
	"character": {"label": "Character", "screen": "forge"},
	"area": {"label": "Zone", "screen": "city"},
	"place": {"label": "Place", "screen": "city"},
	"hook": {"label": "Job hook", "screen": "city"},
	"beat": {"label": "Beat", "screen": "city"},
	"log": {"label": "Session log", "screen": "library"},
	"location": {"label": "Board", "screen": "location"},
	"architecture": {"label": "Architecture", "screen": "netrun"},
	"vehicle": {"label": "Vehicle", "screen": "vehicles"},
	"item": {"label": "Item", "screen": "workshop"},
}


static func label_for(kind: String) -> String:
	return String((SOURCES.get(kind, {}) as Dictionary).get("label", kind.capitalize()))


static func screen_for(kind: String) -> String:
	return String((SOURCES.get(kind, {}) as Dictionary).get("screen", "library"))


## How well a phrase answers a query. Negative means it does not.
##
## Deliberately blunt: a GM typing three letters wants the thing whose name
## starts with them, and after that the thing that contains them early.
static func score(text: String, query: String) -> int:
	if query == "":
		return 0
	var haystack := text.to_lower()
	var needle := query.to_lower()
	if haystack == needle:
		return 100
	if haystack.begins_with(needle):
		return 80
	var at := haystack.find(needle)
	if at < 0:
		return -1
	return maxi(10, 60 - at)


static func _row(kind: String, id: String, title: String, subtitle: String, target: Dictionary) -> Dictionary:
	var row := {
		"kind": kind,
		"id": id,
		"title": title,
		"subtitle": subtitle,
		"label": label_for(kind),
		"screen": screen_for(kind),
		"target": target,
		"score": 0,
	}
	return row


## Everything in the campaign that answers [param query].
##
## [param sources] is {campaign, roster, locations, items}; a missing key simply
## contributes nothing, so a caller with no item catalog loaded still searches
## the rest.
static func query(sources: Dictionary, text: String) -> Array[Dictionary]:
	var trimmed := text.strip_edges()
	if trimmed.length() < 2:
		return [] as Array[Dictionary]

	var campaign: Dictionary = sources.get("campaign", {})
	var roster: Dictionary = sources.get("roster", {})
	var rows: Array[Dictionary] = []

	for entry in roster.get("characters", []):
		var character: Dictionary = entry
		rows.append(
			_row(
				"character",
				String(character.get("id", "")),
				String(character.get("name", "")),
				"%s · %s" % [
					String(character.get("role", "—")), String(character.get("kind", "npc")).to_upper()
				],
				{"character_id": String(character.get("id", ""))},
			)
		)

	for entry in campaign.get("areas", []):
		var area: Dictionary = entry
		rows.append(
			_row(
				"area",
				String(area.get("id", "")),
				String(area.get("name", "")),
				String(area.get("control", "Unclaimed")),
				{"area_id": String(area.get("id", ""))},
			)
		)

	for entry in campaign.get("points_of_interest", []):
		var poi: Dictionary = entry
		rows.append(
			_row(
				"place",
				String(poi.get("id", "")),
				String(poi.get("name", "")),
				String(poi.get("kind", "")),
				{"poi_id": String(poi.get("id", ""))},
			)
		)

	for entry in campaign.get("hooks", []):
		var hook: Dictionary = entry
		rows.append(
			_row(
				"hook",
				String(hook.get("id", "")),
				String(hook.get("title", hook.get("name", ""))),
				String(hook.get("summary", hook.get("detail", ""))),
				{"area_id": String(hook.get("area_id", ""))},
			)
		)

	for entry in campaign.get("beats", []):
		var beat: Dictionary = entry
		rows.append(
			_row(
				"beat",
				String(beat.get("id", "")),
				String(beat.get("title", "")),
				String(beat.get("notes", "")),
				{"beat_id": String(beat.get("id", ""))},
			)
		)

	for entry in campaign.get("session_log", []):
		var line: Dictionary = entry
		rows.append(
			_row(
				"log",
				"",
				String(line.get("text", "")),
				"Session %d" % int(line.get("session", 0)),
				{},
			)
		)

	for entry in sources.get("locations", []):
		var location: Dictionary = entry
		rows.append(
			_row(
				"location",
				String(location.get("id", "")),
				String(location.get("name", "")),
				"%d units" % (location.get("units", []) as Array).size(),
				{"location_id": String(location.get("id", ""))},
			)
		)

	for entry in campaign.get("architectures", []):
		var architecture: Dictionary = entry
		rows.append(
			_row(
				"architecture",
				String(architecture.get("id", "")),
				String(architecture.get("name", "")),
				"%d floors" % (architecture.get("floors", []) as Array).size(),
				{"architecture_id": String(architecture.get("id", ""))},
			)
		)

	for entry in campaign.get("vehicles", []):
		var vehicle: Dictionary = entry
		rows.append(
			_row(
				"vehicle",
				String(vehicle.get("id", "")),
				String(vehicle.get("name", "")),
				"SDP %d · SP %d" % [int(vehicle.get("sdp", 0)), int(vehicle.get("sp", 0))],
				{"vehicle_id": String(vehicle.get("id", ""))},
			)
		)

	for entry in sources.get("items", []):
		var item: Dictionary = entry
		rows.append(
			_row(
				"item",
				String(item.get("id", "")),
				String(item.get("name", "")),
				"%s · %deb" % [String(item.get("kind", "")), int(item.get("price", 0))],
				{"item_id": String(item.get("id", ""))},
			)
		)

	var hits: Array[Dictionary] = []
	for entry in rows:
		var row: Dictionary = entry
		var title_score := score(String(row["title"]), trimmed)
		var subtitle_score := score(String(row["subtitle"]), trimmed)
		if title_score < 0 and subtitle_score < 0:
			continue
		# A name is worth more than a description that happens to mention it.
		row["score"] = maxi(title_score * 2, subtitle_score)
		hits.append(row)

	hits.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["score"]) != int(b["score"]):
				return int(a["score"]) > int(b["score"])
			if String(a["kind"]) != String(b["kind"]):
				return String(a["kind"]) < String(b["kind"])
			return String(a["title"]) < String(b["title"])
	)
	return hits.slice(0, LIMIT) as Array[Dictionary]
