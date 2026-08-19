extends Control

## Campaign-level market screen. The open market and the Fixer's Night Market
## share the same external ItemDB catalog and purchase flow.
##
## The Night Market is generated rather than filtered: it is an event a Rank 5+
## Fixer organizes, so its stock is rolled once and held in campaign state.
## Every character therefore visits the same event, including after a save/load.

var night := false
var _body: VBoxContainer
var _message := ""


func _ready() -> void:
	var panel := UI.panel()
	add_child(UI.fill_margins(panel, UI.GAP_3))
	_body = UI.vbox(UI.GAP_2)
	panel.add_child(_body)
	_rebuild()


func _roll_night_market(character: Dictionary, force := false) -> void:
	if not force and not Store.night_market().is_empty():
		return
	var result := Store.organize_night_market(character, Dice.SeededRandom.new(randi()))
	if not bool(result.get("ok", false)):
		_message = String(result.get("error", "Night Market setup failed."))


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	var character := Store.active_character()
	if character.is_empty():
		_body.add_child(UI.micro("No character selected. Choose one in Forge."))
		return

	var head := UI.hbox(UI.GAP_3)
	var title := UI.display("Night Market" if night else "Market", 28)
	UI.expand(UI.elide(title), true, false)
	head.add_child(title)
	var purse := UI.value(
		"%s · %deb" % [character["name"], int(character.get("cash", 0))], 14
	)
	UI.elide(purse)
	purse.custom_minimum_size.x = 200
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(purse)
	_body.add_child(head)

	var stock: Array[Dictionary] = []
	if night:
		_roll_night_market(character)
		var shared := Store.night_market()
		if shared.is_empty():
			var unavailable := _message
			if unavailable == "":
				unavailable = (
					"No Night Market is open. A Fixer with Operator Rank 5+ can "
					+ "organize one for everybody."
				)
			_body.add_child(_wrapped(unavailable, UI.WARN))
			return
		stock.assign(shared.get("stock", []))
		var categories := PackedStringArray(shared.get("categories", []))
		var summary := "%s · organized by %s · every price category up to Super Luxury" % [
			", ".join(categories), shared.get("organizer_name", "a Fixer")
		]
		if bool(shared.get("midnight", false)):
			summary += " · Midnight Market seated"
		_body.add_child(_wrapped(summary, UI.MUTED))
		var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
		if String(character.get("role_key", "")) == "fixer" and rank >= (
			GearMarket.NIGHT_MARKET_MINIMUM_RANK
		):
			var reroll := UI.plain_button("Organize a new Night Market")
			reroll.pressed.connect(
				func() -> void:
					_roll_night_market(Store.active_character(), true)
					_message = ""
					_rebuild()
			)
			_body.add_child(reroll)
	else:
		stock = ItemDB.catalog()
		var note := "Every item in the global item database. %s" % ItemDB.source_label()
		if String(character.get("role_key", "")) == "fixer":
			var rank := int((character.get("role_ability", {}) as Dictionary).get("rank", 0))
			note += (
				" · Operator Reach sources up to %deb piece by piece."
				% GearMarket.reach_ceiling(rank)
			)
		_body.add_child(_wrapped(note, UI.MUTED))

	if _message != "":
		_body.add_child(
			_wrapped(_message, UI.GOOD if _message.begins_with("Bought") else UI.ALERT_BRIGHT)
		)

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := UI.vbox(UI.GAP_1)
	UI.expand(list, true, false)
	scroll.add_child(list)

	if stock.is_empty():
		list.add_child(UI.micro("Nothing on the shelves."))
		return

	for product in stock:
		list.add_child(UI.margins(_product_row(character, product), UI.GAP_2))
		list.add_child(UI.rule_line())


## One stall row. Every column that can hold arbitrary catalog text is elided,
## because a Label's minimum size is its full text: a single long rulebook
## description would otherwise widen the row past the viewport.
func _product_row(character: Dictionary, product: Dictionary) -> HBoxContainer:
	var row := UI.hbox(UI.GAP_3)

	var description := UI.vbox(1)
	UI.expand(description, true, false)
	description.add_child(UI.elide(UI.body(String(product["name"]), 13)))
	description.add_child(
		UI.elide(UI.micro("%s · %s" % [product["kind"], product.get("description", "")]))
	)
	row.add_child(description)

	var price := UI.value("%deb" % int(product["price"]), 12)
	price.custom_minimum_size.x = 88
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	var buy := UI.primary_button("Buy")
	buy.custom_minimum_size.x = 72
	buy.disabled = int(character.get("cash", 0)) < int(product["price"])
	buy.pressed.connect(_buy.bind(String(product["id"])))
	row.add_child(buy)
	return row


func _wrapped(text: String, color: Color) -> Label:
	var label := UI.body(text, 12, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.custom_minimum_size.x = 0
	return label


func _buy(item_id: String) -> void:
	var result := GearMarket.buy(Store.active_character(), ItemDB.catalog(), item_id)
	if bool(result.get("ok", false)):
		_message = "Bought %s for %deb." % [result["item"], result["price"]]
		Store.mark_dirty()
	else:
		_message = String(result.get("error", "Purchase failed."))
	_rebuild()
