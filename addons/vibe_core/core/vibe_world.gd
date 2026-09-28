@tool
extends RefCounted
## Builds a whole world from a declarative recipe (JSON). A recipe is the
## "vibe" contract between a human/Claude and the suite:
##
## {
##   "scene": "res://scenes/ilha.tscn",          # optional (creates/opens it)
##   "environment": "sunset" | {"preset": "night", "fog_density": 0.02},
##   "terrain": {
##     "preset": "island", "size": 256, "seed": 7, "height": 40,
##     "palette": "tropical", "water": true, "water_level": 2.0,
##     "features": [ {"type": "river"}, {"type": "lake", "at": "valley"},
##                   {"type": "mountain", "at": [40, -30], "radius": 50, "height": 60},
##                   {"type": "crater", "at": "center"}, {"type": "flatten", "at": "center", "radius": 12},
##                   {"type": "road"} ],
##     "erosion": {"type": "hydraulic", "iterations": 20000},
##     "auto_paint": true
##   },
##   "grass": [ {"preset": "meadow", "density": 0.8}, {"preset": "flowers", "density": 0.3} ],
##   "vfx": [ {"preset": "campfire", "at": "flat"}, {"preset": "fireflies", "count": 3},
##            {"preset": "fire", "at": [10, 5], "color": "blue", "scale": 2} ],
##   "camera": {"type": "fly", "view": "hero"},
##   "style": "toon",                             # realistic | stylized | toon | cel | lowpoly
##   "commands": [ {"cmd": "node.add", "args": {...}} ]   # any extra commands, run last
## }

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const WEATHER := ["rain", "snowfall", "dust", "leaves", "mist"]
const DEFAULT_ANCHOR := {
	"volcano_plume": "peak", "lightning": "random", "waterfall": "random",
	"rain": "center", "snowfall": "center", "dust": "center", "leaves": "center", "mist": "center",
}

const EXAMPLES := {
	"ilha_tropical": {
		"scene": "res://scenes/ilha_tropical.tscn",
		"style": "realistic",
		"environment": "sunset",
		"terrain": {"preset": "island", "size": 256, "seed": 11, "palette": "tropical", "water": true},
		"grass": [{"preset": "lush", "density": 0.9}, {"preset": "flowers", "name": "Flores", "density": 0.25}],
		"vfx": [{"preset": "campfire", "at": "beach"}, {"preset": "fireflies", "count": 2, "at": "flat"}],
		"camera": {"type": "fly", "view": "hero"},
	},
	"montanhas_nevadas": {
		"scene": "res://scenes/montanhas_nevadas.tscn",
		"environment": "dawn",
		"terrain": {"preset": "mountains", "size": 512, "seed": 3, "palette": "snowy", "height_multiplier": 1.3,
			"erosion": {"type": "thermal", "iterations": 30}},
		"grass": [{"preset": "tundra", "density": 0.6}],
		"vfx": [{"preset": "snowfall"}],
		"camera": {"type": "fly", "view": "hero"},
	},
	"deserto_canion": {
		"scene": "res://scenes/deserto_canion.tscn",
		"style": "stylized",
		"environment": "sunset",
		"terrain": {"preset": "canyon", "size": 256, "seed": 21, "palette": "canyon",
			"features": [{"type": "river", "width": 7, "depth": 5}]},
		"grass": [{"preset": "dry", "density": 0.35}],
		"vfx": [{"preset": "dust"}, {"preset": "campfire", "at": "flat"}],
		"camera": {"type": "fly", "view": "hero"},
	},
	"vulcao": {
		"scene": "res://scenes/vulcao.tscn",
		"environment": "stormy",
		"terrain": {"preset": "volcano", "size": 256, "seed": 5, "palette": "volcanic", "water": true},
		"vfx": [{"preset": "volcano_plume", "at": "peak"}, {"preset": "embers", "at": "peak"}, {"preset": "lightning", "at": "random"}],
		"camera": {"type": "fly", "view": "hero"},
	},
	"campo_noturno": {
		"scene": "res://scenes/campo_noturno.tscn",
		"style": "toon",
		"environment": "night",
		"terrain": {"preset": "hills", "size": 256, "seed": 8, "palette": "temperate", "height_multiplier": 0.6,
			"features": [{"type": "lake", "at": "valley", "radius": 28}, {"type": "flatten", "at": "center", "radius": 10}]},
		"grass": [{"preset": "meadow", "density": 1.0}, {"preset": "flowers", "name": "Flores", "density": 0.3}],
		"vfx": [{"preset": "campfire", "at": "center"}, {"preset": "fireflies", "count": 4, "at": "flat"}, {"preset": "portal", "at": "north", "color": "purple"}],
		"camera": {"type": "fly", "view": "hero"},
	},
}

var steps: Array = []
var ok := true


func _step(registry, ctx, cmd: String, args: Dictionary) -> Dictionary:
	var r: Dictionary = await registry.execute(cmd, args, ctx)
	var entry := {"cmd": cmd, "ok": r.get("ok", false)}
	if not r.get("ok", false):
		entry["error"] = r.get("error", "")
		ok = false
	elif r.has("warnings"):
		entry["warnings"] = r.warnings
	steps.append(entry)
	return r


