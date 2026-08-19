extends Control

## A GM-only campaign notebook with a small, persistent directed beat graph.

const FlowRules := preload("res://scripts/rules/campaign_flow.gd")

var _selected_id := ""
var _beat_list: VBoxContainer
var _editor: VBoxContainer
var _canvas: _BeatCanvas
var _notes: TextEdit


func _ready() -> void:
	FlowRules.ensure_campaign(Store.campaign)

	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_3))
	column.add_child(_build_header())

	var body := UI.hbox(UI.GAP_3)
	UI.expand(body)
	column.add_child(body)

	body.add_child(_build_notebook())
	body.add_child(_build_flowchart())
	body.add_child(_build_editor_shell())

	if not Store.beats().is_empty():
		_selected_id = String((Store.beats()[0] as Dictionary)["id"])
	_refresh_all()


func _build_header() -> Control:
	var row := UI.hbox(UI.GAP_3)
	var titles := UI.vbox(0)
	titles.add_child(UI.micro("GM tools · private campaign workspace"))
	titles.add_child(UI.display("Notes / Beats", 26))
	UI.expand(titles, true, false)
	row.add_child(titles)
	var add := UI.primary_button("+ Add beat")
	add.pressed.connect(_add_beat)
	row.add_child(add)
	return row


func _build_notebook() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(300, 0)
	UI.expand(shell, false, true)
	var box := UI.vbox(UI.GAP_2)
	shell.add_child(UI.margins(box, UI.GAP_3))
	box.add_child(UI.micro("Campaign notes"))
	box.add_child(UI.body("Loose notes, clues, and session prep. Saved inside this campaign.", 11, UI.MUTED))
	_notes = TextEdit.new()
	_notes.placeholder_text = "What is moving behind the scenes?"
	_notes.text = String(Store.campaign.get("gm_notes", ""))
	_notes.custom_minimum_size = Vector2(0, 210)
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes.text_changed.connect(_save_gm_notes)
	box.add_child(_notes)
	box.add_child(UI.rule_line())
	box.add_child(UI.micro("Beat index"))

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	_beat_list = UI.vbox(UI.GAP_1)
	_beat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_beat_list)
	box.add_child(scroll)
	return shell


func _build_flowchart() -> Control:
	var shell := UI.panel(UI.PANEL_INSET)
	UI.expand(shell)
	var column := UI.vbox(UI.GAP_2)
	shell.add_child(UI.margins(column, UI.GAP_2))
	var hint := UI.micro("Campaign flow · drag cards to arrange · click to edit")
	column.add_child(hint)

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	_canvas = _BeatCanvas.new()
	_canvas.custom_minimum_size = FlowRules.CANVAS_SIZE
	_canvas.beat_selected.connect(_select_beat)
	_canvas.beat_moved.connect(_move_beat)
	scroll.add_child(_canvas)
	column.add_child(scroll)
	return shell


func _build_editor_shell() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(310, 0)
	UI.expand(shell, false, true)
	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	_editor = UI.vbox(UI.GAP_2)
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_editor)
	shell.add_child(UI.margins(scroll, UI.GAP_3))
	return shell


func _refresh_all() -> void:
	_refresh_list()
	_refresh_editor()
	_canvas.set_beats(Store.beats())
	_canvas.set_selected(_selected_id)


