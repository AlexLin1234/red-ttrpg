extends RefCounted

## Lifestyle billing, including the cases the FastAPI service is held to.
##
## The app and the optional service both close a campaign month, in two
## languages. They read one table now, and both suites walk the same case file,
## so a rule change that reaches only one of them fails here or there rather
## than drifting quietly.

const Harness := preload("res://tests/harness.gd")

const CASES_PATH := "res://data/lifestyle_cases.json"


static func run(h: Harness) -> void:
	h.describe("lifestyle")

	_conformance(h)

	h.it("uses the four sourcebook monthly costs")
	var costs := {}
	for entry in Lifestyle.catalog():
		costs[String(entry["key"])] = int(entry["cost"])
	h.equal(costs["kibble"], 100, "Kibble")
	h.equal(costs["generic_prepak"], 300, "Generic Prepak")
	h.equal(costs["good_prepak"], 600, "Good Prepak")
	h.equal(costs["fresh_food"], 1500, "Fresh Food")

	h.it("charges affordable Lifestyles and marks unaffordable ones unpaid")
	var characters: Array = [
		{"name": "Rich", "cash": 700, "lifestyle": "good_prepak"},
		{"name": "Short", "cash": 50, "lifestyle": "kibble"},
		{"name": "No Downtime", "cash": 0},
	]
	var report := Lifestyle.settle(characters, "2045-07")
	h.equal(characters[0]["cash"], 100, "paid character cash")
	h.equal(characters[0]["lifestyle_paid_through"], "2045-07", "paid through")
	h.equal(characters[1]["cash"], 50, "unpaid character never goes negative")
	h.equal(characters[1]["lifestyle_status"], "unpaid", "unpaid status")
	h.equal(characters[1]["lifestyle_balance_due"], 100, "balance due")
	h.equal(characters[1]["lifestyle_grace_days"], 7, "grace period")
	h.equal(report["paid"], 1, "paid count")
	h.equal(report["unpaid"], 1, "unpaid count")

	h.it("rolls December into January")
	var next := Lifestyle.next_month_clock(
		{"year": 2045, "month": 12, "day": 31, "hour": 22, "minute": 10}
	)
	h.equal(Lifestyle.month_key(next), "2046-01", "next month")
	h.equal(next["day"], 1, "first day")
	h.equal(next["hour"], 22, "hour preserved")


## The shared cases, run against [method Lifestyle.settle].
##
## tests/service/test_month_end.py runs the same file against the endpoint.
static func _conformance(h: Harness) -> void:
	h.it("bills the shared cases the way the service does")
	var file := FileAccess.open(CASES_PATH, FileAccess.READ)
	if file == null:
		h.check(false, "could not open %s" % CASES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		h.check(false, "%s is not a JSON object" % CASES_PATH)
		return

	var document: Dictionary = parsed
	var billed := String(document["billed_month"])
	var cases: Array = document["cases"]
	var characters: Array = []
	for entry in cases:
		characters.append((entry as Dictionary)["character"].duplicate(true))

	Lifestyle.settle(characters, billed)

	for index in cases.size():
		var expected: Dictionary = (cases[index] as Dictionary)["expect"]
		var name := String((cases[index] as Dictionary)["name"])
		var character: Dictionary = characters[index]
		h.equal(int(character["cash"]), int(expected["cash"]), "%s: cash" % name)
		h.equal(
			String(character["lifestyle_status"]), String(expected["status"]), "%s: status" % name
		)
		h.equal(
			int(character["lifestyle_balance_due"]),
			int(expected["balance_due"]),
			"%s: balance due" % name
		)
		h.equal(
			int(character["lifestyle_grace_days"]),
			int(expected["grace_days"]),
			"%s: grace days" % name
		)
		if expected["paid_through"] != null:
			h.equal(
				String(character["lifestyle_paid_through"]),
				String(expected["paid_through"]),
				"%s: paid through" % name
			)
