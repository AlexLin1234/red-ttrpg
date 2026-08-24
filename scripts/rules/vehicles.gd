class_name Vehicles
extends RefCounted

## Vehicles, and the chase they exist for.
##
## Pure like [Resolver] and [Netrun]: no I/O, nothing mutated, every state change
## returned as an [Events] event.
##
## A vehicle is modelled as an actor — SDP where a person has HP, SP where a
## person has armour — so a car takes fire through the same event kinds a Solo
## does, and a wreck undoes the same way a death does.
##
## The templates below are homebrew placeholders, exactly as [TablesDefault]'s
## weapons are. They are generic categories rather than a printed catalogue, and
## a GM who owns the book edits them in the garage.

const RULES := {
	## The gap, in range bands, that a chase starts at.
	"opening_gap": 3,
	## Open the gap this far and the quarry is gone.
	"escape_gap": 8,
	## Gap 0 is alongside, which is where ramming happens rather than where the
	## chase ends. It ends when the pursuer forces it below that.
	"caught_gap": -1,
	## However well an exchange goes, it moves the gap at most this far.
	"max_gap_shift": 3,
	## Ramming hurts both cars; the rammer takes this share of it.
	"ram_dice": 3,
	"sideswipe_dice": 2,
	## A shortcut that does not pay off puts the car into something.
	"crash_dice": 3,
}

const CAUGHT := "caught"
const ESCAPED := "escaped"
const WRECKED_PURSUER := "pursuer_wrecked"
const WRECKED_QUARRY := "quarry_wrecked"
const RUNNING := ""

## Homebrew placeholder vehicles. SDP is structure, SP is plating, handling is
## the modifier the driver gets on every chase check.
const TEMPLATES: Array[Dictionary] = [
	{
		"key": "bike",
		"name": "Street Bike",
		"kind": "ground",
		"sdp": 25,
		"sp": 5,
		"seats": 2,
		"handling": 3,
		"size_m": [2.0, 1.2, 0.8],
		"notes": "Fast, nimble, and nothing at all between the rider and the road.",
	},
	{
		"key": "compact",
		"name": "Compact Sedan",
		"kind": "ground",
		"sdp": 40,
		"sp": 8,
		"seats": 4,
		"handling": 1,
		"size_m": [4.2, 1.5, 1.8],
		"notes": "What most of Night City drives, and what most of it abandons.",
	},
	{
		"key": "muscle",
		"name": "Muscle Coupe",
		"kind": "ground",
		"sdp": 50,
		"sp": 10,
		"seats": 4,
		"handling": 2,
		"size_m": [4.8, 1.4, 1.9],
		"notes": "Built to be seen leaving.",
	},
	{
		"key": "van",
		"name": "Crew Van",
		"kind": "ground",
		"sdp": 60,
		"sp": 12,
		"seats": 8,
		"handling": 0,
		"size_m": [5.4, 2.1, 2.0],
		"notes": "The whole team, their gear, and no corners taken quickly.",
	},
	{
		"key": "armored",
		"name": "Armored Transport",
		"kind": "ground",
		"sdp": 80,
		"sp": 20,
		"seats": 6,
		"handling": -1,
		"size_m": [6.0, 2.4, 2.4],
		"notes": "Corporate. Slow. Very hard to open.",
	},
	{
		"key": "aerodyne",
		"name": "Aerodyne",
		"kind": "air",
		"sdp": 55,
		"sp": 15,
		"seats": 4,
		"handling": 2,
		"size_m": [7.0, 2.2, 3.0],
		"notes": "Ignores the street entirely, which is the point.",
	},
]

