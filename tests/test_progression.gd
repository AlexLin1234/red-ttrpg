extends RefCounted

## Handing out Improvement Points and Reputation, and taking them back.
##
## The rules these cases exist to protect: IP has a source now as well as a
## sink, an award reaches the whole party in one action, Reputation records why
## it moved, and both undo as one step — an award that has to be reversed one
## sheet at a time is an award a GM will not dare make.

const Harness := preload("res://tests/harness.gd")
const StoreScript := preload("res://scripts/campaign/store.gd")


static func _store() -> Object:
	var store := StoreScript.new()
	store.campaign = {
		"name": "Test",
		"clock": {"year": 2045, "month": 1, "day": 1, "hour": 12, "minute": 0},
		"sessions": 3,
		"session_log": [],
	}
	store.roster = {
		"characters":
		[
			{"id": "spike", "name": "Spike", "improvement_points": 5, "reputation": 2},
			{"id": "mira", "name": "Mira", "improvement_points": 0, "reputation": 0},
			{"id": "mook", "name": "Booster 1", "improvement_points": 0, "reputation": 0},
		],
	}
	store.path = "user://test.red"
	return store


static func run(h: Harness) -> void:
	h.describe("progression")

	_awarding_ip(h)
	_reversing_ip(h)
	_reputation(h)
	_tiers(h)


static func _awarding_ip(h: Harness) -> void:
	h.it("awards the same IP to everybody named, and nobody else")
	var store := _store()
	var result: Dictionary = store.award_improvement_points(10, PackedStringArray(["spike", "mira"]))
	h.equal(result["ok"], true, "the award went through")
	h.equal(int(store.character_by_id("spike")["improvement_points"]), 15, "added to what was there")
	h.equal(int(store.character_by_id("mira")["improvement_points"]), 10, "from zero")
	h.equal(int(store.character_by_id("mook")["improvement_points"]), 0, "the mook was not at the table")

	h.it("writes one log line naming everyone who earned")
	var log: Array = store.campaign["session_log"]
	h.equal(log.size(), 1, "one line, not one per character")
	h.contains(String((log[0] as Dictionary)["text"]), "Spike", "named")
	h.contains(String((log[0] as Dictionary)["text"]), "Mira", "named")
	h.equal(int((log[0] as Dictionary)["session"]), 3, "filed under the session it happened in")

	h.it("refuses an award of nothing rather than logging one")
	var empty: Dictionary = store.award_improvement_points(0, PackedStringArray(["spike"]))
	h.equal(empty["ok"], false, "zero IP is not an award")
	var nobody: Dictionary = store.award_improvement_points(10, PackedStringArray())
	h.equal(nobody["ok"], false, "nobody is not a party")
	h.equal((store.campaign["session_log"] as Array).size(), 1, "neither reached the log")

	h.it("refuses an award to characters who are not on the roster, leaving no snapshot")
	# A refused award that still pushed a snapshot would put a do-nothing step
	# on the undo stack, so the next undo would appear to do nothing at all.
	var fresh := _store()
	var ghosts: Dictionary = fresh.award_improvement_points(10, PackedStringArray(["nobody"]))
	h.equal(ghosts["ok"], false, "no such character")
	h.equal(fresh.can_undo_campaign(), false, "and nothing was left on the stack")

	h.it("takes IP back when the amount is negative")
	store.award_improvement_points(-5, PackedStringArray(["spike"]))
	h.equal(int(store.character_by_id("spike")["improvement_points"]), 10, "deducted")

	h.it("never drives a character below zero IP")
	store.award_improvement_points(-999, PackedStringArray(["mira"]))
	h.equal(int(store.character_by_id("mira")["improvement_points"]), 0, "floored, not negative")


static func _reversing_ip(h: Harness) -> void:
	h.it("undoes a whole award in one step")
	# The reason this is a snapshot rather than a per-sheet event: an award
	# touches every sheet at the table, and putting that back one at a time is
	# the thing a GM would rather not risk making a mistake with.
	var store := _store()
	store.award_improvement_points(10, PackedStringArray(["spike", "mira"]))
	h.equal(store.can_undo_campaign(), true, "there is something to take back")
	h.equal(store.undo_label(), "IP award", "and it says what")

	store.undo_campaign()
	h.equal(int(store.character_by_id("spike")["improvement_points"]), 5, "back to what it was")
	h.equal(int(store.character_by_id("mira")["improvement_points"]), 0, "and so is everyone else")
	h.equal((store.campaign["session_log"] as Array).size(), 0, "the log line went with it")

	h.it("redoes it just as completely")
	store.redo_campaign()
	h.equal(int(store.character_by_id("spike")["improvement_points"]), 15, "reapplied")
	h.equal((store.campaign["session_log"] as Array).size(), 1, "log line came back")


static func _reputation(h: Harness) -> void:
	h.it("moves Reputation and says why in the log")
	var store := _store()
	var moved: Dictionary = store.award_reputation("spike", 3, "Walked out of the Totentanz")
	h.equal(moved["ok"], true, "awarded")
	h.equal(int(moved["before"]), 2, "from")
	h.equal(int(moved["after"]), 5, "to")
	var line := String((store.campaign["session_log"][0] as Dictionary)["text"])
	h.contains(line, "Walked out of the Totentanz", "the reason is on the record")
	h.contains(line, "2", "and so is where it came from")

	h.it("clamps Reputation to the track rather than running off the end")
	store.award_reputation("spike", 99, "")
	h.equal(
		int(store.character_by_id("spike")["reputation"]),
		CharacterRules.REPUTATION_MAX,
		"capped at the top",
	)
	store.award_reputation("spike", -99, "")
	h.equal(int(store.character_by_id("spike")["reputation"]), 0, "and at the bottom")

	h.it("refuses a move of zero and an unknown character")
	h.equal(bool(store.award_reputation("spike", 0, "")["ok"]), false, "nothing to do")
	h.equal(bool(store.award_reputation("nobody", 1, "")["ok"]), false, "no such character")

	h.it("undoes a Reputation award as one step")
	var before := int(store.character_by_id("mira")["reputation"])
	store.award_reputation("mira", 4, "Took the fall")
	h.equal(store.undo_label(), "Reputation award", "named for what it was")
	store.undo_campaign()
	h.equal(int(store.character_by_id("mira")["reputation"]), before, "back to where it started")


static func _tiers(h: Harness) -> void:
	h.it("reads every Reputation score as a tier")
	# The bottom tier has to cover zero, because most characters are nobody.
	h.equal(String(CharacterRules.reputation_tier(0)["label"]), "Unknown", "nobody has heard of you")
	h.equal(String(CharacterRules.reputation_tier(1)["label"]), "Known", "the first step up")
	h.equal(String(CharacterRules.reputation_tier(4)["label"]), "Known in the district", "mid")
	h.equal(String(CharacterRules.reputation_tier(10)["label"]), "Legendary", "the top of the track")

	h.it("reads a score between two tiers as the lower of them")
	h.equal(String(CharacterRules.reputation_tier(6)["label"]), "Known in the city", "6 is not 7")

	h.it("keeps one ceiling for the sheet and the Facedown")
	h.equal(
		int(Downtime.RULES["reputation_max"]),
		CharacterRules.REPUTATION_MAX,
		"one number, two readers",
	)
