extends RefCounted

## Vehicles, and the chase they exist for.
##
## The rules the cases here pin: the gap is the whole state of a chase, a
## manoeuvre buys an edge by risking something, and both cars take damage
## through the same events a person does — so all of it undoes.

const Harness := preload("res://tests/harness.gd")


static func _pursuer(overrides := {}) -> Dictionary:
	var side := {
		"vehicle": Vehicles.from_template("muscle", "NCPD Cruiser"),
		"driver_name": "Sgt. Halvorsen",
		"driver_skill": 10,
	}
	side.merge(overrides, true)
	return side


static func _quarry(overrides := {}) -> Dictionary:
	var side := {
		"vehicle": Vehicles.from_template("bike", "Stolen Bike"),
		"driver_name": "Spike",
		"driver_skill": 10,
	}
	side.merge(overrides, true)
	return side


static func _chase(rolls: Array[int] = [], gap := -1) -> Chase:
	return Chase.new(_pursuer(), _quarry(), Dice.FixedRandom.new(rolls), gap)


static func run(h: Harness) -> void:
	h.describe("vehicles and chases")

	_garage(h)
	_gap(h)
	_maneuvers(h)
	_endings(h)


static func _garage(h: Harness) -> void:
	h.it("builds a vehicle from a template")
	var bike := Vehicles.from_template("bike")
	h.equal(bike["name"], "Street Bike", "name")
	h.equal(bike["sdp"], 25, "sdp")
	h.equal(bike["max_sdp"], 25, "max sdp")
	h.equal(bike["handling"], 3, "handling")

	h.it("presents a vehicle as an actor the damage events already understand")
	var actor := Vehicles.as_actor(bike)
	h.equal(actor["hp"], 25, "hp is sdp")
	h.equal(actor["max_hp"], 25, "max hp")
	h.equal((actor["armor"] as Dictionary)["body"], 5, "sp is armour")
	h.equal(Vehicles.is_wrecked(actor), false, "intact")
	actor["hp"] = 0
	h.equal(Vehicles.is_wrecked(actor), true, "wrecked at zero")

	h.it("presents a parked vehicle as a cover block")
	var cover := Vehicles.as_cover(bike)
	h.equal(cover["material"], "Vehicle Hulk", "material")
	h.equal(cover["name"], "Street Bike", "the palette reads names, not labels")
	h.equal(cover["hp"], 25, "the block wrecks at the vehicle's SDP")
	h.equal(cover["sp"], 5, "and stops what its plating stops")

	h.it("offers only the manoeuvres the gap allows")
	var far := PackedStringArray()
	for entry in Vehicles.maneuvers_at(5):
		far.append(String((entry as Dictionary)["key"]))
	h.not_contains(far, "ram", "cannot ram from five bands back")
	h.not_contains(far, "sideswipe", "nor sideswipe")
	var alongside := PackedStringArray()
	for entry in Vehicles.maneuvers_at(0):
		alongside.append(String((entry as Dictionary)["key"]))
	h.contains(alongside, "ram", "alongside, ramming is on the table")
	h.contains(alongside, "sideswipe", "and so is sideswiping")


static func _gap(h: Harness) -> void:
	h.it("starts at the opening gap")
	var session := _chase()
	h.equal(session.gap(), 3, "gap")
	h.equal(session.snapshot()["round"], 1, "round")
	h.equal(session.outcome(), Vehicles.RUNNING, "outcome")

	h.it("opens the gap when the quarry wins the exchange")
	# Both drive 10; the bike's handling 3 beats the coupe's 2. A d10 of 4 for
	# the pursuer and 6 for the quarry is a margin of 3.
	var opening := _chase([4, 6])
	opening.exchange("steady", "steady")
	h.equal(opening.gap(), 6, "gap")
	h.equal(opening.snapshot()["round"], 2, "round")

	h.it("closes it when the pursuer wins")
	var closing := _chase([8, 4])
	closing.exchange("steady", "steady")
	# 10 + 2 + 8 = 20 against 10 + 3 + 4 = 17: the pursuer takes three bands.
	h.equal(closing.gap(), 0, "gap")

	h.it("never moves the gap more than the cap")
	var blowout := _chase([10, 10, 1, 9])
	# The pursuer explodes to 20 and the quarry fumbles to -8, a margin far past
	# the cap of three.
	blowout.exchange("steady", "steady")
	h.equal(blowout.gap(), 0, "gap moved by the cap, not the margin")

	h.it("undoes an exchange exactly")
	var undone := _chase([4, 6])
	undone.exchange("steady", "steady")
	undone.undo()
	h.equal(undone.gap(), 3, "gap restored")
	h.equal(undone.snapshot()["round"], 1, "round restored")