## What each side can try in an exchange, and what it risks.
##
## [code]min_gap[/code] and [code]max_gap[/code] are the range of gaps at which
## the manoeuvre is possible at all: you cannot ram someone you cannot reach.
const MANEUVERS: Array[Dictionary] = [
	{
		"key": "steady",
		"label": "Steady",
		"summary": "Drive. No edge, no risk.",
		"modifier": 0,
		"min_gap": 0,
		"max_gap": 99,
		"risk": "",
	},
	{
		"key": "push",
		"label": "Push it",
		"summary": "+2, and a lost exchange costs an extra band.",
		"modifier": 2,
		"min_gap": 0,
		"max_gap": 99,
		"risk": "overshoot",
	},
	{
		"key": "shortcut",
		"label": "Shortcut",
		"summary": "+3, and a lost exchange puts you into something.",
		"modifier": 3,
		"min_gap": 0,
		"max_gap": 99,
		"risk": "crash",
	},
	{
		"key": "sideswipe",
		"label": "Sideswipe",
		"summary": "Alongside only. Damage them, no edge on the gap.",
		"modifier": 0,
		"min_gap": 0,
		"max_gap": 1,
		"risk": "sideswipe",
	},
	{
		"key": "ram",
		"label": "Ram",
		"summary": "Alongside only. Hurts them more, and hurts you.",
		"modifier": -2,
		"min_gap": 0,
		"max_gap": 0,
		"risk": "ram",
	},
]


static func template(key: String) -> Dictionary:
	for entry in TEMPLATES:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return TEMPLATES[1]


static func maneuver(key: String) -> Dictionary:
	for entry in MANEUVERS:
		if String((entry as Dictionary)["key"]) == key:
			return entry
	return MANEUVERS[0]


