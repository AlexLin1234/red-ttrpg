extends Control

## Campaign-level market screen. The open market and the Fixer's Night Market
## share the same external ItemDB catalog and purchase flow.
##
## The Night Market is generated rather than filtered: it is an event a Rank 5+
## Fixer organizes, so its stock is rolled once and held in campaign state.
## Every character therefore visits the same event, including after a save/load.

const SORTS := [
	{"id": "shelf", "label": "Shelf order"},
	{"id": "price_up", "label": "Price · low first"},
	{"id": "price_down", "label": "Price · high first"},
	{"id": "name", "label": "Name"},
]

var night := false
var _body: VBoxContainer
var _message := ""
## The stalls currently on screen. A Night Market is a rolled snapshot held in
## campaign state, so a purchase must resolve against what the GM is looking at
## rather than against today's ItemDB, which may no longer hold those ids.
var _stock: Array[Dictionary] = []

## What the shelf is narrowed to. Held on the screen rather than rebuilt with
## it, so buying the third thing a search found does not clear the search.
var _mode := "buy"
var _query := ""
var _kind := ""
var _affordable_only := false
var _sort := "shelf"

var _list: VBoxContainer
var _scroll: ScrollContainer
var _purse: Label
var _message_label: Label
var _count_label: Label
var _mode_buttons: Dictionary = {}
## The controls that narrow a shelf and mean nothing to a bag of six things.
var _buy_only: Array[Control] = []


func _ready() -> void:
	var panel := UI.panel()
	add_child(UI.fill_margins(panel, UI.GAP_3))
	_body = UI.vbox(UI.GAP_2)
	panel.add_child(UI.margins(_body, UI.GAP_3))
	_rebuild()


## Catch up in place when the GM comes back, instead of being thrown away and
## rebuilt: cash and inventory may have moved, the filters should not.
func on_shown() -> void:
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
	_list = null
	var character := Store.active_character()
	if character.is_empty():
		_body.add_child(UI.micro("Nobody on the roster yet. Add a character in the Forge."))
		return

	var head := UI.hbox(UI.GAP_3)
	var title := UI.display("Night Market" if night else "Market", 28)
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(_shopper_picker(character))
	_purse = UI.value("", 16, UI.AMBER)
	_purse.custom_minimum_size.x = 110
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_purse)
	_body.add_child(head)

	_stock = []
	var stock: Array[Dictionary] = []
	var closed := ""
	if night:
		_roll_night_market(character)
		var shared := Store.night_market()
		if shared.is_empty():
			closed = _message
			if closed == "":
				closed = (
					"No Night Market is open. A Fixer with Operator Rank 5+ can "
					+ "organize one for everybody."
				)
		else:
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
				reroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	_stock = stock

	# A closed Night Market has nothing to buy, but what is in the bag can
	# still be sold: the closed notice replaces the shelf, not the screen.
	if closed != "":
		_body.add_child(_wrapped(closed, UI.WARN))
		_mode = "sell"

	_body.add_child(_build_toolbar(closed == ""))

	_message_label = _wrapped("", UI.GOOD)
	_body.add_child(_message_label)

	_scroll = ScrollContainer.new()
	UI.expand(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_list = UI.vbox(UI.GAP_1)
	UI.expand(_list, true, false)
	_scroll.add_child(_list)

	_refresh_list()


## Who is shopping. This used to say "choose one in Forge", three screens away
## from the shelf the GM was standing at.
func _shopper_picker(character: Dictionary) -> Control:
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 240
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.tooltip_text = "Who is buying and selling"
	var ordered: Array = Store.characters().duplicate()
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_pc := String(a.get("kind", "")) == "pc"
			var b_pc := String(b.get("kind", "")) == "pc"
			return a_pc and not b_pc
	)
	for entry in ordered:
		var shopper: Dictionary = entry
		picker.add_item("%s · %s" % [shopper["name"], shopper.get("role", "")])
		picker.set_item_metadata(picker.item_count - 1, String(shopper["id"]))
		if String(shopper["id"]) == String(character["id"]):
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(
		func(index: int) -> void:
			Store.active_character_id = String(picker.get_item_metadata(index))
			_message = ""
			_rebuild()
	)
	return picker


