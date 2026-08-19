extends Control

## Screen 1D — the character forge.
##
## One editor for PCs, named NPCs and mook templates; they differ by a tag, not
## by a screen. The cover builder alongside writes props straight into the
## campaign's palette, which is where screen 1C reads them from.

const TABS: PackedStringArray = [
	"stats", "skills", "gear", "cyberware", "cover"
]

const MATERIAL_COLORS := {
	"Concrete": Color("3b434c"),
	"Steel Plate": Color("4a5666"),
	"Glass": Color("2f5566"),
	"Sheet Metal": Color("5a5f66"),
	"Wood Crate": Color("6a4a26"),
	"Vehicle Hulk": Color("63343a"),
}

const MOOK_FIRST: PackedStringArray = [
	"Wire", "Chrome", "Sixer", "Rat", "Coil", "Dregs", "Static", "Hatch"
]
const MOOK_LAST: PackedStringArray = [
	"Vasquez", "Okoro", "Petrov", "Ng", "Hale", "Duarte", "Sable", "Kovac"
]

var _tab := "stats"
var _roster_box: VBoxContainer
var _sheet_box: VBoxContainer
var _tab_buttons: Dictionary = {}
var _check_rng := Dice.SeededRandom.new(Time.get_ticks_usec())
var _market_message := ""

# Cover builder state.
var _cover_name := "Concrete Jersey Barrier"
var _cover_material := "Concrete"
var _cover_size := Vector3(2.0, 1.2, 1.0)
var _cover_destructible := true
var _preview: _CoverPreview
var _rules_label: Label
var _palette_count: Label
var _dims_label: Label


func _ready() -> void:
	var row := UI.hbox(UI.GAP_3)
	add_child(UI.fill_margins(row, UI.GAP_3))

	row.add_child(_build_roster())
	row.add_child(_build_sheet())
	row.add_child(_build_cover_builder())

	_refresh_roster()
	_refresh_sheet()


# -- roster ---------------------------------------------------------------------


func _build_roster() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(226, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)

	var head := UI.hbox()
	var title := UI.micro("Roster")
	UI.expand(title, true, false)
	head.add_child(title)
	head.add_child(UI.micro(str(Store.characters().size())))
	column.add_child(UI.margins(head, UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_roster_box = UI.vbox(1)
	UI.expand(_roster_box, true, false)
	var wrapper := UI.margins(_roster_box, UI.GAP_2)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	column.add_child(UI.rule_line())
	var actions := UI.vbox(UI.GAP_2)
	var new_button := UI.primary_button("+ New character")
	new_button.pressed.connect(
		func() -> void:
			Store.add_character(_blank_character())
			_refresh_roster()
			_refresh_sheet()
	)
	actions.add_child(new_button)
	var mook_button := UI.plain_button("Roll random mook")
	mook_button.pressed.connect(
		func() -> void:
			Store.add_character(_roll_mook())
			_refresh_roster()
			_refresh_sheet()
	)
	actions.add_child(mook_button)
	column.add_child(UI.margins(actions, UI.GAP_3))

	return shell


func _refresh_roster() -> void:
	for child in _roster_box.get_children():
		child.queue_free()

	for character in Store.characters():
		var entry: Dictionary = character
		var id := String(entry["id"])
		var is_selected := id == Store.active_character_id

		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 42)
		button.focus_mode = Control.FOCUS_NONE
		var style := UI.flat(UI.PANEL_RAISED if is_selected else UI.PANEL_INSET, UI.HAIRLINE, 1, 6)
		if is_selected:
			style.border_color = UI.ACCENT
			style.border_width_left = 2
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.RULE, 1, 6))
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(
			func() -> void:
				Store.active_character_id = id
				_refresh_roster()
				_refresh_sheet()
		)

		var row := UI.hbox(UI.GAP_2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrapper := UI.fill_margins(row, UI.GAP_2)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(wrapper)

		row.add_child(UI.hatch(Vector2(26, 26)))
		var text := UI.vbox(0)
		UI.expand(text, true, false)
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		text.add_child(UI.elide(UI.value(String(entry["name"]), 11)))
		text.add_child(UI.elide(UI.micro(String(entry["role"]))))

		var kind := String(entry.get("kind", "npc"))
		var tag_color := UI.MUTED
		if kind == "pc":
			tag_color = UI.ACCENT
		elif String(entry.get("side", "")) == "hostile":
			tag_color = UI.ALERT_BRIGHT
		var tag := UI.micro("Editing" if is_selected else kind, tag_color)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)

		_roster_box.add_child(button)


# -- sheet ------------------------------------------------------------------------


func _build_sheet() -> Control:
	var shell := UI.panel()
	UI.expand(shell)
	_sheet_box = UI.vbox(0)
	shell.add_child(_sheet_box)
	return shell


func _refresh_sheet() -> void:
	for child in _sheet_box.get_children():
		child.queue_free()

	var character := Store.active_character()
	if character.is_empty():
		_sheet_box.add_child(UI.margins(UI.micro("No character selected"), UI.GAP_4))
		return
	CharacterRules.ensure_character(character)

	_sheet_box.add_child(_build_sheet_head(character))
	_sheet_box.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet_box.add_child(scroll)

	var body := UI.vbox(UI.GAP_2)
	UI.expand(body, true, false)
	var wrapper := UI.margins(body, UI.GAP_4)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	match _tab:
		"stats":
			_build_stats_tab(body, character)
		"skills":
			_build_skills_tab(body, character)
		"gear":
			_build_gear_tab(body, character)
		"cyberware":
			_build_cyberware_tab(body, character)
		"cover":
			var note := UI.body(
				(
					"The cover builder is in the right rail — it stays visible on every tab so a "
					+ "prop can be built while reading a sheet."
				),
				12,
				UI.MUTED,
			)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# Autowrap needs the full width, so clipping has to come back off.
			note.clip_text = false
			body.add_child(note)


