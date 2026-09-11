class_name LifepathDefault
extends RefCounted

## Homebrew placeholder Lifepath tables.
##
## These are NOT book data, exactly as [TablesDefault] and [NetrunDefault] are
## not. Redline ships no sourcebook content; a GM who owns the book replaces
## every row below in the Rules screen or imports their own JSON in this shape.
##
## What is real here is the *shape* — which questions a lifepath asks, in what
## order, and how a role's own path hangs off the general one. The answers are
## invented, deliberately generic, and chosen to be obviously placeholder rather
## than a paraphrase of anything.

## Every table is ten rows, so one d10 reads any of them. A GM whose own table
## is longer or shorter is fine: the roller uses the row count it finds.
const DIE := 10


static func _rows(values: PackedStringArray) -> Array:
	var rows: Array = []
	for index in values.size():
		rows.append({"roll": index + 1, "text": values[index]})
	return rows


## The questions asked of every character, whatever they do for a living.
##
## The order is the order the Forge walks: where you come from, who you are,
## what you wear, what you care about, who raised you, and what has happened to
## you since.
static func general() -> Dictionary:
	return {
		"cultural_origin":
		_rows(
			[
				"North American",
				"South American",
				"Western European",
				"Eastern European",
				"Central Asian",
				"South Asian",
				"East Asian",
				"African",
				"Oceanic",
				"Offworld",
			]
		),
		"personality":
		_rows(
			[
				"Shy and secretive",
				"Rebellious and antisocial",
				"Arrogant and proud",
				"Moody and violent",
				"Picky and fussy",
				"Sneaky and deceptive",
				"Intellectual and detached",
				"Friendly and outgoing",
				"Stable and reliable",
				"Silent and grim",
			]
		),
		"clothing":
		_rows(
			[
				"Workwear and boots",
				"Corporate tailoring",
				"Gang colours",
				"Street leathers",
				"Surplus military",
				"Nomad denim and dust",
				"Clubwear",
				"Medical whites",
				"Hand-patched everything",
				"Whatever was on the floor",
			]
		),
		"hairstyle":
		_rows(
			[
				"Shaved",
				"Long and loose",
				"Braided",
				"Bleached",
				"Mohawk",
				"Neat and corporate",
				"Dyed a colour that does not occur",
				"Wrapped and covered",
				"Cropped short",
				"Grown out and ignored",
			]
		),
		"affectation":
		_rows(
			[
				"A scar left unrepaired",
				"Mirrorshades, always",
				"Ritual tattoos",
				"A dead relative's jacket",
				"Gloves, indoors",
				"A tooth replaced in metal",
				"An accent from somewhere else",
				"Rings on every finger",
				"A weapon worn openly",
				"Nothing at all, on purpose",
			]
		),
		"value_most":
		_rows(
			[
				"Money",
				"Honour",
				"Your word",
				"Honesty",
				"Knowledge",
				"Vengeance",
				"Love",
				"Power",
				"Family",
				"Friendship",
			]
		),
		"feel_about_people":
		_rows(
			[
				"They are tools",
				"They are worth protecting",
				"They are competition",
				"They are unknowable",
				"They are family, eventually",
				"They are in the way",
				"They are owed something",
				"They are a resource",
				"They are the only thing that matters",
				"They are temporary",
			]
		),
		"valued_person":
		_rows(
			[
				"A parent",
				"A sibling",
				"A lover",
				"A friend from before",
				"A mentor",
				"A child",
				"Someone owed a debt",
				"Someone owed an apology",
				"Someone long dead",
				"Nobody left",
			]
		),
		"valued_possession":
		_rows(
			[
				"A weapon",
				"A vehicle",
				"A photograph",
				"A tool of the trade",
				"A recording",
				"A piece of jewellery",
				"A book on paper",
				"A key to somewhere gone",
				"An instrument",
				"A debt marker",
			]
		),
		"family_background":
		_rows(
			[
				"Corporate executives",
				"Corporate managers",
				"Corporate technicians",
				"Nomad pack",
				"Ganger family",
				"Combat zone survivors",
				"Urban homeless",
				"Megastructure warren",
				"Reclaimers",
				"Edgerunners themselves",
			]
		),
		"childhood_environment":
		_rows(
			[
				"A corporate arcology",
				"A company town",
				"A nomad convoy",
				"A combat zone block",
				"A megabuilding floor",
				"A ruined suburb",
				"A boarding school",
				"The road, mostly",
				"A squat",
				"Somewhere nobody names",
			]
		),
		"family_crisis":
		_rows(
			[
				"Your family lost everything to a rival",
				"Your family is imprisoned",
				"You are the only one left",
				"Your family vanished",
				"Your family is hunted",
				"Your family disowned you",
				"Your family owes a debt you inherited",
				"Your family sold you a future you did not want",
				"Your family is fine and you left anyway",
				"You do not know what happened",
			]
		),
		"life_event":
		_rows(
			[
				"You made a powerful enemy",
				"You made a lasting friend",
				"You came into money and lost it",
				"You were betrayed by someone close",
				"You spent time locked up",
				"You fell in love",
				"You were badly hurt and healed wrong",
				"You found a mentor",
				"You did something you will not discuss",
				"A quiet year, for once",
			]
		),
	}


