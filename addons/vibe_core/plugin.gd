@tool
extends EditorPlugin
## Vibe Core: command registry + live HTTP bridge + "Vibe" dock.
##
## While this plugin is enabled, Claude Code (or any terminal tool) can drive
## the editor through `python3 tools/vibe.py <command>` or the MCP server,
## and every change shows up live in the viewport (and is undoable).

const Registry = preload("res://addons/vibe_core/core/vibe_registry.gd")
const Context = preload("res://addons/vibe_core/core/vibe_context.gd")
const Bridge = preload("res://addons/vibe_core/core/vibe_bridge.gd")
const Dock = preload("res://addons/vibe_core/ui/vibe_dock.gd")

const SETTINGS := {
	"vibe/bridge/enabled": [TYPE_BOOL, true, PROPERTY_HINT_NONE, ""],
	"vibe/bridge/port": [TYPE_INT, 8423, PROPERTY_HINT_RANGE, "1024,65535"],
	"vibe/bridge/require_token": [TYPE_BOOL, true, PROPERTY_HINT_NONE, ""],
}

var registry = null
var bridge = null
var dock = null


func _enter_tree() -> void:
	_ensure_settings()
	registry = Registry.new()
	# Other Vibe plugins (docks) run commands through this registry.
	Engine.set_meta(&"vibe_core_plugin", self)
	var modules: Array = registry.discover_modules()
	bridge = Bridge.new()
	bridge.registry = registry
	bridge.context_factory = make_context.bind("bridge")
	bridge.status_provider = _status_extra
	dock = Dock.new()
	dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	registry.command_executed.connect(dock.on_command_executed)
	bridge.status_changed.connect(dock.set_bridge_status)
	if ProjectSettings.get_setting("vibe/bridge/enabled", true):
		bridge.require_token = ProjectSettings.get_setting("vibe/bridge/require_token", true)
		bridge.start(int(ProjectSettings.get_setting("vibe/bridge/port", 8423)))
	dock.set_bridge_status(bridge.is_listening(), bridge.port)
	print_rich("[color=#7fd][Vibe][/color] %d comandos (%s). Bridge: %s" % [
		registry.get_command_names().size(), ", ".join(modules),
		("127.0.0.1:%d" % bridge.port) if bridge.is_listening() else "desligada"])


func _exit_tree() -> void:
	if Engine.has_meta(&"vibe_core_plugin") and Engine.get_meta(&"vibe_core_plugin") == self:
		Engine.remove_meta(&"vibe_core_plugin")
	if bridge != null:
		bridge.stop()
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	if bridge != null:
		bridge.registry = null
		bridge.context_factory = Callable()
		bridge.status_provider = Callable()
		bridge = null
	if registry != null:
		# Breaks handler <-> module cycles so nothing leaks when the editor quits.
		registry.shutdown()
		registry = null


func _process(_delta: float) -> void:
	if bridge != null:
		bridge.poll()


func _get_plugin_name() -> String:
	return "Vibe Core"


## Builds an editor-mode context bound to the currently edited scene.
func make_context(source: String = "dock"):
	var ctx = Context.new()
	ctx.mode = "editor"
	ctx.source = source
	ctx.editor_interface = EditorInterface
	ctx.undo_redo = get_undo_redo()
	ctx.plugin = self
	ctx.registry = registry
	ctx.tree = get_tree()
	ctx.root = EditorInterface.get_edited_scene_root()
	ctx.scene_path = ctx.root.scene_file_path if ctx.root != null else ""
	return ctx


func _status_extra() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	return {
		"scene": root.scene_file_path if root != null else "",
		"open_scenes": Array(EditorInterface.get_open_scenes()),
		"playing": EditorInterface.is_playing_scene(),
	}


func _ensure_settings() -> void:
	for key in SETTINGS:
		var s: Array = SETTINGS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, s[1])
		ProjectSettings.set_initial_value(key, s[1])
		ProjectSettings.add_property_info({"name": key, "type": s[0], "hint": s[2], "hint_string": s[3]})