## Which manoeuvres are possible at this gap.
static func maneuvers_at(gap: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in MANEUVERS:
		var candidate: Dictionary = entry
		if gap >= int(candidate["min_gap"]) and gap <= int(candidate["max_gap"]):
			found.append(candidate)
	return found


## Build a vehicle from a template. The result is the saved shape: a garage
## entry a GM can rename, re-plate and drive.
static func from_template(key: String, name := "") -> Dictionary:
	var spec := template(key)
	return {
		"id": "vehicle-%d" % Time.get_ticks_usec(),
		"template": String(spec["key"]),
		"name": name if name != "" else String(spec["name"]),
		"kind": String(spec["kind"]),
		"sdp": int(spec["sdp"]),
		"max_sdp": int(spec["sdp"]),
		"sp": int(spec["sp"]),
		"seats": int(spec["seats"]),
		"handling": int(spec["handling"]),
		"size_m": (spec["size_m"] as Array).duplicate(),
		"notes": String(spec["notes"]),
		"owner_id": "",
	}


## The actor shape [Events] already knows how to damage.
static func as_actor(vehicle: Dictionary) -> Dictionary:
	return {
		"name": String(vehicle.get("name", "Vehicle")),
		"max_hp": maxi(1, int(vehicle.get("max_sdp", vehicle.get("sdp", 1)))),
		"hp": int(vehicle.get("sdp", vehicle.get("max_sdp", 1))),
		"armor": {"body": maxi(0, int(vehicle.get("sp", 0)))},
		"weapons": {},
		"handling": int(vehicle.get("handling", 0)),
		"kind": String(vehicle.get("kind", "ground")),
	}


## A vehicle parked on an isometric board is cover with a wreck value: it stops
## bullets until it stops being a car. This turns one into a palette entry the
## Location screen can place like any other block.
static func as_cover(vehicle: Dictionary) -> Dictionary:
	var size: Array = vehicle.get("size_m", [4.2, 1.5, 1.8])
	return {
		"id": "vehicle-%s" % String(vehicle.get("id", "cover")),
		# "name", not "label": this has to be the same shape as every other entry
		# in the cover palette or the Location screen's props tab draws a blank.
		"name": String(vehicle.get("name", "Vehicle")),
		"material": "Vehicle Hulk",
		"destructible": true,
		"width": float(size[0]),
		"depth": float(size[1]),
		"height": float(size[2]),
		"hp": maxi(1, int(vehicle.get("sdp", 1))),
		"sp": maxi(0, int(vehicle.get("sp", 0))),
	}


static func is_wrecked(vehicle_actor: Dictionary) -> bool:
	return int(vehicle_actor.get("hp", 1)) <= 0


# -- the chase -------------------------------------------------------------------


## One driver's check: their Drive or Pilot total, the car's handling, the
## manoeuvre they chose, and a d10.
static func chase_check(
	driver_skill: int, handling: int, maneuver_key: String, rng: Dice.RandomSource
) -> Dictionary:
	var move := maneuver(maneuver_key)
	var check := Dice.roll_check(rng)
	return {
		"skill": driver_skill,
		"handling": handling,
		"maneuver": maneuver_key,
		"modifier": int(move["modifier"]),
		"rolls": check["rolls"],
		"total": driver_skill + handling + int(move["modifier"]) + int(check["total"]),
	}


static func _check_line(label: String, check: Dictionary) -> String:
	var pieces := PackedStringArray()
	for value in check.get("rolls", PackedInt32Array()):
		pieces.append(str(value))
	return (
		"%s: drive %d + handling %d %+d %s + d10 [%s] = %d"
		% [
			label,
			int(check["skill"]),
			int(check["handling"]),
			int(check["modifier"]),
			String(maneuver(String(check["maneuver"]))["label"]),
			", ".join(pieces),
			int(check["total"]),
		]
	)


## Resolve one exchange of a chase.
##
## Both sides roll, the margin moves the gap, and whatever each side risked to
## get its edge is collected afterwards. Returns {"events", "card_lines",
## "gap", "title"} with [code]gap[/code] the new gap.
static func exchange(
	pursuer: Dictionary, quarry: Dictionary, moves: Dictionary, gap: int, rng: Dice.RandomSource
) -> Dictionary:
	var pursuer_move := String(moves.get("pursuer", "steady"))
	var quarry_move := String(moves.get("quarry", "steady"))
	var pursuer_check := chase_check(
		int(pursuer.get("driver_skill", 0)), int(pursuer.get("handling", 0)), pursuer_move, rng
	)
	var quarry_check := chase_check(
		int(quarry.get("driver_skill", 0)), int(quarry.get("handling", 0)), quarry_move, rng
	)

	var margin := int(quarry_check["total"]) - int(pursuer_check["total"])
	var limit := int(RULES["max_gap_shift"])
	var shift := clampi(margin, -limit, limit)

	var lines := PackedStringArray(
		[_check_line("Pursuer", pursuer_check), _check_line("Quarry", quarry_check)]
	)
	var events: Array[Dictionary] = []

	# Pushing it costs the loser an extra band; the winner's push is free.
	if pursuer_move == "push" and shift > 0:
		shift += 1
		lines.append("The pursuer overcooked it: one more band.")
	if quarry_move == "push" and shift < 0:
		shift -= 1
		lines.append("The quarry overcooked it: one more band.")

	# The gap stops at "run down" rather than running away negative, so the
	# recorded event carries the distance actually travelled.
	var next_gap := maxi(int(RULES["caught_gap"]), gap + shift)
	var delta := next_gap - gap
	if delta > 0:
		events.append({"kind": "chase_gap_opened", "amount": delta})
		lines.append("The quarry pulls away: gap %d → %d." % [gap, next_gap])
	elif delta < 0:
		events.append({"kind": "chase_gap_closed", "amount": -delta})
		lines.append("The pursuer closes: gap %d → %d." % [gap, next_gap])
	else:
		lines.append("Neither gains: gap holds at %d." % gap)

	var risks := _collect_risks(pursuer_move, quarry_move, shift, gap, rng)
	events.append_array(risks["events"] as Array[Dictionary])
	lines.append_array(risks["card_lines"])

	return {
		"events": events,
		"card_lines": lines,
		"gap": next_gap,
		"title": "GAP %d" % next_gap,
	}


## What each side's manoeuvre costs it once the exchange is settled.
static func _collect_risks(
	pursuer_move: String, quarry_move: String, shift: int, gap: int, rng: Dice.RandomSource
) -> Dictionary:
	var events: Array[Dictionary] = []
	var lines := PackedStringArray()

	if pursuer_move == "shortcut" and shift > 0:
		var hit := _crash("pursuer", int(RULES["crash_dice"]), rng)
		events.append_array(hit["events"] as Array[Dictionary])
		lines.append_array(hit["card_lines"])
	if quarry_move == "shortcut" and shift < 0:
		var hit := _crash("quarry", int(RULES["crash_dice"]), rng)
		events.append_array(hit["events"] as Array[Dictionary])
		lines.append_array(hit["card_lines"])

	if gap <= 1:
		if pursuer_move == "sideswipe":
			var hit := _collide("pursuer", "quarry", int(RULES["sideswipe_dice"]), rng, false)
			events.append_array(hit["events"] as Array[Dictionary])
			lines.append_array(hit["card_lines"])
		if quarry_move == "sideswipe":
			var hit := _collide("quarry", "pursuer", int(RULES["sideswipe_dice"]), rng, false)
			events.append_array(hit["events"] as Array[Dictionary])
			lines.append_array(hit["card_lines"])
	if gap == 0:
		if pursuer_move == "ram":
			var hit := _collide("pursuer", "quarry", int(RULES["ram_dice"]), rng, true)
			events.append_array(hit["events"] as Array[Dictionary])
			lines.append_array(hit["card_lines"])
		if quarry_move == "ram":
			var hit := _collide("quarry", "pursuer", int(RULES["ram_dice"]), rng, true)
			events.append_array(hit["events"] as Array[Dictionary])
			lines.append_array(hit["card_lines"])

	return {"events": events, "card_lines": lines}


static func _crash(actor_id: String, dice: int, rng: Dice.RandomSource) -> Dictionary:
	var damage := Dice.damage_roll(dice, rng)
	var total := int(damage["total"])
	return {
		"events":
		[{"kind": "damage_taken", "target_id": actor_id, "amount": total}] as Array[Dictionary],
		"card_lines":
		PackedStringArray(["The shortcut did not pay off: %d SDP to the %s." % [total, actor_id]]),
	}


## A collision. Ramming is the version where the rammer takes half of it too.
static func _collide(
	actor_id: String, target_id: String, dice: int, rng: Dice.RandomSource, mutual: bool
) -> Dictionary:
	var damage := Dice.damage_roll(dice, rng)
	var total := int(damage["total"])
	var events: Array[Dictionary] = [
		{"kind": "damage_taken", "target_id": target_id, "amount": total}
	]
	var lines := PackedStringArray(
		["%s connects: %d SDP to the %s." % [actor_id.capitalize(), total, target_id]]
	)
	if mutual:
		@warning_ignore("integer_division")
		var back := total / 2
		if back > 0:
			events.append({"kind": "damage_taken", "target_id": actor_id, "amount": back})
			lines.append("And %d back to the %s." % [back, actor_id])
	return {"events": events, "card_lines": lines}


## Has this chase ended, and how?
static func outcome_for(gap: int, pursuer: Dictionary, quarry: Dictionary) -> String:
	if is_wrecked(pursuer):
		return WRECKED_PURSUER
	if is_wrecked(quarry):
		return WRECKED_QUARRY
	if gap >= int(RULES["escape_gap"]):
		return ESCAPED
	if gap <= int(RULES["caught_gap"]):
		return CAUGHT
	return RUNNING


static func outcome_label(outcome: String) -> String:
	match outcome:
		CAUGHT:
			return "Caught — run down"
		ESCAPED:
			return "Escaped — gone"
		WRECKED_PURSUER:
			return "The pursuer is wrecked"
		WRECKED_QUARRY:
			return "The quarry is wrecked"
		_:
			return "Still running"
