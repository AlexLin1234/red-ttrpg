extends Control

## Screen 1A — the campaign library.
##
## Saves are files, so the panel says so: path, format, size on disk and a
## checksum-verified integrity state, with named restore points listed rather
## than hidden behind a menu.

var _rows: Array = []
var _selected := ""
var _list_box: VBoxContainer
var _hero_holder: Control
var _count_label: Label
var _new_dialog: ConfirmationDialog
var _new_name: LineEdit
var _new_city: LineEdit
var _new_gm: LineEdit
var _new_month: LineEdit


func _ready() -> void:
	var grid := UI.hbox(UI.GAP_3)
	add_child(UI.fill_margins(grid, UI.GAP_3))

	grid.add_child(_build_list())
	_build_new_campaign_dialog()

	_hero_holder = Control.new()
	UI.expand(_hero_holder)
	grid.add_child(_hero_holder)

	_refresh()


func _build_list() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(340, 0)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := UI.vbox(0)
	shell.add_child(column)

	var head := UI.hbox()
	head.add_theme_constant_override("separation", UI.GAP_3)
	var title := UI.micro("Saved campaigns")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_label = UI.micro("")
	head.add_child(_count_label)
	column.add_child(UI.margins(head, UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list_box = UI.vbox(1)
	UI.expand(_list_box, true, false)
	var list_margins := UI.margins(_list_box, UI.GAP_2)
	UI.expand(list_margins, true, false)
	scroll.add_child(list_margins)

	column.add_child(UI.rule_line())
	var actions := UI.hbox()
	var new_button := UI.primary_button("+ New campaign")
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(_create_campaign)
	actions.add_child(new_button)
	var import_button := UI.plain_button("Import .red")
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(_import_campaign)
	actions.add_child(import_button)
	column.add_child(UI.margins(actions, UI.GAP_3))

	return shell


func _refresh() -> void:
	_rows = Store.list_saves()
	_count_label.text = UI._letterspace(
		"%d %s" % [_rows.size(), "save" if _rows.size() == 1 else "saves"]
	)
	if _selected == "" and not _rows.is_empty():
		_selected = String((_rows[0] as Dictionary)["path"])

	for child in _list_box.get_children():
		child.queue_free()

	for row in _rows:
		_list_box.add_child(_build_row(row))

	_rebuild_hero()


func _build_row(row: Dictionary) -> Control:
	var path := String(row["path"])
	var is_selected := path == _selected

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 50)
	button.focus_mode = Control.FOCUS_NONE
	var normal := UI.flat(UI.PANEL_RAISED if is_selected else UI.PANEL_INSET, UI.RULE if is_selected else Color.TRANSPARENT, 1, 8)
	if is_selected:
		normal.border_color = UI.ACCENT
		normal.border_width_left = 2
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.HAIRLINE, 1, 8))
	button.add_theme_stylebox_override("pressed", normal)
	button.pressed.connect(
		func() -> void:
			_selected = path
			_refresh()
	)

	var content := UI.hbox(UI.GAP_3)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := UI.fill_margins(content, UI.GAP_2)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(wrapper)

	content.add_child(UI.hatch(Vector2(44, 32), "Cover"))

	var text := UI.vbox(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(text)

	if bool(row.get("ok", false)):
		text.add_child(UI.elide(UI.display(String(row["name"]), 13)))
		var session_text := (
			"Session %d" % int(row["sessions"]) if int(row["sessions"]) > 0 else String(row["arc"])
		)
		text.add_child(
			UI.elide(
				UI.micro("%s · %d players · %s" % [row["city"], int(row["players"]), session_text])
			)
		)
	else:
		text.add_child(UI.elide(UI.display(String(row["name"]), 13)))
		text.add_child(
			UI.elide(UI.micro("Unreadable — %s" % String(row.get("error", "")), UI.ALERT_BRIGHT))
		)

	var meta := UI.vbox(1)
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(meta)
	var age := UI.micro(_format_age(int(row.get("modified", 0))))
	age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(age)
	var size_label := UI.micro(_format_size(int(row.get("size", 0))), UI.MUTED_DIM)
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(size_label)

	return button


## Select a save by path. Used by the screenshot harness so the shot does not
## depend on whichever file happened to be written last.
func select_save(save_path: String) -> void:
	_selected = save_path
	_refresh()


func _selected_row() -> Dictionary:
	for row in _rows:
		if String((row as Dictionary)["path"]) == _selected:
			return row
	return {}


func _rebuild_hero() -> void:
	for child in _hero_holder.get_children():
		child.queue_free()

	var row := _selected_row()
	var shell := UI.panel()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shell.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hero_holder.add_child(shell)

	if row.is_empty() or not bool(row.get("ok", false)):
		var empty := UI.vbox()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		var note := UI.micro("Select a campaign")
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(note)
		if not row.is_empty():
			var detail := UI.body(String(row.get("error", "")), 12, UI.ALERT_BRIGHT)
			detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(detail)
		shell.add_child(empty)
		return

	# The hero panel shows party state and the log, so it needs the whole
	# campaign — but only for the one save the GM is looking at.
	var loaded := CampaignContainer.load_file(String(row["path"]))
	var column := UI.vbox(0)
	shell.add_child(column)

	column.add_child(UI.hatch(Vector2(0, 104), "Campaign key art — 962 × 228 drop zone"))
	column.add_child(UI.rule_line())
	column.add_child(_build_hero_head(row, loaded))
	column.add_child(UI.rule_line())

	var body := UI.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(UI.expand(_build_party_and_log(loaded)))

	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(1, 0)
	divider.add_theme_stylebox_override("panel", UI.flat(UI.HAIRLINE))
	body.add_child(divider)

	body.add_child(_build_save_facts(row, loaded))


func _build_hero_head(row: Dictionary, loaded: Dictionary) -> Control:
	var head := UI.hbox(UI.GAP_4)

	var text := UI.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UI.micro("Active save · %s" % _format_age(int(row.get("modified", 0))), UI.ALERT_BRIGHT))
	text.add_child(UI.display(String(row["name"]), 34))
	var session_text := "Session %d · " % int(row["sessions"]) if int(row["sessions"]) > 0 else ""
	text.add_child(UI.micro("%s%s · %s" % [session_text, row["arc"], row["city"]]))
	head.add_child(text)

	var buttons := UI.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	var continue_button := UI.primary_button("▶ Continue")
	continue_button.pressed.connect(func() -> void: Store.open(String(row["path"])))
	buttons.add_child(continue_button)
	var snapshots := UI.plain_button("Snapshots")
	var restore_points: Array = (loaded.get("campaign", {}) as Dictionary).get("restore_points", [])
	snapshots.disabled = restore_points.is_empty()
	buttons.add_child(snapshots)
	head.add_child(buttons)

	return UI.margins(head, UI.GAP_4)


