@tool
extends RefCounted
## Minimal HTTP/1.1 server that exposes the Vibe command registry to the
## terminal while the Godot editor is open ("live mode").
##
## Endpoints (all JSON):
##   GET  /status            -> editor/project/scene info
##   GET  /commands          -> command schema
##   POST /cmd    {"cmd": "terrain.sculpt", "args": {...}}
##   POST /batch  {"commands": [{"cmd": ..., "args": ...}, ...], "stop_on_error": true}
##
## Security: binds to 127.0.0.1 only, requires the per-session token written to
## `.godot/vibe_bridge.json` (header `X-Vibe-Token`), rejects browser requests
## (any `Origin` header) and unexpected `Host` headers (DNS rebinding).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

signal status_changed(listening: bool, port: int)

const INFO_PATH := "res://.godot/vibe_bridge.json"
const MAX_BODY := 16 * 1024 * 1024
const MAX_HEADER := 32 * 1024
const TIMEOUT_MS := 30000
const PORT_ATTEMPTS := 10

var host := "127.0.0.1"
var port := 8423
var token := ""
var require_token := true
var registry = null
## Callable that returns a fresh editor-mode context for each request.
var context_factory: Callable
## Optional Callable returning extra fields for GET /status.
var status_provider: Callable

var _server: TCPServer = null
var _clients: Array = []


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func start(preferred_port: int = 8423) -> Error:
	stop()
	_server = TCPServer.new()
	var err := ERR_CANT_CREATE
	for i in PORT_ATTEMPTS:
		err = _server.listen(preferred_port + i, host)
		if err == OK:
			port = preferred_port + i
			break
	if err != OK:
		_server = null
		push_warning("[Vibe] Bridge could not listen on ports %d-%d" % [preferred_port, preferred_port + PORT_ATTEMPTS - 1])
		status_changed.emit(false, 0)
		return err
	token = _make_token()
	_write_info()
	status_changed.emit(true, port)
	return OK


func stop() -> void:
	for c in _clients:
		(c.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
		_server = null
		_remove_info()
		status_changed.emit(false, 0)


func _make_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func _write_info() -> void:
	var info := {
		"port": port,
		"host": host,
		"token": token,
		"pid": OS.get_process_id(),
		"project": ProjectSettings.globalize_path("res://"),
		"godot": Engine.get_version_info().get("string", ""),
		"started": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(INFO_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "  "))
		f.close()


func _remove_info() -> void:
	if not FileAccess.file_exists(INFO_PATH):
		return
	var f := FileAccess.open(INFO_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	# Only delete the file if it still belongs to this editor instance.
	if data is Dictionary and int(data.get("pid", -1)) == OS.get_process_id():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INFO_PATH))


## Call every frame (EditorPlugin._process).
func poll() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "buf": PackedByteArray(), "t": Time.get_ticks_msec(), "busy": false})
	for c in _clients.duplicate():
		if c.busy:
			continue
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var r: Array = peer.get_partial_data(available)
			if r[0] == OK:
				(c.buf as PackedByteArray).append_array(r[1])
		var req := _parse_request(c.buf)
		if req.is_empty():
			if Time.get_ticks_msec() - int(c.t) > TIMEOUT_MS:
				_close(c)
			continue
		c.busy = true
		if req.has("error"):
			_respond(c, int(req.status), {"ok": false, "error": req.error})
		else:
			_handle(c, req)


func _parse_request(buf: PackedByteArray) -> Dictionary:
	if buf.is_empty():
		return {}
	var head_bytes := buf.slice(0, mini(buf.size(), MAX_HEADER))
	var head := head_bytes.get_string_from_ascii()
	var header_end := head.find("\r\n\r\n")
	if header_end < 0:
		if buf.size() >= MAX_HEADER:
			return {"error": "request header too large", "status": 431}
		return {}
	var lines := head.substr(0, header_end).split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {"error": "malformed request line", "status": 400}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		return {"error": "request body too large", "status": 413}
	var body_start := header_end + 4
	if buf.size() < body_start + length:
		return {}
	var body := buf.slice(body_start, body_start + length).get_string_from_utf8()
	var path: String = request_line[1]
	var query := ""
	if path.contains("?"):
		query = path.get_slice("?", 1)
		path = path.get_slice("?", 0)
	return {"method": request_line[0].to_upper(), "path": path, "query": query, "headers": headers, "body": body}


