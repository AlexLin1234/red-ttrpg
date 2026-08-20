extends Control

## The rulebook reference: ask, library, and setup.
##
## Three tabs, in the order a GM meets them. **Ask** is the table-side tab: the
## campaign's active books on the left, a question and its cited answer on the
## right. **Rulebook Library** manages the books this installation holds, which
## are shared by every campaign. **Assistant Setup** holds the GM's own Anthropic
## key and the disclosure that retrieved passages leave the machine.
##
## No rules are decided here. The assistant quotes the GM's own books and cites
## the page; Redline's own engine still owns every roll and every outcome.

const TABS := [
	{"id": "ask", "label": "Ask"},
	{"id": "books", "label": "Rulebook Library"},
	{"id": "setup", "label": "Assistant Setup"},
]

var _tab := "ask"
var _books: Array = []
var _key: Dictionary = {"stored": false, "hint": ""}
var _settings: Dictionary = {}
var _tiers: Array = []
var _history: Array = []
var _answer: Dictionary = {}
var _question := ""
var _message := ""
var _message_good := false
var _busy := false
var _loading := false

var _tab_row: HBoxContainer
var _body: PanelContainer
var _content: Control
var _question_field: TextEdit
var _key_field: LineEdit
var _import_dialog: FileDialog


func _ready() -> void:
	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_3))

	var header := UI.hbox(UI.GAP_3)
	header.add_child(UI.display("Rules Assistant", 22))
	_tab_row = UI.hbox(1)
	header.add_child(_tab_row)
	UI.expand(header, true, false)
	column.add_child(header)

	_body = UI.panel()
	UI.expand(_body)
	column.add_child(_body)

	Assistant.state_changed.connect(_on_helper_state)
	Store.campaign_changed.connect(_rebuild)
	Assistant.start()
	_refresh()


func _refresh() -> void:
	_loading = true
	_rebuild()
	Assistant.fetch_library(_on_library)


func _on_library(result: Dictionary) -> void:
	_loading = false
	if not bool(result.get("ok", false)):
		_message = String(result.get("error", "The assistant is unavailable."))
		_message_good = false
		_rebuild()
		return
	var data: Dictionary = result["data"]
	_books = data.get("books", [])
	_key = data.get("key", {"stored": false, "hint": ""})
	_settings = data.get("settings", {})
	_tiers = data.get("model_tiers", [])
	_rebuild()
	if Store.is_open():
		Assistant.fetch_history(Store.assistant_campaign_id(), _on_history)


func _on_history(result: Dictionary) -> void:
	_history = (result.get("data", {}) as Dictionary).get("entries", []) if bool(result.get("ok", false)) else []
	if _tab == "ask":
		_rebuild()


func _on_helper_state(state: String, detail: String) -> void:
	if state == Assistant.STATE_FAILED:
		_message = detail
		_message_good = false
	_rebuild()
	if state == Assistant.STATE_READY and _books.is_empty():
		_refresh()


func _show_tab(tab_id: String) -> void:
	_tab = tab_id
	_message = ""
	_rebuild()


# -- layout ------------------------------------------------------------------------


func _rebuild() -> void:
	# The screen is rebuilt whenever anything changes, so a half-typed question
	# is captured first rather than thrown away with the old field.
	if is_instance_valid(_question_field):
		_question = _question_field.text
	for child in _tab_row.get_children():
		child.queue_free()
	for entry in TABS:
		var tab: Dictionary = entry
		var button := UI.tab_button(String(tab["label"]), String(tab["id"]) == _tab)
		button.pressed.connect(_show_tab.bind(String(tab["id"])))
		_tab_row.add_child(button)

	if is_instance_valid(_content):
		_content.queue_free()
	var column := UI.vbox(UI.GAP_3)
	_content = UI.margins(column, UI.GAP_4)
	_body.add_child(_content)

	column.add_child(_helper_banner())
	match _tab:
		"books":
			column.add_child(_build_books())
		"setup":
			column.add_child(_build_setup())
		_:
			column.add_child(_build_ask())
	if _message != "":
		column.add_child(UI.body(_message, 13, UI.GOOD if _message_good else UI.ALERT_BRIGHT))


