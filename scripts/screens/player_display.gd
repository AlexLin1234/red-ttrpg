extends Control

## The player-facing board.
##
## Lives in its own native OS window, meant for the second monitor or the TV the
## table is looking at. It is deliberately dumb: it draws the payload [PlayerView]
## hands it and reads nothing from [Store], so there is no route by which a GM
## note, an unrevealed unit or an enemy's exact HP arrives here by accident.
##
## Read at three metres rather than fifty centimetres, so everything on it is
## bigger than the console's equivalent and there is far less of it.

var _board: IsoBoard
var _viewport: SubViewport
var _payload: Dictionary = {}
var _board_signature := ""

var _title_label: Label
var _round_label: Label
var _initiative_box: VBoxContainer
var _headline_box: VBoxContainer
var _standby: Control


func _ready() -> void:
	name = "PlayerDisplay"
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = UI.BG_DEEP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_4))

	column.add_child(_build_header())

	var body := UI.hbox(UI.GAP_3)
	UI.expand(body)
	column.add_child(body)
	body.add_child(_build_stage())
	body.add_child(_build_rail())

	_standby = _build_standby()
	add_child(_standby)

	present(_payload)


func _build_header() -> Control:
	var row := UI.hbox(UI.GAP_4)
	_title_label = UI.display("", 30)
	UI.expand(_title_label, true, false)
	row.add_child(UI.elide(_title_label))
	_round_label = UI.display("", 30, UI.ACCENT)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_round_label)
	return row


func _build_stage() -> Control:
	var frame := UI.panel(UI.PANEL_INSET)
	UI.expand(frame)

	var container := SubViewportContainer.new()
	container.stretch = true
	UI.expand(container)
	# Nothing here is clickable: the GM drives, the table watches.
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)

	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	container.add_child(_viewport)

	frame.add_child(UI.reticle())

	_board = IsoBoard.new()
	_viewport.add_child(_board)
	return frame


func _build_rail() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(340, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)
	column.add_child(UI.margins(UI.micro("Turn order"), UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	column.add_child(scroll)
	_initiative_box = UI.vbox(UI.GAP_1)
	UI.expand(_initiative_box, true, false)
	var wrapper := UI.margins(_initiative_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	_headline_box = UI.vbox(UI.GAP_1)
	_headline_box.custom_minimum_size = Vector2(0, 150)
	column.add_child(UI.margins(_headline_box, UI.GAP_3))
	return shell


## What the room sees between encounters: the app's name and nothing else.
func _build_standby() -> Control:
	var cover := ColorRect.new()
	cover.color = UI.BG_DEEP
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := UI.vbox(UI.GAP_2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_child(box)
	var mark := UI.display("REDLINE", 44, UI.ACCENT_DIM)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mark)
	var caption := UI.micro("Standby", UI.MUTED_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	return cover


## Draw a payload from [method PlayerView.compose]. An empty one blanks the
## window rather than leaving the last fight on the TV.
func present(payload: Dictionary) -> void:
	_payload = payload
	if not is_node_ready():
		return
	_standby.visible = payload.is_empty()
	if payload.is_empty():
		return

	_title_label.text = String(payload.get("title", "")).to_upper()
	var round_number := int(payload.get("round", 0))
	_round_label.text = "ROUND %d" % round_number if round_number > 0 else "SETUP"

	_refresh_board(payload)
	_refresh_initiative(payload)
	_refresh_headline(payload)


func _refresh_board(payload: Dictionary) -> void:
	var board: Dictionary = payload.get("board", {})
	if board.is_empty():
		return
	# Rebuilding the deck every refresh would restart the tile mesh on every
	# shot fired, so it happens only when the terrain itself changed.
	var signature := (
		"%s/%d/%d"
		% [
			String(board.get("id", "")),
			(board.get("tiles", []) as Array).size(),
			(board.get("props", []) as Array).size(),
		]
	)
	if signature != _board_signature:
		_board.set_location(board, board.get("covers", []))
		_board_signature = signature
	_board.set_units(payload.get("units", []), payload.get("visuals", {}))


func _refresh_initiative(payload: Dictionary) -> void:
	for child in _initiative_box.get_children():
		child.queue_free()
	var order: Array = payload.get("initiative", [])
	if order.is_empty():
		_initiative_box.add_child(UI.body("Not rolled yet.", 16, UI.MUTED))
		return
	for row in order:
		_initiative_box.add_child(_build_row(row))


func _build_row(entry: Dictionary) -> Control:
	var current := bool(entry.get("current", false))
	var panel := UI.panel(UI.PANEL_RAISED if current else UI.PANEL_INSET, UI.HAIRLINE)
	if current:
		panel.add_theme_stylebox_override("panel", UI.flat(UI.PANEL_RAISED, UI.ACCENT, 2))

	var row := UI.hbox(UI.GAP_3)
	panel.add_child(UI.margins(row, UI.GAP_2))

	var score := UI.display(str(int(entry.get("score", 0))), 24, UI.ACCENT)
	score.custom_minimum_size = Vector2(44, 0)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(score)

	var text := UI.vbox(1)
	UI.expand(text, true, false)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var side := String(entry.get("side", "neutral"))
	var name_color: Color = IsoBoard.SIDE_COLORS.get(side, UI.TEXT)
	text.add_child(UI.elide(UI.value(String(entry.get("name", "")), 18, name_color)))
	text.add_child(UI.elide(UI.micro(String(entry.get("condition", "")))))
	return panel


func _refresh_headline(payload: Dictionary) -> void:
	for child in _headline_box.get_children():
		child.queue_free()
	var headline: Dictionary = payload.get("headline", {})
	if headline.is_empty():
		return

	var tone := UI.TEXT_DISPLAY
	match String(headline.get("tone", "")):
		"miss":
			tone = UI.MUTED
		"hit":
			tone = UI.ALERT_BRIGHT
	_headline_box.add_child(UI.display(String(headline.get("title", "")), 32, tone))

	var attacker := String(headline.get("attacker", ""))
	var target := String(headline.get("target", ""))
	var weapon := String(headline.get("weapon", ""))
	if attacker != "":
		var summary := attacker
		if target != "":
			summary += " → " + target
		if weapon != "":
			summary += " · " + weapon
		var label := UI.body(summary, 15, UI.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_headline_box.add_child(label)

	for line in headline.get("lines", []):
		_headline_box.add_child(UI.body(String(line), 13, UI.MUTED_DIM))