func _authorize(req: Dictionary) -> Dictionary:
	var headers: Dictionary = req.headers
	if headers.has("origin"):
		return {"status": 403, "error": "browser requests are not allowed"}
	var host_header: String = headers.get("host", "")
	var allowed := ["127.0.0.1:%d" % port, "localhost:%d" % port, "[::1]:%d" % port, "127.0.0.1", "localhost"]
	if host_header != "" and not allowed.has(host_header):
		return {"status": 403, "error": "unexpected Host header"}
	if require_token and headers.get("x-vibe-token", "") != token:
		return {"status": 401, "error": "missing or invalid X-Vibe-Token (read it from .godot/vibe_bridge.json)"}
	return {}


func _handle(c: Dictionary, req: Dictionary) -> void:
	var denied := _authorize(req)
	if not denied.is_empty():
		_respond(c, denied.status, {"ok": false, "error": denied.error})
		return
	var method: String = req.method
	var path: String = req.path
	if method == "GET" and (path == "/" or path == "/status"):
		_respond(c, 200, _status())
		return
	if method == "GET" and path == "/commands":
		_respond(c, 200, {"ok": true, "commands": registry.get_schema()})
		return
	if method == "POST" and (path == "/cmd" or path == "/batch"):
		var parsed = JSON.parse_string(req.body) if req.body != "" else {}
		if not (parsed is Dictionary):
			_respond(c, 400, {"ok": false, "error": "body must be a JSON object"})
			return
		var ctx = context_factory.call()
		if path == "/cmd":
			var cmd_name := str(parsed.get("cmd", parsed.get("command", "")))
			var args = parsed.get("args", {})
			if not (args is Dictionary):
				args = {}
			var result: Dictionary = await registry.execute(cmd_name, args, ctx)
			var log_lines: Array = ctx.take_log()
			if not log_lines.is_empty():
				result["log"] = log_lines
			_respond(c, 200, result)
		else:
			var commands = parsed.get("commands", [])
			var stop_on_error := Util.to_bool(parsed.get("stop_on_error", true))
			var results: Array = []
			var all_ok := true
			if commands is Array:
				for item in commands:
					if not (item is Dictionary):
						continue
					var args = item.get("args", {})
					var r: Dictionary = await registry.execute(str(item.get("cmd", "")), args if args is Dictionary else {}, ctx)
					results.append(r)
					if not r.get("ok", false):
						all_ok = false
						if stop_on_error:
							break
			_respond(c, 200, {"ok": all_ok, "results": results})
		return
	_respond(c, 404, {"ok": false, "error": "unknown endpoint %s %s (use GET /status, GET /commands, POST /cmd, POST /batch)" % [method, path]})


func _status() -> Dictionary:
	var out := {
		"ok": true,
		"mode": "editor",
		"godot": Engine.get_version_info().get("string", ""),
		"project": ProjectSettings.get_setting("application/config/name", ""),
		"port": port,
		"commands": registry.get_command_names().size() if registry != null else 0,
	}
	if status_provider.is_valid():
		out.merge(status_provider.call(), true)
	return out


func _respond(c: Dictionary, status: int, payload: Variant) -> void:
	var peer: StreamPeerTCP = c.peer
	var reason := {200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large", 431: "Request Header Fields Too Large", 500: "Internal Server Error"}
	var body := JSON.stringify(Util.to_json_safe(payload)).to_utf8_buffer()
	var header := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % [status, reason.get(status, "OK"), body.size()]
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(header.to_ascii_buffer())
		peer.put_data(body)
	_close(c)


func _close(c: Dictionary) -> void:
	(c.peer as StreamPeerTCP).disconnect_from_host()
	_clients.erase(c)