func _helper_banner() -> Control:
	var row := UI.hbox(UI.GAP_2)
	var label := "Local assistant: %s" % Assistant.state
	var colour := UI.MUTED
	if Assistant.state == Assistant.STATE_READY:
		label = "Local assistant running · books and index stay on this machine"
		colour = UI.GOOD
	elif Assistant.state == Assistant.STATE_STARTING:
		label = "Starting the local assistant…"
		colour = UI.WARN
	elif Assistant.state == Assistant.STATE_FAILED:
		label = Assistant.detail
		colour = UI.ALERT_BRIGHT
	else:
		label = "The local assistant is not running."
	row.add_child(UI.micro(label, colour))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if Assistant.state == Assistant.STATE_FAILED or Assistant.state == Assistant.STATE_STOPPED:
		var restart := UI.plain_button("Restart helper")
		restart.pressed.connect(func() -> void:
			Assistant.restart()
			_refresh()
		)
		row.add_child(restart)
	return row


# -- ask ---------------------------------------------------------------------------


func _build_ask() -> Control:
	if not Store.is_open():
		var empty := UI.vbox(UI.GAP_2)
		empty.add_child(UI.display("Open a campaign", 20))
		empty.add_child(
			UI.body(
				"The assistant answers from the books a campaign has made active. Open a save in the Library first.",
				13,
				UI.MUTED,
			)
		)
		return empty
	var row := UI.hbox(UI.GAP_4)
	UI.expand(row)
	row.add_child(_active_books_rail())
	row.add_child(_question_panel())
	return row


func _active_books_rail() -> Control:
	var panel := UI.panel(UI.PANEL_INSET)
	panel.custom_minimum_size = Vector2(320, 0)
	var column := UI.vbox(UI.GAP_2)
	panel.add_child(UI.margins(column, UI.GAP_3))
	column.add_child(UI.micro("Active in this campaign"))

	var resolved := Rulebooks.resolve(Store.campaign, _books)
	if _books.is_empty():
		column.add_child(
			UI.body("No rulebooks are installed yet. Import one in the Rulebook Library tab.", 12, UI.MUTED)
		)
		return panel

	for value in _books:
		var book: Dictionary = value
		var book_id := String(book["book_id"])
		var box := CheckBox.new()
		box.text = String(book.get("label", book.get("filename", book_id)))
		box.button_pressed = Store.is_rulebook_active(book_id)
		box.disabled = String(book.get("status", "")) != "indexed"
		box.tooltip_text = _book_status_line(book)
		box.toggled.connect(func(pressed: bool) -> void:
			Store.set_rulebook_active(book_id, pressed)
			_rebuild()
		)
		column.add_child(box)
		var status := String(book.get("status", ""))
		if status != "indexed":
			column.add_child(UI.micro(_book_status_line(book), UI.WARN))

	for value in (resolved["unavailable"] as Array):
		column.add_child(UI.micro("Source unavailable on this machine", UI.ALERT_BRIGHT))
		column.add_child(UI.body(String(value), 11, UI.MUTED_DIM))

	column.add_child(UI.rule_line())
	column.add_child(
		UI.micro(
			"%d of %d books searched" % [Store.searchable_rulebook_ids(_books).size(), _books.size()]
		)
	)
	return panel


func _question_panel() -> Control:
	var panel := UI.panel()
	UI.expand(panel)
	var column := UI.vbox(UI.GAP_3)
	panel.add_child(UI.margins(column, UI.GAP_4))

	if not bool(_settings.get("disclosure_accepted", false)):
		column.add_child(_disclosure())

	column.add_child(UI.micro("Ask the rulebooks"))
	_question_field = TextEdit.new()
	_question_field.text = _question
	_question_field.placeholder_text = "When does armor ablate?"
	_question_field.custom_minimum_size = Vector2(0, 68)
	_question_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_question_field)

	var actions := UI.hbox(UI.GAP_2)
	var ask := UI.primary_button("Ask" if not _busy else "Asking…")
	ask.disabled = _busy or not bool(_key.get("stored", false))
	ask.pressed.connect(_ask)
	actions.add_child(ask)
	if not bool(_key.get("stored", false)):
		var setup := UI.plain_button("Add API key")
		setup.pressed.connect(_show_tab.bind("setup"))
		actions.add_child(setup)
		actions.add_child(UI.body("An Anthropic API key is needed to ask.", 12, UI.WARN))
	column.add_child(actions)
	column.add_child(UI.rule_line())

	if _busy:
		column.add_child(UI.body("Searching the active books…", 13, UI.MUTED))
	elif not _answer.is_empty():
		column.add_child(_answer_block())
	else:
		column.add_child(
			UI.body(
				"Answers come only from the active books, and always name the file and PDF page they came from.",
				13,
				UI.MUTED,
			)
		)

	if not _history.is_empty():
		column.add_child(_history_block())
	return panel


