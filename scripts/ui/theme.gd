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
##
## Two accents carry it. Blue is the structural one — frames, rules, anything
## the console says about itself. Amber is the human one — what the table has
## touched, what is unsaved, what is about to hurt. They are complements, so a
## panel trimmed in both has a corner your eye goes to without being told.

const BG_DEEP := Color("070c14")
const BG_PAGE := Color("0b111a")
const PANEL := Color("101724")
const PANEL_RAISED := Color("161d2c")
const PANEL_INSET := Color("0a1019")
const HAIRLINE := Color("1d2637")
const RULE := Color("27364e")

const TEXT := Color("dfe7f0")
const TEXT_DISPLAY := Color("ffffff")
const MUTED := Color("7189a5")
const MUTED_DIM := Color("4a5c76")

const ACCENT := Color("8fd0ff")
const ACCENT_FILL := Color("2f7fc9")
const ACCENT_DIM := Color("1d3f66")
const ACCENT_GLOW := Color("4fb4ff")

## The yellow half of the pair. AMBER is what is read, AMBER_FILL what is sat
## on, AMBER_DIM what is only hinted at in a bracket or a corner.
const AMBER := Color("ffd166")
const AMBER_FILL := Color("d9a326")
const AMBER_DIM := Color("6a5320")
const AMBER_GLOW := Color("ffbe3d")

const ALERT := Color("d05a52")
const ALERT_BRIGHT := Color("f0736a")
const GOOD := Color("5fd39b")
const WARN := AMBER

const DISPLAY_FONT := preload("res://assets/fonts/oswald-400-700.woff2")
const BODY_FONT := preload("res://assets/fonts/barlow-400.woff2")
const BODY_BOLD_FONT := preload("res://assets/fonts/barlow-600.woff2")

const GAP_1 := 4
const GAP_2 := 8
const GAP_3 := 12
const GAP_4 := 16
const GAP_5 := 24


## How far the corner cuts reach on each kind of frame. A panel can afford a
## generous chamfer; a 24px-tall row in a list cannot, and would lose its whole
## corner to one.
const CUT_PANEL := 14.0
const CUT_TILE := 9.0
const CUT_CONTROL := 6.0


