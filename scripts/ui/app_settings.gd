class_name AppSettings
extends RefCounted

## Preferences about the app rather than about a campaign.
##
## Kept in per-user application data, not in a `.red`: a GM running the console
## on a 4K television wants it bigger on that machine and not on their laptop,
## and neither preference belongs in a file they hand to another GM.

const PATH := "user://display.json"

const MIN_SCALE := 0.8
const MAX_SCALE := 2.0

const DEFAULTS := {
	## Multiplies every control in the app. The console is dense on purpose;
	## across a table it needs to be less dense.
	"ui_scale": 1.0,
	## Skips the tracer, the impact flash and the blast shell. They are lovely
	## and they are also the thing a GM turns off when the room is projecting.
	"reduce_motion": false,
}

static var _loaded: Dictionary = {}


static func all() -> Dictionary:
	if _loaded.is_empty():
		_loaded = _read()
	return _loaded


static func get_value(key: String) -> Variant:
	return all().get(key, DEFAULTS.get(key))


static func ui_scale() -> float:
	return clampf(float(get_value("ui_scale")), MIN_SCALE, MAX_SCALE)


static func reduce_motion() -> bool:
	return bool(get_value("reduce_motion"))


## Change one preference and write the file. Unknown keys are refused rather
## than stored, so a typo cannot quietly become a setting nothing reads.
static func set_value(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	var settings := all()
	settings[key] = value
	_loaded = settings
	return _write(settings)


static func _read() -> Dictionary:
	var settings := DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		return settings
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return settings
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return settings
	for key in DEFAULTS:
		if (parsed as Dictionary).has(key):
			settings[key] = (parsed as Dictionary)[key]
	return settings


static func _write(settings: Dictionary) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	return true


## Push the display preferences at the window they describe.
##
## Called on start and after every change, so the slider is the setting rather
## than a request for one.
static func apply(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = ui_scale()


## Only for tests, which must not inherit whatever the developer's machine has
## in its application data.
static func forget() -> void:
	_loaded = {}
