class_name Humanity
extends RefCounted

## What losing Humanity costs, and the point at which it costs the character.
##
## Cyberware already subtracted Humanity and therapy already gave it back, but
## nothing read the number: a character could be chromed to zero and play on
## unchanged. This is the other half. Humanity has bands, the low ones carry a
## penalty to the stat a character deals with people through, and the bottom of
## the scale takes the character away from the player.
##
## Pure like [Resolver] and [Mortality]: performs no I/O, mutates nothing it is
## handed, and returns every state change as an [Events] event.
##
## The constants below are working values carrying no page citation, because
## they were not checked line by line against a licensed copy. Treat them the
## way [TablesDefault] is treated.

const RULES := {
	## Below this, the character is gone: not dead, but no longer played.
	"cyberpsychosis_at_or_below": 0,
	## A band is this many points wide, counting down from full.
	"band_size": 10,
	## EMP is capped at the band, which is what makes chrome cost something
	## other than money.
	"empathy_follows_humanity": true,
	## The check a character makes when the chrome takes them under a band.
	"humanity_check_dv": 15,
}

const STABLE := "stable"
const STRAINED := "strained"
const DETACHED := "detached"
const BORDERLINE := "borderline"
const CYBERPSYCHOTIC := "cyberpsychotic"

const LABELS := {
	STABLE: "Stable",
	STRAINED: "Strained",
	DETACHED: "Detached",
	BORDERLINE: "Borderline",
	CYBERPSYCHOTIC: "Cyberpsychotic",
}

## What each band does to the character, in the GM's words rather than a number.
const NOTES := {
	STABLE: "Themselves.",
	STRAINED: "Short-tempered with people who are not on the crew.",
	DETACHED: "Reads other people as obstacles or tools.",
	BORDERLINE: "One bad night from going over. Therapy or nothing.",
	CYBERPSYCHOTIC: "No longer a player character.",
}


## The Empathy a character can actually use, which their Humanity caps.
##
## A character with 14 Humanity has an effective EMP of 1 however high the stat
## on the sheet says, and that is the number every social check uses.
static func effective_empathy(character: Dictionary) -> int:
	var stats: Dictionary = character.get("stats", {})
	var written := int(character.get("empathy", stats.get("EMP", 0)))
	if not bool(RULES["empathy_follows_humanity"]):
		return written
	@warning_ignore("integer_division")
	var capped := current(character) / int(RULES["band_size"])
	return mini(written, maxi(0, capped))


static func current(character: Dictionary) -> int:
	return maxi(0, int(character.get("humanity", 0)))


static func maximum(character: Dictionary) -> int:
	return maxi(1, int(character.get("max_humanity", 1)))


## The band [param value] falls in, given a ceiling of [param max_value].
##
## The bands are proportional rather than absolute, so a character built with a
## low EMP is not born halfway to cyberpsychosis.
static func state_for(value: int, max_value: int) -> String:
	if value <= int(RULES["cyberpsychosis_at_or_below"]):
		return CYBERPSYCHOTIC
	var ceiling := maxi(1, max_value)
	var fraction := float(value) / float(ceiling)
	if fraction <= 0.2:
		return BORDERLINE
	if fraction <= 0.4:
		return DETACHED
	if fraction <= 0.7:
		return STRAINED
	return STABLE


static func state_of(character: Dictionary) -> String:
	return state_for(current(character), maximum(character))


static func label(state: String) -> String:
	return String(LABELS.get(state, state.capitalize()))


static func note(state: String) -> String:
	return String(NOTES.get(state, ""))


static func is_lost(character: Dictionary) -> bool:
	return state_of(character) == CYBERPSYCHOTIC


## Take Humanity off a character, and report what that did to them.
##
## [param amount] is the loss — from installing chrome, or from whatever the GM
## decided the night cost them. Returns {"events", "card_lines", "lost",
## "state", "crossed"}, where "crossed" is true when this loss moved them into a
## worse band, which is the moment worth stopping the table for.
static func lose(character_id: String, character: Dictionary, amount: int) -> Dictionary:
	assert(amount > 0, "a Humanity loss must be positive")
	var before := current(character)
	var ceiling := maximum(character)
	var lost := mini(amount, before)
	var after := before - lost
	var was := state_for(before, ceiling)
	var now := state_for(after, ceiling)

	var events: Array[Dictionary] = []
	var lines := PackedStringArray()
	if lost > 0:
		events.append(
			{"kind": "humanity_lost", "target_id": character_id, "amount": lost}
		)
	lines.append("Humanity %d → %d of %d." % [before, after, ceiling])

	if now != was:
		events.append(
			{"kind": "humanity_state_set", "target_id": character_id, "state": now}
		)
		lines.append("%s — %s" % [label(now), note(now)])
	if now == CYBERPSYCHOTIC and was != CYBERPSYCHOTIC:
		lines.append("The character is lost. They belong to the GM now.")

	return {
		"events": events,
		"card_lines": lines,
		"lost": lost,
		"state": now,
		"crossed": now != was,
	}


## Give Humanity back, which is what therapy does a week at a time.
##
## Cyberpsychosis is not undone by climbing back over the line: a character who
## went under is gone, and the events that took them there are what the GM undoes
## if they want them back.
static func restore(character_id: String, character: Dictionary, amount: int) -> Dictionary:
	assert(amount > 0, "a Humanity gain must be positive")
	var before := current(character)
	var ceiling := maximum(character)
	var events: Array[Dictionary] = []
	var lines := PackedStringArray()

	if is_lost(character):
		lines.append("They are already gone. Undo the loss rather than treating it.")
		return {"events": events, "card_lines": lines, "restored": 0, "state": CYBERPSYCHOTIC}

	var restored := mini(amount, ceiling - before)
	if restored <= 0:
		lines.append("Already at %d of %d." % [before, ceiling])
		return {"events": events, "card_lines": lines, "restored": 0, "state": state_of(character)}

	var after := before + restored
	var now := state_for(after, ceiling)
	events.append({"kind": "humanity_restored", "target_id": character_id, "amount": restored})
	lines.append("Humanity %d → %d of %d." % [before, after, ceiling])
	if now != state_for(before, ceiling):
		events.append({"kind": "humanity_state_set", "target_id": character_id, "state": now})
		lines.append("%s — %s" % [label(now), note(now)])

	return {"events": events, "card_lines": lines, "restored": restored, "state": now}


## Keep a sheet's Humanity band honest about its own Humanity.
##
## The same reconciliation [CharacterRules] does for wound state, and for the
## same reason: three screens read the band, so it is derived rather than
## trusted. Cyberpsychosis is the exception, exactly as death is — a character
## the GM has taken away stays taken away until that is undone.
static func reconcile(character: Dictionary) -> void:
	if not character.has("humanity"):
		return
	character["humanity"] = clampi(current(character), 0, maximum(character))
	var stored := String(character.get("humanity_state", ""))
	if stored == CYBERPSYCHOTIC:
		return
	character["humanity_state"] = state_of(character)
