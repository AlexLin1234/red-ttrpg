extends RefCounted

## Driving a vehicle onto the encounter board.
##
## The rules these cases exist to protect: a vehicle on the board is a unit and
## not a fourth kind of thing, so everything that already knows how to shoot a
## Solo knows how to shoot a car; it crosses the board at its own speed rather
## than at a walking pace; and the driver lends it their REF, because a car is
## only as quick off the mark as whoever is behind the wheel.

const Harness := preload("res://tests/harness.gd")
const StoreScript := preload("res://scripts/campaign/store.gd")


static func _driver() -> Dictionary:
	return {"id": "spike", "name": "Spike", "stats": {"REF": 7, "MOVE": 6}, "hp": 40, "max_hp": 40}


static func run(h: Harness) -> void:
	h.describe("vehicles on the board")

	_roster_entry(h)
	_speed(h)
	_deploying(h)
	_returning(h)


static func _roster_entry(h: Harness) -> void:
	h.it("turns a vehicle into a sheet the rest of the app already understands")
	var car := Vehicles.from_template("compact", "Getaway")
	var entry := Vehicles.as_roster_entry(car, _driver())
	h.equal(int(entry["max_hp"]), int(car["max_sdp"]), "SDP is where its HP goes")
	h.equal(int(entry["hp"]), int(car["sdp"]), "and what it has left")
	h.contains(entry["tags"], "VEHICLE", "marked for what it is")
	h.equal(String(entry["vehicle_id"]), String(car["id"]), "it remembers which car it is")

	h.it("plates every hit location rather than leaving the car an unarmoured head")
	for location in Resolver.HIT_LOCATIONS:
		h.equal(
			int((entry["armor"][location] as Dictionary)["sp"]),
			int(car["sp"]),
			"%s is plated" % location,
		)

	h.it("takes REF from the driver, because the car does not have one")
	h.equal(int((entry["stats"] as Dictionary)["REF"]), 7, "the driver's reflexes")

	h.it("leaves a parked car with nothing, so it acts last and does not move")
	var parked := Vehicles.as_roster_entry(car, {})
	h.equal(int((parked["stats"] as Dictionary)["REF"]), 0, "nobody behind the wheel")
	h.equal(String(parked["driver_id"]), "", "and no driver recorded")

	h.it("names a driven car after the person driving it")
	h.contains(String(entry["name"]), "Spike", "so the initiative list says who is in it")
	h.equal(String(parked["name"]), "Getaway", "a parked one is just the car")

	h.it("takes the side of whoever is driving it")
	# A getaway car the party drove in reading as neutral in the turn order is
	# exactly the thing a GM should not have to remember mid-fight.
	var party_driver := _driver()
	party_driver["side"] = "party"
	h.equal(String(Vehicles.as_roster_entry(car, party_driver)["side"]), "party", "party car")
	var hostile_driver := _driver()
	hostile_driver["side"] = "hostile"
	var enemy := Vehicles.as_roster_entry(car, hostile_driver)
	h.equal(String(enemy["side"]), "hostile", "enemy car")
	h.contains(enemy["tags"], "HOSTILE", "and tagged for it")
	h.equal(String(parked["side"]), "neutral", "a parked car belongs to nobody")

	h.it("recognises a vehicle sheet from either the id or the tag")
	h.equal(Vehicles.is_vehicle(entry), true, "by vehicle_id")
	h.equal(Vehicles.is_vehicle({"tags": ["VEHICLE"]}), true, "by tag")
	h.equal(Vehicles.is_vehicle(_driver()), false, "a person is not a car")


