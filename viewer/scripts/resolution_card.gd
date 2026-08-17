class_name ResolutionCard
extends PanelContainer

## The readable outcome of one resolved action.
##
## Every line comes from the resolver's own card text, so what the audience
## reads is exactly the arithmetic the service performed.

const FADE_SECONDS := 0.25
const LINE_STAGGER := 0.06

var _title: Label
var _subtitle: Label
var _lines: VBoxContainer
var _timer: Timer


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style(Palette.ACCENT))
	custom_minimum_size = Vector2(760, 0)
	modulate.a = 0.0
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 44)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Palette.MUTED)
	column.add_child(_subtitle)

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	column.add_child(_lines)


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_card)
	add_child(_timer)


func show_card(card: Dictionary, seconds: float) -> void:
	var accent := _accent_for(card)
	add_theme_stylebox_override("panel", Palette.panel_style(accent))

	_title.text = String(card.get("title", ""))
	_title.add_theme_color_override("font_color", accent)
	_subtitle.text = _subtitle_for(card)
	_subtitle.visible = _subtitle.text != ""

	for child in _lines.get_children():
		child.queue_free()
	var delay := 0.0
	for entry in card.get("lines", []):
		var line := Label.new()
		line.text = String(entry)
		line.add_theme_font_size_override("font_size", 26)
		line.add_theme_color_override("font_color", Palette.TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.modulate.a = 0.0
		_lines.add_child(line)
		var reveal := create_tween()
		reveal.tween_interval(delay)
		reveal.tween_property(line, "modulate:a", 1.0, FADE_SECONDS)
		delay += LINE_STAGGER

	visible = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_timer.start(seconds)


func hide_card() -> void:
	if not visible:
		return
	_timer.stop()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: visible = false)


## JSON nulls reach the viewer as null, not as an empty string.
static func text_of(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key)
	return "" if value == null else String(value)


func _accent_for(card: Dictionary) -> Color:
	if text_of(card, "critical_injury") != "":
		return Palette.DANGER
	match String(card.get("title", "")):
		"MISS", "STOPPED":
			return Palette.MUTED
		"HIT":
			return Palette.WARN
		_:
			return Palette.ACCENT


func _subtitle_for(card: Dictionary) -> String:
	if String(card.get("kind", "")) != "attack":
		return String(card.get("actor", ""))
	var text := (
		"%s -> %s  |  %s"
		% [
			String(card.get("attacker", "")),
			String(card.get("target", "")),
			String(card.get("weapon", "")),
		]
	)
	var mode := String(card.get("mode", "single"))
	if mode != "single":
		text += " (%s)" % mode
	if String(card.get("location", "body")) == "head":
		text += "  |  HEAD"
	return text