## A chamfered frame: the default shape of everything in the console.
##
## Takes the same four arguments as [method flat] so one can be swapped for the
## other at a call site, and adds the two that make it a frame rather than a
## box — how deep the corner cuts run, and which corners they take.
static func chamfer(
	bg: Color,
	border := Color.TRANSPARENT,
	border_width := 1,
	margin := 0,
	cut := CUT_CONTROL,
	corners := Chrome.CUT_DIAGONAL
) -> Chrome.ChamferBox:
	var box := Chrome.ChamferBox.new()
	box.bg = bg
	box.bg_top = bg.lightened(0.045) if bg.a > 0.0 else bg
	box.border = border
	box.border_width = float(border_width)
	box.cut = cut
	box.corners = corners
	# Anything brighter than the hairline is a state — selected, armed, focused —
	# and states are lit. The dim frames stay unlit or the screen turns to soup.
	if border.a > 0.0 and border.get_luminance() > 0.22:
		box.glow = border
		box.glow_strength = 1.0
	if margin > 0:
		box.content_margin_left = margin
		box.content_margin_right = margin
		box.content_margin_top = margin
		box.content_margin_bottom = margin
	return box


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

	theme.set_stylebox("panel", "PanelContainer", frame_box(PANEL, HAIRLINE))
	theme.set_stylebox("panel", "Panel", frame_box(PANEL, HAIRLINE))

	var button_normal := chamfer(PANEL_RAISED, RULE, 1, 8)
	var button_hover := chamfer(PANEL_RAISED, ACCENT, 1, 8)
	button_hover.edge = AMBER
	button_hover.edge_length = 12.0
	var button_pressed := chamfer(ACCENT_DIM, ACCENT, 1, 8)
	button_pressed.foot = AMBER
	var button_disabled := chamfer(PANEL_INSET, HAIRLINE, 1, 8)
	theme.set_stylebox("normal", "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("focus", "Button", chamfer(Color.TRANSPARENT, ACCENT, 1, 8))
	theme.set_stylebox("disabled", "Button", button_disabled)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_DISPLAY)
	theme.set_color("font_pressed_color", "Button", TEXT_DISPLAY)
	theme.set_color("font_disabled_color", "Button", MUTED_DIM)
	theme.set_font("font", "Button", BODY_BOLD_FONT)
	theme.set_font_size("font_size", "Button", 13)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)

	var field := chamfer(PANEL_INSET, HAIRLINE, 1, 6, CUT_CONTROL, Chrome.CUT_TOP_LEFT)
	var field_focus := chamfer(PANEL_INSET, ACCENT, 1, 6, CUT_CONTROL, Chrome.CUT_TOP_LEFT)
	field_focus.foot = ACCENT_GLOW
	field_focus.foot_width = 1.5
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", AMBER)

	# Both bars, not just the vertical one: a horizontal scrollbar left in the
	# engine's default grey was the brightest thing on the beats board.
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, flat(PANEL_INSET))
		theme.set_stylebox("grabber", bar, flat(RULE))
		theme.set_stylebox("grabber_highlight", bar, flat(ACCENT_FILL))
		theme.set_stylebox("grabber_pressed", bar, flat(ACCENT))

	theme.set_stylebox("slider", "HSlider", flat(PANEL_INSET, HAIRLINE, 1))
	theme.set_stylebox("grabber_area", "HSlider", flat(ACCENT_FILL))
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT))

	theme.set_stylebox(
		"panel", "PopupMenu", chamfer(PANEL_RAISED, RULE, 1, 4, CUT_TILE, Chrome.CUT_DIAGONAL)
	)
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", AMBER)

	var option := chamfer(PANEL_INSET, RULE, 1, 8, CUT_CONTROL, Chrome.CUT_DIAGONAL)
	var option_hover := chamfer(PANEL_RAISED, ACCENT, 1, 8, CUT_CONTROL, Chrome.CUT_DIAGONAL)
	theme.set_stylebox("normal", "OptionButton", option)
	theme.set_stylebox("hover", "OptionButton", option_hover)
	theme.set_stylebox("pressed", "OptionButton", option_hover)
	theme.set_stylebox("focus", "OptionButton", chamfer(Color.TRANSPARENT, ACCENT, 1, 8))

	_restyle_dialogs(theme)

	return theme


