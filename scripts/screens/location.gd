extends Control

## Screen 1C — the isometric location.
##
## Build the scene from the palette, roll initiative, then fight. Every attack
## prints its arithmetic longhand, and cover in the line of fire is a question
## put to the GM rather than a decision the app makes quietly.

const BLAST_RADIUS_M := 6.0
const BLAST_DICE := 6

const TOOLS := [
	{"id": "select", "label": "Select", "hint": "Click a unit to inspect it"},
	{"id": "move", "label": "Move", "hint": "Click a unit, then click a cell"},
	{"id": "fire", "label": "Fire", "hint": "Click a target"},
	{"id": "aimed", "label": "Aimed", "hint": "Called shot at −8 DV"},
	{"id": "autofire", "label": "Autofire", "hint": "Ten rounds, multiplier by margin"},
	{"id": "blast", "label": "Blast", "hint": "Click a cell to detonate"},
]

var _encounter: Encounter
var _snapshot: Dictionary = {}
var _board: IsoBoard
var _viewport: SubViewport
var _tool := "select"
var _palette_tab := "units"
var _selected_unit := ""
var _hover_cell: Dictionary = {}
var _message := "Roll initiative to begin the round."
var _drag_unit := ""
var _skill_result := "Choose a skill for a check before combat."
var _check_rng := Dice.SeededRandom.new(Time.get_ticks_usec())

var _palette_box: VBoxContainer
var _initiative_box: VBoxContainer
var _selected_box: VBoxContainer
var _card_box: VBoxContainer
var _tool_buttons: Dictionary = {}
var _hint_label: Label
var _header_label: Label
var _undo_button: Button
var _end_turn_button: Button


func _ready() -> void:
	var location := Store.active_location()
	if location.is_empty():
		var empty := UI.vbox()
		empty.set_anchors_preset(Control.PRESET_CENTER)
		empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
		empty.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(empty)
		empty.add_child(UI.micro("No location in this campaign yet."))
		return

	_build_encounter(location)

	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_3))
	column.add_child(_build_bar(location))

	var body := UI.hbox(UI.GAP_3)
	UI.expand(body)
	column.add_child(body)

	body.add_child(_build_palette(location))
	body.add_child(_build_stage(location))
	body.add_child(_build_rail())

	_set_tool(_tool)
	_refresh()


func _build_encounter(location: Dictionary) -> void:
	var actors := {}
	for unit in location.get("units", []):
		var entry: Dictionary = unit
		var character := Store.character_by_id(String(entry["character_id"]))
		if not character.is_empty():
			actors[String(entry["id"])] = CampaignFixtures.actor_input(character)
	if actors.is_empty():
		return
	var tables := Tables.new(Store.campaign.get("tables", TablesDefault.document()))
	_encounter = Encounter.new(tables, actors)
	_snapshot = _encounter.snapshot()
	var units: Array = location.get("units", [])
	_selected_unit = String((units[0] as Dictionary)["id"]) if not units.is_empty() else ""


func _build_bar(location: Dictionary) -> Control:
	var bar := UI.hbox(UI.GAP_4)
	var left := UI.micro("%s / %s" % [Store.campaign["city"], location["name"]])
	UI.expand(left, true, false)
	bar.add_child(left)
	_header_label = UI.micro("")
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_header_label)
	return bar


# -- palette ---------------------------------------------------------------------


