extends RefCounted

## Table notation for the dice tray.
##
## The rule these cases protect: what the tray prints is the arithmetic that
## happened, and a d10! is the same check die the resolver rolls.

const Harness := preload("res://tests/harness.gd")


static func _fixed(values: Array[int]) -> Dice.FixedRandom:
	return Dice.FixedRandom.new(values)


static func run(h: Harness) -> void:
	h.describe("dice notation")

	h.it("reads dice, flat numbers and signs")
	var parsed := Dice.parse(" 2D6 + 3 ")
	h.equal(parsed["ok"], true, "parses")
	h.equal(parsed["text"], "2d6 + 3", "normalised text")
	h.equal((parsed["terms"] as Array).size(), 2, "two terms")
	h.equal(Dice.parse("d10")["terms"][0]["count"], 1, "a bare d means one die")
	h.equal(Dice.parse("4d6-1d4+2")["text"], "4d6 − 1d4 + 2", "mixed signs")
	h.equal(Dice.parse("-2")["text"], "−2", "a leading minus")

	h.it("refuses what is not dice, with a sentence")
	for bad in ["", "banana", "2d", "d", "2d6+", "3x4", "0d6", "2d1", "101d6", "d1001", "d6!", "2d6+d"]:
		var refused := Dice.parse(bad)
		h.equal(refused["ok"], false, "“%s” refused" % bad)
		h.check(String(refused.get("error", "")) != "", "“%s” says why" % bad)

	h.it("rolls and prints the arithmetic longhand")
	var rolled := Dice.roll_notation("2d6+3", _fixed([4, 2]))
	h.equal(rolled["total"], 9, "total")
	h.equal(rolled["breakdown"], "2d6 [4, 2] + 3 = 9", "breakdown")
	h.equal(rolled["critical"], false, "plain dice never crit")

	h.it("subtracts a dice term")
	h.equal(Dice.roll_notation("d20-1d4", _fixed([15, 3]))["total"], 12, "15 − 3")

	h.it("explodes a check die on a 10, once")
	var crit := Dice.roll_notation("d10!+14", _fixed([10, 10]))
	h.equal(crit["total"], 34, "10 + 10 + 14, and the second 10 does not explode")
	h.equal(crit["critical"], true, "flagged")
	h.equal(crit["fumble"], false, "not a fumble")

	h.it("fumbles a check die on a 1")
	var fumble := Dice.roll_notation("d10!+8", _fixed([1, 6]))
	h.equal(fumble["total"], 3, "1 − 6 + 8")
	h.equal(fumble["fumble"], true, "flagged")

	h.it("leaves a plain d10 alone")
	var plain := Dice.roll_notation("d10", _fixed([10]))
	h.equal(plain["total"], 10, "no explosion without the !")
	h.equal(plain["critical"], false, "and no flag")

	h.it("passes a refusal straight through")
	h.equal(Dice.roll_notation("nope", _fixed([]))["ok"], false, "not rolled")
