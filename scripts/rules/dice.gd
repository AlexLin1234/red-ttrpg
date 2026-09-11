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


# -- free-form rolls ------------------------------------------------------------
#
# Everything above is welded to a mechanic: a check, a damage roll, a Hustle.
# A table also needs to roll things no rule covers — how many guards, how far
# the fall, who the NPC likes today — and a GM who has to leave the app to do
# it has left the app.

## The most dice and the largest die a single roll will take.
##
## Not a rule, a guard: a typo of "100d1000" should say no rather than spend a
## frame building a hundred thousand numbers nobody asked for.
const MAX_DICE := 100
const MAX_SIDES := 1000


## Read a dice expression into terms, without rolling anything.
##
## Accepts the shape a person actually types — "2d6+3", "d10 - 1", "4", mixed
## case, spaces anywhere. Returns [code]{ok, terms}[/code], or
## [code]{ok: false, error}[/code] naming what it could not read, because a
## roller that silently treats "2d" as 2 is worse than one that refuses it.
static func parse(expression: String) -> Dictionary:
	var text := expression.strip_edges().to_lower().replace(" ", "")
	if text.is_empty():
		return {"ok": false, "error": "Type something to roll, like 2d6+3."}

	var terms: Array[Dictionary] = []
	var sign := 1
	var cursor := 0
	# An operator has to be followed by something. Without this flag "2d6+" and
	# "2d6++3" both parse as 2d6+3, which is a different roll than the one that
	# was typed and gives no sign that the input was mangled.
	var awaiting_term := false
	while cursor < text.length():
		if text[cursor] == "+" or text[cursor] == "-":
			if awaiting_term:
				return {"ok": false, "error": "There are two operators in a row."}
			sign = 1 if text[cursor] == "+" else -1
			awaiting_term = true
			cursor += 1
			continue
		var start := cursor
		while cursor < text.length() and text[cursor] != "+" and text[cursor] != "-":
			cursor += 1
		var chunk := text.substr(start, cursor - start)
		if chunk.is_empty():
			return {"ok": false, "error": "There is an operator with nothing after it."}
		var term := _parse_term(chunk, sign)
		if not bool(term.get("ok", false)):
			return term
		terms.append(term["term"])
		sign = 1
		awaiting_term = false

	if awaiting_term:
		return {"ok": false, "error": "There is an operator with nothing after it."}
	if terms.is_empty():
		return {"ok": false, "error": "Nothing to roll there."}
	return {"ok": true, "terms": terms}


static func _parse_term(chunk: String, sign: int) -> Dictionary:
	if not chunk.contains("d"):
		if not chunk.is_valid_int():
			return {"ok": false, "error": "\"%s\" is not a number or a die." % chunk}
		return {"ok": true, "term": {"kind": "flat", "value": sign * int(chunk)}}

	var halves := chunk.split("d", true)
	if halves.size() != 2:
		return {"ok": false, "error": "\"%s\" has more than one d in it." % chunk}
	# "d10" means one d10, which is how everybody writes it.
	var count_text := String(halves[0])
	var count := 1 if count_text.is_empty() else (int(count_text) if count_text.is_valid_int() else -1)
	if count < 0:
		return {"ok": false, "error": "\"%s\" does not say how many dice." % chunk}
	var sides_text := String(halves[1])
	if not sides_text.is_valid_int():
		return {"ok": false, "error": "\"%s\" does not say how many sides." % chunk}
	var sides := int(sides_text)

	if count < 1 or count > MAX_DICE:
		return {"ok": false, "error": "Roll between 1 and %d dice at a time." % MAX_DICE}
	if sides < 2 or sides > MAX_SIDES:
		return {"ok": false, "error": "A die has between 2 and %d sides." % MAX_SIDES}
	return {"ok": true, "term": {"kind": "dice", "count": count, "sides": sides, "sign": sign}}


## Roll a parsed expression.
##
## Returns [code]{ok, total, detail, terms}[/code]. [code]detail[/code] is the
## sentence a GM reads back to the table — every die that was rolled, in the
## order it was rolled — because "17" on its own is a number nobody can check.
static func evaluate(expression: String, rng: RandomSource) -> Dictionary:
	var parsed := parse(expression)
	if not bool(parsed.get("ok", false)):
		return parsed

	var total := 0
	var parts := PackedStringArray()
	var rolled: Array[Dictionary] = []
	for value in parsed["terms"]:
		var term: Dictionary = value
		if String(term["kind"]) == "flat":
			var flat := int(term["value"])
			total += flat
			parts.append("%+d" % flat)
			continue
		var count := int(term["count"])
		var sides := int(term["sides"])
		var sign := int(term["sign"])
		var faces := PackedInt32Array()
		var subtotal := 0
		for index in count:
			var face := rng.randint(1, sides)
			faces.append(face)
			subtotal += face
		total += sign * subtotal
		rolled.append({"count": count, "sides": sides, "sign": sign, "faces": faces})
		parts.append(
			"%s%dd%d [%s]" % ["-" if sign < 0 else "+", count, sides, ", ".join(_strings(faces))]
		)

	var detail := " ".join(parts).strip_edges()
	# A roll that opens with a plus reads as a typo rather than as arithmetic.
	if detail.begins_with("+"):
		detail = detail.substr(1).strip_edges()
	return {"ok": true, "total": total, "detail": detail, "terms": rolled}


static func _strings(values: PackedInt32Array) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		out.append(str(value))
	return out
