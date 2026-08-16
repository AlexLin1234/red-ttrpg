class_name RulesCard
extends PanelContainer

## A cited rules answer the GM chose to put on stream.
##
## The citation is never optional: if the service returned no citation the card
## says so rather than presenting an unsourced claim as a rule.

const FADE_SECONDS := 0.25

var _question: Label
var _answer: Label
var _citations: Label
var _timer: Timer


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.panel_style(Palette.ACCENT))
	custom_minimum_size = Vector2(820, 0)
	modulate.a = 0.0
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	_question = Label.new()
	_question.add_theme_font_size_override("font_size", 24)
	_question.add_theme_color_override("font_color", Palette.ACCENT)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_question)

	_answer = Label.new()
	_answer.add_theme_font_size_override("font_size", 28)
	_answer.add_theme_color_override("font_color", Palette.TEXT)
	_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_answer)

	_citations = Label.new()
	_citations.add_theme_font_size_override("font_size", 20)
	_citations.add_theme_color_override("font_color", Palette.MUTED)
	_citations.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_citations)


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_card)
	add_child(_timer)


func show_card(card: Dictionary, seconds: float) -> void:
	_question.text = String(card.get("question", ""))
	_answer.text = String(card.get("answer", ""))
	_citations.text = _citation_text(card.get("citations", []))

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


func _citation_text(citations: Array) -> String:
	var labels := PackedStringArray()
	for entry in citations:
		var citation: Dictionary = entry
		var book := String(citation.get("book", "Cyberpunk Red"))
		var first := int(citation.get("page_start", 0))
		var last := int(citation.get("page_end", first))
		labels.append("%s, p. %d" % [book, first] if first == last else "%s, pp. %d-%d" % [book, first, last])
	if labels.is_empty():
		return "No citation returned - treat this as a GM ruling, not a printed rule."
	return "  ".join(labels)
