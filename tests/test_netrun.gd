extends RefCounted

## Running a NET architecture.
##
## The rules the cases here pin: a floor is in the way until it is opened, a
## rezzed program is in the way until it is derezzed, every single thing the
## runner does costs one of a fixed number of NET Actions, and all of it undoes.

const Harness := preload("res://tests/harness.gd")


static func _architecture() -> Dictionary:
	return {
		"id": "arch-test",
		"name": "Test Substation",
		"difficulty": "standard",
		"floors":
		[
			{"id": "f1", "kind": "password", "name": "Front Door", "level": 1, "dv": 6},
			{"id": "f2", "kind": "ice", "ice_id": "Watchdog", "level": 2},
			{"id": "f3", "kind": "file", "name": "Payroll", "level": 3, "dv": 8},
		],
	}


## One black program, right at the top, so a case can reach it in one move.
static func _black_architecture() -> Dictionary:
	return {
		"id": "arch-black",
		"name": "Test Vault",
		"floors": [{"id": "b1", "kind": "ice", "ice_id": "Mauler", "level": 1}],
	}


static func _runner(overrides := {}) -> Dictionary:
	var runner := {
		"character_id": "mira",
		"name": "Mira Vega",
		"interface": 6,
		"hp": 30,
		"max_hp": 30,
	}
	runner.merge(overrides, true)
	return runner


static func _session(rolls: Array[int] = [], architecture := {}, runner := {}) -> NetrunSession:
	return NetrunSession.new(
		architecture if not architecture.is_empty() else _architecture(),
		runner if not runner.is_empty() else _runner(),
		Dice.FixedRandom.new(rolls),
	)


static func run(h: Harness) -> void:
	h.describe("netrun")

	_ladder(h)
	_ice(h)
	_budget(h)
	_endings(h)
	_generation(h)


static func _ladder(h: Harness) -> void:
	h.it("starts in the lobby with a full budget")
	var session := _session()
	var runner := session.runner()
	h.equal(runner["level"], 0, "level")
	h.equal(runner["floor_id"], "", "floor")
	# Interface 6 buys six NET Actions a turn.
	h.equal(runner["actions_left"], 6, "actions")
	h.equal(session.run_state(), "running", "run state")

	h.it("steps down onto the first floor")
	session.perform("move")
	h.equal(session.runner()["level"], 1, "level")
	h.equal(String(session.current_floor()["id"]), "f1", "floor")
	h.equal(session.runner()["actions_left"], 5, "the move cost an action")
	h.equal(session.current_floor()["revealed"], true, "stepping onto a floor reveals it")

	h.it("will not walk through a closed door")
	var blocked := session.availability("move")
	h.equal(blocked["ok"], false, "blocked")
	h.contains(String(blocked["reason"]), "still closed", "reason")

	h.it("opens a password and walks on")
	# Interface 6 + a d10 of 4 = 10, over the DV 6.
	var opening := _session([4])
	opening.perform("move")
	opening.perform("backdoor")
	h.equal(String(opening.current_floor()["state"]), Netrun.DEFEATED, "floor state")
	h.equal(String(opening.card["title"]), "BACKDOOR", "card")
	h.equal(opening.can("move"), true, "the way down is open")

	h.it("charges the trace for a failed attempt")
	# A d10 of 1 fumbles down by the next roll: 6 + (1 - 9) = -2, under DV 6.
	var failed := _session([1, 9])
	failed.perform("move")
	failed.perform("backdoor")
	h.equal(String(failed.current_floor()["state"]), Netrun.INTACT, "floor stays shut")
	h.equal(failed.runner()["trace"], 1, "trace")

	h.it("reads the floors below without stepping onto them")
	var scout := _session()
	scout.perform("pathfinder")
	h.equal(scout.runner()["level"], 0, "still in the lobby")
	var ladder: Array = scout.snapshot()["floors"]
	for entry in ladder:
		if String((entry as Dictionary)["id"]) == "f1":
			h.equal((entry as Dictionary)["revealed"], true, "the floor below is now known")

	h.it("undoes a move exactly")
	var undone := _session()
	undone.perform("move")
	undone.undo()
	h.equal(undone.runner()["level"], 0, "back in the lobby")
	h.equal(undone.runner()["floor_id"], "", "no floor")
	h.equal(undone.runner()["actions_left"], 6, "the action came back")
	h.equal(undone.floor_by_id("f1")["revealed"], false, "and so did what it revealed")


