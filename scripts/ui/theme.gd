class_name UI
extends RefCounted

## The visual system, and the small factory functions the screens build from.
##
## The UI is assembled in GDScript rather than authored as .tscn trees. Screens
## here are dense, data-driven grids whose contents come from the campaign file,
## so the layout has to be built in a loop either way; doing it in code keeps the
## structure readable in one place instead of split across a scene file.
##
## Colours are sampled from the UI mockups in docs/mockups. The app commits to a
## single dark identity on purpose: it is a GM console read in a dim room.

const BG_DEEP := Color("0a0f15")
const BG_PAGE := Color("0e1318")
const PANEL := Color("11161f")
const PANEL_RAISED := Color("161a26")
const PANEL_INSET := Color("0c1117")
const HAIRLINE := Color("1b232e")
const RULE := Color("243044")

const TEXT := Color("dfe7f0")
const TEXT_DISPLAY := Color("ffffff")
const MUTED := Color("6b7d94")
const MUTED_DIM := Color("47576b")

const ACCENT := Color("93bce2")
const ACCENT_FILL := Color("567da4")
const ACCENT_DIM := Color("2d4462")
const ALERT := Color("bb5451")
const ALERT_BRIGHT := Color("d4675f")
const GOOD := Color("6fbf8b")
const WARN := Color("d9b45c")

const DISPLAY_FONT := preload("res://assets/fonts/oswald-400-700.woff2")
const BODY_FONT := preload("res://assets/fonts/barlow-400.woff2")
const BODY_BOLD_FONT := preload("res://assets/fonts/barlow-600.woff2")

const GAP_1 := 4
const GAP_2 := 8
const GAP_3 := 12
const GAP_4 := 16
const GAP_5 := 24


static func flat(
	bg: Color, border := Color.TRANSPARENT, border_width := 0, margin := 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	if margin > 0:
		box.content_margin_left = margin
		box.content_margin_right = margin
		box.content_margin_top = margin
		box.content_margin_bottom = margin
	return box


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 15

	theme.set_stylebox("panel", "PanelContainer", flat(PANEL, HAIRLINE, 1))
	theme.set_stylebox("panel", "Panel", flat(PANEL, HAIRLINE, 1))

	var button_normal := flat(PANEL_RAISED, RULE, 1, 8)
	var button_hover := flat(PANEL_RAISED, ACCENT_FILL, 1, 8)
	var button_pressed := flat(ACCENT_DIM, ACCENT, 1, 8)
	var button_disabled := flat(PANEL_INSET, HAIRLINE, 1, 8)
	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("focus", "Button", flat(Color.TRANSPARENT, ACCENT, 1, 8))
	theme.set_stylebox("disabled", "Button", button_disabled)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_DISPLAY)
	theme.set_color("font_pressed_color", "Button", TEXT_DISPLAY)
	theme.set_color("font_disabled_color", "Button", MUTED_DIM)
	theme.set_font("font", "Button", BODY_BOLD_FONT)
	theme.set_font_size("font_size", "Button", 13)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)

	theme.set_stylebox("normal", "LineEdit", flat(PANEL_INSET, HAIRLINE, 1, 6))
	theme.set_stylebox("focus", "LineEdit", flat(PANEL_INSET, ACCENT, 1, 6))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)

	theme.set_stylebox("scroll", "VScrollBar", flat(Color.TRANSPARENT))
	theme.set_stylebox("grabber", "VScrollBar", flat(RULE))
	theme.set_stylebox("grabber_highlight", "VScrollBar", flat(ACCENT_FILL))
	theme.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT))

	theme.set_stylebox("slider", "HSlider", flat(PANEL_INSET, HAIRLINE, 1))
	theme.set_stylebox("grabber_area", "HSlider", flat(ACCENT_FILL))
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT))

	return theme


# -- factories -----------------------------------------------------------------


## The mockups' signature move: a tiny letterspaced uppercase label above every
## block of content. It appears often enough to be one factory.
static func micro(text: String, color := MUTED) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", BODY_BOLD_FONT)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 2)
	# Godot has no letter-spacing property, so the effect is approximated with
	# spaces between characters for the short labels that carry it.
	label.text = _letterspace(label.text)
	return label


static func _letterspace(text: String) -> String:
	var spaced := ""
	for index in text.length():
		spaced += text[index]
		if index < text.length() - 1 and text[index] != " ":
			spaced += " "
	return spaced


