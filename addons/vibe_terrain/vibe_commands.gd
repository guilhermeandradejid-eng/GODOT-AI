@tool
extends RefCounted
## Terminal/bridge commands for VibeTerrain3D (terrain.*).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const TerrainScript = preload("res://addons/vibe_terrain/vibe_terrain_3d.gd")
const DataScript = preload("res://addons/vibe_terrain/vibe_terrain_data.gd")
const LayerScript = preload("res://addons/vibe_terrain/vibe_terrain_layer.gd")
const Generator = preload("res://addons/vibe_terrain/terrain_generator.gd")
const Ops = preload("res://addons/vibe_terrain/terrain_ops.gd")
const Palettes = preload("res://addons/vibe_terrain/terrain_palettes.gd")

const T_ARG := {"type": "string", "description": "Terrain node name (defaults to the first terrain in the scene)."}


func register(reg) -> void:
	var presets: Array = Generator.PRESETS.keys()
	var palettes: Array = Palettes.names()
	reg.add("terrain.create", {
		"description": "Creates a VibeTerrain3D (heightmap terrain) and generates it from a preset: " + ", ".join(presets) + ". Also paints it (biome palette) and can add a sea.",
		"args": {
			"name": {"type": "string", "default": "Terrain", "description": "Node name."},
			"size": {"type": "number", "default": 256.0, "description": "Width/depth in meters (the terrain is centered on its position)."},
			"cell_size": {"type": "number", "description": "Meters between vertices (default 1, or 2 for sizes above 512)."},
			"preset": {"type": "string", "default": "hills", "enum": presets + ["none"], "open_enum": true, "description": "Landform generator."},
			"seed": {"type": "integer", "default": 1, "description": "Random seed (same seed = same terrain)."},
			"height": {"type": "number", "description": "Peak height in meters (auto per preset when omitted)."},
			"height_multiplier": {"type": "number", "default": 1.0, "description": "Scales the preset height (e.g. 1.5 = taller)."},
			"scale": {"type": "number", "default": 1.0, "description": "Feature size multiplier (bigger = broader shapes)."},
			"roughness": {"type": "number", "default": 0.5, "description": "0..1 amount of small detail."},
			"palette": {"type": "string", "default": "temperate", "enum": palettes, "open_enum": true, "description": "Biome colors + auto-paint rules."},
			"water": {"type": "boolean", "default": false, "description": "Adds a sea plane at water_level (islands/volcano usually want this)."},
			"water_level": {"type": "number", "default": 0.0, "description": "Sea level (local height)."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Paint layers from height/slope rules after generating."},
			"position": {"type": "vector3", "default": [0, 0, 0], "description": "Node position."},
			"replace": {"type": "boolean", "default": false, "description": "Replace an existing terrain with the same name."},
		},
		"handler": _create,
		"examples": [{"preset": "island", "size": 256, "palette": "tropical", "water": true, "seed": 7}],
	})
	reg.add("terrain.generate", {
		"description": "Regenerates (or layers) a preset on an existing terrain. mode: replace | add | max | min | blend.",
		"args": {
			"terrain": T_ARG,
			"preset": {"type": "string", "required": true, "enum": presets, "open_enum": true, "description": "Landform generator."},
			"seed": {"type": "integer", "default": 1, "description": "Random seed."},
			"height": {"type": "number", "description": "Peak height in meters."},
			"height_multiplier": {"type": "number", "default": 1.0, "description": "Scales the preset height."},
			"scale": {"type": "number", "default": 1.0, "description": "Feature size multiplier."},
			"roughness": {"type": "number", "default": 0.5, "description": "0..1 detail."},
			"mode": {"type": "string", "default": "replace", "enum": ["replace", "add", "max", "min", "blend"], "description": "How to combine with the current heights."},
			"strength": {"type": "number", "default": 1.0, "description": "Factor for add/blend."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Repaint layers afterwards."},
		},
		"handler": _generate,
	})
	reg.add("terrain.sculpt", {
		"description": "Sculpts with a brush: raise, lower, smooth, flatten, set (exact height), noise, terrace. Use 'points' for a stroke along a path.",
		"args": {
			"terrain": T_ARG,
			"op": {"type": "string", "required": true, "enum": Ops.SCULPT_OPS, "description": "Brush operation."},
			"position": {"type": "position", "default": "center", "description": "Brush center."},
			"points": {"type": "array", "description": "Optional stroke: list of positions ([x,z]) to apply the brush along."},
			"radius": {"type": "number", "default": 12.0, "description": "Brush radius in meters."},
			"strength": {"type": "number", "default": 3.0, "description": "Meters for raise/lower/noise; 0..1 for smooth/flatten/terrace."},
			"height": {"type": "number", "description": "Target height for flatten/set."},
			"hardness": {"type": "number", "default": 0.35, "description": "0 = soft edge, 1 = hard edge."},
			"step": {"type": "number", "default": 4.0, "description": "Terrace step height (terrace op)."},
			"spacing": {"type": "number", "description": "Distance between dabs along 'points' (default radius/3)."},
		},
		"handler": _sculpt,
		"examples": [{"op": "raise", "position": [30, -20], "radius": 25, "strength": 15}, {"op": "smooth", "position": "center", "radius": 40, "strength": 0.8}],
	})
	reg.add("terrain.paint", {
		"description": "Paints a surface layer (0..3 or its name, e.g. 'Rocha') with a brush. Use 'points' to paint along a path.",
		"args": {
			"terrain": T_ARG,
			"layer": {"type": "any", "required": true, "description": "Layer index 0-3 or layer name."},
			"position": {"type": "position", "default": "center", "description": "Brush center."},
			"points": {"type": "array", "description": "Optional list of positions for a stroke."},
			"radius": {"type": "number", "default": 8.0, "description": "Brush radius in meters."},
			"strength": {"type": "number", "default": 1.0, "description": "0..1."},
			"hardness": {"type": "number", "default": 0.4, "description": "Edge hardness."},
		},
		"handler": _paint,
	})
	reg.add("terrain.auto_paint", {
		"description": "Repaints all layers automatically from height/slope rules (beach near water, rock on cliffs, snow/lava on peaks). Override any rule, e.g. {\"cliff_slope\": 30, \"peak_height\": 0.7}.",
		"args": {
			"terrain": T_ARG,
			"rules": {"type": "object", "default": {}, "description": "Rule overrides: base_layer, beach_layer, beach_band, cliff_layer, cliff_slope, steep_layer, steep_slope, peak_layer, peak_height (0..1), peak_max_slope, peak_concave, patch_layer, patch_amount, seed."},
		},
		"allow_extra_args": true,
		"handler": _auto_paint,
	})
	reg.add("terrain.erode", {
		"description": "Erosion for realism: 'hydraulic' (water carves gullies; iterations = droplets) or 'thermal' (slopes settle; iterations = passes).",
		"args": {
			"terrain": T_ARG,
			"type": {"type": "string", "default": "hydraulic", "enum": ["hydraulic", "thermal"], "description": "Erosion model."},
			"iterations": {"type": "integer", "description": "Droplets (hydraulic, default ~0.35 per vertex) or passes (thermal, default 20)."},
			"strength": {"type": "number", "default": 1.0, "description": "Erosion strength."},
			"talus": {"type": "number", "default": 34.0, "description": "Thermal: stable slope angle in degrees."},
			"seed": {"type": "integer", "default": 1, "description": "Random seed (hydraulic)."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Repaint layers afterwards."},
		},
		"handler": _erode,
	})
	reg.add("terrain.carve_path", {
		"description": "Carves a river (channel + flowing water) or a road (flattened strip) along points, or along an automatic natural path when no points are given.",
		"args": {
			"terrain": T_ARG,
			"mode": {"type": "string", "default": "river", "enum": ["river", "road"], "description": "river or road."},
			"points": {"type": "array", "description": "World positions [[x,z], ...]. Omit for an automatic path."},
			"width": {"type": "number", "description": "Width in meters (default 7 river / 5 road)."},
			"depth": {"type": "number", "default": 2.5, "description": "River depth in meters."},
			"seed": {"type": "integer", "default": 1, "description": "Seed for the automatic path."},
			"paint_layer": {"type": "integer", "description": "Layer painted along the path (default: 1 = dirt/sand)."},
		},
		"handler": _carve_path,
	})
	reg.add("terrain.stamp", {
		"description": "Adds a landform at a position: mountain, hill, crater, volcano, lake (adds water), plateau, pit.",
		"args": {
			"terrain": T_ARG,
			"shape": {"type": "string", "required": true, "enum": Ops.STAMP_SHAPES, "open_enum": true, "description": "Landform."},
			"position": {"type": "position", "default": "center", "description": "Where."},
			"radius": {"type": "number", "default": 30.0, "description": "Radius in meters."},
			"height": {"type": "number", "description": "Height (or depth for crater/lake/pit) in meters."},
			"seed": {"type": "integer", "default": 1, "description": "Noise seed."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Repaint layers afterwards."},
		},
		"handler": _stamp,
	})
	reg.add("terrain.flatten_area", {
		"description": "Flattens a circular area (e.g. for a building, arena or camp).",
		"args": {
			"terrain": T_ARG,
			"position": {"type": "position", "default": "center", "description": "Center."},
			"radius": {"type": "number", "default": 12.0, "description": "Radius in meters."},
			"height": {"type": "number", "description": "Target height (default: average height there)."},
		},
		"handler": _flatten_area,
	})
	reg.add("terrain.palette", {
		"description": "Applies a biome palette to the 4 layers: " + ", ".join(palettes) + ".",
		"args": {
			"terrain": T_ARG,
			"name": {"type": "string", "required": true, "enum": palettes, "open_enum": true, "description": "Palette name (PT/EN aliases accepted)."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Repaint with the palette's rules."},
		},
		"handler": _palette,
	})
	reg.add("terrain.set_layer", {
		"description": "Edits one surface layer (colors, roughness, glow, rock strata, textures).",
		"args": {
			"terrain": T_ARG,
			"index": {"type": "integer", "required": true, "description": "Layer 0-3."},
			"name": {"type": "string", "description": "Display name."},
			"color_a": {"type": "color", "description": "Main color."},
			"color_b": {"type": "color", "description": "Variation color."},
			"noise_scale": {"type": "number", "description": "Variation patch frequency."},
			"strata": {"type": "number", "description": "0..1 rock banding."},
			"roughness": {"type": "number", "description": "0..1."},
			"emission": {"type": "number", "description": "Glow strength (lava, crystals)."},
			"albedo_texture": {"type": "string", "description": "res:// texture path ('' to remove)."},
			"normal_texture": {"type": "string", "description": "res:// normal map path ('' to remove)."},
			"uv_scale": {"type": "number", "description": "Meters per texture tile."},
		},
		"handler": _set_layer,
	})
	reg.add("terrain.water", {
		"description": "Configures the sea/water plane (and optionally removes rivers/lakes).",
		"args": {
			"terrain": T_ARG,
			"enabled": {"type": "boolean", "default": true, "description": "Show the sea plane."},
			"level": {"type": "number", "description": "Water level (local height)."},
			"deep_color": {"type": "color", "description": "Deep water color."},
			"shallow_color": {"type": "color", "description": "Shallow water color."},
			"clear_features": {"type": "boolean", "default": false, "description": "Remove all rivers and lakes."},
		},
		"handler": _water,
	})
	reg.add("terrain.info", {
		"description": "Size, resolution, height range, palette, layers and water of a terrain.",
		"args": {"terrain": T_ARG},
		"handler": _info,
	})
	reg.add("terrain.height_at", {
		"description": "Height, slope and layer weights at a position (useful to place things precisely).",
		"args": {"terrain": T_ARG, "position": {"type": "position", "required": true, "description": "[x, z] or anchor."}},
		"handler": _height_at,
	})
	reg.add("terrain.import_heightmap", {
		"description": "Imports a grayscale image (PNG/EXR/...) as heights between min_height and max_height.",
		"args": {
			"terrain": T_ARG,
			"path": {"type": "string", "required": true, "description": "Image path (res:// or absolute)."},
			"min_height": {"type": "number", "default": 0.0, "description": "Height of black."},
			"max_height": {"type": "number", "default": 60.0, "description": "Height of white."},
			"auto_paint": {"type": "boolean", "default": true, "description": "Repaint afterwards."},
		},
		"handler": _import_heightmap,
	})
	reg.add("terrain.export_heightmap", {
		"description": "Exports the heightmap: .exr keeps real heights (float), .png is a normalized 8-bit preview.",
		"args": {"terrain": T_ARG, "path": {"type": "string", "required": true, "description": "Output (res://... .png or .exr)."}},
		"handler": _export_heightmap,
	})


# --- helpers -------------------------------------------------------------------------------

func _find_terrain(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var wanted := str(args.get("terrain", ""))
	var t: Node = ctx.get_terrain(wanted)
	if t == null:
		if wanted != "":
			return Util.err("terrain '%s' not found" % wanted)
		return Util.err("no VibeTerrain3D in the scene. Create one with terrain.create (e.g. {\"preset\": \"hills\"}).")
	return t


func _begin(ctx, t: Node) -> Dictionary:
	return t.make_snapshot() if ctx.is_editor() else {}


func _commit(ctx, t: Node, before: Dictionary) -> void:
	ctx.dirty = true
	if ctx.is_editor():
		ctx.record_snapshot(t, before, t.make_snapshot())


func _texel_radius(t: Node, meters: float) -> float:
	var s: float = t.global_transform.basis.get_scale().x if t.is_inside_tree() else 1.0
	return meters / (t.data.cell_size * maxf(s, 0.0001))


func _to_texel(t: Node, ctx, pos: Variant) -> Variant:
	var p = ctx.resolve_position(pos)
	if Util.is_err(p):
		return p
	return t.world_to_texel(p)


func _positions(t: Node, ctx, args: Dictionary) -> Variant:
	var pts: Array = []
	var raw = args.get("points", null)
	if raw is Array and not (raw as Array).is_empty():
		for p in raw:
			var tx = _to_texel(t, ctx, p)
			if Util.is_err(tx):
				return tx
			pts.append(tx)
	else:
		var tx = _to_texel(t, ctx, args.get("position", "center"))
		if Util.is_err(tx):
			return tx
		pts.append(tx)
	return pts


func _stroke(pts: Array, spacing: float) -> Array:
	if pts.size() < 2:
		return pts
	return Ops._resample(pts, maxf(spacing, 0.5))


func _layer_index(t: Node, value: Variant) -> int:
	if value is float or value is int:
		return clampi(int(value), 0, 3)
	var s := Util.normalize_text(str(value))
	if s.is_valid_int():
		return clampi(s.to_int(), 0, 3)
	var layers: Array = t.get_layers()
	for i in layers.size():
		if layers[i] != null and Util.normalize_text(layers[i].name).begins_with(s):
			return i
	var generic := {"grass": 0, "grama": 0, "base": 0, "dirt": 1, "terra": 1, "sand": 1, "areia": 1, "rock": 2, "rocha": 2, "pedra": 2, "cliff": 2, "snow": 3, "neve": 3, "lava": 3, "special": 3}
	return generic.get(s, -1)


func _repaint(t: Node, extra_rules: Dictionary = {}) -> void:
	var rules: Dictionary = t.get_palette_rules()
	rules.merge(extra_rules, true)
	var wl: float = t.water_level if (t.water_enabled or not t.lakes.is_empty() or not t.rivers.is_empty()) else -INF
	Ops.auto_paint(t.data, rules, wl)
	t.notify_splat_changed()


func _resolution_for(size: float, cell: float) -> int:
	var quads := maxi(16, int(round(size / cell)))
	quads = int(ceil(float(quads) / 32.0)) * 32
	return quads + 1


# --- handlers --------------------------------------------------------------------------------

func _create(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var node_name := str(args.name)
	var existing: Node = ctx.find_in_group(Util.TERRAIN_GROUP, node_name)
	if existing != null:
		if not args.replace:
			return Util.err("a terrain named '%s' already exists (use replace: true or another name)" % node_name)
		ctx.remove_node(existing)
	var size := clampf(float(args.size), 16.0, 8192.0)
	var cell := float(args.get("cell_size", 2.0 if size > 512.0 else 1.0))
	cell = clampf(cell, 0.1, 64.0)
	var res := _resolution_for(size, cell)
	if res > 2049:
		return Util.err("terrain too detailed (%d vertices per side). Increase cell_size." % res)
	var data := DataScript.new()
	data.setup(res, cell)
	var t := TerrainScript.new()
	t.name = ctx.unique_name(node_name) if existing == null else node_name
	t.water_enabled = args.water
	t.water_level = float(args.water_level)
	t.apply_palette(str(args.palette))
	var gen := {}
	var preset := str(args.preset)
	if preset != "none" and preset != "":
		var params := {"preset": preset, "seed": args.seed, "height_multiplier": args.height_multiplier, "scale": args.scale, "roughness": args.roughness}
		if args.has("height"):
			params["height"] = args.height
		gen = Generator.generate(data, params)
	t.data = data
	var err: Error = ctx.adopt_resource(data, ctx.data_path_for(str(t.name), "terrain"))
	if err != OK:
		ctx.warn("could not write terrain data file (%s); it will be embedded in the scene" % error_string(err))
	ctx.add_node(t)
	t.position = Util.parse_vector3(args.position)
	if args.auto_paint:
		_repaint(t)
	ctx.info("terrain %s: %s %dm (%dx%d)" % [t.name, preset, int(data.get_size()), res, res])
	var info: Dictionary = t.get_info()
	info["generator"] = gen
	return info


func _generate(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var before := _begin(ctx, t)
	var params := {"preset": args.preset, "seed": args.seed, "height_multiplier": args.height_multiplier, "scale": args.scale,
		"roughness": args.roughness, "mode": args.mode, "strength": args.strength}
	if args.has("height"):
		params["height"] = args.height
	var gen := Generator.generate(t.data, params)
	t.notify_heights_changed()
	if args.auto_paint:
		_repaint(t)
	_commit(ctx, t, before)
	return gen


func _sculpt(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var pts = _positions(t, ctx, args)
	if Util.is_err(pts):
		return pts
	var radius := _texel_radius(t, float(args.radius))
	var spacing := _texel_radius(t, float(args.get("spacing", float(args.radius) / 3.0)))
	var opts := {"hardness": args.hardness, "step": args.step}
	if args.has("height"):
		opts["height"] = float(args.height)
	elif args.op in ["flatten", "set"] and not (pts as Array).is_empty():
		opts["height"] = t.data.sample(pts[0].x, pts[0].y)
	var before := _begin(ctx, t)
	var stroke := _stroke(pts, spacing)
	var strength := float(args.strength)
	# Spread raise/lower over the stroke so the total amount matches `strength`.
	if stroke.size() > 1 and args.op in ["raise", "lower", "noise"]:
		strength /= clampf(float(radius) / maxf(spacing, 0.5), 1.0, 8.0)
	for p in stroke:
		Ops.sculpt(t.data, args.op, p, radius, strength, opts)
	t.notify_heights_changed()
	_commit(ctx, t, before)
	var r: Vector2 = t.get_height_range()
	return {"op": args.op, "dabs": stroke.size(), "height_range": [snappedf(r.x, 0.01), snappedf(r.y, 0.01)]}


func _paint(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var layer := _layer_index(t, args.layer)
	if layer < 0:
		return Util.err("unknown layer '%s' (use 0-3 or a layer name: %s)" % [args.layer, str(t.get_layers().map(func(l): return l.name))])
	var pts = _positions(t, ctx, args)
	if Util.is_err(pts):
		return pts
	var radius := _texel_radius(t, float(args.radius))
	var before := _begin(ctx, t)
	for p in _stroke(pts, maxf(radius / 3.0, 0.5)):
		Ops.paint(t.data, layer, p, radius, float(args.strength), float(args.hardness))
	t.notify_splat_changed()
	_commit(ctx, t, before)
	return {"layer": layer, "layer_name": t.get_layer(layer).name}


func _auto_paint(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var rules: Dictionary = args.get("rules", {}).duplicate()
	for k in args:
		if Ops.DEFAULT_RULES.has(k):
			rules[k] = args[k]
	var before := _begin(ctx, t)
	_repaint(t, rules)
	_commit(ctx, t, before)
	var used: Dictionary = t.get_palette_rules()
	used.merge(rules, true)
	return {"palette": t.palette, "rules": used}


func _erode(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var before := _begin(ctx, t)
	var res: int = t.data.resolution
	var started := Time.get_ticks_msec()
	var iterations := 0
	if args.type == "thermal":
		iterations = int(args.get("iterations", 20))
		Ops.thermal_erosion(t.data, clampi(iterations, 1, 500), float(args.talus), float(args.strength))
	else:
		iterations = int(args.get("iterations", int(res * res * 0.35)))
		Ops.hydraulic_erosion(t.data, clampi(iterations, 1, 2000000), int(args.seed), float(args.strength))
	t.notify_heights_changed()
	if args.auto_paint:
		_repaint(t)
	_commit(ctx, t, before)
	return {"type": args.type, "iterations": iterations, "seconds": (Time.get_ticks_msec() - started) / 1000.0}


func _carve_path(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var mode := str(args.mode)
	var width_m := float(args.get("width", 7.0 if mode == "river" else 5.0))
	var pts: Array = []
	if args.get("points", null) is Array and (args.points as Array).size() >= 2:
		for p in args.points:
			var tx = _to_texel(t, ctx, p)
			if Util.is_err(tx):
				return tx
			pts.append(tx)
	else:
		var wl: float = t.water_level if t.water_enabled else -INF
		pts = Ops.auto_path(t.data, mode, int(args.seed), wl)
	if pts.size() < 2:
		return Util.err("path needs at least 2 points")
	var before := _begin(ctx, t)
	var water_min: float = t.water_level if t.water_enabled else -INF
	var result := Ops.carve_path(t.data, pts, _texel_radius(t, width_m), float(args.depth), mode, water_min)
	var layer := int(args.get("paint_layer", 1))
	if layer >= 0:
		for p in result.points:
			Ops.paint(t.data, layer, p, _texel_radius(t, width_m) * (0.9 if mode == "road" else 1.3), 0.8, 0.5)
	t.notify_heights_changed()
	t.notify_splat_changed()
	if mode == "river":
		var local_pts := PackedVector2Array()
		for p in result.points:
			var lp: Vector3 = t.texel_to_local(p)
			local_pts.append(Vector2(lp.x, lp.z))
		t.add_river(local_pts, PackedFloat32Array(result.levels), width_m)
	_commit(ctx, t, before)
	var length := 0.0
	for i in range(1, result.points.size()):
		length += (result.points[i] as Vector2).distance_to(result.points[i - 1]) * t.data.cell_size
	return {"mode": mode, "length_m": snappedf(length, 0.1), "width": width_m, "start": t.texel_to_world(result.points[0]), "end": t.texel_to_world(result.points[-1])}


func _stamp(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var shape := Util.normalize_text(str(args.shape))
	shape = Ops.STAMP_ALIASES.get(shape, shape)
	if not Ops.STAMP_SHAPES.has(shape):
		return Util.err("unknown shape '%s' (use %s)" % [args.shape, ", ".join(Ops.STAMP_SHAPES)])
	var c = _to_texel(t, ctx, args.position)
	if Util.is_err(c):
		return c
	var radius_m := float(args.radius)
	var default_h := {"mountain": radius_m * 0.8, "hill": radius_m * 0.3, "crater": radius_m * 0.35, "volcano": radius_m * 0.9, "lake": 3.5, "plateau": radius_m * 0.4, "pit": radius_m * 0.3}
	var h := float(args.get("height", default_h.get(shape, 10.0)))
	var before := _begin(ctx, t)
	var r := Ops.stamp(t.data, shape, c, _texel_radius(t, radius_m), h, int(args.seed))
	var out := {"shape": shape, "position": t.texel_to_world(c), "radius": radius_m, "height": h}
	if shape == "lake":
		var lp: Vector3 = t.texel_to_local(c)
		t.add_lake(Vector2(lp.x, lp.z), radius_m, float(r.level))
		out["water_level"] = r.level
	t.notify_heights_changed()
	if args.auto_paint:
		_repaint(t)
	_commit(ctx, t, before)
	return out


func _flatten_area(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var c = _to_texel(t, ctx, args.position)
	if Util.is_err(c):
		return c
	var before := _begin(ctx, t)
	var r := Ops.flatten_area(t.data, c, _texel_radius(t, float(args.radius)), args.get("height", null))
	t.notify_heights_changed()
	_commit(ctx, t, before)
	return {"position": t.texel_to_world(c), "height": r.height, "radius": args.radius}


func _palette(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	if Palettes.resolve(str(args.name)) == "":
		return Util.err("unknown palette '%s' (available: %s)" % [args.name, ", ".join(Palettes.names())])
	var before := _begin(ctx, t)
	var old_layers: Array = t.get_layers()
	t.apply_palette(str(args.name))
	if args.auto_paint:
		_repaint(t)
	_commit(ctx, t, before)
	if ctx.is_editor():
		for i in 4:
			ctx.record_method(t, &"set_layer", [i, t.get_layer(i)], &"set_layer", [i, old_layers[i]])
	return {"palette": t.palette, "layers": t.get_layers().map(func(l): return l.to_dict())}


func _set_layer(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var i := clampi(int(args.index), 0, 3)
	var layer: Resource = t.get_layer(i)
	if layer == null:
		layer = LayerScript.new()
		t.set_layer(i, layer)
	for key in ["name", "color_a", "color_b", "noise_scale", "strata", "roughness", "emission", "uv_scale"]:
		if args.has(key):
			ctx.set_property(layer, key, args[key])
	for key in ["albedo_texture", "normal_texture"]:
		if args.has(key):
			var path := str(args[key])
			var tex: Texture2D = null
			if path != "":
				path = Util.to_res_path(path)
				if not ResourceLoader.exists(path):
					return Util.err("texture not found: %s" % path)
				tex = load(path)
			ctx.set_property(layer, key, tex)
	t.set_layer(i, layer)
	return {"index": i, "layer": layer.to_dict()}


func _water(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	ctx.set_property(t, &"water_enabled", args.enabled)
	if args.has("level"):
		ctx.set_property(t, &"water_level", float(args.level))
	if args.has("deep_color"):
		ctx.set_property(t, &"water_deep_color", args.deep_color)
	if args.has("shallow_color"):
		ctx.set_property(t, &"water_shallow_color", args.shallow_color)
	if args.clear_features:
		var before := _begin(ctx, t)
		t.clear_water_features()
		_commit(ctx, t, before)
	return t.get_info().water


func _info(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var info: Dictionary = t.get_info()
	info["layer_details"] = t.get_layers().map(func(l): return l.to_dict() if l != null else {})
	info["presets"] = Generator.PRESETS.keys()
	info["palettes"] = Palettes.names()
	return info


func _height_at(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var p = ctx.resolve_position(args.position)
	if Util.is_err(p):
		return p
	var tx: Vector2 = t.world_to_texel(p)
	var weights := {}
	var layers: Array = t.get_layers()
	for i in 4:
		weights[layers[i].name if layers[i] != null else str(i)] = snappedf(t.data.sample_weight(tx.x, tx.y, i), 0.01)
	return {
		"position": p,
		"height": snappedf(t.get_height_at_world(p), 0.01),
		"slope_degrees": snappedf(t.get_slope_at_world(p), 0.1),
		"inside": t.is_inside_terrain(p),
		"underwater": t.water_enabled and p.y < t.water_level,
		"layers": weights,
	}


func _import_heightmap(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var path := str(args.path)
	var img: Image = null
	if path.begins_with("res://") or path.begins_with("user://") or not path.is_absolute_path():
		path = Util.to_res_path(path)
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				img = (tex as Texture2D).get_image()
		if img == null:
			img = Image.load_from_file(ProjectSettings.globalize_path(path))
	else:
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return Util.err("could not load image: %s" % args.path)
	var before := _begin(ctx, t)
	t.data.import_height_image(img, float(args.min_height), float(args.max_height))
	t.notify_heights_changed()
	if args.auto_paint:
		_repaint(t)
	_commit(ctx, t, before)
	return {"imported": path, "source_size": [img.get_width(), img.get_height()], "resolution": t.data.resolution}


func _export_heightmap(args: Dictionary, ctx) -> Variant:
	var t = _find_terrain(args, ctx)
	if Util.is_err(t):
		return t
	var path := Util.to_res_path(str(args.path), "png")
	if not Util.is_safe_write_path(path):
		return Util.err("export path must be inside the project (res://) or user://")
	Util.ensure_dir(path.get_base_dir())
	var err := OK
	if path.get_extension().to_lower() == "exr":
		err = t.data.height_image().save_exr(ProjectSettings.globalize_path(path), true)
	else:
		err = t.data.export_height_image().save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		return Util.err("could not save: %s" % error_string(err))
	var r: Vector2 = t.get_height_range()
	return {"path": path, "file": ProjectSettings.globalize_path(path), "height_min": r.x, "height_max": r.y}