## Buy or sell, and the four ways of narrowing sixty rows to the one wanted.
func _build_toolbar(can_buy: bool) -> Control:
	var box := UI.vbox(UI.GAP_2)
	_buy_only.clear()

	var top := UI.hbox(UI.GAP_3)
	var modes := UI.hbox(1)
	_mode_buttons.clear()
	for mode in ["buy", "sell"]:
		var button := UI.tab_button(mode, _mode == mode)
		button.custom_minimum_size.x = 84
		button.disabled = mode == "buy" and not can_buy
		button.pressed.connect(
			func() -> void:
				_mode = mode
				_message = ""
				for id in _mode_buttons:
					(_mode_buttons[id] as Button).button_pressed = id == _mode
				_refresh_list()
		)
		_mode_buttons[mode] = button
		modes.add_child(button)
	top.add_child(modes)

	var search := LineEdit.new()
	search.placeholder_text = "Search by name, kind or description…"
	search.text = _query
	search.clear_button_enabled = true
	UI.expand(search, true, false)
	search.text_changed.connect(
		func(text: String) -> void:
			_query = text
			_refresh_list()
	)
	top.add_child(search)

	var affordable := UI.tab_button("Can afford", _affordable_only)
	affordable.tooltip_text = "Hide what this character cannot pay for"
	affordable.pressed.connect(
		func() -> void:
			_affordable_only = affordable.button_pressed
			_refresh_list()
	)
	top.add_child(affordable)
	_buy_only.append(affordable)

	var sort := OptionButton.new()
	sort.custom_minimum_size.x = 170
	for index in SORTS.size():
		sort.add_item(String(SORTS[index]["label"]))
		if String(SORTS[index]["id"]) == _sort:
			sort.select(index)
	sort.item_selected.connect(
		func(index: int) -> void:
			_sort = String(SORTS[index]["id"])
			_refresh_list()
	)
	top.add_child(sort)
	_buy_only.append(sort)
	box.add_child(top)

	# One tab per kind actually on the shelf, so a Night Market that rolled
	# three categories offers three, not eleven with eight of them empty.
	var kinds := UI.hbox(1)
	var seen := PackedStringArray()
	for product in _stock:
		var kind := String(product.get("kind", ""))
		if kind != "" and not seen.has(kind):
			seen.append(kind)
	if not seen.has(_kind):
		_kind = ""
	var kind_buttons: Dictionary = {}
	for kind in [""] + Array(seen):
		var button := UI.tab_button("All" if kind == "" else String(kind), _kind == kind)
		button.pressed.connect(
			func() -> void:
				_kind = kind
				for id in kind_buttons:
					(kind_buttons[id] as Button).button_pressed = id == _kind
				_refresh_list()
		)
		kind_buttons[kind] = button
		kinds.add_child(button)
		_buy_only.append(button)
	var spacer := Control.new()
	UI.expand(spacer, true, false)
	kinds.add_child(spacer)
	_count_label = UI.micro("")
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kinds.add_child(_count_label)
	box.add_child(kinds)
	box.add_child(UI.rule_line())
	return box


## The rows a search, a kind, a budget and a sort leave. Public so the screen
## runner can check the filters by what they return rather than by pixels.
func visible_stock() -> Array[Dictionary]:
	var character := Store.active_character()
	var cash := int(character.get("cash", 0))
	var needle := _query.strip_edges().to_lower()
	var rows: Array[Dictionary] = []
	for product in _stock:
		if _kind != "" and String(product.get("kind", "")) != _kind:
			continue
		if _affordable_only and int(product.get("price", 0)) > cash:
			continue
		if needle != "":
			var hay := (
				"%s %s %s"
				% [product.get("name", ""), product.get("kind", ""), product.get("description", "")]
			).to_lower()
			if not hay.contains(needle):
				continue
		rows.append(product)
	match _sort:
		"price_up":
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["price"]) < int(b["price"]))
		"price_down":
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["price"]) > int(b["price"]))
		"name":
			rows.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
			)
	return rows


