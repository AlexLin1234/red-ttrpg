extends Control

## The garage, and the chase.
##
## Nomad has had a Role Ability about family vehicles and every character has had
## Drive Land Vehicle on the skill list since the first release, with nothing to
## drive. This is both halves: cars on the left, and the road between two of them
## in the middle.
##
## Like Netrun it is the Location screen's shape — rules in [Vehicles], live state
## in [Chase], and a screen that draws snapshots and forwards clicks.

const DRIVING_SKILLS: PackedStringArray = [
	"Drive Land Vehicle", "Pilot Air Vehicle", "Pilot Sea Vehicle"
]

var _chase: Chase
var _snapshot: Dictionary = {}
var _pursuer_vehicle := ""
var _quarry_vehicle := ""
var _pursuer_driver := ""
var _quarry_driver := ""
var _pursuer_move := "steady"
var _quarry_move := "steady"
var _message := "Put two cars on the road and start the chase."

var _garage_box: VBoxContainer
var _road_box: VBoxContainer
var _rail_box: VBoxContainer
var _card_box: VBoxContainer
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
	body.add_child(_build_garage())
	body.add_child(_build_road())
	body.add_child(_build_rail())
	_refresh()


func _build_bar() -> Control:
	var bar := UI.hbox(UI.GAP_4)
	var left := UI.micro("%s / Garage" % Store.campaign["city"])
	UI.expand(left, true, false)
	bar.add_child(left)
	_header_label = UI.micro("")
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_header_label)
	return bar


# -- garage -----------------------------------------------------------------------