func _build_sheet_head(character: Dictionary) -> Control:
	var head := UI.hbox(UI.GAP_3)

	head.add_child(UI.hatch(Vector2(78, 92), "Portrait"))

	var identity := UI.vbox(2)
	UI.expand(identity, true, false)
	head.add_child(identity)
	identity.add_child(UI.micro("Role · %s" % String(character["role"])))

	var name_edit := LineEdit.new()
	name_edit.text = String(character["name"])
	name_edit.flat = true
	name_edit.add_theme_font_override("font", UI.DISPLAY_FONT)
	name_edit.add_theme_font_size_override("font_size", 30)
	name_edit.add_theme_color_override("font_color", UI.TEXT_DISPLAY)
	name_edit.text_changed.connect(
		func(text: String) -> void:
			Store.active_character()["name"] = text
			Store.mark_dirty()
	)
	identity.add_child(name_edit)

	var tags := UI.hbox(UI.GAP_1)
	for tag in character.get("tags", []):
		var tag_panel := UI.panel(UI.PANEL_INSET)
		var color := UI.ALERT_BRIGHT if String(tag) == "HOSTILE" else UI.MUTED
		tag_panel.add_child(UI.margins(UI.micro(String(tag), color), 3))
		tags.add_child(tag_panel)
	identity.add_child(tags)

	var vitals := UI.hbox(UI.GAP_4)
	vitals.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(vitals)

	var hp_box := UI.vbox(1)
	hp_box.alignment = BoxContainer.ALIGNMENT_END
	var hp_label := UI.micro("HP / seriously wounded")
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_box.add_child(hp_label)
	var hp_value := UI.display(
		"%d / %d"
		% [
			int(character["max_hp"]),
			CampaignSchema.serious_wound_threshold(int(character["max_hp"])),
		],
		30,
	)
	hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_box.add_child(hp_value)
	vitals.add_child(hp_box)

	var humanity := int(character["humanity"])
	var max_humanity := int(character["max_humanity"])
	var at_risk := humanity <= max_humanity / 2
	var hum_box := UI.vbox(1)
	var hum_label := UI.micro("Humanity")
	hum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hum_box.add_child(hum_label)
	var hum_value := UI.display(
		"%d / %d" % [humanity, max_humanity], 30, UI.ALERT_BRIGHT if at_risk else UI.TEXT_DISPLAY
	)
	hum_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hum_box.add_child(hum_value)
	var risk := UI.micro("Cyberpsychosis risk" if at_risk else "Stable")
	risk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hum_box.add_child(risk)
	vitals.add_child(hum_box)

	var column := UI.vbox(UI.GAP_2)
	column.add_child(head)

	var tabs := UI.hbox(1)
	for tab in TABS:
		var button := UI.tab_button(tab, tab == _tab)
		button.pressed.connect(
			func() -> void:
				_tab = tab
				_refresh_sheet()
		)
		tabs.add_child(button)
		_tab_buttons[tab] = button
	column.add_child(tabs)

	return UI.margins(column, UI.GAP_4)


func _section_head(title: String, note: String) -> Control:
	var row := UI.hbox()
	var label := UI.micro(title)
	UI.expand(label, true, false)
	row.add_child(label)
	row.add_child(UI.micro(note))
	return row


func _build_stats_tab(body: VBoxContainer, character: Dictionary) -> void:
	_build_role_section(body, character)
	body.add_child(UI.rule_line())
	_build_model_section(body, character)
	body.add_child(UI.rule_line())
	var stats: Dictionary = character["stats"]
	var creating := not bool(character.get("creation_complete", true))
	body.add_child(
		_section_head(
			"Stats",
			"%d / %d creation points" % [CampaignSchema.points_spent(stats), CharacterRules.STAT_POINT_BUDGET]
			if creating
			else "Locked after creation (not improvable with IP)",
		)
	)

	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	body.add_child(grid)

	for key in CampaignSchema.STAT_KEYS:
		var tile := UI.panel(UI.PANEL_INSET)
		var box := UI.vbox(2)
		tile.add_child(UI.margins(box, UI.GAP_1))
		var key_label := UI.micro(key)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(key_label)

		var spin := SpinBox.new()
		spin.min_value = CharacterRules.CREATION_STAT_MIN
		spin.max_value = CharacterRules.CREATION_STAT_MAX
		spin.value = int(stats.get(key, 4))
		spin.editable = creating
		spin.custom_minimum_size = Vector2(40, 0)
		spin.get_line_edit().add_theme_font_override("font", UI.DISPLAY_FONT)
		spin.get_line_edit().add_theme_font_size_override("font_size", 19)
		spin.get_line_edit().add_theme_color_override("font_color", UI.TEXT_DISPLAY)
		spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
		var stat_key := String(key)
		spin.value_changed.connect(
			func(value: float) -> void:
				if CharacterRules.set_stat(Store.active_character(), stat_key, int(value)):
					Store.mark_dirty()
					_refresh_sheet()
				else:
					spin.set_value_no_signal(int((Store.active_character()["stats"] as Dictionary)[stat_key]))
		)
		box.add_child(spin)
		grid.add_child(tile)

	body.add_child(_section_head("Armor · SP by location", "Ablation tracked per hit"))
	var armor_grid := GridContainer.new()
	armor_grid.columns = 6
	armor_grid.add_theme_constant_override("h_separation", 1)
	armor_grid.add_theme_constant_override("v_separation", 1)
	body.add_child(armor_grid)

	var armor: Dictionary = character["armor"]
	for location in Resolver.HIT_LOCATIONS:
		var slot: Dictionary = armor[location]
		var ablated := bool(slot["ablated"])
		var tile := UI.panel(UI.PANEL_INSET, UI.ALERT if ablated else UI.HAIRLINE)
		var box := UI.vbox(2)
		tile.add_child(UI.margins(box, UI.GAP_2))
		box.add_child(UI.micro(String(CampaignSchema.LOCATION_LABELS[location])))
		var value_row := UI.hbox(5)
		value_row.add_child(UI.display(str(int(slot["sp"])), 19))
		var note := UI.micro(
			"Ablated" if ablated else "SP%d" % int(slot["sp"]),
			UI.ALERT_BRIGHT if ablated else UI.MUTED,
		)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_row.add_child(note)
		box.add_child(value_row)
		armor_grid.add_child(tile)


