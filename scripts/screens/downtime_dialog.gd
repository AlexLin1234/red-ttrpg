class_name DowntimeDialog
extends ConfirmationDialog

## The downtime actions a week off is actually for.
##
## Its own class rather than another two hundred lines of city.gd: the clock
## lives on the City screen, so the button belongs there, but nothing about the
## dialog needs the map beside it.
##
## Every action is driven off [constant Downtime.ACTIONS] rather than hard-coded
## here, so a new one appears in this dialog by being added to the rules.

signal performed(action_key: String, result: Dictionary)

var _action := "facedown"
var _actor_id := ""
var _opponent_id := ""
var _medic_id := ""
var _item_id := ""
var _days := 3
var _weeks := 1

var _tabs: HBoxContainer
var _form: VBoxContainer
var _summary: Label


func _init() -> void:
	title = "Downtime"
	get_ok_button().text = "Do it"
	var column := UI.vbox(UI.GAP_3)
	add_child(UI.margins(column, UI.GAP_4))

	_tabs = UI.hbox(1)
	column.add_child(_tabs)
	column.add_child(UI.rule_line())
	_form = UI.vbox(UI.GAP_3)
	column.add_child(_form)
	_summary = UI.body("", 12, UI.MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)
	confirmed.connect(_confirm)


## Open on a given action, rebuilt from the campaign as it stands right now.
func open(action_key := "") -> void:
	if action_key != "":
		_action = action_key
	_rebuild()
	popup_centered(Vector2i(620, 470))


func _rebuild() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for entry in Downtime.ACTIONS:
		var action: Dictionary = entry
		var key := String(action["key"])
		var button := UI.tab_button(String(action["label"]), key == _action)
		UI.expand(button, true, false)
		button.pressed.connect(
			func() -> void:
				_action = key
				_rebuild()
		)
		_tabs.add_child(button)

	for child in _form.get_children():
		child.queue_free()

	var characters := Store.characters()
	if characters.is_empty():
		_summary.text = "This campaign has no characters yet."
		get_ok_button().disabled = true
		return
	if _actor_id == "":
		_actor_id = String((characters[0] as Dictionary)["id"])

	_form.add_child(_character_picker("Who", _actor_id, func(id: String) -> void: _actor_id = id))

	match _action:
		"facedown":
			if _opponent_id == "":
				_opponent_id = String(
					(characters[mini(1, characters.size() - 1)] as Dictionary)["id"]
				)
			_form.add_child(
				_character_picker(
					"Against", _opponent_id, func(id: String) -> void: _opponent_id = id
				)
			)
		"recover":
			_form.add_child(
				_number_row("Days of rest", _days, 1, 30, func(value: int) -> void: _days = value)
			)
			_form.add_child(
				_character_picker(
					"Attended by",
					_medic_id,
					func(id: String) -> void: _medic_id = id,
					"Nobody — just rest"
				)
			)
		"therapy":
			_form.add_child(
				_number_row("Weeks", _weeks, 1, 12, func(value: int) -> void: _weeks = value)
			)
		"fabricate":
			_form.add_child(_item_picker())

	_summary.text = String(Downtime.action(_action).get("summary", ""))
	get_ok_button().disabled = false
	get_ok_button().text = String(Downtime.action(_action).get("label", "Do it"))


func _character_picker(
	label: String, selected_id: String, on_pick: Callable, blank := ""
) -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(UI.micro(label))
	var picker := OptionButton.new()
	picker.clip_text = true
	var ids: Array[String] = []
	if blank != "":
		picker.add_item(blank)
		ids.append("")
	for entry in Store.characters():
		var character: Dictionary = entry
		picker.add_item(
			"%s · %s" % [String(character["name"]), String(character.get("role", "—"))]
		)
		ids.append(String(character["id"]))
	for index in ids.size():
		if ids[index] == selected_id:
			picker.selected = index
	picker.item_selected.connect(func(index: int) -> void: on_pick.call(ids[index]))
	box.add_child(picker)
	return box


func _number_row(label: String, value: int, low: int, high: int, on_change: Callable) -> Control:
	var row := UI.hbox(UI.GAP_2)
	var caption := UI.micro(label)
	UI.expand(caption, true, false)
	row.add_child(caption)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	spin.custom_minimum_size = Vector2(96, 0)
	spin.value_changed.connect(func(next: float) -> void: on_change.call(int(next)))
	row.add_child(spin)
	return row


func _item_picker() -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(UI.micro("What to build"))
	var picker := OptionButton.new()
	picker.clip_text = true
	var catalog := ItemDB.catalog()
	for index in catalog.size():
		var item: Dictionary = catalog[index]
		picker.add_item("%s · %deb" % [String(item["name"]), int(item.get("price", 0))])
		picker.set_item_metadata(index, String(item["id"]))
		if String(item["id"]) == _item_id:
			picker.selected = index
	if catalog.is_empty():
		picker.add_item("No item catalog loaded")
		picker.disabled = true
	elif _item_id == "":
		_item_id = String((catalog[0] as Dictionary)["id"])
	picker.item_selected.connect(
		func(index: int) -> void: _item_id = String(picker.get_item_metadata(index))
	)
	box.add_child(picker)
	return box


## Run whatever the dialog is currently set to. Public so the screenshot runner
## and the smoke test drive the GM's own path.
func perform() -> Dictionary:
	var params := {"character_id": _actor_id}
	match _action:
		"facedown":
			params["opponent_id"] = _opponent_id
		"recover":
			params["days"] = _days
			params["medic_id"] = _medic_id
		"therapy":
			params["weeks"] = _weeks
		"fabricate":
			params["item"] = ItemDB.find_item(_item_id)
	var result := Store.perform_downtime(
		_action, params, Dice.SeededRandom.new(Time.get_ticks_usec())
	)
	if not bool(result.get("ok", false)):
		Store.set_status(String(result.get("error", "Downtime failed")))
	else:
		Store.set_status(String(result.get("work", "Downtime done")))
	performed.emit(_action, result)
	return result


func _confirm() -> void:
	perform()