func _disclosure() -> Control:
	var box := UI.panel(UI.PANEL_INSET, UI.ACCENT_DIM)
	var column := UI.vbox(UI.GAP_2)
	box.add_child(UI.margins(column, UI.GAP_3))
	column.add_child(UI.micro("Before your first question", UI.ACCENT))
	var prose := UI.body(
		"Your rulebooks, the extracted text and the search index never leave this machine. "
		+ "When you ask a question, the passages found in your active books are sent to Anthropic "
		+ "with your question, using your own API key. Nothing else about your campaign is sent.",
		13,
		UI.TEXT,
	)
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prose)
	var accept := UI.plain_button("I understand")
	accept.pressed.connect(func() -> void:
		Assistant.save_settings({"disclosure_accepted": true}, func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				_settings = (result["data"] as Dictionary).get("settings", _settings)
			_rebuild()
		)
	)
	column.add_child(accept)
	return box


func _ask() -> void:
	if not is_instance_valid(_question_field):
		return
	_question = _question_field.text.strip_edges()
	if _question.length() < 3:
		_message = "Ask a rules question first."
		_message_good = false
		_rebuild()
		return
	var active := Store.searchable_rulebook_ids(_books)
	if active.is_empty():
		_message = "Choose at least one indexed rulebook for this campaign."
		_message_good = false
		_rebuild()
		return
	_busy = true
	_message = ""
	_answer = {}
	_rebuild()
	Assistant.ask(_question, active, Store.assistant_campaign_id(), _on_answer)


func _on_answer(result: Dictionary) -> void:
	_busy = false
	if not bool(result.get("ok", false)):
		_message = String(result.get("error", "The assistant could not answer."))
		_message_good = false
		if String(result.get("code", "")) in ["missing_key", "invalid_key"]:
			# Switch tabs without going through _show_tab, which would clear the
			# very message that explains why the GM is now looking at Setup. The
			# question itself is held in _question and comes back with the tab.
			_tab = "setup"
		_rebuild()
		return
	_answer = result["data"]
	_rebuild()
	if Store.is_open():
		Assistant.fetch_history(Store.assistant_campaign_id(), _on_history)


func _answer_block() -> Control:
	var column := UI.vbox(UI.GAP_2)
	var status := String(_answer.get("status", ""))
	column.add_child(
		UI.micro(
			"Answer" if status == "answered" else "Not established by the active books",
			UI.GOOD if status == "answered" else UI.WARN,
		)
	)
	var prose := UI.body(String(_answer.get("answer", "")), 15)
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prose)

	var citations: Array = _answer.get("citations", [])
	if not citations.is_empty():
		column.add_child(UI.micro("Source"))
		for value in citations:
			var citation: Dictionary = value
			column.add_child(UI.value(String(citation.get("label", "")), 13, UI.ACCENT))
	for value in (_answer.get("unavailable_books", []) as Array):
		column.add_child(
			UI.micro("An active book is not installed here and was not searched: %s" % String(value), UI.ALERT_BRIGHT)
		)
	for value in (_answer.get("indexing_books", []) as Array):
		column.add_child(UI.micro("Still indexing, not searched: %s" % String(value), UI.WARN))
	column.add_child(UI.micro(String(_answer.get("disclosure", "")), UI.MUTED_DIM))
	return column