## Pick the 3D model the board draws for this character. Models are glTF files
## the GM drops into the library folder; the board normalizes whatever it finds
## to the declared real-world height, so scale never has to match between them.
func _build_model_section(body: VBoxContainer, character: Dictionary) -> void:
	var models := ModelDB.catalog("character")
	body.add_child(
		_section_head(
			"Board model",
			"%d in the library" % models.size() if ModelDB.has_models() else "Library is empty",
		)
	)
	if models.is_empty():
		var hint := UI.micro("Drop .glb or .gltf files into %s" % ModelDB.library_path())
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 0
		body.add_child(hint)
		return

	var row := UI.hbox(UI.GAP_2)
	var picker := OptionButton.new()
	picker.add_item("Default token")
	picker.set_item_metadata(0, "")
	var current := String(character.get("model_id", ""))
	for index in models.size():
		var model: Dictionary = models[index]
		picker.add_item("%s · %.2gm" % [model["name"], float(model["height_m"])])
		picker.set_item_metadata(index + 1, String(model["id"]))
		if String(model["id"]) == current:
			picker.select(index + 1)
	picker.item_selected.connect(
		func(index: int) -> void:
			Store.active_character()["model_id"] = String(picker.get_item_metadata(index))
			Store.mark_dirty()
			_refresh_sheet()
	)
	UI.expand(picker, true, false)
	row.add_child(picker)

	var rescan := UI.plain_button("Rescan library")
	rescan.pressed.connect(
		func() -> void:
			ModelDB.reload()
			_refresh_sheet()
	)
	row.add_child(rescan)
	body.add_child(row)


func _build_role_section(body: VBoxContainer, character: Dictionary) -> void:
	var role_key := String(character.get("role_key", ""))
	var profile := CharacterRules.role(role_key)
	var ability: Dictionary = character.get("role_ability", {})
	var creating := not bool(character.get("creation_complete", true))
	var ip := int(character.get("improvement_points", 0))
	body.add_child(_section_head("Role & ability", "%d IP available" % ip))

	var editor := UI.hbox(UI.GAP_2)
	var picker := OptionButton.new()
	UI.expand(picker, true, false)
	picker.add_item("Choose a role…")
	picker.set_item_metadata(0, "")
	for index in CharacterRules.ROLES.size():
		var entry: Dictionary = CharacterRules.ROLES[index]
		picker.add_item("%s · %s" % [entry["name"], entry["ability"]])
		picker.set_item_metadata(index + 1, entry["key"])
		if String(entry["key"]) == role_key:
			picker.select(index + 1)
	picker.item_selected.connect(
		func(index: int) -> void:
			CharacterRules.select_role(
				Store.active_character(), String(picker.get_item_metadata(index))
			)
			Store.mark_dirty()
			_refresh_roster()
			_refresh_sheet()
	)
	picker.disabled = not creating
	editor.add_child(picker)

	var rank := SpinBox.new()
	rank.min_value = 1
	rank.max_value = 10
	rank.value = maxi(1, int(ability.get("rank", 4)))
	rank.prefix = "Rank "
	rank.custom_minimum_size = Vector2(110, 0)
	rank.editable = false
	editor.add_child(rank)
	if not creating and not profile.is_empty() and int(ability.get("rank", 0)) < 10:
		var improve := UI.primary_button("Improve · %d IP" % CharacterRules.role_ip_cost(character))
		improve.pressed.connect(
			func() -> void:
				if CharacterRules.improve_role(Store.active_character()):
					Store.mark_dirty()
					_refresh_sheet()
		)
		editor.add_child(improve)
	body.add_child(editor)

	if creating:
		var status := CharacterRules.creation_status(character)
		var finish := UI.primary_button(
			"Finish creation · Stats %d/%d · Skills %d/%d"
			% [status["stat_spent"], status["stat_maximum"], status["skill_spent"], status["skill_maximum"]]
		)
		finish.disabled = (
			int(status["stat_spent"]) != int(status["stat_maximum"])
			or int(status["skill_spent"]) != int(status["skill_maximum"])
			or profile.is_empty()
		)
		finish.tooltip_text = "Choose a Role and spend exactly the Complete Package point budgets."
		finish.pressed.connect(
			func() -> void:
				if CharacterRules.finish_creation(Store.active_character()):
					Store.mark_dirty()
					_refresh_sheet()
		)
		body.add_child(finish)
	else:
		var ip_editor := SpinBox.new()
		ip_editor.min_value = 0
		ip_editor.max_value = 99999
		ip_editor.value = ip
		ip_editor.prefix = "Available IP "
		ip_editor.tooltip_text = "Record IP awarded by the GM. Improvements deduct from this pool."
		ip_editor.value_changed.connect(
			func(value: float) -> void:
				Store.active_character()["improvement_points"] = int(value)
				Store.mark_dirty()
		)
		body.add_child(ip_editor)

	if profile.is_empty():
		body.add_child(UI.micro("Choose one of the ten Roles to configure its Role Ability."))
		return

	var summary := UI.body(String(profile["summary"]), 11, UI.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.clip_text = false
	body.add_child(summary)
	for effect in CharacterRules.role_effects(character):
		body.add_child(UI.micro(String(effect), UI.ACCENT))

	_build_role_allocations(body, character)
	_build_role_roller(body, character)


func _build_role_allocations(body: VBoxContainer, character: Dictionary) -> void:
	var role_key := String(character.get("role_key", ""))
	var ability: Dictionary = character["role_ability"]
	var rank := int(ability["rank"])
	var options: Dictionary = ability["options"]
	var fields: Array[Dictionary] = []
	if role_key == "solo":
		for key in CharacterRules.SOLO_ALLOCATIONS:
			var definition: Dictionary = CharacterRules.SOLO_ALLOCATIONS[key]
			fields.append(
				{
					"key": key,
					"label": definition["label"],
					"step": definition["step"],
					"maximum": rank,
				}
			)
	elif role_key == "tech":
		for key in CharacterRules.MAKER_SPECIALTIES:
			fields.append(
				{
					"key": key,
					"label": CharacterRules.MAKER_SPECIALTIES[key],
					"step": 1,
					"maximum": rank,
				}
			)
	elif role_key == "medtech":
		fields = [
			{"key": "surgery", "label": "Surgery", "step": 1, "maximum": 5},
			{"key": "pharmaceuticals", "label": "Pharmaceuticals", "step": 1, "maximum": 5},
			{"key": "cryosystems", "label": "Cryosystem Operation", "step": 1, "maximum": 5},
		]
	if fields.is_empty():
		return

	var budget := CharacterRules.role_option_budget(character)
	body.add_child(
		_section_head(
			"Ability allocation", "%d / %d points" % [budget["spent"], budget["maximum"]]
		)
	)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UI.GAP_2)
	grid.add_theme_constant_override("v_separation", UI.GAP_1)
	body.add_child(grid)
	for field in fields:
		var row := UI.hbox(UI.GAP_2)
		UI.expand(row, true, false)
		var label := UI.micro(String(field["label"]))
		UI.expand(label, true, false)
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = int(field["maximum"])
		spin.step = int(field["step"])
		spin.value = int(options.get(String(field["key"]), 0))
		spin.custom_minimum_size = Vector2(76, 0)
		var option_key := String(field["key"])
		spin.value_changed.connect(
			func(value: float) -> void:
				if CharacterRules.set_role_option(
					Store.active_character(), option_key, int(value)
				):
					Store.mark_dirty()
					_refresh_sheet()
				else:
					spin.set_value_no_signal(
						int(
							(
								Store.active_character()["role_ability"]["options"]
								as Dictionary
							).get(option_key, 0)
						)
					)
		)
		row.add_child(spin)
		grid.add_child(row)


