extends RefCounted

## A run made during a fight rather than beside it.
##
## The gap these cases exist for: Netrun kept a turn counter of its own with no
## link to the encounter's initiative or rounds, so a GM running the shape of
## session Cyberpunk RED actually produces — the netrunner in the room, acting
## on their turn while the Solo shoots — had to run two clocks and reconcile
## them in their head.
##
## The rules: a bound run reads the fight's round, refuses actions when it is
## not the runner's turn, offers that refusal as a ruling the table may waive,
## and hands the runner their NET Actions when the fight comes round to them. An
## unbound run — a netrunner working alone — is untouched by all of it.

const Harness := preload("res://tests/harness.gd")


static func _architecture() -> Dictionary:
	return {
		"id": "arch-1",
		"name": "Test",
		"floors":
		[
			{"id": "f1", "kind": "password", "name": "Password", "level": 1, "branch": 0, "dv": 6},
			{"id": "f2", "kind": "file", "name": "The file", "level": 2, "branch": 0, "dv": 6},
		],
	}


static func _runner() -> Dictionary:
	return {"character_id": "mira", "name": "Mira", "interface": 4, "hp": 30, "max_hp": 30}


static func run(h: Harness) -> void:
	h.describe("netrun on initiative")

	_unbound(h)
	_gating(h)
	_turns(h)


static func _unbound(h: Harness) -> void:
	h.it("leaves a run made alone exactly as it was")
	var session := NetrunSession.new(_architecture(), _runner(), Dice.FixedRandom.new([5]))
	h.equal(session.is_bound(), false, "not bound to anything")
	var gate := session.turn_block("somebody-else", 3)
	h.equal(bool(gate["ok"]), true, "no fight, no gate")

	h.it("keeps its own turn counter when nothing is driving it")
	h.equal(session.turn, 1, "turn one")
	session.end_turn()
	h.equal(session.turn, 2, "and it advances on its own")


static func _gating(h: Harness) -> void:
	h.it("refuses to act when it is somebody else's turn")
	var session := NetrunSession.new(_architecture(), _runner(), Dice.FixedRandom.new([5]))
	session.bind_to_actor("unit-mira")
	h.equal(session.is_bound(), true, "bound")
	var blocked := session.turn_block("unit-spike", 2)
	h.equal(bool(blocked["ok"]), false, "the Solo is acting")
	h.check(String(blocked["reason"]) != "", "and it says so")

	h.it("offers waiting for your turn as a ruling the table can waive")
	# The same shape the encounter uses: turn order is a courtesy, an empty
	# magazine is not.
	h.equal(bool(blocked["override"]), true, "the GM may wave it through")

	h.it("lets the runner act when the fight reaches them")
	var allowed := session.turn_block("unit-mira", 2)
	h.equal(bool(allowed["ok"]), true, "their turn")
	h.equal(bool(allowed["override"]), false, "nothing to waive")

	h.it("refuses before initiative has been rolled")
	# An encounter exists from the moment a board opens; it has rounds only once
	# somebody rolls, and until then there is no turn to act on.
	var unrolled := session.turn_block("unit-mira", 0)
	h.equal(bool(unrolled["ok"]), false, "no rounds yet")
	h.equal(bool(unrolled["override"]), true, "still the GM's call")

	h.it("stops gating when the binding is cleared")
	session.bind_to_actor("")
	h.equal(bool(session.turn_block("unit-spike", 2)["ok"]), true, "unbound acts freely")


static func _turns(h: Harness) -> void:
	h.it("takes its round from the fight rather than counting its own")
	var session := NetrunSession.new(_architecture(), _runner(), Dice.FixedRandom.new([5]))
	session.bind_to_actor("unit-mira")
	session.begin_bound_turn(4)
	h.equal(session.turn, 4, "the fight is in round four, so the run is")

	h.it("hands the runner their NET Actions back when their turn comes round")
	var spent := int(session.runner()["actions_left"]) - 1
	session.session.state["runner"]["actions_left"] = spent
	session.begin_bound_turn(5)
	h.equal(
		int(session.runner()["actions_left"]),
		Netrun.actions_per_turn(4),
		"a full turn's worth arrived with the turn",
	)

	h.it("does not refresh twice inside one round")
	# The screen redraws on every change to the fight, so this is called far
	# more often than the round changes.
	session.session.state["runner"]["actions_left"] = 1
	session.begin_bound_turn(5)
	h.equal(int(session.runner()["actions_left"]), 1, "the same round changes nothing")

	h.it("ignores a bound turn call on a run that is not bound")
	var alone := NetrunSession.new(_architecture(), _runner(), Dice.FixedRandom.new([5]))
	alone.begin_bound_turn(9)
	h.equal(alone.turn, 1, "an unbound run keeps its own count")
