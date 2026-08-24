extends RefCounted

## One field over the whole campaign.
##
## What these cases protect: everything in a save is reachable by name, a name
## outranks a description that merely mentions it, and every row knows where it
## lives so the caller can actually go there.

const Harness := preload("res://tests/harness.gd")


static func _sources() -> Dictionary:
	return {
		"campaign":
		{
			"areas":
			[
				{"id": "watson", "name": "Watson", "control": "Maelstrom"},
				{"id": "pacifica", "name": "Pacifica", "control": "Voodoo Boys"},
			],
			"points_of_interest":
			[
				{"id": "clinic", "name": "Ross Clinic", "kind": "ripperdoc", "area_id": "watson"}
			],
			"hooks":
			[
				{
					"id": "hook-1",
					"title": "Pier Generator",
					"summary": "A Fixer wants the pier generator back online.",
					"area_id": "pacifica",
				}
			],
			"beats": [{"id": "beat-1", "title": "The client lies", "notes": "Arasaka is paying."}],
			"session_log": [{"session": 14, "text": "Doc Tallow took 22 from an autofire burst."}],
			"architectures": [{"id": "arch-1", "name": "Zetatech Substation", "floors": [{}, {}]}],
			"vehicles": [{"id": "car-1", "name": "Muscle Coupe", "sdp": 50, "sp": 10}],
		},
		"roster":
		{
			"characters":
			[
				{"id": "spike", "name": "Spike Adebayo", "role": "Solo", "kind": "pc"},
				{"id": "doc", "name": "Doc Tallow", "role": "Medtech", "kind": "pc"},
			]
		},
		"locations": [{"id": "parkade", "name": "Kabuki Parkade", "units": [{}, {}, {}]}],
		"items": [{"id": "item-1", "name": "Heavy Sidearm", "kind": "weapon", "price": 500}],
	}


static func _titles(rows: Array) -> PackedStringArray:
	var titles := PackedStringArray()
	for row in rows:
		titles.append(String((row as Dictionary)["title"]))
	return titles


static func _kinds(rows: Array) -> PackedStringArray:
	var kinds := PackedStringArray()
	for row in rows:
		kinds.append(String((row as Dictionary)["kind"]))
	return kinds


static func run(h: Harness) -> void:
	h.describe("campaign search")

	h.it("waits for something worth searching for")
	h.equal(CampaignSearch.query(_sources(), "").size(), 0, "empty")
	h.equal(CampaignSearch.query(_sources(), "a").size(), 0, "one letter is not a query")

	h.it("finds a character by name")
	var people := CampaignSearch.query(_sources(), "spike")
	h.equal(people.size(), 1, "one hit")
	var row: Dictionary = people[0]
	h.equal(row["kind"], "character", "kind")
	h.equal(row["screen"], "forge", "the sheet lives in the Forge")
	h.equal((row["target"] as Dictionary)["character_id"], "spike", "and the row says which one")

	h.it("reaches every kind of thing in the save")
	h.equal(_kinds(CampaignSearch.query(_sources(), "watson")), PackedStringArray(["area"]), "zone")
	h.equal(_kinds(CampaignSearch.query(_sources(), "ross")), PackedStringArray(["place"]), "place")
	h.equal(_kinds(CampaignSearch.query(_sources(), "pier")), PackedStringArray(["hook"]), "hook")
	h.equal(_kinds(CampaignSearch.query(_sources(), "client")), PackedStringArray(["beat"]), "beat")
	h.equal(_kinds(CampaignSearch.query(_sources(), "autofire")), PackedStringArray(["log"]), "log")
	h.equal(
		_kinds(CampaignSearch.query(_sources(), "kabuki")), PackedStringArray(["location"]), "board"
	)
	h.equal(
		_kinds(CampaignSearch.query(_sources(), "zetatech")),
		PackedStringArray(["architecture"]),
		"architecture"
	)
	h.equal(
		_kinds(CampaignSearch.query(_sources(), "coupe")), PackedStringArray(["vehicle"]), "vehicle"
	)
	h.equal(
		_kinds(CampaignSearch.query(_sources(), "sidearm")), PackedStringArray(["item"]), "item"
	)

	h.it("puts the thing that is named that above the thing that mentions it")
	# "Doc Tallow" is a character, and also the subject of a session log line.
	var tallow := CampaignSearch.query(_sources(), "tallow")
	h.equal(tallow.size(), 2, "both are found")
	h.equal(String((tallow[0] as Dictionary)["kind"]), "character", "the person comes first")
	h.equal(String((tallow[1] as Dictionary)["kind"]), "log", "the mention comes second")

	h.it("prefers a name that starts with the query")
	var scores := CampaignSearch.query(_sources(), "pac")
	h.equal(_titles(scores), PackedStringArray(["Pacifica"]), "prefix hit")
	h.check(
		CampaignSearch.score("Pacifica", "pac") > CampaignSearch.score("Kabuki Pacifica", "pac"),
		"a prefix beats a match in the middle"
	)

	h.it("is not case sensitive")
	h.equal(CampaignSearch.query(_sources(), "SPIKE").size(), 1, "upper")
	h.equal(CampaignSearch.query(_sources(), "sPiKe").size(), 1, "mixed")

	h.it("says nothing when there is nothing")
	h.equal(CampaignSearch.query(_sources(), "arasaka tower").size(), 0, "no hits")

	h.it("searches whatever it is given and skips what it is not")
	var partial := {"roster": {"characters": [{"id": "x", "name": "Spike", "role": "Solo"}]}}
	h.equal(CampaignSearch.query(partial, "spike").size(), 1, "a roster alone still searches")

	h.it("scores the way the list is ordered")
	h.equal(CampaignSearch.score("Watson", "watson"), 100, "exact")
	h.equal(CampaignSearch.score("Watson", "wat"), 80, "prefix")
	h.check(CampaignSearch.score("Kabuki Parkade", "parkade") > 0, "contained")
	h.equal(CampaignSearch.score("Watson", "pacifica"), -1, "absent")