## What a role's own lifepath asks on top of the general one.
##
## Keys are [constant CharacterRules.ROLES] keys, so a campaign that adds a role
## adds its path here. A role with no entry falls back to the general questions
## alone rather than failing.
static func roles() -> Dictionary:
	return {
		"rockerboy":
		{
			"what_kind": _rows(
				[
					"Musician",
					"Slam poet",
					"Streamer",
					"Orator",
					"Comedian",
					"Performance artist",
					"Preacher",
					"Agitator",
					"Dancer",
					"Something with no name yet",
				]
			),
			"venue": _rows(
				[
					"A basement club",
					"A rooftop",
					"A corporate showcase",
					"A pirate broadcast",
					"A street corner",
					"A refugee camp",
					"A stadium, once",
					"A funeral",
					"A riot",
					"Anywhere with power",
				]
			),
		},
		"solo":
		{
			"what_kind": _rows(
				[
					"Bodyguard",
					"Assassin",
					"Corporate enforcer",
					"Mercenary",
					"Bounty hunter",
					"Gun for hire",
					"Ex-military",
					"Arena fighter",
					"Debt collector",
					"Freelance",
				]
			),
			"moral_line": _rows(
				[
					"Never children",
					"Never civilians",
					"Never for free",
					"Never the same client twice",
					"Never without a contract",
					"Never in front of a camera",
					"Never someone you know",
					"Never unarmed targets",
					"Never on credit",
					"No lines left",
				]
			),
		},
		"netrunner":
		{
			"what_kind": _rows(
				[
					"Data thief",
					"Corporate infiltrator",
					"Security consultant",
					"Saboteur",
					"Archivist",
					"Freelance investigator",
					"Blackwall watcher",
					"Program writer",
					"Hardware specialist",
					"Self-taught",
				]
			),
			"first_run": _rows(
				[
					"A school system",
					"A rival's rig",
					"A clinic's records",
					"A corporate subnet",
					"A gang's ledger",
					"A dead runner's deck",
					"Something behind the Blackwall",
					"A friend's private files",
					"A public utility",
					"You do not remember",
				]
			),
		},
		"tech":
		{
			"what_kind": _rows(
				[
					"Weaponsmith",
					"Vehicle mechanic",
					"Cyberware fitter",
					"Electronics",
					"Drone builder",
					"Scavenger",
					"Field engineer",
					"Forger",
					"Demolitions",
					"Generalist",
				]
			),
			"workshop": _rows(
				[
					"A garage bay",
					"The back of a van",
					"A corporate lab, formerly",
					"A shipping container",
					"A market stall",
					"A rooftop shed",
					"Nowhere fixed",
					"A basement",
					"Someone else's shop",
					"Wherever the job is",
				]
			),
		},
		"medtech":
		{
			"what_kind": _rows(
				[
					"Trauma surgeon",
					"Ripperdoc",
					"Pharmacist",
					"Cryo specialist",
					"Field medic",
					"Street clinic doctor",
					"Corporate physician",
					"Veterinarian, once",
					"Coroner",
					"Self-taught",
				]
			),
			"who_you_treat": _rows(
				[
					"Anyone who walks in",
					"Only those who can pay",
					"Only your own crew",
					"Only the neighbourhood",
					"Whoever the Fixer sends",
					"Nobody the corps want",
					"Gangers, mostly",
					"Children first",
					"Whoever is closest",
					"You have stopped choosing",
				]
			),
		},
		"media":
		{
			"what_kind": _rows(
				[
					"Investigative journalist",
					"Screamsheet writer",
					"Documentarian",
					"Photographer",
					"Braindance editor",
					"Talk host",
					"Blogger",
					"War correspondent",
					"Critic",
					"Independent",
				]
			),
			"the_story": _rows(
				[
					"A corporate cover-up",
					"A missing person",
					"A gang war nobody reports",
					"A poisoned district",
					"A rigged election",
					"A miracle cure that is not",
					"Somebody powerful and their past",
					"The story that got someone killed",
					"A quiet, ordinary injustice",
					"You are still looking",
				]
			),
		},
		"exec":
		{
			"what_kind": _rows(
				[
					"Middle management",
					"Division head",
					"Acquisitions",
					"Corporate security",
					"Legal",
					"Research director",
					"Marketing",
					"Logistics",
					"Internal affairs",
					"Disgraced and out",
				]
			),
			"corporation": _rows(
				[
					"A megacorp's local office",
					"A hungry startup",
					"A medical concern",
					"An arms manufacturer",
					"A media conglomerate",
					"A shipping line",
					"An agricultural combine",
					"A security contractor",
					"A bank",
					"One that no longer exists",
				]
			),
		},
		"lawman":
		{
			"what_kind": _rows(
				[
					"Patrol",
					"Detective",
					"Corporate security",
					"Federal agent",
					"Prison officer",
					"Highway patrol",
					"Internal affairs",
					"Bounty enforcement",
					"Border control",
					"Off the books",
				]
			),
			"your_beat": _rows(
				[
					"The combat zone",
					"A corporate plaza",
					"The docks",
					"A residential district",
					"The highways",
					"An arcology",
					"The badlands",
					"Nightlife",
					"Wherever they send you",
					"Nowhere any more",
				]
			),
		},
		"fixer":
		{
			"what_kind": _rows(
				[
					"Broker",
					"Smuggler",
					"Fence",
					"Talent agent",
					"Supplier",
					"Information dealer",
					"Procurer of the rare",
					"Loan shark",
					"Organiser",
					"Everything, a little",
				]
			),
			"your_market": _rows(
				[
					"Weapons",
					"Cyberware",
					"Information",
					"People",
					"Medicine",
					"Vehicles",
					"Contraband",
					"Favours",
					"Property",
					"Whatever is scarce",
				]
			),
		},
		"nomad":
		{
			"what_kind": _rows(
				[
					"Courier",
					"Smuggler",
					"Scout",
					"Driver",
					"Pilot",
					"Trader",
					"Mechanic",
					"Outrider",
					"Water carrier",
					"Packless",
				]
			),
			"your_pack": _rows(
				[
					"Large and old",
					"Small and tight",
					"Newly formed",
					"Scattered",
					"Hunted",
					"Wealthy",
					"Barely holding on",
					"Famous, locally",
					"Notorious",
					"Gone",
				]
			),
		},
	}


static func document() -> Dictionary:
	return {"general": general(), "roles": roles()}
