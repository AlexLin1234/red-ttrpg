class_name CampaignFixtures
extends RefCounted

## Demo content.
##
## "Blackwall Sunrise" is the campaign shown throughout the UI mockups. It seeds
## a fresh install so every screen has something real to draw. The lighter saves
## exist to fill out the library list.


static func _stats(overrides := {}) -> Dictionary:
	var stats := {
		"INT": 5, "REF": 5, "DEX": 5, "TECH": 4, "COOL": 5,
		"WILL": 5, "LUCK": 4, "MOVE": 5, "BODY": 5, "EMP": 5,
	}
	stats.merge(overrides, true)
	return stats


static func _armor(sp: int, ablated := {}) -> Dictionary:
	var armor := {}
	for location in Resolver.HIT_LOCATIONS:
		if ablated.has(location):
			armor[location] = {"sp": int(ablated[location]), "ablated": true}
		else:
			armor[location] = {"sp": sp, "ablated": false}
	return armor


static func _skills(rows: Array) -> Array:
	var skills: Array = []
	for row in rows:
		skills.append({"name": String(row[0]), "stat": String(row[1]), "level": int(row[2])})
	return skills


static func _weapon(name: String, ammo: int, weapon_type: String, dice: int, rof := 2, autofire := -1) -> Dictionary:
	return {
		"name": name,
		"ammo": ammo,
		"magazine": ammo,
		"weapon_type": weapon_type,
		"damage_dice": dice,
		"rof": rof,
		"autofire_rating": autofire,
		"quality": "standard",
		"jammed": false,
	}


static func cover_palette() -> Array:
	return [
		{
			"id": "cover-jersey",
			"name": "Concrete Jersey Barrier",
			"material": "Concrete",
			"height": 1.2, "width": 2.0, "depth": 1.0,
			"sp": 15, "hp": 30, "destructible": true,
		},
		{
			"id": "cover-crate",
			"name": "Market Crate",
			"material": "Wood Crate",
			"height": 1.1, "width": 1.2, "depth": 1.2,
			"sp": 5, "hp": 12, "destructible": true,
		},
		{
			"id": "cover-hulk",
			"name": "Burned-Out Hatchback",
			"material": "Vehicle Hulk",
			"height": 1.5, "width": 4.0, "depth": 1.8,
			"sp": 12, "hp": 50, "destructible": true,
		},
		{
			"id": "cover-pillar",
			"name": "Parkade Pillar",
			"material": "Concrete",
			"height": 3.0, "width": 0.8, "depth": 0.8,
			"sp": 15, "hp": 30, "destructible": false,
		},
		{
			"id": "cover-vending",
			"name": "Vending Kiosk",
			"material": "Sheet Metal",
			"height": 2.0, "width": 1.0, "depth": 0.8,
			"sp": 7, "hp": 15, "destructible": true,
		},
	]


