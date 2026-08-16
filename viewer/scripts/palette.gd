class_name Palette
extends RefCounted

## Shared colours and panel styling for every viewer widget.
##
## Cards are drawn dark and semi-opaque so they stay readable over any stream
## layout, while the window itself is transparent for OBS.

const INK := Color("0a0e14")
const PANEL := Color(0.043, 0.055, 0.078, 0.88)
const EDGE := Color("1f2a37")
const TEXT := Color("e6edf3")
const MUTED := Color("8b9bb0")
const ACCENT := Color("22d3ee")
const WARN := Color("fbbf24")
const DANGER := Color("f43f5e")
const GOOD := Color("34d399")
const ARMOR := Color("60a5fa")


static func panel_style(edge: Color = EDGE, thickness: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(10)
	style.set_border_width_all(thickness)
	style.border_color = edge
	style.set_content_margin_all(18)
	return style


static func chip_style(edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(edge.r, edge.g, edge.b, 0.16)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = edge
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func bar_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(4)
	return style


## Green while healthy, amber once the character is hurt, red when they are
## down. The thresholds mirror the seriously wounded line the service reports.
static func health_color(hp: int, max_hp: int) -> Color:
	if hp <= 0:
		return DANGER
	if hp <= int((max_hp - 1) / 2.0):
		return WARN
	return GOOD
