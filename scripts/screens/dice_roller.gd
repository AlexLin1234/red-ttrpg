class_name DiceRoller
extends Control

## Rolling the things no rule covers.
##
## Every other roll in Redline is welded to a mechanic — a check, a damage roll,
## a Hustle — and each is better for it. But a table also rolls for how many
## guards are on the door, how far somebody falls, which way the courier ran,
## and a GM who has to reach past the app for that has left the app.
##
## Two ways to roll, because a GM wants both. An expression, which is arithmetic
## and says what it did. And the house d10, which is the check the rest of the
## rules are made of: it explodes upward on a 10 and fumbles downward on a 1,
## and having it one key away means a ruling made on the spot uses the same
## curve as a ruling made through a sheet.

## Rolls kept on screen. Enough to answer "what did that come up as" twice ago,
## short enough that the panel does not become a log.
const HISTORY := 12

## What the field offers before anything has been typed into it.
const PRESETS: PackedStringArray = ["1d6", "2d6", "1d10", "2d10", "1d100", "3d6+2"]

var _expression: LineEdit
var _error: Label
var _history: VBoxContainer
var _rolls: Array[Dictionary] = []
var _modifier: SpinBox


func _init() -> void:
	name = "DiceRoller"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.06, 0.08, 0.82)
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
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)

	var frame := UI.panel(UI.PANEL)
	frame.custom_minimum_size = Vector2(560, 0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(frame)

	var body := UI.vbox(UI.GAP_2)
	frame.add_child(UI.margins(body, UI.GAP_4))
	_build(body)


func _build(body: VBoxContainer) -> void:
	var head := UI.hbox()
	var title := UI.display("Dice", 22)
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("Ctrl + D or Escape to close"))
	body.add_child(head)
	body.add_child(UI.rule_line())

	_expression = LineEdit.new()
	_expression.placeholder_text = "2d6+3"
	_expression.text_submitted.connect(func(_text: String) -> void: _roll_expression())
	_expression.text_changed.connect(func(_text: String) -> void: _clear_error())
	body.add_child(_expression)

	var presets := UI.hbox(1)
	for preset in PRESETS:
		var button := UI.plain_button(preset)
		UI.expand(button, true, false)
		var text := preset
		button.pressed.connect(
			func() -> void:
				_expression.text = text
				_roll_expression()
		)
		presets.add_child(button)
	body.add_child(presets)

	var roll := UI.primary_button("Roll")
	roll.pressed.connect(_roll_expression)
	body.add_child(roll)

	_error = UI.body("", 12, UI.ALERT_BRIGHT)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.clip_text = false
	_error.visible = false
	body.add_child(_error)

	body.add_child(UI.rule_line())
	body.add_child(UI.micro("The house d10 · explodes on 10, fumbles on 1"))
	var check_row := UI.hbox(UI.GAP_2)
	_modifier = SpinBox.new()
	_modifier.min_value = -50
	_modifier.max_value = 50
	_modifier.value = 0
	_modifier.prefix = "Mod "
	_modifier.custom_minimum_size = Vector2(110, 0)
	check_row.add_child(_modifier)
	var check := UI.plain_button("Roll a check")
	check.tooltip_text = (
		"The same d10 every skill check in the app rolls, for a ruling made on the spot."
	)
	UI.expand(check, true, false)
	check.pressed.connect(_roll_check)
	check_row.add_child(check)
	body.add_child(check_row)

	body.add_child(UI.rule_line())
	_history = UI.vbox(UI.GAP_1)
	body.add_child(_history)


func open() -> void:
	visible = true
	_clear_error()
	_expression.grab_focus()
	_expression.select_all()
	_render_history()


func close() -> void:
	visible = false


func _clear_error() -> void:
	_error.visible = false
	_error.text = ""


func _show_error(message: String) -> void:
	_error.text = message
	_error.visible = true


## Roll whatever is in the field.
##
## A refusal is a sentence rather than a silent zero: a roller that reads "2d"
## as 2 has quietly answered a different question than the one that was asked.
func _roll_expression() -> void:
	var result := Dice.evaluate(_expression.text, Dice.SeededRandom.new(randi()))
	if not bool(result.get("ok", false)):
		_show_error(String(result.get("error", "That is not a roll.")))
		return
	_clear_error()
	_record(
		"%s" % _expression.text.strip_edges(),
		int(result["total"]),
		String(result["detail"]),
	)


func _roll_check() -> void:
	var modifier := int(_modifier.value)
	var rolled := Dice.roll_check(Dice.SeededRandom.new(randi()))
	var faces := PackedStringArray()
	for face in rolled["rolls"]:
		faces.append(str(face))
	var detail := "d10 [%s]" % ", ".join(faces)
	if modifier != 0:
		detail += " %+d" % modifier
	_record("Check", int(rolled["total"]) + modifier, detail)


func _record(label: String, total: int, detail: String) -> void:
	_rolls.push_front({"label": label, "total": total, "detail": detail})
	while _rolls.size() > HISTORY:
		_rolls.pop_back()
	_render_history()


func _render_history() -> void:
	for child in _history.get_children():
		child.queue_free()
	if _rolls.is_empty():
		_history.add_child(UI.micro("Nothing rolled yet.", UI.MUTED_DIM))
		return
	for index in _rolls.size():
		var entry: Dictionary = _rolls[index]
		var line := UI.hbox(UI.GAP_2)
		# The newest roll is the one being read out, so it is the one that is lit.
		var fresh := index == 0
		line.add_child(
			UI.mark(Chrome.Mark.Kind.DIAMOND, UI.AMBER if fresh else UI.MUTED_DIM, 9.0)
		)
		var total := UI.display(str(int(entry["total"])), 20 if fresh else 15)
		total.custom_minimum_size.x = 58
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(total)
		var detail := UI.elide(
			UI.body(String(entry["detail"]), 12, UI.TEXT if fresh else UI.MUTED)
		)
		UI.expand(detail, true, false)
		line.add_child(detail)
		_history.add_child(line)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE or (key.ctrl_pressed and key.keycode == KEY_D):
		close()
		get_viewport().set_input_as_handled()
