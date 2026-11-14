class_name Dice
extends RefCounted

## Dice for the resolver.
##
## Rolls go through a [RandomSource] rather than [method @GlobalScope.randi] so
## every rule can be tested against a scripted sequence instead of a seed.


## A scripted or seeded source of d-rolls.
class RandomSource extends RefCounted:
	func randint(_low: int, _high: int) -> int:
		push_error("RandomSource is abstract")
		return 0


## Returns values from a fixed list. Used by the tests.
class FixedRandom extends RandomSource:
	var values: Array[int]
	var index := 0

	func _init(p_values: Array[int]) -> void:
		values = p_values

	func randint(low: int, high: int) -> int:
		assert(index < values.size(), "FixedRandom ran out of values")
		var value := values[index]
		index += 1
		assert(value >= low and value <= high, "FixedRandom value %d outside %d..%d" % [value, low, high])
		return value


## A seeded generator, so a fight can be replayed exactly.
class SeededRandom extends RandomSource:
	var _rng := RandomNumberGenerator.new()

	func _init(p_seed: int) -> void:
		_rng.seed = p_seed

	func randint(low: int, high: int) -> int:
		return _rng.randi_range(low, high)


## One d10 check: 10s explode upward once, 1s fumble downward once.
##
## Returns {"rolls": PackedInt32Array, "total": int}.
static func roll_check(rng: RandomSource) -> Dictionary:
	var first := rng.randint(1, 10)
	if first == 10:
		var extra := rng.randint(1, 10)
		return {"rolls": PackedInt32Array([first, extra]), "total": first + extra}
	if first == 1:
		var extra := rng.randint(1, 10)
		return {"rolls": PackedInt32Array([first, extra]), "total": first - extra}
	return {"rolls": PackedInt32Array([first]), "total": first}


## Roll [param dice] d6. Returns {"rolls": PackedInt32Array, "total": int}.
static func damage_roll(dice: int, rng: RandomSource) -> Dictionary:
	var rolls := PackedInt32Array()
	var total := 0
	for i in dice:
		var value := rng.randint(1, 6)
		rolls.append(value)
		total += value
	return {"rolls": rolls, "total": total}


# -- free-form notation ----------------------------------------------------------

## The most dice and the biggest die one roll may ask for. A typo of "1000d1000"
## should be an answer, not a frozen console.
const MAX_DICE := 100
const MAX_SIDES := 1000


## Read table notation — "2d6+3", "d10", "4d6 - 1d4 + 2", "d10!" — into terms.
##
## A trailing "!" on a d10 makes it a Cyberpunk RED check die: a 10 explodes
## upward once and a 1 fumbles downward once, exactly as [method roll_check]
## does, so the tray and the resolver cannot disagree about what a check is.
##
## Returns {"ok": true, "terms": Array, "text": String} or {"ok": false,
## "error": String}. A term is {"sign", "count", "sides", "check"} for dice and
## {"sign", "flat"} for a plain number.
static func parse(notation: String) -> Dictionary:
	var text := notation.strip_edges().to_lower().replace(" ", "")
	if text == "":
		return {"ok": false, "error": "Type something to roll, like 2d6+3."}

	var terms: Array[Dictionary] = []
	var index := 0
	while index < text.length():
		var sign := 1
		var symbol := text[index]
		if symbol == "+" or symbol == "-":
			sign = -1 if symbol == "-" else 1
			index += 1
		elif not terms.is_empty():
			return {"ok": false, "error": "Expected + or − before “%s”." % text.substr(index)}

		var start := index
		while index < text.length() and text[index] != "+" and text[index] != "-":
			index += 1
		var term := _parse_term(text.substr(start, index - start), sign)
		if not bool(term.get("ok", false)):
			return term
		term.erase("ok")
		terms.append(term)

	return {"ok": true, "terms": terms, "text": _notation_text(terms)}


static func _parse_term(piece: String, sign: int) -> Dictionary:
	if piece == "":
		return {"ok": false, "error": "There is a + or − with nothing after it."}
	if piece.is_valid_int():
		return {"ok": true, "sign": sign, "flat": int(piece)}

	var check := piece.ends_with("!")
	if check:
		piece = piece.substr(0, piece.length() - 1)
	var halves := piece.split("d")
	if halves.size() != 2 or not halves[1].is_valid_int():
		return {"ok": false, "error": "“%s” is not dice. Try 2d6, d10 or d10!." % piece}
	if halves[0] != "" and not halves[0].is_valid_int():
		return {"ok": false, "error": "“%s” is not dice. Try 2d6, d10 or d10!." % piece}

	var count := 1 if halves[0] == "" else int(halves[0])
	var sides := int(halves[1])
	if count < 1 or count > MAX_DICE:
		return {"ok": false, "error": "Roll between 1 and %d dice at a time." % MAX_DICE}
	if sides < 2 or sides > MAX_SIDES:
		return {"ok": false, "error": "A die has between 2 and %d sides." % MAX_SIDES}
	if check and sides != 10:
		return {"ok": false, "error": "Only a d10 explodes and fumbles: write d10!."}
	return {"ok": true, "sign": sign, "count": count, "sides": sides, "check": check}


static func _notation_text(terms: Array[Dictionary]) -> String:
	var text := ""
	for term in terms:
		var negative := int(term["sign"]) < 0
		if text != "":
			text += " − " if negative else " + "
		elif negative:
			text += "−"
		if term.has("flat"):
			text += str(int(term["flat"]))
		else:
			text += "%dd%d%s" % [int(term["count"]), int(term["sides"]), "!" if term["check"] else ""]
	return text


## Roll [param notation].
##
## Returns {"ok", "text", "total", "breakdown", "groups", "critical", "fumble"}.
## [code]breakdown[/code] is the arithmetic longhand — "2d6 [4, 2] + 3 = 9" — so
## a roll is read the way every other roll in the app is. [code]critical[/code]
## and [code]fumble[/code] are only ever set by a check die.
static func roll_notation(notation: String, rng: RandomSource) -> Dictionary:
	var parsed := parse(notation)
	if not bool(parsed.get("ok", false)):
		return parsed

	var total := 0
	var parts := ""
	var groups: Array[Dictionary] = []
	var critical := false
	var fumble := false
	for term in parsed["terms"] as Array[Dictionary]:
		var sign := int(term["sign"])
		var negative := sign < 0
		if parts != "":
			parts += " − " if negative else " + "
		elif negative:
			parts += "−"

		if term.has("flat"):
			total += sign * int(term["flat"])
			parts += str(int(term["flat"]))
			continue

		var rolls := PackedInt32Array()
		var subtotal := 0
		if bool(term["check"]):
			for i in int(term["count"]):
				var check := roll_check(rng)
				var faces: PackedInt32Array = check["rolls"]
				critical = critical or faces[0] == 10
				fumble = fumble or faces[0] == 1
				rolls.append_array(faces)
				subtotal += int(check["total"])
		else:
			for i in int(term["count"]):
				var face := rng.randint(1, int(term["sides"]))
				rolls.append(face)
				subtotal += face
		total += sign * subtotal
		var label := "%dd%d%s" % [int(term["count"]), int(term["sides"]), "!" if term["check"] else ""]
		parts += "%s %s" % [label, str(Array(rolls))]
		groups.append({"label": label, "rolls": rolls, "subtotal": subtotal, "sign": sign})

	return {
		"ok": true,
		"text": String(parsed["text"]),
		"total": total,
		"breakdown": "%s = %d" % [parts, total],
		"groups": groups,
		"critical": critical,
		"fumble": fumble,
	}
