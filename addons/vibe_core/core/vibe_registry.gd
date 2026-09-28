@tool
extends RefCounted
## Command registry shared by all Vibe addons.
##
## Commands are discovered automatically: every addon folder that contains a
## `vibe_commands.gd` script (with a `register(registry)` method) contributes
## its commands. The same registry powers the live editor bridge (HTTP), the
## headless CLI, the MCP server schema and the "Vibe" dock console.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

signal command_executed(entry: Dictionary)

var _commands := {}
var _aliases := {}
var _modules: Array = []
var history: Array = []
var max_history := 200


## Loads every `res://addons/*/vibe_commands.gd` module.
func discover_modules(addons_dir: String = "res://addons") -> Array:
	var loaded: Array = []
	var dir := DirAccess.open(addons_dir)
	if dir == null:
		return loaded
	var names: Array = Array(dir.get_directories())
	names.sort()
	# vibe_core first so generic commands are registered before extensions.
	if names.has("vibe_core"):
		names.erase("vibe_core")
		names.push_front("vibe_core")
	for n in names:
		var path: String = addons_dir.path_join(n).path_join("vibe_commands.gd")
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			continue
		var script = load(path)
		if script == null or not (script is Script) or not (script as Script).can_instantiate():
			push_warning("[Vibe] Could not load command module (script error?): %s" % path)
			continue
		var module = script.new()
		if module == null or not module.has_method("register"):
			push_warning("[Vibe] %s has no register(registry) method" % path)
			continue
		module.register(self)
		_modules.append(module)
		loaded.append(n)
	return loaded


## Registers a command.
## spec = {description, args: {name: {type, default, required, description, enum}}, handler: Callable}
func add(command_name: String, spec: Dictionary) -> void:
	if not spec.has("handler") or not (spec.handler is Callable):
		push_error("[Vibe] Command '%s' has no handler Callable" % command_name)
		return
	var s := spec.duplicate()
	s["name"] = command_name
	if not s.has("args"):
		s["args"] = {}
	if not s.has("description"):
		s["description"] = ""
	if not s.has("category"):
		s["category"] = command_name.get_slice(".", 0) if command_name.contains(".") else "core"
	_commands[command_name] = s
	_aliases[command_name.replace(".", "_")] = command_name
	_aliases[command_name.replace(".", "-")] = command_name
	_aliases[command_name.replace(".", "_").replace("_", "")] = command_name
	for a in spec.get("aliases", []):
		_aliases[str(a)] = command_name


func remove(command_name: String) -> void:
	_commands.erase(command_name)


func has_command(command_name: String) -> bool:
	return resolve_name(command_name) != ""


func resolve_name(command_name: String) -> String:
	var n := command_name.strip_edges().to_lower()
	if _commands.has(n):
		return n
	if _aliases.has(n):
		return _aliases[n]
	return ""


func get_command_names() -> Array:
	var names := _commands.keys()
	names.sort()
	return names


func get_spec(command_name: String) -> Dictionary:
	var n := resolve_name(command_name)
	return _commands.get(n, {})


## Returns a JSON-friendly description of every command (used by `help`,
## the MCP server and the generated commands.schema.json snapshot).
func get_schema(filter: String = "") -> Array:
	var out: Array = []
	for n in get_command_names():
		if filter != "" and not n.begins_with(filter):
			continue
		var spec: Dictionary = _commands[n]
		var args_out := {}
		var props := {}
		var required: Array = []
		for arg_name in spec.args:
			var a: Dictionary = spec.args[arg_name]
			var entry := {"type": a.get("type", "any"), "description": a.get("description", "")}
			if a.has("default"):
				entry["default"] = Util.to_json_safe(a["default"])
			if a.has("enum"):
				entry["enum"] = a["enum"]
			if a.get("required", false):
				entry["required"] = true
				required.append(arg_name)
			args_out[arg_name] = entry
			props[arg_name] = _json_schema_for(a)
		var js := {"type": "object", "properties": props}
		if not required.is_empty():
			js["required"] = required
		out.append({
			"name": n,
			"category": spec.category,
			"description": spec.description,
			"editor_only": spec.get("editor_only", false),
			"args": args_out,
			"input_schema": js,
			"examples": spec.get("examples", []),
		})
	return out


