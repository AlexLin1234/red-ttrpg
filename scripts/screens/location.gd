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
var _location_id := ""


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


## The app keeps this screen alive between visits, which is the whole point
## here: a GM who looks a price up in the Market comes back to the fight they
## left rather than to a board that has never been rolled.
##
## So the encounter is deliberately not rebuilt. Only what can go stale without
## it is: the palette, the cover blocks (a car may have been added to the garage
## since), and the tokens.
func on_shown() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var location := Store.active_location()
	if location.is_empty() or _board == null:
		return
	_rebuild_palette()
	_board.set_location(location, Store.cover_palette())
	_sync_units()
	_refresh()


## A three-dimensional board redrawn every frame behind a screen nobody is
## looking at is pure heat.
func on_hidden() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## A different board entirely shares nothing with this one — not the deck, not
## the units, and certainly not the fight — so it is built again from scratch.
func wants_rebuild() -> bool:
	return String(Store.active_location().get("id", "")) != _location_id


func _build_encounter(location: Dictionary) -> void:
	_location_id = String(location.get("id", ""))
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

	if _palette_tab == "units":
		_palette_box.add_child(_build_squad_spawner())
		_palette_box.add_child(UI.rule_line())

	for entry in entries:
		_palette_box.add_child(_build_palette_chip(entry))


## Roll a whole squad onto the deck at once.
##
## The Forge could already roll one mook, and then the GM placed it, and then
## rolled the next one. An ambush is not one mook.
func _build_squad_spawner() -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(UI.micro("Spawn a squad"))
	var picker := OptionButton.new()
	picker.clip_text = true
	for entry in EncounterTables.SQUADS:
		var profile: Dictionary = entry
		picker.add_item(String(profile["label"]))
		picker.set_item_metadata(picker.item_count - 1, String(profile["key"]))
	box.add_child(picker)

	var row := UI.hbox(UI.GAP_2)
	var count := SpinBox.new()
	count.min_value = 0
	count.max_value = 12
	count.prefix = "N "
	count.custom_minimum_size = Vector2(74, 0)
	count.tooltip_text = "0 rolls the archetype's own size"
	row.add_child(count)
	var spawn := UI.primary_button("Spawn")
	UI.expand(spawn, true, false)
	spawn.pressed.connect(
		func() -> void:
			spawn_squad(String(picker.get_item_metadata(picker.selected)), int(count.value))
	)
	row.add_child(spawn)
	box.add_child(row)
	return box


## Roll a squad and stand it on the nearest free tiles.
##
## Public so the screenshot runner drives the GM's own path.
func spawn_squad(squad_key: String, count := 0) -> Array:
	var location := Store.active_location()
	if location.is_empty():
		return []
	var members := Store.spawn_squad(
		squad_key, count, Dice.SeededRandom.new(Time.get_ticks_usec())
	)
	var placed: Array = []
	for member in members:
		var cell := _free_cell()
		if cell.is_empty():
			break
		var unit := {
			"id": "unit-%d-%d" % [Time.get_ticks_usec(), placed.size()],
			"character_id": String(member["id"]),
			"x": int(cell["x"]),
			"z": int(cell["z"]),
			"layer": int(cell.get("layer", 0)),
		}
		(location["units"] as Array).append(unit)
		placed.append(unit)

	Store.mark_dirty()
	var joining := {}
	for unit in placed:
		joining[String((unit as Dictionary)["id"])] = String((unit as Dictionary)["character_id"])
	if not joining.is_empty():
		_join_encounter(location, joining)
	_board.set_location(location, Store.cover_palette())
	_sync_units()
	_message = "%d %s on the deck." % [
		placed.size(), String(EncounterTables.squad(squad_key)["label"])
	]
	_refresh()
	return placed


## The first tile nobody is standing on.
##
## Squads land wherever there is room rather than in a formation: the GM drags
## them where they want them, which is what the Move tool has always been for.
func _free_cell() -> Dictionary:
	var location := Store.active_location()
	var taken := {}
	for unit in location.get("units", []):
		var entry: Dictionary = unit
		taken["%d,%d,%d" % [int(entry["x"]), int(entry["z"]), int(entry.get("layer", 0))]] = true
	for tile in location.get("tiles", []):
		var entry: Dictionary = tile
		var key := "%d,%d,%d" % [int(entry["x"]), int(entry["z"]), int(entry.get("layer", 0))]
		if not taken.has(key):
			return {"x": int(entry["x"]), "z": int(entry["z"]), "layer": int(entry.get("layer", 0))}
	return {}


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
			var unit_id := "unit-%d" % Time.get_ticks_usec()
			(location["units"] as Array).append(
				{
					"id": unit_id,
					"character_id": id,
					"x": cell["x"],
					"z": cell["z"],
					"layer": cell.get("layer", 0),
				}
			)
			_join_encounter(location, {unit_id: id})

	Store.mark_dirty()
	_board.set_location(location, Store.cover_palette())
	_sync_units()
	_message = "Placed."
	_refresh()


