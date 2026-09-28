@tool
extends RefCounted
## Core commands: help/status, scenes, generic nodes, camera, screenshots,
## editor control, and the high level "vibe" / "world.*" commands.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const VibeNL = preload("res://addons/vibe_core/core/vibe_nl.gd")
const VibeWorld = preload("res://addons/vibe_core/core/vibe_world.gd")
const FlyCamera = preload("res://addons/vibe_core/runtime/vibe_fly_camera.gd")

const SCREENSHOT_DIR := "res://.vibe/screenshots"
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const STYLE_ALIASES := {
	"realista": "realistic", "real": "realistic", "fotorealista": "realistic", "pbr": "realistic",
	"estilizado": "stylized", "estilizada": "stylized", "pintado": "stylized", "painterly": "stylized", "ghibli": "stylized",
	"cartoon": "toon", "desenho": "toon", "cartunesco": "toon", "anime": "cel", "cel_shading": "cel", "cel-shaded": "cel",
	"celshaded": "cel", "low_poly": "lowpoly", "low-poly": "lowpoly", "poligonal": "lowpoly", "facetado": "lowpoly",
}

var registry = null


func register(reg) -> void:
	registry = reg
	reg.add("help", {
		"description": "Lists every command (grouped by category) or shows the full arguments of one command.",
		"args": {
			"command": {"type": "string", "description": "Command name to describe, e.g. 'terrain.sculpt'."},
			"category": {"type": "string", "description": "Only list commands of a category (core, scene, node, terrain, grass, vfx, env, world)."},
		},
		"handler": _help,
		"examples": [{"command": "terrain.sculpt"}],
	})
	reg.add("status", {
		"description": "Shows where commands run (editor or headless), the open scene and every terrain, grass layer and VFX in it.",
		"handler": _status,
	})
	reg.add("scene.new", {
		"description": "Creates a new 3D scene (Node3D root) at the given path and makes it the target of the next commands (opens it in the editor).",
		"args": {
			"path": {"type": "string", "required": true, "description": "Scene path, e.g. 'res://scenes/world.tscn'."},
			"root_name": {"type": "string", "description": "Root node name (defaults to the file name in PascalCase)."},
			"overwrite": {"type": "boolean", "default": false, "description": "Replace the file if it already exists."},
		},
		"handler": _scene_new,
	})
	reg.add("scene.open", {
		"description": "Opens an existing scene and makes it the target of the next commands.",
		"args": {"path": {"type": "string", "required": true, "description": "Scene path (res://...)."}},
		"handler": _scene_open,
	})
	reg.add("scene.save", {
		"description": "Saves the target scene and the generated data (terrain heightmaps, grass density...).",
		"args": {"path": {"type": "string", "description": "Optional new path (save as)."}},
		"handler": _scene_save,
	})
	reg.add("scene.tree", {
		"description": "Returns the node tree of the target scene (names, types, paths).",
		"args": {"max_depth": {"type": "integer", "default": 4, "description": "Maximum depth to list."}},
		"handler": _scene_tree,
	})
	reg.add("node.add", {
		"description": "Adds any node: a built-in class (MeshInstance3D, OmniLight3D, Camera3D...), a global script class or a scene path (res://x.tscn). Properties accept JSON values ([x,y,z] vectors, '#hex' colors, resource class names like 'BoxMesh' or {\"type\": \"BoxMesh\", \"size\": [2,1,2]}).",
		"args": {
			"type": {"type": "string", "required": true, "description": "Class name, global class or scene path."},
			"name": {"type": "string", "description": "Node name."},
			"parent": {"type": "string", "description": "Parent node path/name (defaults to the scene root)."},
			"position": {"type": "position", "description": "Where to place it (Node3D only)."},
			"properties": {"type": "object", "default": {}, "description": "Property values to set, e.g. {\"light_color\": \"#ffaa55\", \"omni_range\": 12}."},
			"replace": {"type": "boolean", "default": false, "description": "Replace a node with the same name under the parent (instead of adding 'Name2')."},
		},
		"handler": _node_add,
		"examples": [{"type": "MeshInstance3D", "name": "Pedra", "position": [10, 4], "properties": {"mesh": {"type": "SphereMesh", "radius": 2}}}],
	})
	reg.add("node.remove", {
		"description": "Removes a node (and its children) from the scene.",
		"args": {"path": {"type": "string", "required": true, "description": "Node path or name."}},
		"handler": _node_remove,
	})
	reg.add("node.set", {
		"description": "Sets properties of a node (undoable in the editor). Supports nested paths like 'mesh:size'.",
		"args": {
			"path": {"type": "string", "required": true, "description": "Node path or name."},
			"properties": {"type": "object", "required": true, "description": "Property values, e.g. {\"position\": [0, 5, 0], \"visible\": false}."},
		},
		"handler": _node_set,
	})
	reg.add("node.get", {
		"description": "Reads properties of a node (all editor-visible properties when none are given).",
		"args": {
			"path": {"type": "string", "required": true, "description": "Node path or name."},
			"properties": {"type": "array", "default": [], "description": "Property names to read."},
		},
		"handler": _node_get,
	})
	reg.add("camera.add", {
		"description": "Adds (or replaces) the main camera. type 'fly' attaches a WASD + mouse fly-camera script for exploring the world when the game runs.",
		"args": {
			"type": {"type": "string", "default": "fly", "enum": ["fly", "static"], "description": "Camera behavior."},
			"view": {"type": "string", "default": "aerial", "enum": ["aerial", "hero", "ground", "top", "north", "south", "east", "west"], "description": "Automatic framing of the terrain ('hero' = low three-quarter shot across the landscape)."},
			"position": {"type": "position", "description": "Explicit camera position (overrides view)."},
			"look_at": {"type": "position", "description": "Point to look at."},
			"name": {"type": "string", "default": "VibeCamera", "description": "Node name."},
		},
		"handler": _camera_add,
	})
	reg.add("screenshot", {
		"description": "Renders the scene to a PNG so you can SEE the result (returns the file path). Works in the live editor; in headless mode it needs a display (the terminal client runs Godot with a window).",
		"aliases": ["scene.screenshot", "editor.screenshot", "capture"],
		"args": {
			"path": {"type": "string", "description": "Output PNG (default res://.vibe/screenshots/shot_<time>.png)."},
			"view": {"type": "string", "default": "aerial", "enum": ["aerial", "hero", "top", "ground", "north", "south", "east", "west", "camera", "editor"], "description": "Automatic camera placement: 'hero' = low three-quarter shot across the landscape, 'camera' = the scene's camera, 'editor' = what the editor viewport shows."},
			"target": {"type": "string", "description": "Node name/path to frame (e.g. a VFX)."},
			"position": {"type": "position", "description": "Camera position (overrides view)."},
			"look_at": {"type": "position", "description": "Point to look at (with position)."},
			"width": {"type": "integer", "default": 1280, "description": "Image width."},
			"height": {"type": "integer", "default": 720, "description": "Image height."},
			"fov": {"type": "number", "default": 60.0, "description": "Vertical field of view in degrees."},
			"frames": {"type": "integer", "default": 12, "description": "Frames to wait before capturing (lets particles/shaders warm up)."},
		},
		"handler": _screenshot,
	})
	reg.add("editor.run", {
		"description": "Plays the scene in the editor (current scene by default, or a given path, or the main scene).",
		"editor_only": true,
		"args": {"scene": {"type": "string", "default": "current", "description": "'current', 'main' or a scene path."}},
		"handler": _editor_run,
	})
	reg.add("editor.stop", {
		"description": "Stops the running game started from the editor.",
		"editor_only": true,
		"handler": _editor_stop,
	})
	reg.add("editor.reload", {
		"description": "Reloads the current scene from disk (use after editing .tscn files by hand).",
		"editor_only": true,
		"handler": _editor_reload,
	})
	reg.add("undo", {
		"description": "Undoes the last change in the current scene (editor only).",
		"editor_only": true,
		"args": {"steps": {"type": "integer", "default": 1, "description": "How many actions to undo."}},
		"handler": _undo.bind(false),
	})
	reg.add("redo", {
		"description": "Redoes the last undone change in the current scene (editor only).",
		"editor_only": true,
		"args": {"steps": {"type": "integer", "default": 1, "description": "How many actions to redo."}},
		"handler": _undo.bind(true),
	})
	reg.add("vibe", {
		"description": "Builds a whole world from a free-form description in Portuguese or English (e.g. 'ilha tropical ao pôr do sol com fogueira e vagalumes'). Returns the recipe it interpreted; refine it and call world.build for full control.",
		"args": {
			"prompt": {"type": "string", "required": true, "description": "What you want, in natural language."},
			"scene": {"type": "string", "description": "Scene to create/replace (optional; defaults to the current scene)."},
			"apply": {"type": "boolean", "default": true, "description": "false = only return the interpreted recipe."},
			"clear": {"type": "boolean", "default": true, "description": "Remove previously generated terrain/grass/VFX first."},
		},
		"handler": _vibe,
		"examples": [{"prompt": "montanhas nevadas ao amanhecer com um lago"}, {"prompt": "desert canyon at sunset with a river and 3 campfires"}],
	})
	reg.add("world.build", {
		"description": "Builds a world from a declarative recipe (terrain + features + grass + VFX + environment + camera). See world.example for the format.",
		"args": {
			"recipe": {"type": "object", "description": "Recipe object (see world.example)."},
			"path": {"type": "string", "description": "Or a JSON recipe file (res://recipes/x.json)."},
			"clear": {"type": "boolean", "default": true, "description": "Remove previously generated terrain/grass/VFX first."},
		},
		"handler": _world_build,
	})
	reg.add("world.example", {
		"description": "Returns example recipes for world.build (names: ilha_tropical, montanhas_nevadas, deserto_canion, vulcao, campo_noturno).",
		"args": {"name": {"type": "string", "description": "Example name (all examples when empty)."}},
		"handler": _world_example,
	})
	reg.add("style.set", {
		"description": "Changes the art style of the whole scene at once (terrain, water, grass, VFX, sky/post): realistic, stylized, toon, cel, lowpoly.",
		"args": {
			"style": {"type": "string", "required": true, "enum": STYLES, "description": "realistic (PBR textures), stylized (painterly), toon, cel (anime 2-tone), lowpoly (faceted)."},
		},
		"handler": _style_set,
		"examples": [{"style": "toon"}],
	})
	reg.add("world.clear", {
		"description": "Removes every Vibe terrain, grass, VFX, the Vibe environment/sun and the Vibe camera from the scene.",
		"handler": _world_clear,
	})


