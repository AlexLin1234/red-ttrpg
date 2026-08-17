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
