extends Control

## The private GM window: notes and beats, and the tools that go with them.
##
## Everything here is in the one window the table never sees, which is the
## reason it is here. A Perception roll made for the whole party is only worth
## making if the party does not watch it being made, and a clock counting down
## to the corp's response team is not something to put on the stream.

const NotesBeatsScreen := preload("res://scripts/screens/notes_beats.gd")

const TABS := [
	{"id": "notes", "label": "Notes / Beats"},
	{"id": "party", "label": "Party"},
	{"id": "clocks", "label": "Clocks"},
	{"id": "generators", "label": "Generators"},
]
const LOOT_BUDGETS := [100, 500, 1000, 5000]

var _tab := "notes"
var _tab_buttons: Dictionary = {}
var _notes: Control
var _tool_shell: Control
var _tool_body: VBoxContainer
var _rng: Dice.RandomSource = Dice.SeededRandom.new(Time.get_ticks_usec())

var _check_skill := "Perception"
var _check_modifier := 0
var _check_dv := 13
var _check: Dictionary = {}

var _clock_name := ""
var _clock_segments := 6

var _npc: Dictionary = {}
var _npc_added := false
var _loot: Dictionary = {}
var _loot_budget := 500
var _loot_given := ""


func _ready() -> void:
	var column := UI.vbox(0)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var strip := UI.hbox(1)
	for entry in TABS:
		var id := String(entry["id"])
		var button := UI.tab_button(String(entry["label"]), id == _tab)
		button.pressed.connect(set_tab.bind(id))
		strip.add_child(button)
		_tab_buttons[id] = button
	var note := UI.micro("Private · never drawn on the player display", UI.MUTED_DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(note)
	var strip_wrap := UI.margins(strip, UI.GAP_3)
	strip_wrap.add_theme_constant_override("margin_bottom", 0)
	column.add_child(strip_wrap)

	var stack := Control.new()
	UI.expand(stack)
	column.add_child(stack)

	_notes = NotesBeatsScreen.new()
	_notes.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_notes)

	_tool_shell = UI.fill_margins(UI.panel(), UI.GAP_3)
	_tool_shell.visible = false
	stack.add_child(_tool_shell)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	(_tool_shell.get_child(0) as Control).add_child(UI.margins(scroll, UI.GAP_4))
	_tool_body = UI.vbox(UI.GAP_3)
	UI.expand(_tool_body, true, false)
	scroll.add_child(_tool_body)

	Store.campaign_changed.connect(_on_campaign_changed)


## Public so a test opens a tab the way a click does.
func set_tab(id: String) -> void:
	_tab = id
	for key in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == id
	_notes.visible = id == "notes"
	_tool_shell.visible = id != "notes"
	_render()


## HP moves on the board and cash moves in the Market while this window sits
## open beside them, so the party board follows the campaign rather than
## showing what was true when the tab was clicked.
func _on_campaign_changed() -> void:
	if is_inside_tree() and _tab == "party" and _tool_shell.visible:
		_render()


func _render() -> void:
	for child in _tool_body.get_children():
		child.queue_free()
	match _tab:
		"party":
			_render_party()
		"clocks":
			_render_clocks()
		"generators":
			_render_generators()


