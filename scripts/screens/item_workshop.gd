extends Control

## Global item browser and variant workshop, available before opening a save.

var _selected_id := ""
var _list: VBoxContainer
var _detail: VBoxContainer
var _name: LineEdit
var _description: TextEdit
var _price: SpinBox
var _primary_stat: SpinBox
var _bonus: SpinBox
var _message := ""


func _ready() -> void:
	var row := UI.hbox(UI.GAP_3)
	add_child(UI.fill_margins(row, UI.GAP_3))
	row.add_child(_build_browser())
	var panel := UI.panel()
	UI.expand(panel)
	_detail = UI.vbox(UI.GAP_2)
	panel.add_child(UI.margins(_detail, UI.GAP_4))
	row.add_child(panel)
	var catalog := ItemDB.catalog()
	if not catalog.is_empty():
		_selected_id = String(catalog[0]["id"])
	_rebuild()


func _build_browser() -> Control:
	var panel := UI.panel()
	panel.custom_minimum_size = Vector2(320, 0)
	var column := UI.vbox(0)
	panel.add_child(column)
	column.add_child(UI.margins(UI.display("Item Workshop", 22), UI.GAP_3))
	column.add_child(UI.rule_line())
	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = UI.vbox(1)
	UI.expand(_list, true, false)
	scroll.add_child(UI.margins(_list, UI.GAP_2))
	return panel


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	for entry in ItemDB.catalog():
		var button := UI.tab_button(String(entry["name"]), String(entry["id"]) == _selected_id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select.bind(String(entry["id"])))
		_list.add_child(button)
	for child in _detail.get_children():
		child.queue_free()
	var item := ItemDB.find_item(_selected_id)
	if item.is_empty():
		_detail.add_child(UI.micro("Select an item."))
		return
	_detail.add_child(UI.micro("Global item database · %s" % String(item["kind"])))
	_detail.add_child(UI.display(String(item["name"]), 30))
	var prose := UI.body(String(item.get("description", "No description.")), 13, UI.MUTED)
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prose.clip_text = false
	_detail.add_child(prose)
	_detail.add_child(UI.value("%deb" % int(item.get("price", 0)), 16))
	if item.has("weapon"):
		var profile: Dictionary = item["weapon"]
		_detail.add_child(
			UI.value(
				"%dd6 %+d damage · ROF %d · magazine %d"
				% [profile.get("damage_dice", 0), profile.get("damage_bonus", 0), profile.get("rof", 1), profile.get("magazine", 1)],
				13,
			)
		)
	elif item.has("armor"):
		_detail.add_child(UI.value("SP %d" % int((item["armor"] as Dictionary).get("sp", 0)), 13))
	elif String(item.get("kind", "")) == "cyberware":
		_detail.add_child(UI.value("%d Humanity loss" % int(item.get("humanity_cost", 0)), 13))
	_detail.add_child(UI.rule_line())
	_detail.add_child(UI.micro("Create a variation"))
	_name = LineEdit.new()
	_name.text = "%s (Custom)" % item["name"]
	_detail.add_child(_labeled("Name", _name))
	_description = TextEdit.new()
	_description.text = String(item.get("description", ""))
	_description.custom_minimum_size = Vector2(0, 70)
	_detail.add_child(_labeled("Description", _description))
	_price = _spin(int(item.get("price", 0)), 0, 100000)
	_detail.add_child(_labeled("Price (eb)", _price))
	_primary_stat = null
	_bonus = null
	if item.has("weapon"):
		var weapon: Dictionary = item["weapon"]
		_primary_stat = _spin(int(weapon.get("damage_dice", 1)), 1, 20)
		_detail.add_child(_labeled("Damage dice (d6)", _primary_stat))
		_bonus = _spin(int(weapon.get("damage_bonus", 0)), -20, 50)
		_detail.add_child(_labeled("Flat damage bonus", _bonus))
	elif item.has("armor"):
		_primary_stat = _spin(int((item["armor"] as Dictionary).get("sp", 0)), 0, 30)
		_detail.add_child(_labeled("Stopping Power", _primary_stat))
	elif String(item.get("kind", "")) == "cyberware":
		_primary_stat = _spin(int(item.get("humanity_cost", 0)), 0, 50)
		_detail.add_child(_labeled("Humanity loss", _primary_stat))
	var create := UI.primary_button("Create item variation")
	create.pressed.connect(_create.bind(item))
	_detail.add_child(create)
	if _message != "":
		_detail.add_child(UI.body(_message, 12, UI.GOOD if _message.begins_with("Created") else UI.ALERT_BRIGHT))


func _select(item_id: String) -> void:
	_selected_id = item_id
	_message = ""
	_rebuild()


func _create(base: Dictionary) -> void:
	var changes := {"name": _name.text.strip_edges(), "description": _description.text, "price": int(_price.value)}
	if changes["name"] == "":
		_message = "Give the variation a name."
		_rebuild()
		return
	if base.has("weapon"):
		changes["weapon"] = {"damage_dice": int(_primary_stat.value), "damage_bonus": int(_bonus.value)}
	elif base.has("armor"):
		var armor: Dictionary = (base["armor"] as Dictionary).duplicate(true)
		armor["sp"] = int(_primary_stat.value)
		changes["armor"] = armor
	elif String(base.get("kind", "")) == "cyberware":
		changes["humanity_cost"] = int(_primary_stat.value)
	var result := ItemDB.create_variant(String(base["id"]), changes)
	if bool(result.get("ok", false)):
		_selected_id = String((result["item"] as Dictionary)["id"])
		_message = "Created %s in the global item database." % (result["item"] as Dictionary)["name"]
	else:
		_message = String(result.get("error", "Could not create item."))
	_rebuild()


func _spin(value: int, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	return spin


func _labeled(label_text: String, control: Control) -> Control:
	var row := UI.hbox(UI.GAP_3)
	var label := UI.micro(label_text)
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	UI.expand(control, true, false)
	row.add_child(control)
	return row