func _json_schema_for(a: Dictionary) -> Dictionary:
	var desc: String = a.get("description", "")
	var s := {}
	match a.get("type", "any"):
		"string":
			s = {"type": "string"}
		"number":
			s = {"type": "number"}
		"integer":
			s = {"type": "integer"}
		"boolean":
			s = {"type": "boolean"}
		"array":
			s = {"type": "array"}
		"object":
			s = {"type": "object"}
		"vector3":
			s = {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}
		"color":
			s = {"type": "string"}
			desc += " (hex '#rrggbb' or a color name such as 'red'/'vermelho')"
		"position":
			desc += " ([x, z] on the terrain surface, [x, y, z], or an anchor: center, north, south, east, west, northeast, northwest, southeast, southwest, peak, valley, flat, beach, random)"
		_:
			pass
	if a.has("enum"):
		s["enum"] = a["enum"]
	if a.has("default"):
		s["default"] = Util.to_json_safe(a["default"])
	s["description"] = desc
	return s


func _coerce_args(spec: Dictionary, raw_args: Dictionary) -> Dictionary:
	var out := {}
	var warnings: Array = []
	var specs: Dictionary = spec.args
	for arg_name in raw_args:
		if not specs.has(arg_name):
			if spec.get("allow_extra_args", false):
				out[arg_name] = raw_args[arg_name]
			else:
				warnings.append("unknown argument '%s' ignored (see: help %s)" % [arg_name, spec.name])
	for arg_name in specs:
		var a: Dictionary = specs[arg_name]
		if raw_args.has(arg_name) and raw_args[arg_name] != null:
			var res := Util.coerce(raw_args[arg_name], a.get("type", "any"))
			if not res[0]:
				return {"ok": false, "error": "argument '%s': %s" % [arg_name, res[1]]}
			var v = res[1]
			if a.has("enum") and v is String:
				var options: Array = a["enum"]
				var norm := Util.normalize_text(v)
				if not options.has(v) and options.has(norm):
					v = norm
				if not options.has(v) and not a.get("open_enum", false):
					return {"ok": false, "error": "argument '%s' must be one of %s (got '%s')" % [arg_name, str(options), v]}
			out[arg_name] = v
		elif a.get("required", false):
			return {"ok": false, "error": "missing required argument '%s' (see: help %s)" % [arg_name, spec.name]}
		elif a.has("default"):
			var d = a["default"]
			out[arg_name] = d.duplicate(true) if (d is Array or d is Dictionary) else d
	return {"ok": true, "args": out, "warnings": warnings}


## Executes a command. This is a coroutine: always call it with `await`.
func execute(command_name: String, raw_args: Dictionary, ctx) -> Dictionary:
	var started := Time.get_ticks_msec()
	var n := resolve_name(command_name)
	if n == "":
		var suggestion := _suggest(command_name)
		var msg := "unknown command '%s'" % command_name
		if suggestion != "":
			msg += " (did you mean '%s'?)" % suggestion
		return _finish(command_name, raw_args, {"ok": false, "error": msg + ". Use 'help' to list commands."}, started, ctx)
	var spec: Dictionary = _commands[n]
	if spec.get("editor_only", false) and not ctx.is_editor():
		return _finish(n, raw_args, {"ok": false, "error": "'%s' needs the Godot editor open with the Vibe plugins enabled (live bridge)." % n}, started, ctx)
	var coerced := _coerce_args(spec, raw_args)
	if not coerced.ok:
		return _finish(n, raw_args, {"ok": false, "error": coerced.error}, started, ctx)
	ctx.begin_command(n)
	for w in coerced.warnings:
		ctx.warn(w)
	var result = await spec.handler.call(coerced.args, ctx)
	var out := {}
	if Util.is_err(result):
		out = {"ok": false, "error": result[Util.ERROR_KEY]}
		ctx.abort_command()
	else:
		out = {"ok": true, "result": Util.to_json_safe(result)}
		ctx.end_command()
	return _finish(n, raw_args, out, started, ctx)


func _finish(command_name: String, raw_args: Dictionary, out: Dictionary, started: int, ctx) -> Dictionary:
	out["cmd"] = command_name
	if ctx != null:
		var w: Array = ctx.take_warnings()
		if not w.is_empty():
			out["warnings"] = w
	out["ms"] = Time.get_ticks_msec() - started
	var entry := {
		"cmd": command_name,
		"args": Util.to_json_safe(raw_args),
		"ok": out.get("ok", false),
		"error": out.get("error", ""),
		"ms": out["ms"],
		"source": ctx.source if ctx != null else "",
		"time": Time.get_time_string_from_system(),
	}
	history.append(entry)
	if history.size() > max_history:
		history.pop_front()
	command_executed.emit(entry)
	return out


func _suggest(command_name: String) -> String:
	var best := ""
	var best_score := 0.0
	var target := command_name.to_lower()
	for n in _commands:
		var score := target.similarity(n)
		if score > best_score:
			best_score = score
			best = n
	return best if best_score > 0.45 else ""