static func _party() -> Array:
	return [
		{
			"id": "spike", "name": "Spike Adebayo", "role": "Solo", "kind": "pc", "side": "party",
			"tags": ["PC", "RECURRING"],
			"stats": _stats({"INT": 6, "REF": 7, "DEX": 7, "COOL": 6, "WILL": 6, "LUCK": 5, "MOVE": 6, "BODY": 8, "EMP": 4}),
			"skills": _skills([["Handgun", "REF", 6], ["Shoulder Arms", "REF", 4], ["Evasion", "DEX", 5], ["Athletics", "BODY", 4], ["Perception", "INT", 4]]),
			"gear": [
				{"name": "Heavy Sidearm", "kind": "weapon", "detail": "3d6"},
				{"name": "Light Plate", "kind": "armor", "detail": "SP11"},
				{"name": "Kerenzikov", "kind": "cyberware", "detail": "+2 initiative", "humanity_cost": 7},
			],
			"armor": _armor(11),
			"hp": 42, "max_hp": 45, "humanity": 32, "max_humanity": 40,
			"cash": 5000, "lifestyle": "fresh_food",
			"weapons": [_weapon("Heavy Sidearm", 8, "pistol", 3)],
		},
		{
			"id": "mira", "name": "Mira Vega", "role": "Netrunner", "kind": "pc", "side": "party",
			"tags": ["PC", "JACKED IN"],
			"stats": _stats({"INT": 8, "REF": 6, "DEX": 6, "TECH": 7, "WILL": 6, "LUCK": 6}),
			"skills": _skills([["Interface", "INT", 6], ["Handgun", "REF", 3], ["Evasion", "DEX", 4], ["Perception", "INT", 5], ["Electronics", "TECH", 5]]),
			"gear": [
				{"name": "Service Sidearm", "kind": "weapon", "detail": "2d6"},
				{"name": "Kevlar Weave", "kind": "armor", "detail": "SP7"},
				{"name": "Neural Link", "kind": "cyberware", "detail": "interface plugs", "humanity_cost": 2},
			],
			"armor": _armor(7),
			"hp": 28, "max_hp": 38, "humanity": 40, "max_humanity": 50,
			"cash": 1000, "lifestyle": "good_prepak",
			"weapons": [_weapon("Service Sidearm", 12, "pistol", 2)],
		},
		{
			"id": "tallow", "name": "Doc Tallow", "role": "Medtech", "kind": "pc", "side": "party",
			"tags": ["PC", "SERIOUSLY WOUNDED"],
			"stats": _stats({"INT": 7, "DEX": 6, "TECH": 8, "WILL": 6, "BODY": 6, "EMP": 7}),
			"skills": _skills([["First Aid", "TECH", 6], ["Surgery", "TECH", 5], ["Handgun", "REF", 3], ["Perception", "INT", 4], ["Evasion", "DEX", 3]]),
			"gear": [
				{"name": "Light Sidearm", "kind": "weapon", "detail": "1d6"},
				{"name": "Kevlar Weave", "kind": "armor", "detail": "SP7"},
				{"name": "Medscanner", "kind": "gear"},
			],
			"armor": _armor(7),
			"hp": 11, "max_hp": 40, "humanity": 38, "max_humanity": 50,
			"cash": 250, "lifestyle": "generic_prepak",
			"weapons": [_weapon("Light Sidearm", 12, "pistol", 1)],
		},
		{
			"id": "brick", "name": "Brick Osei", "role": "Solo", "kind": "pc", "side": "party",
			"tags": ["PC", "BORGWARE"],
			"stats": _stats({"REF": 7, "DEX": 6, "COOL": 6, "WILL": 7, "MOVE": 6, "BODY": 9, "EMP": 3}),
			"skills": _skills([["Shoulder Arms", "REF", 6], ["Melee Weapon", "DEX", 5], ["Athletics", "BODY", 5], ["Evasion", "DEX", 3], ["Endurance", "WILL", 4]]),
			"gear": [
				{"name": "Service Rifle", "kind": "weapon", "detail": "5d6, autofire 4"},
				{"name": "Heavy Plate", "kind": "armor", "detail": "SP13"},
				{"name": "Subdermal Armor", "kind": "cyberware", "detail": "SP13", "humanity_cost": 7},
			],
			"armor": _armor(13),
			"hp": 50, "max_hp": 50, "humanity": 28, "max_humanity": 40,
			"cash": 500, "lifestyle": "kibble",
			"weapons": [_weapon("Service Rifle", 25, "assault_rifle", 5, 1, 4)],
		},
	]