# --- help / status ----------------------------------------------------------------

func _help(args: Dictionary, ctx) -> Variant:
	if args.get("command", "") != "":
		var spec: Dictionary = registry.get_spec(args.command)
		if spec.is_empty():
			return Util.err("unknown command '%s'" % args.command)
		for s in registry.get_schema():
			if s.name == spec.name:
				return s
	var groups := {}
	for s in registry.get_schema(str(args.get("category", ""))):
		var cat: String = s.category
		if not groups.has(cat):
			groups[cat] = []
		var line := {"name": s.name, "description": s.description}
		if s.editor_only:
			line["editor_only"] = true
		groups[cat].append(line)
	return {
		"mode": ctx.mode,
		"usage": "Run a command with its args. Details: help {\"command\": \"terrain.sculpt\"}.",
		"commands": groups,
	}


func _status(_args: Dictionary, ctx) -> Variant:
	var out := {
		"mode": ctx.mode,
		"godot": Engine.get_version_info().get("string", ""),
		"project": ProjectSettings.get_setting("application/config/name", ""),
		"scene": ctx.scene_path,
		"has_scene": ctx.root != null,
	}
	if ctx.root == null:
		out["hint"] = "No scene yet: use scene.new {\"path\": \"res://scenes/world.tscn\"} or vibe {\"prompt\": ...}."
		return out
	out["root"] = str(ctx.root.name)
	out["node_count"] = ctx.all_nodes().size()
	var terrains: Array = []
	for t in ctx.nodes_in_group(Util.TERRAIN_GROUP):
		terrains.append(t.get_info() if t.has_method("get_info") else {"name": str(t.name)})
	var grass: Array = []
	for g in ctx.nodes_in_group(Util.GRASS_GROUP):
		grass.append(g.get_info() if g.has_method("get_info") else {"name": str(g.name)})
	var vfx: Array = []
	for v in ctx.nodes_in_group(Util.VFX_GROUP):
		vfx.append(v.get_info() if v.has_method("get_info") else {"name": str(v.name)})
	out["terrains"] = terrains
	out["grass"] = grass
	out["vfx"] = vfx
	var env: Node = ctx.root.find_child("VibeEnvironment", true, false)
	if env != null and env.has_meta("vibe_preset"):
		out["environment"] = env.get_meta("vibe_preset")
	return out