## Put newly placed units into the fight rather than starting a new one.
##
## Rebuilding the encounter was how a placed unit used to reach it, which threw
## away the round, the initiative order and every undo step with it. A squad
## arriving mid-fight is reinforcements, not a new fight.
func _join_encounter(location: Dictionary, units: Dictionary) -> void:
	if _encounter == null:
		_build_encounter(location)
		return
	var actors := {}
	for unit_id in units:
		var character := Store.character_by_id(String(units[unit_id]))
		if not character.is_empty():
			actors[String(unit_id)] = CampaignFixtures.actor_input(character)
	if actors.is_empty():
		return
	_encounter.add_actors(actors)
	_snapshot = _encounter.snapshot()


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


## Roll the Death Save the selected actor owes. Public for the same reason
## [method roll_initiative] is: the screenshot harness drives the GM's path.
func roll_death_save(actor_id: String) -> void:
	if _encounter == null or not _encounter.has_actor(actor_id):
		return
	if not Mortality.owes_death_save(_encounter.actor(actor_id)):
		return
	_encounter.death_save(actor_id)
	_after_medical_action()


func stabilize(patient_id: String, medic_id: String, skill_name: String, dv: int) -> void:
	if _encounter == null or not _encounter.has_actor(patient_id):
		return
	_encounter.stabilize(patient_id, medic_id, skill_name, dv)
	_after_medical_action()


func heal_actor(actor_id: String, amount: int) -> void:
	if _encounter == null or amount <= 0 or not _encounter.has_actor(actor_id):
		return
	_encounter.heal(actor_id, amount)
	_after_medical_action()


func treat_injury(patient_id: String, medic_id: String, injury: String, skill_name: String, dv: int) -> void:
	if _encounter == null or not _encounter.has_actor(patient_id):
		return
	_encounter.treat_injury(patient_id, medic_id, injury, skill_name, dv)
	_after_medical_action()


func _after_medical_action() -> void:
	_snapshot = _encounter.snapshot()
	_sync_units()
	_refresh()


## Write what the fight did back onto the roster.
##
## The encounter is a scratch copy of the party, so an NPC killed here would
## otherwise be alive again the moment the GM changes screen. Committing is the
## GM's own button rather than something that happens quietly, because an
## encounter is often replayed before it counts.
func commit_to_roster() -> void:
	if _encounter == null:
		return
	var written := 0
	for unit in Store.active_location().get("units", []):
		var entry: Dictionary = unit
		var unit_id := String(entry["id"])
		if not _encounter.has_actor(unit_id):
			continue
		var character := Store.character_by_id(String(entry["character_id"]))
		if character.is_empty():
			continue
		var actor := _encounter.actor(unit_id)
		character["hp"] = int(actor["hp"])
		character["wound_state"] = String(actor["wound_state"])
		character["death_save_due"] = bool(actor["death_save_due"])
		character["death_save_penalty"] = int(actor["death_save_penalty"])
		character["critical_injuries"] = (actor["critical_injuries"] as Array).duplicate()
		written += 1
	if written == 0:
		return
	Store.mark_dirty()
	Store.set_status("%d sheets updated" % written)
	_message = "Committed HP, wounds and injuries for %d characters." % written
	_refresh_card()


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
	column.add_child(UI.margins(_build_player_display_controls(), UI.GAP_3))

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

	var commit := UI.plain_button("Save results to roster")
	commit.tooltip_text = "Write HP, wounds and injuries onto the character sheets"
	commit.pressed.connect(commit_to_roster)
	actions.add_child(commit)

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


