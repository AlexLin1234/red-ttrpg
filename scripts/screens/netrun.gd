extends Control

## The Netrun screen.
##
## The Forge has been able to build a Netrunner since the first release — all ten
## Roles, Interface ranks, the lot — and there has been nowhere to run. This is
## the ladder they run down: architectures on the left, the floors themselves in
## the middle, and the runner and their NET Actions on the right.
##
## It is the Location screen's shape rather than a new one, deliberately. The
## rules live in [Netrun], the live state in [NetrunSession], and the screen only
## draws snapshots and forwards clicks.

const LEVEL_HEIGHT := 78

var _run: NetrunSession
var _snapshot: Dictionary = {}
var _selected_floor := ""
var _runner_id := ""
var _interface_override := -1
var _message := "Pick an architecture and jack in."

var _architecture_box: VBoxContainer
var _ladder_box: VBoxContainer
var _runner_box: VBoxContainer
var _action_box: VBoxContainer
var _card_box: VBoxContainer
var _editor_box: VBoxContainer
var _header_label: Label


func _ready() -> void:
	if not Store.is_open():
		return
	var column := UI.vbox(UI.GAP_3)
	add_child(UI.fill_margins(column, UI.GAP_3))
	column.add_child(_build_bar())

	var body := UI.hbox(UI.GAP_3)
	UI.expand(body)
	column.add_child(body)
	body.add_child(_build_architectures())
	body.add_child(_build_ladder())
	body.add_child(_build_rail())

	_refresh()


func _build_bar() -> Control:
	var bar := UI.hbox(UI.GAP_4)
	var left := UI.micro("%s / NET" % Store.campaign["city"])
	UI.expand(left, true, false)
	bar.add_child(left)
	_header_label = UI.micro("")
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_header_label)
	return bar


# -- architectures ---------------------------------------------------------------