## Repaint the windows the engine draws for us.
##
## Downtime, Snapshots, the file pickers and the recovery prompt are engine
## dialogs, and they arrived in the default theme's light grey — the only pale
## surface anywhere in the app, and the one that lit up a dark room. Their own
## styleboxes are duplicated and recoloured rather than replaced, so every
## margin the engine measures its title bar and buttons against stays exactly
## where it was.
static func _restyle_dialogs(theme: Theme) -> void:
	var base := ThemeDB.get_default_theme()

	var border := base.get_stylebox("embedded_border", "Window")
	if border is StyleBoxFlat:
		var frame := (border as StyleBoxFlat).duplicate() as StyleBoxFlat
		frame.bg_color = PANEL
		frame.border_color = ACCENT_DIM
		frame.set_border_width_all(1)
		frame.shadow_color = Color(BG_DEEP, 0.7)
		theme.set_stylebox("embedded_border", "Window", frame)
		var unfocused := frame.duplicate() as StyleBoxFlat
		unfocused.border_color = HAIRLINE
		theme.set_stylebox("embedded_unfocused_border", "Window", unfocused)
	theme.set_color("title_color", "Window", TEXT_DISPLAY)

	var panel_style := base.get_stylebox("panel", "AcceptDialog")
	if panel_style is StyleBoxFlat:
		var body := (panel_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		body.bg_color = PANEL
		theme.set_stylebox("panel", "AcceptDialog", body)
	theme.set_stylebox("panel", "PopupPanel", chamfer(PANEL, RULE, 1, 6, CUT_TILE))


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
	# thin spaces between characters for the short labels that carry it.
	label.text = _letterspace(label.text)
	return label


## What is put between two letters to hold them apart: a thin space, followed by
## a word joiner. The joiner draws nothing and takes no width; it is there to
## deny the line breaker the break it would otherwise take on the space, so a
## letterspaced line that has to wrap breaks between two words rather than
## between two letters of the same word.
const LETTER_GAP := " ⁠"


static func _letterspace(text: String) -> String:
	var spaced := ""
	for index in text.length():
		spaced += text[index]
		if index < text.length() - 1 and text[index] != " ":
			spaced += LETTER_GAP
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


## The frame a panel is drawn with: chamfered, bracketed, and lit along the top.
##
## The trim is deliberately asymmetric — blue on the cut corners and the top
## edge, amber on the two corners the cut left square. A screen of these has a
## rhythm to it that a screen of bordered rectangles does not, and the amber
## corners give the eye something to count panels by.
static func frame_box(bg := PANEL, border := HAIRLINE) -> Chrome.ChamferBox:
	var box := chamfer(bg, border, 1, 0, CUT_PANEL, Chrome.CUT_DIAGONAL)
	var lit := border.a > 0.0 and border.get_luminance() > 0.22
	box.bracket = border if lit else AMBER_DIM
	box.bracket_length = 16.0
	box.bracket_width = 1.5
	box.edge = border if lit else ACCENT
	box.edge_length = 26.0
	if not lit:
		box.edge = Color(ACCENT, 0.5)
	# The texture is there to be felt rather than seen: at this alpha it reads
	# as a surface, and one step brighter it reads as a pattern behind the text.
	box.weave = Color(ACCENT, 0.022)
	box.weave_step = 11.0
	return box


static func panel(bg := PANEL, border := HAIRLINE) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", frame_box(bg, border))
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


## The separator between two blocks of a panel, lit at its left end.
##
## It was a one-pixel rectangle, repeated seventy times across the console. Now
## it starts as a bright blue filament under an amber node, steps down through a
## short diagonal and runs out as the old hairline — so the same separator both
## marks where a block begins and points along it.
static func rule_line() -> Control:
	var line := Chrome.GlowRule.new()
	line.core = Color(ACCENT, 0.7)
	line.tail = RULE
	line.node = AMBER
	return line


## A rule with no node and no diagonal, for the places a plain divider is all
## that fits — inside a 24px row, or under a single line of text.
static func hairline(colour := HAIRLINE) -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.add_theme_stylebox_override("panel", flat(colour))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## One of the small angled marks: a diamond, a hexagon, a chevron or a stack.
##
## [param extent] is the box it draws inside, so it lines up with the cap height
## of the label it sits beside.
static func mark(kind := Chrome.Mark.Kind.DIAMOND, colour := ACCENT, extent := 9.0) -> Control:
	return Chrome.Mark.new(kind, colour, extent)


## A heading: a lit mark, the letterspaced label, and a rule taking the rest of
## the row. The three together are what a section title looks like here.
static func heading(text: String, colour := ACCENT, kind := Chrome.Mark.Kind.DIAMOND) -> Control:
	var row := hbox(GAP_2)
	row.add_child(mark(kind, colour, 9.0))
	var label := micro(text, MUTED if colour == ACCENT else colour)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var line := Chrome.GlowRule.new()
	line.core = Color(colour, 0.55)
	line.tail = RULE
	line.node = Color.TRANSPARENT
	line.lit = 0.22
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(expand(line, true, false))
	return row


## The bracket frame that goes over a 3D board, as a sibling of the viewport.
##
## Ignores the mouse, so the board underneath keeps every click.
static func reticle() -> Control:
	var frame := Chrome.Reticle.new()
	frame.frame = ACCENT
	frame.tick = AMBER
	return frame


## The app's ground: a grid with lit traces run across it.
static func backdrop(base := BG_PAGE) -> Control:
	var ground := Chrome.Backdrop.new()
	ground.base = base
	ground.grid = ACCENT
	ground.trace = ACCENT_GLOW
	ground.spark = AMBER_GLOW
	return ground


## A label/value row with a hairline above it, used all over the side rails.
##
## Both halves expand, so a value too long for the space left beside its key can
## wrap within its own half of the row rather than running out of the panel. It
## is drawn against the right edge, where it sits when it is short enough to need
## only part of that half.
static func field_row(label: String, value_text: String, value_color := TEXT) -> HBoxContainer:
	var row := hbox()
	var key := micro(label)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var reading := value(value_text, 11, value_color)
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(reading)
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
	var idle := chamfer(PANEL_INSET, Color.TRANSPARENT, 0, 8, CUT_CONTROL, Chrome.CUT_TOP_LEFT)
	button.add_theme_stylebox_override("normal", idle)
	var hover := chamfer(PANEL_INSET, HAIRLINE, 1, 8, CUT_CONTROL, Chrome.CUT_TOP_LEFT)
	hover.foot = Color(ACCENT, 0.45)
	hover.foot_width = 1.0
	button.add_theme_stylebox_override("hover", hover)
	# The selected tab is the one place both accents meet: a blue frame cut at
	# the top-left, standing on an amber bar.
	var active := chamfer(PANEL_RAISED, ACCENT_DIM, 1, 8, CUT_CONTROL, Chrome.CUT_TOP_LEFT)
	active.bg_top = ACCENT_DIM.lerp(PANEL_RAISED, 0.45)
	active.foot = AMBER
	active.foot_width = 2.0
	active.edge = Color(ACCENT, 0.8)
	active.edge_length = 14.0
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
	# The one filled control on a screen, so it gets the full treatment: a blue
	# slab cut on both diagonals, lit all round, with an amber filament along
	# the top edge to keep it from reading as another blue rectangle.
	var normal := chamfer(ACCENT_FILL, ACCENT, 1, 8, CUT_CONTROL, Chrome.CUT_DIAGONAL)
	normal.bg_top = ACCENT_FILL.lightened(0.2)
	normal.edge = AMBER
	normal.edge_length = 16.0
	var hot := chamfer(ACCENT, ACCENT, 1, 8, CUT_CONTROL, Chrome.CUT_DIAGONAL)
	hot.bg_top = ACCENT.lightened(0.15)
	hot.edge = AMBER
	hot.edge_length = 22.0
	hot.glow = ACCENT_GLOW
	hot.glow_strength = 1.6
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hot)
	button.add_theme_stylebox_override("pressed", hot)
	button.add_theme_stylebox_override(
		"disabled", chamfer(PANEL_INSET, HAIRLINE, 1, 8, CUT_CONTROL, Chrome.CUT_DIAGONAL)
	)
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


