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