func _build_palette(location: Dictionary) -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(215, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)

	var tabs := UI.hbox(1)
	for tab in ["tiles", "props", "units"]:
		var button := UI.tab_button(tab, tab == _palette_tab)
		UI.expand(button, true, false)
		button.pressed.connect(
			func() -> void:
				_palette_tab = tab
				_rebuild_palette()
		)
		tabs.add_child(button)
	column.add_child(tabs)

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_palette_box = UI.vbox(1)
	UI.expand(_palette_box, true, false)
	var wrapper := UI.margins(_palette_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	var hint := UI.micro("Click a palette entry, then click the grid.")
	column.add_child(UI.margins(hint, UI.GAP_2))
	column.add_child(UI.rule_line())

	var facts := UI.vbox(0)
	facts.add_child(UI.field_row("Snap", "%d m" % int(location.get("tile_metres", 2))))
	facts.add_child(UI.field_row("Elevation shading", "On"))
	facts.add_child(UI.field_row("Line of sight", "Dynamic"))
	facts.add_child(UI.field_row("Cover prompt", "GM decides"))
	column.add_child(UI.margins(facts, UI.GAP_3))

	_rebuild_palette()
	return shell


var _pending_place: Dictionary = {}


func _rebuild_palette() -> void:
	if _palette_box == null:
		return
	for child in _palette_box.get_children():
		child.queue_free()

	var entries: Array = []
	match _palette_tab:
		"tiles":
			for tile in ["deck", "grate", "rubble", "ramp", "water"]:
				entries.append({"id": tile, "label": tile, "sub": ""})
		"props":
			for cover in Store.cover_palette():
				var entry: Dictionary = cover
				entries.append(
					{
						"id": String(entry["id"]),
						"label": String(entry["name"]),
						"sub": "SP %d · %d HP" % [int(entry["sp"]), int(entry["hp"])],
					}
				)
		"units":
			for character in Store.characters():
				var entry: Dictionary = character
				entries.append(
					{"id": String(entry["id"]), "label": String(entry["name"]), "sub": String(entry["role"])}
				)

	for entry in entries:
		_palette_box.add_child(_build_palette_chip(entry))


func _build_palette_chip(entry: Dictionary) -> Control:
	var id := String(entry["id"])
	var is_armed := (
		not _pending_place.is_empty()
		and String(_pending_place.get("kind", "")) == _palette_tab
		and String(_pending_place.get("id", "")) == id
	)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override(
		"normal", UI.flat(UI.PANEL_INSET, UI.ACCENT if is_armed else UI.HAIRLINE, 1, 6)
	)
	button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_INSET, UI.ACCENT_FILL, 1, 6))
	button.add_theme_stylebox_override("pressed", UI.flat(UI.PANEL_RAISED, UI.ACCENT, 1, 6))
	button.pressed.connect(
		func() -> void:
			_pending_place = {"kind": _palette_tab, "id": id}
			_message = "Placing %s — click the grid." % String(entry["label"])
			_rebuild_palette()
			_refresh_card()
	)

	var row := UI.hbox(UI.GAP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := UI.fill_margins(row, UI.GAP_2)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(wrapper)

	row.add_child(UI.hatch(Vector2(24, 24)))
	var text := UI.vbox(0)
	UI.expand(text, true, false)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	text.add_child(UI.elide(UI.value(String(entry["label"]), 11)))
	if String(entry["sub"]) != "":
		text.add_child(UI.elide(UI.micro(String(entry["sub"]))))
	return button


# -- stage ------------------------------------------------------------------------


func _build_stage(location: Dictionary) -> Control:
	var column := UI.vbox(UI.GAP_2)
	UI.expand(column)

	var frame := UI.panel(UI.PANEL_INSET)
	UI.expand(frame)
	column.add_child(frame)

	var container := SubViewportContainer.new()
	container.stretch = true
	UI.expand(container)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(_on_board_input)
	frame.add_child(container)

	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	container.add_child(_viewport)

	_board = IsoBoard.new()
	_viewport.add_child(_board)
	_board.set_location(location, Store.cover_palette())
	_sync_units()

	var toolbar := UI.panel()
	column.add_child(toolbar)
	var tools := UI.hbox(1)
	toolbar.add_child(UI.margins(tools, UI.GAP_2))
	for tool in TOOLS:
		var entry: Dictionary = tool
		var button := UI.tab_button(String(entry["label"]), String(entry["id"]) == _tool)
		button.pressed.connect(_set_tool.bind(String(entry["id"])))
		tools.add_child(button)
		_tool_buttons[String(entry["id"])] = button
	_hint_label = UI.micro("")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.expand(_hint_label, true, false)
	tools.add_child(_hint_label)

	var card := UI.panel()
	card.custom_minimum_size = Vector2(0, 92)
	column.add_child(card)
	_card_box = UI.vbox(2)
	card.add_child(UI.margins(_card_box, UI.GAP_3))

	return column


func _set_tool(tool_id: String) -> void:
	_tool = tool_id
	_pending_place = {}
	for id in _tool_buttons:
		(_tool_buttons[id] as Button).button_pressed = id == tool_id
	for tool in TOOLS:
		if String((tool as Dictionary)["id"]) == tool_id:
			_hint_label.text = UI._letterspace(String((tool as Dictionary)["hint"]).to_upper())
	if _board != null:
		_board.show_blast_preview({}, BLAST_RADIUS_M)
	_rebuild_palette()


func _on_board_input(event: InputEvent) -> void:
	if _board == null:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var pick := _board.pick(motion.position)
		_hover_cell = pick.get("cell", {}) if not pick.is_empty() else {}
		_board.set_hover_cell(_hover_cell)
		if _drag_unit != "" and _is_setup() and not _hover_cell.is_empty():
			_move_unit(_drag_unit, _hover_cell, false)
		if _tool == "blast":
			_board.show_blast_preview(_hover_cell, BLAST_RADIUS_M)
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			if button.button_index == MOUSE_BUTTON_LEFT and _drag_unit != "":
				_drag_unit = ""
				Store.mark_dirty()
				_message = "Position updated."
				_refresh_card()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_board.set_zoom_delta(-2.0)
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_board.set_zoom_delta(2.0)
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return

		var pick := _board.pick(button.position)
		if pick.is_empty():
			return
		if _is_setup() and _pending_place.is_empty() and String(pick.get("kind", "")) == "unit":
			_drag_unit = String(pick["id"])
		_handle_click(pick)


func _handle_click(pick: Dictionary) -> void:
	var cell: Dictionary = pick.get("cell", {})

	if not _pending_place.is_empty():
		_place(cell)
		return

	if _tool == "blast":
		_detonate(cell)
		return

	if String(pick["kind"]) == "unit":
		var id := String(pick["id"])
		if _tool == "fire":
			begin_attack(id, "single")
		elif _tool == "aimed":
			begin_attack(id, "aimed")
		elif _tool == "autofire":
			begin_attack(id, "autofire")
		else:
			_selected_unit = id
			_refresh()
		return

	if _tool == "move" and _selected_unit != "":
		_move_unit(_selected_unit, cell)


func _place(cell: Dictionary) -> void:
	var location := Store.active_location()
	var kind := String(_pending_place["kind"])
	var id := String(_pending_place["id"])
	_pending_place = {}

	match kind:
		"tiles":
			for tile in location["tiles"]:
				var entry: Dictionary = tile
				if int(entry["x"]) == int(cell["x"]) and int(entry["z"]) == int(cell["z"]):
					return
			(location["tiles"] as Array).append(
				{"x": cell["x"], "z": cell["z"], "layer": cell.get("layer", 0), "tile_id": id, "rotation": 0}
			)
		"props":
			var cover := Store.cover_by_id(id)
			(location["props"] as Array).append(
				{
					"id": "prop-%d" % Time.get_ticks_usec(),
					"cover_id": id,
					"x": cell["x"],
					"z": cell["z"],
					"layer": cell.get("layer", 0),
					"rotation": 0,
					"hp": int(cover.get("hp", 10)),
				}
			)
		"units":
			(location["units"] as Array).append(
				{
					"id": "unit-%d" % Time.get_ticks_usec(),
					"character_id": id,
					"x": cell["x"],
					"z": cell["z"],
					"layer": cell.get("layer", 0),
				}
			)
			_build_encounter(location)

	Store.mark_dirty()
	_board.set_location(location, Store.cover_palette())
	_sync_units()
	_message = "Placed."
	_refresh()


func _move_unit(unit_id: String, cell: Dictionary, commit := true) -> void:
	var location := Store.active_location()
	for unit in location["units"]:
		var entry: Dictionary = unit
		if String(entry["id"]) == unit_id:
			entry["x"] = int(cell["x"])
			entry["z"] = int(cell["z"])
			entry["layer"] = int(cell.get("layer", 0))
	if commit:
		Store.mark_dirty()
	_sync_units()
	if commit:
		_refresh()


func _is_setup() -> bool:
	return int(_snapshot.get("round", 0)) == 0


# -- combat -------------------------------------------------------------------------


## Public entry points, so the screenshot harness drives the same paths the GM
## clicks rather than a parallel test-only route.
func roll_initiative() -> void:
	_encounter.roll_initiative()
	_snapshot = _encounter.snapshot()
	_message = "Initiative rolled."
	_refresh()


func select_unit(unit_id: String) -> void:
	_selected_unit = unit_id
	_refresh()


func unit_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for unit in Store.active_location().get("units", []):
		ids.append(String((unit as Dictionary)["id"]))
	return ids


func has_cover_prompt() -> bool:
	return has_node("CoverPrompt")


## Answer an open cover prompt the way the GM would: "absorb", "penalty" or
## "none".
func answer_cover_prompt(choice: String) -> void:
	var prompt := get_node_or_null("CoverPrompt")
	if prompt == null:
		return
	for button in prompt.find_children("*", "Button", true, false):
		if String((button as Button).get_meta("choice", "")) == choice:
			(button as Button).pressed.emit()
			return


func _unit_cell(unit_id: String) -> Dictionary:
	for unit in Store.active_location().get("units", []):
		var entry: Dictionary = unit
		if String(entry["id"]) == unit_id:
			return {"x": int(entry["x"]), "z": int(entry["z"]), "layer": int(entry.get("layer", 0))}
	return {}


func begin_attack(target_id: String, mode: String) -> void:
	if _encounter == null or _selected_unit == "" or target_id == _selected_unit:
		return
	var from := _unit_cell(_selected_unit)
	var to := _unit_cell(target_id)
	if from.is_empty() or to.is_empty():
		return

	var shot := {
		"attacker": _selected_unit,
		"target": target_id,
		"mode": mode,
		"location": "head" if mode == "aimed" else "body",
		"distance_m": snappedf(_board.distance_m(from, to), 0.1),
	}

	var cover := _board.cover_between(from, to)
	if cover.is_empty():
		_resolve(shot, "none", {})
		return

	# The GM decides what the geometry means. That is the whole point of the
	# prompt: the board proposes, the table disposes.
	_show_cover_prompt(shot, cover)


func _show_cover_prompt(shot: Dictionary, cover: Dictionary) -> void:
	var definition := Store.cover_by_id(String(cover["cover_id"]))
	var prop_hp := 0
	for prop in Store.active_location().get("props", []):
		if String((prop as Dictionary)["id"]) == String(cover["prop_id"]):
			prop_hp = int((prop as Dictionary)["hp"])
	if prop_hp == 0:
		prop_hp = int(definition.get("hp", 0))

	var scrim := ColorRect.new()
	scrim.name = "CoverPrompt"
	scrim.color = Color(0.024, 0.035, 0.051, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scrim.grow_vertical = Control.GROW_DIRECTION_BOTH
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var dialog := UI.panel(UI.PANEL_RAISED, UI.ACCENT_FILL)
	dialog.custom_minimum_size = Vector2(460, 0)
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	scrim.add_child(dialog)

	var box := UI.vbox(UI.GAP_2)
	dialog.add_child(UI.margins(box, UI.GAP_5))

	box.add_child(UI.micro("Cover in the line of fire"))
	box.add_child(UI.display(String(definition.get("name", "Cover")), 26))
	var text := UI.body(
		(
			"%d%% of the target is behind it, %s m from the shooter. Range to target %s m."
			% [
				roundi(float(cover["occlusion"]) * 100.0),
				String.num(float(cover["distance_m"]), 1),
				String.num(float(shot["distance_m"]), 1),
			]
		),
		12,
		UI.MUTED,
	)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs the full width, so clipping has to come back off.
	text.clip_text = false
	box.add_child(text)

	var choices := [
		{
			"id": "absorb",
			"label": "Cover takes the hit",
			"sub": "SP %d · %d HP absorbs the damage" % [int(definition.get("sp", 0)), prop_hp],
			"primary": true,
		},
		{
			"id": "penalty",
			"label": "Partial cover",
			"sub": "−2 to the attack, damage carries to the target",
			"primary": false,
		},
		{"id": "none", "label": "Ignore cover", "sub": "Clear shot", "primary": false},
	]
	for choice in choices:
		var entry: Dictionary = choice
		var button: Button = (
			UI.primary_button(String(entry["label"]))
			if bool(entry["primary"])
			else UI.plain_button(String(entry["label"]))
		)
		button.custom_minimum_size = Vector2(0, 44)
		button.tooltip_text = String(entry["sub"])
		button.set_meta("choice", String(entry["id"]))
		var payload := {"prop_id": cover["prop_id"], "hp": prop_hp}
		button.pressed.connect(
			func() -> void:
				scrim.queue_free()
				_resolve(shot, String(entry["id"]), payload)
		)
		box.add_child(button)
		box.add_child(UI.micro(String(entry["sub"]), UI.MUTED_DIM))

	var cancel := UI.plain_button("Cancel the shot")
	cancel.pressed.connect(scrim.queue_free)
	box.add_child(cancel)


func _resolve(shot: Dictionary, cover_choice: String, cover: Dictionary) -> void:
	var attacker: Dictionary = {}
	for actor in _snapshot.get("actors", []):
		if String((actor as Dictionary)["id"]) == String(shot["attacker"]):
			attacker = actor
	var weapon_name := String(attacker.get("selected_weapon", ""))
	if weapon_name == "":
		_message = "The selected unit has no weapon configured."
		_refresh_card()
		return

	var command := {
		"attacker_id": shot["attacker"],
		"target_id": shot["target"],
		"weapon": weapon_name,
		"distance_m": shot["distance_m"],
		"location": shot["location"],
		"mode": shot["mode"],
		# Partial cover as a flat penalty is a GM call, not the printed rule;
		# absorbing the hit is what the resolver does by default.
		"modifiers": -2 if cover_choice == "penalty" else 0,
	}
	if cover_choice == "absorb" and not cover.is_empty():
		command["cover_hp"] = int(cover["hp"])
		command["cover_id"] = String(cover["prop_id"])

	_encounter.attack(command)
	_snapshot = _encounter.snapshot()

	_board.play_shot(
		_unit_cell(String(shot["attacker"])),
		_unit_cell(String(shot["target"])),
		bool((_snapshot.get("result", {}) as Dictionary).get("hit", false)),
	)
	_sync_units()
	_message = String((_snapshot.get("card", {}) as Dictionary).get("title", "Resolved"))
	_refresh()


## Grenades hit everyone in radius for full damage with no cover save, so this
## walks the units itself rather than going through the single-target resolver.
func _detonate(cell: Dictionary) -> void:
	_board.play_blast(cell, BLAST_RADIUS_M)
	var caught := 0
	for unit in Store.active_location().get("units", []):
		var entry: Dictionary = unit
		var at := {"x": int(entry["x"]), "z": int(entry["z"]), "layer": int(entry.get("layer", 0))}
		if _board.distance_m(cell, at) <= BLAST_RADIUS_M:
			caught += 1
	if caught == 0:
		_message = "Blast at %d m caught nobody." % int(BLAST_RADIUS_M)
	else:
		_message = (
			"Frag · %dd6 · blast %d m · %d in radius · roll damage per target, no cover save"
			% [BLAST_DICE, int(BLAST_RADIUS_M), caught]
		)
	_refresh_card()


# -- rail -----------------------------------------------------------------------------


func _build_rail() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(290, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)

	var head := UI.hbox()
	var title := UI.micro("Initiative")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("1d10 + REF"))
	column.add_child(UI.margins(head, UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_initiative_box = UI.vbox(1)
	UI.expand(_initiative_box, true, false)
	var init_wrapper := UI.margins(_initiative_box, UI.GAP_2)
	UI.expand(init_wrapper, true, false)
	scroll.add_child(init_wrapper)

	column.add_child(UI.rule_line())
	_selected_box = UI.vbox(0)
	UI.expand(_selected_box)
	column.add_child(_selected_box)

	column.add_child(UI.rule_line())
	var actions := UI.vbox(UI.GAP_2)
	var top := UI.hbox(UI.GAP_2)
	var roll := UI.plain_button("Roll initiative")
	UI.expand(roll, true, false)
	roll.pressed.connect(roll_initiative)
	top.add_child(roll)
	_undo_button = UI.plain_button("Undo")
	UI.expand(_undo_button, true, false)
	_undo_button.pressed.connect(
		func() -> void:
			_encounter.undo()
			_snapshot = _encounter.snapshot()
			_sync_units()
			_refresh()
	)
	top.add_child(_undo_button)
	actions.add_child(top)

	_end_turn_button = UI.primary_button("End turn ▸")
	_end_turn_button.pressed.connect(
		func() -> void:
			_encounter.end_turn()
			_snapshot = _encounter.snapshot()
			var current: Dictionary = _encounter.current_turn()
			if not current.is_empty():
				_selected_unit = String(current["actor_id"])
			_refresh()
	)
	actions.add_child(_end_turn_button)
	column.add_child(UI.margins(actions, UI.GAP_3))

	return shell


func _sync_units() -> void:
	if _board == null:
		return
	var location := Store.active_location()
	var visuals := {}
	for unit in location.get("units", []):
		var entry: Dictionary = unit
		var character := Store.character_by_id(String(entry["character_id"]))
		if character.is_empty():
			continue
		var hp := int(character["hp"])
		var max_hp := int(character["max_hp"])
		for actor in _snapshot.get("actors", []):
			if String((actor as Dictionary)["id"]) == String(entry["id"]):
				hp = int((actor as Dictionary)["hp"])
				max_hp = int((actor as Dictionary)["max_hp"])
		visuals[String(entry["id"])] = {
			"side": String(character.get("side", "neutral")),
			"hp_ratio": clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0),
			"down": hp <= 0,
			"model_id": String(character.get("model_id", "")),
		}
	_board.set_units(location.get("units", []), visuals)
	_board.set_selection(_selected_unit)


func _refresh() -> void:
	if _encounter == null:
		return
	_refresh_header()
	_refresh_initiative()
	_refresh_selected()
	_refresh_card()
	if _board != null:
		_board.set_selection(_selected_unit)


func _refresh_header() -> void:
	var location := Store.active_location()
	var state := (
		"Combat · Round %d" % int(_snapshot.get("round", 0))
		if int(_snapshot.get("round", 0)) > 0
		else "Setup"
	)
	_header_label.text = UI._letterspace(
		(
			"Grid %d m · Elev %d layers · %s"
			% [int(location.get("tile_metres", 2)), int(location.get("layers", 1)), state]
		).to_upper()
	)


func _refresh_initiative() -> void:
	for child in _initiative_box.get_children():
		child.queue_free()

	var order: Array = _snapshot.get("initiative", [])
	if order.is_empty():
		_initiative_box.add_child(UI.margins(UI.micro("Not rolled yet."), UI.GAP_2))
		_undo_button.disabled = not bool(_snapshot.get("can_undo", false))
		_end_turn_button.disabled = true
		return

	_undo_button.disabled = not bool(_snapshot.get("can_undo", false))
	_end_turn_button.disabled = false

	for entry in order:
		var row: Dictionary = entry
		var actor_id := String(row["actor_id"])
		var actor: Dictionary = {}
		for candidate in _snapshot.get("actors", []):
			if String((candidate as Dictionary)["id"]) == actor_id:
				actor = candidate
		var is_current := String(_snapshot.get("current_actor_id", "")) == actor_id
		_initiative_box.add_child(_build_initiative_row(row, actor, is_current))


func _build_initiative_row(entry: Dictionary, actor: Dictionary, is_current: bool) -> Control:
	var actor_id := String(entry["actor_id"])
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	var style := UI.flat(UI.PANEL_RAISED if is_current else UI.PANEL_INSET, UI.HAIRLINE, 1, 6)
	if is_current:
		style.border_color = UI.ACCENT
		style.border_width_left = 2
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.RULE, 1, 6))
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(
		func() -> void:
			_selected_unit = actor_id
			_refresh()
	)

	var row := UI.hbox(UI.GAP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := UI.fill_margins(row, UI.GAP_2)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(wrapper)

	var score := UI.display(str(int(entry["score"])), 17, UI.ACCENT)
	score.custom_minimum_size = Vector2(28, 0)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(score)

	var text := UI.vbox(1)
	UI.expand(text, true, false)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	text.add_child(UI.elide(UI.value(String(entry["name"]), 11)))

	var status := ""
	if not actor.is_empty():
		if int(actor["hp"]) <= 0:
			status = "Down"
		elif int(actor["hp"]) <= CampaignSchema.serious_wound_threshold(int(actor["max_hp"])):
			status = "Seriously wounded"
	if is_current:
		status = "Acting now" if status == "" else "Acting now · " + status
	text.add_child(UI.elide(UI.micro(status, UI.ALERT_BRIGHT if status.contains("wounded") else UI.MUTED)))

	if not actor.is_empty():
		text.add_child(UI.hp_bar(float(actor["hp"]) / maxf(1.0, float(actor["max_hp"]))))
		var hp := UI.micro("%d/%d" % [int(actor["hp"]), int(actor["max_hp"])])
		hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hp)

	return button


