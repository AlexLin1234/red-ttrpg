class_name Toasts
extends Control

## What just happened, said where it can be seen.
##
## The status line is one word-width of green in a corner, and a Hustle result
## or a refused save arrived there and was replaced by the next thing before
## anyone read it. A toast rises in the corner of the screen being looked at,
## stays a few seconds, and stacks if three things happen at once.

const LIFETIME := 4.0
const MAX_SHOWN := 4
const WIDTH := 380.0

## The words that mean something went wrong, so the toast can say so in red
## without every caller having to pass a tone.
const BAD_WORDS: PackedStringArray = [
	"could not", "failed", "refused", "cannot", "not enough", "error", "nobody",
]

var _stack: VBoxContainer


func _init() -> void:
	name = "Toasts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_stack = VBoxContainer.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", 6)
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_right = -14.0
	_stack.offset_bottom = -40.0
	_stack.offset_left = -14.0 - WIDTH
	add_child(_stack)


static func tone_of(message: String) -> String:
	var lowered := message.to_lower()
	for word in BAD_WORDS:
		if lowered.contains(word):
			return "bad"
	return "good"


## How many toasts are up. For the screen runner.
func count() -> int:
	var alive := 0
	for child in _stack.get_children():
		if not child.is_queued_for_deletion():
			alive += 1
	return alive


func push(message: String, tone := "") -> void:
	var text := message.strip_edges()
	if text == "":
		return
	if tone == "":
		tone = tone_of(text)
	while count() >= MAX_SHOWN:
		for child in _stack.get_children():
			if not child.is_queued_for_deletion():
				child.queue_free()
				break

	var colour := UI.ALERT_BRIGHT if tone == "bad" else UI.GOOD
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(WIDTH, 0)
	var box := UI.chamfer(UI.PANEL_RAISED, Color(colour, 0.7), 1, 0, UI.CUT_TILE, Chrome.CUT_DIAGONAL)
	box.bg_top = UI.PANEL_RAISED.lightened(0.05)
	box.edge = colour
	box.edge_length = 40.0
	box.glow = colour
	box.glow_strength = 1.2
	card.add_theme_stylebox_override("panel", box)

	var row := UI.hbox(UI.GAP_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := UI.mark(Chrome.Mark.Kind.DIAMOND, colour, 9.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var label := UI.body(text, 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 70.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var wrap := UI.margins(row, UI.GAP_3)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wrap)
	_stack.add_child(card)

	Fx.fade_in(card, Fx.SETTLE)
	var timer := card.create_tween()
	timer.tween_interval(LIFETIME)
	if Fx.enabled():
		timer.tween_property(card, "modulate:a", 0.0, 0.3)
	timer.tween_callback(card.queue_free)