# --- scenes ------------------------------------------------------------------------

func _scene_new(args: Dictionary, ctx) -> Variant:
	var path := Util.to_res_path(args.path, "tscn")
	if not Util.is_safe_write_path(path):
		return Util.err("scene path must be inside the project (res://...)")
	if FileAccess.file_exists(path) and not args.overwrite:
		return Util.err("'%s' already exists (use overwrite: true or scene.open)" % path)
	var root := Node3D.new()
	root.name = args.get("root_name", "") if str(args.get("root_name", "")) != "" else Util.pascal_case(path.get_file().get_basename())
	Util.ensure_dir(path.get_base_dir())
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		return Util.err("could not create scene: %s" % error_string(err))
	var open_res = _open_scene(path, ctx)
	if Util.is_err(open_res):
		return open_res
	ctx.info("new scene %s" % path)
	return {"scene": path, "root": str(ctx.root.name)}


func _scene_open(args: Dictionary, ctx) -> Variant:
	var path := Util.to_res_path(args.path, "tscn")
	if not ResourceLoader.exists(path):
		return Util.err("scene not found: %s" % path)
	return _open_scene(path, ctx)


func _open_scene(path: String, ctx) -> Variant:
	if ctx.is_editor():
		ctx.editor_interface.open_scene_from_path(path)
		ctx.root = ctx.editor_interface.get_edited_scene_root()
		ctx.scene_path = path
		if ctx.root == null:
			return Util.err("editor could not open %s" % path)
	else:
		var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not (packed is PackedScene):
			return Util.err("not a scene: %s" % path)
		var state := PackedScene.GEN_EDIT_STATE_MAIN if OS.has_feature("editor") else PackedScene.GEN_EDIT_STATE_DISABLED
		var new_root: Node = packed.instantiate(state)
		if ctx.root != null and is_instance_valid(ctx.root):
			if ctx.root.get_parent() != null:
				ctx.root.get_parent().remove_child(ctx.root)
			ctx.root.queue_free()
		ctx.root = new_root
		ctx.scene_path = path
		if ctx.tree != null:
			ctx.tree.root.add_child(new_root)
		ctx.dirty = false
	return {"scene": path, "root": str(ctx.root.name), "nodes": ctx.all_nodes().size()}