func _build_role_roller(body: VBoxContainer, character: Dictionary) -> void:
	var options := CharacterRules.role_roll_options(character)
	body.add_child(UI.rule_line())
	body.add_child(_section_head("Role Ability check", "Modifiers are cumulative"))
	if options.is_empty():
		body.add_child(
			UI.micro(
				"This ability grants persistent or allocated effects; it does not use a Role Ability roll."
			)
		)
		return

	var row := UI.hbox(UI.GAP_2)
	var action := OptionButton.new()
	UI.expand(action, true, false)
	for index in options.size():
		var option: Dictionary = options[index]
		action.add_item(String(option["label"]))
		action.set_item_metadata(index, option)
	row.add_child(action)
	var modifier := _modifier_spin()
	row.add_child(modifier)
	var dv := _dv_spin(0)
	dv.tooltip_text = "0 uses the Role Ability's built-in DV or makes an open check."
	row.add_child(dv)
	var roll := UI.primary_button("Roll")
	row.add_child(roll)
	body.add_child(row)
	var result := UI.body("No Role Ability check rolled yet.", 11, UI.MUTED)
	body.add_child(result)
	roll.pressed.connect(
		func() -> void:
			var rolled := CharacterRules.roll_role(
				Store.active_character(),
				action.get_item_metadata(action.selected),
				int(modifier.value),
				int(dv.value),
				_check_rng,
			)
			_show_roll_result(result, rolled)
	)