static func _ice(h: Harness) -> void:
	h.it("blocks everything but a fight while a program is rezzed")
	# Open the door, walk down onto the Watchdog.
	var session := _session([4])
	session.perform("move")
	session.perform("backdoor")
	session.perform("move")
	h.equal(String(session.current_floor()["id"]), "f2", "standing on the ICE")
	h.equal(session.can("move"), false, "cannot walk past it")
	h.equal(session.can("backdoor"), false, "cannot work the floor")
	h.equal(session.can("zap"), true, "can attack it")
	h.equal(session.can("jack_out"), true, "can always leave")

	h.it("derezzes a program it out-damages")
	# 2d6 of 6 and 6, plus Interface 6, is 18 against a Watchdog's 15 REZ.
	var kill := _session([4, 6, 6])
	kill.perform("move")
	kill.perform("backdoor")
	kill.perform("move")
	kill.perform("zap")
	h.equal(kill.floor_by_id("f2")["rez"], 0, "rez")
	h.equal(String(kill.floor_by_id("f2")["state"]), Netrun.DEFEATED, "state")
	h.equal(String(kill.card["title"]), "DEREZZED", "card")
	h.equal(kill.can("move"), true, "the way down opens")

	h.it("takes an answer from a program that survives")
	# 2d6 of 1 and 1, plus Interface 6, is 8 against 15: it lives, and a
	# non-black program answers by advancing the trace.
	var traded := _session([4, 1, 1, 3])
	traded.perform("move")
	traded.perform("backdoor")
	traded.perform("move")
	traded.perform("zap")
	h.equal(traded.floor_by_id("f2")["rez"], 7, "rez")
	h.equal(traded.runner()["trace"], 1, "the trace advanced by its damage dice")
	h.equal(traded.runner()["hp"], 30, "a non-black program does not hurt the runner")

	h.it("lets black ICE reach the netrunner")
	var black := _session([1, 1, 2, 2, 2], _black_architecture())
	black.perform("move")
	black.perform("zap")
	h.equal(black.floor_by_id("b1")["rez"], 17, "rez")
	h.equal(black.runner()["hp"], 24, "3d6 of 2 went to the netrunner")

	h.it("undoes a trade exactly")
	var undone := _session([1, 1, 2, 2, 2], _black_architecture())
	undone.perform("move")
	undone.perform("zap")
	undone.undo()
	h.equal(undone.floor_by_id("b1")["rez"], 25, "rez restored")
	h.equal(undone.runner()["hp"], 30, "hp restored")

	h.it("raises the DV of every floor once the alarm goes")
	var alerted := _session()
	h.equal(int((alerted.snapshot()["floors"][0] as Dictionary)["dv"]), 6, "quiet")
	alerted.set_alert(true)
	h.equal(int((alerted.snapshot()["floors"][0] as Dictionary)["dv"]), 8, "alarmed")
	alerted.undo()
	h.equal(int((alerted.snapshot()["floors"][0] as Dictionary)["dv"]), 6, "and back")


static func _budget(h: Harness) -> void:
	h.it("spends the turn one action at a time")
	var session := _session()
	for index in 6:
		session.perform("pathfinder")
	h.equal(session.runner()["actions_left"], 0, "spent out")
	var blocked := session.availability("pathfinder")
	h.equal(blocked["ok"], false, "nothing left")
	h.contains(String(blocked["reason"]), "No NET Actions", "reason")

	h.it("hands the budget back at the end of the turn")
	session.end_turn()
	h.equal(session.runner()["actions_left"], 6, "restored")
	h.equal(session.turn, 2, "turn")

	h.it("undoes the end of a turn")
	session.undo()
	h.equal(session.runner()["actions_left"], 0, "spent again")
	h.equal(session.turn, 1, "turn walked back")


static func _endings(h: Harness) -> void:
	h.it("ends the run when the trace catches up")
	var traced := _session([1, 9], {}, _runner({"trace": 9}))
	traced.perform("move")
	traced.perform("backdoor")
	h.equal(traced.runner()["trace"], 10, "trace")
	h.equal(traced.run_state(), "traced", "run state")
	h.equal(traced.can("move"), false, "the run is over")

	h.it("ends the run when the netrunner is flatlined")
	var dead := _session([1, 1, 6, 6, 6], _black_architecture(), _runner({"hp": 3, "max_hp": 30}))
	dead.perform("move")
	dead.perform("zap")
	h.equal(dead.run_state(), "flatlined", "run state")

	h.it("gives live ICE a parting shot on the way out")
	var leaving := _session([2, 2, 2], _black_architecture())
	leaving.perform("move")
	leaving.perform("jack_out")
	h.equal(leaving.run_state(), "jacked_out", "run state")
	h.equal(leaving.runner()["hp"], 24, "the program got one more hit")

	h.it("undoes jacking out")
	leaving.undo()
	h.equal(leaving.run_state(), "running", "back on the ladder")
	h.equal(leaving.runner()["hp"], 30, "and unhurt")


static func _generation(h: Harness) -> void:
	h.it("rolls an architecture that is immediately playable")
	var rolled := NetrunDefault.generate_architecture(
		"Zetatech Substation", "standard", Dice.FixedRandom.new([0, 1, 0])
	)
	var floors: Array = rolled["floors"]
	h.equal(floors.size(), 5, "a standard architecture runs five deep")
	h.equal(String((floors[0] as Dictionary)["kind"]), "password", "the first floor is a door")
	h.equal(String((floors[1] as Dictionary)["kind"]), "ice", "the second is a defender")
	h.equal(
		String((floors[4] as Dictionary)["kind"]), "file", "the bottom is worth the trip"
	)
	for index in floors.size():
		h.equal(int((floors[index] as Dictionary)["level"]), index + 1, "level %d" % (index + 1))

	h.it("runs the generated ladder without further setup")
	var session := NetrunSession.new(rolled, _runner(), Dice.FixedRandom.new([5]))
	h.equal(session.can("move"), true, "the lobby opens onto it")
	session.perform("move")
	h.equal(session.runner()["level"], 1, "level")