static func display(text: String, size := 24, color := TEXT_DISPLAY) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func body(text: String, size := 14, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func value(text: String, size := 13, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_BOLD_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Let a label shrink below its text width and elide.
##
## A Label's minimum size is its full text, so one long character name in a
## narrow rail pushes every neighbouring panel off the screen. Applied only where
## a name genuinely may be too long, never to tiles whose text is the content.
static func elide(label: Label) -> Label:
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0
	return label


static func panel(bg := PANEL, border := HAIRLINE) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", flat(bg, border, 1))
	# Panels own a fixed slot in the screen grid; content that overruns is
	# clipped rather than allowed to shove the neighbouring rail off screen.
	container.clip_contents = true
	return container


static func margins(node: Control, all := GAP_3) -> MarginContainer:
	var container := MarginContainer.new()
	container.add_theme_constant_override("margin_left", all)
	container.add_theme_constant_override("margin_right", all)
	container.add_theme_constant_override("margin_top", all)
	container.add_theme_constant_override("margin_bottom", all)
	container.add_child(node)
	return container


## Margins that fill their parent.
##
## Needed whenever the parent is not itself a container — a Control screen root,
## or a Button we are decorating — because anchors on the inner node are ignored
## once a container owns its layout.
static func fill_margins(node: Control, all := GAP_3) -> MarginContainer:
	var container := margins(node, all)
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	return container


## Marks a control as taking all the room its container will give it.
static func expand(node: Control, horizontal := true, vertical := true) -> Control:
	if horizontal:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node


static func vbox(separation := GAP_2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation := GAP_2) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func rule_line() -> Panel:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.add_theme_stylebox_override("panel", flat(RULE))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## A label/value row with a hairline above it, used all over the side rails.
static func field_row(label: String, value_text: String, value_color := TEXT) -> HBoxContainer:
	var row := hbox()
	var key := micro(label)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	row.add_child(value(value_text, 11, value_color))
	return row


## A button styled as a tab in a tab strip.
static func tab_button(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = _letterspace(text.to_upper())
	button.toggle_mode = true
	button.button_pressed = selected
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", BODY_BOLD_FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", flat(PANEL_INSET, Color.TRANSPARENT, 0, 8))
	button.add_theme_stylebox_override("hover", flat(PANEL_INSET, HAIRLINE, 1, 8))
	var active := flat(PANEL_RAISED, Color.TRANSPARENT, 0, 8)
	active.border_color = ACCENT
	active.border_width_bottom = 2
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_pressed_color", TEXT_DISPLAY)
	button.add_theme_color_override("font_hover_color", TEXT)
	return button


## The filled call-to-action used once per screen.
static func primary_button(text: String) -> Button:
	var button := Button.new()
	button.text = _letterspace(text.to_upper())
	button.add_theme_font_override("font", BODY_BOLD_FONT)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_stylebox_override("normal", flat(ACCENT_FILL, ACCENT_FILL, 1, 8))
	button.add_theme_stylebox_override("hover", flat(ACCENT, ACCENT, 1, 8))
	button.add_theme_stylebox_override("pressed", flat(ACCENT, ACCENT, 1, 8))
	button.add_theme_stylebox_override("disabled", flat(PANEL_INSET, HAIRLINE, 1, 8))
	button.add_theme_color_override("font_color", BG_DEEP)
	button.add_theme_color_override("font_hover_color", BG_DEEP)
	button.add_theme_color_override("font_pressed_color", BG_DEEP)
	button.add_theme_color_override("font_disabled_color", MUTED_DIM)
	return button


static func plain_button(text: String) -> Button:
	var button := Button.new()
	button.text = _letterspace(text.to_upper())
	button.add_theme_font_override("font", BODY_BOLD_FONT)
	button.add_theme_font_size_override("font_size", 10)
	return button


## A thin horizontal HP bar, coloured by how bad things are.
static func hp_bar(ratio: float, width := 0.0) -> Control:
	var track := Panel.new()
	track.custom_minimum_size = Vector2(width, 2)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.add_theme_stylebox_override("panel", flat(RULE))
	track.clip_contents = true

	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.offset_right = 0
	var colour := ACCENT
	if ratio <= 0.25:
		colour = ALERT
	elif ratio < 1.0:
		colour = WARN
	fill.add_theme_stylebox_override("panel", flat(colour))
	track.add_child(fill)
	return track


## The hatched placeholder block standing in for art that has not been made yet.
static func hatch(size: Vector2, caption := "") -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = size
	holder.add_theme_stylebox_override("panel", flat(PANEL_INSET, HAIRLINE, 1))

	var lines := _Hatch.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lines)

	if caption != "":
		var label := micro(caption, MUTED_DIM)
		label.set_anchors_preset(Control.PRESET_CENTER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.grow_vertical = Control.GROW_DIRECTION_BOTH
		holder.add_child(label)
	return holder


## Diagonal hatching, drawn rather than textured so it scales with the panel.
class _Hatch extends Control:
	func _draw() -> void:
		var step := 5.0
		var colour := Color(0.576, 0.737, 0.886, 0.07)
		var extent := size.x + size.y
		var offset := 0.0
		while offset < extent:
			draw_line(Vector2(offset, 0), Vector2(offset - size.y, size.y), colour, 1.0)
			offset += step
