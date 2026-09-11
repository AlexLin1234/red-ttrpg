class_name SessionDialog
extends ConfirmationDialog

## Ending a session: what the party earned, and what it is remembered as.
##
## [method Store.start_session] has been called from the Library's Continue
## button since sessions existed, and [method Store.end_session] was written at
## the same time and then called by nothing — so a campaign counted the evenings
## it began and never the ones it finished.
##
## This is the other end, and it is also the only place Improvement Points are
## actually handed out. IP had a sink and no source: it could be spent on a
## skill or a Role rank, but the only way to grant it was to type a number into
## one sheet at a time, which is not what a GM is doing at midnight with four
## players waiting to log off.

signal finished

var _amount: SpinBox
var _summary: LineEdit
var _rows: Array[Dictionary] = []
var _list: VBoxContainer
var _note: Label


func _init() -> void:
	title = "End session"
	theme = UI.build_theme()
	get_ok_button().text = "End the session"
	get_cancel_button().text = "Not yet"
	confirmed.connect(_apply)

	var box := UI.vbox(UI.GAP_3)
	box.custom_minimum_size = Vector2(520, 0)
	add_child(UI.margins(box, UI.GAP_4))

	_note = UI.body("", 13, UI.MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.clip_text = false
	box.add_child(_note)

	box.add_child(UI.rule_line())

	var award_row := UI.hbox(UI.GAP_3)
	var award_label := UI.micro("Improvement Points each")
	award_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI.expand(award_label, true, false)
	award_row.add_child(award_label)
	_amount = SpinBox.new()
	_amount.min_value = 0
	_amount.max_value = 999
	_amount.value = 10
	_amount.custom_minimum_size = Vector2(110, 0)
	_amount.tooltip_text = (
		"What every ticked character receives. How much a session is worth is the "
		+ "GM's call, so this is a starting number rather than a rule."
	)
	award_row.add_child(_amount)
	box.add_child(award_row)

	box.add_child(UI.micro("Who was at the table"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 190)
	box.add_child(scroll)
	_list = UI.vbox(UI.GAP_1)
	UI.expand(_list, true, false)
	scroll.add_child(_list)

	box.add_child(UI.rule_line())
	box.add_child(UI.micro("What this session is remembered as"))
	_summary = LineEdit.new()
	_summary.placeholder_text = "Left blank, the log just records that it ended."
	box.add_child(_summary)


## Fill the sheet list and open.
##
## Player characters are ticked and everybody else is not, because awarding a
## night's IP to seventeen mooks is a mistake nobody wants to undo one sheet at
## a time — but the mooks are still listed, since an NPC the party keeps around
## earns alongside them.
func present() -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()

	var session := int(Store.campaign.get("sessions", 0))
	_note.text = (
		"Session %d closes with a restore point, so the evening can be reopened. "
		% maxi(session, 1)
		+ "IP is the one thing the Forge can spend but never grant, and this is where it comes from."
	)

	for entry in Store.characters():
		var character: Dictionary = entry
		var row := UI.hbox(UI.GAP_2)
		var box := CheckBox.new()
		var tags: Array = character.get("tags", [])
		box.button_pressed = tags.has("PC")
		row.add_child(box)
		var name := UI.elide(UI.value(String(character.get("name", "")), 13))
		UI.expand(name, true, false)
		row.add_child(name)
		row.add_child(
			UI.micro(
				"%s · %d IP"
				% [
					String(character.get("role", "")),
					int(character.get("improvement_points", 0)),
				]
			)
		)
		_list.add_child(row)
		_rows.append({"id": String(character.get("id", "")), "box": box})

	if _rows.is_empty():
		_list.add_child(UI.micro("The roster is empty.", UI.MUTED_DIM))

	popup_centered(Vector2i(600, 620))


func _apply() -> void:
	var chosen := PackedStringArray()
	for entry in _rows:
		var row: Dictionary = entry
		if (row["box"] as CheckBox).button_pressed:
			chosen.append(String(row["id"]))

	var amount := int(_amount.value)
	if amount > 0 and not chosen.is_empty():
		Store.award_improvement_points(amount, chosen)
	Store.end_session(_summary.text)
	_summary.text = ""
	finished.emit()