static func _speed(h: Harness) -> void:
	h.it("crosses the board at the vehicle's speed rather than at a walking pace")
	# The bug this exists for: a car that moves MOVE × 2 metres is moving at
	# about the pace of somebody jogging beside it.
	var car := Vehicles.from_template("muscle")
	var entry := Vehicles.as_roster_entry(car, _driver())
	var encounter := Encounter.new(
		TablesDefault.tables(), {"car": CampaignFixtures.actor_input(entry)}
	)
	h.equal(
		encounter.move_allowance("car"),
		float(int(car["speed_m"])),
		"one Move Action is the car's own reach",
	)

	h.it("still reads MOVE for anything that is not a vehicle")
	var people := Encounter.new(
		TablesDefault.tables(), {"spike": CampaignFixtures.actor_input(_driver())}
	)
	h.equal(
		people.move_allowance("spike"),
		6.0 * Encounter.METRES_PER_MOVE,
		"MOVE × 2 metres, unchanged",
	)

	h.it("gives a vehicle saved before speed existed a usable default")
	var old_save := {"id": "v9", "name": "Old", "sdp": 30, "max_sdp": 30, "sp": 5, "seats": 4}
	var adopted := Vehicles.as_roster_entry(old_save, {})
	h.equal(int(adopted["speed_m"]), Vehicles.DEFAULT_SPEED_M, "moves at the default rather than not at all")

	h.it("gives every built-in template a speed")
	for entry_template in Vehicles.TEMPLATES:
		var spec: Dictionary = entry_template
		h.check(int(spec.get("speed_m", 0)) > 0, "%s has a speed" % String(spec["key"]))


static func _deploying(h: Harness) -> void:
	h.it("puts a garaged vehicle on the roster with a driver in it")
	var store := StoreScript.new()
	var car := Vehicles.from_template("van", "Crew Van")
	store.campaign = {
		"name": "Test",
		"clock": {"year": 2045, "month": 1, "day": 1, "hour": 12, "minute": 0},
		"sessions": 1,
		"session_log": [],
		"vehicles": [car],
	}
	store.roster = {"characters": [_driver()]}
	store.path = "user://test.red"

	var deployed: Dictionary = store.deploy_vehicle(String(car["id"]), "spike")
	h.equal(bool(deployed["ok"]), true, "driven in")
	var actor_entry: Dictionary = deployed["character"]
	h.equal(store.character_by_id(String(actor_entry["id"])).is_empty(), false, "it is on the roster")
	h.equal((store.campaign["session_log"] as Array).size(), 1, "and the log says so")

	h.it("refuses to drive the same vehicle in twice")
	var again: Dictionary = store.deploy_vehicle(String(car["id"]), "spike")
	h.equal(bool(again["ok"]), false, "already on the board")

	h.it("refuses a vehicle or a driver that does not exist")
	h.equal(bool(store.deploy_vehicle("nope", "spike")["ok"]), false, "no such vehicle")
	h.equal(bool(store.deploy_vehicle(String(car["id"]), "ghost")["ok"]), false, "no such driver")

	h.it("lets a car be parked with nobody in it")
	var parked_car := Vehicles.from_template("compact", "Parked")
	(store.campaign["vehicles"] as Array).append(parked_car)
	var parked: Dictionary = store.deploy_vehicle(String(parked_car["id"]), "")
	h.equal(bool(parked["ok"]), true, "a parked car is still a thing on the board")


static func _returning(h: Harness) -> void:
	h.it("writes damage taken on the board back to the garage")
	# An encounter is a scratch copy replayed more often than it counts, so the
	# garage is only written when the GM saves the results.
	var store := StoreScript.new()
	var car := Vehicles.from_template("armored", "Bank Run")
	store.campaign = {
		"name": "Test",
		"clock": {"year": 2045, "month": 1, "day": 1, "hour": 12, "minute": 0},
		"sessions": 1,
		"session_log": [],
		"vehicles": [car],
	}
	store.roster = {"characters": []}
	store.path = "user://test.red"

	var full := int(car["sdp"])
	store.return_vehicle({"vehicle_id": String(car["id"]), "hp": full - 25})
	h.equal(int(store.vehicle_by_id(String(car["id"]))["sdp"]), full - 25, "the dents stayed")

	h.it("never drives SDP below zero or above the frame")
	store.return_vehicle({"vehicle_id": String(car["id"]), "hp": -50})
	h.equal(int(store.vehicle_by_id(String(car["id"]))["sdp"]), 0, "a wreck is zero, not negative")
	store.return_vehicle({"vehicle_id": String(car["id"]), "hp": 9999})
	h.equal(int(store.vehicle_by_id(String(car["id"]))["sdp"]), full, "and never more than it was built with")

	h.it("ignores an actor that is not a vehicle at all")
	h.equal(store.return_vehicle({"hp": 10}), false, "nothing to write back")
