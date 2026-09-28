@tool
extends RefCounted
## Terminal/bridge commands for VibeGrass3D (grass.*).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const GrassScript = preload("res://addons/vibe_grass/vibe_grass_3d.gd")
const DataScript = preload("res://addons/vibe_grass/vibe_grass_data.gd")
const Presets = preload("res://addons/vibe_grass/grass_presets.gd")

const G_ARG := {"type": "string", "description": "Grass node name (defaults to the first grass layer in the scene)."}
const TUNABLE := ["blade_height", "blade_width", "blade_curve", "blades_per_clump", "density_per_m2", "flower_chance",
	"color_base", "color_tip", "dry_color", "dry_amount", "sss_color", "emission", "wind_strength", "wind_speed",
	"view_distance", "cast_shadows", "style"]


func register(reg) -> void:
	var presets: Array = Presets.names()
	var tunables := {
		"blade_height": {"type": "number", "description": "Blade height in meters."},
		"blade_width": {"type": "number", "description": "Blade width in meters."},
		"blade_curve": {"type": "number", "description": "How much blades bend (0..1.5)."},
		"blades_per_clump": {"type": "integer", "description": "Blades per clump."},
		"density_per_m2": {"type": "number", "description": "Clumps per m² at full density."},
		"flower_chance": {"type": "number", "description": "0..1 chance of a flower on a blade."},
		"color_base": {"type": "color", "description": "Color at the root."},
		"color_tip": {"type": "color", "description": "Color at the tip."},
		"dry_color": {"type": "color", "description": "Color of dry patches."},
		"dry_amount": {"type": "number", "description": "0..1 amount of dry patches."},
		"sss_color": {"type": "color", "description": "Backlight (subsurface) color."},
		"emission": {"type": "number", "description": "Glow (alien grass)."},
		"wind_strength": {"type": "number", "description": "Wind bend."},
		"wind_speed": {"type": "number", "description": "Wind speed."},
		"view_distance": {"type": "number", "description": "Draw distance in meters."},
		"cast_shadows": {"type": "boolean", "description": "Blades cast shadows (costly)."},
		"style": {"type": "string", "enum": GrassScript.STYLES, "description": "Art style: realistic, stylized, toon, cel, lowpoly."},
	}
	var create_args := {
		"name": {"type": "string", "default": "Grass", "description": "Node name."},
		"terrain": {"type": "string", "description": "Terrain to grow on (default: first terrain)."},
		"preset": {"type": "string", "default": "meadow", "enum": presets, "open_enum": true, "description": "Grass type."},
		"replace": {"type": "boolean", "default": false, "description": "Replace a grass node with the same name."},
		"area_size": {"type": "number", "default": 64.0, "description": "Area in meters when there is no terrain."},
	}
	create_args.merge(tunables)
	reg.add("grass.create", {
		"description": "Adds a grass layer (VibeGrass3D) on the terrain. Types: " + ", ".join(presets) + ". Starts empty: use grass.fill (rules) or grass.paint.",
		"args": create_args,
		"handler": _create,
		"examples": [{"preset": "flowers", "name": "Flores"}],
	})
	reg.add("grass.fill", {
		"description": "Fills grass density automatically by rules: height range, max slope, terrain layer, away from water, natural patches.",
		"args": {
			"grass": G_ARG,
			"density": {"type": "number", "default": 1.0, "description": "0..1 density where the rules match."},
			"min_height": {"type": "number", "description": "Only above this height."},
			"max_height": {"type": "number", "description": "Only below this height."},
			"max_slope": {"type": "number", "default": 38.0, "description": "No grass on slopes steeper than this (degrees)."},
			"min_slope": {"type": "number", "default": 0.0, "description": "Only on slopes steeper than this."},
			"layer": {"type": "integer", "description": "Only where this terrain layer (0-3) is painted (e.g. 0 = grass)."},
			"min_layer_weight": {"type": "number", "default": 0.35, "description": "Layer weight threshold."},
			"avoid_water": {"type": "boolean", "default": true, "description": "Keep out of the sea and lakes."},
			"patchiness": {"type": "number", "default": 0.3, "description": "0 = uniform, 1 = sparse patches."},
			"patch_scale": {"type": "number", "default": 18.0, "description": "Patch size in meters."},
			"mode": {"type": "string", "default": "replace", "enum": ["replace", "add", "max", "min", "multiply"], "description": "Combine with the current density."},
			"seed": {"type": "integer", "default": 5, "description": "Patch noise seed."},
		},
		"handler": _fill,
	})
	reg.add("grass.paint", {
		"description": "Paints (or erases) grass density with a brush at a position or along 'points'.",
		"args": {
			"grass": G_ARG,
			"position": {"type": "position", "default": "center", "description": "Brush center."},
			"points": {"type": "array", "description": "Optional stroke positions."},
			"radius": {"type": "number", "default": 8.0, "description": "Brush radius in meters."},
			"density": {"type": "number", "default": 1.0, "description": "Target density 0..1 (0 erases)."},
			"strength": {"type": "number", "default": 1.0, "description": "0..1."},
			"erase": {"type": "boolean", "default": false, "description": "Shortcut for density 0."},
		},
		"handler": _paint,
	})
	reg.add("grass.clear", {
		"description": "Removes all grass of a layer (density 0 everywhere).",
		"args": {"grass": G_ARG},
		"handler": _clear,
	})
	var set_args := {"grass": G_ARG, "preset": {"type": "string", "enum": presets, "open_enum": true, "description": "Apply a grass type first."}}
	set_args.merge(tunables)
	reg.add("grass.set", {
		"description": "Changes grass look/behavior: preset, style, height, colors, wind, draw distance...",
		"args": set_args,
		"handler": _set_cmd,
	})
	reg.add("grass.info", {
		"description": "Info about a grass layer (coverage, type, style...).",
		"args": {"grass": G_ARG},
		"handler": _info,
	})


