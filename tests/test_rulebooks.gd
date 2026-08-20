extends RefCounted

## A campaign's active rulebooks are the one part of the assistant that lives in
## the portable save, so what may enter that list — and what must not — is
## checked here rather than trusted to the screen that edits it.

const Harness := preload("res://tests/harness.gd")
const Books := preload("res://scripts/rules/rulebooks.gd")


static func _library() -> Array:
	return [
		{
			"book_id": "aa11bb22cc33dd44",
			"filename": "Core Rules.pdf",
			"label": "Core Rules",
			"status": "indexed",
			"chunk_count": 1200,
		},
		{
			"book_id": "1122334455667788",
			"filename": "Black Chrome.pdf",
			"label": "Black Chrome",
			"status": "indexed",
			"chunk_count": 300,
		},
		{
			"book_id": "99887766554433aa",
			"filename": "Interface RED.pdf",
			"label": "Interface RED",
			"status": "indexing",
			"chunk_count": 0,
		},
	]


static func run(h: Harness) -> void:
	h.describe("campaign rulebook selection")

	h.it("migrates a campaign saved before the assistant existed")
	var campaign := {}
	Books.ensure_campaign(campaign)
	h.equal(campaign["active_rulebook_ids"], [], "empty selection")

	h.it("activates and deactivates books by id")
	h.equal(Books.set_active(campaign, "aa11bb22cc33dd44", true), true, "first book activated")
	h.equal(Books.set_active(campaign, "aa11bb22cc33dd44", true), false, "already active")
	h.equal(Books.set_active(campaign, "1122334455667788", true), true, "second book activated")
	h.equal(Books.active_ids(campaign).size(), 2, "two active books")
	h.equal(Books.is_active(campaign, "1122334455667788"), true, "reports active")
	h.equal(Books.set_active(campaign, "1122334455667788", false), true, "deactivated")
	h.equal(Books.is_active(campaign, "1122334455667788"), false, "reports inactive")
	h.equal(Books.set_active(campaign, "1122334455667788", false), false, "already inactive")

	# An id is the helper's sixteen hex characters and nothing else, so neither a
	# path nor a pasted credential can ever be stored as one.
	h.it("refuses an id that is not a book id")
	h.equal(Books.set_active(campaign, "", true), false, "empty id")
	h.equal(Books.set_active(campaign, "../../etc/passwd", true), false, "path traversal")
	h.equal(Books.set_active(campaign, "api-key-pasted-here", true), false, "unexpected characters")
	h.equal(Books.set_active(campaign, "abc", true), false, "too short to be a book id")
	h.equal(Books.active_ids(campaign), ["aa11bb22cc33dd44"], "selection unchanged")

	h.it("cleans a hand-edited or corrupted selection on open")
	var messy := {"active_rulebook_ids": [" AA11BB22CC33DD44 ", "aa11bb22cc33dd44", "", 42, "bad/id"]}
	Books.ensure_campaign(messy)
	h.equal(messy["active_rulebook_ids"], ["aa11bb22cc33dd44"], "deduplicated and normalized")

	h.it("keeps the order the GM arranged")
	var ordered := {"active_rulebook_ids": ["aa11bb22cc33dd44", "1122334455667788"]}
	h.equal(Books.move(ordered, "1122334455667788", -1), true, "moved up")
	h.equal(ordered["active_rulebook_ids"], ["1122334455667788", "aa11bb22cc33dd44"], "new order")
	h.equal(Books.move(ordered, "1122334455667788", -1), false, "already first")
	h.equal(Books.move(ordered, "missing0000000000", 1), false, "unknown book")

	h.it("reports a book this installation does not have instead of dropping it")
	var shared := {"active_rulebook_ids": ["aa11bb22cc33dd44", "ffffffffffffffff"]}
	var resolved := Books.resolve(shared, _library())
	h.equal((resolved["active"] as Array).size(), 1, "one book resolved")
	h.equal(resolved["unavailable"], ["ffffffffffffffff"], "missing book named")
	h.equal(shared["active_rulebook_ids"].size(), 2, "the campaign keeps the id")

	h.it("only searches books that finished indexing")
	var mixed := {"active_rulebook_ids": ["aa11bb22cc33dd44", "99887766554433aa", "ffffffffffffffff"]}
	h.equal(Books.searchable_ids(mixed, _library()), ["aa11bb22cc33dd44"], "indexing book excluded")

	h.it("persists the selection, and only the selection, inside a save")
	var bundle := CampaignFixtures.blackwall_sunrise()
	var saved_campaign: Dictionary = bundle["campaign"]
	Books.set_active(saved_campaign, "aa11bb22cc33dd44", true)
	Books.set_active(saved_campaign, "1122334455667788", true)
	var path := "user://test_rulebooks.red"
	h.equal(CampaignContainer.save(path, bundle)["ok"], true, "campaign saved")
	var loaded := CampaignContainer.load_file(path)
	h.equal(
		loaded["campaign"]["active_rulebook_ids"],
		["aa11bb22cc33dd44", "1122334455667788"],
		"selection round trip",
	)
	var stored := JSON.stringify(loaded["campaign"])
	h.check(not stored.contains("Core Rules.pdf"), "no filename travels in the save")
	h.check(not stored.contains("sk-ant"), "no credential travels in the save")
	h.check(not stored.contains(".pdf"), "no book path travels in the save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
