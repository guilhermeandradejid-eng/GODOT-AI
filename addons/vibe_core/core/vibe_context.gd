@tool
extends RefCounted
## Execution context for Vibe commands.
##
## The same command code runs in two very different places:
##  * "editor"   – inside the Godot editor (live bridge / dock). Changes are
##                 applied to the currently edited scene and are undoable.
##  * "headless" – from the terminal (`godot --headless --script vibe_cli.gd`).
##                 The scene is loaded from disk, modified and saved back.
## Handlers only talk to this object, never to EditorInterface directly.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const TERRAIN_GROUP := Util.TERRAIN_GROUP
const GRASS_GROUP := Util.GRASS_GROUP
const VFX_GROUP := Util.VFX_GROUP

var mode := "headless"
var source := "cli"
var root: Node = null
var scene_path := ""
var tree: SceneTree = null
var editor_interface: Object = null
var undo_redo: Object = null
var plugin: Object = null
var registry = null
var dirty := false
var auto_save := true

var _warnings: Array = []
var _log: Array = []
var _depth := 0
var _action_open := false
var _action_name := ""


func is_editor() -> bool:
	return mode == "editor"


# --- Command lifecycle (called by the registry) --------------------------------

func begin_command(command_name: String) -> void:
	_depth += 1
	if _depth == 1:
		_action_name = "Vibe: " + command_name
		_log.clear()


func end_command() -> void:
	_depth = maxi(0, _depth - 1)
	if _depth == 0 and _action_open:
		_action_open = false
		undo_redo.commit_action(false)


func abort_command() -> void:
	# Partial changes stay applied, so they must stay undoable too.
	end_command()


func warn(message: String) -> void:
	_warnings.append(message)


func take_warnings() -> Array:
	var w := _warnings.duplicate()
	_warnings.clear()
	return w


func info(message: String) -> void:
	_log.append(message)
	if mode == "editor":
		print_rich("[color=#7fd]Vibe[/color] ", message)


func get_log() -> Array:
	return _log.duplicate()


## Returns and clears the log lines of the last command(s).
func take_log() -> Array:
	var l := _log.duplicate()
	_log.clear()
	return l


# --- Undo helpers -----------------------------------------------------------------

func _ensure_action() -> bool:
	if mode != "editor" or undo_redo == null:
		return false
	if not _action_open:
		undo_redo.create_action(_action_name if _action_name != "" else "Vibe", UndoRedo.MERGE_DISABLE, root, true)
		_action_open = true
	return true


## Records an already-applied change as an undoable method pair.
func record_method(obj: Object, do_method: StringName, do_args: Array, undo_method: StringName, undo_args: Array) -> void:
	if not _ensure_action():
		return
	undo_redo.add_do_method.callv([obj, do_method] + do_args)
	undo_redo.add_undo_method.callv([obj, undo_method] + undo_args)


## Records a data snapshot change for nodes implementing apply_snapshot(Dictionary).
func record_snapshot(node: Object, before: Dictionary, after: Dictionary) -> void:
	dirty = true
	if not _ensure_action():
		return
	undo_redo.add_do_method(node, &"apply_snapshot", after)
	undo_redo.add_undo_method(node, &"apply_snapshot", before)


# --- Scene helpers -----------------------------------------------------------------

func require_root() -> Variant:
	if root == null:
		if is_editor():
			return Util.err("No scene is open in the editor. Use 'scene.new' (e.g. {\"path\": \"res://scenes/world.tscn\"}) or open one.")
		return Util.err("No target scene. Pass --scene res://path.tscn or run 'scene.new' first.")
	return null


## Adds `node` under `parent` (scene root by default), owned by the scene so it is saved.
func add_node(node: Node, parent: Node = null, own_children: bool = false) -> Node:
	if parent == null:
		parent = root
	parent.add_child(node, true)
	node.owner = root
	if own_children:
		for c in _descendants(node):
			c.owner = root
	dirty = true
	if _ensure_action():
		undo_redo.add_do_method(parent, &"add_child", node, true)
		undo_redo.add_do_property(node, &"owner", root)
		undo_redo.add_do_reference(node)
		undo_redo.add_undo_method(parent, &"remove_child", node)
	return node


func remove_node(node: Node) -> void:
	if node == null or node == root:
		return
	var parent := node.get_parent()
	if parent == null:
		return
	var index := node.get_index()
	var owned: Array = []
	for c in [node] + _descendants(node):
		if c.owner == root:
			owned.append(c)
	parent.remove_child(node)
	dirty = true
	if _ensure_action():
		undo_redo.add_do_method(parent, &"remove_child", node)
		undo_redo.add_undo_method(parent, &"add_child", node, true)
		undo_redo.add_undo_method(parent, &"move_child", node, index)
		for c in owned:
			undo_redo.add_undo_property(c, &"owner", root)
		undo_redo.add_undo_reference(node)
	else:
		node.queue_free()


## Sets a property with undo support.
func set_property(obj: Object, property: StringName, value: Variant) -> void:
	var old = obj.get(property)
	obj.set(property, value)
	dirty = true
	if _ensure_action():
		undo_redo.add_do_property(obj, property, value)
		undo_redo.add_undo_property(obj, property, old)