## What the second screen is allowed to add to what it already shows.
##
## Both default off: the table gets positions and a name, not the arithmetic
## behind a DV or an enemy's exact HP.
func _build_player_display_controls() -> Control:
	var box := UI.vbox(UI.GAP_2)
	var head := UI.hbox()
	var title := UI.micro("Player display")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro("Second screen"))
	box.add_child(head)

	var options := PlayerView.options_for(Store.active_location())
	var row := UI.hbox(1)
	for entry in [
		{"key": "show_enemy_hp", "label": "Enemy HP"},
		{"key": "show_math", "label": "Dice math"},
	]:
		var option: Dictionary = entry
		var key := String(option["key"])
		var button := UI.tab_button(String(option["label"]), bool(options[key]))
		UI.expand(button, true, false)
		button.pressed.connect(
			func() -> void: set_player_display_option(key, button.button_pressed)
		)
		row.add_child(button)
	box.add_child(row)
	return box


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
		var wound_state := String(character.get("wound_state", Mortality.UNHURT))
		for actor in _snapshot.get("actors", []):
			if String((actor as Dictionary)["id"]) == String(entry["id"]):
				hp = int((actor as Dictionary)["hp"])
				max_hp = int((actor as Dictionary)["max_hp"])
				wound_state = String((actor as Dictionary)["wound_state"])
		visuals[String(entry["id"])] = {
			"side": String(character.get("side", "neutral")),
			"hp_ratio": clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0),
			"down": hp <= 0 or wound_state == Mortality.DEAD,
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
	_publish_player_view()


## Hand the table's window the filtered view of what just happened.
##
## Published on every refresh rather than on a timer, so the TV is never a beat
## behind the console. Leaving this screen does not blank it: the GM stepping
## over to the Market mid-fight should not clear the board the table is reading.
func _publish_player_view() -> void:
	var location := Store.active_location()
	if location.is_empty():
		Store.publish_player_view({})
		return
	var characters := {}
	for character in Store.characters():
		characters[String((character as Dictionary)["id"])] = character
	Store.publish_player_view(
		PlayerView.compose(
			_snapshot,
			location,
			characters,
			Store.cover_palette(),
			PlayerView.options_for(location),
		)
	)


func _unit_entry(unit_id: String) -> Dictionary:
	for unit in Store.active_location().get("units", []):
		if String((unit as Dictionary)["id"]) == unit_id:
			return unit
	return {}


## Take a unit off the table's screen, or put it back.
##
## The ambush waiting in the stairwell is on the GM's board from the moment it
## is placed; the table meets it when it steps out.
func set_unit_hidden(unit_id: String, hidden: bool) -> void:
	var entry := _unit_entry(unit_id)
	if entry.is_empty():
		return
	entry[PlayerView.HIDDEN_KEY] = hidden
	Store.mark_dirty()
	_refresh()


func set_player_display_option(key: String, value: bool) -> void:
	var location := Store.active_location()
	if location.is_empty():
		return
	if not location.has("player_display"):
		location["player_display"] = {}
	(location["player_display"] as Dictionary)[key] = value
	Store.mark_dirty()
	_refresh()


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
	var tone := UI.MUTED
	if not actor.is_empty():
		var wound_state := String(actor.get("wound_state", Mortality.UNHURT))
		if wound_state != Mortality.UNHURT and wound_state != Mortality.LIGHTLY_WOUNDED:
			status = Mortality.label(wound_state)
			tone = UI.WARN if wound_state == Mortality.SERIOUSLY_WOUNDED else UI.ALERT_BRIGHT
		if bool(actor.get("death_save_due", false)):
			status += " · save due"
	if is_current:
		status = "Acting now" if status == "" else "Acting now · " + status
	text.add_child(UI.elide(UI.micro(status, tone)))

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

	var hidden := bool(_unit_entry(_selected_unit).get(PlayerView.HIDDEN_KEY, false))
	var reveal := UI.tab_button("Hidden from players", hidden)
	reveal.tooltip_text = (
		"On the GM board only — not drawn on the player display, and not listed in its turn order"
	)
	reveal.pressed.connect(
		func() -> void: set_unit_hidden(_selected_unit, reveal.button_pressed)
	)
	_selected_box.add_child(UI.margins(reveal, UI.GAP_2))

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

	_build_condition(actor)

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


