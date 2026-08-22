extends RefCounted

const Harness := preload("res://tests/harness.gd")
const EconomyRules := preload("res://scripts/rules/economy.gd")
const StoreScript := preload("res://scripts/campaign/store.gd")


static func _character(id: String, role_key := "solo", rank := 4, cash := 0) -> Dictionary:
	return {
		"id": id,
		"name": id.capitalize(),
		"role": role_key.capitalize(),
		"role_key": role_key,
		"role_ability": {"rank": rank},
		"cash": cash,
		"gear": [],
		"weapons": [],
		"armor": CampaignSchema.empty_armor(),
	}


static func run(h: Harness) -> void:
	h.describe("shared character economy")
	h.it("uses the rulebook Role, Rank band, and d6 result for Hustles")
	var rockerboy := _character("red", "rockerboy", 4)
	var local_gig := EconomyRules.hustle(rockerboy, Dice.FixedRandom.new([1] as Array[int]))
	h.equal(local_gig["earned"], 200, "Rank 1-4 payout")
	h.equal(rockerboy["cash"], 200, "payout added")
	var fixer := _character("broker", "fixer", 7)
	var rare_item := EconomyRules.hustle(fixer, Dice.FixedRandom.new([6] as Array[int]))
	h.equal(rare_item["earned"], 500, "Rank 5-7 payout")
	var exec := _character("boss", "exec", 8)
	var project := EconomyRules.hustle(exec, Dice.FixedRandom.new([1] as Array[int]))
	h.equal(project["earned"], 800, "Rank 8-10 payout")
	h.equal(project["days"], 7, "a Hustle consumes seven days")

	h.it("rejects a Hustle without a valid Role and changes no cash")
	var unclassed := _character("new", "", 0, 50)
	h.equal(EconomyRules.hustle(unclassed, Dice.FixedRandom.new([1] as Array[int]))["ok"], false, "rejected")
	h.equal(unclassed["cash"], 50, "cash unchanged")

	h.it("moves money atomically between two characters")
	var giver := _character("giver", "solo", 4, 500)
	var recipient := _character("recipient", "tech", 4, 25)
	var paid := EconomyRules.transfer_cash(giver, recipient, 125)
	h.equal(paid["ok"], true, "transfer succeeds")
	h.equal(giver["cash"], 375, "giver debited")
	h.equal(recipient["cash"], 150, "recipient credited")
	h.equal(EconomyRules.transfer_cash(giver, recipient, 999)["ok"], false, "overdraft rejected")
	h.equal(giver["cash"], 375, "failed transfer does not debit")
	h.equal(recipient["cash"], 150, "failed transfer does not credit")

	h.it("moves an item and its weapon profile to the recipient")
	giver["gear"] = [{"name": "Heavy Sidearm", "kind": "weapon"}]
	giver["weapons"] = [{"name": "Heavy Sidearm", "damage_dice": 3}]
	var handed_over := EconomyRules.transfer_item(giver, recipient, 0)
	h.equal(handed_over["ok"], true, "item transfer succeeds")
	h.equal(giver["gear"].size(), 0, "item removed from giver")
	h.equal(recipient["gear"][0]["name"], "Heavy Sidearm", "item received")
	h.equal(giver["weapons"].size(), 0, "combat profile removed")
	h.equal(recipient["weapons"][0]["damage_dice"], 3, "combat profile received")

	h.it("moves only the given armor's location, and only what left with it")
	var armed := _character("armed", "solo", 4, 0)
	var bare := _character("bare", "tech", 4, 0)
	armed["gear"] = [
		{"name": "Kevlar Weave (body)", "kind": "armor", "armor_profile": {"location": "body", "sp": 7}},
		{"name": "Light Plate (head)", "kind": "armor", "armor_profile": {"location": "head", "sp": 11}},
	]
	armed["armor"] = {"body": {"sp": 7, "ablated": false}, "head": {"sp": 11, "ablated": false}}
	h.equal(EconomyRules.transfer_item(armed, bare, 0)["ok"], true, "armor transfer succeeds")
	h.equal(armed["armor"]["body"]["sp"], 0, "giver loses the body SP that left")
	h.equal(armed["armor"]["head"]["sp"], 11, "giver keeps the head piece they still wear")
	h.equal(bare["armor"]["body"]["sp"], 7, "recipient wears the body piece")
	h.equal(bare["armor"]["head"]["sp"], 0, "recipient's head is untouched")

	h.it("keeps a location covered while a second piece of that armor remains")
	var doubled := _character("doubled", "solo", 4, 0)
	var taker := _character("taker", "tech", 4, 0)
	var vest := {
		"name": "Kevlar Weave (body)",
		"kind": "armor",
		"armor_profile": {"location": "body", "sp": 7},
	}
	doubled["gear"] = [vest.duplicate(true), vest.duplicate(true)]
	doubled["armor"] = {"body": {"sp": 7, "ablated": false}, "head": {"sp": 0, "ablated": false}}
	h.equal(EconomyRules.transfer_item(doubled, taker, 0)["ok"], true, "spare vest given away")
	h.equal(doubled["armor"]["body"]["sp"], 7, "the spare left, the worn one did not")
	h.equal(taker["armor"]["body"]["sp"], 7, "recipient wears the spare")

	h.it("treats a profile-less armor entry as the whole suit only when it is the last one")
	# The sample party carries armor with no profile to say what it covers.
	var legacy := _character("legacy", "solo", 4, 0)
	var receiver := _character("receiver", "tech", 4, 0)
	legacy["gear"] = [{"name": "Light Plate", "kind": "armor", "detail": "SP11"}]
	legacy["armor"] = {"body": {"sp": 11, "ablated": false}, "head": {"sp": 11, "ablated": false}}
	receiver["armor"] = {"body": {"sp": 7, "ablated": false}, "head": {"sp": 0, "ablated": false}}
	h.equal(EconomyRules.transfer_item(legacy, receiver, 0)["ok"], true, "suit given away")
	h.equal(legacy["armor"]["body"]["sp"], 0, "giver is stripped")
	h.equal(receiver["armor"]["body"]["sp"], 7, "recipient's own body armor stands")
	h.equal(receiver["armor"]["head"]["sp"], 11, "recipient covers the location they had bare")

	h.it("leaves a worn suit alone when the giver still carries other armor")
	var hoarder := _character("hoarder", "solo", 4, 0)
	var other := _character("other", "tech", 4, 0)
	hoarder["gear"] = [
		{"name": "Light Plate", "kind": "armor", "detail": "SP11"},
		{"name": "Kevlar Weave", "kind": "armor", "detail": "SP7"},
	]
	hoarder["armor"] = {"body": {"sp": 11, "ablated": false}, "head": {"sp": 11, "ablated": false}}
	h.equal(EconomyRules.transfer_item(hoarder, other, 0)["ok"], true, "one of two given away")
	h.equal(hoarder["armor"]["body"]["sp"], 11, "the suit they still carry stays worn")
	h.equal(other["armor"]["body"]["sp"], 0, "recipient gets the item, not a guessed suit")

	h.it("transfers armor onto a sheet that has no armor block at all")
	var plain := _character("plain", "solo", 4, 0)
	var sheetless := _character("sheetless", "tech", 4, 0)
	plain.erase("armor")
	sheetless.erase("armor")
	plain["gear"] = [
		{"name": "Kevlar Weave (body)", "kind": "armor", "armor_profile": {"location": "body", "sp": 7}},
	]
	h.equal(EconomyRules.transfer_item(plain, sheetless, 0)["ok"], true, "transfer succeeds")
	h.equal(sheetless["armor"]["body"]["sp"], 7, "recipient gains an armor block")
	h.equal(plain["armor"]["body"]["sp"], 0, "giver gains an empty one")

	h.it("requires installed cyberware to be detached before transfer")
	giver["gear"] = [{"name": "Cyberarm", "kind": "cyberware", "installed_on": "left_arm"}]
	h.equal(EconomyRules.transfer_item(giver, recipient, 0)["ok"], false, "installed item rejected")
	h.equal(giver["gear"].size(), 1, "installed item remains")

	h.it("stores one Fixer-organized Night Market for every active character")
	var shopper := _character("shopper", "solo", 4, 1000)
	var organizer := _character("organizer", "fixer", 5, 1000)
	var store := StoreScript.new()
	store.campaign = {
		"name": "Test",
		"clock": {"year": 2045, "month": 1, "day": 1, "hour": 12, "minute": 0},
		"sessions": 1,
		"session_log": [],
		"night_market": {},
	}
	store.roster = {"characters": [organizer, shopper]}
	store.active_character_id = "organizer"
	var document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/items.json")
	)
	var opened := store.organize_night_market(
		organizer,
		Dice.FixedRandom.new([3, 4, 1, 0, 1, 0] as Array[int]),
		document["items"],
	)
	h.equal(opened["ok"], true, "Fixer opens market")
	var shared := store.night_market()
	store.active_character_id = "shopper"
	h.equal(store.night_market(), shared, "same market for another character")
	h.equal(String(store.night_market()["organizer_id"]), "organizer", "organizer retained")
	h.check((store.night_market()["stock"] as Array).size() > 0, "shared stock retained")

	h.it("round trips the shared Night Market through a campaign save")
	var saved := CampaignContainer.save(
		"user://test_shared_market.red",
		{"campaign": store.campaign, "roster": store.roster, "locations": []},
	)
	h.equal(saved["ok"], true, "campaign saved")
	var loaded := CampaignContainer.load_file("user://test_shared_market.red")
	h.equal(loaded["ok"], true, "campaign loaded")
	h.equal(
		loaded["campaign"]["night_market"]["organizer_id"],
		"organizer",
		"shared market persisted",
	)
	h.equal(
		(loaded["campaign"]["night_market"]["stock"] as Array).size(),
		(store.night_market()["stock"] as Array).size(),
		"shared stock persisted",
	)

	h.it("advances the campaign clock by the Hustle's full seven days")
	store.active_character_id = "organizer"
	var before_cash := int(organizer["cash"])
	var weekly := store.perform_hustle(
		"organizer", Dice.FixedRandom.new([1] as Array[int])
	)
	h.equal(weekly["ok"], true, "Hustle completed")
	h.equal(store.campaign["clock"]["day"], 8, "seven days elapsed")
	h.equal(organizer["cash"], before_cash + 300, "Rank 5 payout added")

	h.it("runs selected Hustles concurrently during one shared free-time week")
	var organizer_before := int(organizer["cash"])
	var shopper_before := int(shopper["cash"])
	var group := store.perform_hustles(
		["organizer", "shopper", "organizer"],
		Dice.FixedRandom.new([1, 1] as Array[int]),
	)
	h.equal(group["ok"], true, "group Hustles completed")
	h.equal(group["participants"], 2, "duplicate selection only runs once")
	h.equal((group["results"] as Array).size(), 2, "one result per selected player")
	h.equal(store.campaign["clock"]["day"], 15, "shared week advances only seven days")
	h.check(int(organizer["cash"]) > organizer_before, "first player was paid")
	h.check(int(shopper["cash"]) > shopper_before, "second player was paid")
	h.equal(
		group["total_earned"],
		int(group["results"][0]["earned"]) + int(group["results"][1]["earned"]),
		"group payout total",
	)

	h.it("validates every selected Hustler before changing anyone")
	organizer_before = int(organizer["cash"])
	var day_before := int(store.campaign["clock"]["day"])
	var invalid := store.perform_hustles(
		["organizer", "missing"], Dice.FixedRandom.new([1] as Array[int])
	)
	h.equal(invalid["ok"], false, "invalid group rejected")
	h.equal(organizer["cash"], organizer_before, "no partial payout")
	h.equal(store.campaign["clock"]["day"], day_before, "no time advanced")
	store.free()
