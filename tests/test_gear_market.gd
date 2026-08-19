extends RefCounted

const Harness := preload("res://tests/harness.gd")


static func _character(cash := 6000) -> Dictionary:
	return {"cash": cash, "gear": [], "weapons": [], "armor": CampaignSchema.empty_armor(), "humanity": 40, "max_humanity": 50}


static func _catalog() -> Array:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	return document["items"]


static func run(h: Harness) -> void:
	var catalog := _catalog()
	h.describe("character markets")
	h.it("offers every catalog item in the full market")
	h.equal(catalog.size(), 60, "complete built-in catalog")

	h.it("pays for purchases and puts equipment on the character")
	var buyer := _character()
	var result := GearMarket.buy(buyer, catalog, "heavy_sidearm")
	h.equal(result["ok"], true, "purchase succeeds")
	h.equal(buyer["cash"], 5500, "cash deducted")
	h.equal(buyer["gear"][0]["name"], "Heavy Sidearm", "inventory updated")
	h.equal(buyer["weapons"][0]["damage_dice"], 3, "combat weapon equipped")
	GearMarket.buy(buyer, catalog, "light_plate_head")
	h.equal(buyer["armor"]["head"]["sp"], 11, "armor equipped")

	h.it("rejects an unaffordable purchase without changing the character")
	var broke := _character(10)
	h.equal(GearMarket.buy(broke, catalog, "agent")["ok"], false, "purchase rejected")
	h.equal(broke["cash"], 10, "cash unchanged")
	h.equal(broke["gear"].size(), 0, "inventory unchanged")

	h.it("sets Operator Reach by rank, in price categories")
	h.equal(GearMarket.reach_ceiling(0), 0, "no Reach without the Role Ability")
	h.equal(GearMarket.reach_ceiling(1), 20, "Ranks 1-2 reach Everyday")
	h.equal(GearMarket.reach_ceiling(2), 20, "Ranks 1-2 reach Everyday")
	h.equal(GearMarket.reach_ceiling(3), 500, "Ranks 3-4 reach Expensive")
	h.equal(GearMarket.reach_ceiling(6), 500, "Ranks 5-6 keep the Expensive ceiling")
	h.equal(GearMarket.reach_ceiling(7), 1000, "Ranks 7-8 reach Very Expensive")
	h.equal(GearMarket.reach_ceiling(9), 5000, "Rank 9 reaches Luxury")
	h.equal(GearMarket.reach_ceiling(10), 10000, "Rank 10 reaches Super Luxury")

	h.it("only lets a Rank 5 or higher Fixer organize a Night Market")
	var outsider := _character()
	var any_rng := Dice.SeededRandom.new(1)
	h.equal(GearMarket.night_market(outsider, catalog, any_rng)["ok"], false, "non-Fixer cannot")
	var junior := _character()
	junior["role_key"] = "fixer"
	junior["role_ability"] = {"rank": 4}
	var refused := GearMarket.night_market(junior, catalog, any_rng)
	h.equal(refused["ok"], false, "Rank 4 cannot organize one")
	h.equal(refused["stock"].size(), 0, "no stock is offered")

	h.it("rolls two kinds of goods and stocks each with 1d10 types")
	var fixer := _character()
	fixer["role_key"] = "fixer"
	fixer["role_ability"] = {"rank": 5}
	# 1d6 -> 3 (Weapons and Armor) and 4 (Cyberware); then 2 and 1 types drawn.
	var scripted := Dice.FixedRandom.new([3, 4, 2, 0, 0, 1, 0] as Array[int])
	var market := GearMarket.night_market(fixer, catalog, scripted)
	h.equal(market["ok"], true, "Rank 5 organizes a Night Market")
	h.equal(market["categories"], PackedStringArray(["Weapons and Armor", "Cyberware"]), "goods rolled")
	h.equal(market["stock"].size(), 3, "1d10 types per kind of goods")
	h.equal(market["midnight"], false, "Rank 5 seats no Midnight Market")
	for product in market["stock"]:
		var kind := String(product["kind"])
		h.check(
			["weapon", "armor", "ammo", "cyberware"].has(kind),
			"%s belongs to a rolled category" % product["name"],
		)

	h.it("rerolls a repeated goods roll so two kinds are always present")
	var repeated := Dice.FixedRandom.new([2, 2, 2, 5, 1, 0, 1, 0] as Array[int])
	var varied := GearMarket.night_market(fixer, catalog, repeated)
	h.equal(varied["categories"].size(), 2, "two distinct kinds of goods")
	h.equal(varied["categories"][0] != varied["categories"][1], true, "no repeat")

	h.it("lifts the price ceiling at a Night Market and seats a Midnight Market at Rank 9")
	var boss := _character()
	boss["role_key"] = "fixer"
	boss["role_ability"] = {"rank": 9}
	var wide := GearMarket.night_market(boss, catalog, Dice.SeededRandom.new(7))
	h.equal(wide["ok"], true, "Rank 9 organizes a Night Market")
	h.equal(wide["midnight"], true, "Rank 9 seats a Midnight Market")
	var priciest := 0
	for value in catalog:
		priciest = maxi(priciest, int((value as Dictionary)["price"]))
	var reachable := GearMarket.night_market(boss, [{"id": "x", "name": "X", "kind": "cyberware", "price": priciest}], Dice.SeededRandom.new(3))
	h.equal(reachable["ok"], true, "the most expensive stock is still sourceable")

	h.it("attaches owned cyberware to compatible body parts and loses Humanity")
	var augmented := _character()
	GearMarket.buy(augmented, catalog, "cyberarm")
	var installed := GearMarket.install_cyberware(augmented, 0, "left_arm")
	h.equal(installed["ok"], true, "implant attached")
	h.equal(augmented["gear"][0]["installed_on"], "left_arm", "body part recorded")
	h.equal(augmented["humanity"], 33, "Humanity deducted")
	h.equal(GearMarket.install_cyberware(augmented, 0, "right_arm")["ok"], false, "same implant cannot be attached twice")

	h.it("detaches cyberware without reversing Humanity loss")
	h.equal(GearMarket.detach_cyberware(augmented, "left_arm")["ok"], true, "implant detached")
	h.equal(augmented["humanity"], 33, "Humanity loss remains")
	h.equal(GearMarket.installed_at(augmented, "left_arm"), -1, "body part is free")
