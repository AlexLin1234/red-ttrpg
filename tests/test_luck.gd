extends RefCounted

## The Luck pool, and spending out of it.
##
## The rule these cases exist to protect: Luck is declared before the die and
## gone whether or not the check lands, so undoing the check has to give it back.

const Harness := preload("res://tests/harness.gd")


static func _character() -> Dictionary:
	return {"name": "Rache", "stats": {"LUCK": 6}, "luck_available": 6}


static func run(h: Harness) -> void:
	h.describe("luck")

	_pool(h)
	_spending(h)
	_refreshing(h)
	_reversibility(h)


static func _pool(h: Harness) -> void:
	h.it("reads the pool off the LUCK stat")
	h.equal(Luck.pool({"stats": {"LUCK": 7}}), 7, "from stats")
	h.equal(Luck.pool({"luck": 4, "stats": {"LUCK": 7}}), 4, "an explicit value wins")
	h.equal(Luck.pool({}), 0, "no stat at all")

	h.it("starts a sheet that has never spent a point with all of them")
	# Sheets written before Luck was spendable carry the stat and no pool. A
	# character who has never spent a point has spent none of them.
	var old_sheet := {"name": "Legacy", "stats": {"LUCK": 5}}
	Luck.ensure(old_sheet)
	h.equal(Luck.available(old_sheet), 5, "full rather than empty")

	h.it("never lets a pool exceed the stat behind it")
	var inflated := {"stats": {"LUCK": 3}, "luck_available": 99}
	Luck.ensure(inflated)
	h.equal(Luck.available(inflated), 3, "clamped to the stat")

	h.it("leaves a partly spent pool where it is")
	var mid := {"stats": {"LUCK": 6}, "luck_available": 2}
	Luck.ensure(mid)
	h.equal(Luck.available(mid), 2, "untouched")


static func _spending(h: Harness) -> void:
	h.it("spends points and reports what is left")
	var outcome := Luck.spend("solo", _character(), 2)
	h.check(bool(outcome["ok"]), "the spend was allowed")
	h.equal(int(outcome["spent"]), 2, "how many")
	h.equal(int((outcome["events"][0] as Dictionary)["amount"]), 2, "the event carries it")

	h.it("refuses to spend more than the character has rather than quietly clamping")
	# The GM chose a number. Spending a different one silently would be a worse
	# answer than saying no.
	var greedy := Luck.spend("solo", _character(), 9)
	h.check(not bool(greedy["ok"]), "refused")
	h.equal(int(greedy["spent"]), 0, "nothing spent")
	h.equal((greedy["events"] as Array).size(), 0, "and nothing recorded")

	h.it("refuses a spend of nothing")
	var nothing := Luck.spend("solo", _character(), 0)
	h.check(not bool(nothing["ok"]), "refused")

	h.it("lets a character spend their whole pool at once")
	var everything := Luck.spend("solo", _character(), 6)
	h.check(bool(everything["ok"]), "allowed")
	h.equal(int(everything["spent"]), 6, "all of it")


static func _refreshing(h: Harness) -> void:
	h.it("puts the pool back to full")
	var spent := {"stats": {"LUCK": 6}, "luck_available": 1}
	var outcome := Luck.refresh("solo", spent)
	h.equal(int(outcome["restored"]), 5, "the difference")

	h.it("does nothing to a pool that is already full")
	var full := Luck.refresh("solo", _character())
	h.equal(int(full["restored"]), 0, "nothing to restore")
	h.equal((full["events"] as Array).size(), 0, "and nothing recorded")


static func _reversibility(h: Harness) -> void:
	h.it("gives the points back when the check that spent them is undone")
	var state := {"actors": {"solo": _character()}}
	var session := Events.Session.new(state)
	session.record({"kind": "spend_luck"}, [{"kind": "luck_spent", "target_id": "solo", "amount": 3}])
	h.equal(int(session.state["actors"]["solo"]["luck_available"]), 3, "spent")
	session.undo()
	h.equal(int(session.state["actors"]["solo"]["luck_available"]), 6, "given back")
	session.redo()
	h.equal(int(session.state["actors"]["solo"]["luck_available"]), 3, "and spent again")

	h.it("never takes a pool below zero, and inverts by what it actually took")
	var state_low := {"actors": {"solo": {"luck_available": 2}}}
	var session_low := Events.Session.new(state_low)
	session_low.record(
		{"kind": "spend_luck"}, [{"kind": "luck_spent", "target_id": "solo", "amount": 5}]
	)
	h.equal(int(session_low.state["actors"]["solo"]["luck_available"]), 0, "floored at zero")
	session_low.undo()
	# The inverse carries 2, not 5: undo restores what was actually spent.
	h.equal(int(session_low.state["actors"]["solo"]["luck_available"]), 2, "back to what it was")