func _find_grass(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var wanted := str(args.get("grass", ""))
	var g: Node = ctx.find_in_group(Util.GRASS_GROUP, wanted)
	if g == null:
		if wanted != "":
			return Util.err("grass '%s' not found" % wanted)
		return Util.err("no VibeGrass3D in the scene. Create one with grass.create.")
	return g


func _snapshot(ctx, g: Node) -> Dictionary:
	return g.make_snapshot() if ctx.is_editor() else {}


func _commit(ctx, g: Node, before: Dictionary) -> void:
	ctx.dirty = true
	if ctx.is_editor():
		ctx.record_snapshot(g, before, g.make_snapshot())


func _apply_tunables(g: Node, args: Dictionary, ctx, undoable: bool) -> Array:
	var changed: Array = []
	for k in TUNABLE:
		if args.has(k) and args[k] != null:
			if undoable:
				ctx.set_property(g, k, args[k])
			else:
				g.set(k, args[k])
			changed.append(k)
	return changed


func _create(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var node_name := str(args.name)
	var existing: Node = ctx.find_in_group(Util.GRASS_GROUP, node_name)
	if existing != null:
		if not args.replace:
			return Util.err("a grass layer named '%s' already exists (use replace: true)" % node_name)
		ctx.remove_node(existing)
	var terrain: Node = ctx.get_terrain(str(args.get("terrain", "")))
	if str(args.get("terrain", "")) != "" and terrain == null:
		return Util.err("terrain '%s' not found" % args.terrain)
	var g := GrassScript.new()
	g.name = node_name if existing != null else ctx.unique_name(node_name, terrain if terrain != null else ctx.root)
	if not g.apply_preset(str(args.preset)):
		ctx.warn("unknown grass preset '%s', using meadow" % args.preset)
		g.apply_preset("meadow")
	g.area_size = float(args.area_size)
	_apply_tunables(g, args, ctx, false)
	var data := DataScript.new()
	var res: int = terrain.data.resolution if terrain != null else int(g.area_size) + 1
	data.setup(res, 0)
	g.data = data
	var err: Error = ctx.adopt_resource(data, ctx.data_path_for(str(g.name), "grass"))
	if err != OK:
		ctx.warn("could not write grass data file (%s)" % error_string(err))
	# As a child of the terrain it follows it automatically.
	ctx.add_node(g, terrain if terrain != null else ctx.root)
	return g.get_info()


func _fill(args: Dictionary, ctx) -> Variant:
	var g = _find_grass(args, ctx)
	if Util.is_err(g):
		return g
	var before := _snapshot(ctx, g)
	var rules := args.duplicate()
	rules.erase("grass")
	var started := Time.get_ticks_msec()
	var coverage: float = g.fill(rules)
	_commit(ctx, g, before)
	return {"grass": str(g.name), "coverage": snappedf(coverage, 0.001), "seconds": (Time.get_ticks_msec() - started) / 1000.0}


func _paint(args: Dictionary, ctx) -> Variant:
	var g = _find_grass(args, ctx)
	if Util.is_err(g):
		return g
	var pts: Array = []
	var raw = args.get("points", null)
	if raw is Array and not (raw as Array).is_empty():
		for p in raw:
			var w = ctx.resolve_position(p)
			if Util.is_err(w):
				return w
			pts.append(w)
	else:
		var w = ctx.resolve_position(args.position)
		if Util.is_err(w):
			return w
		pts.append(w)
	var target := 0.0 if args.erase else float(args.density)
	var before := _snapshot(ctx, g)
	var dabs := 0
	var radius := float(args.radius)
	for i in pts.size():
		if i == 0:
			g.paint(pts[i], radius, target, float(args.strength))
			dabs += 1
			continue
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var steps := maxi(1, int(a.distance_to(b) / maxf(radius * 0.4, 0.2)))
		for s in range(1, steps + 1):
			g.paint(a.lerp(b, float(s) / steps), radius, target, float(args.strength))
			dabs += 1
	_commit(ctx, g, before)
	return {"grass": str(g.name), "dabs": dabs, "coverage": snappedf(g.data.coverage(), 0.001)}


func _clear(args: Dictionary, ctx) -> Variant:
	var g = _find_grass(args, ctx)
	if Util.is_err(g):
		return g
	var before := _snapshot(ctx, g)
	g.clear()
	_commit(ctx, g, before)
	return {"grass": str(g.name), "coverage": 0.0}


func _set_cmd(args: Dictionary, ctx) -> Variant:
	var g = _find_grass(args, ctx)
	if Util.is_err(g):
		return g
	var changed: Array = []
	if args.has("preset"):
		if Presets.resolve(str(args.preset)) == "":
			return Util.err("unknown grass preset '%s' (available: %s)" % [args.preset, ", ".join(Presets.names())])
		ctx.set_property(g, &"preset", Presets.resolve(str(args.preset)))
		g.apply_preset(str(args.preset))
		changed.append("preset")
	changed.append_array(_apply_tunables(g, args, ctx, true))
	return {"grass": str(g.name), "changed": changed, "info": g.get_info()}


func _info(args: Dictionary, ctx) -> Variant:
	var g = _find_grass(args, ctx)
	if Util.is_err(g):
		return g
	var info: Dictionary = g.get_info()
	info["presets"] = Presets.names()
	info["styles"] = GrassScript.STYLES
	return info