static func _npcs() -> Array:
	var roster: Array = [
		{
			"id": "ninevolt", "name": 'Kestrel "Nine-Volt"', "role": "Solo — Maelstrom Lieutenant",
			"kind": "npc", "side": "hostile",
			"tags": ["HOSTILE", "RANK & SOLO", "BORGWARE", "RECURRING"],
			"stats": _stats({"INT": 5, "REF": 8, "DEX": 8, "COOL": 7, "WILL": 7, "LUCK": 3, "MOVE": 7, "BODY": 9, "EMP": 2}),
			"skills": _skills([["Handgun", "REF", 6], ["Shoulder Arms", "REF", 5], ["Melee Weapon", "REF", 6], ["Evasion", "DEX", 5], ["Athletics", "BODY", 4], ["Interrogation", "COOL", 4], ["Perception", "INT", 4]]),
			"gear": [
				{"name": "Hand Cannon", "kind": "weapon", "detail": "4d6"},
				{"name": "Heavy SMG", "kind": "weapon", "detail": "3d6, autofire 3"},
				{"name": "Monowire", "kind": "weapon", "detail": "2d6 AP"},
				{"name": "Sandevistan", "kind": "cyberware", "detail": "+3 initiative", "humanity_cost": 3},
				{"name": "Kerenzikov", "kind": "cyberware", "detail": "+2 initiative", "humanity_cost": 7},
				{"name": "Subdermal Armor", "kind": "cyberware", "detail": "SP11", "humanity_cost": 7},
				{"name": "Cybereye", "kind": "cyberware", "detail": "low-light", "humanity_cost": 2},
			],
			"armor": _armor(11, {"left_arm": 7, "right_leg": 9}),
			"hp": 45, "max_hp": 45, "humanity": 18, "max_humanity": 40,
			"weapons": [_weapon("Hand Cannon", 8, "pistol", 4, 1), _weapon("Heavy SMG", 40, "smg", 3, 1, 3)],
		},
		{
			"id": "ninetails", "name": "Ninetails", "role": "Fixer — Westbrook", "kind": "npc", "side": "neutral",
			"tags": ["NPC", "FIXER"],
			"stats": _stats({"INT": 7, "COOL": 8, "WILL": 6, "LUCK": 7, "BODY": 4, "EMP": 7}),
			"skills": _skills([["Persuasion", "COOL", 6], ["Streetwise", "COOL", 6], ["Trading", "INT", 5], ["Perception", "INT", 4]]),
			"gear": [{"name": "Light Sidearm", "kind": "weapon", "detail": "1d6"}],
			"armor": _armor(4),
			"hp": 30, "max_hp": 30, "humanity": 45, "max_humanity": 50,
			"weapons": [_weapon("Light Sidearm", 12, "pistol", 1)],
		},
		{
			"id": "annika", "name": "Dr. Annika Ross", "role": "Ripperdoc — Watson", "kind": "npc", "side": "neutral",
			"tags": ["NPC", "RIPPERDOC"],
			"stats": _stats({"INT": 8, "REF": 4, "DEX": 6, "TECH": 8, "BODY": 4, "EMP": 6}),
			"skills": _skills([["Surgery", "TECH", 7], ["First Aid", "TECH", 6], ["Perception", "INT", 4]]),
			"gear": [{"name": "Surgery Suite", "kind": "gear"}],
			"armor": _armor(0),
			"hp": 28, "max_hp": 28, "humanity": 48, "max_humanity": 50,
			"weapons": [],
		},
		{
			"id": "halvorsen", "name": "Sgt. Halvorsen", "role": "NCPD — City Center", "kind": "npc", "side": "neutral",
			"tags": ["NPC", "NCPD"],
			"stats": _stats({"INT": 6, "REF": 7, "DEX": 6, "COOL": 7, "WILL": 7, "MOVE": 6, "BODY": 7}),
			"skills": _skills([["Handgun", "REF", 5], ["Shoulder Arms", "REF", 4], ["Interrogation", "COOL", 5], ["Perception", "INT", 5]]),
			"gear": [
				{"name": "Service Sidearm", "kind": "weapon", "detail": "2d6"},
				{"name": "Light Plate", "kind": "armor", "detail": "SP11"},
			],
			"armor": _armor(11),
			"hp": 40, "max_hp": 40, "humanity": 42, "max_humanity": 50,
			"weapons": [_weapon("Service Sidearm", 12, "pistol", 2)],
		},
		{
			"id": "courier", "name": "The Courier", "role": "Plot — location unknown", "kind": "npc", "side": "neutral",
			"tags": ["HOOK", "PLOT"],
			"stats": _stats({"INT": 6, "REF": 6, "DEX": 7, "LUCK": 6, "MOVE": 7}),
			"skills": _skills([["Athletics", "BODY", 6], ["Stealth", "DEX", 6], ["Evasion", "DEX", 5]]),
			"gear": [{"name": "Data Shard", "kind": "gear", "detail": "the Arasoma leak"}],
			"armor": _armor(4),
			"hp": 30, "max_hp": 30, "humanity": 44, "max_humanity": 50,
			"weapons": [],
		},
	]

	for index in range(1, 13):
		roster.append(
			{
				"id": "booster-%d" % index,
				"name": "Booster %d" % index,
				"role": "Mook",
				"kind": "mook",
				"side": "hostile",
				"tags": ["MOOK", "MAELSTROM"],
				"stats": _stats({"COOL": 4, "WILL": 4, "EMP": 3}),
				"skills": _skills([["Handgun", "REF", 3], ["Evasion", "DEX", 2]]),
				"gear": [{"name": "Service Sidearm", "kind": "weapon", "detail": "2d6"}],
				"armor": _armor(4),
				"hp": 25, "max_hp": 25, "humanity": 30, "max_humanity": 40,
				"weapons": [_weapon("Service Sidearm", 12, "pistol", 2)],
			}
		)
	return roster


