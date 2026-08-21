extends Node

## The Godot half of the local rulebook assistant.
##
## Registered as the `Assistant` autoload. It starts the packaged helper process
## on demand, hands it a session token over the pipe — never on the command line
## — and then talks to it over loopback HTTP. Every visible pixel stays here in
## Godot; PDF extraction, the search index, the credential vault and the one
## request to Anthropic all live inside the helper.
##
## The helper dies with Redline: closing the pipe is its shutdown signal, so a
## crash cannot leave an orphan holding a socket.

signal state_changed(state: String, detail: String)

const STATE_STOPPED := "stopped"
const STATE_STARTING := "starting"
const STATE_READY := "ready"
const STATE_FAILED := "failed"

const TOKEN_HEADER := "X-Redline-Token"
const TOKEN_BYTES := 24
const HANDSHAKE_TIMEOUT_SECONDS := 20.0
const REQUEST_TIMEOUT_SECONDS := 120.0
## One restart is a crash. A second in the same session is a broken install, and
## saying so beats an invisible loop of respawns.
const MAX_RESTARTS := 1

var state := STATE_STOPPED
var detail := ""
var port := 0

var _token := ""
var _process_id := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _thread: Thread
var _restarts := 0
## Requests that arrived before the helper was ready. Held as their parts rather
## than as closures so a queue that cannot be replayed can still be answered:
## every caller gets its on_done exactly once, success or failure.
var _pending: Array[Dictionary] = []


func _ready() -> void:
	name = "Assistant"


func _exit_tree() -> void:
	stop()


func is_ready() -> bool:
	return state == STATE_READY


## The base URL of the running helper, for building request paths.
func base_url() -> String:
	return "http://127.0.0.1:%d" % port


# -- process lifecycle ------------------------------------------------------------


## Start the helper if it is not already running. Safe to call repeatedly.
func start() -> void:
	if state in [STATE_STARTING, STATE_READY]:
		return
	var command := _resolve_command()
	if command.is_empty():
		_fail(
			"Redline could not find its assistant helper. Reinstall Redline, or run it from a checkout with Python available.",
		)
		return
	_token = Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()
	var launched := OS.execute_with_pipe(String(command["path"]), command["arguments"])
	if launched.is_empty() or not launched.has("stdio"):
		_fail("The assistant helper could not be started.")
		return
	_process_id = int(launched.get("pid", -1))
	_stdio = launched["stdio"]
	_stderr = launched.get("stderr")
	_set_state(STATE_STARTING, "Starting the local assistant…")
	_thread = Thread.new()
	# The pipe and pid are passed in, so the worker never touches a field the
	# main thread may be clearing underneath it.
	_thread.start(_handshake.bind(_stdio, _process_id))


## Stop the helper and forget the session token.
func stop() -> void:
	# The process goes first. That ends any pipe read the handshake thread is
	# still blocked on, so joining it below cannot hang Redline's shutdown. The
	# helper holds nothing unsaved: an interrupted index rolls back, and the
	# book returns to "not indexed" the next time Redline starts.
	if _process_id > 0 and OS.is_process_running(_process_id):
		OS.kill(_process_id)
	_process_id = -1
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null
	_token = ""
	port = 0
	# Queued requests survive a stop: restart() and the crash retry below both
	# start the helper again, and _on_handshake replays them. Dropping them here
	# would strand every caller that is still waiting on an answer.
	_set_state(STATE_STOPPED, "")


func restart() -> void:
	stop()
	_restarts = 0
	start()


## Runs on its own thread: the pipe reads block until the helper answers.
##
## The token goes down the pipe and the port comes back up it, so neither ever
## appears in a process list.
func _handshake(pipe: FileAccess, process_id: int) -> void:
	var line := ""
	if pipe != null:
		pipe.store_line(_token)
		pipe.flush()
		var deadline := Time.get_ticks_msec() + int(HANDSHAKE_TIMEOUT_SECONDS * 1000.0)
		while Time.get_ticks_msec() < deadline:
			if not pipe.is_open() or not OS.is_process_running(process_id):
				break
			line = pipe.get_line().strip_edges()
			if line != "":
				break
	call_deferred("_on_handshake", line)


