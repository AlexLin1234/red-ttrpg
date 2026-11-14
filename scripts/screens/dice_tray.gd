class_name DiceTray
extends Control

## A dice tray over whatever screen is up, on D or the header's Dice button.
##
## Every roll the app knew how to make belonged to a rule: an attack, a skill
## check, a Death Save. The table rolls for a hundred things that are none of
## those — a random direction, how many guards, whether the vending machine
## works — and the GM had to reach for physical dice or another window to do it.
##
## It reads table notation, prints the arithmetic longhand like every other roll
## here does, and keeps what was rolled so "what did I get a minute ago" has an
## answer. The parsing and rolling are [Dice]'s; this is the tray.

const QUICK_DICE := [4, 6, 8, 10, 12, 20, 100]
const MAX_HISTORY := 30
const SHOWN_HISTORY := 8

var _rng: Dice.RandomSource = Dice.SeededRandom.new(Time.get_ticks_usec())
var _history: Array[Dictionary] = []
var _error := ""
var _count := 1
var _modifier := 0

var _field: LineEdit
var _result_box: VBoxContainer
var _history_box: VBoxContainer


func _init() -> void:
	name = "DiceTray"
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
	frame.custom_minimum_size = Vector2(640, 0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stack.add_child(frame)

	var column := UI.vbox(UI.GAP_2)
	frame.add_child(UI.margins(column, UI.GAP_4))

	var head := UI.hbox()
	var title := UI.display("Dice tray", 22)
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("Escape to close"))
	column.add_child(head)
	column.add_child(UI.rule_line())

	column.add_child(_build_quick_row())

	var entry := UI.hbox(UI.GAP_2)
	_field = LineEdit.new()
	_field.placeholder_text = "2d6+3 · d10!+14 · 4d6-1d4   (d10! explodes and fumbles)"
	UI.expand(_field, true, false)
	_field.text_submitted.connect(func(text: String) -> void: roll(text))
	entry.add_child(_field)
	var go := UI.primary_button("Roll")
	go.custom_minimum_size.x = 84
	go.pressed.connect(func() -> void: roll(_field.text))
	entry.add_child(go)
	column.add_child(entry)

	_result_box = UI.vbox(UI.GAP_1)
	column.add_child(_result_box)

	column.add_child(UI.rule_line())
	_history_box = UI.vbox(1)
	column.add_child(_history_box)


## One click per die: how many, which, and what to add.
func _build_quick_row() -> Control:
	var row := UI.hbox(UI.GAP_2)

	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 20
	count.value = _count
	count.suffix = "×"
	count.tooltip_text = "How many dice a button below rolls"
	count.custom_minimum_size.x = 78
	count.value_changed.connect(func(value: float) -> void: _count = int(value))
	row.add_child(count)

	var dice := UI.hbox(1)
	UI.expand(dice, true, false)
	for sides in QUICK_DICE:
		var button := UI.plain_button("d%d" % sides)
		UI.expand(button, true, false)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: roll(_quick_notation("d%d" % sides)))
		dice.add_child(button)
	var check := UI.plain_button("Check")
	check.tooltip_text = "A Cyberpunk RED check die: d10, a 10 explodes and a 1 fumbles"
	check.focus_mode = Control.FOCUS_NONE
	UI.expand(check, true, false)
	check.pressed.connect(func() -> void: roll(_quick_notation("d10!")))
	dice.add_child(check)
	row.add_child(dice)

	var modifier := SpinBox.new()
	modifier.min_value = -99
	modifier.max_value = 99
	modifier.value = _modifier
	modifier.prefix = "Mod"
	modifier.tooltip_text = "Added to every roll made from a button"
	modifier.custom_minimum_size.x = 96
	modifier.value_changed.connect(func(value: float) -> void: _modifier = int(value))
	row.add_child(modifier)
	return row


func _quick_notation(die: String) -> String:
	var text := "%d%s" % [_count, die]
	if _modifier > 0:
		text += "+%d" % _modifier
	elif _modifier < 0:
		text += "-%d" % absi(_modifier)
	return text


func open() -> void:
	visible = true
	_error = ""
	_render()
	_field.grab_focus()


func close() -> void:
	visible = false
	_field.release_focus()