## The Kabuki parkade from mockup 1C: a deck with pillars, barriers and a wreck.
static func kabuki_parkade() -> Dictionary:
	var tiles: Array = []
	for x in 20:
		for z in 20:
			# A ramp bites a corner out of the deck, which the mockup shows as a gap.
			if x > 15 and z > 15:
				continue
			tiles.append({"x": x, "z": z, "layer": 0, "tile_id": "deck", "rotation": 0})

	return {
		"id": "kabuki-parkade",
		"name": "Kabuki Parkade — Level 2",
		"district_id": "watson",
		"grid_width": 20,
		"grid_height": 20,
		"tile_metres": 2.0,
		"layers": 3,
		"tiles": tiles,
		"props": [
			{"id": "prop-pillar-a", "cover_id": "cover-pillar", "x": 6, "z": 6, "layer": 0, "rotation": 0, "hp": 30},
			{"id": "prop-pillar-b", "cover_id": "cover-pillar", "x": 13, "z": 6, "layer": 0, "rotation": 0, "hp": 30},
			{"id": "prop-pillar-c", "cover_id": "cover-pillar", "x": 6, "z": 13, "layer": 0, "rotation": 0, "hp": 30},
			{"id": "prop-pillar-d", "cover_id": "cover-pillar", "x": 13, "z": 13, "layer": 0, "rotation": 0, "hp": 30},
			{"id": "prop-jersey-a", "cover_id": "cover-jersey", "x": 9, "z": 8, "layer": 0, "rotation": 0, "hp": 30},
			{"id": "prop-jersey-b", "cover_id": "cover-jersey", "x": 10, "z": 12, "layer": 0, "rotation": 90, "hp": 30},
			{"id": "prop-hulk", "cover_id": "cover-hulk", "x": 15, "z": 9, "layer": 0, "rotation": 0, "hp": 50},
			{"id": "prop-crate-a", "cover_id": "cover-crate", "x": 4, "z": 10, "layer": 0, "rotation": 0, "hp": 12},
			{"id": "prop-kiosk", "cover_id": "cover-vending", "x": 17, "z": 4, "layer": 0, "rotation": 0, "hp": 15},
		],
		"units": [
			{"id": "unit-spike", "character_id": "spike", "x": 4, "z": 15, "layer": 0},
			{"id": "unit-mira", "character_id": "mira", "x": 6, "z": 17, "layer": 0},
			{"id": "unit-tallow", "character_id": "tallow", "x": 3, "z": 12, "layer": 0},
			{"id": "unit-ninevolt", "character_id": "ninevolt", "x": 14, "z": 5, "layer": 0},
			{"id": "unit-booster-1", "character_id": "booster-1", "x": 12, "z": 9, "layer": 0},
			{"id": "unit-booster-2", "character_id": "booster-2", "x": 16, "z": 11, "layer": 0},
		],
	}


