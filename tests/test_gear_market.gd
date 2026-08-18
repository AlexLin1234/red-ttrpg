extends RefCounted

const Harness := preload("res://tests/harness.gd")


static func _character(cash := 6000) -> Dictionary:
	return {"cash": cash, "gear": [], "weapons": [], "armor": CampaignSchema.empty_armor(), "humanity": 40, "max_humanity": 50}


static func run(h: Harness) -> void:
	h.describe("character markets")
	h.it("offers every catalog item in the full market")
	h.equal(GearMarket.CATALOG.size(), 22, "complete built-in catalog")

	h.it("pays for purchases and puts equipment on the character")
	var buyer := _character()
	var result := GearMarket.buy(buyer, "heavy_sidearm")
	h.equal(result["ok"], true, "purchase succeeds")
	h.equal(buyer["cash"], 5500, "cash deducted")
	h.equal(buyer["gear"][0]["name"], "Heavy Sidearm", "inventory updated")
	h.equal(buyer["weapons"][0]["damage_dice"], 3, "combat weapon equipped")
	GearMarket.buy(buyer, "helmet")
	h.equal(buyer["armor"]["head"]["sp"], 11, "armor equipped")

	h.it("rejects an unaffordable purchase without changing the character")
	var broke := _character(10)
	h.equal(GearMarket.buy(broke, "agent")["ok"], false, "purchase rejected")
	h.equal(broke["cash"], 10, "cash unchanged")
	h.equal(broke["gear"].size(), 0, "inventory unchanged")

	h.it("limits Night Market stock by Fixer Operator rank")
	var outsider := _character()
	h.equal(GearMarket.night_market(outsider).size(), 0, "non-Fixer has no stock")
	var fixer := _character()
	fixer["role_key"] = "fixer"
	fixer["role_ability"] = {"rank": 4}
	var stock := GearMarket.night_market(fixer)
	h.equal(stock.size() < GearMarket.CATALOG.size(), true, "stock is limited")
	for product in stock:
		h.equal(int(product["price"]) <= 1000, true, "%s is within reach" % product["name"])

	h.it("attaches owned cyberware to compatible body parts and loses Humanity")
	var augmented := _character()
	GearMarket.buy(augmented, "cyberarm")
	var installed := GearMarket.install_cyberware(augmented, 0, "left_arm")
	h.equal(installed["ok"], true, "implant attached")
	h.equal(augmented["gear"][0]["installed_on"], "left_arm", "body part recorded")
	h.equal(augmented["humanity"], 33, "Humanity deducted")
	h.equal(GearMarket.install_cyberware(augmented, 0, "right_arm")["ok"], false, "same implant cannot be attached twice")

	h.it("detaches cyberware without reversing Humanity loss")
	h.equal(GearMarket.detach_cyberware(augmented, "left_arm")["ok"], true, "implant detached")
	h.equal(augmented["humanity"], 33, "Humanity loss remains")
	h.equal(GearMarket.installed_at(augmented, "left_arm"), -1, "body part is free")
