class_name Luck
extends RefCounted

## The Luck pool, and spending out of it.
##
## LUCK has always been on the sheet as a stat, but nothing spent it, so it sat
## there as a number that did not do anything. This is the part that does: a
## character starts each session with LUCK points, adds any number of them to a
## check before it is rolled, and gets none of them back until the pool is
## refreshed.
##
## Pure like [Resolver] and [Mortality]: performs no I/O, mutates nothing it is
## handed, and returns every state change as an [Events] event so the GM's undo
## stays exact.
##
## The constants below are working values carrying no page citation, because
## they were not checked line by line against a licensed copy. Treat them the
## way [TablesDefault] is treated.

const RULES := {
	## Luck is declared before the die is rolled, never after seeing it. The
	## screen enforces that by offering the spend on the way into a check.
	"spend_before_roll": true,
	## A refresh is a session boundary, not a night's sleep: the pool comes back
	## whole when the table sits down, however much in-game time has passed.
	"refresh_to_full": true,
}


## The points [param character] has left to spend.
static func available(character: Dictionary) -> int:
	return maxi(0, int(character.get("luck_available", 0)))


## The size of the pool the character refreshes to.
static func pool(character: Dictionary) -> int:
	var stats: Dictionary = character.get("stats", {})
	return maxi(0, int(character.get("luck", stats.get("LUCK", 0))))


## Give a sheet a Luck pool if it has never had one.
##
## Sheets written before Luck was spendable carry a LUCK stat and no pool. They
## start full rather than empty: a character who has never spent a point has
## spent none of them.
static func ensure(character: Dictionary) -> void:
	if not character.has("luck_available"):
		character["luck_available"] = pool(character)
		return
	character["luck_available"] = clampi(
		int(character["luck_available"]), 0, pool(character)
	)


## Spend [param amount] points, raising the check that follows by the same
## number.
##
## Returns {"events", "card_lines", "spent", "ok"}. Asking for more than the
## character has is refused rather than clamped: the GM chose a number, and
## quietly spending a different one would be a worse answer than saying no.
static func spend(character_id: String, character: Dictionary, amount: int) -> Dictionary:
	var lines := PackedStringArray()
	var events: Array[Dictionary] = []
	if amount <= 0:
		lines.append("Spend at least one point of Luck.")
		return {"events": events, "card_lines": lines, "spent": 0, "ok": false}

	var have := available(character)
	if amount > have:
		lines.append(
			"%s has %d point%s of Luck left, not %d."
			% [String(character.get("name", character_id)), have, "" if have == 1 else "s", amount]
		)
		return {"events": events, "card_lines": lines, "spent": 0, "ok": false}

	events.append({"kind": "luck_spent", "target_id": character_id, "amount": amount})
	lines.append(
		"Luck: %+d to the check, %d point%s left."
		% [amount, have - amount, "" if have - amount == 1 else "s"]
	)
	return {"events": events, "card_lines": lines, "spent": amount, "ok": true}


## Put the pool back to full, which is what starting a session does.
static func refresh(character_id: String, character: Dictionary) -> Dictionary:
	var have := available(character)
	var full := pool(character)
	var events: Array[Dictionary] = []
	var lines := PackedStringArray()
	if have >= full:
		lines.append("Luck is already full at %d." % full)
		return {"events": events, "card_lines": lines, "restored": 0}
	events.append(
		{"kind": "luck_restored", "target_id": character_id, "amount": full - have}
	)
	lines.append("Luck: %d → %d." % [have, full])
	return {"events": events, "card_lines": lines, "restored": full - have}