func _refresh_selected() -> void:
	for child in _selected_box.get_children():
		child.queue_free()

	var actor: Dictionary = {}
	for candidate in _snapshot.get("actors", []):
		if String((candidate as Dictionary)["id"]) == _selected_unit:
			actor = candidate
	if actor.is_empty():
		return

	var head := UI.hbox()
	var title := UI.micro("Selected")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro(String(actor["name"])))
	_selected_box.add_child(UI.margins(head, UI.GAP_2))

	var stats: Dictionary = actor.get("stats", {})
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	for key in CampaignSchema.STAT_KEYS:
		var tile := UI.panel(UI.PANEL_INSET)
		var box := UI.vbox(0)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_child(UI.margins(box, 4))
		var key_label := UI.micro(key)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(key_label)
		var value_label := UI.display(str(int(stats.get(key, 0))), 15)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(value_label)
		grid.add_child(tile)
	_selected_box.add_child(UI.margins(grid, UI.GAP_2))

	if _is_setup():
		_build_setup_skill_check()

	_selected_box.add_child(UI.margins(UI.micro("Actions this turn"), UI.GAP_2))
	var actions := UI.vbox(1)
	var spent: Array = (_snapshot.get("actions_taken", {}) as Dictionary).get(_selected_unit, [])
	for action in spent:
		actions.add_child(_action_row(String(action), "Used", true))
	actions.add_child(_action_row("Move · %d m" % (int(stats.get("MOVE", 0)) * 2), "Action", false))
	var weapons: Array = actor.get("weapons", [])
	var ammo_text := "—"
	if not weapons.is_empty():
		ammo_text = "%d rds" % int((weapons[0] as Dictionary)["ammo"])
	actions.add_child(
		_action_row("Attack · %s" % String(actor.get("selected_weapon", "—")), ammo_text, false)
	)
	actions.add_child(_action_row("Aimed shot · head", "−8 DV", false))
	_selected_box.add_child(UI.margins(actions, UI.GAP_2))


