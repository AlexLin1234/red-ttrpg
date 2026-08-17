extends RefCounted

const Harness := preload("res://tests/harness.gd")


static func run(h: Harness) -> void:
	h.describe("lifestyle")

	h.it("uses the four sourcebook monthly costs")
	var costs := {}
	for entry in Lifestyle.CATALOG:
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