func _on_handshake(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if not parsed is Dictionary or not (parsed as Dictionary).has("port"):
		_fail("The assistant helper did not start correctly.")
		return
	port = int((parsed as Dictionary)["port"])
	_set_state(STATE_READY, "")
	for request in _take_pending():
		call_helper(
			int(request["method"]),
			String(request["path"]),
			request["body"],
			request["on_done"] as Callable,
		)


## Give up on the helper and answer everyone still waiting, so no screen is left
## on a spinner that will never resolve.
##
## The attempt is counted before the queue is answered: a caller that retries
## from its own callback then gets the recorded failure instead of provoking
## another respawn. `restart()` clears the count when the GM asks for one.
func _fail(message: String) -> void:
	_restarts += 1
	_set_state(STATE_FAILED, message)
	for request in _take_pending():
		(request["on_done"] as Callable).call(
			{"ok": false, "status": 0, "error": message, "data": {}}
		)


func _take_pending() -> Array[Dictionary]:
	var queued := _pending.duplicate()
	_pending.clear()
	return queued


func _resolve_command() -> Dictionary:
	# An installed Redline ships the helper beside the executable.
	var packaged := OS.get_executable_path().get_base_dir().path_join(
		"redline-assistant.exe" if OS.get_name() == "Windows" else "redline-assistant"
	)
	if FileAccess.file_exists(packaged):
		return {"path": packaged, "arguments": PackedStringArray()}
	# A development checkout runs the same helper from source instead.
	var project := ProjectSettings.globalize_path("res://")
	if not FileAccess.file_exists(project.path_join("assistant/__main__.py")):
		return {}
	var interpreter := OS.get_environment("REDLINE_ASSISTANT_PYTHON")
	if interpreter == "":
		interpreter = "python" if OS.get_name() == "Windows" else "python3"
	return {"path": interpreter, "arguments": PackedStringArray(["-m", "assistant"])}


func _set_state(next: String, message: String) -> void:
	state = next
	detail = message
	state_changed.emit(state, detail)


# -- requests ---------------------------------------------------------------------


## Call the helper. [param on_done] receives a result dictionary carrying
## `ok`, `status`, `data` and, when something went wrong, a readable `error`.
func call_helper(method: int, path: String, body: Variant, on_done: Callable) -> void:
	if state == STATE_STOPPED or state == STATE_FAILED:
		if state == STATE_FAILED and _restarts >= MAX_RESTARTS:
			on_done.call({"ok": false, "status": 0, "error": detail, "data": {}})
			return
		_pending.append({"method": method, "path": path, "body": body, "on_done": on_done})
		# A start that fails outright calls _fail, which answers the queue this
		# request just joined; a start that succeeds replays it after the
		# handshake.
		start()
		return
	if state == STATE_STARTING:
		_pending.append({"method": method, "path": path, "body": body, "on_done": on_done})
		return

	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
			request.queue_free()
			_complete(result, code, bytes, method, path, body, on_done)
	)
	var headers := PackedStringArray(
		["%s: %s" % [TOKEN_HEADER, _token], "Content-Type: application/json"]
	)
	var payload := "" if body == null else JSON.stringify(body)
	var error := request.request(base_url() + path, headers, method, payload)
	if error != OK:
		request.queue_free()
		on_done.call({"ok": false, "status": 0, "error": "The assistant is not reachable.", "data": {}})


func _complete(
	result: int,
	code: int,
	bytes: PackedByteArray,
	method: int,
	path: String,
	body: Variant,
	on_done: Callable,
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		# A dead helper is restarted once, and the request is tried again.
		if _restarts < MAX_RESTARTS:
			_restarts += 1
			stop()
			_pending.append({"method": method, "path": path, "body": body, "on_done": on_done})
			start()
			return
		var message := "The assistant helper stopped responding. Restart Redline to try again."
		_fail(message)
		on_done.call({"ok": false, "status": 0, "error": message, "data": {}})
		return

	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if code >= 200 and code < 300:
		on_done.call({"ok": true, "status": code, "error": "", "data": data})
		return
	# Only the helper's own errors carry a coded detail object. FastAPI answers a
	# rejected body with a list and a bad route with a string, so the code is read
	# from a dictionary or not at all.
	var detail_value: Variant = data.get("detail", null)
	var code_name := ""
	if detail_value is Dictionary:
		code_name = String((detail_value as Dictionary).get("code", ""))
	on_done.call(
		{
			"ok": false,
			"status": code,
			"error": describe_error(data, code),
			"code": code_name,
			"data": data,
		}
	)


## Turn a helper error body into one sentence a GM can act on.
static func describe_error(data: Dictionary, code: int) -> String:
	var detail_value: Variant = data.get("detail", null)
	if detail_value is Dictionary:
		var message := String((detail_value as Dictionary).get("message", ""))
		if message != "":
			return message
	if detail_value is String and String(detail_value) != "":
		return String(detail_value)
	if detail_value is Array and not (detail_value as Array).is_empty():
		# FastAPI's validation errors arrive as a list of field problems.
		var first: Variant = (detail_value as Array)[0]
		if first is Dictionary:
			return String((first as Dictionary).get("msg", "That request was not accepted."))
		return "That request was not accepted."
	return "The assistant returned an error (%d)." % code


# -- the calls the screens make ----------------------------------------------------


func fetch_library(on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_GET, "/library", null, on_done)


func import_book(path: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_POST, "/library/import", {"path": path}, on_done)


func reindex_book(book_id: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_POST, "/library/%s/reindex" % book_id, null, on_done)


func rename_book(book_id: String, label: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_PATCH, "/library/%s" % book_id, {"label": label}, on_done)


func remove_book(book_id: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_DELETE, "/library/%s" % book_id, null, on_done)


func store_key(key: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_PUT, "/key", {"key": key}, on_done)


func remove_key(on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_DELETE, "/key", null, on_done)


func test_key(on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_POST, "/key/test", null, on_done)


func save_settings(changes: Dictionary, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_PUT, "/settings", changes, on_done)


func ask(question: String, book_ids: Array, campaign_id: String, on_done: Callable) -> void:
	call_helper(
		HTTPClient.METHOD_POST,
		"/ask",
		{"question": question, "book_ids": book_ids, "campaign_id": campaign_id},
		on_done,
	)


func fetch_history(campaign_id: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_GET, "/history/%s" % campaign_id, null, on_done)


func clear_history(campaign_id: String, on_done: Callable) -> void:
	call_helper(HTTPClient.METHOD_DELETE, "/history/%s" % campaign_id, null, on_done)
