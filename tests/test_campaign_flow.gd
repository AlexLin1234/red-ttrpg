extends RefCounted

const Harness := preload("res://tests/harness.gd")
const Flow := preload("res://scripts/rules/campaign_flow.gd")


static func run(h: Harness) -> void:
	h.describe("campaign notes and beat flow")

	h.it("migrates older campaigns to an empty notebook")
	var campaign := {}
	Flow.ensure_campaign(campaign)
	h.equal(campaign["gm_notes"], "", "GM notes")
	h.equal(campaign["beats"], [], "beat graph")

	h.it("creates and arranges JSON-safe beat cards")
	var opening := Flow.new_beat(0)
	var reveal := Flow.new_beat(1)
	reveal["id"] = "reveal"
	opening["id"] = "opening"
	(campaign["beats"] as Array).append(opening)
	(campaign["beats"] as Array).append(reveal)
	var moved := Flow.set_beat_position(opening, Vector2(245.0, 310.0))
	h.equal(moved, Vector2(245.0, 310.0), "moved position")
	h.equal(Flow.beat_position(opening), Vector2(245.0, 310.0), "stored position")
	h.check(JSON.stringify(campaign).contains("opening"), "graph can be serialized as JSON")

	h.it("links beats without self-links or duplicates")
	h.equal(Flow.link_beats(campaign, "opening", "reveal"), true, "first link")
	h.equal(Flow.link_beats(campaign, "opening", "reveal"), false, "duplicate refused")
	h.equal(Flow.link_beats(campaign, "opening", "opening"), false, "self-link refused")
	h.equal(opening["next_ids"], ["reveal"], "one outgoing link")
	h.equal(Flow.unlink_beats(campaign, "opening", "reveal"), true, "link removed")
	h.equal(Flow.unlink_beats(campaign, "opening", "reveal"), false, "missing link unchanged")

	h.it("deleting a beat removes inbound links")
	Flow.link_beats(campaign, "opening", "reveal")
	h.equal(Flow.remove_beat(campaign, "reveal"), true, "beat removed")
	h.equal((campaign["beats"] as Array).size(), 1, "one beat remains")
	h.equal(opening["next_ids"], [], "inbound path cleaned")
	h.equal(Flow.remove_beat(campaign, "missing"), false, "missing beat unchanged")

	h.it("persists notes and flow inside a campaign save")
	var bundle := CampaignFixtures.blackwall_sunrise()
	(bundle["campaign"] as Dictionary)["gm_notes"] = "The client is lying."
	(bundle["campaign"] as Dictionary)["beats"] = [opening]
	var path := "user://test_campaign_flow.red"
	h.equal(CampaignContainer.save(path, bundle)["ok"], true, "flow campaign saved")
	var loaded := CampaignContainer.load_file(path)
	h.equal(loaded["campaign"]["gm_notes"], "The client is lying.", "notes round trip")
	h.equal(loaded["campaign"]["beats"][0]["id"], "opening", "beat round trip")
	h.equal(loaded["campaign"]["beats"][0]["x"], 245.0, "position round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
