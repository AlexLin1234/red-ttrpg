extends Control

## Stream overlay for the local Cyberpunk RED GM service.
##
## Layout is fixed for a 1920x1080 capture: the roster sits top left, the
## resolution card bottom right, and a cited rules answer bottom left. The
## window is transparent so OBS can composite it over the rest of the scene.

const MARGIN := 48
const CARD_SECONDS := 9.0
const RULES_SECONDS := 16.0

var _client: GMClient
var _roster: VBoxContainer
var _panels: Dictionary = {}
var _card: ResolutionCard
var _rules: RulesCard
var _status: PanelContainer
var _revision := -1


func _ready() -> void:
	_make_window_capturable()
	_build_layout()

	_client = GMClient.new()
	_client.name = "GMClient"
	_client.url = GMClient.resolve_url()
	_client.snapshot_received.connect(_on_snapshot)
	_client.rules_received.connect(_on_rules)
	_client.connection_changed.connect(_on_connection_changed)
	add_child(_client)


func _make_window_capturable() -> void:
	# An opaque backdrop is easier to key in some OBS setups, so it stays
	# available behind --opaque without rebuilding the project.
	if "--opaque" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		RenderingServer.set_default_clear_color(Palette.INK)
		return
	get_window().set_flag(Window.FLAG_TRANSPARENT, true)
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(frame)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 14)
	_roster.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_roster.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(_lane(_roster, BoxContainer.ALIGNMENT_BEGIN, BoxContainer.ALIGNMENT_BEGIN))

	_card = ResolutionCard.new()
	frame.add_child(_lane(_card, BoxContainer.ALIGNMENT_END, BoxContainer.ALIGNMENT_END))

	_rules = RulesCard.new()
	frame.add_child(_lane(_rules, BoxContainer.ALIGNMENT_END, BoxContainer.ALIGNMENT_BEGIN))

	_status = _build_status()
	frame.add_child(_lane(_status, BoxContainer.ALIGNMENT_BEGIN, BoxContainer.ALIGNMENT_END))


## Park one widget in a corner of the frame without hand-computed offsets. The
## lanes overlap on purpose: each only claims the corner it aligns into.
func _lane(widget: Control, vertical: int, horizontal: int) -> Control:
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = vertical
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var columns := HBoxContainer.new()
	columns.alignment = horizontal
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(widget)
	rows.add_child(columns)
	return rows


func _build_status() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.chip_style(Palette.DANGER))
	panel.visible = false

	var label := Label.new()
	label.name = "Label"
	label.text = "GM SERVICE OFFLINE"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Palette.DANGER)
	panel.add_child(label)
	return panel


func _on_connection_changed(connected: bool) -> void:
	_status.visible = not connected
	if not connected:
		_revision = -1


func _on_snapshot(snapshot: Dictionary) -> void:
	var revision := int(snapshot.get("revision", 0))
	_sync_roster(snapshot.get("actors", []))

	var card: Variant = snapshot.get("card")
	if revision == _revision:
		# A reconnect replays the current snapshot; do not re-run its card.
		return
	_revision = revision
	if typeof(card) == TYPE_DICTIONARY:
		_card.show_card(card, CARD_SECONDS)
	else:
		_card.hide_card()


func _sync_roster(actors: Array) -> void:
	var seen := {}
	for index in actors.size():
		var actor: Dictionary = actors[index]
		var actor_id := String(actor.get("id", ""))
		seen[actor_id] = true
		var panel: ActorPanel = _panels.get(actor_id)
		if panel == null:
			panel = ActorPanel.new()
			_panels[actor_id] = panel
			_roster.add_child(panel)
		_roster.move_child(panel, index)
		panel.update_actor(actor)

	for actor_id in _panels.keys():
		if not seen.has(actor_id):
			_panels[actor_id].queue_free()
			_panels.erase(actor_id)


func _on_rules(card: Dictionary) -> void:
	_rules.show_card(card, RULES_SECONDS)
