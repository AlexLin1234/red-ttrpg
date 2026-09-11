extends RefCounted

## Lifepath rolling, editing and undo.
##
## The rules these cases exist to protect: a lifepath is rolled off supplied
## tables rather than built-in ones, a GM's own table is read whole however long
## it is, and re-rolling somebody's history is undoable — because the mistake
## this has to survive is wiping a hand-written past with one stray click.

const Harness := preload("res://tests/harness.gd")


static func _tables() -> Lifepath:
	return Lifepath.new(
		{
			"general":
			{
				"cultural_origin": [{"roll": 1, "text": "Somewhere"}, {"roll": 2, "text": "Else"}],
				"personality": [{"roll": 1, "text": "Grim"}, {"roll": 2, "text": "Sunny"}],
				"life_event": [{"roll": 1, "text": "A bad year"}, {"roll": 2, "text": "A good one"}],
			},
			"roles":
			{
				"solo":
				{
					"moral_line": [{"roll": 1, "text": "No children"}],
					"what_kind": [{"roll": 1, "text": "Bodyguard"}],
				},
			},
		}
	)


static func run(h: Harness) -> void:
	h.describe("lifepath")

	_rolling(h)
	_banded_tables(h)
	_role_paths(h)
	_editing(h)
	_reversibility(h)
	_defaults(h)


static func _rolling(h: Harness) -> void:
	h.it("rolls every general question off the supplied tables")
	var rolled := _tables().roll("", Dice.FixedRandom.new([1, 2]))
	h.equal(String(rolled["cultural_origin"]), "Somewhere", "first question")
	h.equal(String(rolled["personality"]), "Sunny", "second question")

	h.it("leaves a question the document has no table for blank rather than failing")
	h.equal(String(rolled.get("valued_possession", "")), "", "no table, no answer")

	h.it("reads a table of any length, not a fixed d10")
	# A two-row table is a d2. A roller hard-coded to d10 would spend eight
	# tenths of its rolls off the end of a GM's short table.
	var rows: Array = [{"roll": 1, "text": "One"}, {"roll": 2, "text": "Two"}]
	h.equal(Lifepath.roll_row(rows, Dice.FixedRandom.new([2])), "Two", "the high row is reachable")

	h.it("reads a list that declares no numbers at all positionally")
	var bare: Array = [{"text": "First"}, {"text": "Second"}, {"text": "Third"}]
	h.equal(Lifepath.roll_row(bare, Dice.FixedRandom.new([3])), "Third", "indexed by the roll")

	h.it("answers an empty table with nothing rather than crashing")
	h.equal(Lifepath.roll_row([], Dice.FixedRandom.new([])), "", "no rows, no text")


static func _banded_tables(h: Harness) -> void:
	h.it("honours a row that covers a range of numbers")
	# Real tables bunch several results under one band, so a row may claim
	# 1-3 rather than just 1. The die is set by the highest number mentioned.
	var banded: Array = [
		{"roll": 1, "to": 3, "text": "Common"},
		{"roll": 4, "to": 9, "text": "Usual"},
		{"roll": 10, "text": "Rare"},
	]
	h.equal(Lifepath.roll_row(banded, Dice.FixedRandom.new([2])), "Common", "inside the first band")
	h.equal(Lifepath.roll_row(banded, Dice.FixedRandom.new([9])), "Usual", "top of the second")
	h.equal(Lifepath.roll_row(banded, Dice.FixedRandom.new([10])), "Rare", "the single-number row")


static func _role_paths(h: Harness) -> void:
	h.it("rolls the questions a role asks on top of the general ones")
	var solo := _tables().roll("solo", Dice.FixedRandom.new([1, 1, 1, 1]))
	h.equal(String(solo["moral_line"]), "No children", "a role question was answered")
	h.equal(String(solo["role"]), "solo", "the path remembers whose it is")

	h.it("asks a role's questions in a stable order")
	var fields := _tables().role_fields("solo")
	h.equal(fields.size(), 2, "both questions")
	h.equal(String(fields[0]["key"]), "moral_line", "sorted, so two rolls agree")

	h.it("treats a role with no path as complete rather than broken")
	h.equal(_tables().role_fields("rockerboy").size(), 0, "no questions")
	var none := _tables().roll("rockerboy", Dice.FixedRandom.new([1, 1]))
	h.equal(String(none["cultural_origin"]), "Somewhere", "the general path still ran")

	h.it("prints a key the file never saw as a readable label")
	h.equal(String(fields[1]["label"]), "What kind", "underscores become a sentence")


