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
		_wrap_text(child)
		fit_child_in_rect(child as Control, Rect2(Vector2.ZERO, size))


## Make every caption placed in the rail wrap instead of running off its edge.
##
## Clipping alone is not enough. A Label or a Button reports its whole caption as
## a minimum width, and Control.set_size never shrinks a control below the
## minimum it asks for, so one long zone name stretches the rail's inner column
## wider than the rail. The column then lays its own contents out at that width,
## and the clamp clips the overhang away: the tail of the name, the right-hand
## clock buttons and the panel edge all vanish off the side of the screen.
## Wrapping drops that minimum to a single word, so the column stays inside the
## rail and a long caption runs onto a second line.
##
## This is done here rather than at each of the rail's two dozen build sites so
## that content added later is covered too. Both setters ignore a value they
## already hold, so re-running it on every sort costs nothing after the first.
func _wrap_text(node: Node) -> void:
	if node is Label:
		var label := node as Label
		# Labels deliberately set to elide (UI.elide) already report no minimum
		# width, and say what they have to say on one line.
		if not label.clip_text and _may_wrap(label):
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif node is OptionButton:
		# A picker is as wide as the item it happens to be showing. Wrapping it
		# would change the height of the row every time a longer option was
		# chosen, so its text is trimmed instead.
		var picker := node as OptionButton
		picker.clip_text = true
		picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif node is Button:
		if _may_wrap(node as Button):
			(node as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in node.get_children():
		_wrap_text(child)


## Whether wrapping this control would leave it anything to wrap into.
##
## A wrapped control asks for no more than one word, and a row hands a child that
## does not expand exactly the width it asks for. Wrapping the short trailing
## caption of a row -- "8 drawn", "Danger 4" -- would therefore squeeze it into a
## column one letter wide while the expanding half of the row kept the space. Such
## captions stay whole; it is the half beside them that gives way.
func _may_wrap(control: Control) -> bool:
	if control.get_parent() is HBoxContainer:
		return control.size_flags_horizontal & SIZE_EXPAND != 0
	return true