func _history_block() -> Control:
	var column := UI.vbox(UI.GAP_1)
	var header := UI.hbox(UI.GAP_2)
	header.add_child(UI.micro("Earlier questions in this campaign"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var clear := UI.plain_button("Clear history")
	clear.pressed.connect(func() -> void:
		Assistant.clear_history(Store.assistant_campaign_id(), func(_result: Dictionary) -> void:
			_history = []
			_rebuild()
		)
	)
	header.add_child(clear)
	column.add_child(header)
	for index in mini(_history.size(), 6):
		var entry: Dictionary = _history[index]
		var line := UI.body(String(entry.get("question", "")), 12, UI.MUTED)
		UI.elide(line)
		column.add_child(line)
	return column


# -- library -----------------------------------------------------------------------


func _build_books() -> Control:
	var column := UI.vbox(UI.GAP_3)
	UI.expand(column)

	var header := UI.hbox(UI.GAP_2)
	header.add_child(UI.micro("Installed for every campaign on this computer"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var import_button := UI.primary_button("Import PDF")
	import_button.pressed.connect(_open_import_dialog)
	header.add_child(import_button)
	var refresh := UI.plain_button("Refresh")
	refresh.pressed.connect(_refresh)
	header.add_child(refresh)
	column.add_child(header)
	column.add_child(UI.rule_line())

	if _loading:
		column.add_child(UI.body("Reading the library…", 13, UI.MUTED))
		return column
	if _books.is_empty():
		column.add_child(
			UI.body(
				"No rulebooks yet. Import a PDF you own — it is copied into Redline's private folder, "
				+ "indexed locally, and never included in a campaign save or an export.",
				13,
				UI.MUTED,
			)
		)
		return column

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(UI.GAP_2)
	UI.expand(list, true, false)
	scroll.add_child(list)
	for value in _books:
		list.add_child(_book_row(value))
	column.add_child(scroll)
	return column


func _book_row(book: Dictionary) -> Control:
	var book_id := String(book["book_id"])
	var panel := UI.panel(UI.PANEL_INSET)
	var column := UI.vbox(UI.GAP_1)
	panel.add_child(UI.margins(column, UI.GAP_3))

	var title := UI.hbox(UI.GAP_2)
	title.add_child(UI.value(String(book.get("label", book.get("filename", book_id))), 15))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(spacer)
	if Store.is_open():
		var active := CheckBox.new()
		active.text = "Active"
		active.button_pressed = Store.is_rulebook_active(book_id)
		active.disabled = String(book.get("status", "")) != "indexed"
		active.toggled.connect(func(pressed: bool) -> void:
			Store.set_rulebook_active(book_id, pressed)
			_rebuild()
		)
		title.add_child(active)
	column.add_child(title)

	column.add_child(UI.micro(String(book.get("filename", "")), UI.MUTED))
	column.add_child(UI.micro(_book_status_line(book), _status_colour(String(book.get("status", "")))))

	var actions := UI.hbox(UI.GAP_2)
	var reindex := UI.plain_button("Reindex")
	reindex.pressed.connect(func() -> void:
		Assistant.reindex_book(book_id, func(result: Dictionary) -> void:
			_note(result, "Indexing %s…" % String(book.get("label", "")))
		)
	)
	actions.add_child(reindex)

	var label_field := LineEdit.new()
	label_field.text = String(book.get("label", ""))
	label_field.custom_minimum_size = Vector2(220, 0)
	actions.add_child(label_field)
	var rename := UI.plain_button("Rename")
	rename.pressed.connect(func() -> void:
		Assistant.rename_book(book_id, label_field.text, func(result: Dictionary) -> void:
			_note(result, "Renamed.")
		)
	)
	actions.add_child(rename)

	var remove := UI.plain_button("Remove")
	remove.tooltip_text = "Deletes the imported copy and its index. Campaigns that used it stay valid."
	remove.pressed.connect(func() -> void:
		Assistant.remove_book(book_id, func(result: Dictionary) -> void:
			_note(result, "Removed from this installation.")
		)
	)
	actions.add_child(remove)
	column.add_child(actions)
	return panel


func _book_status_line(book: Dictionary) -> String:
	var pages := int(book.get("page_count", 0))
	var megabytes := float(book.get("bytes", 0)) / 1048576.0
	var imported := String(book.get("imported_at", "")).left(10)
	match String(book.get("status", "")):
		"indexed":
			return "Indexed · %d pages · %.1f MB · imported %s" % [pages, megabytes, imported]
		"indexing":
			return "Indexing page %d of %d…" % [int(book.get("indexed_pages", 0)), pages]
		"pending":
			return "Waiting to be indexed · %d pages" % pages
		"unavailable":
			return "The imported file is missing from Redline's library folder."
		"failed":
			return String(book.get("error", "Indexing failed."))
	return "%d pages · %.1f MB" % [pages, megabytes]


func _status_colour(status: String) -> Color:
	match status:
		"indexed":
			return UI.GOOD
		"failed", "unavailable":
			return UI.ALERT_BRIGHT
		_:
			return UI.WARN


func _open_import_dialog() -> void:
	if not is_instance_valid(_import_dialog):
		_import_dialog = FileDialog.new()
		_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_dialog.use_native_dialog = true
		_import_dialog.title = "Import rulebook PDFs you own"
		_import_dialog.filters = PackedStringArray(["*.pdf ; PDF rulebooks"])
		_import_dialog.files_selected.connect(_import_files)
		_import_dialog.file_selected.connect(func(path: String) -> void:
			_import_files(PackedStringArray([path]))
		)
		add_child(_import_dialog)
	_import_dialog.popup_centered_ratio(0.7)


func _import_files(files: PackedStringArray) -> void:
	for path in files:
		Assistant.import_book(path, func(result: Dictionary) -> void:
			if not bool(result.get("ok", false)):
				_note(result, "")
				return
			var data: Dictionary = result["data"]
			var book: Dictionary = data.get("book", {})
			var label := String(book.get("label", path.get_file()))
			_message = (
				"Imported %s. Indexing starts now." % label
				if bool(data.get("imported", false))
				else "%s is already in the library." % label
			)
			_message_good = true
			_refresh()
		)


# -- setup -------------------------------------------------------------------------


func _build_setup() -> Control:
	var column := UI.vbox(UI.GAP_3)
	column.add_child(UI.micro("Anthropic API key"))
	var prose := UI.body(
		"The assistant uses your own Anthropic key. It is stored in this computer's credential vault — "
		+ "never in a campaign save, a settings file, or an export. Your books and index stay local; only "
		+ "the passages found for a question are sent, with the question itself.",
		13,
		UI.MUTED,
	)
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prose)

	var stored := bool(_key.get("stored", false))
	column.add_child(
		UI.value(
			"Key stored (%s)" % String(_key.get("hint", "")) if stored else "No key stored yet",
			14,
			UI.GOOD if stored else UI.WARN,
		)
	)

	_key_field = LineEdit.new()
	_key_field.secret = true
	_key_field.placeholder_text = "sk-ant-…"
	_key_field.custom_minimum_size = Vector2(420, 0)
	column.add_child(_key_field)

	var actions := UI.hbox(UI.GAP_2)
	var save := UI.primary_button("Replace key" if stored else "Save key")
	save.pressed.connect(func() -> void:
		Assistant.store_key(_key_field.text.strip_edges(), func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				_key = (result["data"] as Dictionary).get("key", _key)
			_note(result, "Key stored in the credential vault.")
		)
	)
	actions.add_child(save)
	var test := UI.plain_button("Test key")
	test.disabled = not stored
	test.pressed.connect(func() -> void:
		Assistant.test_key(func(result: Dictionary) -> void:
			_note(result, "Anthropic accepted the key.")
		)
	)
	actions.add_child(test)
	var remove := UI.plain_button("Remove key")
	remove.disabled = not stored
	remove.pressed.connect(func() -> void:
		Assistant.remove_key(func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				_key = (result["data"] as Dictionary).get("key", {"stored": false, "hint": ""})
			_note(result, "Key removed from the credential vault.")
		)
	)
	actions.add_child(remove)
	column.add_child(actions)

	column.add_child(UI.rule_line())
	column.add_child(UI.micro("Model"))
	var tier_row := UI.hbox(UI.GAP_2)
	var current := String(_settings.get("model_tier", "capable"))
	for value in _tiers:
		var tier := String(value)
		var button := UI.tab_button(_tier_label(tier), tier == current)
		button.pressed.connect(func() -> void:
			Assistant.save_settings({"model_tier": tier}, func(result: Dictionary) -> void:
				if bool(result.get("ok", false)):
					_settings = (result["data"] as Dictionary).get("settings", _settings)
				_note(result, "Model set to %s." % _tier_label(tier))
			)
		)
		tier_row.add_child(button)
	column.add_child(tier_row)
	column.add_child(
		UI.body(
			"The choice is stored per installation, not in a campaign, so a shared save never carries a model name.",
			12,
			UI.MUTED,
		)
	)

	column.add_child(UI.rule_line())
	var history_box := CheckBox.new()
	history_box.text = "Keep a local history of questions per campaign"
	history_box.button_pressed = bool(_settings.get("history_enabled", true))
	history_box.toggled.connect(func(pressed: bool) -> void:
		Assistant.save_settings({"history_enabled": pressed}, func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				_settings = (result["data"] as Dictionary).get("settings", _settings)
		)
	)
	column.add_child(history_box)
	return column


func _tier_label(tier: String) -> String:
	return "Fast and economical" if tier == "fast" else "More capable"


func _note(result: Dictionary, success: String) -> void:
	_message_good = bool(result.get("ok", false))
	_message = success if _message_good else String(result.get("error", "That did not work."))
	_refresh()