func _scene_save(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var path := ""
	if str(args.get("path", "")) != "":
		path = Util.to_res_path(args.path, "tscn")
		if not Util.is_safe_write_path(path):
			return Util.err("scene path must be inside the project (res://...)")
	return ctx.save_scene(path)


func _scene_tree(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	return {"scene": ctx.scene_path, "tree": _describe(ctx.root, ctx, 0, int(args.max_depth))}


func _describe(node: Node, ctx, depth: int, max_depth: int) -> Dictionary:
	var d := {"name": str(node.name), "type": node.get_class(), "path": ctx.node_path(node)}
	var script: Script = node.get_script()
	if script != null:
		var g := script.get_global_name()
		d["script"] = str(g) if str(g) != "" else script.resource_path
	if node is Node3D:
		d["position"] = Util.to_json_safe((node as Node3D).position)
	var kids := node.get_children()
	if not kids.is_empty():
		if depth >= max_depth:
			d["children_count"] = kids.size()
		else:
			var arr: Array = []
			for c in kids:
				arr.append(_describe(c, ctx, depth + 1, max_depth))
			d["children"] = arr
	return d


# --- nodes -------------------------------------------------------------------------

func _instantiate_type(type_name: String) -> Object:
	var t := type_name.strip_edges()
	if t.begins_with("res://"):
		if not ResourceLoader.exists(t):
			return null
		var res = load(t)
		if res is PackedScene:
			return (res as PackedScene).instantiate()
		if res is Script:
			return (res as Script).new()
		return null
	if ClassDB.class_exists(t):
		if ClassDB.can_instantiate(t) and ClassDB.is_parent_class(t, "Node"):
			return ClassDB.instantiate(t)
		return null
	for g in ProjectSettings.get_global_class_list():
		if str(g.get("class", "")) == t:
			var script = load(str(g.path))
			if script != null:
				return script.new()
	return null


func _prop_info(obj: Object, prop: String) -> Dictionary:
	var base := prop.get_slice(":", 0)
	for p in obj.get_property_list():
		if p.name == base:
			return p
	return {}


## Converts a JSON value into the Variant type expected by obj.prop.
func convert_for_property(obj: Object, prop: String, value: Variant) -> Variant:
	var current = obj.get_indexed(NodePath(prop)) if prop.contains(":") else obj.get(prop)
	var t := typeof(current)
	if t == TYPE_NIL:
		var info := _prop_info(obj, prop)
		t = int(info.get("type", TYPE_NIL))
	match t:
		TYPE_VECTOR3:
			var v = Util.parse_vector3(value)
			return v if v != null else value
		TYPE_VECTOR3I:
			var v = Util.parse_vector3(value)
			return Vector3i(v) if v != null else value
		TYPE_VECTOR2:
			var v = Util.parse_vector2(value)
			return v if v != null else value
		TYPE_VECTOR2I:
			var v = Util.parse_vector2(value)
			return Vector2i(v) if v != null else value
		TYPE_COLOR:
			var c = Util.parse_color(value)
			return c if c != null else value
		TYPE_BOOL:
			return Util.to_bool(value)
		TYPE_INT:
			return int(value) if (value is float or value is int or (value is String and (value as String).is_valid_float())) else value
		TYPE_FLOAT:
			return float(value) if (value is float or value is int or (value is String and (value as String).is_valid_float())) else value
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			return NodePath(str(value))
		TYPE_OBJECT:
			return _make_resource(value)
	return value


func _make_resource(value: Variant) -> Variant:
	if value is String:
		var s: String = value
		if s == "" or s == "null":
			return null
		if s.begins_with("res://"):
			return load(s) if ResourceLoader.exists(s) else null
		if ClassDB.class_exists(s) and ClassDB.can_instantiate(s) and ClassDB.is_parent_class(s, "Resource"):
			return ClassDB.instantiate(s)
		return null
	if value is Dictionary and value.has("type"):
		var res = _make_resource(str(value.type))
		if res is Object:
			for k in value:
				if k == "type":
					continue
				res.set(k, convert_for_property(res, k, value[k]))
		return res
	return value


func _apply_properties(obj: Object, props: Dictionary, ctx, undoable: bool) -> Array:
	var applied: Array = []
	for k in props:
		var key := str(k)
		var v = convert_for_property(obj, key, props[k])
		if key.contains(":"):
			var before = obj.get_indexed(NodePath(key))
			obj.set_indexed(NodePath(key), v)
			if undoable:
				ctx.record_method(obj, &"set_indexed", [NodePath(key), v], &"set_indexed", [NodePath(key), before])
		elif undoable:
			ctx.set_property(obj, key, v)
		else:
			obj.set(key, v)
		applied.append(key)
	return applied


func _node_add(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var obj := _instantiate_type(args.type)
	if obj == null:
		return Util.err("cannot create '%s' (use a Node class like MeshInstance3D, a global class, or a res:// scene)" % args.type)
	if not (obj is Node):
		return Util.err("'%s' is not a Node" % args.type)
	var node: Node = obj
	var parent: Node = ctx.root
	if str(args.get("parent", "")) != "":
		parent = ctx.find_node(args.parent)
		if parent == null:
			node.free()
			return Util.err("parent not found: %s" % args.parent)
	if Util.to_bool(args.get("replace", false)) and str(args.get("name", "")) != "":
		var old: Node = parent.get_node_or_null(NodePath(str(args.name)))
		if old != null and old != ctx.root:
			ctx.remove_node(old)
	node.name = ctx.unique_name(str(args.get("name", "")) if str(args.get("name", "")) != "" else str(args.type).get_file().get_basename(), parent)
	_apply_properties(node, args.properties, ctx, false)
	var world_pos = null
	if args.has("position") and node is Node3D:
		world_pos = ctx.resolve_position(args.position)
		if Util.is_err(world_pos):
			node.free()
			return world_pos
	ctx.add_node(node, parent)
	if world_pos != null:
		(node as Node3D).global_position = world_pos
	return {"name": str(node.name), "path": ctx.node_path(node), "type": node.get_class()}


func _node_remove(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var node: Node = ctx.find_node(args.path)
	if node == null:
		return Util.err("node not found: %s" % args.path)
	if node == ctx.root:
		return Util.err("cannot remove the scene root")
	var p: String = ctx.node_path(node)
	ctx.remove_node(node)
	return {"removed": p}


func _node_set(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var node: Node = ctx.find_node(args.path)
	if node == null:
		return Util.err("node not found: %s" % args.path)
	var props: Dictionary = args.properties
	if props.has("position") and node is Node3D and (props.position is String or (props.position is Array and props.position.size() == 2)):
		var p = ctx.resolve_position(props.position)
		if Util.is_err(p):
			return p
		props = props.duplicate()
		props.erase("position")
		ctx.set_property(node, &"global_position", p)
	var applied := _apply_properties(node, props, ctx, true)
	return {"path": ctx.node_path(node), "set": applied}


func _node_get(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var node: Node = ctx.find_node(args.path)
	if node == null:
		return Util.err("node not found: %s" % args.path)
	var out := {"path": ctx.node_path(node), "type": node.get_class()}
	var props: Array = args.properties
	var values := {}
	if props.is_empty():
		for p in node.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_EDITOR and not (int(p.usage) & PROPERTY_USAGE_CATEGORY) and not (int(p.usage) & PROPERTY_USAGE_GROUP) and not (int(p.usage) & PROPERTY_USAGE_SUBGROUP):
				values[p.name] = Util.to_json_safe(node.get(p.name))
	else:
		for p in props:
			var key := str(p)
			values[key] = Util.to_json_safe(node.get_indexed(NodePath(key)) if key.contains(":") else node.get(key))
	out["properties"] = values
	return out


# --- camera ------------------------------------------------------------------------

## Returns [position, target] for an automatic view of the terrain (or scene).
func auto_view(ctx, view: String) -> Array:
	var terrain: Node = ctx.get_terrain()
	if terrain == null or not terrain.has_method("get_world_size"):
		var bounds := _scene_bounds(ctx)
		var c := bounds.get_center()
		var r := maxf(bounds.size.length() * 0.5, 4.0)
		match view:
			"top":
				return [c + Vector3(0, r * 2.2, 0.01), c]
			"ground":
				return [c + Vector3(0, 1.7, r * 1.2), c + Vector3(0, 1.0, 0)]
		return [c + Vector3(r * 1.1, r * 0.8, r * 1.1), c]
	var center: Vector3 = terrain.global_position
	var s: float = terrain.get_world_size()
	var hr: Vector2 = terrain.get_height_range()
	var peak := hr.y
	var mid := (hr.x + hr.y) * 0.5
	match view:
		"top":
			return [center + Vector3(0, s * 0.95 + peak, 0.01), center]
		"ground":
			var p: Vector3 = terrain.find_anchor("flat", 1)
			var eye := p + Vector3.UP * 1.8
			var to_center := (center - eye)
			to_center.y = 0
			if to_center.length() < 5.0:
				to_center = Vector3(0, 0, -1)
			var look := eye + to_center.normalized() * 30.0
			look.y = terrain.get_height_at_world(look) + 3.0
			return [eye, look]
		"hero":
			return _hero_view(ctx, terrain, center, s)
		"north", "south", "east", "west":
			var dir: Vector3 = {"north": Vector3(0, 0, -1), "south": Vector3(0, 0, 1), "east": Vector3(1, 0, 0), "west": Vector3(-1, 0, 0)}[view]
			return [center + dir * s * 0.62 + Vector3.UP * (peak + s * 0.12), center + Vector3.UP * (mid * 0.6)]
	return [center + Vector3(s * 0.36, peak * 0.75 + s * 0.24, s * 0.36), center + Vector3.UP * (mid * 0.5)]


## Three-quarter view across the landscape, framed like a photo. Tries 80
## spots around the center (5 distances x 16 directions), each looking toward
## it with the pitch that puts the skyline in the upper third, and keeps the
## best: skyline where the pitch can frame it, no slope right in front of the
## lens, the sun behind/beside the camera (front-lit terrain reads best),
## over land and, with a sea, some water in the picture.
func _hero_view(ctx, terrain: Node, center: Vector3, s: float) -> Array:
	var to_sun := Vector3(0.35, 0.0, 0.94)
	for n in ctx.all_nodes():
		if n is DirectionalLight3D and (n as DirectionalLight3D).visible:
			var z := (n as DirectionalLight3D).global_transform.basis.z
			if Vector2(z.x, z.z).length() > 0.01:
				to_sun = Vector3(z.x, 0.0, z.z).normalized()
			break
	var has_sea: bool = terrain.water_enabled
	var water: float = terrain.water_level if has_sea else -INF
	var third := deg_to_rad(10.0)  # skyline this far above the view center = upper third (60° fov)
	var best: Array = [center + Vector3(s * 0.3, s * 0.1, s * 0.3), center]
	var best_score := -INF
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var fwd := -dir
		for rf in [0.2, 0.3, 0.42, 0.56, 0.7]:
			var xz: Vector3 = center + dir * s * rf
			var g: float = terrain.get_height_at_world(xz)
			var eye := Vector3(xz.x, maxf(g, water) + maxf(7.0, s * 0.05), xz.z)
			var score := 0.0
			if g < water + 0.3:
				score -= 1.0
			# Skyline (highest elevation angle of the terrain ahead) and slopes
			# rising right in front of the lens.
			var skyline := -INF
			for k in range(1, 25):
				var d := s * 0.05 * k
				var h: float = terrain.get_height_at_world(eye + fwd * d)
				skyline = maxf(skyline, atan2(h - eye.y, d))
				if d < s * 0.12 and h > eye.y - 1.0:
					score -= 1.5
			var pitch := clampf(skyline - third, deg_to_rad(-14.0), deg_to_rad(6.0))
			score -= absf(skyline - pitch - third) / third
			score -= absf(fwd.dot(to_sun) + 0.45) * 1.2
			if has_sea:
				var wet := 0
				var total := 0
				for yaw in [-0.5, -0.25, 0.0, 0.25, 0.5]:
					var ray := fwd.rotated(Vector3.UP, yaw)
					for k in range(1, 7):
						total += 1
						if terrain.get_height_at_world(eye + ray * s * 0.13 * k) < water:
							wet += 1
				score += 1.0 - 2.5 * absf(float(wet) / float(total) - 0.3)
			elif rf > 0.5:
				score -= 0.4  # prefer standing on the terrain itself
			if score > best_score:
				best_score = score
				var look := (fwd * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
				best = [eye, eye + look * 60.0]
	return best


func _scene_bounds(ctx) -> AABB:
	var box := AABB()
	var first := true
	for n in ctx.all_nodes():
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var b: AABB = (n as VisualInstance3D).get_aabb()
			b = (n as Node3D).global_transform * b
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
	if first:
		box = AABB(Vector3(-5, 0, -5), Vector3(10, 4, 10))
	return box


func _camera_add(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var old: Node = ctx.root.find_child(args.name, false, false)
	if old != null:
		ctx.remove_node(old)
	var cam := Camera3D.new()
	cam.name = args.name
	cam.current = true
	cam.far = 4000.0
	if args.type == "fly":
		cam.set_script(FlyCamera)
	var pos_target := auto_view(ctx, args.view)
	var pos: Vector3 = pos_target[0]
	var target: Vector3 = pos_target[1]
	if args.has("position"):
		var p = ctx.resolve_position(args.position, 1.8)
		if Util.is_err(p):
			return p
		pos = p
	if args.has("look_at"):
		var t = ctx.resolve_position(args.look_at)
		if Util.is_err(t):
			return t
		target = t
	ctx.add_node(cam)
	cam.global_position = pos
	if not pos.is_equal_approx(target):
		cam.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	return {"name": str(cam.name), "position": cam.global_position, "type": args.type}


# --- screenshots -----------------------------------------------------------------------

func _screenshot(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	if DisplayServer.get_name() == "headless":
		return Util.err("cannot render in headless mode. Open the project in the Godot editor (live bridge) or let the terminal client run Godot with a window.")
	if not (ctx.root is Node3D) and ctx.root.get_viewport() == null:
		return Util.err("scene root is not 3D")
	var path := str(args.get("path", ""))
	if path == "":
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
		path = SCREENSHOT_DIR.path_join("shot_%s_%d.png" % [stamp, Time.get_ticks_msec() % 1000])
	path = Util.to_res_path(path, "png")
	if not Util.is_safe_write_path(path):
		return Util.err("screenshot path must be inside the project (res:// or user://)")
	Util.ensure_dir(path.get_base_dir())
	if path.begins_with(SCREENSHOT_DIR):
		_ensure_gdignore("res://.vibe")

	var world: World3D = (ctx.root as Node3D).get_world_3d() if ctx.root is Node3D else ctx.root.get_viewport().world_3d
	var vp := SubViewport.new()
	vp.size = Vector2i(clampi(int(args.width), 64, 4096), clampi(int(args.height), 64, 4096))
	vp.world_3d = world
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.fov = float(args.fov)
	cam.far = 12000.0
	cam.near = 0.1
	cam.cull_mask = (1 << 20) - 1
	vp.add_child(cam)

	var pos_target := auto_view(ctx, args.view)
	if args.view == "editor" and ctx.is_editor():
		var ev = ctx.editor_interface.get_editor_viewport_3d(0)
		if ev != null and ev.get_camera_3d() != null:
			var ecam: Camera3D = ev.get_camera_3d()
			pos_target = [ecam.global_position, ecam.global_position - ecam.global_transform.basis.z * 10.0]
			cam.fov = ecam.fov
	if args.view == "camera":
		var scam := _scene_camera(ctx)
		if scam != null:
			pos_target = [scam.global_position, scam.global_position - scam.global_transform.basis.z * 10.0]
			cam.fov = scam.fov
	if str(args.get("target", "")) != "":
		var n: Node = ctx.find_node(args.target)
		if n == null or not (n is Node3D):
			vp.free()
			return Util.err("target not found: %s" % args.target)
		var radius := 4.0
		if n.has_method("get_effect_radius"):
			radius = n.get_effect_radius()
		elif n is VisualInstance3D:
			radius = maxf((n as VisualInstance3D).get_aabb().size.length() * 0.5, 1.0)
		var focus := radius * 0.4
		if n.has_method("get_effect_focus_height"):
			focus = n.get_effect_focus_height()
		var tp: Vector3 = (n as Node3D).global_position + Vector3.UP * focus
		pos_target = [tp + Vector3(1.0, 0.45, 1.0).normalized() * radius * 3.2, tp]
	if args.has("position"):
		var p = ctx.resolve_position(args.position, 1.8)
		if Util.is_err(p):
			vp.free()
			return p
		pos_target[0] = p
		if not args.has("look_at"):
			pos_target[1] = p + Vector3(0, -0.2, -1)
	if args.has("look_at"):
		var t = ctx.resolve_position(args.look_at)
		if Util.is_err(t):
			vp.free()
			return t
		pos_target[1] = t

	# Temporary sun/sky if the scene has none, so the picture is readable.
	var temp_nodes: Array = []
	if world.environment == null and world.fallback_environment == null:
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = Sky.new()
		env.sky.sky_material = ProceduralSkyMaterial.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		vp.add_child(we)
		temp_nodes.append(we)
	if not _scene_has_sun(ctx):
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.shadow_enabled = true
		vp.add_child(sun)
		temp_nodes.append(sun)

	var host: Node = ctx.editor_interface.get_base_control() if ctx.is_editor() else ctx.tree.root
	host.add_child(vp)
	cam.global_position = pos_target[0]
	var dir: Vector3 = (pos_target[1] - pos_target[0])
	if dir.length() > 0.001:
		cam.look_at(pos_target[1], Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD)
	cam.current = true

	var was_low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for i in maxi(2, int(args.frames)):
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	OS.low_processor_usage_mode = was_low
	# Leave the tree right away so temporary environment/sun stop affecting the world.
	host.remove_child(vp)
	vp.queue_free()
	if img == null or img.is_empty():
		return Util.err("render produced an empty image")
	var err := img.save_png(path)
	if err != OK:
		return Util.err("could not save PNG: %s" % error_string(err))
	return {
		"path": path,
		"file": ProjectSettings.globalize_path(path),
		"size": [img.get_width(), img.get_height()],
		"camera": {"position": pos_target[0], "look_at": pos_target[1]},
	}


func _scene_camera(ctx) -> Camera3D:
	var first: Camera3D = null
	for n in ctx.all_nodes():
		if n is Camera3D:
			if (n as Camera3D).current:
				return n
			if first == null:
				first = n
	return first


func _scene_has_sun(ctx) -> bool:
	for n in ctx.all_nodes():
		if n is DirectionalLight3D and (n as DirectionalLight3D).visible:
			return true
	return false


func _ensure_gdignore(dir: String) -> void:
	Util.ensure_dir(dir)
	var p := dir.path_join(".gdignore")
	if not FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string("")
			f.close()


# --- editor control --------------------------------------------------------------------

func _editor_run(args: Dictionary, ctx) -> Variant:
	var ei = ctx.editor_interface
	var which := str(args.scene)
	if which == "main":
		ei.play_main_scene()
	elif which == "current" or which == "":
		ei.play_current_scene()
	else:
		ei.play_custom_scene(Util.to_res_path(which, "tscn"))
	return {"playing": true, "scene": which}


func _editor_stop(_args: Dictionary, ctx) -> Variant:
	ctx.editor_interface.stop_playing_scene()
	return {"playing": false}


func _editor_reload(_args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var path: String = ctx.root.scene_file_path
	if path == "":
		return Util.err("scene has never been saved")
	ctx.editor_interface.reload_scene_from_path(path)
	ctx.root = ctx.editor_interface.get_edited_scene_root()
	return {"reloaded": path}


func _undo(args: Dictionary, ctx, redo: bool) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var ur = ctx.undo_redo
	var history_id: int = ur.get_object_history_id(ctx.root)
	var history: UndoRedo = ur.get_history_undo_redo(history_id)
	var done := 0
	for i in maxi(1, int(args.steps)):
		var ok: bool = history.redo() if redo else history.undo()
		if not ok:
			break
		done += 1
	return {"redo" if redo else "undo": done, "current_action": history.get_current_action_name()}


# --- vibe / world ---------------------------------------------------------------------

func _vibe(args: Dictionary, ctx) -> Variant:
	var nl := VibeNL.new()
	var recipe := nl.parse(args.prompt)
	if str(args.get("scene", "")) != "":
		recipe["scene"] = args.scene
	var out := {"prompt": args.prompt, "interpretation": nl.notes, "recipe": recipe}
	if not args.apply:
		return out
	if ctx.root == null and not recipe.has("scene"):
		recipe["scene"] = "res://scenes/%s.tscn" % Util.slugify(args.prompt).left(40)
		out["recipe"] = recipe
	if args.clear and ctx.root != null:
		_world_clear({}, ctx)
	var builder := VibeWorld.new()
	var built = await builder.build(recipe, ctx, registry)
	if Util.is_err(built):
		return built
	out["build"] = built
	out["hint"] = "Take a screenshot to check the result, then refine with terrain.*, grass.*, vfx.* or world.build."
	return out


func _world_build(args: Dictionary, ctx) -> Variant:
	var recipe = args.get("recipe", null)
	if str(args.get("path", "")) != "":
		var p := Util.to_res_path(args.path, "json")
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			return Util.err("cannot read recipe file %s" % p)
		recipe = JSON.parse_string(f.get_as_text())
		if not (recipe is Dictionary):
			return Util.err("recipe file is not a JSON object: %s" % p)
	if not (recipe is Dictionary):
		return Util.err("pass 'recipe' (object) or 'path' (JSON file)")
	if args.clear and ctx.root != null and (not recipe.has("scene") or Util.to_res_path(str(recipe.scene), "tscn") == ctx.scene_path):
		_world_clear({}, ctx)
	var builder := VibeWorld.new()
	return await builder.build(recipe, ctx, registry)


func _world_example(args: Dictionary, _ctx) -> Variant:
	var n := str(args.get("name", ""))
	if n == "":
		return {"examples": VibeWorld.EXAMPLES, "hint": "Pass one to world.build {\"recipe\": ...} (edit freely)."}
	if not VibeWorld.EXAMPLES.has(n):
		return Util.err("unknown example '%s' (available: %s)" % [n, ", ".join(VibeWorld.EXAMPLES.keys())])
	return VibeWorld.EXAMPLES[n]


static func resolve_style(value: String) -> String:
	var s := Util.normalize_text(value).strip_edges().replace(" ", "_")
	if STYLES.has(s):
		return s
	return STYLE_ALIASES.get(s, "")


func _style_set(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var style := resolve_style(str(args.style))
	if style == "":
		return Util.err("unknown style '%s' (use %s)" % [args.style, ", ".join(STYLES)])
	var old_style: String = str(ctx.root.get_meta("vibe_style", "realistic"))
	ctx.root.set_meta("vibe_style", style)
	if ctx.is_editor():
		ctx.record_method(ctx.root, &"set_meta", [&"vibe_style", style], &"set_meta", [&"vibe_style", old_style])
	var changed: Array = []
	for g in [Util.TERRAIN_GROUP, Util.GRASS_GROUP, Util.VFX_GROUP]:
		for n in ctx.nodes_in_group(g):
			if "style" in n:
				ctx.set_property(n, &"style", style)
				changed.append(ctx.node_path(n))
	var env: Node = ctx.root.find_child("VibeEnvironment", false, false)
	if env != null and registry.has_command("env.set"):
		await registry.execute("env.set", {"preset": str(env.get_meta("vibe_preset", "day")), "style": style}, ctx)
		changed.append("VibeEnvironment")
	ctx.dirty = true
	return {"style": style, "changed": changed}


func _world_clear(_args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var removed: Array = []
	var targets: Array = []
	for g in [Util.TERRAIN_GROUP, Util.GRASS_GROUP, Util.VFX_GROUP]:
		for n in ctx.nodes_in_group(g):
			if not targets.has(n):
				targets.append(n)
	for nm in ["VibeEnvironment", "VibeSun", "VibeCamera"]:
		var n: Node = ctx.root.find_child(nm, false, false)
		if n != null and not targets.has(n):
			targets.append(n)
	# Remove children before parents (grass is usually a child of the terrain).
	targets.sort_custom(func(a, b): return a.get_path().get_name_count() > b.get_path().get_name_count())
	for n in targets:
		if is_instance_valid(n) and n.is_inside_tree():
			removed.append(ctx.node_path(n))
			ctx.remove_node(n)
	return {"removed": removed}