func set_filter(query: String, kind := "", affordable_only := false, sort := "shelf") -> void:
	_query = query
	_kind = kind
	_affordable_only = affordable_only
	_sort = sort
	_rebuild()


func set_mode(mode: String) -> void:
	_mode = mode
	_rebuild()


## Redraw the rows and the purse, and nothing else: the search field keeps its
## focus while it is typed in, and the list keeps its scroll position when
## something half-way down it is bought.
func _refresh_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var character := Store.active_character()
	_purse.text = "%s eb" % _thousands(int(character.get("cash", 0)))
	_message_label.text = _message
	_message_label.visible = _message != ""
	_message_label.add_theme_color_override(
		"font_color",
		UI.GOOD if _message.begins_with("Bought") or _message.begins_with("Sold") else UI.ALERT_BRIGHT
	)

	for control in _buy_only:
		control.visible = _mode != "sell"
	if _mode == "sell":
		_fill_sell_rows(character)
		return

	var rows := visible_stock()
	_count_label.text = UI._letterspace(("%d of %d items" % [rows.size(), _stock.size()]).to_upper())
	if _stock.is_empty():
		_list.add_child(UI.micro("Nothing on the shelves."))
		return
	if rows.is_empty():
		_list.add_child(
			_wrapped("Nothing on the shelves matches. Clear the search or pick another kind.", UI.MUTED)
		)
		return
	for product in rows:
		_list.add_child(UI.margins(_product_row(character, product), UI.GAP_2))
		_list.add_child(UI.hairline())


func _fill_sell_rows(character: Dictionary) -> void:
	var gear: Array = character.get("gear", [])
	var catalog: Array = ItemDB.catalog()
	_count_label.text = UI._letterspace(("%d carried" % gear.size()).to_upper())
	if gear.is_empty():
		_list.add_child(_wrapped("%s is carrying nothing to sell." % character["name"], UI.MUTED))
		return
	_list.add_child(
		_wrapped(
			"The street pays half of what something cost. Installed cyberware has to come out first.",
			UI.MUTED
		)
	)
	var needle := _query.strip_edges().to_lower()
	for index in gear.size():
		var entry: Dictionary = gear[index]
		var detail := String(entry.get("detail", ""))
		if needle != "" and not (
			("%s %s %s" % [entry.get("name", ""), entry.get("kind", ""), detail]).to_lower().contains(needle)
		):
			continue
		var row := UI.hbox(UI.GAP_3)
		var text := UI.vbox(1)
		UI.expand(text, true, false)
		text.add_child(UI.elide(UI.body(String(entry.get("name", "Item")), 13)))
		var kind := String(entry.get("kind", "gear"))
		text.add_child(UI.elide(UI.micro(kind if detail == "" else "%s · %s" % [kind, detail])))
		row.add_child(text)

		var installed := String(entry.get("installed_on", "")) != ""
		var worth := GearMarket.resale_value(entry, catalog)
		var price := UI.value("%s eb" % _thousands(worth) if worth > 0 else "—", 12)
		price.custom_minimum_size.x = 88
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)

		var sell := UI.plain_button("Sell")
		sell.custom_minimum_size.x = 72
		sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sell.disabled = installed or worth <= 0
		if installed:
			sell.tooltip_text = "Installed — detach it in the Forge's Cyberware tab first"
		elif worth <= 0:
			sell.tooltip_text = "Nobody is buying this"
		sell.pressed.connect(_sell.bind(index))
		row.add_child(sell)
		_list.add_child(UI.margins(row, UI.GAP_2))
		_list.add_child(UI.hairline())


