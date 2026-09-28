extends SceneTree
## Headless command line entry point (no editor window needed).
##
##   godot --headless --path <project> --script res://addons/vibe_core/cli/vibe_cli.gd -- [options]
##
## Options:
##   --scene <res://x.tscn>   target scene (loaded if it exists, created on save otherwise)
##   --cmd '<json>'           {"cmd": "terrain.create", "args": {...}} or an array of those
##   --batch <file.json>      JSON file with an array of commands (or {"commands": [...]})
##   --schema                 print the full command schema
##   --write-schema <file>    write the command schema to a JSON file
##   --no-save                do not save the scene/data at the end
##   --keep-going             do not stop at the first failing command
##
## The result is printed as ONE line prefixed with @@VIBE@@ followed by JSON,
## so wrappers (tools/vibe.py, the MCP server) can ignore Godot's own logs.

const Registry = preload("res://addons/vibe_core/core/vibe_registry.gd")
const Context = preload("res://addons/vibe_core/core/vibe_context.gd")
const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const MARKER := "@@VIBE@@"


func _initialize() -> void:
	_main.call_deferred()


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var o := {"scene": "", "cmd": "", "batch": "", "schema": false, "write_schema": "", "no_save": false, "keep_going": false}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		match a:
			"--scene":
				i += 1
				o.scene = argv[i] if i < argv.size() else ""
			"--cmd":
				i += 1
				o.cmd = argv[i] if i < argv.size() else ""
			"--batch":
				i += 1
				o.batch = argv[i] if i < argv.size() else ""
			"--write-schema":
				i += 1
				o.write_schema = argv[i] if i < argv.size() else ""
			"--schema":
				o.schema = true
			"--no-save":
				o.no_save = true
			"--keep-going":
				o.keep_going = true
		i += 1
	return o


func _emit(payload: Dictionary) -> void:
	print(MARKER + JSON.stringify(Util.to_json_safe(payload)))


func _main() -> void:
	var opts := _parse_args(OS.get_cmdline_user_args())
	var registry = Registry.new()
	var modules: Array = registry.discover_modules()

	if opts.schema or opts.write_schema != "":
		var schema := {
			"generated_by": "vibe_cli.gd --write-schema",
			"godot": Engine.get_version_info().get("string", ""),
			"modules": modules,
			"commands": registry.get_schema(),
		}
		if opts.write_schema != "":
			var f := FileAccess.open(opts.write_schema, FileAccess.WRITE)
			if f == null:
				_emit({"ok": false, "error": "cannot write %s" % opts.write_schema})
				quit(1)
				return
			f.store_string(JSON.stringify(schema, "  ", false) + "\n")
			f.close()
			_emit({"ok": true, "written": opts.write_schema, "commands": registry.get_command_names().size()})
		else:
			_emit(schema)
		quit(0)
		return

	var commands: Array = []
	if opts.cmd != "":
		var parsed = JSON.parse_string(opts.cmd)
		if parsed is Dictionary:
			commands = [parsed]
		elif parsed is Array:
			commands = parsed
		else:
			_emit({"ok": false, "error": "--cmd must be a JSON object or array"})
			quit(2)
			return
	elif opts.batch != "":
		var f := FileAccess.open(opts.batch, FileAccess.READ)
		if f == null:
			_emit({"ok": false, "error": "cannot read batch file %s" % opts.batch})
			quit(2)
			return
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and parsed.has("commands"):
			parsed = parsed.commands
		if not (parsed is Array):
			_emit({"ok": false, "error": "batch file must contain a JSON array of commands"})
			quit(2)
			return
		commands = parsed
	else:
		commands = [{"cmd": "help", "args": {}}]

	var ctx = Context.new()
	ctx.mode = "headless"
	ctx.source = "cli"
	ctx.registry = registry
	ctx.tree = self
	if opts.scene != "":
		var path := Util.to_res_path(opts.scene, "tscn")
		ctx.scene_path = path
		if ResourceLoader.exists(path):
			var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if packed is PackedScene:
				var state := PackedScene.GEN_EDIT_STATE_MAIN if OS.has_feature("editor") else PackedScene.GEN_EDIT_STATE_DISABLED
				ctx.root = (packed as PackedScene).instantiate(state)
				root.add_child(ctx.root)
			else:
				_emit({"ok": false, "error": "not a scene: %s" % path})
				quit(2)
				return

	var results: Array = []
	var all_ok := true
	for c in commands:
		if not (c is Dictionary):
			continue
		var args = c.get("args", {})
		var r: Dictionary = await registry.execute(str(c.get("cmd", c.get("command", ""))), args if args is Dictionary else {}, ctx)
		var log_lines: Array = ctx.take_log()
		if not log_lines.is_empty():
			r["log"] = log_lines
		results.append(r)
		if not r.get("ok", false):
			all_ok = false
			if not opts.keep_going:
				break

	var saved = null
	if ctx.root != null and ctx.dirty and not opts.no_save and ctx.scene_path != "":
		saved = ctx.save_scene()
		if Util.is_err(saved):
			all_ok = false
			saved = {"error": saved[Util.ERROR_KEY]}
	_emit({"ok": all_ok, "mode": "headless", "scene": ctx.scene_path, "results": results, "saved": saved})
	if ctx.root != null and is_instance_valid(ctx.root):
		ctx.root.queue_free()
		ctx.root = null
	await process_frame
	quit(0 if all_ok else 1)
