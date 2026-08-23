extends RefCounted

## What reaches the table's screen.
##
## Every case here is really the same case: something the GM knows must not
## arrive on the player display unless the GM sent it. A regression in this file
## is a regression the room can read across the table.

const Harness := preload("res://tests/harness.gd")


static func _characters() -> Dictionary:
	return {
		"rache":
		{"id": "rache", "name": "Rache", "side": "party", "hp": 30, "max_hp": 40},
		"booster":
		{"id": "booster", "name": "Booster", "side": "hostile", "hp": 9, "max_hp": 40},
		"sniper":
		{"id": "sniper", "name": "Rooftop Sniper", "side": "hostile", "hp": 25, "max_hp": 25},
	}


static func _location() -> Dictionary:
	return {
		"id": "parkade",
		"name": "Kabuki Parkade",
		"grid_width": 16,
		"grid_height": 16,
		"tile_metres": 2.0,
		"layers": 3,
		"tiles": [{"x": 0, "z": 0, "layer": 0, "tile_id": "deck"}],
		"props": [],
		"gm_only_note": "the sniper is a decoy",
		"units":
		[
			{"id": "u-rache", "character_id": "rache", "x": 2, "z": 2, "layer": 0},
			{"id": "u-booster", "character_id": "booster", "x": 5, "z": 5, "layer": 0},
			{"id": "u-sniper", "character_id": "sniper", "x": 9, "z": 1, "layer": 1, "hidden": true},
		],
	}


static func _snapshot() -> Dictionary:
	return {
		"round": 2,
		"current_actor_id": "u-rache",
		"initiative":
		[
			{"actor_id": "u-sniper", "name": "Rooftop Sniper", "score": 19},
			{"actor_id": "u-rache", "name": "Rache", "score": 15},
			{"actor_id": "u-booster", "name": "Booster", "score": 8},
		],
		"actors":
		[
			{"id": "u-rache", "hp": 30, "max_hp": 40, "wound_state": "lightly_wounded"},
			{"id": "u-booster", "hp": 9, "max_hp": 40, "wound_state": "seriously_wounded"},
			{"id": "u-sniper", "hp": 25, "max_hp": 25, "wound_state": "unhurt"},
		],
		"card":
		{
			"title": "HIT",
			"tone": "hit",
			"attacker": "Rache",
			"target": "Booster",
			"weapon": "Heavy Pistol",
			"lines": PackedStringArray(["Attack: base 12 + d10 7 = 19", "Armor: 14 - SP 7 = 7"]),
		},
	}


static func _compose(options := {}) -> Dictionary:
	return PlayerView.compose(_snapshot(), _location(), _characters(), [], options)


static func _ids(rows: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for row in rows:
		ids.append(String((row as Dictionary)["id"]))
	return ids


static func run(h: Harness) -> void:
	h.describe("player view")

	h.it("draws the units the GM has not held back")
	var view := _compose()
	h.equal(_ids(view["units"]), PackedStringArray(["u-rache", "u-booster"]), "units")
	h.not_contains(view["visuals"].keys(), "u-sniper", "no visual for a hidden unit")

	h.it("drops a hidden unit from the turn order too")
	# A name in the initiative rail is as much of a tell as a token on the board.
	h.equal(_ids(view["initiative"]), PackedStringArray(["u-rache", "u-booster"]), "order")

	h.it("prints party HP and only a word for the opposition")
	var party: Dictionary = view["initiative"][0]
	var enemy: Dictionary = view["initiative"][1]
	h.equal(party["condition"], "30 / 40", "the party reads its own numbers")
	# 9 of 40 is under a quarter left, which is the last band before down.
	h.equal(enemy["condition"], "Badly hurt", "an enemy reads as a condition")

	h.it("shows enemy HP when the GM turns it on")
	var open_books := _compose({"show_enemy_hp": true})
	h.equal((open_books["initiative"][1] as Dictionary)["condition"], "9 / 40", "enemy HP")

	h.it("rounds an enemy's bar rather than reporting it exactly")
	# 9 of 40 is 0.225, which would draw a bar precise enough to read back as HP.
	h.equal((view["visuals"]["u-booster"] as Dictionary)["hp_ratio"], 0.25, "rounded")
	h.equal((open_books["visuals"]["u-booster"] as Dictionary)["hp_ratio"], 0.225, "exact")
	h.equal((view["visuals"]["u-rache"] as Dictionary)["hp_ratio"], 0.75, "the party is exact")

	h.it("keeps the arithmetic off the table's screen by default")
	h.equal(String((view["headline"] as Dictionary)["title"]), "HIT", "the outcome carries")
	h.equal((view["headline"] as Dictionary)["lines"], PackedStringArray(), "the working does not")
	var shown := _compose({"show_math": true})
	h.equal((shown["headline"] as Dictionary)["lines"].size(), 2, "unless the GM asks")

	h.it("rebuilds the terrain rather than passing the location through")
	var board: Dictionary = view["board"]
	h.not_contains(board.keys(), "gm_only_note", "a GM key cannot ride along")
	h.not_contains(board.keys(), "units", "units travel filtered, not in the terrain")
	h.equal(board["grid_width"], 16, "grid width")
	h.equal((board["tiles"] as Array).size(), 1, "tiles")

	h.it("marks whose turn it is")
	h.equal((view["initiative"][0] as Dictionary)["current"], true, "the acting unit")
	h.equal((view["initiative"][1] as Dictionary)["current"], false, "everyone else")

	h.it("works before initiative, when there is no encounter yet")
	var setup := PlayerView.compose({}, _location(), _characters(), [])
	h.equal(setup["round"], 0, "round")
	h.equal(setup["initiative"], [], "no turn order")
	h.equal(setup["headline"], {}, "no card")
	h.equal(_ids(setup["units"]), PackedStringArray(["u-rache", "u-booster"]), "units still draw")

	h.it("reads its settings off the location")
	var location := _location()
	h.equal(PlayerView.options_for(location)["show_enemy_hp"], false, "default")
	location["player_display"] = {"show_enemy_hp": true}
	h.equal(PlayerView.options_for(location)["show_enemy_hp"], true, "stored")
	h.equal(PlayerView.options_for(location)["show_math"], false, "unstored keys keep the default")

	h.it("has a word for every state of health")
	h.equal(PlayerView.condition_word(1.0, "unhurt"), "Untouched", "full")
	h.equal(PlayerView.condition_word(0.8, "lightly_wounded"), "Steady", "lightly")
	h.equal(PlayerView.condition_word(0.4, "seriously_wounded"), "Hurt", "hurt")
	h.equal(PlayerView.condition_word(0.1, "seriously_wounded"), "Badly hurt", "badly")
	h.equal(PlayerView.condition_word(0.0, "mortally_wounded"), "Down", "down")
	h.equal(PlayerView.condition_word(0.5, "dead"), "Dead", "dead outranks the ratio")
