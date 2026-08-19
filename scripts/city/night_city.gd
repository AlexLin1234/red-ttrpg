class_name NightCity
extends RefCounted

## The built-in Night City map.
##
## The geometry is a stylised block diagram, not a survey — angular plates laid
## out on a 1000 × 700 grid, the way the mockup draws it. All descriptive text is
## original: Redline ships no book prose, the same way it ships no book tables. A
## GM overrides control, danger and notes per campaign.

const MAP_SIZE := Vector2(1000, 700)

const ZONE_LABELS := {
	"corporate": "Corporate Zone",
	"combat": "Combat Zone",
	"residential": "Residential",
	"industrial": "Industrial",
	"reclaimed": "Reclaimed",
	"outland": "Outland",
}


static func districts() -> Array:
	return [
		{
			"id": "watson",
			"name": "Watson",
			"subtitle": "Maelstrom · Heat 4",
			"zone_type": "combat",
			"control": "Maelstrom",
			"danger": 4,
			"population": 310000,
			"law_response": "Slow",
			"net_density": "High",
			"description":
			"Half-finished towers the developers walked away from, now wired into somebody else. "
			+ "The markets run all night under the parkades and nobody asks where the stock came from. "
			+ "Maelstrom took the north blocks two winters ago and has not been pushed back since.",
			"polygon": PackedVector2Array([
				Vector2(40, 380), Vector2(300, 380), Vector2(300, 520),
				Vector2(250, 660), Vector2(40, 660),
			]),
			"label": Vector2(60, 604),
		},
		{
			"id": "heywood",
			"name": "Heywood",
			"subtitle": "Valentinos · Heat 2",
			"zone_type": "residential",
			"control": "Valentinos",
			"danger": 3,
			"population": 480000,
			"law_response": "Moderate",
			"net_density": "Medium",
			"description":
			"The part of the city that still behaves like a neighbourhood. Family money, block parties, "
			+ "and a very clear understanding of which streets are spoken for. Outsiders get one polite warning.",
			"polygon": PackedVector2Array([
				Vector2(300, 380), Vector2(560, 380), Vector2(560, 660),
				Vector2(250, 660), Vector2(300, 520),
			]),
			"label": Vector2(320, 604),
		},
		{
			"id": "pacifica",
			"name": "Pacifica",
			"subtitle": "Combat Zone · Heat 5",
			"zone_type": "combat",
			"control": "Voodoo Boys",
			"danger": 5,
			"population": 6000,
			"law_response": "Never",
			"net_density": "High",
			"description":
			"An abandoned resort megaproject. The Voodoo Boys hold the drowned levels, nobody else claims "
			+ "the surface. Rain never fully stops here — the runoff is unseeded cyberware and worse. "
			+ "Bring your own light and your own way out.",
			"polygon": PackedVector2Array([
				Vector2(560, 380), Vector2(860, 380), Vector2(900, 500),
				Vector2(820, 660), Vector2(560, 660),
			]),
			"label": Vector2(580, 604),
		},
		{
			"id": "city-center",
			"name": "City Center",
			"subtitle": "Corporate · Heat 1",
			"zone_type": "corporate",
			"control": "Arasoma & partners",
			"danger": 2,
			"population": 92000,
			"law_response": "Immediate",
			"net_density": "Saturated",
			"description":
			"Glass, private security, and a skyline that bills by the hour. Everything is monitored and "
			+ "most of it is deniable. Violence here is a paperwork problem, which makes it more expensive, "
			+ "not less likely.",
			"polygon": PackedVector2Array([
				Vector2(300, 150), Vector2(560, 150), Vector2(560, 380), Vector2(300, 380),
			]),
			"label": Vector2(320, 324),
		},
		{
			"id": "santo-domingo",
			"name": "Santo Domingo",
			"subtitle": "Industrial · Heat 3",
			"zone_type": "industrial",
			"control": "Corporate contractors",
			"danger": 3,
			"population": 265000,
			"law_response": "Slow",
			"net_density": "Low",
			"description":
			"Fabrication plants and the housing built to keep them staffed. The grid browns out on a "
			+ "schedule everyone has memorised. Union muscle and corporate muscle share the same parking "
			+ "lot and mostly leave each other alone.",
			"polygon": PackedVector2Array([
				Vector2(560, 150), Vector2(820, 150), Vector2(860, 380), Vector2(560, 380),
			]),
			"label": Vector2(580, 324),
		},
		{
			"id": "westbrook",
			"name": "Westbrook",
			"subtitle": "Nightlife · Heat 2",
			"zone_type": "residential",
			"control": "Tyger Claws",
			"danger": 3,
			"population": 198000,
			"law_response": "Bought",
			"net_density": "High",
			"description":
			"Where the money goes to be seen. Clubs, clinics, and the fixers who work the gap between them. "
			+ "The Tyger Claws keep it orderly the way a bouncer keeps a door orderly.",
			"polygon": PackedVector2Array([
				Vector2(560, 40), Vector2(820, 40), Vector2(820, 150), Vector2(560, 150),
			]),
			"label": Vector2(578, 100),
		},
		{
			"id": "north-oak",
			"name": "North Oak",
			"subtitle": "Private · Heat 1",
			"zone_type": "corporate",
			"control": "Private estates",
			"danger": 1,
			"population": 14000,
			"law_response": "Immediate",
			"net_density": "Private",
			"description":
			"Above the smog line. Gate codes, private roads, and response times measured against a contract. "
			+ "If you are here without an invitation, that has already been noticed.",
			"polygon": PackedVector2Array([
				Vector2(300, 40), Vector2(560, 40), Vector2(560, 150), Vector2(300, 150),
			]),
			"label": Vector2(318, 100),
		},
		{
			"id": "badlands",
			"name": "Badlands",
			"subtitle": "Nomad · Heat 2",
			"zone_type": "outland",
			"control": "Nomad families",
			"danger": 3,
			"population": 41000,
			"law_response": "None",
			"net_density": "None",
			"description":
			"Dust, solar farms, and the convoy routes that keep the city fed. The families run their own law "
			+ "out here and it is enforced faster than anything inside the ring.",
			"polygon": PackedVector2Array([
				Vector2(820, 40), Vector2(960, 40), Vector2(960, 660), Vector2(820, 660),
				Vector2(900, 500), Vector2(860, 380), Vector2(820, 150),
			]),
			"label": Vector2(838, 604),
		},
	]