func _build_skills_tab(body: VBoxContainer, character: Dictionary) -> void:
	CharacterRules.ensure_character(character)
	var stats: Dictionary = character["stats"]
	var skills: Array = character.get("skills", [])
	var creating := not bool(character.get("creation_complete", true))
	body.add_child(
		_section_head(
			"Skill checks",
			("%d / %d creation points" % [CharacterRules.skill_points(character), CharacterRules.SKILL_POINT_BUDGET]) if creating else "%d IP available · STAT + Skill + 1d10" % int(character.get("improvement_points", 0)),
		)
	)
	var check_row := UI.hbox(UI.GAP_2)
	var selected := OptionButton.new()
	UI.expand(selected, true, false)
	for index in skills.size():
		var listed: Dictionary = skills[index]
		selected.add_item(
			"%s · %s +%d"
			% [listed["name"], listed["stat"], CampaignSchema.skill_total(stats, listed)]
		)
		selected.set_item_metadata(index, listed["name"])
	if skills.is_empty():
		selected.add_item("Add a Skill to roll")
		selected.disabled = true
	check_row.add_child(selected)
	var modifier := _modifier_spin()
	check_row.add_child(modifier)
	var dv := _dv_spin(13)
	check_row.add_child(dv)
	var roll := UI.primary_button("Roll")
	roll.disabled = skills.is_empty()
	check_row.add_child(roll)
	body.add_child(check_row)
	var result := UI.body("No Skill Check rolled yet.", 11, UI.MUTED)
	body.add_child(result)
	roll.pressed.connect(
		func() -> void:
			var rolled := CharacterRules.roll_skill(
				Store.active_character(),
				String(selected.get_item_metadata(selected.selected)),
				int(modifier.value),
				int(dv.value),
				_check_rng,
			)
			_show_roll_result(result, rolled)
	)

	body.add_child(UI.rule_line())
	body.add_child(_section_head("Chosen Skills", "Creation maximum Level 6" if creating else "Raise one Level at a time with IP"))
	if skills.is_empty():
		body.add_child(UI.micro("No Skills selected."))
	for skill in skills:
		var entry: Dictionary = skill
		body.add_child(UI.rule_line())
		var row := UI.hbox(UI.GAP_2)
		var name_label := UI.body(String(entry["name"]), 12)
		UI.expand(name_label, true, false)
		row.add_child(name_label)
		row.add_child(
			UI.micro(
				"%s%s" % [entry["stat"], " · x2" if bool(entry.get("x2", false)) else ""]
			)
		)
		var level := SpinBox.new()
		level.min_value = 2 if CharacterRules.BASIC_SKILLS.has(String(entry["name"])) else 0
		level.max_value = CharacterRules.CREATION_SKILL_MAX if creating else mini(10, int(entry["level"]) + 1)
		level.value = int(entry["level"])
		level.prefix = "Lv "
		if not creating and int(entry["level"]) < 10:
			level.tooltip_text = "Next Level costs %d IP%s" % [CharacterRules.skill_ip_cost(entry), " (x2 Skill)" if bool(entry.get("x2", false)) else ""]
		level.custom_minimum_size = Vector2(88, 0)
		row.add_child(level)
		var total := UI.value("+%d" % CampaignSchema.skill_total(stats, entry), 11, UI.ACCENT)
		total.custom_minimum_size = Vector2(40, 0)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(total)
		level.value_changed.connect(
			func(value: float) -> void:
				if CharacterRules.set_skill_level(Store.active_character(), String(entry["name"]), int(value)):
					Store.mark_dirty()
					_refresh_sheet()
				else:
					level.set_value_no_signal(int(entry["level"]))
		)
		var remove := UI.plain_button("Remove")
		remove.disabled = CharacterRules.BASIC_SKILLS.has(String(entry["name"])) or not creating
		remove.tooltip_text = "Basic Skills are required." if remove.disabled else "Remove this Skill."
		remove.pressed.connect(
			func() -> void:
				if CharacterRules.remove_skill(
					Store.active_character(), String(entry["name"])
				):
					Store.mark_dirty()
					_refresh_sheet()
		)
		row.add_child(remove)
		body.add_child(UI.margins(row, 3))

	body.add_child(UI.rule_line())
	body.add_child(_section_head("Add a Skill", "x2 Skills cost twice as many points"))
	var add_row := UI.hbox(UI.GAP_2)
	var add_picker := OptionButton.new()
	UI.expand(add_picker, true, false)
	var available: Array[Dictionary] = []
	for definition in CharacterRules.SKILLS:
		var base_name := String((definition as Dictionary)["name"])
		if bool((definition as Dictionary).get("specialized", false)) or CharacterRules.selected_skill(
			character, base_name
		).is_empty():
			available.append(definition)
	for index in available.size():
		var definition: Dictionary = available[index]
		add_picker.add_item(
			"%s · %s%s"
			% [
				definition["name"],
				definition["stat"],
				" · x2" if bool(definition.get("x2", false)) else "",
			]
		)
		add_picker.set_item_metadata(index, definition)
	add_row.add_child(add_picker)
	var specialty := LineEdit.new()
	specialty.placeholder_text = "Specialty"
	specialty.custom_minimum_size = Vector2(135, 0)
	add_row.add_child(specialty)
	var new_level := SpinBox.new()
	new_level.min_value = 0
	new_level.max_value = CharacterRules.CREATION_SKILL_MAX
	new_level.value = 0
	new_level.prefix = "Lv "
	new_level.custom_minimum_size = Vector2(88, 0)
	add_row.add_child(new_level)
	var add_button := UI.primary_button("Add")
	add_button.disabled = not creating
	add_row.add_child(add_button)
	body.add_child(add_row)
	var add_status := UI.micro("Specialized Skills require a subject.")
	body.add_child(add_status)
	var refresh_specialty := func(index: int) -> void:
		var definition: Dictionary = add_picker.get_item_metadata(index)
		specialty.editable = bool(definition.get("specialized", false))
		if not specialty.editable:
			specialty.text = ""
	refresh_specialty.call(0)
	add_picker.item_selected.connect(refresh_specialty)
	add_button.pressed.connect(
		func() -> void:
			var definition: Dictionary = add_picker.get_item_metadata(add_picker.selected)
			if CharacterRules.add_skill(
				Store.active_character(),
				String(definition["name"]),
				int(new_level.value),
				specialty.text,
			):
				Store.mark_dirty()
				_refresh_sheet()
			else:
				add_status.text = "Choose a specialty or select a Skill not already on the sheet."
				add_status.add_theme_color_override("font_color", UI.WARN)
	)


func _modifier_spin() -> SpinBox:
	var modifier := SpinBox.new()
	modifier.min_value = -20
	modifier.max_value = 20
	modifier.value = 0
	modifier.prefix = "Mod "
	modifier.custom_minimum_size = Vector2(100, 0)
	return modifier


func _dv_spin(initial: int) -> SpinBox:
	var dv := SpinBox.new()
	dv.min_value = 0
	dv.max_value = 40
	dv.value = initial
	dv.prefix = "DV "
	dv.custom_minimum_size = Vector2(92, 0)
	return dv


func _show_roll_result(label: Label, result: Dictionary) -> void:
	label.text = CharacterRules.format_result(result)
	var color := UI.WARN
	if bool(result.get("ok", false)):
		var success: Variant = result.get("success", null)
		color = UI.ACCENT if success == null else (UI.GOOD if bool(success) else UI.ALERT_BRIGHT)
	label.add_theme_color_override("font_color", color)