func _build_architectures() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(240, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)
	column.add_child(UI.margins(UI.micro("Architectures"), UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	column.add_child(scroll)
	_architecture_box = UI.vbox(UI.GAP_1)
	UI.expand(_architecture_box, true, false)
	var wrapper := UI.margins(_architecture_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	var tools := UI.vbox(UI.GAP_2)
	var difficulty := OptionButton.new()
	for entry in NetrunDefault.DIFFICULTIES:
		var spec: Dictionary = entry
		difficulty.add_item("%s · %d floors" % [String(spec["label"]), int(spec["floors"])])
		difficulty.set_item_metadata(difficulty.item_count - 1, String(spec["key"]))
	difficulty.selected = 1
	difficulty.clip_text = true
	tools.add_child(difficulty)

	var generate := UI.primary_button("Roll architecture")
	generate.tooltip_text = "Alternating doors and defenders, editable afterwards"
	generate.pressed.connect(
		func() -> void:
			generate_architecture(String(difficulty.get_item_metadata(difficulty.selected)))
	)
	tools.add_child(generate)
	column.add_child(UI.margins(tools, UI.GAP_3))
	return shell


## Roll a new architecture into the campaign and select it.
func generate_architecture(difficulty_key: String) -> void:
	var spec := NetrunDefault.difficulty(difficulty_key)
	var name := "%s Architecture %d" % [String(spec["label"]), Store.architectures().size() + 1]
	var rolled := NetrunDefault.generate_architecture(
		name, difficulty_key, Dice.SeededRandom.new(Time.get_ticks_usec())
	)
	Store.add_architecture(rolled)
	_run = null
	_snapshot = {}
	_message = "%s rolled. Pick a netrunner and jack in." % name
	_refresh()


func select_architecture(id: String) -> void:
	Store.active_architecture_id = id
	_run = null
	_snapshot = {}
	_selected_floor = ""
	_refresh()


func _refresh_architectures() -> void:
	for child in _architecture_box.get_children():
		child.queue_free()
	var all := Store.architectures()
	if all.is_empty():
		_architecture_box.add_child(
			UI.margins(UI.micro("None yet. Roll one below."), UI.GAP_2)
		)
		return
	var active := String(Store.active_architecture().get("id", ""))
	for entry in all:
		var architecture: Dictionary = entry
		var id := String(architecture["id"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 46)
		button.focus_mode = Control.FOCUS_NONE
		var style := UI.flat(UI.PANEL_RAISED if id == active else UI.PANEL_INSET, UI.HAIRLINE, 1, 6)
		if id == active:
			style.border_color = UI.ACCENT
			style.border_width_left = 2
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.RULE, 1, 6))
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(select_architecture.bind(id))

		var text := UI.vbox(1)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrapper := UI.fill_margins(text, UI.GAP_2)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(wrapper)
		text.add_child(UI.elide(UI.value(String(architecture["name"]), 12)))
		text.add_child(
			UI.elide(
				UI.micro(
					"%s · %d floors"
					% [
						String(
							NetrunDefault.difficulty(String(architecture.get("difficulty", "standard")))[
								"label"
							]
						),
						(architecture.get("floors", []) as Array).size(),
					]
				)
			)
		)
		_architecture_box.add_child(button)


# -- the ladder ------------------------------------------------------------------


func _build_ladder() -> Control:
	var column := UI.vbox(UI.GAP_2)
	UI.expand(column)

	var frame := UI.panel(UI.PANEL_INSET)
	UI.expand(frame)
	column.add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	frame.add_child(scroll)
	_ladder_box = UI.vbox(UI.GAP_2)
	UI.expand(_ladder_box, true, false)
	var wrapper := UI.margins(_ladder_box, UI.GAP_3)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	var card := UI.panel()
	card.custom_minimum_size = Vector2(0, 104)
	column.add_child(card)
	_card_box = UI.vbox(2)
	card.add_child(UI.margins(_card_box, UI.GAP_3))
	return column


func _refresh_ladder() -> void:
	for child in _ladder_box.get_children():
		child.queue_free()

	var architecture := Store.active_architecture()
	if architecture.is_empty():
		_ladder_box.add_child(UI.micro("No architecture selected."))
		return

	_ladder_box.add_child(UI.margins(UI.display(String(architecture["name"]), 20), 0))
	_ladder_box.add_child(_lobby_row())

	var floors: Array = _snapshot.get("floors", [])
	if floors.is_empty():
		# Not running yet: draw the saved definition so the GM can edit it cold.
		for entry in architecture.get("floors", []):
			floors.append(NetrunSession._normalize_floor(entry))
	var deepest := 0
	for entry in floors:
		deepest = maxi(deepest, int((entry as Dictionary)["level"]))

	for level in range(1, deepest + 1):
		var row := UI.hbox(UI.GAP_2)
		for entry in floors:
			var floor_entry: Dictionary = entry
			if int(floor_entry["level"]) != level:
				continue
			row.add_child(_floor_card(floor_entry))
		_ladder_box.add_child(row)


## The way in. Always drawn, so the ladder reads top to bottom.
func _lobby_row() -> Control:
	var here := _run != null and int(_snapshot.get("runner", {}).get("level", 0)) == 0
	var panel := UI.panel(UI.PANEL_RAISED if here else UI.PANEL, UI.ACCENT if here else UI.HAIRLINE)
	var row := UI.hbox(UI.GAP_3)
	panel.add_child(UI.margins(row, UI.GAP_2))
	row.add_child(UI.micro("Lobby"))
	var label := UI.body("The way in, and the way out.", 11, UI.MUTED)
	UI.expand(label, true, false)
	row.add_child(label)
	if here:
		row.add_child(UI.value("◆ HERE", 11, UI.ACCENT))
	return panel


func _floor_card(floor_entry: Dictionary) -> Control:
	var id := String(floor_entry["id"])
	var kind := String(floor_entry["kind"])
	var state := String(floor_entry["state"])
	var here := bool(floor_entry.get("here", false))
	var revealed := bool(floor_entry.get("revealed", false)) or _run == null

	var button := Button.new()
	button.custom_minimum_size = Vector2(260, LEVEL_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	UI.expand(button, true, false)
	var background := UI.PANEL_INSET
	var border := UI.HAIRLINE
	if here:
		background = UI.PANEL_RAISED
		border = UI.ACCENT
	elif state == Netrun.DEFEATED:
		border = UI.ACCENT_DIM
	button.add_theme_stylebox_override("normal", UI.flat(background, border, 1, 8))
	button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.RULE, 1, 8))
	button.add_theme_stylebox_override("pressed", UI.flat(background, border, 1, 8))
	button.pressed.connect(
		func() -> void:
			_selected_floor = id
			_refresh()
	)

	var box := UI.vbox(2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := UI.fill_margins(box, UI.GAP_2)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(wrapper)

	var head := UI.hbox(UI.GAP_2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UI.micro("Lv %d" % int(floor_entry["level"])))
	var title_color := UI.TEXT
	if not revealed:
		title_color = UI.MUTED_DIM
	elif kind == "ice":
		title_color = UI.ALERT_BRIGHT if bool(floor_entry.get("black", false)) else UI.WARN
	var title := UI.elide(
		UI.value(String(floor_entry["name"]) if revealed else "Unknown", 12, title_color)
	)
	UI.expand(title, true, false)
	head.add_child(title)
	if here:
		head.add_child(UI.value("◆", 12, UI.ACCENT))
	box.add_child(head)

	var detail := String(NetrunDefault.floor_kind(kind)["label"]) if revealed else "Not scouted"
	if revealed and kind == "ice":
		detail += " · REZ %d/%d" % [int(floor_entry.get("rez", 0)), int(floor_entry.get("max_rez", 0))]
	elif revealed:
		detail += " · DV %d" % int(floor_entry.get("dv", 0))
	box.add_child(UI.elide(UI.micro(detail)))

	if state != Netrun.INTACT:
		box.add_child(UI.elide(UI.micro(state.capitalize(), UI.ACCENT)))
	elif revealed and kind == "ice":
		box.add_child(
			UI.hp_bar(
				float(floor_entry.get("rez", 0)) / maxf(1.0, float(floor_entry.get("max_rez", 1)))
			)
		)
	return button


# -- the runner rail --------------------------------------------------------------


func _build_rail() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(320, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)
	column.add_child(UI.margins(UI.micro("Netrunner"), UI.GAP_3))
	column.add_child(UI.rule_line())
	_runner_box = UI.vbox(UI.GAP_2)
	column.add_child(UI.margins(_runner_box, UI.GAP_3))

	column.add_child(UI.rule_line())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	column.add_child(scroll)
	_action_box = UI.vbox(UI.GAP_1)
	UI.expand(_action_box, true, false)
	var wrapper := UI.margins(_action_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	_editor_box = UI.vbox(UI.GAP_2)
	column.add_child(UI.margins(_editor_box, UI.GAP_3))
	return shell


func _netrunners() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in Store.characters():
		var character: Dictionary = entry
		found.append(
			{
				"id": String(character["id"]),
				"name": String(character["name"]),
				"interface": _interface_of(character),
				"hp": int(character.get("hp", 1)),
				"max_hp": int(character.get("max_hp", 1)),
			}
		)
	# A Netrunner first, then everyone else: a Solo with a borrowed deck is a
	# perfectly good story, they are just not who this screen is usually for.
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["interface"]) != int(b["interface"]):
				return int(a["interface"]) > int(b["interface"])
			return String(a["name"]) < String(b["name"])
	)
	return found


## Interface is the Netrunner's Role Ability rank. Anyone else is running on a
## borrowed deck and no training.
static func _interface_of(character: Dictionary) -> int:
	if String(character.get("role", "")).to_lower() != "netrunner":
		return 0
	var ability: Dictionary = character.get("role_ability", {})
	return int(ability.get("rank", 0))


func _refresh_runner() -> void:
	for child in _runner_box.get_children():
		child.queue_free()

	var runners := _netrunners()
	if runners.is_empty():
		_runner_box.add_child(UI.micro("No characters in this campaign."))
		return

	if _runner_id == "":
		_runner_id = String((runners[0] as Dictionary)["id"])

	var picker := OptionButton.new()
	picker.clip_text = true
	for index in runners.size():
		var entry: Dictionary = runners[index]
		picker.add_item("%s · Interface %d" % [String(entry["name"]), int(entry["interface"])])
		picker.set_item_metadata(index, String(entry["id"]))
		if String(entry["id"]) == _runner_id:
			picker.selected = index
	picker.disabled = _run != null
	picker.item_selected.connect(
		func(index: int) -> void:
			_runner_id = String(picker.get_item_metadata(index))
			_interface_override = -1
			_refresh()
	)
	_runner_box.add_child(picker)

	if _run == null:
		var chosen := _chosen_runner()
		var row := UI.hbox(UI.GAP_2)
		var rank := SpinBox.new()
		rank.min_value = 0
		rank.max_value = 10
		rank.prefix = "IF "
		rank.value = (
			_interface_override if _interface_override >= 0 else int(chosen.get("interface", 0))
		)
		rank.custom_minimum_size = Vector2(84, 0)
		rank.tooltip_text = "Interface rank, and so how many NET Actions a turn"
		rank.value_changed.connect(func(value: float) -> void: _interface_override = int(value))
		row.add_child(rank)
		var jack := UI.primary_button("Jack in")
		UI.expand(jack, true, false)
		jack.disabled = Store.active_architecture().is_empty()
		jack.pressed.connect(func() -> void: jack_in(_runner_id, int(rank.value)))
		row.add_child(jack)
		_runner_box.add_child(row)
		return

	var runner: Dictionary = _snapshot["runner"]
	var rows := UI.vbox(UI.GAP_1)
	rows.add_child(
		UI.field_row(
			"Run", String(_snapshot["run_state_label"]),
			UI.ACCENT if String(_snapshot["run_state"]) == "running" else UI.ALERT_BRIGHT
		)
	)
	rows.add_child(
		UI.field_row(
			"NET Actions",
			"%d / %d" % [int(runner["actions_left"]), Netrun.actions_per_turn(int(runner["interface"]))],
			UI.ACCENT if int(runner["actions_left"]) > 0 else UI.MUTED
		)
	)
	rows.add_child(UI.field_row("HP", "%d / %d" % [int(runner["hp"]), int(runner["max_hp"])]))
	var trace := int(runner["trace"])
	rows.add_child(
		UI.field_row(
			"Trace",
			"%d / %d" % [trace, int(Netrun.RULES["trace_ceiling"])],
			UI.ALERT_BRIGHT if trace > 0 else UI.MUTED
		)
	)
	rows.add_child(UI.field_row("Turn", str(int(_snapshot["turn"]))))
	_runner_box.add_child(rows)
	_runner_box.add_child(
		UI.hp_bar(float(runner["hp"]) / maxf(1.0, float(runner["max_hp"])))
	)


func _chosen_runner() -> Dictionary:
	for entry in _netrunners():
		if String((entry as Dictionary)["id"]) == _runner_id:
			return entry
	return {}


## Start a run. Public so the screenshot runner drives the GM's own path.
func jack_in(character_id: String, interface_rank := -1) -> void:
	var architecture := Store.active_architecture()
	if architecture.is_empty():
		return
	_runner_id = character_id
	var chosen := _chosen_runner()
	if chosen.is_empty():
		return
	var runner := chosen.duplicate(true)
	runner["character_id"] = character_id
	if interface_rank >= 0:
		runner["interface"] = interface_rank
	_run = NetrunSession.new(architecture, runner)
	_snapshot = _run.snapshot()
	_message = "%s is in the lobby." % String(runner["name"])
	_refresh()


func jack_out() -> void:
	_run = null
	_snapshot = {}
	_message = "Off the ladder."
	_refresh()


## Take one NET Action.
func perform(action_key: String, floor_id := "") -> void:
	if _run == null or not _run.can(action_key):
		return
	_run.perform(action_key, floor_id)
	_snapshot = _run.snapshot()
	_refresh()


func _refresh_actions() -> void:
	for child in _action_box.get_children():
		child.queue_free()

	if _run == null:
		_action_box.add_child(UI.micro("Jack in to act."))
		return

	for entry in _snapshot.get("actions", []):
		var action: Dictionary = entry
		var key := String(action["key"])
		var row := UI.hbox(UI.GAP_2)
		var button := UI.plain_button(String(action["label"]))
		button.custom_minimum_size = Vector2(112, 0)
		button.disabled = not bool(action["enabled"])
		button.tooltip_text = (
			String(action["summary"]) if bool(action["enabled"]) else String(action["reason"])
		)
		if key == "move":
			button.pressed.connect(func() -> void: perform("move", _selected_floor))
		else:
			button.pressed.connect(perform.bind(key, ""))
		row.add_child(button)
		var note := UI.elide(
			UI.micro(
				String(action["summary"]) if bool(action["enabled"]) else String(action["reason"]),
				UI.MUTED if bool(action["enabled"]) else UI.MUTED_DIM
			)
		)
		UI.expand(note, true, false)
		row.add_child(note)
		_action_box.add_child(row)

	_action_box.add_child(UI.rule_line())
	var controls := UI.hbox(UI.GAP_2)
	var undo := UI.plain_button("Undo")
	UI.expand(undo, true, false)
	undo.disabled = not bool(_snapshot.get("can_undo", false))
	undo.pressed.connect(
		func() -> void:
			_run.undo()
			_snapshot = _run.snapshot()
			_refresh()
	)
	controls.add_child(undo)
	var end_turn := UI.primary_button("End turn ▸")
	UI.expand(end_turn, true, false)
	end_turn.disabled = _run.is_over()
	end_turn.pressed.connect(
		func() -> void:
			_run.end_turn()
			_snapshot = _run.snapshot()
			_refresh()
	)
	controls.add_child(end_turn)
	_action_box.add_child(controls)

	var alarm := UI.tab_button("Alarm raised", bool((_snapshot["runner"] as Dictionary)["alerted"]))
	alarm.tooltip_text = "Every floor from here down is at +%d DV" % int(
		Netrun.RULES["alert_dv_penalty"]
	)
	alarm.pressed.connect(
		func() -> void:
			_run.set_alert(alarm.button_pressed)
			_snapshot = _run.snapshot()
			_refresh()
	)
	_action_box.add_child(alarm)

	var leave := UI.plain_button("Leave the run")
	leave.pressed.connect(jack_out)
	_action_box.add_child(leave)


# -- the floor editor -------------------------------------------------------------


func _refresh_editor() -> void:
	for child in _editor_box.get_children():
		child.queue_free()

	var architecture := Store.active_architecture()
	if architecture.is_empty():
		return

	_editor_box.add_child(UI.micro("Selected floor"))
	var floors: Array = architecture.get("floors", [])
	var selected := {}
	for entry in floors:
		if String((entry as Dictionary)["id"]) == _selected_floor:
			selected = entry
	if selected.is_empty():
		_editor_box.add_child(UI.micro("Click a floor to edit it.", UI.MUTED_DIM))
		return

	var name_field := LineEdit.new()
	name_field.text = String(selected.get("name", ""))
	name_field.placeholder_text = "Floor name"
	name_field.text_submitted.connect(
		func(value: String) -> void:
			selected["name"] = value
			Store.mark_dirty()
			_refresh()
	)
	_editor_box.add_child(name_field)

	if String(selected["kind"]) == "ice":
		var picker := OptionButton.new()
		picker.clip_text = true
		var names := NetrunDefault.ice_names()
		for index in names.size():
			picker.add_item(String(names[index]))
			picker.set_item_metadata(index, String(names[index]))
			if String(names[index]) == String(selected.get("ice_id", "")):
				picker.selected = index
		picker.item_selected.connect(
			func(index: int) -> void:
				var pick := String(picker.get_item_metadata(index))
				selected["ice_id"] = pick
				selected["name"] = pick
				selected.erase("rez")
				selected.erase("max_rez")
				selected.erase("damage_dice")
				selected.erase("black")
				selected.erase("effect")
				Store.mark_dirty()
				_refresh()
		)
		_editor_box.add_child(picker)
		var profile := NetrunDefault.ice(String(selected.get("ice_id", "Watchdog")))
		var effect := UI.body(String(profile["effect"]), 11, UI.MUTED)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_editor_box.add_child(effect)
	else:
		var dv := SpinBox.new()
		dv.min_value = 1
		dv.max_value = 30
		dv.prefix = "DV "
		dv.value = int(selected.get("dv", 6))
		dv.value_changed.connect(
			func(value: float) -> void:
				selected["dv"] = int(value)
				Store.mark_dirty()
		)
		_editor_box.add_child(dv)

	if _run != null:
		var commit := UI.plain_button("Save run to architecture")
		commit.tooltip_text = "Write derezzed programs and opened doors back onto the saved ladder"
		commit.pressed.connect(commit_run)
		_editor_box.add_child(commit)


## Persist what the run did to the architecture.
##
## A run is a scratch copy, like an encounter: the GM often walks one twice
## before it counts, so writing back is a button rather than a side effect.
func commit_run() -> void:
	if _run == null:
		return
	var architecture := Store.active_architecture()
	if architecture.is_empty():
		return
	var written := 0
	for entry in architecture.get("floors", []):
		var floor_entry: Dictionary = entry
		var live := _run.floor_by_id(String(floor_entry["id"]))
		if live.is_empty():
			continue
		floor_entry["state"] = String(live["state"])
		floor_entry["revealed"] = bool(live["revealed"])
		if String(floor_entry["kind"]) == "ice":
			floor_entry["rez"] = int(live["rez"])
		written += 1
	if written == 0:
		return
	Store.mark_dirty()
	Store.set_status("%d floors updated" % written)
	_message = "Saved the run onto %s." % String(architecture["name"])
	_refresh_card()


# -- refresh ----------------------------------------------------------------------


func _refresh() -> void:
	_refresh_architectures()
	_refresh_ladder()
	_refresh_runner()
	_refresh_actions()
	_refresh_editor()
	_refresh_card()
	_refresh_header()


func _refresh_header() -> void:
	var architecture := Store.active_architecture()
	var state := "No architecture"
	if not architecture.is_empty():
		state = (
			"Turn %d · %s" % [int(_snapshot["turn"]), String(_snapshot["run_state_label"])]
			if _run != null
			else "%d floors · not running" % (architecture.get("floors", []) as Array).size()
		)
	_header_label.text = UI._letterspace(state.to_upper())


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
	head.custom_minimum_size = Vector2(190, 0)
	row.add_child(head)
	head.add_child(UI.micro("NET action"))
	var tone := UI.TEXT_DISPLAY
	if String(card.get("tone", "")) == "hit":
		tone = UI.ALERT_BRIGHT
	elif String(card.get("tone", "")) == "undo":
		tone = UI.MUTED
	head.add_child(UI.display(String(card["title"]), 24, tone))
	head.add_child(UI.elide(UI.micro(String(card.get("target", "")))))

	var lines := UI.vbox(0)
	UI.expand(lines, true, false)
	row.add_child(lines)
	for line in card.get("lines", []):
		var label := UI.body(String(line), 11)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(label)
