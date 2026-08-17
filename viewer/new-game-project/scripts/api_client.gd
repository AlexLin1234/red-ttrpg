class_name GMApiClient
extends Node

signal request_succeeded(kind: String, payload: Dictionary)
signal request_failed(kind: String, message: String, transport_failure: bool)
signal map_image_succeeded(image: Image)

@export var base_url := "http://127.0.0.1:8000"

var _http: HTTPRequest
var _active_kind := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 4.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func is_busy() -> bool:
	return _active_kind != ""


func fetch_session() -> void:
	_request("/encounter", HTTPClient.METHOD_GET, {}, "fetch")


func fetch_map() -> void:
	_request("/map", HTTPClient.METHOD_GET, {}, "map_fetch")


func fetch_map_image(path: String) -> void:
	_request_raw(path, HTTPClient.METHOD_GET, PackedStringArray(), PackedByteArray(), "map_image")


func upload_map(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		request_failed.emit("map_upload", "Could not read the selected map image.", false)
		return
	var bytes := file.get_buffer(file.get_length())
	var filename := file_path.get_file().uri_encode()
	_request_raw(
		"/map/image?filename=" + filename,
		HTTPClient.METHOD_PUT,
		PackedStringArray(["Content-Type: application/octet-stream"]),
		bytes,
		"map_upload",
	)


func save_map_zones(zones: Array) -> void:
	_request("/map/zones", HTTPClient.METHOD_PUT, {"zones": zones}, "map_zones")


func reset_session(state: Dictionary) -> void:
	_request(
		"/encounter",
		HTTPClient.METHOD_POST,
		{
			"actors": state.get("actors", {}),
			"current_month": state.get("current_month"),
		},
		"reset",
	)


func resolve_attack(payload: Dictionary) -> void:
	_request("/resolve", HTTPClient.METHOD_POST, payload, "resolve")


func reload(payload: Dictionary) -> void:
	_request("/encounter/reload", HTTPClient.METHOD_POST, payload, "reload")


func close_month(month: Variant = null) -> void:
	_request("/encounter/month-end", HTTPClient.METHOD_POST, {"month": month}, "month_end")


func undo() -> void:
	_request("/encounter/undo", HTTPClient.METHOD_POST, {}, "undo")


func redo() -> void:
	_request("/encounter/redo", HTTPClient.METHOD_POST, {}, "redo")


func _request(path: String, method: HTTPClient.Method, payload: Dictionary, kind: String) -> void:
	if is_busy():
		request_failed.emit(kind, "The rules service is busy. Try again in a moment.", false)
		return
	_active_kind = kind
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var error := _http.request(base_url + path, headers, method, body)
	if error != OK:
		_active_kind = ""
		request_failed.emit(kind, "Could not start HTTP request (error %s)." % error, true)


func _request_raw(
	path: String,
	method: HTTPClient.Method,
	headers: PackedStringArray,
	body: PackedByteArray,
	kind: String,
) -> void:
	if is_busy():
		request_failed.emit(kind, "The rules service is busy. Try again in a moment.", false)
		return
	_active_kind = kind
	var error := _http.request_raw(base_url + path, headers, method, body)
	if error != OK:
		_active_kind = ""
		request_failed.emit(kind, "Could not start HTTP request (error %s)." % error, true)


func _on_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	var kind := _active_kind
	_active_kind = ""
	if kind == "map_image" and response_code >= 200 and response_code < 300:
		var image := Image.new()
		var image_error := image.load_png_from_buffer(body)
		if image_error == OK:
			map_image_succeeded.emit(image)
			return
		request_failed.emit(kind, "The map service returned an unreadable image.", false)
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if response_code >= 200 and response_code < 300 and parsed is Dictionary:
		request_succeeded.emit(kind, parsed)
		return
	var message := "Rules service returned HTTP %s." % response_code
	if parsed is Dictionary and parsed.has("detail"):
		message = str(parsed["detail"])
	elif not text.is_empty():
		message = text
	request_failed.emit(kind, message, response_code == 0)