static func _editing(h: Harness) -> void:
	h.it("counts a sheet with no answers as unwritten")
	var character := {"id": "c1", "role_key": "solo"}
	Lifepath.ensure(character)
	h.check(not Lifepath.is_written(character), "an empty lifepath is not a lifepath")

	h.it("counts a sheet with one answer as written")
	Lifepath.apply(character, Lifepath.set_field_event("c1", "personality", "", "Grim"))
	h.check(Lifepath.is_written(character), "one answer is enough")

	h.it("adds life events in order")
	Lifepath.apply(character, Lifepath.add_event_event("c1", "A bad year"))
	Lifepath.apply(character, Lifepath.add_event_event("c1", "A worse one"))
	h.equal(Lifepath.life_events(character).size(), 2, "both kept")
	h.equal(String(Lifepath.life_events(character)[1]), "A worse one", "newest last")

	h.it("prints a sheet's whole path even after it changes role")
	character["role_key"] = "rockerboy"
	var rows := _tables().entries(character)
	var keys := PackedStringArray()
	for entry in rows:
		keys.append(String((entry as Dictionary)["key"]))
	h.check(keys.has("moral_line"), "the Solo answers it already gave are still printed")


static func _reversibility(h: Harness) -> void:
	h.it("puts a hand-written history back when a re-roll is undone")
	# The mistake this exists for: a GM writes a past by hand, then hits the
	# re-roll. Undo has to return the sentences, not an empty sheet.
	var character := {"id": "c1", "role_key": "solo"}
	Lifepath.ensure(character)
	var written := {"role": "solo", "personality": "Written by hand", "events": ["Something"]}
	var write := Lifepath.write_event("c1", character["lifepath"], written)
	Lifepath.apply(character, write)

	var rolled := _tables().roll("solo", Dice.FixedRandom.new([1, 1, 1, 1]))
	var reroll := Lifepath.write_event("c1", character["lifepath"], rolled)
	Lifepath.apply(character, reroll)
	h.equal(String((character["lifepath"] as Dictionary)["personality"]), "Grim", "the roll landed")

	Lifepath.undo(character, reroll)
	h.equal(
		String((character["lifepath"] as Dictionary)["personality"]),
		"Written by hand",
		"the sentence came back",
	)
	h.equal(Lifepath.life_events(character).size(), 1, "and so did the history")

	h.it("undoes one edited answer without touching the others")
	var edit := Lifepath.set_field_event("c1", "personality", "Written by hand", "Changed")
	Lifepath.apply(character, edit)
	Lifepath.undo(character, edit)
	h.equal(
		String((character["lifepath"] as Dictionary)["personality"]),
		"Written by hand",
		"back to what it was",
	)

	h.it("undoes the last life event and no others")
	var added := Lifepath.add_event_event("c1", "One more")
	Lifepath.apply(character, added)
	h.equal(Lifepath.life_events(character).size(), 2, "added")
	Lifepath.undo(character, added)
	h.equal(Lifepath.life_events(character).size(), 1, "removed")
	h.equal(String(Lifepath.life_events(character)[0]), "Something", "the older one survived")


static func _defaults(h: Harness) -> void:
	h.it("ships a placeholder document that answers every general question")
	var tables := Lifepath.new(LifepathDefault.document())
	var rolled := tables.roll("solo", Dice.SeededRandom.new(7))
	for entry in Lifepath.GENERAL:
		var key := String((entry as Dictionary)["key"])
		h.check(String(rolled.get(key, "")) != "", "%s was answered" % key)

	h.it("gives every built-in Role a path of its own")
	for entry in CharacterRules.ROLES:
		var key := String((entry as Dictionary)["key"])
		h.check(tables.role_fields(key).size() > 0, "%s has lifepath questions" % key)

	h.it("shapes a sheet written before lifepaths existed instead of failing on it")
	var legacy := {"name": "Legacy", "role_key": "fixer"}
	Lifepath.ensure(legacy)
	h.equal(String((legacy["lifepath"] as Dictionary)["role"]), "fixer", "adopted the role")
	h.equal(Lifepath.life_events(legacy).size(), 0, "and an empty history")