func _selected_character() -> Dictionary:
	for unit in Store.active_location().get("units", []):
		var entry: Dictionary = unit
		if String(entry["id"]) == _selected_unit:
			return Store.character_by_id(String(entry["character_id"]))
	return {}


func _build_setup_skill_check() -> void:
	var character := _selected_character()
	if character.is_empty():
		return
	CharacterRules.ensure_character(character)
	var skills: Array = character.get("skills", [])
	_selected_box.add_child(UI.rule_line())
	_selected_box.add_child(UI.margins(UI.micro("Setup skill check"), UI.GAP_2))
	var row := UI.hbox(UI.GAP_2)
	var selected := OptionButton.new()
	UI.expand(selected, true, false)
	for index in skills.size():
		var skill: Dictionary = skills[index]
		selected.add_item(String(skill["name"]))
		selected.set_item_metadata(index, String(skill["name"]))
	if skills.is_empty():
		selected.add_item("No skills")
		selected.disabled = true
	row.add_child(selected)
	var modifier := SpinBox.new()
	modifier.min_value = -10
	modifier.max_value = 10
	modifier.prefix = "Mod "
	modifier.custom_minimum_size = Vector2(78, 0)
	row.add_child(modifier)
	var dv := SpinBox.new()
	dv.min_value = 1
	dv.max_value = 30
	dv.value = 13
	dv.prefix = "DV "
	dv.custom_minimum_size = Vector2(72, 0)
	row.add_child(dv)
	var roll := UI.primary_button("Roll")
	roll.disabled = skills.is_empty()
	roll.pressed.connect(
		func() -> void:
			roll_selected_skill(
				String(selected.get_item_metadata(selected.selected)),
				int(modifier.value),
				int(dv.value),
			)
	)
	row.add_child(roll)
	_selected_box.add_child(UI.margins(row, UI.GAP_2))
	var result := UI.body(_skill_result, 10, UI.MUTED)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.clip_text = false
	_selected_box.add_child(UI.margins(result, UI.GAP_2))