static func by_id(id: String) -> Dictionary:
	for district in districts():
		if String((district as Dictionary)["id"]) == id:
			return district
	return {}


static func centroid(district: Dictionary) -> Vector2:
	var total := Vector2.ZERO
	var polygon: PackedVector2Array = district["polygon"]
	for point in polygon:
		total += point
	return total / polygon.size()


## Fill and stroke for a district plate, brighter when it has focus.
static func zone_colors(zone_type: String, focused: bool) -> Dictionary:
	var fill := Color("121a24")
	var stroke := UI.RULE
	match zone_type:
		"combat":
			fill = Color("26161b")
			stroke = Color("4a2a2d")
		"corporate":
			fill = Color("141d29")
			stroke = Color("2b3b52")
		"industrial":
			fill = Color("161a20")
		"outland":
			fill = Color("171712")
			stroke = Color("2f2f22")
	if focused:
		if zone_type == "combat":
			return {"fill": Color("371d22"), "stroke": UI.ALERT_BRIGHT}
		return {"fill": Color("1c2836"), "stroke": UI.ACCENT}
	return {"fill": fill, "stroke": stroke}


const _WEATHER: Array = [
	{"condition": "Clear", "temperature_c": 22, "visibility_pct": 95},
	{"condition": "Smog", "temperature_c": 26, "visibility_pct": 55},
	{"condition": "Acid Rain", "temperature_c": 18, "visibility_pct": 40},
	{"condition": "Heavy Rain", "temperature_c": 16, "visibility_pct": 35},
	{"condition": "Dust Haze", "temperature_c": 30, "visibility_pct": 45},
	{"condition": "Cold Snap", "temperature_c": 8, "visibility_pct": 80},
]


static func roll_weather() -> Dictionary:
	return (_WEATHER[randi() % _WEATHER.size()] as Dictionary).duplicate()


# -- editable areas ----------------------------------------------------------
#
# Districts above are only the seed. Once a campaign is opened they are copied
# into `campaign.areas`, where the GM can edit, draw and delete them. Polygons
# are stored flat — [x, y, x, y, …] — because a PackedVector2Array does not
# survive a JSON round trip into the .red container.

const ZONE_TYPES: PackedStringArray = [
	"corporate", "combat", "residential", "industrial", "reclaimed", "outland"
]
const LAW_RESPONSES: PackedStringArray = [
	"Immediate", "Moderate", "Slow", "Bought", "Never", "None"
]
const NET_DENSITIES: PackedStringArray = [
	"Saturated", "High", "Medium", "Low", "Private", "None"
]


static func flatten(points: PackedVector2Array) -> Array:
	var flat: Array = []
	for point in points:
		flat.append(point.x)
		flat.append(point.y)
	return flat


