extends RefCounted

## Campaign-held rules documents.
##
## The bug these cases exist for: `tables` was never a campaign key, so
## Store.campaign.get("tables", TablesDefault.document()) could only ever return
## the placeholder. Every fight in every campaign resolved against numbers
## nobody had checked, while two doc comments and the README said a GM could
## replace them.

const Harness := preload("res://tests/harness.gd")
const StoreScript := preload("res://scripts/campaign/store.gd")


static func _store() -> Object:
	var store := StoreScript.new()
	store.campaign = {
		"name": "Test",
		"clock": {"year": 2045, "month": 1, "day": 1, "hour": 12, "minute": 0},
		"sessions": 1,
		"session_log": [],
	}
	store.roster = {"characters": []}
	store.path = "user://test.red"
	return store


static func run(h: Harness) -> void:
	h.describe("rules documents")

	_falling_back(h)
	_replacing(h)
	_validation(h)
	_netrun(h)
	_reach(h)


static func _falling_back(h: Harness) -> void:
	h.it("uses the built-in placeholders when a campaign carries none")
	var store := _store()
	h.equal(store.rules_are_custom("tables"), false, "nothing of its own yet")
	h.equal(
		store.rules_document("tables").has("ranged_dv"), true, "and the placeholder answered"
	)

	h.it("treats an empty document as no document rather than as an empty ruleset")
	# A campaign that somehow carries {} must not resolve every shot against
	# nothing; it falls back exactly as one carrying no key at all does.
	store.campaign["tables"] = {}
	h.equal(store.rules_are_custom("tables"), false, "still the placeholder")
	h.equal(store.rules_document("tables").has("weapons"), true, "and it still has weapons")


static func _replacing(h: Harness) -> void:
	h.it("stores a campaign's own tables and reads them back")
	var store := _store()
	var document := TablesDefault.document()
	(document["cover"] as Dictionary)["Concrete"] = {"hp": 99, "sp": 42, "page": 0}
	var result: Dictionary = store.set_rules_document("tables", document)
	h.equal(bool(result["ok"]), true, "accepted")
	h.equal(store.rules_are_custom("tables"), true, "the campaign carries its own now")
	h.equal(int(store.rules_tables().cover("Concrete")["sp"]), 42, "the edited value is in force")

	h.it("reaches the encounter through the same reader the Location screen uses")
	h.equal(int(store.rules_tables().cover("Concrete")["hp"]), 99, "one source, one answer")

	h.it("undoes an edit in one step")
	h.equal(store.undo_label(), "Rules edit", "named for what it was")
	store.undo_campaign()
	h.equal(store.rules_are_custom("tables"), false, "back to the placeholders")

	h.it("resets a document back to the placeholders")
	store.set_rules_document("tables", document)
	h.equal(store.reset_rules_document("tables"), true, "reset")
	h.equal(store.rules_are_custom("tables"), false, "gone")
	h.equal(store.reset_rules_document("tables"), false, "and resetting twice is not an action")

	h.it("takes a copy rather than storing the caller's dictionary")
	# Otherwise an edit made to the document afterwards would reach into the
	# campaign without going through validation.
	var live := TablesDefault.document()
	store.set_rules_document("tables", live)
	(live["cover"] as Dictionary)["Concrete"] = {"hp": 1, "sp": 1, "page": 0}
	h.not_equal(int(store.rules_tables().cover("Concrete")["hp"]), 1, "the campaign was not reached")


static func _validation(h: Harness) -> void:
	h.it("refuses a document the rules cannot read")
	# A broken table does not fail when it is saved. It fails in the middle of a
	# fight, on the one shot that happens to land in the gap.
	var store := _store()
	var broken := TablesDefault.document()
	broken.erase("weapons")
	var result: Dictionary = store.set_rules_document("tables", broken)
	h.equal(bool(result["ok"]), false, "refused")
	h.check((result["problems"] as PackedStringArray).size() > 0, "and said what was wrong")
	h.equal(store.rules_are_custom("tables"), false, "nothing was stored")

	h.it("leaves no snapshot behind when it refuses")
	h.equal(store.can_undo_campaign(), false, "the undo stack is untouched")

	h.it("refuses a document key it does not know")
	h.equal(bool(store.set_rules_document("nonsense", {})["ok"]), false, "not a rules document")


static func _netrun(h: Harness) -> void:
	h.it("reads NET content through the campaign's document when it has one")
	var store := _store()
	var document := NetrunDefault.document()
	(document["ice"] as Dictionary)["Watchdog"] = {
		"name": "Watchdog", "rez": 99, "atk": 1, "def": 1, "effect": "Homebrewed", "page": 0
	}
	store.set_rules_document("netrun_tables", document)
	h.equal(int(store.netrun_tables().ice("Watchdog")["rez"]), 99, "the campaign's own ICE")

	h.it("falls back per lookup, not per document")
	# Replacing the ICE and not the floor kinds is a normal thing to do halfway
	# through an evening.
	var partial := {"ice": {"Custom": {"name": "Custom", "rez": 5}}}
	var reader := NetrunTables.new(partial)
	h.equal(int(reader.ice("Custom")["rez"]), 5, "the replaced half")
	h.equal(
		String(reader.floor_kind("password")["label"]) != "", true, "and the half left alone"
	)
	h.check(reader.difficulties().size() > 0, "difficulty bands still answer")

	h.it("rolls an architecture from whichever bands are in force")
	var rolled := reader.generate_architecture("Test", "standard", Dice.SeededRandom.new(3))
	h.check((rolled["floors"] as Array).size() > 0, "a ladder was built")
	h.equal(
		String((rolled["floors"] as Array).back()["kind"]),
		"file",
		"and the last floor is worth reaching",
	)


static func _reach(h: Harness) -> void:
	h.it("names a default for every document it will accept")
	for key in StoreScript.RULES_DOCUMENTS:
		var document := StoreScript.default_rules_document(String(key))
		h.check(not document.is_empty(), "%s has placeholders to fall back to" % String(key))

	h.it("keeps the lifepath document on the same footing as the rest")
	var store := _store()
	var lifepath := LifepathDefault.document()
	((lifepath["general"] as Dictionary)["personality"] as Array).append(
		{"roll": 99, "text": "Homebrewed"}
	)
	h.equal(bool(store.set_rules_document("lifepath_tables", lifepath)["ok"]), true, "accepted")
	h.equal(store.rules_are_custom("lifepath_tables"), true, "campaign-held")
	h.equal(
		store.lifepath_tables().general_rows("personality").size(),
		((lifepath["general"] as Dictionary)["personality"] as Array).size(),
		"and the roller reads the campaign's copy",
	)