## Swap the dice, so a test can script what comes up.
func set_rng(rng: Dice.RandomSource) -> void:
	_rng = rng


## Roll [param notation] and put it at the top of the tray. Public so a button,
## the field and a test all go through the same door.
func roll(notation: String) -> Dictionary:
	var result := Dice.roll_notation(notation, _rng)
	if bool(result.get("ok", false)):
		_error = ""
		_history.push_front(result)
		if _history.size() > MAX_HISTORY:
			_history.resize(MAX_HISTORY)
		_field.text = String(result["text"]).replace("−", "-").replace(" ", "")
		_field.caret_column = _field.text.length()
	else:
		_error = String(result.get("error", "That could not be rolled."))
	_render()
	return result


func history() -> Array[Dictionary]:
	return _history


func latest() -> Dictionary:
	return _history[0] if not _history.is_empty() else {}


## Write the latest roll into the session log, for the rolls that mattered.
func log_latest() -> bool:
	var result := latest()
	if result.is_empty() or not Store.is_open():
		return false
	var logged := Store.log_line("Rolled %s" % String(result["breakdown"]))
	if logged:
		Store.set_status("Roll logged")
	return logged


func _render() -> void:
	for child in _result_box.get_children():
		child.queue_free()
	for child in _history_box.get_children():
		child.queue_free()

	if _error != "":
		_result_box.add_child(UI.body(_error, 13, UI.ALERT_BRIGHT))

	var result := latest()
	if result.is_empty():
		if _error == "":
			_result_box.add_child(
				UI.micro("Click a die, or type what to roll and press Enter.", UI.MUTED_DIM)
			)
		_history_box.add_child(UI.micro("Nothing rolled yet.", UI.MUTED_DIM))
		return

	var line := UI.hbox(UI.GAP_4)
	var colour := UI.TEXT_DISPLAY
	var tag := ""
	if bool(result["critical"]):
		colour = UI.AMBER
		tag = "Critical · the 10 exploded"
	elif bool(result["fumble"]):
		colour = UI.ALERT_BRIGHT
		tag = "Fumble · the 1 rolled down"
	var total := UI.display(str(int(result["total"])), 54, colour)
	total.custom_minimum_size.x = 110
	line.add_child(total)

	var detail := UI.vbox(2)
	UI.expand(detail, true, false)
	detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail.add_child(UI.micro(String(result["text"]), UI.ACCENT))
	var breakdown := UI.body(String(result["breakdown"]), 13)
	breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(breakdown)
	if tag != "":
		detail.add_child(UI.micro(tag, colour))
	line.add_child(detail)

	var side := UI.vbox(UI.GAP_1)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var again := UI.plain_button("Roll again")
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void: roll(String(result["text"]).replace("−", "-")))
	side.add_child(again)
	var keep := UI.plain_button("Log it")
	keep.focus_mode = Control.FOCUS_NONE
	keep.disabled = not Store.is_open()
	keep.tooltip_text = (
		"Write this roll into the session log"
		if Store.is_open()
		else "Open a campaign to log rolls"
	)
	keep.pressed.connect(
		func() -> void:
			if log_latest():
				keep.disabled = true
				keep.text = UI._letterspace("LOGGED")
	)
	side.add_child(keep)
	line.add_child(side)
	_result_box.add_child(line)

	var head := UI.hbox()
	var label := UI.micro("Earlier")
	UI.expand(label, true, false)
	head.add_child(label)
	head.add_child(UI.micro("%d rolled" % _history.size(), UI.MUTED_DIM))
	_history_box.add_child(head)
	if _history.size() == 1:
		_history_box.add_child(UI.micro("This was the first.", UI.MUTED_DIM))
	for index in range(1, mini(_history.size(), SHOWN_HISTORY + 1)):
		var past: Dictionary = _history[index]
		var row := UI.hbox(UI.GAP_3)
		var past_total := UI.value(str(int(past["total"])), 13, UI.ACCENT)
		past_total.custom_minimum_size.x = 44
		past_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(past_total)
		var past_text := UI.elide(UI.body(String(past["breakdown"]), 12, UI.MUTED))
		UI.expand(past_text, true, false)
		row.add_child(past_text)
		_history_box.add_child(row)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
