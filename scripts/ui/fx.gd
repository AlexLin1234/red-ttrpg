class_name Fx
extends RefCounted

## Motion, in one place, and all of it optional.
##
## The console was drawn carefully and then never moved: a screen replaced
## another in a single frame, an overlay was simply there, and a status message
## changed a word in a corner. Nothing told the eye where to look. These are
## the few short movements that do — a fade as a screen arrives, a pop as a
## panel opens — and every one of them is skipped when Reduce motion is on.

const QUICK := 0.14
const SETTLE := 0.22

## Set by the screen runner while it photographs screens, so a shot is never
## taken half-way through a fade.
static var suspended := false


static func enabled() -> bool:
	return not suspended and not AppSettings.reduce_motion()


## Bring [param node] up from transparent.
static func fade_in(node: CanvasItem, seconds := QUICK) -> void:
	if not enabled() or not node.is_inside_tree():
		node.modulate.a = 1.0
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, seconds).set_ease(Tween.EASE_OUT)


## Open [param panel] the way a hatch opens: slightly small, then to size.
static func pop(panel: Control, from := 0.96) -> void:
	if not enabled() or not panel.is_inside_tree():
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0
		return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(from, from)
	panel.modulate.a = 0.0
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "scale", Vector2.ONE, SETTLE).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(panel, "modulate:a", 1.0, QUICK)


## Light [param node] up and let it settle back: something here just changed.
static func flash(node: CanvasItem, colour := Color(1.6, 1.5, 1.2), seconds := 0.45) -> void:
	if not enabled() or not node.is_inside_tree():
		return
	node.modulate = colour
	var tween := node.create_tween()
	tween.tween_property(node, "modulate", Color.WHITE, seconds).set_ease(Tween.EASE_OUT)


## A sliver of light crossing the backdrop along each of its traces.
##
## Drawn by a layer of its own so the grid underneath is painted once and left
## alone: three dots a frame is all that moves.
class Pulses:
	extends Control

	var colours: Array[Color] = [Color("8fd0ff"), Color("ffd166"), Color("8fd0ff")]
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if not Fx.enabled() or not is_visible_in_tree():
			return
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if not Fx.enabled():
			return
		# The same three lanes Chrome.Backdrop draws its traces along.
		var lanes := [
			{"y": size.y * 0.22, "at": 0.18, "drop": 90.0, "period": 11.0, "phase": 0.0},
			{"y": size.y * 0.62, "at": 0.55, "drop": -120.0, "period": 14.0, "phase": 0.4},
			{"y": size.y * 0.86, "at": 0.31, "drop": 70.0, "period": 9.0, "phase": 0.7},
		]
		for index in lanes.size():
			var lane: Dictionary = lanes[index]
			var y := float(lane["y"])
			var elbow := size.x * float(lane["at"])
			var drop := float(lane["drop"])
			var path := [
				Vector2(0, y),
				Vector2(elbow, y),
				Vector2(elbow + absf(drop) * 0.5, y + drop * 0.5),
				Vector2(size.x, y + drop * 0.5),
			]
			var travel := fposmod(_time / float(lane["period"]) + float(lane["phase"]), 1.0)
			var head := _along(path, travel)
			var colour := colours[index % colours.size()]
			for step in 6:
				var tail := _along(path, maxf(0.0, travel - float(step) * 0.006))
				draw_circle(tail, 2.2 - float(step) * 0.25, Color(colour, 0.5 - float(step) * 0.08))
			draw_circle(head, 5.0, Color(colour, 0.12))

	static func _along(path: Array, fraction: float) -> Vector2:
		var total := 0.0
		for index in path.size() - 1:
			total += (path[index] as Vector2).distance_to(path[index + 1])
		var target := total * clampf(fraction, 0.0, 1.0)
		for index in path.size() - 1:
			var from: Vector2 = path[index]
			var to: Vector2 = path[index + 1]
			var length := from.distance_to(to)
			if target <= length or index == path.size() - 2:
				return from.lerp(to, clampf(target / maxf(length, 0.001), 0.0, 1.0))
			target -= length
		return path[path.size() - 1]
