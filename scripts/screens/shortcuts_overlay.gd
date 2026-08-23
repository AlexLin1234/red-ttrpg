class_name ShortcutsOverlay
extends Control

## The keys, and how big everything is.
##
## Redline's shortcuts were number keys bound in the app shell with nothing
## anywhere that said so, and the theme's font sizes were constants. Both are
## the same question — how do I work this thing — so both are here, on `?`.

const SCALE_STEPS: Array[float] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

var _rows: Array[Dictionary] = []
var _body: VBoxContainer


func _init() -> void:
	name = "ShortcutsOverlay"
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
	frame.custom_minimum_size = Vector2(640, 0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_child(frame)

	_body = UI.vbox(UI.GAP_2)
	frame.add_child(UI.margins(_body, UI.GAP_4))


## [param rows] is the app's own shortcut table, so this cannot drift from what
## the keys actually do.
func present(rows: Array[Dictionary]) -> void:
	_rows = rows
	visible = true
	_render()


func close() -> void:
	visible = false


func _render() -> void:
	for child in _body.get_children():
		child.queue_free()

	var head := UI.hbox()
	var title := UI.display("Keys & display", 22)
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("? or Escape to close"))
	_body.add_child(head)
	_body.add_child(UI.rule_line())

	for entry in _rows:
		var shortcut: Dictionary = entry
		var line := UI.hbox(UI.GAP_3)
		var keys := UI.value(String(shortcut["keys"]), 12, UI.ACCENT)
		keys.custom_minimum_size = Vector2(150, 0)
		line.add_child(keys)
		var what := UI.elide(UI.body(String(shortcut["does"]), 12))
		UI.expand(what, true, false)
		line.add_child(what)
		_body.add_child(line)

	_body.add_child(UI.rule_line())
	_body.add_child(UI.micro("Display"))
	_body.add_child(_scale_row())
	_body.add_child(_motion_row())


## Scale, in steps rather than on a slider: a console read across a table wants
## a size that was chosen, not one that was dragged past.
func _scale_row() -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(
		UI.field_row("Interface size", "%d%%" % roundi(AppSettings.ui_scale() * 100.0), UI.ACCENT)
	)
	var row := UI.hbox(1)
	for step in SCALE_STEPS:
		var button := UI.tab_button(
			"%d%%" % roundi(step * 100.0), is_equal_approx(step, AppSettings.ui_scale())
		)
		UI.expand(button, true, false)
		button.pressed.connect(
			func() -> void:
				AppSettings.set_value("ui_scale", step)
				AppSettings.apply(get_tree())
				_render()
		)
		row.add_child(button)
	box.add_child(row)
	return box


func _motion_row() -> Control:
	var button := UI.tab_button("Reduce motion", AppSettings.reduce_motion())
	button.tooltip_text = "Skip the tracer, the impact flash and the blast shell"
	button.pressed.connect(
		func() -> void:
			AppSettings.set_value("reduce_motion", button.button_pressed)
			_render()
	)
	return button


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE or key.keycode == KEY_QUESTION or key.keycode == KEY_F1:
		close()
		get_viewport().set_input_as_handled()
