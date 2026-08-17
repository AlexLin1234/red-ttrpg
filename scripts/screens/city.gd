extends Control

## Screen placeholder — built next.

func _ready() -> void:
	var box := UI.vbox()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)
	box.add_child(UI.micro("City screen"))
