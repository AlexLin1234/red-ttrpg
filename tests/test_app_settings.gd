extends RefCounted

## Preferences about the app rather than about a campaign.
##
## Small, but the rules matter: they belong to the machine and not to the save,
## a bad key must not become a setting nothing reads, and a file that has been
## edited by hand must not take the app down with it.

const Harness := preload("res://tests/harness.gd")


static func _clean() -> void:
	AppSettings.forget()
	if FileAccess.file_exists(AppSettings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppSettings.PATH))


static func _write_raw(text: String) -> void:
	var file := FileAccess.open(AppSettings.PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	AppSettings.forget()


static func run(h: Harness) -> void:
	h.describe("display settings")

	_clean()

	h.it("starts from the defaults with no file on disk")
	h.equal(AppSettings.ui_scale(), 1.0, "scale")
	h.equal(AppSettings.reduce_motion(), false, "motion")

	h.it("keeps what it is told, across a reload")
	h.equal(AppSettings.set_value("ui_scale", 1.5), true, "set")
	h.equal(AppSettings.ui_scale(), 1.5, "held in memory")
	AppSettings.forget()
	h.equal(AppSettings.ui_scale(), 1.5, "and read back from disk")

	h.it("refuses a key nothing reads")
	h.equal(AppSettings.set_value("uiscale", 2.0), false, "a typo is refused")
	h.equal(AppSettings.set_value("colour", "green"), false, "and so is an invention")
	AppSettings.forget()
	h.not_contains(AppSettings.all().keys(), "uiscale", "and neither is stored")

	h.it("clamps a scale outside what the app can draw")
	AppSettings.set_value("ui_scale", 40.0)
	h.equal(AppSettings.ui_scale(), AppSettings.MAX_SCALE, "too large")
	AppSettings.set_value("ui_scale", 0.05)
	h.equal(AppSettings.ui_scale(), AppSettings.MIN_SCALE, "too small")

	h.it("survives a file edited by hand into nonsense")
	_write_raw("{not json at all")
	h.equal(AppSettings.ui_scale(), 1.0, "falls back to the default")
	_write_raw('["a list, not an object"]')
	h.equal(AppSettings.ui_scale(), 1.0, "and to the default again")

	h.it("keeps the settings it recognises and ignores the rest")
	_write_raw('{"ui_scale": 1.3, "favourite_colour": "red"}')
	h.equal(AppSettings.ui_scale(), 1.3, "the known one is read")
	h.not_contains(AppSettings.all().keys(), "favourite_colour", "the unknown one is not")

	h.it("keeps every default reachable by name")
	for key in AppSettings.DEFAULTS:
		h.not_equal(AppSettings.get_value(String(key)), null, "%s has a value" % key)

	_clean()
