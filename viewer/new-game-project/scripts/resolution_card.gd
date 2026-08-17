class_name ResolutionCard
extends PanelContainer

var _fade_tween: Tween

@onready var title_label: Label = %Title
@onready var lines_label: Label = %Lines


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func show_card(card: Dictionary) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var tone := str(card.get("tone", "neutral"))
	title_label.text = str(card.get("title", "RESOLUTION"))
	lines_label.text = "\n".join(PackedStringArray(card.get("lines", [])))
	_set_tone(tone)
	visible = true
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_fade_tween.tween_interval(float(card.get("duration_seconds", 5.0)))
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.45)
	_fade_tween.tween_callback(func() -> void: visible = false)


func _set_tone(tone: String) -> void:
	var color := Color("00e5ff")
	if tone == "hit":
		color = Color("ff2ca8")
	elif tone == "miss":
		color = Color("9aa6b6")
	elif tone == "undo":
		color = Color("ffe45c")
	title_label.add_theme_color_override("font_color", color)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.018, 0.025, 0.055, 0.96)
	panel.border_color = color
	panel.set_border_width_all(3)
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 18
	panel.corner_radius_bottom_left = 18
	panel.corner_radius_bottom_right = 4
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 20
	panel.content_margin_bottom = 22
	add_theme_stylebox_override("panel", panel)