static func points_of(area: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var flat: Array = area.get("polygon", [])
	var index := 0
	while index + 1 < flat.size():
		points.append(Vector2(float(flat[index]), float(flat[index + 1])))
		index += 2
	return points


static func label_of(area: Dictionary) -> Vector2:
	var label: Array = area.get("label", [])
	if label.size() < 2:
		return centroid_of(points_of(area))
	return Vector2(float(label[0]), float(label[1]))


static func centroid_of(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / points.size()


## Where a new zone's name sits: low and inside, the way the seeded plates read.
static func suggest_label(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var centre := centroid_of(points)
	var lowest := points[0].y
	for point in points:
		lowest = maxf(lowest, point.y)
	return Vector2(centre.x - 60.0, lowest - 40.0)


## The seed districts in the editable, JSON-safe shape.
static func default_areas() -> Array:
	var areas: Array = []
	for district in districts():
		var entry: Dictionary = district
		var area := entry.duplicate(true)
		area["polygon"] = flatten(entry["polygon"])
		area["label"] = [entry["label"].x, entry["label"].y]
		area["custom"] = false
		areas.append(area)
	return areas


## A blank area around a freshly drawn polygon.
static func new_area(points: PackedVector2Array) -> Dictionary:
	var label := suggest_label(points)
	return {
		"id": "area-%d" % Time.get_ticks_usec(),
		"name": "New Zone",
		"subtitle": "Unclaimed",
		"zone_type": "residential",
		"control": "Unclaimed",
		"danger": 2,
		"population": 10000,
		"law_response": "Moderate",
		"net_density": "Medium",
		"description": "",
		"polygon": flatten(points),
		"label": [label.x, label.y],
		"custom": true,
	}


# -- points of interest ------------------------------------------------------
#
# A POI is a pin dropped inside a zone. It optionally links to a location — one
# of the isometric boards in the campaign — which is what turns "the Kabuki
# parkade is here" into something the party can walk into.

const POI_KINDS: PackedStringArray = [
	"job", "contact", "shop", "clinic", "safehouse", "corp", "hazard", "landmark"
]

const POI_COLORS := {
	"job": Color("93bce2"),
	"contact": Color("6fbf8b"),
	"shop": Color("d9b45c"),
	"clinic": Color("7fd4c8"),
	"safehouse": Color("8f9bd6"),
	"corp": Color("b0bcc9"),
	"hazard": Color("bb5451"),
	"landmark": Color("c58fd6"),
}


static func poi_color(kind: String) -> Color:
	return POI_COLORS.get(kind, UI.ACCENT)


## Which zone contains this point, or "" when it sits on bare ground.
static func area_at(areas: Array, point: Vector2) -> String:
	for area in areas:
		var entry: Dictionary = area
		if Geometry2D.is_point_in_polygon(point, points_of(entry)):
			return String(entry["id"])
	return ""


static func new_poi(point: Vector2, area_id: String) -> Dictionary:
	return {
		"id": "poi-%d" % Time.get_ticks_usec(),
		"name": "New Place",
		"kind": "landmark",
		"area_id": area_id,
		"x": point.x,
		"y": point.y,
		"description": "",
		# Empty until the GM links or builds a board for it.
		"location_id": "",
	}


static func poi_position(poi: Dictionary) -> Vector2:
	return Vector2(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)))


## Move a place on the city map and update the zone that now contains it.
## Clamping keeps a dragged pin inside the saved map coordinate system.
static func relocate_poi(poi: Dictionary, point: Vector2, areas: Array) -> Vector2:
	var bounded := Vector2(
		clampf(point.x, 0.0, MAP_SIZE.x), clampf(point.y, 0.0, MAP_SIZE.y)
	)
	poi["x"] = bounded.x
	poi["y"] = bounded.y
	poi["area_id"] = area_at(areas, bounded)
	return bounded


# -- reshaping ----------------------------------------------------------------


static func set_points(area: Dictionary, points: PackedVector2Array) -> void:
	area["polygon"] = flatten(points)


## Slide the whole zone, label included, so a moved district keeps its name in
## the same spot relative to its outline.
static func move_area(area: Dictionary, delta: Vector2) -> void:
	var moved := PackedVector2Array()
	for point in points_of(area):
		moved.append(point + delta)
	set_points(area, moved)
	var label := label_of(area) + delta
	area["label"] = [label.x, label.y]


## Add a corner after [param index]. Used when the GM clicks an edge midpoint.
static func insert_corner(points: PackedVector2Array, index: int, at: Vector2) -> PackedVector2Array:
	var out := points.duplicate()
	out.insert(clampi(index + 1, 0, out.size()), at)
	return out


## Drop a corner. A polygon needs three, so the last three are held.
static func remove_corner(points: PackedVector2Array, index: int) -> PackedVector2Array:
	if points.size() <= 3 or index < 0 or index >= points.size():
		return points
	var out := points.duplicate()
	out.remove_at(index)
	return out


## Midpoint of every edge, in order, for drawing the "add a corner" handles.
static func edge_midpoints(points: PackedVector2Array) -> PackedVector2Array:
	var mids := PackedVector2Array()
	for index in points.size():
		mids.append((points[index] + points[(index + 1) % points.size()]) * 0.5)
	return mids
