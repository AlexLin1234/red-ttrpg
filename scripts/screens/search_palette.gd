class_name SearchPalette
extends Control

## One field over the whole campaign, on Ctrl+K.
##
## A GM mid-session knows the name of the thing they want and not which of nine
## screens it lives on. This finds it and goes there. The searching itself is
## [CampaignSearch]'s; this is the field, the list, and the keys.

signal chosen(row: Dictionary)

const MAX_ROWS := 12

var _field: LineEdit
var _results: VBoxContainer
var _rows: Array[Dictionary] = []
var _index := 0


func _init() -> void:
	name = "SearchPalette"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.06, 0.08, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				close()
	)
	add_child(scrim)

	# Centred by containers rather than by anchors and an offset: a panel whose
	# height comes from its contents cannot be positioned by anchors alone
	# without pinning a height it does not know yet.
	var row := UI.hbox(0)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var stack := UI.vbox(0)
	stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)

	var drop := Control.new()
	drop.custom_minimum_size = Vector2(0, 90)
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(drop)

	var frame := UI.panel(UI.PANEL)
	frame.custom_minimum_size = Vector2(620, 0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stack.add_child(frame)

	var column := UI.vbox(0)
	frame.add_child(column)

	_field = LineEdit.new()
	_field.placeholder_text = "Find a character, zone, place, beat, board, item…"
	_field.text_changed.connect(_on_typed)
	column.add_child(UI.margins(_field, UI.GAP_3))
	column.add_child(UI.rule_line())

	_results = UI.vbox(1)
	column.add_child(UI.margins(_results, UI.GAP_2))


func open() -> void:
	visible = true
	_field.text = ""
	_index = 0
	_rows = []
	_render()
	_field.grab_focus()


func close() -> void:
	visible = false
	_rows = []
	_index = 0


## Run a query without typing it, so the screenshot runner and the smoke test
## drive the same path the GM does.
func search(text: String) -> Array[Dictionary]:
	_field.text = text
	_on_typed(text)
	return _rows


func rows() -> Array[Dictionary]:
	return _rows


func selected() -> Dictionary:
	return _rows[_index] if _index >= 0 and _index < _rows.size() else {}


## Take whatever is highlighted.
func accept() -> void:
	var row := selected()
	close()
	if not row.is_empty():
		chosen.emit(row)


func _on_typed(text: String) -> void:
	_rows = CampaignSearch.query(
		{
			"campaign": Store.campaign,
			"roster": Store.roster,
			"locations": Store.locations,
			"items": ItemDB.catalog(),
		},
		text,
	)
	_index = 0
	_render()


func _render() -> void:
	for child in _results.get_children():
		child.queue_free()

	if _rows.is_empty():
		var hint := (
			"Type at least two characters."
			if _field.text.strip_edges().length() < 2
			else "Nothing in this campaign matches."
		)
		_results.add_child(UI.micro(hint, UI.MUTED_DIM))
		return

	for index in mini(_rows.size(), MAX_ROWS):
		_results.add_child(_build_row(_rows[index], index))
	if _rows.size() > MAX_ROWS:
		_results.add_child(
			UI.micro("%d more · keep typing" % (_rows.size() - MAX_ROWS), UI.MUTED_DIM)
		)


func _build_row(row: Dictionary, index: int) -> Control:
	var current := index == _index
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	var style := UI.flat(UI.PANEL_RAISED if current else UI.PANEL_INSET, UI.HAIRLINE, 1, 6)
	if current:
		style.border_color = UI.ACCENT
		style.border_width_left = 2
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.RULE, 1, 6))
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(
		func() -> void:
			_index = index
			accept()
	)

	var line := UI.hbox(UI.GAP_3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := UI.fill_margins(line, UI.GAP_2)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(wrapper)

	var kind := UI.micro(String(row["label"]))
	kind.custom_minimum_size = Vector2(104, 0)
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(kind)

	var text := UI.vbox(0)
	UI.expand(text, true, false)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(text)
	text.add_child(UI.elide(UI.value(String(row["title"]), 12)))
	if String(row["subtitle"]) != "":
		text.add_child(UI.elide(UI.micro(String(row["subtitle"]))))
	return button


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			accept()
		KEY_DOWN:
			_move(1)
		KEY_UP:
			_move(-1)
		_:
			return
	get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _rows.is_empty():
		return
	_index = wrapi(_index + delta, 0, mini(_rows.size(), MAX_ROWS))
	_render()