func build(recipe: Dictionary, ctx, registry) -> Dictionary:
	steps.clear()
	ok = true
	var scene_path := str(recipe.get("scene", ""))
	if scene_path != "" and (ctx.root == null or ctx.scene_path != Util.to_res_path(scene_path, "tscn")):
		var r := await _step(registry, ctx, "scene.new", {"path": scene_path, "overwrite": Util.to_bool(recipe.get("overwrite", true))})
		if not r.ok:
			return {"ok": false, "steps": steps}
	if ctx.root == null:
		return Util.err("no scene to build into: pass \"scene\": \"res://scenes/world.tscn\" in the recipe")
	var style := str(recipe.get("style", ""))
	if style != "":
		# Remembered on the scene root so every effect/atmosphere uses it.
		ctx.root.set_meta("vibe_style", style)

	# Environment first so screenshots/editor look right while the rest builds.
	var env = recipe.get("environment", null)
	if env is String:
		env = {"preset": env}
	if env is Dictionary:
		await _step(registry, ctx, "env.set", env)

	var terrain_name := ""
	var t = recipe.get("terrain", null)
	if t is String:
		t = {"preset": t}
	if t is Dictionary:
		var targs := {}
		for k in ["name", "size", "preset", "seed", "height", "height_multiplier", "scale", "roughness", "palette", "water", "water_level", "cell_size", "position"]:
			if t.has(k):
				targs[k] = t[k]
		targs["replace"] = true
		var r := await _step(registry, ctx, "terrain.create", targs)
		if r.ok:
			terrain_name = str(r.result.get("name", ""))
			for f in t.get("features", []):
				if f is Dictionary:
					await _feature(registry, ctx, f, terrain_name)
			var erosion = t.get("erosion", null)
			if erosion is Dictionary:
				var eargs: Dictionary = erosion.duplicate()
				eargs["terrain"] = terrain_name
				await _step(registry, ctx, "terrain.erode", eargs)
			var auto_paint = t.get("auto_paint", true)
			if auto_paint is Dictionary:
				var aargs: Dictionary = auto_paint.duplicate()
				aargs["terrain"] = terrain_name
				await _step(registry, ctx, "terrain.auto_paint", aargs)
			elif Util.to_bool(auto_paint):
				await _step(registry, ctx, "terrain.auto_paint", {"terrain": terrain_name})

	var grass = recipe.get("grass", [])
	if grass is Dictionary or grass is String:
		grass = [grass]
	var gi := 0
	for g in grass:
		if g is String:
			g = {"preset": g}
		if not (g is Dictionary):
			continue
		var gargs := {"preset": g.get("preset", "meadow"), "replace": true}
		gargs["name"] = str(g.get("name", "Grass" if gi == 0 else "Grass%d" % (gi + 1)))
		if terrain_name != "":
			gargs["terrain"] = terrain_name
		for k in ["color_base", "color_tip", "blade_height", "blade_width", "density_per_m2", "view_distance", "wind_strength"]:
			if g.has(k):
				gargs[k] = g[k]
		var r := await _step(registry, ctx, "grass.create", gargs)
		if r.ok:
			var fargs := {"grass": gargs.name, "density": g.get("density", 1.0)}
			var rules = g.get("rules", {})
			if rules is Dictionary:
				fargs.merge(rules)
			await _step(registry, ctx, "grass.fill", fargs)
		gi += 1

	var vfx = recipe.get("vfx", [])
	if vfx is Dictionary or vfx is String:
		vfx = [vfx]
	for v in vfx:
		if v is String:
			v = {"preset": v}
		if not (v is Dictionary):
			continue
		var preset := str(v.get("preset", "fire"))
		var count := clampi(int(v.get("count", 1)), 1, 50)
		for i in count:
			var vargs := {"preset": preset, "seed": i + int(v.get("seed", 0))}
			vargs["position"] = v.get("at", v.get("position", DEFAULT_ANCHOR.get(preset, "flat")))
			for k in ["scale", "color", "intensity", "name", "speed"]:
				if v.has(k):
					vargs[k] = v[k]
			if count > 1 and v.has("name"):
				vargs["name"] = "%s%d" % [v.name, i + 1]
			await _step(registry, ctx, "vfx.spawn", vargs)

	var cam = recipe.get("camera", null)
	if cam is String:
		cam = {"type": cam}
	if cam is Dictionary:
		await _step(registry, ctx, "camera.add", cam)

	if style != "":
		await _step(registry, ctx, "style.set", {"style": style})

	# Anything else, as raw commands (labels, lights, props, extra effects...).
	var extra = recipe.get("commands", [])
	if extra is Array:
		for c in extra:
			if c is Dictionary and str(c.get("cmd", "")) != "":
				var cargs = c.get("args", {})
				await _step(registry, ctx, str(c.cmd), cargs if cargs is Dictionary else {})

	return {"ok": ok, "scene": ctx.scene_path, "terrain": terrain_name, "style": style if style != "" else "realistic", "steps": steps}


func _feature(registry, ctx, f: Dictionary, terrain_name: String) -> void:
	var kind := Util.normalize_text(str(f.get("type", "")))
	var args := f.duplicate()
	args.erase("type")
	args["terrain"] = terrain_name
	match kind:
		"river", "rio":
			args["mode"] = "river"
			await _step(registry, ctx, "terrain.carve_path", args)
		"road", "estrada", "path", "trilha":
			args["mode"] = "road"
			await _step(registry, ctx, "terrain.carve_path", args)
		"flatten", "plateau_flat", "nivelar":
			if args.has("at"):
				args["position"] = args.at
				args.erase("at")
			await _step(registry, ctx, "terrain.flatten_area", args)
		_:
			# mountain, hill, crater, lake, plateau, volcano, pit...
			args["shape"] = kind
			if args.has("at"):
				args["position"] = args.at
				args.erase("at")
			await _step(registry, ctx, "terrain.stamp", args)
