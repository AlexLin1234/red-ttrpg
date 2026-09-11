extends RefCounted

## Reading and rolling a free-form dice expression.
##
## The rule these cases exist to protect: a roller that cannot read what it was
## given says so. Silently treating "2d" as 2, or "d0" as a die, answers a
## different question than the one the GM asked and never admits it.

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("dice expressions")

	_reading(h)
	_refusing(h)
	_rolling(h)
	_detail(h)


static func _reading(h: Harness) -> void:
	h.it("reads the shapes a person actually types")
	h.equal(bool(Dice.parse("2d6+3")["ok"]), true, "no spaces")
	h.equal(bool(Dice.parse("2d6 + 3")["ok"]), true, "spaces")
	h.equal(bool(Dice.parse(" 2D6+3 ")["ok"]), true, "upper case and padding")
	h.equal(bool(Dice.parse("4")["ok"]), true, "a bare number")
	h.equal(bool(Dice.parse("1d10-1d6")["ok"]), true, "dice on both sides of a minus")

	h.it("treats a bare d as one die, because everybody writes it that way")
	var parsed := Dice.parse("d10")
	h.equal(bool(parsed["ok"]), true, "read")
	var term: Dictionary = parsed["terms"][0]
	h.equal(int(term["count"]), 1, "one die")
	h.equal(int(term["sides"]), 10, "ten sides")

	h.it("keeps the sign with the term it belongs to")
	var mixed := Dice.parse("2d6-3")
	var flat: Dictionary = mixed["terms"][1]
	h.equal(int(flat["value"]), -3, "the minus stayed attached")

	h.it("reads a leading minus")
	var negative := Dice.parse("-2")
	h.equal(int((negative["terms"][0] as Dictionary)["value"]), -2, "negative flat term")


static func _refusing(h: Harness) -> void:
	h.it("refuses an expression it cannot read rather than guessing")
	# Each of these has a plausible wrong answer a sloppier parser would give.
	for bad in ["", "   ", "2d", "d", "dd6", "2d6+", "2d6++3", "banana", "2x6"]:
		var result := Dice.parse(bad)
		h.equal(bool(result["ok"]), false, "refused %s" % bad)
		h.check(String(result.get("error", "")) != "", "and said why")

	h.it("refuses a die with fewer than two sides")
	h.equal(bool(Dice.parse("1d1")["ok"]), false, "a one-sided die is not a die")
	h.equal(bool(Dice.parse("1d0")["ok"]), false, "nor is a zero-sided one")

	h.it("refuses a roll too large to be meant")
	# A guard, not a rule: "100d1000" is a typo, and building a hundred thousand
	# numbers for it helps nobody.
	h.equal(bool(Dice.parse("%dd6" % (Dice.MAX_DICE + 1))["ok"]), false, "too many dice")
	h.equal(bool(Dice.parse("1d%d" % (Dice.MAX_SIDES + 1))["ok"]), false, "too many sides")
	h.equal(bool(Dice.parse("0d6")["ok"]), false, "no dice at all")

	h.it("passes the refusal out of evaluate rather than rolling anyway")
	var evaluated := Dice.evaluate("2d", Dice.FixedRandom.new([3]))
	h.equal(bool(evaluated["ok"]), false, "refused")
	h.equal(evaluated.has("total"), false, "and produced no number")


static func _rolling(h: Harness) -> void:
	h.it("sums the dice it rolled and the constants it was given")
	var result := Dice.evaluate("2d6+3", Dice.FixedRandom.new([4, 5]))
	h.equal(int(result["total"]), 12, "4 + 5 + 3")

	h.it("subtracts a negative term instead of adding it")
	var minus := Dice.evaluate("2d6-3", Dice.FixedRandom.new([4, 5]))
	h.equal(int(minus["total"]), 6, "9 - 3")

	h.it("subtracts a whole subtracted die group")
	var opposed := Dice.evaluate("1d10-1d6", Dice.FixedRandom.new([8, 2]))
	h.equal(int(opposed["total"]), 6, "8 - 2")

	h.it("rolls exactly as many dice as it was asked for")
	# FixedRandom asserts when it is read past the end, so a roller that took an
	# extra die would fail here rather than quietly using a number from nowhere.
	var three := Dice.evaluate("3d6", Dice.FixedRandom.new([1, 2, 3]))
	h.equal(int(three["total"]), 6, "three dice, no more")

	h.it("rolls a bare constant without touching the dice at all")
	var flat := Dice.evaluate("7", Dice.FixedRandom.new([]))
	h.equal(int(flat["total"]), 7, "no rolls needed")


static func _detail(h: Harness) -> void:
	h.it("says which faces came up, because a total nobody can check is a number to argue about")
	var result := Dice.evaluate("2d6+3", Dice.FixedRandom.new([4, 5]))
	var detail := String(result["detail"])
	h.contains(detail, "4, 5", "the faces are named")
	h.contains(detail, "2d6", "and so is what was rolled")
	h.contains(detail, "+3", "and the modifier")

	h.it("does not open the line with a stray plus")
	h.check(not detail.begins_with("+"), "reads as arithmetic rather than a typo")

	h.it("marks a subtracted group as subtracted")
	var opposed := Dice.evaluate("1d10-1d6", Dice.FixedRandom.new([8, 2]))
	h.contains(String(opposed["detail"]), "-1d6", "the minus is visible in the read-back")
