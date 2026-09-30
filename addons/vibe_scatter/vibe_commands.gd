@tool
extends RefCounted
## Terminal/bridge commands for vegetation and props (scatter.*).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const ScatterScript = preload("res://addons/vibe_scatter/vibe_scatter_3d.gd")
const Presets = preload("res://addons/vibe_scatter/scatter_presets.gd")
const DataScript = preload("res://addons/vibe_scatter/vibe_scatter_data.gd")

const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]


func register(reg) -> void:
	var presets := ", ".join(Presets.PRESETS.keys())
	reg.add("scatter.add", {
		"description": "Scatters trees, bushes, rocks or props over the terrain: " + presets + ". PT/EN names work (floresta, pinheiros, palmeiras, rochas, cactos...). Placement follows slope/height/water rules, groves and clearings around effects/characters.",
		"args": {
			"preset": {"type": "string", "required": true, "description": "What to scatter."},
			"density": {"type": "number", "default": 1.0, "description": "Density multiplier (0.2 sparse, 1 normal, 2 dense)."},
			"name": {"type": "string", "description": "Node name (default from the preset)."},
			"terrain": {"type": "string", "description": "Terrain node (default first)."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style (default: scene style)."},
			"palette": {"type": "string", "description": "Colors: temperate, tropical, snowy, desert, canyon, volcanic, autumn, alien, lunar, swamp, savanna (default: the terrain's)."},
			"rules": {"type": "object", "default": {}, "description": "Placement overrides: max_slope, min_slope, min_above_water, max_above_water, min_height_frac, max_height_frac, cluster (0..1), cluster_scale, water_margin, clearing."},
			"colors": {"type": "object", "default": {}, "description": "Color overrides: {\"leaves\": [\"#c33\", \"#e83\"], \"bark\": \"#543\", \"rock\": \"#888\", \"top\": \"#fff\", \"top_amount\": 0.6, \"snow\": 0.5}."},
			"seed": {"type": "integer", "default": 1, "description": "Variation seed."},
			"view_distance": {"type": "number", "description": "Draw distance in meters."},
			"collision": {"type": "boolean", "default": true, "description": "Trees and rocks block characters."},
			"replace": {"type": "boolean", "default": true, "description": "Replace a node with the same name."},
		},
		"handler": _add,
		"examples": [{"preset": "floresta", "density": 0.8}, {"preset": "pinheiros", "rules": {"max_height_frac": 0.6}}, {"preset": "rochas", "density": 1.5}],
	})
	reg.add("scatter.auto", {
		"description": "Adds the natural vegetation of the terrain's palette (temperate: forest+bushes+rocks+logs, tropical: palms+jungle, snowy: pines+rocks, desert: cacti+rocks, autumn: orange forest+mushrooms, alien: crystals...).",
		"args": {
			"density": {"type": "number", "default": 1.0, "description": "Global density multiplier."},
			"terrain": {"type": "string", "description": "Terrain node (default first)."},
			"palette": {"type": "string", "description": "Override the palette."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style (default: scene style)."},
		},
		"handler": _auto,
	})
	reg.add("scatter.set", {
		"description": "Changes a scatter layer (preset, density, style, palette, rules, colors, seed, view distance, wind).",
		"args": {
			"name": {"type": "string", "required": true, "description": "Scatter node name."},
			"preset": {"type": "string", "description": "New preset."},
			"density": {"type": "number", "description": "Density multiplier."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style."},
			"palette": {"type": "string", "description": "Color palette."},
			"rules": {"type": "object", "description": "Placement rules (merged)."},
			"colors": {"type": "object", "description": "Color overrides (merged)."},
			"seed": {"type": "integer", "description": "Variation seed."},
			"view_distance": {"type": "number", "description": "Draw distance (m)."},
			"wind_strength": {"type": "number", "description": "Wind (0..3)."},
		},
		"handler": _set_cmd,
	})
	reg.add("scatter.paint", {
		"description": "Paints where a scatter layer grows: erase trees around a point (a clearing, a village, a path) or bring them back.",
		"args": {
			"name": {"type": "string", "required": true, "description": "Scatter node name."},
			"position": {"type": "position", "required": true, "description": "Center ([x, z], anchor...)."},
			"radius": {"type": "number", "default": 15.0, "description": "Brush radius (m)."},
			"density": {"type": "number", "default": 1.0, "description": "Target density 0..1."},
			"erase": {"type": "boolean", "default": false, "description": "Shortcut for density 0."},
			"strength": {"type": "number", "default": 1.0, "description": "Brush strength 0..1."},
		},
		"handler": _paint,
	})
	reg.add("scatter.clear", {
		"description": "Removes a scatter layer (name) or every one (all=true).",
		"args": {"name": {"type": "string", "description": "Scatter node name."}, "all": {"type": "boolean", "default": false, "description": "Remove all."}},
		"handler": _clear,
	})
	reg.add("scatter.list", {
		"description": "Lists scatter presets, palettes and the scatter layers in the scene.",
		"handler": _list,
	})


func _scene_style(ctx) -> String:
	if ctx.root != null and ctx.root.has_meta("vibe_style"):
		return str(ctx.root.get_meta("vibe_style"))
	return "realistic"


func _find(ctx, name: String) -> Node:
	return ctx.find_in_group(Util.SCATTER_GROUP, name)


func _add(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var key := Presets.resolve(str(args.preset))
	if key == "":
		return Util.err("unknown scatter preset '%s' (use %s)" % [args.preset, ", ".join(Presets.PRESETS.keys())])
	var terrain: Node = ctx.get_terrain(str(args.get("terrain", "")))
	if terrain == null:
		return Util.err("no terrain in the scene (terrain.create first)")
	var name := str(args.get("name", ""))
	if name == "":
		name = Util.pascal_case(key)
	var old: Node = terrain.get_node_or_null(NodePath(name))
	if old != null:
		if Util.to_bool(args.replace):
			ctx.remove_node(old)
		else:
			name = ctx.unique_name(name, terrain)
	var s = ScatterScript.new()
	s.name = name
	s.preset = key
	s.style = str(args.get("style", "")) if str(args.get("style", "")) != "" else _scene_style(ctx)
	s.density = float(args.density)
	s.random_seed = int(args.seed)
	if str(args.get("palette", "")) != "":
		s.palette = str(args.palette)
	if args.rules is Dictionary:
		s.rules = args.rules
	if args.colors is Dictionary:
		s.colors = args.colors
	if args.has("view_distance"):
		s.view_distance = float(args.view_distance)
	s.collision = Util.to_bool(args.collision)
	ctx.add_node(s, terrain)
	s.rebuild()
	var info: Dictionary = s.get_info()
	return {"name": str(s.name), "preset": key, "instances": info.instances, "per_kind": info.per_kind, "palette": info.palette, "style": s.style}


func _auto(args: Dictionary, ctx) -> Variant:
	var terrain: Node = ctx.get_terrain(str(args.get("terrain", "")))
	if terrain == null:
		return Util.err("no terrain in the scene (terrain.create first)")
	var pal := str(args.get("palette", "")) if str(args.get("palette", "")) != "" else str(terrain.palette)
	var added: Array = []
	var total := 0
	var i := 0
	for entry in Presets.defaults_for(pal):
		var r = await _add({"preset": entry[0], "density": float(entry[1]) * float(args.density), "terrain": str(terrain.name),
			"style": str(args.get("style", "")), "palette": pal if Presets.get_preset(entry[0]).get("palette", "") == "" else "",
			"rules": {}, "colors": {}, "seed": 1 + i * 17, "collision": true, "replace": true}, ctx)
		if Util.is_err(r):
			return r
		added.append({"name": r.name, "preset": r.preset, "instances": r.instances})
		total += int(r.instances)
		i += 1
	return {"palette": pal, "layers": added, "instances": total}


func _set_cmd(args: Dictionary, ctx) -> Variant:
	var s: Node = _find(ctx, str(args.name))
	if s == null:
		return Util.err("scatter layer not found: %s" % args.name)
	if args.has("preset"):
		var key := Presets.resolve(str(args.preset))
		if key == "":
			return Util.err("unknown scatter preset '%s'" % args.preset)
		ctx.set_property(s, &"preset", key)
	for k in ["density", "view_distance", "wind_strength"]:
		if args.has(k):
			ctx.set_property(s, StringName(k), float(args[k]))
	if args.has("style"):
		ctx.set_property(s, &"style", str(args.style))
	if args.has("palette"):
		ctx.set_property(s, &"palette", str(args.palette))
	if args.has("seed"):
		ctx.set_property(s, &"random_seed", int(args.seed))
	if args.has("rules") and args.rules is Dictionary:
		var r: Dictionary = (s.rules as Dictionary).duplicate()
		r.merge(args.rules, true)
		ctx.set_property(s, &"rules", r)
	if args.has("colors") and args.colors is Dictionary:
		var c: Dictionary = (s.colors as Dictionary).duplicate()
		c.merge(args.colors, true)
		ctx.set_property(s, &"colors", c)
	s.rebuild()
	return s.get_info()


func _paint(args: Dictionary, ctx) -> Variant:
	var s: Node = _find(ctx, str(args.name))
	if s == null:
		return Util.err("scatter layer not found: %s" % args.name)
	var pos = ctx.resolve_position(args.position)
	if Util.is_err(pos):
		return pos
	var before: Dictionary = s.make_snapshot()
	if s.data == null or s.data.resource_path == "":
		s.ensure_data()
		ctx.adopt_resource(s.data, ctx.data_path_for(str(s.name), "scatter"))
	var value := 0.0 if Util.to_bool(args.erase) else clampf(float(args.density), 0.0, 1.0)
	s.paint(pos, float(args.radius), value, clampf(float(args.strength), 0.0, 1.0))
	ctx.record_snapshot(s, before, s.make_snapshot())
	return s.get_info()


func _clear(args: Dictionary, ctx) -> Variant:
	var removed: Array = []
	if Util.to_bool(args.all):
		for s in ctx.nodes_in_group(Util.SCATTER_GROUP):
			removed.append(str(s.name))
			ctx.remove_node(s)
		return {"removed": removed}
	var s: Node = _find(ctx, str(args.get("name", "")))
	if s == null:
		return Util.err("scatter layer not found: %s" % args.get("name", ""))
	removed.append(str(s.name))
	ctx.remove_node(s)
	return {"removed": removed}


func _list(_args: Dictionary, ctx) -> Variant:
	var presets := {}
	for k in Presets.PRESETS:
		presets[k] = Presets.PRESETS[k].desc
	var layers: Array = []
	for s in ctx.nodes_in_group(Util.SCATTER_GROUP):
		layers.append(s.get_info())
	var defaults := {}
	for p in Presets.PALETTE_DEFAULTS:
		defaults[p] = Presets.PALETTE_DEFAULTS[p].map(func(e): return e[0])
	return {"presets": presets, "palette_defaults": defaults, "layers": layers}
