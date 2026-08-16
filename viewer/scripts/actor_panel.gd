class_name ActorPanel
extends PanelContainer

## One combatant's live status: HP, armour, cover, ammo and standing injuries.

const FLASH_SECONDS := 0.45

var actor_id: String = ""

var _name_label: Label
var _state_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _chips: HBoxContainer
var _weapons: HBoxContainer
var _injuries: Label
var _last_hp: int = 0
var _seeded := false


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style())
	custom_minimum_size = Vector2(460, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.add_theme_color_override("font_color", Palette.TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_name_label)

	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 18)
	_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(_state_label)

	var health := HBoxContainer.new()
	health.add_theme_constant_override("separation", 12)
	column.add_child(health)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 18)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.add_theme_stylebox_override("background", Palette.bar_style(Color(1, 1, 1, 0.10)))
	health.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 22)
	_hp_label.add_theme_color_override("font_color", Palette.TEXT)
	health.add_child(_hp_label)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	column.add_child(_chips)

	_weapons = HBoxContainer.new()
	_weapons.add_theme_constant_override("separation", 8)
	column.add_child(_weapons)

	_injuries = Label.new()
	_injuries.add_theme_font_size_override("font_size", 18)
	_injuries.add_theme_color_override("font_color", Palette.DANGER)
	_injuries.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_injuries.visible = false
	column.add_child(_injuries)


func update_actor(actor: Dictionary) -> void:
	actor_id = String(actor.get("id", ""))
	var hp := int(actor.get("hp", 0))
	var max_hp := maxi(1, int(actor.get("max_hp", 1)))

	_name_label.text = String(actor.get("name", actor_id))
	_hp_bar.max_value = max_hp
	_hp_bar.value = clampi(hp, 0, max_hp)
	_hp_bar.add_theme_stylebox_override("fill", Palette.bar_style(Palette.health_color(hp, max_hp)))
	_hp_label.text = "%d / %d" % [hp, max_hp]
	_hp_label.add_theme_color_override("font_color", Palette.health_color(hp, max_hp))

	_state_label.text = _state_text(actor)
	_state_label.add_theme_color_override("font_color", _state_color(actor))
	_state_label.visible = _state_label.text != ""

	_rebuild_chips(actor)
	_rebuild_weapons(actor)

	var injuries: Array = actor.get("critical_injuries", [])
	_injuries.text = "Critical: %s" % ", ".join(PackedStringArray(injuries))
	_injuries.visible = not injuries.is_empty()

	if _seeded and hp != _last_hp:
		_flash(Palette.DANGER if hp < _last_hp else Palette.GOOD)
	_last_hp = hp
	_seeded = true


func _state_text(actor: Dictionary) -> String:
	if bool(actor.get("death_save_due", false)):
		return "DEATH SAVE"
	if String(actor.get("wound_state", "unhurt")) == "seriously_wounded":
		return "SERIOUSLY WOUNDED"
	return ""


func _state_color(actor: Dictionary) -> Color:
	return Palette.DANGER if bool(actor.get("death_save_due", false)) else Palette.WARN


func _rebuild_chips(actor: Dictionary) -> void:
	for child in _chips.get_children():
		child.queue_free()
	var armor: Dictionary = actor.get("armor", {})
	_chips.add_child(_chip("BODY SP %d" % int(armor.get("body", 0)), Palette.ARMOR))
	_chips.add_child(_chip("HEAD SP %d" % int(armor.get("head", 0)), Palette.ARMOR))
	var cover := int(actor.get("cover_hp", 0))
	if cover > 0:
		_chips.add_child(_chip("COVER %d" % cover, Palette.ACCENT))


func _rebuild_weapons(actor: Dictionary) -> void:
	for child in _weapons.get_children():
		child.queue_free()
	for entry in actor.get("weapons", []):
		var weapon: Dictionary = entry
		var jammed := bool(weapon.get("jammed", false))
		var text := "%s  %d" % [String(weapon.get("name", "?")), int(weapon.get("ammo", 0))]
		if jammed:
			text += "  JAMMED"
		var color := Palette.DANGER if jammed else Palette.MUTED
		if not jammed and int(weapon.get("ammo", 0)) == 0:
			color = Palette.WARN
		_weapons.add_child(_chip(text, color))


func _chip(text: String, edge: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Palette.chip_style(edge))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", edge)
	chip.add_child(label)
	return chip


func _flash(color: Color) -> void:
	var style := Palette.panel_style(color, 3)
	add_theme_stylebox_override("panel", style)
	var tween := create_tween()
	tween.tween_method(_blend_edge.bind(color), 0.0, 1.0, FLASH_SECONDS)


func _blend_edge(amount: float, from: Color) -> void:
	add_theme_stylebox_override(
		"panel", Palette.panel_style(from.lerp(Palette.EDGE, amount), 3 if amount < 1.0 else 2)
	)