func _title(kicker: String, text: String, blurb: String) -> void:
	_tool_body.add_child(UI.micro(kicker))
	_tool_body.add_child(UI.display(text, 26))
	var line := UI.body(blurb, 12, UI.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_body.add_child(line)
	_tool_body.add_child(UI.rule_line())


# -- party -----------------------------------------------------------------------


func _render_party() -> void:
	_title(
		"GM tools · the table at a glance",
		"Party",
		"Every player character in the numbers asked for mid-scene, and a roll made for all of them at once without anyone being told to pick up dice."
	)
	var rows := GMTools.party_overview(Store.characters())
	if rows.is_empty():
		_tool_body.add_child(UI.micro("No player characters on the roster yet."))
		return

	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", UI.GAP_4)
	grid.add_theme_constant_override("v_separation", UI.GAP_2)
	for heading in ["Character", "HP", "", "Condition", "SP head / body", "Humanity", "Luck", "Cash", "IP · Rep"]:
		grid.add_child(UI.micro(heading))
	for row in rows:
		var hurt := String(row["wound_state"]) != Mortality.UNHURT
		var name_box := UI.vbox(0)
		name_box.add_child(UI.value(String(row["name"]), 14))
		name_box.add_child(UI.micro(String(row["role"])))
		grid.add_child(name_box)
		grid.add_child(UI.value("%d / %d" % [row["hp"], row["max_hp"]], 14, UI.WARN if hurt else UI.TEXT))
		var bar := UI.hp_bar(float(row["hp"]) / maxf(1.0, float(row["max_hp"])), 150)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		grid.add_child(UI.micro(String(row["wound_label"]), UI.WARN if hurt else UI.GOOD))
		grid.add_child(UI.value("%d / %d" % [row["head_sp"], row["body_sp"]], 13))
		grid.add_child(UI.value("%d / %d" % [row["humanity"], row["max_humanity"]], 13))
		grid.add_child(
			UI.value(
				"%d / %d" % [row["luck"], row["luck_pool"]],
				13,
				UI.MUTED if int(row["luck"]) == 0 else UI.TEXT
			)
		)
		grid.add_child(UI.value("%d eb" % int(row["cash"]), 13, UI.AMBER))
		grid.add_child(UI.value("%d · %d" % [row["ip"], row["reputation"]], 13))
	_tool_body.add_child(grid)

	var luck := UI.plain_button("Refresh the party's Luck")
	luck.tooltip_text = "Fill every player character's Luck pool, as the start of a session does"
	luck.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	luck.pressed.connect(
		func() -> void:
			Store.refresh_party_luck()
			_render()
	)
	_tool_body.add_child(luck)

	_tool_body.add_child(UI.rule_line())
	_tool_body.add_child(UI.micro("Secret group check"))
	var controls := UI.hbox(UI.GAP_2)
	var skill := OptionButton.new()
	skill.custom_minimum_size.x = 260
	var names := GMTools.skill_names()
	for index in names.size():
		skill.add_item(names[index])
		if names[index] == _check_skill:
			skill.select(index)
	skill.item_selected.connect(func(index: int) -> void: _check_skill = names[index])
	controls.add_child(skill)
	var modifier := SpinBox.new()
	modifier.min_value = -20
	modifier.max_value = 20
	modifier.value = _check_modifier
	modifier.prefix = "Mod"
	modifier.value_changed.connect(func(value: float) -> void: _check_modifier = int(value))
	controls.add_child(modifier)
	var dv := SpinBox.new()
	dv.min_value = 0
	dv.max_value = 40
	dv.value = _check_dv
	dv.prefix = "DV"
	dv.tooltip_text = "0 rolls without a target and just ranks the party"
	dv.value_changed.connect(func(value: float) -> void: _check_dv = int(value))
	controls.add_child(dv)
	var roll := UI.primary_button("Roll for everyone")
	roll.pressed.connect(
		func() -> void:
			modifier.apply()
			dv.apply()
			roll_group_check(_check_skill, _check_modifier, _check_dv)
	)
	controls.add_child(roll)
	_tool_body.add_child(controls)

	if _check.is_empty():
		_tool_body.add_child(
			UI.micro("Nothing rolled. Someone without the skill rolls the bare stat.", UI.MUTED_DIM)
		)
		return
	if not bool(_check.get("ok", false)):
		_tool_body.add_child(UI.body(String(_check.get("error", "")), 13, UI.ALERT_BRIGHT))
		return
	_tool_body.add_child(UI.value(String(_check["summary"]), 15, UI.ACCENT))
	for entry in _check["results"]:
		var result: Dictionary = entry
		var line := UI.hbox(UI.GAP_3)
		var total := UI.display(str(int(result["total"])), 20)
		total.custom_minimum_size.x = 44
		line.add_child(total)
		var who := UI.value(String(result["name"]), 13)
		who.custom_minimum_size.x = 190
		line.add_child(who)
		var verdict := ""
		var colour := UI.MUTED
		if result["success"] != null:
			verdict = "Success" if bool(result["success"]) else "Fail"
			colour = UI.GOOD if bool(result["success"]) else UI.ALERT_BRIGHT
		if bool(result["critical"]):
			verdict += " · exploded"
		elif bool(result["fumble"]):
			verdict += " · fumbled"
		var mark := UI.micro(verdict.trim_prefix(" · "), colour)
		mark.custom_minimum_size.x = 150
		line.add_child(mark)
		var text := String(result["text"])
		if not bool(result["trained"]):
			text += "  (untrained)"
		line.add_child(UI.body(text, 12, UI.MUTED))
		_tool_body.add_child(line)


func roll_group_check(skill: String, modifier: int, dv: int) -> Dictionary:
	_check = GMTools.group_check(Store.characters(), skill, modifier, dv, _rng)
	_render()
	return _check


# -- clocks ----------------------------------------------------------------------


func _render_clocks() -> void:
	_title(
		"GM tools · what is coming",
		"Clocks",
		"A name for something on its way and a number of ticks until it arrives: the response team, the bomb, the rival crew getting there first. Saved with the campaign, and logged the moment one fills."
	)
	var maker := UI.hbox(UI.GAP_2)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "What is counting down?  e.g. Arasaka response team"
	name_field.text = _clock_name
	UI.expand(name_field, true, false)
	name_field.text_changed.connect(func(text: String) -> void: _clock_name = text)
	maker.add_child(name_field)
	var segments := SpinBox.new()
	segments.min_value = GMTools.CLOCK_MIN_SEGMENTS
	segments.max_value = GMTools.CLOCK_MAX_SEGMENTS
	segments.value = _clock_segments
	segments.suffix = " ticks"
	segments.value_changed.connect(func(value: float) -> void: _clock_segments = int(value))
	maker.add_child(segments)
	var add := UI.primary_button("+ Start clock")
	var start := func() -> void:
		segments.apply()
		add_clock(_clock_name, _clock_segments)
	add.pressed.connect(start)
	name_field.text_submitted.connect(func(_text: String) -> void: start.call())
	maker.add_child(add)
	_tool_body.add_child(maker)

	var clocks := Store.clocks()
	if clocks.is_empty():
		_tool_body.add_child(UI.micro("No clocks running.", UI.MUTED_DIM))
		return
	for entry in clocks:
		_tool_body.add_child(_clock_row(entry))


func _clock_row(clock: Dictionary) -> Control:
	var id := String(clock["id"])
	var filled := int(clock["filled"])
	var total := int(clock["segments"])
	var full := filled >= total
	var card := UI.panel(UI.PANEL_INSET)
	var row := UI.hbox(UI.GAP_3)
	card.add_child(UI.margins(row, UI.GAP_3))

	var text := UI.vbox(2)
	text.custom_minimum_size.x = 300
	text.add_child(UI.elide(UI.value(String(clock["name"]), 15, UI.ALERT_BRIGHT if full else UI.TEXT)))
	text.add_child(UI.micro("It is here" if full else "%d of %d" % [filled, total], UI.ALERT_BRIGHT if full else UI.MUTED))
	row.add_child(text)

	# Segments rather than a bar: a clock is read by counting what is left.
	var pips := UI.hbox(3)
	UI.expand(pips, true, false)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for index in total:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(0, 18)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lit := index < filled
		var colour := UI.PANEL_RAISED
		if lit:
			colour = UI.ALERT if full else UI.AMBER_FILL
		pip.add_theme_stylebox_override("panel", UI.flat(colour, UI.RULE, 1, 0))
		pips.add_child(pip)
	row.add_child(pips)

	var back := UI.plain_button("−")
	back.custom_minimum_size.x = 40
	back.disabled = filled <= 0
	back.pressed.connect(tick_clock.bind(id, -1))
	row.add_child(back)
	var forward := UI.primary_button("Tick +1")
	forward.disabled = full
	forward.pressed.connect(tick_clock.bind(id, 1))
	row.add_child(forward)
	var drop := UI.plain_button("Remove")
	drop.pressed.connect(
		func() -> void:
			Store.remove_clock(id)
			_render()
	)
	row.add_child(drop)
	return card


func add_clock(clock_name: String, segments: int) -> Dictionary:
	var clock := Store.add_clock(clock_name, segments)
	_clock_name = ""
	_render()
	return clock


func tick_clock(id: String, delta: int) -> void:
	Store.tick_clock(id, delta)
	_render()


# -- generators ------------------------------------------------------------------


func _render_generators() -> void:
	_title(
		"GM tools · on the spot",
		"Generators",
		"For the person nobody planned and the pockets nobody stocked. Homebrew tables; roll again until one fits."
	)

	var npc_head := UI.hbox(UI.GAP_2)
	var npc_label := UI.micro("Someone the party just met")
	UI.expand(npc_label, true, false)
	npc_head.add_child(npc_label)
	var roll_person := UI.primary_button("Roll a person")
	roll_person.pressed.connect(roll_npc)
	npc_head.add_child(roll_person)
	_tool_body.add_child(npc_head)

	if _npc.is_empty():
		_tool_body.add_child(UI.micro("Nobody yet.", UI.MUTED_DIM))
	else:
		var card := UI.panel(UI.PANEL_INSET)
		var box := UI.vbox(UI.GAP_1)
		card.add_child(UI.margins(box, UI.GAP_3))
		box.add_child(UI.display(String(_npc["name"]), 22))
		box.add_child(UI.micro(String(_npc["job"]), UI.ACCENT))
		for pair in [
			["You notice", _npc["look"]],
			["Wants", _npc["wants"]],
			["Habit", _npc["quirk"]],
			["Secret", _npc["secret"]],
		]:
			var said := String(pair[1])
			box.add_child(UI.field_row(String(pair[0]), said.substr(0, 1).to_upper() + said.substr(1)))
		var actions := UI.hbox(UI.GAP_2)
		var keep := UI.plain_button("Added to roster" if _npc_added else "Add to roster")
		keep.disabled = _npc_added
		keep.tooltip_text = "Give them a sheet, so they can be placed on a board"
		keep.pressed.connect(add_npc_to_roster)
		actions.add_child(keep)
		var copy := UI.plain_button("Copy")
		copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(String(_npc["text"])))
		actions.add_child(copy)
		box.add_child(actions)
		_tool_body.add_child(card)

	_tool_body.add_child(UI.rule_line())
	var loot_head := UI.hbox(UI.GAP_2)
	var loot_label := UI.micro("What they were carrying")
	UI.expand(loot_label, true, false)
	loot_head.add_child(loot_label)
	var budgets := UI.hbox(1)
	for budget in LOOT_BUDGETS:
		var choice := UI.tab_button("≤ %d eb" % budget, budget == _loot_budget)
		choice.pressed.connect(
			func() -> void:
				_loot_budget = budget
				_render()
		)
		budgets.add_child(choice)
	loot_head.add_child(budgets)
	var roll_bag := UI.primary_button("Roll loot")
	roll_bag.pressed.connect(func() -> void: roll_loot(_loot_budget))
	loot_head.add_child(roll_bag)
	_tool_body.add_child(loot_head)

	if _loot.is_empty():
		_tool_body.add_child(UI.micro("Nothing yet.", UI.MUTED_DIM))
		return
	var bag := UI.panel(UI.PANEL_INSET)
	var contents := UI.vbox(UI.GAP_1)
	bag.add_child(UI.margins(contents, UI.GAP_3))
	contents.add_child(UI.field_row("Loose cash", "%d eb" % int(_loot["cash"]), UI.AMBER))
	for entry in _loot["items"]:
		var item: Dictionary = entry
		contents.add_child(UI.field_row(String(item["name"]), "%d eb" % int(item["price"])))
	contents.add_child(UI.hairline())
	contents.add_child(UI.field_row("Worth", "%d eb" % int(_loot["worth"]), UI.ACCENT))

	var give := UI.hbox(UI.GAP_2)
	var taker := OptionButton.new()
	taker.custom_minimum_size.x = 240
	for entry in GMTools.party_overview(Store.characters()):
		taker.add_item(String(entry["name"]))
		taker.set_item_metadata(taker.item_count - 1, String(entry["id"]))
	give.add_child(taker)
	var hand := UI.plain_button("Given to %s" % _loot_given if _loot_given != "" else "Give it to them")
	hand.disabled = _loot_given != "" or taker.item_count == 0
	hand.pressed.connect(
		func() -> void:
			if taker.selected >= 0:
				give_loot(String(taker.get_item_metadata(taker.selected)))
	)
	give.add_child(hand)
	contents.add_child(give)
	_tool_body.add_child(bag)


func roll_npc() -> Dictionary:
	_npc = GMTools.roll_npc(_rng)
	_npc_added = false
	_render()
	return _npc


func add_npc_to_roster() -> Dictionary:
	if _npc.is_empty() or _npc_added:
		return {}
	var sheet := GMTools.npc_sheet(_npc, _rng)
	Store.add_character(sheet)
	Store.log_line("Met %s, %s." % [_npc["name"], _npc["job"]])
	Store.set_status("%s added to the roster" % String(_npc["name"]))
	_npc_added = true
	_render()
	return sheet


func roll_loot(budget: int) -> Dictionary:
	_loot_budget = budget
	_loot = GMTools.roll_loot(ItemDB.catalog(), budget, _rng)
	_loot_given = ""
	_render()
	return _loot


func give_loot(character_id: String) -> bool:
	var character := Store.character_by_id(character_id)
	var result := GMTools.give_loot(character, _loot)
	if not bool(result.get("ok", false)):
		return false
	_loot_given = String(result["name"])
	Store.log_line("%s picked up %s." % [_loot_given, String(_loot["text"])])
	Store.set_status("Loot given to %s" % _loot_given)
	_render()
	return true
