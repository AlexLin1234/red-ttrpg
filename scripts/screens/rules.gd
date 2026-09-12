extends Control

## The table editor the rest of the app has been promising.
##
## Redline ships no book data. Every fight has always resolved against homebrew
## placeholder numbers, and [Tables] and the README both said a GM who owns the
## book "edits any value in the table editor or imports their own JSON". There
## was no table editor, and `tables` was not a campaign key, so the read that
## looked for one could only ever return the placeholder. This is the screen
## that makes the sentence true.
##
## Documents are campaign-held rather than per-install: two campaigns may be run
## under two different sets of house rules, and a campaign carries its own rules
## with it when it moves between machines.
##
## What is editable in place is what a GM actually corrects — range bands,
## weapon profiles, armour SP, aimed-shot modifiers, cover. Everything else,
## including the long text of the critical injury tables, goes through import
## and export, which is also the only sane way to move a table somebody typed up
## once between campaigns.

const GROUPS: Array[Dictionary] = [
	{"key": "ranged_dv", "label": "Range DV", "document": "tables", "kind": "bands"},
	{"key": "autofire_dv", "label": "Autofire DV", "document": "tables", "kind": "bands"},
	{"key": "weapons", "label": "Weapons", "document": "tables", "kind": "weapons"},
	{"key": "armor", "label": "Armor", "document": "tables", "kind": "armor"},
	{"key": "aimed_shots", "label": "Aimed shots", "document": "tables", "kind": "aimed"},
	{"key": "cover", "label": "Cover", "document": "tables", "kind": "cover"},
	{"key": "critical_injuries", "label": "Critical injuries", "document": "tables", "kind": "text"},
	{"key": "ice", "label": "ICE", "document": "netrun_tables", "kind": "text"},
	{"key": "difficulties", "label": "NET difficulty", "document": "netrun_tables", "kind": "text"},
	{"key": "general", "label": "Lifepath", "document": "lifepath_tables", "kind": "text"},
	{"key": "roles", "label": "Role lifepaths", "document": "lifepath_tables", "kind": "text"},
]

var _selected := "ranged_dv"
var _body: VBoxContainer
var _rail: VBoxContainer
var _status: Label
var _import_dialog: FileDialog
var _export_dialog: FileDialog


func _ready() -> void:
	name = "RulesScreen"
	var row := UI.hbox(UI.GAP_3)
	add_child(UI.fill_margins(row, UI.GAP_3))

	var rail_panel := UI.panel()
	rail_panel.custom_minimum_size = Vector2(230, 0)
	UI.expand(rail_panel, false, true)
	row.add_child(rail_panel)
	var rail_column := UI.vbox(0)
	rail_panel.add_child(rail_column)
	rail_column.add_child(UI.margins(UI.heading("Tables"), UI.GAP_3))
	var rail_scroll := ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(rail_scroll)
	rail_column.add_child(rail_scroll)
	_rail = UI.vbox(1)
	UI.expand(_rail, true, false)
	rail_scroll.add_child(UI.margins(_rail, UI.GAP_2))

	var sheet := UI.panel()
	UI.expand(sheet)
	row.add_child(sheet)
	var column := UI.vbox(UI.GAP_2)
	sheet.add_child(UI.margins(column, UI.GAP_4))

	column.add_child(_build_head())
	column.add_child(UI.rule_line())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	column.add_child(scroll)
	_body = UI.vbox(UI.GAP_2)
	UI.expand(_body, true, false)
	scroll.add_child(_body)

	_build_dialogs()
	refresh()