## A notched HP gauge, coloured by how bad things are.
##
## Ten leaning notches rather than one sliding rectangle: a GM reads the quarter
## the party is in, never the exact number of points, and the leading notch is
## lit so a glance finds the head of the bar without hunting for its edge.
static func hp_bar(ratio: float, width := 0.0) -> Control:
	var colour := ACCENT
	if ratio <= 0.25:
		colour = ALERT
	elif ratio < 1.0:
		colour = AMBER
	var meter := Chrome.Meter.new(ratio, colour)
	meter.track = RULE
	meter.custom_minimum_size = Vector2(width, 4)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return meter


## The hatched placeholder block standing in for art that has not been made yet.
static func hatch(size: Vector2, caption := "") -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = size
	var box := chamfer(PANEL_INSET, HAIRLINE, 1, 0, CUT_TILE, Chrome.CUT_DIAGONAL)
	box.bracket = Color(AMBER_DIM, 0.9)
	box.bracket_length = 10.0
	box.bracket_width = 1.0
	holder.add_theme_stylebox_override("panel", box)

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


## A lattice, drawn rather than textured so it scales with the panel.
##
## Two sets of diagonals crossing at right angles, blue one way and amber the
## other, with a lit diamond where the middle two cross. It says "nothing here
## yet" the way the single hatch did, and looks like part of the console while
## it says it.
class _Hatch extends Control:
	func _draw() -> void:
		var step := 7.0
		var blue := Color(UI.ACCENT, 0.075)
		var gold := Color(UI.AMBER, 0.05)
		var extent := size.x + size.y
		var offset := 0.0
		while offset < extent:
			draw_line(Vector2(offset, 0), Vector2(offset - size.y, size.y), blue, 1.0)
			draw_line(Vector2(offset - size.y, 0), Vector2(offset, size.y), gold, 1.0)
			offset += step * 2.0
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.16
		if radius > 2.0:
			Chrome.glow_stroke(
				get_canvas_item(),
				Chrome.closed(Chrome.diamond(centre, radius)),
				Color(UI.ACCENT, 0.35),
				1.0
			)
