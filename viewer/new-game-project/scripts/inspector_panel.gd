class_name TokenInspector
extends PanelContainer

@onready var title_label: Label = %Title
@onready var status_label: Label = %Status
@onready var hp_bar: ProgressBar = %HPBar
@onready var threshold_marker: ColorRect = %ThresholdMarker
@onready var hp_label: Label = %HPText
@onready var threshold_label: Label = %Threshold
@onready var armor_label: Label = %Armor
@onready var ammo_label: Label = %Ammo
@onready var skills_label: Label = %Skills
@onready var lifestyle_label: Label = %Lifestyle
@onready var cover_label: Label = %Cover


func _ready() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.012, 0.018, 0.042, 0.94)
	panel.border_color = Color("243b62")
	panel.set_border_width_all(2)
	panel.corner_radius_top_left = 16
	panel.corner_radius_bottom_left = 16
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	add_theme_stylebox_override("panel", panel)
	clear()


func clear() -> void:
	title_label.text = "NO TOKEN SELECTED"
	status_label.text = "Select a token on the board."
	hp_bar.value = 0
	hp_label.text = "HP —"
	threshold_label.text = ""
	armor_label.text = "ARMOR\n—"
	ammo_label.text = "AMMO\n—"
	skills_label.text = "RELEVANT SKILLS\n—"
	lifestyle_label.text = "LIFESTYLE\n—"
	cover_label.text = "COVER\n—"


func show_actor(name: String, state: Dictionary, cover_info: Dictionary, evading: bool) -> void:
	var hp := int(state.get("hp", 0))
	var max_hp := maxi(1, int(state.get("max_hp", 1)))
	var serious_threshold := floori(float(max_hp - 1) / 2.0)
	title_label.text = name.to_upper()
	status_label.text = str(state.get("wound_state", "ready")).replace("_", " ").to_upper()
	if evading:
		status_label.text += "  •  DODGING"
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	var threshold_ratio := float(serious_threshold) / float(max_hp)
	threshold_marker.anchor_left = threshold_ratio
	threshold_marker.anchor_right = threshold_ratio
	hp_label.text = "HP  %d / %d" % [hp, max_hp]
	threshold_label.text = "Seriously Wounded below %d HP" % serious_threshold

	var armor: Dictionary = state.get("armor", {})
	armor_label.text = (
		"ARMOR\nBody SP %d    Head SP %d" % [int(armor.get("body", 0)), int(armor.get("head", 0))]
	)

	var ammo_lines := PackedStringArray()
	var weapons: Dictionary = state.get("weapons", {})
	for weapon_name in weapons:
		var weapon: Dictionary = weapons[weapon_name]
		ammo_lines.append(
			(
				"%s  %d / %d"
				% [weapon_name, int(weapon.get("ammo", 0)), int(weapon.get("magazine", 0))]
			)
		)
	ammo_label.text = "AMMO\n" + ("\n".join(ammo_lines) if not ammo_lines.is_empty() else "—")

	var skill_lines := PackedStringArray()
	var skills: Dictionary = state.get("skills", {})
	for skill_name in skills:
		skill_lines.append("%-18s  +%d" % [skill_name, int(skills[skill_name])])
	skills_label.text = (
		"RELEVANT SKILLS\n" + ("\n".join(skill_lines) if not skill_lines.is_empty() else "—")
	)

	var lifestyle: Dictionary = state.get("lifestyle", {})
	var lifestyle_status := str(state.get("lifestyle_status", "current")).to_upper()
	var lifestyle_line := (
		"%s  •  %deb/MO  •  %s"
		% [
			str(lifestyle.get("label", "Kibble")),
			int(lifestyle.get("monthly_cost", 100)),
			lifestyle_status,
		]
	)
	var payment_line := "Cash %deb" % int(state.get("cash", 0))
	if lifestyle_status == "UNPAID":
		payment_line += (
			"  •  %deb due  •  %d-day grace"
			% [
				int(state.get("lifestyle_balance_due", 0)),
				int(state.get("lifestyle_grace_days", 0)),
			]
		)
	elif state.get("lifestyle_paid_through") != null:
		payment_line += "  •  Paid through %s" % str(state.get("lifestyle_paid_through"))
	lifestyle_label.text = "LIFESTYLE\n%s\n%s" % [lifestyle_line, payment_line]

	var classification := str(cover_info.get("classification", "none")).to_upper()
	if classification == "NONE":
		cover_label.text = "COVER\nNONE"
	else:
		cover_label.text = (
			"COVER\n%s  •  %s  •  %d HP"
			% [
				classification,
				str(cover_info.get("material", "unknown")).to_upper(),
				int(cover_info.get("hp", 0)),
			]
		)