static func blackwall_sunrise() -> Dictionary:
	var characters: Array = []
	characters.append_array(_party())
	characters.append_array(_npcs())

	return {
		"campaign":
		{
			"id": "blackwall-sunrise",
			"name": "Blackwall Sunrise",
			"arc": 'Arc 2 "The Arasoma Leak"',
			"city": "Night City",
			"gm": "V. Okonkwo",
			"players": 4,
			"sessions": 14,
			"clock": {"year": 2045, "month": 9, "day": 14, "hour": 21, "minute": 47},
			"current_month": "2045-09", "closed_months": [],
			"weather": {"condition": "Acid Rain", "temperature_c": 18, "visibility_pct": 40},
			"session_log":
			[
				{"session": 14, "text": "Party breached the Kabuki parkade and lost the courier in the stairwell."},
				{"session": 14, "text": "Doc Tallow took 22 from an autofire burst — still at Seriously Wounded."},
				{"session": 13, "text": "Mira traced the Arasoma leak to a dead drop under the Pacifica pier."},
				{"session": 13, "text": "Maelstrom marked the party. Watson heat raised to 4."},
				{"session": 12, "text": 'Fixer "Ninetails" advanced 3,000eb against the courier job.'},
			],
			"hooks":
			[
				{"id": "hook-extraction", "district_id": "pacifica", "title": "Extraction", "detail": "Arasoma counter-grab goes dark tonight.", "status": "open"},
				{"id": "hook-pier", "district_id": "pacifica", "title": "Pier Generator", "detail": "Fixer wants the pier generator back online.", "status": "open"},
				{"id": "hook-courier", "district_id": "watson", "title": "The Courier", "detail": "Lost in the Kabuki parkade stairwell with the leak shard.", "status": "running"},
				{"id": "hook-heat", "district_id": "watson", "title": "Maelstrom Marker", "detail": "The party is marked. Heat 4 and climbing.", "status": "open"},
				{"id": "hook-audit", "district_id": "city-center", "title": "Internal Audit", "detail": "Arasoma is auditing its own leak. Someone inside is helping.", "status": "open"},
			],
			"districts":
			{
				"watson": {"heat": 4, "note": "Party marked by Maelstrom."},
				"pacifica": {"note": "Pier generator dark since session 12."},
			},
			"cover_palette": cover_palette(),
			# Pins the party already knows about. Only the parkade has a board
			# behind it; the rest are notes until the GM builds one.
			"points_of_interest":
			[
				{
					"id": "poi-parkade",
					"name": "Kabuki Parkade",
					"kind": "landmark",
					"area_id": "watson",
					"x": 150.0, "y": 470.0,
					"description": "Where the courier went into the stairwell and did not come out.",
					"location_id": "kabuki-parkade",
				},
				{
					"id": "poi-clinic",
					"name": "Ross Clinic",
					"kind": "clinic",
					"area_id": "watson",
					"x": 95.0, "y": 570.0,
					"description": "Dr. Annika Ross. Cash, no questions, closes at dawn.",
					"location_id": "",
				},
				{
					"id": "poi-booth",
					"name": "Ninetails' Booth",
					"kind": "contact",
					"area_id": "westbrook",
					"x": 690.0, "y": 95.0,
					"description": "Back of the club. She advances against jobs, at a rate.",
					"location_id": "",
				},
				{
					"id": "poi-pier",
					"name": "Pacifica Pier",
					"kind": "hazard",
					"area_id": "pacifica",
					"x": 690.0, "y": 545.0,
					"description": "Dead drop under the boards. Generator has been dark since session 12.",
					"location_id": "",
				},
				{
					"id": "poi-arasoma",
					"name": "Arasoma Tower",
					"kind": "corp",
					"area_id": "city-center",
					"x": 430.0, "y": 255.0,
					"description": "Forty floors of deniability. The leak came from somewhere inside.",
					"location_id": "",
				},
			],
			"restore_points":
			[
				{"id": "restore-parkade", "label": "Before the Parkade", "session": 14, "created_at": "2045-09-14T21:12:00"},
				{"id": "restore-session-13", "label": "End of Session 13", "session": 13, "created_at": "2045-09-07T23:48:00"},
				{"id": "restore-arc-2", "label": "Arc 2 Start", "session": 11, "created_at": "2045-08-24T19:30:00"},
			],
		},
		"roster": {"characters": characters},
		"locations": [kabuki_parkade()],
	}


## The lighter saves that fill out the library list in mockup 1A.
static func library_fillers() -> Array:
	var rows := [
		["pistol-club", "The Pistol Club", "Night City", 5, 31, "Session 31"],
		["rust-revelation", "Rust & Revelation", "Badlands", 3, 7, "Session 7"],
		["arasoma-internal", "Arasoma Internal", "City Center", 4, 2, "Session 2"],
		["downtime-sandbox", "Downtime Sandbox", "Unset", 0, 0, "Prep only"],
		["one-shot-pacifica", "One-Shot: Pacifica", "Pacifica", 6, 1, "Complete"],
	]
	var bundles: Array = []
	for row in rows:
		bundles.append(
			{
				"campaign":
				{
					"id": row[0], "name": row[1], "arc": row[5], "city": row[2],
					"gm": "V. Okonkwo", "players": row[3], "sessions": row[4],
					"clock": {"year": 2045, "month": 6, "day": 2, "hour": 14, "minute": 0},
					"current_month": "2045-06", "closed_months": [],
					"weather": {"condition": "Smog", "temperature_c": 24, "visibility_pct": 65},
					"session_log": [], "hooks": [], "districts": {},
					"cover_palette": cover_palette(), "restore_points": [],
				},
				"roster": {"characters": []},
				"locations": [],
			}
		)
	return bundles


