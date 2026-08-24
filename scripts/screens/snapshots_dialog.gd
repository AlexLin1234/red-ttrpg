class_name SnapshotsDialog
extends AcceptDialog

## Restore points: taking them, reading them, going back to one.
##
## The library has drawn this list since the first release and the button beside
## it was connected to nothing. This is what it opens.

signal changed

var _list: VBoxContainer
var _label_field: LineEdit


func _init() -> void:
	title = "Restore points"
	get_ok_button().text = "Close"
	var column := UI.vbox(UI.GAP_3)
	column.custom_minimum_size = Vector2(560, 0)
	add_child(UI.margins(column, UI.GAP_4))

	var take := UI.hbox(UI.GAP_2)
	_label_field = LineEdit.new()
	_label_field.placeholder_text = "Before the Parkade"
	UI.expand(_label_field, true, false)
	take.add_child(_label_field)
	var button := UI.primary_button("Take one now")
	button.pressed.connect(_take)
	take.add_child(button)
	column.add_child(take)
	column.add_child(
		UI.micro(
			"A whole copy of the campaign, kept beside the save. The newest %d are held."
			% RestorePoints.KEEP
		)
	)
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 320)
	column.add_child(scroll)
	_list = UI.vbox(UI.GAP_1)
	UI.expand(_list, true, false)
	scroll.add_child(_list)


func open() -> void:
	_refresh()
	popup_centered(Vector2i(620, 520))


func _take() -> void:
	Store.create_restore_point(_label_field.text)
	_label_field.text = ""
	_refresh()
	changed.emit()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var points := Store.restore_points()
	if points.is_empty():
		_list.add_child(UI.micro("None yet. Take one before the party does something."))
		return

	for entry in points:
		var point: Dictionary = entry
		var id := String(point["id"])
		var card := UI.panel(UI.PANEL_INSET)
		var row := UI.hbox(UI.GAP_3)
		card.add_child(UI.margins(row, UI.GAP_2))

		var text := UI.vbox(1)
		UI.expand(text, true, false)
		row.add_child(text)
		text.add_child(UI.elide(UI.value(String(point["label"]), 12)))
		var created := String(point.get("created_at", ""))
		text.add_child(
			UI.elide(
				UI.micro(
					"Session %d · %s" % [int(point.get("session", 0)), created.replace("T", " ")]
				)
			)
		)

		var restore := UI.plain_button("Restore")
		restore.tooltip_text = "Load it as unsaved changes; the file on disk is untouched"
		restore.pressed.connect(
			func() -> void:
				if Store.restore_to(id):
					hide()
					changed.emit()
		)
		row.add_child(restore)

		var remove := UI.plain_button("Delete")
		remove.pressed.connect(
			func() -> void:
				Store.remove_restore_point(id)
				_refresh()
				changed.emit()
		)
		row.add_child(remove)
		_list.add_child(card)