func _descendants(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out


func all_nodes() -> Array:
	if root == null:
		return []
	return [root] + _descendants(root)


func nodes_in_group(group: StringName) -> Array:
	var out: Array = []
	for n in all_nodes():
		if n.is_in_group(group):
			out.append(n)
	return out


## Finds a node by path (relative to the scene root), by name, or returns null.
func find_node(name_or_path: String) -> Node:
	if root == null or name_or_path == "":
		return null
	var s := name_or_path.strip_edges()
	if s == "." or s == str(root.name):
		return root
	var n := root.get_node_or_null(NodePath(s))
	if n != null:
		return n
	return root.find_child(s, true, false)


## Returns a node of the given group by name, or the first one if name is empty.
func find_in_group(group: StringName, name: String = "") -> Node:
	var list := nodes_in_group(group)
	if list.is_empty():
		return null
	if name == "":
		return list[0]
	for n in list:
		if str(n.name) == name or str(root.get_path_to(n)) == name:
			return n
	var norm := Util.normalize_text(name)
	for n in list:
		if Util.normalize_text(str(n.name)) == norm:
			return n
	return null


func get_terrain(name: String = "") -> Node:
	return find_in_group(TERRAIN_GROUP, name)


func unique_name(base: String, parent: Node = null) -> String:
	if parent == null:
		parent = root
	var candidate := Util.pascal_case(base) if not base.is_valid_identifier() else base
	if parent == null or not parent.has_node(NodePath(candidate)):
		return candidate
	var i := 2
	while parent.has_node(NodePath("%s%d" % [candidate, i])):
		i += 1
	return "%s%d" % [candidate, i]


func node_path(node: Node) -> String:
	if root == null or node == null:
		return ""
	if node == root:
		return "."
	return str(root.get_path_to(node))


## Converts a position argument into a world position.
## Accepts [x, y, z], [x, z] (snapped onto the terrain), {"x":..,"z":..}
## or an anchor string such as "center", "north", "peak", "flat", "random".
func resolve_position(value: Variant, y_offset: float = 0.0, seed_value: int = 0) -> Variant:
	var terrain := get_terrain()
	if value == null:
		value = "center"
	if value is Array and value.size() == 1:
		value = value[0]
	if value is String:
		var anchor: String = Util.normalize_text(value).strip_edges()
		if anchor.begins_with("["):
			var parsed = JSON.parse_string(anchor)
			if parsed is Array:
				return resolve_position(parsed, y_offset, seed_value)
		if terrain != null and terrain.has_method("find_anchor"):
			var p = terrain.find_anchor(anchor, seed_value)
			if p == null:
				return Util.err("unknown position anchor '%s'" % value)
			return p + Vector3.UP * y_offset
		match anchor:
			"center", "centro", "origin", "origem":
				return Vector3(0, y_offset, 0)
		return Util.err("position '%s' needs a terrain in the scene (or use [x, y, z])" % value)
	if value is Dictionary:
		if value.has("y"):
			return Vector3(float(value.x), float(value.y), float(value.z))
		value = [value.get("x", 0.0), value.get("z", 0.0)]
	if value is Array:
		if value.size() >= 3:
			return Vector3(float(value[0]), float(value[1]), float(value[2]))
		if value.size() == 2:
			var x := float(value[0])
			var z := float(value[1])
			var y := 0.0
			if terrain != null and terrain.has_method("get_height_at_world"):
				y = terrain.get_height_at_world(Vector3(x, 0, z))
			return Vector3(x, y + y_offset, z)
	if value is Vector3:
		return value
	return Util.err("invalid position: %s (use [x, z], [x, y, z] or an anchor name)" % str(value))


# --- Resources / saving ---------------------------------------------------------------

## Folder where generated data (terrain heightmaps, grass density...) is stored.
func data_dir() -> String:
	var base := "untitled"
	if scene_path != "":
		base = scene_path.get_file().get_basename()
	elif root != null:
		base = str(root.name)
	return "res://vibe_data".path_join(Util.slugify(base))


func data_path_for(node_name: String, suffix: String) -> String:
	return data_dir().path_join("%s_%s.res" % [Util.slugify(node_name), suffix])


## Gives a resource a file path and writes it, so the scene references it
## externally (keeps .tscn files small and diff-friendly).
func adopt_resource(res: Resource, path: String) -> Error:
	Util.ensure_dir(path.get_base_dir())
	res.take_over_path(path)
	return ResourceSaver.save(res, path)


## Saves data resources of every Vibe node, then the scene itself.
func save_scene(path: String = "") -> Dictionary:
	if root == null:
		return Util.err("nothing to save: no scene")
	if path != "":
		scene_path = path
	if scene_path == "":
		return Util.err("scene has no path; pass {\"path\": \"res://scenes/name.tscn\"}")
	var saved: Array = []
	for n in all_nodes():
		if n.has_method("save_external_data"):
			saved.append_array(n.save_external_data())
	if is_editor():
		var ei = editor_interface
		var current_path: String = root.scene_file_path
		var err := OK
		if current_path == "" or current_path != scene_path:
			ei.save_scene_as(scene_path)
		else:
			err = ei.save_scene()
		if err != OK:
			return Util.err("editor failed to save scene (%s)" % error_string(err))
	else:
		Util.ensure_dir(scene_path.get_base_dir())
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			return Util.err("could not pack scene: %s" % error_string(err))
		err = ResourceSaver.save(packed, scene_path)
		if err != OK:
			return Util.err("could not save scene: %s" % error_string(err))
	dirty = false
	return {"scene": scene_path, "data_files": saved}


func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