static func new_campaign(name: String) -> Dictionary:
	return {
		"campaign":
		{
			"id": "campaign-%d" % Time.get_ticks_msec(),
			"name": name,
			"arc": "Arc 1",
			"city": "Night City",
			"gm": "",
			"players": 0,
			"sessions": 0,
			"clock": {"year": 2045, "month": 1, "day": 1, "hour": 20, "minute": 0},
			"current_month": "2045-01", "closed_months": [],
			"weather": {"condition": "Clear", "temperature_c": 20, "visibility_pct": 90},
			"session_log": [], "hooks": [], "districts": {},
			"lifestyle_closed_months": [], "last_lifestyle_report": {}, "gm_map": {},
			"cover_palette": cover_palette(), "restore_points": [],
		},
		"roster": {"characters": []},
		"locations": [],
	}


## Turn a saved character into the shape the encounter engine wants.
static func actor_input(character: Dictionary) -> Dictionary:
	var weapons := {}
	for weapon in character.get("weapons", []):
		var entry: Dictionary = weapon
		weapons[String(entry["name"])] = {
			"ammo": int(entry.get("ammo", 0)),
			"magazine": int(entry.get("magazine", entry.get("ammo", 1))),
			"weapon_type": String(entry.get("weapon_type", "pistol")),
			"damage_dice": int(entry.get("damage_dice", 1)),
			"rof": int(entry.get("rof", 1)),
			"autofire_rating": int(entry.get("autofire_rating", -1)),
			"quality": String(entry.get("quality", "standard")),
			"jammed": bool(entry.get("jammed", false)),
		}

	var stats: Dictionary = character.get("stats", {})
	var armor := {}
	for location in (character.get("armor", {}) as Dictionary):
		armor[location] = int((character["armor"][location] as Dictionary)["sp"])

	var attack_base := int(stats.get("REF", 0))
	var evasion_base := int(stats.get("DEX", 0))
	var skill_map := {}
	for skill in character.get("skills", []):
		var row: Dictionary = skill
		var total := CampaignSchema.skill_total(stats, row)
		skill_map[String(row["name"])] = total
		if String(row["name"]) in ["Handgun", "Shoulder Arms", "Melee Weapon"]:
			attack_base = maxi(attack_base, total)
		if String(row["name"]) == "Evasion":
			evasion_base = total

	var first_weapon: String = ""
	if not (character.get("weapons", []) as Array).is_empty():
		first_weapon = String((character["weapons"][0] as Dictionary)["name"])

	return {
		"name": String(character["name"]),
		"max_hp": int(character["max_hp"]),
		"hp": int(character["hp"]),
		"armor": armor,
		"ref": int(stats.get("REF", 0)),
		"stats": stats,
		"side": String(character.get("side", "neutral")),
		"attack_base": attack_base,
		"evasion_base": evasion_base,
		"selected_weapon": first_weapon,
		"skills": skill_map,
		"weapons": weapons,
	}


## An empty board, sized like the seeded parkade so a new place is immediately
## workable rather than a blank slate the GM has to tile from scratch.
static func new_location(name: String, district_id: String) -> Dictionary:
	var tiles: Array = []
	for x in 16:
		for z in 16:
			tiles.append({"x": x, "z": z, "layer": 0, "tile_id": "deck", "rotation": 0})
	return {
		"id": "location-%d" % Time.get_ticks_usec(),
		"name": name,
		"district_id": district_id,
		"grid_width": 16,
		"grid_height": 16,
		"tile_metres": 2.0,
		"layers": 3,
		"tiles": tiles,
		"props": [],
		"units": [],
	}