func _build_gear_tab(body: VBoxContainer, character: Dictionary) -> void:
	Lifestyle.ensure_character(character)
	var selected_lifestyle := Lifestyle.profile(String(character["lifestyle"]))
	body.add_child(
		_section_head(
			"Lifestyle & cash",
			"%s · %deb/month" % [selected_lifestyle["label"], selected_lifestyle["cost"]],
		)
	)
	var lifestyle_row := UI.hbox(UI.GAP_2)
	var picker := OptionButton.new()
	UI.expand(picker, true, false)
	for index in Lifestyle.CATALOG.size():
		var entry: Dictionary = Lifestyle.CATALOG[index]
		picker.add_item("%s · %deb/month" % [entry["label"], entry["cost"]])
		picker.set_item_metadata(index, entry["key"])
		if String(entry["key"]) == String(character["lifestyle"]):
			picker.select(index)
	picker.item_selected.connect(
		func(index: int) -> void:
			Store.active_character()["lifestyle"] = String(picker.get_item_metadata(index))
			Store.mark_dirty()
			_refresh_sheet()
	)
	lifestyle_row.add_child(picker)
	var cash := SpinBox.new()
	cash.min_value = 0
	cash.max_value = 1_000_000
	cash.step = 1
	cash.value = int(character["cash"])
	cash.suffix = " eb"
	cash.custom_minimum_size = Vector2(150, 0)
	cash.value_changed.connect(
		func(value: float) -> void:
			Store.active_character()["cash"] = int(value)
			Store.mark_dirty()
	)
	lifestyle_row.add_child(cash)
	body.add_child(lifestyle_row)
	var payment := "Status · %s" % String(character["lifestyle_status"]).to_upper()
	if String(character["lifestyle_status"]) == "unpaid":
		payment += " · %deb due · %d grace days" % [
			int(character["lifestyle_balance_due"]), int(character.get("lifestyle_grace_days", 0))
		]
	elif character.get("lifestyle_paid_through") != null:
		payment += " · paid through %s" % character["lifestyle_paid_through"]
	body.add_child(UI.micro(payment, UI.WARN if String(character["lifestyle_status"]) == "unpaid" else UI.GOOD))
	body.add_child(UI.rule_line())

	var gear: Array = character.get("gear", [])
	body.add_child(
		_section_head("Gear & cyberware", "%d humanity spent" % CampaignSchema.humanity_spent(gear))
	)
	if gear.is_empty():
		body.add_child(UI.micro("Nothing carried."))
		return
	for item in gear:
		var entry: Dictionary = item
		body.add_child(UI.rule_line())
		var row := UI.hbox(UI.GAP_2)
		var name_label := UI.body(String(entry["name"]), 12)
		UI.expand(name_label, true, false)
		row.add_child(name_label)
		row.add_child(UI.micro(String(entry.get("kind", ""))))
		var detail := UI.body(String(entry.get("detail", "")), 11, UI.MUTED)
		detail.custom_minimum_size = Vector2(150, 0)
		row.add_child(detail)
		var cost := int(entry.get("humanity_cost", 0))
		var cost_label := UI.value("%d HUM" % cost if cost > 0 else "", 11, UI.WARN)
		cost_label.custom_minimum_size = Vector2(60, 0)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cost_label)
		body.add_child(UI.margins(row, 3))


func _build_cyberware_tab(body: VBoxContainer, character: Dictionary) -> void:
	var spent := int(character.get("max_humanity", 0)) - int(character.get("humanity", 0))
	body.add_child(
		_section_head(
			"Cyberware attachment",
			"%d / %d Humanity · %d lost" % [character["humanity"], character["max_humanity"], spent],
		)
	)
	body.add_child(
		UI.micro("Buy implants in the Market, then attach one to a compatible empty body part. Detaching does not restore Humanity.", UI.WARN)
	)
	if _market_message != "":
		var message_color := (
			UI.GOOD
			if _market_message.begins_with("Attached") or _market_message.begins_with("Detached")
			else UI.ALERT_BRIGHT
		)
		body.add_child(UI.body(_market_message, 12, message_color))
	var gear: Array = character.get("gear", [])
	for part in GearMarket.BODY_PARTS:
		var part_id := String(part["id"])
		body.add_child(UI.rule_line())
		var row := UI.hbox(UI.GAP_2)
		var label := UI.body(String(part["label"]), 12)
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		var installed := GearMarket.installed_at(character, part_id)
		if installed >= 0:
			var implant: Dictionary = gear[installed]
			var installed_label := UI.body(
				"%s · %d Humanity" % [implant["name"], int(implant.get("humanity_cost", 0))], 12
			)
			UI.expand(installed_label, true, false)
			row.add_child(installed_label)
			var detach := UI.plain_button("Detach")
			detach.pressed.connect(_detach_cyberware.bind(part_id))
			row.add_child(detach)
		else:
			var picker := OptionButton.new()
			UI.expand(picker, true, false)
			picker.add_item("Choose owned cyberware…")
			picker.set_item_metadata(0, -1)
			for index in gear.size():
				var entry: Dictionary = gear[index]
				if GearMarket.can_install(entry, part_id):
					picker.add_item("%s · -%d Humanity" % [entry["name"], int(entry.get("humanity_cost", 0))])
					picker.set_item_metadata(picker.item_count - 1, index)
			row.add_child(picker)
			var attach := UI.primary_button("Attach")
			attach.disabled = picker.item_count == 1
			picker.item_selected.connect(func(index: int) -> void: attach.disabled = index == 0)
			attach.pressed.connect(_install_cyberware.bind(picker, part_id))
			row.add_child(attach)
		body.add_child(row)


func _install_cyberware(picker: OptionButton, body_part: String) -> void:
	var gear_index := int(picker.get_item_metadata(picker.selected))
	var result := GearMarket.install_cyberware(Store.active_character(), gear_index, body_part)
	_market_message = (
		"Attached %s · %d Humanity lost." % [result["item"], result["humanity_loss"]]
		if bool(result.get("ok", false))
		else String(result.get("error", "Installation failed."))
	)
	if bool(result.get("ok", false)):
		Store.mark_dirty()
	_refresh_sheet()


func _detach_cyberware(body_part: String) -> void:
	var result := GearMarket.detach_cyberware(Store.active_character(), body_part)
	_market_message = (
		"Detached %s. Humanity is not restored." % result["item"]
		if bool(result.get("ok", false))
		else String(result.get("error", "Detach failed."))
	)
	if bool(result.get("ok", false)):
		Store.mark_dirty()
	_refresh_sheet()


# -- cover builder -------------------------------------------------------------------