func _build_party_and_log(loaded: Dictionary) -> Control:
	var column := UI.vbox(UI.GAP_2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	column.add_child(UI.micro("Party"))
	var party_grid := GridContainer.new()
	party_grid.columns = 2
	party_grid.add_theme_constant_override("h_separation", UI.GAP_2)
	party_grid.add_theme_constant_override("v_separation", UI.GAP_2)
	column.add_child(party_grid)

	var characters: Array = (loaded.get("roster", {}) as Dictionary).get("characters", [])
	var party_count := 0
	for entry in characters:
		var character: Dictionary = entry
		if String(character.get("kind", "npc")) != "pc":
			continue
		party_count += 1
		party_grid.add_child(_build_party_card(character))
	if party_count == 0:
		column.add_child(UI.micro("No player characters yet."))

	column.add_child(UI.micro("Last session log"))
	var log_box := UI.vbox(0)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(log_box)
	var entries: Array = (loaded.get("campaign", {}) as Dictionary).get("session_log", [])
	for entry in entries:
		var line: Dictionary = entry
		log_box.add_child(UI.rule_line())
		var row := UI.hbox(UI.GAP_3)
		var session := UI.micro("Sess %d" % int(line["session"]))
		session.custom_minimum_size = Vector2(58, 0)
		row.add_child(session)
		var text := UI.body(String(line["text"]), 11)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Autowrap needs the full width, so clipping has to come back off.
		text.clip_text = false
		row.add_child(text)
		log_box.add_child(UI.margins(row, 4))
	if entries.is_empty():
		log_box.add_child(UI.micro("Nothing logged yet."))

	return UI.margins(column, UI.GAP_4)


func _build_party_card(character: Dictionary) -> Control:
	var card := UI.panel(UI.PANEL_INSET)
	var row := UI.hbox(UI.GAP_2)
	card.add_child(UI.margins(row, UI.GAP_2))

	row.add_child(UI.hatch(Vector2(34, 34)))

	var text := UI.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var name_row := UI.hbox(6)
	name_row.add_child(UI.display(String(character["name"]), 12))
	name_row.add_child(UI.micro(String(character["role"])))
	text.add_child(name_row)

	var body_sp := int((character["armor"] as Dictionary)["body"]["sp"])
	text.add_child(
		UI.micro(
			"HP %d/%d · HUM %d · SP %d"
			% [int(character["hp"]), int(character["max_hp"]), int(character["humanity"]), body_sp]
		)
	)
	text.add_child(UI.hp_bar(float(character["hp"]) / maxf(1.0, float(character["max_hp"]))))

	return card


func _build_save_facts(row: Dictionary, loaded: Dictionary) -> Control:
	var column := UI.vbox(UI.GAP_2)
	column.custom_minimum_size = Vector2(250, 0)

	column.add_child(UI.micro("Save file"))
	var facts := UI.vbox(0)
	column.add_child(facts)

	var integrity: Dictionary = loaded.get("integrity", {"verified": true, "problems": []})
	var verified := bool(integrity.get("verified", true))
	var problem_count := (integrity.get("problems", PackedStringArray()) as PackedStringArray).size()

	for pair in [
		["Format", ".RED v%s" % String(row["version"])],
		["Created", _format_date(String(row["created"]))],
		["Sessions", str(int(row["sessions"]))],
		["Locations", "%d built" % int(row["locations"])],
		["NPCs", str(int(row["npcs"]))],
		["Hooks", "%d open" % int(row["hooks"])],
	]:
		facts.add_child(UI.rule_line())
		facts.add_child(UI.field_row(String(pair[0]), String(pair[1])))
	facts.add_child(UI.rule_line())
	facts.add_child(
		UI.field_row(
			"Integrity",
			"Verified" if verified else "%d problems" % problem_count,
			UI.TEXT if verified else UI.ALERT_BRIGHT,
		)
	)

	column.add_child(UI.micro("Restore points"))
	var restore_points: Array = (loaded.get("campaign", {}) as Dictionary).get("restore_points", [])
	for entry in restore_points:
		var point: Dictionary = entry
		var card := UI.panel(UI.PANEL_INSET)
		var style := UI.flat(UI.PANEL_INSET, UI.HAIRLINE, 1)
		style.border_color = UI.ACCENT_FILL
		style.border_width_left = 2
		card.add_theme_stylebox_override("panel", style)
		var text := UI.vbox(1)
		card.add_child(UI.margins(text, UI.GAP_2))
		text.add_child(UI.display(String(point["label"]), 12))
		var created := String(point["created_at"])
		var clock := created.substr(11, 5) if created.length() >= 16 else ""
		text.add_child(UI.micro("Session %d · %s" % [int(point["session"]), clock]))
		column.add_child(card)
	if restore_points.is_empty():
		column.add_child(UI.micro("None recorded."))

	var path_label := UI.body(String(row["path"]), 9, UI.MUTED_DIM)
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	column.add_child(path_label)

	return UI.margins(column, UI.GAP_4)


func _create_campaign() -> void:
	_new_name.text = "New Campaign"
	_new_city.text = "Night City"
	_new_gm.text = ""
	_new_month.text = "2045-01"
	_new_dialog.popup_centered(Vector2i(520, 390))


func _build_new_campaign_dialog() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "Create campaign"
	_new_dialog.get_ok_button().text = "Create & open"
	var form := UI.vbox(UI.GAP_3)
	_new_name = _dialog_field(form, "Campaign name")
	_new_city = _dialog_field(form, "City / setting")
	_new_gm = _dialog_field(form, "Game master")
	_new_month = _dialog_field(form, "Starting month · YYYY-MM")
	_new_dialog.add_child(UI.margins(form, UI.GAP_4))
	_new_dialog.confirmed.connect(_confirm_create_campaign)
	add_child(_new_dialog)


func _dialog_field(form: VBoxContainer, label: String) -> LineEdit:
	form.add_child(UI.micro(label))
	var field := LineEdit.new()
	field.custom_minimum_size.y = 38
	form.add_child(field)
	return field


func _confirm_create_campaign() -> void:
	var name := _new_name.text.strip_edges()
	if name == "":
		Store.set_status("Campaign name is required")
		return
	if not Lifestyle.is_month(_new_month.text):
		Store.set_status("Starting month must use YYYY-MM")
		return
	var bundle := CampaignFixtures.new_campaign(name)
	var campaign: Dictionary = bundle["campaign"]
	campaign["city"] = _new_city.text.strip_edges() if _new_city.text.strip_edges() != "" else "Night City"
	campaign["gm"] = _new_gm.text.strip_edges()
	campaign["current_month"] = _new_month.text
	var parts := _new_month.text.split("-")
	campaign["clock"]["year"] = int(parts[0])
	campaign["clock"]["month"] = int(parts[1])
	var path := Store.library_dir().path_join(CampaignSchema.suggest_file_name(name))
	var suffix := 2
	while FileAccess.file_exists(path):
		path = Store.library_dir().path_join("%s_%d.red" % [CampaignSchema.suggest_file_name(name).trim_suffix(".red"), suffix])
		suffix += 1
	if not bool(CampaignContainer.save(path, bundle).get("ok", false)):
		Store.set_status("Campaign could not be created")
		return
	_selected = path
	_refresh()
	Store.open(path)


func _import_campaign() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.red", "Redline campaign")
	dialog.title = "Import campaign"
	dialog.size = Vector2i(760, 520)
	dialog.file_selected.connect(
		func(picked: String) -> void:
			var loaded := CampaignContainer.load_file(picked)
			if not bool(loaded.get("ok", false)):
				Store.set_status("Import failed: %s" % String(loaded.get("error", "")))
				return
			var destination := Store.library_dir().path_join(picked.get_file())
			DirAccess.copy_absolute(picked, ProjectSettings.globalize_path(destination))
			_selected = destination
			_refresh()
	)
	add_child(dialog)
	dialog.popup_centered()


static func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%d KB" % roundi(bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)


static func _format_age(unix_time: int) -> String:
	if unix_time <= 0:
		return "—"
	var days := (Time.get_unix_time_from_system() - unix_time) / 86400.0
	if days < 1.0:
		return "today"
	if days < 2.0:
		return "yesterday"
	if days < 14.0:
		return "%d days ago" % roundi(days)
	if days < 60.0:
		return "%d weeks ago" % roundi(days / 7.0)
	if days < 365.0:
		return "%d months ago" % roundi(days / 30.0)
	return "last year"


static func _format_date(iso: String) -> String:
	if iso.length() < 10:
		return "—"
	var parts := iso.substr(0, 10).split("-")
	if parts.size() != 3:
		return "—"
	return "%s %s %s" % [parts[2], CampaignSchema.MONTHS[int(parts[1]) - 1], parts[0]]