## Rolls a selected unit's sheet without starting combat. Kept public so UI
## automation can exercise the same setup action as the GM.
func roll_selected_skill(skill_name: String, modifier := 0, dv := 13) -> Dictionary:
	if not _is_setup():
		return {}
	var character := _selected_character()
	if character.is_empty():
		return {}
	var rolled := CharacterRules.roll_skill(character, skill_name, modifier, dv, _check_rng)
	if not bool(rolled.get("ok", false)):
		_skill_result = "That skill is not on this character's sheet."
	else:
		var dice: PackedInt32Array = rolled.get("rolls", PackedInt32Array())
		var dice_parts := PackedStringArray()
		for value in dice:
			dice_parts.append(str(value))
		var dice_text := ", ".join(dice_parts)
		_skill_result = (
			"%s: %d base %+d mod + d10 [%s] = %d vs DV %d — %s"
			% [
				skill_name,
				int(rolled["base"]),
				modifier,
				dice_text,
				int(rolled["total"]),
				dv,
				"SUCCESS" if bool(rolled["success"]) else "FAILURE",
			]
		)
	_message = _skill_result
	_refresh_selected()
	_refresh_card()
	return rolled


func _action_row(label: String, note: String, used: bool) -> Control:
	var panel := UI.panel(UI.PANEL_INSET, Color.TRANSPARENT if used else UI.HAIRLINE)
	var row := UI.hbox(UI.GAP_2)
	panel.add_child(UI.margins(row, 5))
	var text := UI.body(label, 11, UI.MUTED_DIM if used else UI.TEXT)
	UI.expand(text, true, false)
	row.add_child(text)
	row.add_child(UI.micro(note))
	return panel


func _refresh_card() -> void:
	for child in _card_box.get_children():
		child.queue_free()

	var card: Dictionary = _snapshot.get("card", {})
	if card.is_empty():
		_card_box.add_child(UI.micro(_message))
		return

	var row := UI.hbox(UI.GAP_4)
	_card_box.add_child(row)

	var head := UI.vbox(1)
	head.custom_minimum_size = Vector2(180, 0)
	row.add_child(head)
	head.add_child(UI.micro("Attack resolution"))
	var tone := UI.TEXT_DISPLAY
	if String(card.get("tone", "")) == "miss":
		tone = UI.MUTED
	elif String(card.get("tone", "")) == "hit":
		tone = UI.ACCENT
	head.add_child(UI.display(String(card["title"]), 26, tone))

	var lines := UI.vbox(0)
	UI.expand(lines, true, false)
	row.add_child(lines)
	for line in card.get("lines", []):
		lines.add_child(UI.body(String(line), 11))