func _build_cover_builder() -> Control:
	var shell := UI.panel()
	shell.custom_minimum_size = Vector2(286, 0)
	UI.expand(shell, false, true)

	var column := UI.vbox(0)
	shell.add_child(column)

	var head := UI.hbox()
	var title := UI.micro("Cover builder")
	UI.expand(title, true, false)
	head.add_child(title)
	_palette_count = UI.micro("%d in palette" % Store.cover_palette().size())
	head.add_child(_palette_count)
	column.add_child(UI.margins(head, UI.GAP_3))
	column.add_child(UI.rule_line())

	var scroll := ScrollContainer.new()
	UI.expand(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var box := UI.vbox(UI.GAP_2)
	UI.expand(box, true, false)
	var wrapper := UI.margins(box, UI.GAP_3)
	UI.expand(wrapper, true, false)
	scroll.add_child(wrapper)

	var preview_frame := UI.panel(UI.PANEL_INSET)
	preview_frame.custom_minimum_size = Vector2(0, 150)
	box.add_child(preview_frame)
	_preview = _CoverPreview.new()
	preview_frame.add_child(_preview)
	_dims_label = UI.micro("")
	_dims_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dims_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dims_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	preview_frame.add_child(_dims_label)

	box.add_child(UI.micro("Name"))
	var name_edit := LineEdit.new()
	name_edit.text = _cover_name
	name_edit.text_changed.connect(func(text: String) -> void: _cover_name = text)
	box.add_child(name_edit)

	box.add_child(_slider("Height", _cover_size.y, 0.3, 4.0, func(v: float) -> void: _cover_size.y = v))
	box.add_child(_slider("Width", _cover_size.x, 0.3, 6.0, func(v: float) -> void: _cover_size.x = v))
	box.add_child(_slider("Depth", _cover_size.z, 0.3, 4.0, func(v: float) -> void: _cover_size.z = v))

	var destructible_row := UI.hbox()
	var destructible_label := UI.micro("Destructible")
	UI.expand(destructible_label, true, false)
	destructible_row.add_child(destructible_label)
	var check := CheckBox.new()
	check.button_pressed = _cover_destructible
	check.toggled.connect(
		func(on: bool) -> void:
			_cover_destructible = on
			_refresh_cover()
	)
	destructible_row.add_child(check)
	box.add_child(destructible_row)

	box.add_child(UI.micro("Material"))
	var materials := GridContainer.new()
	materials.columns = 2
	materials.add_theme_constant_override("h_separation", 1)
	materials.add_theme_constant_override("v_separation", 1)
	box.add_child(materials)

	var tables := TablesDefault.tables()
	for material_name in tables.cover_names():
		var profile := tables.cover(String(material_name))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 42)
		button.focus_mode = Control.FOCUS_NONE
		# A GridContainer only widens a column when its child asks to expand;
		# without this every tile collapses to zero and they draw on top of
		# each other.
		UI.expand(button, true, false)
		var key := String(material_name)
		var selected := key == _cover_material
		button.add_theme_stylebox_override(
			"normal",
			UI.flat(
				UI.PANEL_RAISED if selected else UI.PANEL_INSET,
				UI.ACCENT if selected else UI.HAIRLINE,
				1,
				6,
			),
		)
		button.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_RAISED, UI.ACCENT_FILL, 1, 6))
		button.pressed.connect(
			func() -> void:
				_cover_material = key
				_refresh_sheet()
				_rebuild_material_buttons(materials)
				_refresh_cover()
		)
		var inner := UI.vbox(1)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner_wrapper := UI.fill_margins(inner, UI.GAP_2)
		inner_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(inner_wrapper)
		inner.add_child(UI.value(key.to_upper(), 10))
		inner.add_child(UI.elide(UI.micro("SP %d · %d HP" % [int(profile["sp"]), int(profile["hp"])])))
		materials.add_child(button)

	var rules_panel := UI.panel(UI.PANEL_INSET)
	var rules_box := UI.vbox(2)
	rules_panel.add_child(UI.margins(rules_box, UI.GAP_2))
	rules_box.add_child(UI.micro("Rules effect"))
	_rules_label = UI.body("", 11, UI.MUTED)
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs the full width, so clipping has to come back off.
	_rules_label.clip_text = false
	rules_box.add_child(_rules_label)
	box.add_child(rules_panel)

	var actions := UI.hbox(UI.GAP_2)
	var save_button := UI.primary_button("Save to palette")
	UI.expand(save_button, true, false)
	save_button.pressed.connect(
		func() -> void:
			Store.add_cover(_build_cover())
			_palette_count.text = UI._letterspace(
				"%d IN PALETTE" % Store.cover_palette().size()
			)
	)
	actions.add_child(save_button)
	var place_button := UI.plain_button("Place on map")
	UI.expand(place_button, true, false)
	place_button.disabled = Store.active_location().is_empty()
	place_button.pressed.connect(
		func() -> void:
			var cover := _build_cover()
			Store.add_cover(cover)
			var location := Store.active_location()
			(location["props"] as Array).append(
				{
					"id": "prop-%d" % Time.get_ticks_usec(),
					"cover_id": String(cover["id"]),
					"x": int(location["grid_width"]) / 2,
					"z": int(location["grid_height"]) / 2,
					"layer": 0,
					"rotation": 0,
					"hp": int(cover["hp"]),
				}
			)
			Store.mark_dirty()
			_palette_count.text = UI._letterspace("%d IN PALETTE" % Store.cover_palette().size())
	)
	actions.add_child(place_button)
	box.add_child(actions)

	_refresh_cover()
	return shell


func _rebuild_material_buttons(_grid: GridContainer) -> void:
	# Rebuilding the whole rail keeps the selected-state styling in one place.
	for child in get_children():
		child.queue_free()
	_ready()


func _slider(label: String, value: float, minimum: float, maximum: float, on_change: Callable) -> Control:
	var row := UI.hbox(UI.GAP_2)
	var key := UI.micro(label)
	key.custom_minimum_size = Vector2(46, 0)
	row.add_child(key)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.1
	slider.value = value
	UI.expand(slider, true, false)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := UI.micro("%.1f m" % value)
	readout.custom_minimum_size = Vector2(44, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)

	slider.value_changed.connect(
		func(new_value: float) -> void:
			on_change.call(new_value)
			readout.text = UI._letterspace("%.1f M" % new_value)
			_refresh_cover()
	)
	return row


## Bigger cover has more to chew through: the printed HP is for a nominal
## 2 × 1 × 1.2 m block and scales with volume from there.
func _cover_hp() -> int:
	var profile := TablesDefault.tables().cover(_cover_material)
	var volume_factor := (_cover_size.x * _cover_size.y * _cover_size.z) / (2.0 * 1.2 * 1.0)
	return maxi(1, roundi(float(profile["hp"]) * volume_factor))