func _build_garage() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(250, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)
	column.add_child(UI.margins(UI.micro("Garage"), UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	column.add_child(scroll)
	_garage_box = UI.vbox(UI.GAP_1)
	UI.expand(_garage_box, true, false)
	var wrapper := UI.margins(_garage_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	var tools := UI.vbox(UI.GAP_2)
	var picker := OptionButton.new()
	picker.clip_text = true
	for entry in Vehicles.TEMPLATES:
		var spec: Dictionary = entry
		picker.add_item(
			"%s · SDP %d · SP %d" % [String(spec["name"]), int(spec["sdp"]), int(spec["sp"])]
		)
		picker.set_item_metadata(picker.item_count - 1, String(spec["key"]))
	picker.selected = 1
	tools.add_child(picker)
	var add := UI.primary_button("Add vehicle")
	add.pressed.connect(
		func() -> void: add_vehicle(String(picker.get_item_metadata(picker.selected)))
	)
	tools.add_child(add)
	column.add_child(UI.margins(tools, UI.GAP_3))
	return shell


## Put a vehicle in the garage. Public so the screenshot runner drives the GM's
## own path rather than a test-only one.
func add_vehicle(template_key: String) -> void:
	var vehicle := Vehicles.from_template(template_key)
	Store.add_vehicle(vehicle)
	if _pursuer_vehicle == "":
		_pursuer_vehicle = String(vehicle["id"])
	elif _quarry_vehicle == "":
		_quarry_vehicle = String(vehicle["id"])
	_message = "%s is in the garage." % String(vehicle["name"])
	_refresh()


func _refresh_garage() -> void:
	for child in _garage_box.get_children():
		child.queue_free()
	var all := Store.vehicles()
	if all.is_empty():
		_garage_box.add_child(UI.margins(UI.micro("Empty. Add one below."), UI.GAP_2))
		return
	for entry in all:
		var vehicle: Dictionary = entry
		var id := String(vehicle["id"])
		var panel := UI.panel(UI.PANEL_INSET)
		var box := UI.vbox(2)
		panel.add_child(UI.margins(box, UI.GAP_2))

		var head := UI.hbox(UI.GAP_2)
		var name_label := UI.elide(UI.value(String(vehicle["name"]), 12))
		UI.expand(name_label, true, false)
		head.add_child(name_label)
		var role := ""
		if id == _pursuer_vehicle:
			role = "Pursuer"
		elif id == _quarry_vehicle:
			role = "Quarry"
		if role != "":
			head.add_child(UI.micro(role, UI.ACCENT))
		box.add_child(head)
		box.add_child(
			UI.elide(
				UI.micro(
					"SDP %d/%d · SP %d · handling %+d"
					% [
						int(vehicle["sdp"]),
						int(vehicle["max_sdp"]),
						int(vehicle["sp"]),
						int(vehicle["handling"]),
					]
				)
			)
		)

		var buttons := UI.hbox(1)
		for choice in [{"key": "pursuer", "label": "Pursuer"}, {"key": "quarry", "label": "Quarry"}]:
			var option: Dictionary = choice
			var button := UI.tab_button(String(option["label"]), role == String(option["label"]))
			UI.expand(button, true, false)
			button.disabled = _chase != null
			button.pressed.connect(assign_vehicle.bind(String(option["key"]), id))
			buttons.add_child(button)
		var scrap := UI.plain_button("Scrap")
		scrap.disabled = _chase != null
		scrap.pressed.connect(
			func() -> void:
				Store.remove_vehicle(id)
				if _pursuer_vehicle == id:
					_pursuer_vehicle = ""
				if _quarry_vehicle == id:
					_quarry_vehicle = ""
				_refresh()
		)
		buttons.add_child(scrap)
		box.add_child(buttons)
		_garage_box.add_child(panel)


func assign_vehicle(side: String, vehicle_id: String) -> void:
	if side == "pursuer":
		_pursuer_vehicle = vehicle_id
		if _quarry_vehicle == vehicle_id:
			_quarry_vehicle = ""
	else:
		_quarry_vehicle = vehicle_id
		if _pursuer_vehicle == vehicle_id:
			_pursuer_vehicle = ""
	_refresh()


# -- the road ---------------------------------------------------------------------


func _build_road() -> Control:
	var column := UI.vbox(UI.GAP_2)
	UI.expand(column)

	var frame := UI.panel(UI.PANEL_INSET)
	UI.expand(frame)
	column.add_child(frame)
	_road_box = UI.vbox(UI.GAP_3)
	UI.expand(_road_box, true, false)
	frame.add_child(UI.margins(_road_box, UI.GAP_4))

	var card := UI.panel()
	card.custom_minimum_size = Vector2(0, 116)
	column.add_child(card)
	_card_box = UI.vbox(2)
	card.add_child(UI.margins(_card_box, UI.GAP_3))
	return column


func _refresh_road() -> void:
	for child in _road_box.get_children():
		child.queue_free()

	if _chase == null:
		_road_box.add_child(UI.display("No chase running", 22, UI.MUTED))
		_road_box.add_child(
			UI.body(
				"Assign a pursuer and a quarry in the garage, pick who is driving each, and start.",
				13,
				UI.MUTED
			)
		)
		return

	var gap := int(_snapshot["gap"])
	_road_box.add_child(_side_panel(_snapshot["pursuer"], "Pursuer"))
	_road_box.add_child(_gap_gauge(gap))
	_road_box.add_child(_side_panel(_snapshot["quarry"], "Quarry"))

	var state := UI.hbox(UI.GAP_3)
	state.add_child(UI.micro("Round %d" % int(_snapshot["round"])))
	var outcome := UI.elide(
		UI.value(
			String(_snapshot["outcome_label"]),
			12,
			UI.ALERT_BRIGHT if String(_snapshot["outcome"]) != Vehicles.RUNNING else UI.ACCENT
		)
	)
	UI.expand(outcome, true, false)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.add_child(outcome)
	_road_box.add_child(state)


## The gap, drawn as the thing it is: distance, with the end of the chase at
## either end of it.
func _gap_gauge(gap: int) -> Control:
	var box := UI.vbox(UI.GAP_1)
	var head := UI.hbox()
	head.add_child(UI.micro("Run down"))
	var middle := UI.micro("Gap %d" % gap, UI.ACCENT)
	UI.expand(middle, true, false)
	middle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(middle)
	head.add_child(UI.micro("Gone"))
	box.add_child(head)

	var track := UI.hbox(2)
	var escape := int(_snapshot.get("escape_gap", 8))
	for band in range(0, escape + 1):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(0, 16)
		UI.expand(pip, true, false)
		var colour := UI.PANEL_INSET
		if band == gap:
			colour = UI.ACCENT
		elif band < gap:
			colour = UI.ACCENT_DIM
		pip.add_theme_stylebox_override("panel", UI.flat(colour, UI.HAIRLINE, 1))
		track.add_child(pip)
	box.add_child(track)
	return box


func _side_panel(side: Dictionary, role: String) -> Control:
	var panel := UI.panel(UI.PANEL_RAISED if not bool(side["wrecked"]) else UI.PANEL_INSET)
	var box := UI.vbox(UI.GAP_1)
	panel.add_child(UI.margins(box, UI.GAP_3))

	var head := UI.hbox(UI.GAP_2)
	head.add_child(UI.micro(role))
	var name_label := UI.elide(UI.display(String(side["name"]), 20))
	UI.expand(name_label, true, false)
	head.add_child(name_label)
	if bool(side["wrecked"]):
		head.add_child(UI.value("WRECKED", 12, UI.ALERT_BRIGHT))
	box.add_child(head)

	box.add_child(
		UI.field_row(
			"Driver",
			"%s · drive %d" % [String(side["driver_name"]), int(side["driver_skill"])]
		)
	)
	box.add_child(
		UI.field_row(
			"SDP",
			"%d / %d · SP %d · handling %+d"
			% [int(side["sdp"]), int(side["max_sdp"]), int(side["sp"]), int(side["handling"])]
		)
	)
	box.add_child(
		UI.hp_bar(float(side["sdp"]) / maxf(1.0, float(side["max_sdp"])))
	)
	return panel


# -- the rail ---------------------------------------------------------------------


func _build_rail() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(300, 0)
	UI.expand(shell, false, true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.expand(scroll)
	shell.add_child(scroll)
	_rail_box = UI.vbox(UI.GAP_3)
	UI.expand(_rail_box, true, false)
	var wrapper := UI.margins(_rail_box, UI.GAP_3)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)
	return shell


## Everyone who could plausibly be behind a wheel, with what they would roll.
func _drivers() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in Store.characters():
		var character: Dictionary = entry
		found.append(
			{
				"id": String(character["id"]),
				"name": String(character["name"]),
				"skill": driving_skill(character),
			}
		)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["skill"]) != int(b["skill"]):
				return int(a["skill"]) > int(b["skill"])
			return String(a["name"]) < String(b["name"])
	)
	return found


## The best of a character's driving skills, whatever they are driving. A
## character with none of them still rolls their REF and hopes.
static func driving_skill(character: Dictionary) -> int:
	var stats: Dictionary = character.get("stats", {})
	var best := int(stats.get("REF", 0))
	for skill in character.get("skills", []):
		var row: Dictionary = skill
		if DRIVING_SKILLS.has(String(row["name"])):
			best = maxi(best, CampaignSchema.skill_total(stats, row))
	return best


func _refresh_rail() -> void:
	for child in _rail_box.get_children():
		child.queue_free()

	if _chase == null:
		_build_setup()
		return
	_build_controls()


func _build_setup() -> void:
	_rail_box.add_child(UI.micro("Who is driving"))
	var drivers := _drivers()
	if drivers.is_empty():
		_rail_box.add_child(UI.micro("No characters in this campaign."))
		return
	if _pursuer_driver == "":
		_pursuer_driver = String((drivers[0] as Dictionary)["id"])
	if _quarry_driver == "":
		_quarry_driver = String((drivers[mini(1, drivers.size() - 1)] as Dictionary)["id"])

	_rail_box.add_child(_driver_picker("Pursuer", drivers, _pursuer_driver, true))
	_rail_box.add_child(_driver_picker("Quarry", drivers, _quarry_driver, false))

	var start := UI.primary_button("Start the chase")
	start.disabled = _pursuer_vehicle == "" or _quarry_vehicle == ""
	start.tooltip_text = (
		"Assign both cars in the garage first"
		if start.disabled
		else "Opening gap %d bands" % int(Vehicles.RULES["opening_gap"])
	)
	start.pressed.connect(func() -> void: start_chase())
	_rail_box.add_child(start)


func _driver_picker(
	label: String, drivers: Array[Dictionary], selected_id: String, is_pursuer: bool
) -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(UI.micro(label))
	var picker := OptionButton.new()
	picker.clip_text = true
	for index in drivers.size():
		var entry: Dictionary = drivers[index]
		picker.add_item("%s · drive %d" % [String(entry["name"]), int(entry["skill"])])
		picker.set_item_metadata(index, String(entry["id"]))
		if String(entry["id"]) == selected_id:
			picker.selected = index
	picker.item_selected.connect(
		func(index: int) -> void:
			if is_pursuer:
				_pursuer_driver = String(picker.get_item_metadata(index))
			else:
				_quarry_driver = String(picker.get_item_metadata(index))
			_refresh()
	)
	box.add_child(picker)
	return box


func _character_side(vehicle_id: String, driver_id: String) -> Dictionary:
	var character := Store.character_by_id(driver_id)
	return {
		"vehicle": Store.vehicle_by_id(vehicle_id),
		"driver_name": String(character.get("name", "Driver")),
		"driver_skill": driving_skill(character),
	}


## Put the two assigned cars on the road.
func start_chase() -> void:
	if _pursuer_vehicle == "" or _quarry_vehicle == "":
		return
	_chase = Chase.new(
		_character_side(_pursuer_vehicle, _pursuer_driver),
		_character_side(_quarry_vehicle, _quarry_driver),
	)
	_snapshot = _chase.snapshot()
	_pursuer_move = "steady"
	_quarry_move = "steady"
	_message = "The chase is on."
	_refresh()


func end_chase() -> void:
	_chase = null
	_snapshot = {}
	_message = "Off the road."
	_refresh()


## Run one exchange with the manoeuvres both sides have committed to.
func exchange(pursuer_move := "", quarry_move := "") -> void:
	if _chase == null or _chase.is_over():
		return
	if pursuer_move != "":
		_pursuer_move = pursuer_move
	if quarry_move != "":
		_quarry_move = quarry_move
	if not _chase.can_run(_pursuer_move):
		_pursuer_move = "steady"
	if not _chase.can_run(_quarry_move):
		_quarry_move = "steady"
	_chase.exchange(_pursuer_move, _quarry_move)
	_snapshot = _chase.snapshot()
	_refresh()


func _build_controls() -> void:
	_rail_box.add_child(_maneuver_picker("Pursuer", true))
	_rail_box.add_child(_maneuver_picker("Quarry", false))

	var run := UI.primary_button("Run the exchange")
	run.disabled = _chase.is_over()
	run.tooltip_text = (
		String(_snapshot["outcome_label"]) if _chase.is_over() else "Both sides roll at once"
	)
	run.pressed.connect(func() -> void: exchange())
	_rail_box.add_child(run)

	var row := UI.hbox(UI.GAP_2)
	var undo := UI.plain_button("Undo")
	UI.expand(undo, true, false)
	undo.disabled = not bool(_snapshot.get("can_undo", false))
	undo.pressed.connect(
		func() -> void:
			_chase.undo()
			_snapshot = _chase.snapshot()
			_refresh()
	)
	row.add_child(undo)
	var leave := UI.plain_button("End chase")
	UI.expand(leave, true, false)
	leave.pressed.connect(end_chase)
	row.add_child(leave)
	_rail_box.add_child(row)

	if _chase.is_over():
		var commit := UI.plain_button("Save damage to the garage")
		commit.tooltip_text = "Write the SDP both cars finished on back onto the saved vehicles"
		commit.pressed.connect(commit_damage)
		_rail_box.add_child(commit)


func _maneuver_picker(label: String, is_pursuer: bool) -> Control:
	var box := UI.vbox(UI.GAP_1)
	box.add_child(UI.micro("%s manoeuvre" % label))
	var chosen := _pursuer_move if is_pursuer else _quarry_move
	for entry in _snapshot.get("maneuvers", []):
		var move: Dictionary = entry
		var key := String(move["key"])
		var button := UI.tab_button(String(move["label"]), key == chosen)
		button.disabled = not bool(move["enabled"])
		button.tooltip_text = String(move["summary"])
		button.pressed.connect(
			func() -> void:
				if is_pursuer:
					_pursuer_move = key
				else:
					_quarry_move = key
				_refresh()
		)
		box.add_child(button)
	return box


## Write what the chase did back onto the saved vehicles.
##
## Like the Location screen's roster commit and Netrun's ladder commit, this is
## the GM's own button: a chase is often run twice before it counts.
func commit_damage() -> void:
	if _chase == null:
		return
	for pair in [[_pursuer_vehicle, "pursuer"], [_quarry_vehicle, "quarry"]]:
		var vehicle := Store.vehicle_by_id(String((pair as Array)[0]))
		if vehicle.is_empty():
			continue
		vehicle["sdp"] = int((_snapshot[String((pair as Array)[1])] as Dictionary)["sdp"])
	Store.mark_dirty()
	Store.set_status("Garage updated")
	_message = "Saved the damage onto both vehicles."
	_refresh_card()


# -- refresh ----------------------------------------------------------------------


func _refresh() -> void:
	_refresh_garage()
	_refresh_road()
	_refresh_rail()
	_refresh_card()
	_refresh_header()


func _refresh_header() -> void:
	var state := "%d in the garage" % Store.vehicles().size()
	if _chase != null:
		state = "Gap %d · round %d · %s" % [
			int(_snapshot["gap"]), int(_snapshot["round"]), String(_snapshot["outcome_label"])
		]
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
	head.add_child(UI.micro("Exchange"))
	var tone := UI.TEXT_DISPLAY
	if String(card.get("tone", "")) == "hit":
		tone = UI.ALERT_BRIGHT
	elif String(card.get("tone", "")) == "undo":
		tone = UI.MUTED
	head.add_child(UI.display(String(card["title"]), 24, tone))

	var lines := UI.vbox(0)
	UI.expand(lines, true, false)
	row.add_child(lines)
	for line in card.get("lines", []):
		var label := UI.body(String(line), 11)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(label)