## One stall row. Every column that can hold arbitrary catalog text is elided,
## because a Label's minimum size is its full text: a single long rulebook
## description would otherwise widen the row past the viewport.
func _product_row(character: Dictionary, product: Dictionary) -> HBoxContainer:
	var row := UI.hbox(UI.GAP_3)

	var description := UI.vbox(1)
	UI.expand(description, true, false)
	var name_line := UI.hbox(UI.GAP_3)
	var name_label := UI.body(String(product["name"]), 13)
	name_line.add_child(name_label)
	# The numbers a player actually buys the thing for, beside its name rather
	# than a click away in the Workshop.
	var stats := stat_line(product)
	if stats != "":
		var stat_label := UI.elide(UI.value(stats, 11, UI.ACCENT))
		UI.expand(stat_label, true, false)
		stat_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_line.add_child(stat_label)
	description.add_child(name_line)
	var blurb := UI.elide(UI.micro("%s · %s" % [product["kind"], product.get("description", "")]))
	blurb.tooltip_text = String(product.get("description", ""))
	blurb.mouse_filter = Control.MOUSE_FILTER_PASS
	description.add_child(blurb)
	row.add_child(description)

	var cost := int(product["price"])
	var short := cost - int(character.get("cash", 0))
	var price := UI.value("%s eb" % _thousands(cost), 12, UI.TEXT if short <= 0 else UI.MUTED)
	price.custom_minimum_size.x = 88
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price)

	var buy := UI.primary_button("Buy")
	buy.custom_minimum_size.x = 72
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = short > 0
	if short > 0:
		buy.tooltip_text = "%s eb short" % _thousands(short)
	buy.pressed.connect(_buy.bind(String(product["id"])))
	row.add_child(buy)
	return row


## What an item does, in the numbers the sheet will use.
static func stat_line(product: Dictionary) -> String:
	var parts := PackedStringArray()
	var weapon: Variant = product.get("weapon")
	if weapon is Dictionary:
		var damage := "%dd6" % int(weapon.get("damage_dice", 0))
		var bonus := int(weapon.get("damage_bonus", 0))
		if bonus != 0:
			damage += "%+d" % bonus
		parts.append(damage)
		parts.append("ROF %d" % int(weapon.get("rof", 1)))
		if int(weapon.get("magazine", 0)) > 1:
			parts.append("Mag %d" % int(weapon["magazine"]))
		if int(weapon.get("autofire_rating", -1)) > 0:
			parts.append("Autofire ×%d" % int(weapon["autofire_rating"]))
	var armor: Variant = product.get("armor")
	if armor is Dictionary:
		parts.append("SP %d" % int(armor.get("sp", 0)))
		parts.append(String(armor.get("location", "")).capitalize())
	if product.has("humanity_cost"):
		parts.append("Humanity −%d" % int(product["humanity_cost"]))
		var places: Variant = product.get("body_parts")
		if places is Array and not (places as Array).is_empty():
			parts.append(String((places as Array)[0]).capitalize())
	return " · ".join(parts)


static func _thousands(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out


func _wrapped(text: String, color: Color) -> Label:
	var label := UI.body(text, 12, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.custom_minimum_size.x = 0
	return label


func _buy(item_id: String) -> void:
	var result := GearMarket.buy(Store.active_character(), _stock, item_id)
	if bool(result.get("ok", false)):
		_message = "Bought %s for %s eb." % [result["item"], _thousands(int(result["price"]))]
		Store.mark_dirty()
	else:
		_message = String(result.get("error", "Purchase failed."))
	_refresh_list()


func _sell(gear_index: int) -> void:
	var result := GearMarket.sell(Store.active_character(), ItemDB.catalog(), gear_index)
	if bool(result.get("ok", false)):
		_message = "Sold %s for %s eb." % [result["item"], _thousands(int(result["price"]))]
		Store.mark_dirty()
	else:
		_message = String(result.get("error", "Sale failed."))
	_refresh_list()