func _build_head() -> Control:
	var box := UI.vbox(UI.GAP_2)
	var row := UI.hbox(UI.GAP_2)
	var title := UI.display("Rules", 26)
	UI.expand(title, true, false)
	row.add_child(title)

	var import_button := UI.plain_button("Import JSON")
	import_button.tooltip_text = "Replace this document with one you have written"
	import_button.pressed.connect(func() -> void: _import_dialog.popup_centered(Vector2i(900, 600)))
	row.add_child(import_button)

	var export_button := UI.plain_button("Export JSON")
	export_button.tooltip_text = "Write this document out, to edit elsewhere or carry to another campaign"
	export_button.pressed.connect(func() -> void: _export_dialog.popup_centered(Vector2i(900, 600)))
	row.add_child(export_button)

	var reset := UI.plain_button("Reset")
	reset.tooltip_text = "Hand this document back to the built-in homebrew placeholders"
	reset.pressed.connect(
		func() -> void:
			Store.reset_rules_document(_document_key())
			refresh()
	)
	row.add_child(reset)
	box.add_child(row)

	_status = UI.body("", 12, UI.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	box.add_child(_status)
	return box


func _build_dialogs() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.add_filter("*.json", "JSON")
	_import_dialog.theme = UI.build_theme()
	_import_dialog.file_selected.connect(_import)
	add_child(_import_dialog)

	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.add_filter("*.json", "JSON")
	_export_dialog.theme = UI.build_theme()
	_export_dialog.file_selected.connect(_export)
	add_child(_export_dialog)


func _group() -> Dictionary:
	for entry in GROUPS:
		var group: Dictionary = entry
		if String(group["key"]) == _selected:
			return group
	return GROUPS[0]


func _document_key() -> String:
	return String(_group()["document"])


## Public so the screenshot runner can walk the tables the way a GM does.
func show_group(key: String) -> void:
	for entry in GROUPS:
		if String((entry as Dictionary)["key"]) == key:
			_selected = key
			refresh()
			return


func refresh() -> void:
	_rebuild_rail()
	_rebuild_body()


func _rebuild_rail() -> void:
	for child in _rail.get_children():
		child.queue_free()
	var current_document := ""
	for entry in GROUPS:
		var group: Dictionary = entry
		var document := String(group["document"])
		if document != current_document:
			current_document = document
			_rail.add_child(
				UI.micro(String(Store.RULES_DOCUMENTS.get(document, document)), UI.MUTED_DIM)
			)
		var key := String(group["key"])
		var button := UI.tab_button(String(group["label"]), key == _selected)
		UI.expand(button, true, false)
		button.pressed.connect(func() -> void: show_group(key))
		_rail.add_child(button)


func _rebuild_body() -> void:
	for child in _body.get_children():
		child.queue_free()

	var group := _group()
	var document_key := _document_key()
	var custom := Store.rules_are_custom(document_key)
	_status.text = (
		"This campaign carries its own %s." % String(Store.RULES_DOCUMENTS[document_key])
		if custom
		else (
			"Built-in homebrew placeholders — not book data. Edit a value and this campaign "
			+ "takes its own copy; nothing is written back to the app."
		)
	)

	var document := Store.rules_document(document_key)
	var table: Variant = document.get(String(group["key"]), {})
	match String(group["kind"]):
		"bands":
			_build_bands(table)
		"weapons":
			_build_weapons(table)
		"armor":
			_build_armor(table)
		"aimed":
			_build_aimed(table)
		"cover":
			_build_cover(table)
		_:
			_build_readonly(table)


## Write one edited value back, taking a copy of the document first.
##
## Every editor here funnels through this: the campaign's document is replaced
## whole, validated, and snapshotted, so a bad edit is one undo away and a
## structurally broken table is refused rather than saved and discovered
## mid-fight.
func _write(path: Array, value: Variant) -> void:
	var document_key := _document_key()
	var document := Store.rules_document(document_key).duplicate(true)
	var cursor: Variant = document
	for index in path.size() - 1:
		cursor = (cursor as Dictionary)[path[index]] if cursor is Dictionary else cursor[path[index]]
	if cursor is Dictionary:
		(cursor as Dictionary)[path[path.size() - 1]] = value
	else:
		cursor[path[path.size() - 1]] = value
	var result := Store.set_rules_document(document_key, document)
	if not bool(result["ok"]):
		_status.text = "Refused: %s" % ", ".join(result["problems"])
		return
	refresh()


func _number_field(value: int, low: int, high: int, on_set: Callable) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.value = value
	field.custom_minimum_size = Vector2(88, 0)
	field.value_changed.connect(func(next: float) -> void: on_set.call(int(next)))
	return field


func _build_bands(table: Variant) -> void:
	if not table is Dictionary:
		return
	_body.add_child(
		UI.body(
			(
				"What a shot is checked against, by how far away the target is. Every metre "
				+ "from zero has to fall inside exactly one band, or a shot at that range has "
				+ "nothing to beat."
			),
			12,
			UI.MUTED,
		)
	)
	for weapon_type in (table as Dictionary):
		_body.add_child(UI.rule_line())
		_body.add_child(UI.heading(String(weapon_type), UI.ACCENT))
		var bands: Array = (table as Dictionary)[weapon_type]
		for index in bands.size():
			var band: Dictionary = bands[index]
			var row := UI.hbox(UI.GAP_2)
			var at := index
			var key := String(weapon_type)
			row.add_child(UI.micro("from"))
			row.add_child(
				_number_field(
					int(band["min_m"]),
					0,
					2000,
					func(next: int) -> void: _write([_group()["key"], key, at, "min_m"], next),
				)
			)
			row.add_child(UI.micro("to"))
			row.add_child(
				_number_field(
					int(band["max_m"]),
					0,
					2000,
					func(next: int) -> void: _write([_group()["key"], key, at, "max_m"], next),
				)
			)
			row.add_child(UI.micro("metres · DV"))
			row.add_child(
				_number_field(
					int(band["dv"]),
					1,
					60,
					func(next: int) -> void: _write([_group()["key"], key, at, "dv"], next),
				)
			)
			_body.add_child(row)


func _build_weapons(table: Variant) -> void:
	if not table is Dictionary:
		return
	_body.add_child(
		UI.body("Damage is in d6. Autofire rating of −1 means the weapon has none.", 12, UI.MUTED)
	)
	for name in (table as Dictionary):
		var profile: Dictionary = (table as Dictionary)[name]
		_body.add_child(UI.rule_line())
		var row := UI.hbox(UI.GAP_2)
		var label := UI.elide(UI.value(String(name), 13))
		label.custom_minimum_size.x = 150
		UI.expand(label, true, false)
		row.add_child(label)
		var key := String(name)
		for field in [
			{"key": "damage_dice", "label": "d6", "low": 0, "high": 12},
			{"key": "rof", "label": "ROF", "low": 1, "high": 10},
			{"key": "magazine", "label": "Mag", "low": 1, "high": 200},
			{"key": "autofire_rating", "label": "Auto", "low": -1, "high": 10},
		]:
			var spec: Dictionary = field
			var field_key := String(spec["key"])
			row.add_child(UI.micro(String(spec["label"])))
			row.add_child(
				_number_field(
					int(profile.get(field_key, 0)),
					int(spec["low"]),
					int(spec["high"]),
					func(next: int) -> void: _write(["weapons", key, field_key], next),
				)
			)
		_body.add_child(row)


func _build_armor(table: Variant) -> void:
	if not table is Dictionary:
		return
	_body.add_child(UI.body("SP is what a hit has to get through before it reaches HP.", 12, UI.MUTED))
	for name in (table as Dictionary):
		var entry: Dictionary = (table as Dictionary)[name]
		var row := UI.hbox(UI.GAP_2)
		var label := UI.elide(UI.value(String(name), 13))
		label.custom_minimum_size.x = 170
		UI.expand(label, true, false)
		row.add_child(label)
		var key := String(name)
		row.add_child(UI.micro("SP"))
		row.add_child(
			_number_field(
				int(entry.get("sp", 0)),
				0,
				40,
				func(next: int) -> void: _write(["armor", key, "sp"], next),
			)
		)
		var penalty: Dictionary = entry.get("penalty", {})
		row.add_child(
			UI.micro(
				"no penalty" if penalty.is_empty() else ", ".join(_penalty_words(penalty)), UI.MUTED
			)
		)
		_body.add_child(row)


static func _penalty_words(penalty: Dictionary) -> PackedStringArray:
	var words := PackedStringArray()
	for stat in penalty:
		words.append("%s %+d" % [String(stat), int(penalty[stat])])
	return words


func _build_aimed(table: Variant) -> void:
	if not table is Dictionary:
		return
	_body.add_child(
		UI.body("What calling a shot at one part of somebody costs the attacker.", 12, UI.MUTED)
	)
	for location in (table as Dictionary):
		var entry: Dictionary = (table as Dictionary)[location]
		var row := UI.hbox(UI.GAP_2)
		var label := UI.value(String(CampaignSchema.LOCATION_LABELS.get(location, location)), 13)
		label.custom_minimum_size.x = 170
		UI.expand(label, true, false)
		row.add_child(label)
		var key := String(location)
		row.add_child(UI.micro("modifier"))
		row.add_child(
			_number_field(
				int(entry.get("modifier", 0)),
				-20,
				20,
				func(next: int) -> void: _write(["aimed_shots", key, "modifier"], next),
			)
		)
		_body.add_child(row)


func _build_cover(table: Variant) -> void:
	if not table is Dictionary:
		return
	_body.add_child(
		UI.body("What a material stops, and how much of it there is before it stops stopping.", 12, UI.MUTED)
	)
	for material in (table as Dictionary):
		var entry: Dictionary = (table as Dictionary)[material]
		var row := UI.hbox(UI.GAP_2)
		var label := UI.value(String(material), 13)
		label.custom_minimum_size.x = 170
		UI.expand(label, true, false)
		row.add_child(label)
		var key := String(material)
		row.add_child(UI.micro("HP"))
		row.add_child(
			_number_field(
				int(entry.get("hp", 0)),
				1,
				400,
				func(next: int) -> void: _write(["cover", key, "hp"], next),
			)
		)
		row.add_child(UI.micro("SP"))
		row.add_child(
			_number_field(
				int(entry.get("sp", 0)),
				0,
				60,
				func(next: int) -> void: _write(["cover", key, "sp"], next),
			)
		)
		_body.add_child(row)


## Tables whose content is prose rather than numbers.
##
## A critical injury is a sentence with effects attached, and a lifepath answer
## is a sentence full stop. Building a bespoke editor for each would be a lot of
## controls for something a GM edits once; export, edit, import is both less
## code and the only way to carry a typed-up table between campaigns.
func _build_readonly(table: Variant) -> void:
	_body.add_child(
		UI.body(
			(
				"Read-only here. Export the document, edit the JSON, and import it back — "
				+ "which is also how a table typed up once moves to another campaign."
			),
			12,
			UI.MUTED,
		)
	)
	_body.add_child(UI.rule_line())
	var text := JSON.stringify(table, "  ")
	var view := TextEdit.new()
	view.text = text
	view.editable = false
	view.custom_minimum_size = Vector2(0, 460)
	UI.expand(view, true, false)
	view.add_theme_font_size_override("font_size", 12)
	_body.add_child(view)


func _import(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_status.text = "Could not read %s." % path.get_file()
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_status.text = "%s is not a JSON object." % path.get_file()
		return
	var result := Store.set_rules_document(_document_key(), parsed)
	if not bool(result["ok"]):
		_status.text = "Refused: %s" % ", ".join(result["problems"])
		return
	refresh()
	_status.text = "Imported %s." % path.get_file()


func _export(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "Could not write %s." % path.get_file()
		return
	file.store_string(JSON.stringify(Store.rules_document(_document_key()), "  "))
	file.close()
	_status.text = "Exported to %s." % path.get_file()


## The campaign's rules changed under a kept screen, so it is rebuilt rather
## than caught up field by field.
func on_shown() -> void:
	refresh()
