class_name Lifestyle
extends RefCounted

## Cyberpunk RED Lifestyle costs and month-end settlement.
##
## The table values are derived from the sourcebook's Lifestyle table (p. 377).
## Campaign state stores only the selected key and payment status.

const CATALOG: Array[Dictionary] = [
	{"key": "kibble", "label": "Kibble", "cost": 100},
	{"key": "generic_prepak", "label": "Generic Prepak", "cost": 300},
	{"key": "good_prepak", "label": "Good Prepak", "cost": 600},
	{"key": "fresh_food", "label": "Fresh Food", "cost": 1500},
]


static func profile(key: String) -> Dictionary:
	for entry in CATALOG:
		if String(entry["key"]) == key:
			return entry
	return CATALOG[0]


static func is_valid_id(key: String) -> bool:
	for entry in CATALOG:
		if String(entry["key"]) == key:
			return true
	return false


static func is_month(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var parts := String(value).split("-")
	return parts.size() == 2 and parts[0].length() == 4 and parts[1].length() == 2 \
		and String(parts[0]).is_valid_int() and String(parts[1]).is_valid_int() \
		and int(parts[1]) >= 1 and int(parts[1]) <= 12


static func next_month(month: String) -> String:
	assert(is_month(month), "invalid campaign month")
	var parts := month.split("-")
	var year := int(parts[0])
	var number := int(parts[1]) + 1
	if number == 13:
		number = 1
		year += 1
	return "%04d-%02d" % [year, number]


static func ensure_character(character: Dictionary) -> void:
	character["cash"] = maxi(0, int(character.get("cash", 0)))
	character["lifestyle"] = String(character.get("lifestyle", "kibble"))
	character["lifestyle_status"] = String(character.get("lifestyle_status", "paid"))
	if character["lifestyle_status"] == "current":
		character["lifestyle_status"] = "paid"
	character["lifestyle_paid_through"] = character.get("lifestyle_paid_through", null)
	character["lifestyle_balance_due"] = maxi(0, int(character.get("lifestyle_balance_due", 0)))
	character["lifestyle_grace_days"] = character.get("lifestyle_grace_days", null)
	character["last_lifestyle_charge"] = character.get("last_lifestyle_charge", null)


static func validate_character(character: Dictionary) -> String:
	if not is_valid_id(String(character.get("lifestyle", ""))):
		return "invalid Lifestyle ID"
	for key in ["cash", "lifestyle_balance_due"]:
		if typeof(character.get(key)) != TYPE_INT and typeof(character.get(key)) != TYPE_FLOAT:
			return "%s must be money" % key
		if int(character[key]) < 0:
			return "%s cannot be negative" % key
	var paid_through: Variant = character.get("lifestyle_paid_through", null)
	if paid_through != null and not is_month(paid_through):
		return "invalid lifestyle_paid_through month"
	return ""


static func month_key(clock: Dictionary) -> String:
	return "%04d-%02d" % [int(clock["year"]), int(clock["month"])]


static func next_month_clock(clock: Dictionary) -> Dictionary:
	var moved: Dictionary = clock.duplicate(true)
	var month := int(clock["month"]) + 1
	var year := int(clock["year"])
	if month > 12:
		month = 1
		year += 1
	moved["year"] = year
	moved["month"] = month
	moved["day"] = 1
	return moved


static func settle(characters: Array, billed_month: String) -> Dictionary:
	var report := {
		"billed_month": billed_month,
		"paid": 0,
		"unpaid": 0,
		"total_charged": 0,
		"lines": [],
	}
	for value in characters:
		var character: Dictionary = value
		if not character.has("lifestyle"):
			continue
		ensure_character(character)
		var selected := profile(String(character["lifestyle"]))
		var cost := int(selected["cost"])
		if int(character["cash"]) >= cost:
			character["cash"] = int(character["cash"]) - cost
			character["lifestyle_status"] = "paid"
			character["lifestyle_paid_through"] = billed_month
			character["lifestyle_balance_due"] = 0
			character["lifestyle_grace_days"] = 0
			character["last_lifestyle_charge"] = cost
			report["paid"] = int(report["paid"]) + 1
			report["total_charged"] = int(report["total_charged"]) + cost
			(report["lines"] as Array).append(
				"%s paid %deb for %s" % [character["name"], cost, selected["label"]]
			)
		else:
			character["lifestyle_status"] = "unpaid"
			character["lifestyle_balance_due"] = cost
			character["lifestyle_grace_days"] = 7
			character["last_lifestyle_charge"] = 0
			report["unpaid"] = int(report["unpaid"]) + 1
			(report["lines"] as Array).append(
				"%s owes %deb for %s — 7-day grace"
				% [character["name"], cost, selected["label"]]
			)
		(report.get_or_add("results", []) as Array).append({
			"character_id": String(character.get("id", "")),
			"name": String(character.get("name", "")),
			"lifestyle": String(selected["key"]),
			"cost": cost,
			"deducted": cost if String(character["lifestyle_status"]) == "paid" else 0,
			"balance_due": int(character["lifestyle_balance_due"]),
			"status": String(character["lifestyle_status"]),
			"warning": "Seven-day grace period started" if String(character["lifestyle_status"]) == "unpaid" else "",
		})
	return report
