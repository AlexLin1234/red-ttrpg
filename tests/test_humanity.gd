extends RefCounted

## Humanity bands, the Empathy they cap, and cyberpsychosis.
##
## The rule these cases exist to protect: chrome costs something other than
## money, and the bottom of the scale takes the character away from the player.
## Like death, that is not undone by the number going back up.

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("humanity")

	_bands(h)
	_empathy(h)
	_losing(h)
	_restoring(h)
	_reconciliation(h)
	_reversibility(h)


static func _bands(h: Harness) -> void:
	h.it("reads a band off Humanity as a fraction of what the character started with")
	# Proportional rather than absolute, so a character built with a low EMP is
	# not born halfway to cyberpsychosis.
	h.equal(Humanity.state_for(60, 60), Humanity.STABLE, "untouched")
	h.equal(Humanity.state_for(43, 60), Humanity.STABLE, "just above the first band")
	h.equal(Humanity.state_for(42, 60), Humanity.STRAINED, "at 70%")
	h.equal(Humanity.state_for(24, 60), Humanity.DETACHED, "at 40%")
	h.equal(Humanity.state_for(12, 60), Humanity.BORDERLINE, "at 20%")
	h.equal(Humanity.state_for(1, 60), Humanity.BORDERLINE, "one point left")
	h.equal(Humanity.state_for(0, 60), Humanity.CYBERPSYCHOTIC, "gone")

	h.it("gives every band a label and a line the GM can read out")
	for state in [
		Humanity.STABLE,
		Humanity.STRAINED,
		Humanity.DETACHED,
		Humanity.BORDERLINE,
		Humanity.CYBERPSYCHOTIC,
	]:
		h.check(Humanity.label(state) != "", "label for %s" % state)
		h.check(Humanity.note(state) != "", "note for %s" % state)


static func _empathy(h: Harness) -> void:
	h.it("caps Empathy at the Humanity behind it")
	# This is what makes chrome cost something: the stat on the sheet stops
	# being the number the social checks use.
	h.equal(Humanity.effective_empathy({"humanity": 60, "stats": {"EMP": 6}}), 6, "untouched")
	h.equal(Humanity.effective_empathy({"humanity": 35, "stats": {"EMP": 6}}), 3, "worn down")
	h.equal(Humanity.effective_empathy({"humanity": 4, "stats": {"EMP": 6}}), 0, "nothing left")

	h.it("never raises Empathy above what the sheet says")
	h.equal(Humanity.effective_empathy({"humanity": 80, "stats": {"EMP": 3}}), 3, "capped by the stat")


static func _losing(h: Harness) -> void:
	h.it("takes Humanity off and says which band that lands in")
	var character := {"name": "Rache", "humanity": 60, "max_humanity": 60}
	var outcome := Humanity.lose("solo", character, 20)
	h.equal(int(outcome["lost"]), 20, "how much")
	h.equal(String(outcome["state"]), Humanity.STRAINED, "the new band")
	h.check(bool(outcome["crossed"]), "it crossed a line")

	h.it("says nothing about a band when the loss stays inside one")
	var shallow := Humanity.lose("solo", {"humanity": 60, "max_humanity": 60}, 2)
	h.check(not bool(shallow["crossed"]), "same band")

	h.it("never takes Humanity below zero")
	var last := Humanity.lose("solo", {"humanity": 3, "max_humanity": 60}, 10)
	h.equal(int(last["lost"]), 3, "only what was there")
	h.equal(String(last["state"]), Humanity.CYBERPSYCHOTIC, "and that is the end of them")


static func _restoring(h: Harness) -> void:
	h.it("gives Humanity back, which is what therapy does")
	var outcome := Humanity.restore("solo", {"humanity": 20, "max_humanity": 60}, 3)
	h.equal(int(outcome["restored"]), 3, "a week's worth")

	h.it("never fills past the ceiling")
	var topped := Humanity.restore("solo", {"humanity": 59, "max_humanity": 60}, 10)
	h.equal(int(topped["restored"]), 1, "only the room that was left")

	h.it("does not bring back a character who went under")
	# Cyberpsychosis is like death: not derivable from the number going back up.
	# The GM undoes the loss that caused it, or the character stays gone.
	var lost := {"humanity": 0, "max_humanity": 60, "humanity_state": Humanity.CYBERPSYCHOTIC}
	var attempt := Humanity.restore("solo", lost, 20)
	h.equal(int(attempt["restored"]), 0, "nothing restored")
	h.equal((attempt["events"] as Array).size(), 0, "and nothing recorded")


static func _reconciliation(h: Harness) -> void:
	h.it("keeps a sheet's band honest about its own Humanity")
	var stale := {"name": "Stale", "humanity": 10, "max_humanity": 60, "humanity_state": "stable"}
	Humanity.reconcile(stale)
	h.equal(String(stale["humanity_state"]), Humanity.BORDERLINE, "derived, not trusted")

	h.it("leaves a lost character lost however the numbers read")
	var gone := {"humanity": 40, "max_humanity": 60, "humanity_state": Humanity.CYBERPSYCHOTIC}
	Humanity.reconcile(gone)
	h.equal(String(gone["humanity_state"]), Humanity.CYBERPSYCHOTIC, "still gone")

	h.it("gives every sheet a band when the character sheet is ensured")
	var sheet := {"name": "New", "humanity": 24, "max_humanity": 60}
	CharacterRules.ensure_character(sheet)
	h.equal(String(sheet["humanity_state"]), Humanity.DETACHED, "set on the way through")

	h.it("leaves a sheet with no Humanity at all alone")
	var bare := {"name": "Mook"}
	Humanity.reconcile(bare)
	h.check(not bare.has("humanity_state"), "nothing invented")


static func _reversibility(h: Harness) -> void:
	h.it("undoes a Humanity loss exactly")
	var state := {"actors": {"solo": {"humanity": 60, "max_humanity": 60}}}
	var session := Events.Session.new(state)
	session.record(
		{"kind": "install"}, [{"kind": "humanity_lost", "target_id": "solo", "amount": 14}]
	)
	h.equal(int(session.state["actors"]["solo"]["humanity"]), 46, "after the chrome")
	session.undo()
	h.equal(int(session.state["actors"]["solo"]["humanity"]), 60, "back")

	h.it("inverts by what it actually took when the loss ran past zero")
	var state_low := {"actors": {"solo": {"humanity": 4, "max_humanity": 60}}}
	var session_low := Events.Session.new(state_low)
	session_low.record(
		{"kind": "install"}, [{"kind": "humanity_lost", "target_id": "solo", "amount": 20}]
	)
	h.equal(int(session_low.state["actors"]["solo"]["humanity"]), 0, "floored")
	session_low.undo()
	h.equal(int(session_low.state["actors"]["solo"]["humanity"]), 4, "restored to what it was")

	h.it("undoes the band the loss set")
	var state_band := {"actors": {"solo": {"humanity_state": Humanity.STABLE}}}
	var session_band := Events.Session.new(state_band)
	session_band.record(
		{"kind": "install"},
		[{"kind": "humanity_state_set", "target_id": "solo", "state": Humanity.BORDERLINE}],
	)
	h.equal(String(session_band.state["actors"]["solo"]["humanity_state"]), Humanity.BORDERLINE, "set")
	session_band.undo()
	h.equal(String(session_band.state["actors"]["solo"]["humanity_state"]), Humanity.STABLE, "back")
