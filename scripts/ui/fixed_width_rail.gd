class_name FixedWidthRail
extends Container

## A side rail whose contents cannot change the width it asks of its parent.
##
## The map screen puts this beside the map in an HBox, so every pixel the rail
## claims as a minimum is taken from the map. Letting a hovered zone or place
## widen the rail rescales the map, slides the polygon out from under the
## pointer, clears the hover and starts a flicker loop.
##
## This has to be a bare Container. The engine's own container types compute
## their minimum size in C++ and never consult a script's _get_minimum_size(),
## so overriding it on a PanelContainer silently does nothing -- the rail goes
## on reporting its widest label. Container has no such override, so the clamp
## can report a fixed width and lay its single child out by hand.

const WIDTH := 320.0


func _init() -> void:
	clip_contents = true


func _get_minimum_size() -> Vector2:
	return Vector2(WIDTH, 0)


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for child in get_children():
		fit_child_in_rect(child as Control, Rect2(Vector2.ZERO, size))
