class_name GMClient
extends Node

## Read-only WebSocket link to the local GM service.
##
## The viewer is a subscriber: it sends nothing but keep-alives and reconnects
## on its own, so restarting the service (or opening OBS first) never needs a
## restart of the scene.

signal snapshot_received(snapshot: Dictionary)
signal rules_received(card: Dictionary)
signal connection_changed(connected: bool)

const DEFAULT_URL := "ws://127.0.0.1:8000/viewer"
const RECONNECT_SECONDS := 2.0
const KEEPALIVE_SECONDS := 5.0

var url: String = DEFAULT_URL

var _socket := WebSocketPeer.new()
var _connected := false
var _reconnect_in := 0.0
var _keepalive_in := KEEPALIVE_SECONDS


## Command line wins over the environment so a single build can drive several
## machines: godot --path viewer -- --gm-url=ws://10.0.0.5:8000/viewer
static func resolve_url() -> String:
	for argument in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if argument.begins_with("--gm-url="):
			return argument.trim_prefix("--gm-url=")
	var from_environment := OS.get_environment("CPR_VIEWER_WS")
	if from_environment != "":
		return from_environment
	return DEFAULT_URL


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_set_connected(true)
			while _socket.get_available_packet_count() > 0:
				_receive(_socket.get_packet().get_string_from_utf8())
			_keepalive_in -= delta
			if _keepalive_in <= 0.0:
				_keepalive_in = KEEPALIVE_SECONDS
				_socket.send_text("ping")
		WebSocketPeer.STATE_CLOSED:
			_set_connected(false)
			_reconnect_in -= delta
			if _reconnect_in <= 0.0:
				_reconnect_in = RECONNECT_SECONDS
				_open()
		_:
			pass


func _open() -> void:
	var error := _socket.connect_to_url(url)
	if error != OK:
		push_warning("Viewer could not reach %s (%d); retrying." % [url, error])


func _set_connected(value: bool) -> void:
	if _connected == value:
		return
	_connected = value
	if value:
		_keepalive_in = KEEPALIVE_SECONDS
	connection_changed.emit(value)


func _receive(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Viewer ignored a malformed message from the GM service.")
		return
	var message: Dictionary = parsed
	match String(message.get("type", "")):
		"snapshot":
			snapshot_received.emit(message)
		"rules":
			rules_received.emit(message)
		"error":
			push_warning("GM service reported: %s" % message.get("detail", "unknown error"))
		_:
			push_warning("Viewer ignored an unknown message type.")
