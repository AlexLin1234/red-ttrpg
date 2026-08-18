extends Control

## Campaign-level market screen. The full and Fixer-limited versions share the
## same external ItemDB catalog and purchase flow.

var night := false
var _body: VBoxContainer
var _message := ""


func _ready() -> void:
	var panel := UI.panel()
	add_child(UI.fill_margins(panel, UI.GAP_3))
	_body = UI.vbox(UI.GAP_2)
	panel.add_child(_body)
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	var character := Store.active_character()
	if character.is_empty():
		_body.add_child(UI.micro("No character selected. Choose one in Forge."))
		return
	var head := UI.hbox(UI.GAP_3)
	var title := UI.display("Night Market" if night else "Market", 28)
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.value("%s · %deb" % [character["name"], int(character.get("cash", 0))], 14))
	_body.add_child(head)
	var catalog := ItemDB.catalog()
	var stock: Array[Dictionary] = GearMarket.night_market(character, catalog) if night else catalog
	if night and String(character.get("role_key", "")) != "fixer":
		_body.add_child(UI.body("The selected character must be a Fixer to source Night Market stock.", 12, UI.WARN))
		return
	_body.add_child(
		UI.micro(
			"%s · %s"
			% [
				(
					"Operator-limited stock from the global item database."
					if night
					else "Every item in the global item database."
				),
				ItemDB.source_label(),
			]
		)
	)
	if _message != "":
		_body.add_child(UI.body(_message, 12, UI.GOOD if _message.begins_with("Bought") else UI.ALERT_BRIGHT))
	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := UI.vbox(UI.GAP_1)
	UI.expand(list, true, false)
	scroll.add_child(list)
	for product in stock:
		var row := UI.hbox(UI.GAP_3)
		var description := UI.vbox(1)
		UI.expand(description, true, false)
		description.add_child(UI.body(String(product["name"]), 13))
		description.add_child(UI.micro("%s · %s" % [product["kind"], product.get("description", "")]))
		row.add_child(description)
		row.add_child(UI.value("%deb" % int(product["price"]), 12))
		var buy := UI.primary_button("Buy")
		buy.disabled = int(character.get("cash", 0)) < int(product["price"])
		buy.pressed.connect(_buy.bind(String(product["id"])))
		row.add_child(buy)
		list.add_child(UI.margins(row, UI.GAP_2))
		list.add_child(UI.rule_line())


func _buy(item_id: String) -> void:
	var result := GearMarket.buy(Store.active_character(), ItemDB.catalog(), item_id)
	if bool(result.get("ok", false)):
		_message = "Bought %s for %deb." % [result["item"], result["price"]]
		Store.mark_dirty()
	else:
		_message = String(result.get("error", "Purchase failed."))
	_rebuild()