## Condition, and the medicine that answers it.
##
## Everything here is one click from the selected unit, because the moment a
## character hits zero the GM is looking at this rail and nowhere else.
func _build_condition(actor: Dictionary) -> void:
	var wound_state := String(actor.get("wound_state", Mortality.UNHURT))
	var penalty := int(actor.get("action_penalty", 0))
	var injuries: Array = actor.get("critical_injuries", [])

	_selected_box.add_child(UI.rule_line())
	var tone := UI.MUTED
	if wound_state == Mortality.SERIOUSLY_WOUNDED:
		tone = UI.WARN
	elif wound_state == Mortality.MORTALLY_WOUNDED or wound_state == Mortality.DEAD:
		tone = UI.ALERT_BRIGHT
	var rows := UI.vbox(UI.GAP_1)
	rows.add_child(UI.field_row("Condition", Mortality.label(wound_state), tone))
	if penalty != 0:
		rows.add_child(UI.field_row("All actions", "%+d" % penalty, UI.ALERT_BRIGHT))
	if bool(actor.get("death_save_due", false)):
		rows.add_child(
			UI.field_row(
				"Death save", "penalty %+d" % -int(actor.get("death_save_penalty", 0)), UI.ALERT_BRIGHT
			)
		)
	_selected_box.add_child(UI.margins(rows, UI.GAP_2))

	if Mortality.is_dead(actor):
		return

	var medics := _medic_options()
	if bool(actor.get("death_save_due", false)):
		_build_death_save_row(actor, medics)
	_build_treatment_row(actor, medics, injuries)


## Everyone still standing, so the GM can pick who is doing the patching.
func _medic_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var current := String(_snapshot.get("current_actor_id", ""))
	for candidate in _snapshot.get("actors", []):
		var entry: Dictionary = candidate
		if Mortality.is_dead(entry):
			continue
		options.append({"id": String(entry["id"]), "name": String(entry["name"])})
	options.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			# Whoever is acting comes first: usually they are the one reaching for
			# the medkit.
			if String(a["id"]) == current:
				return true
			if String(b["id"]) == current:
				return false
			return String(a["name"]) < String(b["name"])
	)
	return options


func _build_death_save_row(actor: Dictionary, medics: Array[Dictionary]) -> void:
	var actor_id := String(actor["id"])
	var spent: Array = (_snapshot.get("actions_taken", {}) as Dictionary).get(actor_id, [])
	var row := UI.hbox(UI.GAP_2)
	var save := UI.primary_button("Roll death save")
	UI.expand(save, true, false)
	save.disabled = spent.has("Death Save")
	save.tooltip_text = (
		"Already rolled this turn"
		if save.disabled
		else "d10 + accumulated penalty against BODY"
	)
	save.pressed.connect(roll_death_save.bind(actor_id))
	row.add_child(save)

	var stabilize_button := UI.plain_button("Stabilize")
	UI.expand(stabilize_button, true, false)
	stabilize_button.disabled = medics.is_empty()
	stabilize_button.tooltip_text = "First Aid against DV %d" % int(
		Mortality.RULES["stabilize_dv"]
	)
	if not medics.is_empty():
		var medic_id := String((medics[0] as Dictionary)["id"])
		stabilize_button.pressed.connect(
			func() -> void: stabilize(actor_id, medic_id, "First Aid", -1)
		)
	row.add_child(stabilize_button)
	_selected_box.add_child(UI.margins(row, UI.GAP_2))


func _build_treatment_row(
	actor: Dictionary, medics: Array[Dictionary], injuries: Array
) -> void:
	var actor_id := String(actor["id"])
	var row := UI.hbox(UI.GAP_2)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 60
	amount.value = 5
	amount.prefix = "HP "
	amount.custom_minimum_size = Vector2(84, 0)
	row.add_child(amount)
	var heal := UI.plain_button("Heal")
	UI.expand(heal, true, false)
	heal.disabled = int(actor["hp"]) >= int(actor["max_hp"])
	heal.pressed.connect(func() -> void: heal_actor(actor_id, int(amount.value)))
	row.add_child(heal)
	_selected_box.add_child(UI.margins(row, UI.GAP_2))

	if injuries.is_empty():
		return
	_selected_box.add_child(UI.margins(UI.micro("Critical injuries"), UI.GAP_2))
	var list := UI.vbox(UI.GAP_1)
	var medic_id := String((medics[0] as Dictionary)["id"]) if not medics.is_empty() else ""
	for injury in injuries:
		var name := String(injury)
		var injury_row := UI.hbox(UI.GAP_2)
		var label := UI.elide(UI.body(name, 11, UI.ALERT_BRIGHT))
		UI.expand(label, true, false)
		injury_row.add_child(label)
		var treat := UI.plain_button("Treat")
		treat.disabled = medic_id == ""
		treat.tooltip_text = "Surgery against DV %d" % int(Mortality.RULES["treatment_dv"])
		if medic_id != "":
			treat.pressed.connect(
				func() -> void:
					treat_injury(
						actor_id, medic_id, name, "Surgery", int(Mortality.RULES["treatment_dv"])
					)
			)
		injury_row.add_child(treat)
		list.add_child(injury_row)
	_selected_box.add_child(UI.margins(list, UI.GAP_2))


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