static func _maneuvers(h: Harness) -> void:
	h.it("charges a lost push an extra band")
	# Pursuer 10 + handling 2 + a d10 of 9 = 21. Quarry 10 + handling 3 + the
	# push's 2 + a d10 that fumbles from 1 down by 3 = 13. The margin of -8 caps
	# to -3, and losing while pushing makes it -4.
	var pushed := _chase([9, 1, 3], 5)
	pushed.exchange("steady", "push")
	h.equal(pushed.gap(), 1, "gap")
	var steady := _chase([9, 1, 3], 5)
	steady.exchange("steady", "steady")
	h.equal(steady.gap(), 2, "the same rolls without the push cost one band less")

	h.it("puts a failed shortcut into something")
	var crashed := _chase([9, 4, 2, 2, 2])
	crashed.exchange("steady", "shortcut")
	# The quarry loses, so the shortcut collects 3d6 of 2 against its own SDP.
	h.equal(crashed.snapshot()["quarry"]["sdp"], 19, "the bike took the crash")
	h.equal(crashed.snapshot()["pursuer"]["sdp"], 50, "the cruiser did not")

	h.it("lets a ram hurt both cars")
	var rammed := _chase([5, 5, 4, 4, 4], 0)
	rammed.exchange("ram", "steady")
	# 3d6 of 4 is 12 to the quarry, and half of it back to the rammer.
	h.equal(rammed.snapshot()["quarry"]["sdp"], 13, "the bike took the ram")
	h.equal(rammed.snapshot()["pursuer"]["sdp"], 44, "and the cruiser took half back")

	h.it("undoes a ram exactly")
	rammed.undo()
	h.equal(rammed.snapshot()["quarry"]["sdp"], 25, "bike restored")
	h.equal(rammed.snapshot()["pursuer"]["sdp"], 50, "cruiser restored")

	h.it("refuses a manoeuvre the gap does not allow")
	var far := _chase([], 5)
	h.equal(far.can_run("ram"), false, "no ramming from five bands back")
	h.equal(far.can_run("steady"), true, "but driving is always available")


static func _endings(h: Harness) -> void:
	h.it("ends the chase when the quarry is gone")
	var escaping := _chase([1, 9, 4, 6], 6)
	# The first exchange is a fumbled pursuit against a good run: the gap opens
	# past the escape threshold of eight.
	escaping.exchange("steady", "steady")
	h.equal(escaping.outcome(), Vehicles.ESCAPED, "outcome")
	h.equal(escaping.is_over(), true, "over")
	h.equal(escaping.can_run("steady"), false, "nothing left to drive at")

	h.it("ends it when the pursuer runs the quarry down")
	var caught := _chase([9, 1, 4], 0)
	caught.exchange("steady", "steady")
	h.equal(caught.outcome(), Vehicles.CAUGHT, "outcome")
	h.equal(caught.gap(), -1, "the gap floors at run down")

	h.it("ends it when a car is wrecked")
	var thin := _quarry()
	(thin["vehicle"] as Dictionary)["sdp"] = 6
	(thin["vehicle"] as Dictionary)["max_sdp"] = 6
	var wreck := Chase.new(_pursuer(), thin, Dice.FixedRandom.new([5, 5, 4, 4, 4]), 0)
	wreck.exchange("ram", "steady")
	h.equal(wreck.outcome(), Vehicles.WRECKED_QUARRY, "outcome")
	h.equal(wreck.snapshot()["quarry"]["wrecked"], true, "wrecked")

	h.it("undoes the ending along with the exchange that caused it")
	wreck.undo()
	h.equal(wreck.outcome(), Vehicles.RUNNING, "back in the chase")
	h.equal(wreck.is_over(), false, "and drivable")
