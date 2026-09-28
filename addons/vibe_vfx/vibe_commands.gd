@tool
extends RefCounted
## Terminal/bridge commands for effects (vfx.*) and atmosphere (env.*).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const VFXScript = preload("res://addons/vibe_vfx/vibe_vfx_3d.gd")
const Library = preload("res://addons/vibe_vfx/vfx_library.gd")
const Env = preload("res://addons/vibe_vfx/env_presets.gd")

const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]


func register(reg) -> void:
	var presets: Array = Library.PRESETS.keys()
	reg.add("vfx.list", {
		"description": "Lists every VFX preset (built-in + custom from res://vfx_presets) with description and category.",
		"args": {"category": {"type": "string", "description": "fire, smoke, impact, magic, ambient, weather, water."}},
		"handler": _list,
	})
	reg.add("vfx.spawn", {
		"description": "Adds a visual effect: " + ", ".join(presets) + ". Accepts PT/EN names (fogueira, explosão, chuva...). Weather presets follow the camera.",
		"args": {
			"preset": {"type": "string", "required": true, "description": "Effect preset (or alias)."},
			"position": {"type": "position", "default": "center", "description": "Where ([x,z] snaps to the terrain)."},
			"name": {"type": "string", "description": "Node name (default: preset name)."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style (default: scene style or realistic)."},
			"color": {"type": "color", "description": "Tint/hue shift, e.g. 'blue' for blue fire."},
			"scale": {"type": "number", "default": 1.0, "description": "Effect size multiplier."},
			"intensity": {"type": "number", "default": 1.0, "description": "Particle amount multiplier."},
			"speed": {"type": "number", "default": 1.0, "description": "Simulation speed."},
			"y_offset": {"type": "number", "default": 0.0, "description": "Extra height above the ground."},
			"follow_camera": {"type": "boolean", "description": "Keep around the camera (default true for weather)."},
			"parent": {"type": "string", "description": "Parent node (default scene root)."},
			"seed": {"type": "integer", "default": 0, "description": "Seed for anchor positions (flat, random...)."},
		},
		"handler": _spawn,
		"examples": [{"preset": "campfire", "position": "flat"}, {"preset": "fire", "position": [12, -4], "color": "blue", "scale": 1.5}],
	})
	reg.add("vfx.set", {
		"description": "Changes an existing effect (preset, style, color, size, intensity, speed, emitting, light).",
		"args": {
			"name": {"type": "string", "required": true, "description": "Effect node name/path."},
			"preset": {"type": "string", "description": "New preset."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style."},
			"color": {"type": "color", "description": "Tint ('none' to reset)."},
			"scale": {"type": "number", "description": "Size multiplier."},
			"intensity": {"type": "number", "description": "Amount multiplier."},
			"speed": {"type": "number", "description": "Simulation speed."},
			"emitting": {"type": "boolean", "description": "On/off."},
			"light_enabled": {"type": "boolean", "description": "Effect light on/off."},
			"position": {"type": "position", "description": "Move it."},
		},
		"handler": _set_cmd,
	})
	reg.add("vfx.remove", {
		"description": "Removes an effect by name, or all effects (all: true).",
		"args": {"name": {"type": "string", "description": "Effect name."}, "all": {"type": "boolean", "default": false, "description": "Remove every effect."}},
		"handler": _remove,
	})
	reg.add("vfx.play", {
		"description": "Restarts an effect (useful for one-shots like explosion/shockwave).",
		"args": {"name": {"type": "string", "required": true, "description": "Effect name."}},
		"handler": _play,
	})
	reg.add("vfx.describe", {
		"description": "Returns the full JSON definition of a preset (copy it, tweak it and save with vfx.define).",
		"args": {"preset": {"type": "string", "required": true, "description": "Preset name."}},
		"handler": _describe,
	})
	reg.add("vfx.define", {
		"description": "Creates/overwrites a custom VFX preset saved as res://vfx_presets/<name>.json. Start from 'based_on' and override keys, or pass a full 'definition' (see vfx.describe for the format).",
		"args": {
			"name": {"type": "string", "required": true, "description": "New preset name."},
			"based_on": {"type": "string", "description": "Existing preset to copy first."},
			"definition": {"type": "object", "default": {}, "description": "Preset keys to set/override (layers, light, mesh_fx, one_shot...)."},
			"layer_overrides": {"type": "object", "default": {}, "description": "Keys applied to every emitter layer (e.g. {\"color_ramp\": [[0, \"#00ffffff\"], [1, \"#0000ff00\"]]})."},
		},
		"handler": _define,
	})
	reg.add("env.set", {
		"description": "Sets the atmosphere: sky, sun/moon, fog, glow and post-processing. Presets: " + ", ".join(Env.PRESETS.keys()) + ". Any value can be overridden.",
		"args": {
			"preset": {"type": "string", "default": "day", "description": "Atmosphere preset (PT/EN aliases: noite, pôr do sol...)."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style for post-processing (default: scene style)."},
			"sun_elevation": {"type": "number", "description": "Sun height in degrees (0 = horizon)."},
			"sun_azimuth": {"type": "number", "description": "Sun direction in degrees."},
			"sun_color": {"type": "color", "description": "Sun/moon light color."},
			"sun_energy": {"type": "number", "description": "Sun/moon intensity."},
			"sky_top": {"type": "color", "description": "Sky color at the zenith."},
			"sky_horizon": {"type": "color", "description": "Sky color at the horizon."},
			"clouds": {"type": "number", "description": "Cloud coverage 0..1."},
			"cloud_color": {"type": "color", "description": "Cloud color."},
			"stars": {"type": "number", "description": "Star brightness 0..1."},
			"fog_density": {"type": "number", "description": "Fog density (0 = off, 0.02 = thick)."},
			"fog_color": {"type": "color", "description": "Fog color."},
			"glow": {"type": "number", "description": "Bloom amount."},
			"exposure": {"type": "number", "description": "Camera exposure."},
			"ambient": {"type": "number", "description": "Ambient light energy."},
		},
		"handler": _env_set,
	})
	reg.add("env.list", {
		"description": "Lists atmosphere presets.",
		"handler": func(_a, _c): return {"presets": _env_list(), "styles": STYLES},
	})


func _env_list() -> Dictionary:
	var out := {}
	for k in Env.PRESETS:
		out[k] = Env.PRESETS[k].description
	return out


func _scene_style(ctx) -> String:
	if ctx.root != null and ctx.root.has_meta("vibe_style"):
		return str(ctx.root.get_meta("vibe_style"))
	return "realistic"


func _list(args: Dictionary, _ctx) -> Variant:
	var out: Array = []
	for n in Library.names():
		var d := Library.get_preset(n)
		if str(args.get("category", "")) != "" and d.get("category", "") != args.category:
			continue
		out.append({"name": n, "description": d.get("description", ""), "category": d.get("category", "custom"),
			"one_shot": d.get("one_shot", false), "follow_camera": d.get("follow_camera", false)})
	return {"presets": out, "styles": STYLES}


func _find_vfx(ctx, n: String) -> Node:
	var node: Node = ctx.find_node(n)
	if node != null and node.is_in_group(Util.VFX_GROUP):
		return node
	return ctx.find_in_group(Util.VFX_GROUP, n)


func _spawn(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var key := Library.resolve(str(args.preset))
	if key == "":
		return Util.err("unknown VFX preset '%s' (see vfx.list). Available: %s" % [args.preset, ", ".join(Library.names())])
	var def := Library.get_preset(key)
	var pos = ctx.resolve_position(args.position, float(args.y_offset), int(args.seed))
	if Util.is_err(pos):
		return pos
	var parent: Node = ctx.root
	if str(args.get("parent", "")) != "":
		parent = ctx.find_node(args.parent)
		if parent == null:
			return Util.err("parent not found: %s" % args.parent)
	var fx := VFXScript.new()
	fx.name = ctx.unique_name(str(args.get("name", "")) if str(args.get("name", "")) != "" else Util.pascal_case(key), parent)
	fx.preset = key
	fx.style = str(args.get("style", _scene_style(ctx)))
	fx.size = float(args.scale)
	fx.intensity = float(args.intensity)
	fx.speed = float(args.speed)
	if args.has("color"):
		fx.color = args.color
	fx.follow_camera = bool(args.get("follow_camera", def.get("follow_camera", false)))
	ctx.add_node(fx, parent)
	fx.global_position = pos
	return fx.get_info()


func _set_cmd(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var fx := _find_vfx(ctx, str(args.name))
	if fx == null:
		return Util.err("effect not found: %s" % args.name)
	if args.has("preset"):
		var key := Library.resolve(str(args.preset))
		if key == "":
			return Util.err("unknown preset '%s'" % args.preset)
		ctx.set_property(fx, &"preset", key)
	var mapping := {"style": &"style", "scale": &"size", "intensity": &"intensity", "speed": &"speed", "emitting": &"emitting", "light_enabled": &"light_enabled"}
	for k in mapping:
		if args.has(k):
			ctx.set_property(fx, mapping[k], args[k])
	if args.has("color"):
		ctx.set_property(fx, &"color", args.color)
	if args.has("position"):
		var p = ctx.resolve_position(args.position)
		if Util.is_err(p):
			return p
		ctx.set_property(fx, &"global_position", p)
	return fx.get_info()


func _remove(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var removed: Array = []
	if args.all:
		for n in ctx.nodes_in_group(Util.VFX_GROUP):
			removed.append(str(n.name))
			ctx.remove_node(n)
		return {"removed": removed}
	var fx := _find_vfx(ctx, str(args.get("name", "")))
	if fx == null:
		return Util.err("effect not found: %s" % args.get("name", ""))
	removed.append(str(fx.name))
	ctx.remove_node(fx)
	return {"removed": removed}


func _play(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var fx := _find_vfx(ctx, str(args.name))
	if fx == null:
		return Util.err("effect not found: %s" % args.name)
	fx.play()
	return fx.get_info()


func _describe(args: Dictionary, _ctx) -> Variant:
	var d := Library.get_preset(str(args.preset))
	if d.is_empty():
		return Util.err("unknown preset '%s'" % args.preset)
	return {"preset": Library.resolve(str(args.preset)), "definition": d, "sprites": Library.SPRITES.keys()}


func _define(args: Dictionary, _ctx) -> Variant:
	var base := {}
	if str(args.get("based_on", "")) != "":
		base = Library.get_preset(str(args.based_on))
		if base.is_empty():
			return Util.err("unknown base preset '%s'" % args.based_on)
	var def := Util.deep_merge(base, args.definition)
	if not def.has("layers") and not def.has("mesh_fx"):
		return Util.err("a preset needs 'layers' (emitters) or 'mesh_fx' (see vfx.describe fire)")
	var lo: Dictionary = args.layer_overrides
	if not lo.is_empty():
		var layers: Array = []
		for l in def.get("layers", []):
			layers.append(Util.deep_merge(l, lo))
		def["layers"] = layers
	if not def.has("description"):
		def["description"] = "Custom: %s" % args.name
	def["category"] = def.get("category", "custom")
	var path := Library.save_custom(str(args.name), def)
	if path == "":
		return Util.err("could not write the preset file")
	return {"name": Library.normalize(str(args.name)), "path": path, "layers": def.get("layers", []).size()}


func _env_set(args: Dictionary, ctx) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var key := Env.resolve(str(args.preset))
	if key == "":
		return Util.err("unknown atmosphere '%s' (available: %s)" % [args.preset, ", ".join(Env.PRESETS.keys())])
	var style := str(args.get("style", _scene_style(ctx)))
	var overrides := {}
	for k in args:
		if not (k in ["preset", "style"]):
			overrides[k] = args[k]
	var settings := Env.resolve_settings(key, overrides)
	var env_node: WorldEnvironment = ctx.root.find_child("VibeEnvironment", false, false) as WorldEnvironment
	if env_node == null:
		# Only one WorldEnvironment may exist: reuse a foreign one if present.
		for n in ctx.all_nodes():
			if n is WorldEnvironment:
				env_node = n
				break
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "VibeEnvironment"
		env_node.environment = Environment.new()
		ctx.add_node(env_node)
	var sun: DirectionalLight3D = ctx.root.find_child("VibeSun", false, false) as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "VibeSun"
		ctx.add_node(sun)
	var before_env: Environment = env_node.environment.duplicate(true) if env_node.environment != null else null
	var before_sun := {"rotation_degrees": sun.rotation_degrees, "light_color": sun.light_color, "light_energy": sun.light_energy}
	Env.apply(env_node, sun, settings, style)
	if ctx.is_editor():
		ctx.record_method(env_node, &"set_environment", [env_node.environment.duplicate(true)], &"set_environment", [before_env])
		for p in before_sun:
			ctx.record_method(sun, &"set", [p, sun.get(p)], &"set", [p, before_sun[p]])
	ctx.dirty = true
	return {"preset": key, "style": style, "sun": {"elevation": settings.sun_elevation, "azimuth": settings.sun_azimuth}, "fog_density": settings.get("fog_density", 0.0)}