func _refresh_list() -> void:
	_clear(_beat_list)
	if Store.beats().is_empty():
		_beat_list.add_child(UI.body("No beats yet. Add one to begin the campaign flow.", 11, UI.MUTED))
		return
	for value in Store.beats():
		var beat: Dictionary = value
		var id := String(beat["id"])
		var button := UI.plain_button(
			"%s  ·  %s" % [String(beat.get("status", "planned")), String(beat.get("title", "Untitled"))]
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = id == _selected_id
		button.pressed.connect(_select_beat.bind(id))
		_beat_list.add_child(button)


func _refresh_editor() -> void:
	_clear(_editor)
	var beat := Store.beat_by_id(_selected_id)
	if beat.is_empty():
		_editor.add_child(UI.micro("Beat editor"))
		_editor.add_child(UI.body("Select a beat on the canvas, or add a new one.", 12, UI.MUTED))
		return

	_editor.add_child(UI.micro("Selected beat"))
	var title := LineEdit.new()
	title.placeholder_text = "Beat title"
	title.text = String(beat.get("title", ""))
	title.text_changed.connect(_rename_beat.bind(_selected_id))
	title.focus_exited.connect(_refresh_list)
	_editor.add_child(title)

	_editor.add_child(UI.micro("Status"))
	var status := OptionButton.new()
	for value in FlowRules.STATUSES:
		status.add_item(String(value).capitalize())
		status.set_item_metadata(status.item_count - 1, String(value))
		if String(value) == String(beat.get("status", "planned")):
			status.select(status.item_count - 1)
	status.item_selected.connect(_set_status.bind(_selected_id, status))
	_editor.add_child(status)

	_editor.add_child(UI.micro("Beat notes"))
	var notes := TextEdit.new()
	notes.placeholder_text = "Scene details, clues, NPC intent, consequences…"
	notes.text = String(beat.get("notes", ""))
	notes.custom_minimum_size = Vector2(0, 180)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.text_changed.connect(_save_beat_notes.bind(_selected_id, notes))
	_editor.add_child(notes)

	_editor.add_child(UI.rule_line())
	_editor.add_child(UI.micro("Leads to"))
	var link_row := UI.hbox(UI.GAP_2)
	var picker := OptionButton.new()
	UI.expand(picker, true, false)
	for value in Store.beats():
		var target: Dictionary = value
		var target_id := String(target["id"])
		if target_id == _selected_id or (beat["next_ids"] as Array).has(target_id):
			continue
		picker.add_item(String(target.get("title", "Untitled")))
		picker.set_item_metadata(picker.item_count - 1, target_id)
	link_row.add_child(picker)
	var link := UI.plain_button("Add link")
	link.disabled = picker.item_count == 0
	link.pressed.connect(_add_link.bind(_selected_id, picker))
	link_row.add_child(link)
	_editor.add_child(link_row)

	if (beat["next_ids"] as Array).is_empty():
		_editor.add_child(UI.body("No outgoing path yet.", 11, UI.MUTED))
	else:
		for next_id_value in beat["next_ids"]:
			var next_id := String(next_id_value)
			var target := Store.beat_by_id(next_id)
			var row := UI.hbox(UI.GAP_2)
			var label := UI.value("→ %s" % String(target.get("title", "Missing beat")), 12)
			UI.expand(label, true, false)
			row.add_child(label)
			var remove := UI.plain_button("Remove")
			remove.pressed.connect(_remove_link.bind(_selected_id, next_id))
			row.add_child(remove)
			_editor.add_child(row)

	_editor.add_child(UI.rule_line())
	var delete := UI.plain_button("Delete beat")
	delete.add_theme_color_override("font_color", UI.ALERT_BRIGHT)
	delete.pressed.connect(_delete_beat.bind(_selected_id))
	_editor.add_child(delete)


func _save_gm_notes() -> void:
	Store.campaign["gm_notes"] = _notes.text
	Store.mark_dirty()


func _add_beat() -> void:
	var beat := Store.add_beat()
	_selected_id = String(beat["id"])
	_refresh_all()


func _select_beat(id: String) -> void:
	_selected_id = id
	_refresh_all()


func _move_beat(id: String, point: Vector2, finished: bool) -> void:
	Store.move_beat(id, point)
	_canvas.set_beats(Store.beats())
	if finished:
		Store.set_status("Beat relocated")


func _rename_beat(value: String, id: String) -> void:
	var beat := Store.beat_by_id(id)
	if beat.is_empty():
		return
	beat["title"] = value
	Store.mark_dirty()
	_canvas.set_beats(Store.beats())


func _set_status(index: int, id: String, picker: OptionButton) -> void:
	var beat := Store.beat_by_id(id)
	if beat.is_empty():
		return
	beat["status"] = String(picker.get_item_metadata(index))
	Store.mark_dirty()
	_refresh_all()


func _save_beat_notes(id: String, field: TextEdit) -> void:
	var beat := Store.beat_by_id(id)
	if beat.is_empty():
		return
	beat["notes"] = field.text
	Store.mark_dirty()


func _add_link(id: String, picker: OptionButton) -> void:
	if picker.item_count == 0:
		return
	if Store.connect_beats(id, String(picker.get_item_metadata(picker.selected))):
		_refresh_all()


func _remove_link(id: String, next_id: String) -> void:
	if Store.disconnect_beats(id, next_id):
		_refresh_all()


func _delete_beat(id: String) -> void:
	if not Store.remove_beat(id):
		return
	_selected_id = String((Store.beats()[0] as Dictionary)["id"]) if not Store.beats().is_empty() else ""
	Store.set_status("Beat deleted")
	_refresh_all()


static func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


class _BeatCanvas extends Control:
	signal beat_selected(id: String)
	signal beat_moved(id: String, point: Vector2, finished: bool)

	const NODE_SIZE := Vector2(190, 82)
	const DRAG_THRESHOLD := 4.0

	var _beats: Array = []
	var _selected := ""
	var _pressed := ""
	var _dragged := false
	var _press_at := Vector2.ZERO
	var _drag_offset := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_beats(beats: Array) -> void:
		_beats = beats
		queue_redraw()

	func set_selected(id: String) -> void:
		_selected = id
		queue_redraw()

	func _beat_rect(beat: Dictionary) -> Rect2:
		return Rect2(FlowRules.beat_position(beat), NODE_SIZE)

	func _beat_at(point: Vector2) -> String:
		for index in range(_beats.size() - 1, -1, -1):
			var beat: Dictionary = _beats[index]
			if _beat_rect(beat).has_point(point):
				return String(beat["id"])
		return ""

	func _by_id(id: String) -> Dictionary:
		for value in _beats:
			var beat: Dictionary = value
			if String(beat["id"]) == id:
				return beat
		return {}

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			if _pressed != "":
				if motion.position.distance_to(_press_at) >= DRAG_THRESHOLD:
					_dragged = true
				if _dragged:
					mouse_default_cursor_shape = Control.CURSOR_MOVE
					var point := motion.position - _drag_offset
					point.x = clampf(point.x, 0.0, size.x - NODE_SIZE.x)
					point.y = clampf(point.y, 0.0, size.y - NODE_SIZE.y)
					beat_moved.emit(_pressed, point.snapped(Vector2(5, 5)), false)
				return
			mouse_default_cursor_shape = (
				Control.CURSOR_DRAG if _beat_at(motion.position) != "" else Control.CURSOR_ARROW
			)
			return

		if not event is InputEventMouseButton:
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_pressed = _beat_at(button.position)
			if _pressed != "":
				_selected = _pressed
				_press_at = button.position
				_drag_offset = button.position - _beat_rect(_by_id(_pressed)).position
				_dragged = false
				queue_redraw()
			return
		if _pressed == "":
			return
		var released := _pressed
		_pressed = ""
		if _dragged:
			var point := button.position - _drag_offset
			point.x = clampf(point.x, 0.0, size.x - NODE_SIZE.x)
			point.y = clampf(point.y, 0.0, size.y - NODE_SIZE.y)
			beat_moved.emit(released, point.snapped(Vector2(5, 5)), true)
		else:
			beat_selected.emit(released)
		_dragged = false
		queue_redraw()

	func _draw() -> void:
		var step := 40.0
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color("141c26"), 1.0)
			x += step
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color("141c26"), 1.0)
			y += step

		for value in _beats:
			var source: Dictionary = value
			var from := _beat_rect(source).position + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
			for next_id in source.get("next_ids", []):
				var target := _by_id(String(next_id))
				if target.is_empty():
					continue
				var to := _beat_rect(target).position + Vector2(0, NODE_SIZE.y * 0.5)
				var elbow_x := (from.x + to.x) * 0.5
				var points := PackedVector2Array([from, Vector2(elbow_x, from.y), Vector2(elbow_x, to.y), to])
				draw_polyline(points, UI.ACCENT_FILL, 2.0)
				draw_line(to, to + Vector2(-8, -5), UI.ACCENT_FILL, 2.0)
				draw_line(to, to + Vector2(-8, 5), UI.ACCENT_FILL, 2.0)

		for value in _beats:
			var beat: Dictionary = value
			var id := String(beat["id"])
			var rect := _beat_rect(beat)
			var status := String(beat.get("status", "planned"))
			var color := _status_color(status)
			draw_rect(rect, UI.PANEL_RAISED, true)
			draw_rect(rect, UI.ACCENT if id == _selected else UI.RULE, false, 2.0 if id == _selected else 1.0)
			draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), color, true)
			draw_string(
				UI.BODY_BOLD_FONT,
				rect.position + Vector2(14, 27),
				String(beat.get("title", "Untitled")),
				HORIZONTAL_ALIGNMENT_LEFT,
				NODE_SIZE.x - 26,
				14,
				UI.TEXT_DISPLAY,
			)
			draw_string(
				UI.BODY_BOLD_FONT,
				rect.position + Vector2(14, 56),
				status.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT,
				NODE_SIZE.x - 26,
				10,
				color,
			)

	func _status_color(status: String) -> Color:
		match status:
			"active":
				return UI.ACCENT
			"complete":
				return UI.GOOD
			"skipped":
				return UI.MUTED_DIM
			_:
				return UI.WARN