func _build_cover() -> Dictionary:
	var profile := TablesDefault.tables().cover(_cover_material)
	return {
		"id": "cover-%d" % Time.get_ticks_usec(),
		"name": _cover_name.strip_edges() if _cover_name.strip_edges() != "" else _cover_material,
		"material": _cover_material,
		"height": _cover_size.y,
		"width": _cover_size.x,
		"depth": _cover_size.z,
		"sp": int(profile["sp"]),
		"hp": _cover_hp(),
		"destructible": _cover_destructible,
	}


func _refresh_cover() -> void:
	if _preview != null:
		_preview.configure(_cover_size, MATERIAL_COLORS.get(_cover_material, Color("3b434c")))
	if _dims_label != null:
		_dims_label.text = UI._letterspace(
			"%.1f × %.1f × %.1f M" % [_cover_size.x, _cover_size.z, _cover_size.y]
		)
	if _rules_label != null:
		var profile := TablesDefault.tables().cover(_cover_material)
		_rules_label.text = (
			"Blocks line of sight above %.1f m. The barrier absorbs damage at SP %d and has %d HP at this size. %s"
			% [
				_cover_size.y,
				int(profile["sp"]),
				_cover_hp(),
				(
					"It ablates as it takes hits and fails when its HP reaches zero."
					if _cover_destructible
					else "It is marked indestructible and will not fail."
				),
			]
		)


# -- character creation ------------------------------------------------------------


func _blank_character() -> Dictionary:
	var character := {
		"id": "character-%d" % Time.get_ticks_usec(),
		"name": "New Character",
		"role": "Unset",
		"role_key": "",
		"role_ability": {"name": "", "rank": 0, "options": {}},
		"creation_complete": false,
		"improvement_points": 0,
		"model_id": "",
		"kind": "pc",
		"side": "party",
		"tags": ["PC"],
		"stats": CampaignSchema.empty_stats(),
		"skills": CharacterRules.new_character_skills(),
		"gear": [],
		"armor": CampaignSchema.empty_armor(),
		"hp": 30,
		"max_hp": 30,
		"humanity": 40,
		"max_humanity": 50,
		"cash": 0,
		"lifestyle": "kibble",
		"lifestyle_status": "paid",
		"lifestyle_paid_through": null,
		"lifestyle_balance_due": 0,
		"lifestyle_grace_days": 0,
		"last_lifestyle_charge": null,
		"weapons": [],
	}
	CharacterRules.ensure_character(character)
	return character


func _roll_mook() -> Dictionary:
	var stats := CampaignSchema.empty_stats()
	for key in CampaignSchema.STAT_KEYS:
		stats[key] = randi_range(3, 6)
	var max_hp := randi_range(20, 32)
	var sp := randi_range(4, 11)
	var armor := CampaignSchema.empty_armor()
	for location in Resolver.HIT_LOCATIONS:
		armor[location] = {"sp": sp, "ablated": false}

	return {
		"id": "mook-%d" % Time.get_ticks_usec(),
		"name": "%s %s" % [MOOK_FIRST[randi() % MOOK_FIRST.size()], MOOK_LAST[randi() % MOOK_LAST.size()]],
		"role": "Mook",
		"kind": "mook",
		"side": "hostile",
		"tags": ["MOOK", "ROLLED"],
		"stats": stats,
		"skills":
		[
			{"name": "Handgun", "stat": "REF", "level": randi_range(2, 5)},
			{"name": "Evasion", "stat": "DEX", "level": randi_range(1, 3)},
		],
		"gear": [{"name": "Service Sidearm", "kind": "weapon", "detail": "2d6"}],
		"armor": armor,
		"hp": max_hp,
		"max_hp": max_hp,
		"humanity": 30,
		"max_humanity": 40,
		"weapons":
		[
			{
				"name": "Service Sidearm",
				"ammo": 12,
				"magazine": 12,
				"weapon_type": "pistol",
				"damage_dice": 2,
				"rof": 2,
				"autofire_rating": -1,
			}
		],
	}


## A live isometric preview of the cover being built.
##
## Its own small 3D scene rather than a second IsoBoard: it needs one box on a
## plinth, not a grid, picking or effects.
class _CoverPreview extends SubViewportContainer:
	var _box: MeshInstance3D
	var _material := StandardMaterial3D.new()

	func _init() -> void:
		stretch = true
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		var viewport := SubViewport.new()
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)

		var root := Node3D.new()
		viewport.add_child(root)

		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 4.6
		camera.look_at_from_position(Vector3(6, 6, 6), Vector3(0, 0.6, 0), Vector3.UP)
		root.add_child(camera)

		var environment := WorldEnvironment.new()
		var world := Environment.new()
		world.background_mode = Environment.BG_COLOR
		world.background_color = UI.PANEL_INSET
		world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.ambient_light_color = Color("8fa8c4")
		world.ambient_light_energy = 1.7
		environment.environment = world
		root.add_child(environment)

		var key := DirectionalLight3D.new()
		key.light_color = Color("d6e6f7")
		key.light_energy = 2.2
		key.rotation_degrees = Vector3(-52, -38, 0)
		root.add_child(key)

		var plinth := MeshInstance3D.new()
		var plinth_mesh := BoxMesh.new()
		plinth_mesh.size = Vector3(4, 0.08, 4)
		plinth.mesh = plinth_mesh
		var plinth_material := StandardMaterial3D.new()
		plinth_material.albedo_color = Color("121a24")
		plinth_material.roughness = 0.95
		plinth.material_override = plinth_material
		plinth.position = Vector3(0, -0.04, 0)
		root.add_child(plinth)

		_material.roughness = 0.65
		_material.metallic = 0.25
		_box = MeshInstance3D.new()
		_box.mesh = BoxMesh.new()
		_box.material_override = _material
		root.add_child(_box)

	func configure(dimensions: Vector3, color: Color) -> void:
		var box: BoxMesh = _box.mesh
		box.size = Vector3(
			maxf(0.1, dimensions.x), maxf(0.1, dimensions.y), maxf(0.1, dimensions.z)
		)
		_box.position = Vector3(0, maxf(0.1, dimensions.y) * 0.5, 0)
		_material.albedo_color = color
