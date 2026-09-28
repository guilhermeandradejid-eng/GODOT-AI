@tool
@icon("res://addons/vibe_vfx/icons/vfx.svg")
class_name VibeVFX3D
extends Node3D
## Ready-made visual effect from the Vibe VFX library (fire, campfire, smoke,
## explosion, magic, portal, rain, snow, fireflies, waterfall, lightning...).
##
## Pick a [member preset] and a [member style]; tweak [member color],
## [member size], [member intensity] and [member speed]. From game code:
## [codeblock]
## VibeVFX3D.spawn(get_tree().current_scene, "explosion", enemy.global_position, {"size": 2.0})
## [/codeblock]

signal finished

const Library = preload("res://addons/vibe_vfx/vfx_library.gd")
const Builder = preload("res://addons/vibe_vfx/vfx_builder.gd")
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const GROUP := &"vibe_vfx"

@export var preset := "fire":
	set(v):
		preset = v
		_queue_rebuild()
@export_enum("realistic", "stylized", "toon", "cel", "lowpoly") var style := "realistic":
	set(v):
		style = v if STYLES.has(v) else "realistic"
		_queue_rebuild()
## Tint for the whole effect (alpha 0 = keep the preset colors).
@export var color := Color(1, 1, 1, 0):
	set(v):
		color = v
		_queue_rebuild()
@export_range(0.05, 50.0, 0.05) var size := 1.0:
	set(v):
		size = v
		_queue_rebuild()
## Particle amount multiplier.
@export_range(0.0, 10.0, 0.05) var intensity := 1.0:
	set(v):
		intensity = v
		_queue_rebuild()
@export_range(0.0, 10.0, 0.05) var speed := 1.0:
	set(v):
		speed = v
		for p in _built.get("particles", []):
			if is_instance_valid(p):
				p.speed_scale = v
@export var emitting := true:
	set(v):
		emitting = v
		for p in _built.get("particles", []):
			if is_instance_valid(p):
				p.emitting = v
@export var light_enabled := true:
	set(v):
		light_enabled = v
		for l in _built.get("lights", []):
			if is_instance_valid(l):
				l.visible = v
## Keep the emitter around the active camera (rain, snow, dust...).
@export var follow_camera := false
## One-shot effects (explosion...) start automatically when entering the tree.
@export var autoplay := true
## Free the node when a one-shot effect finishes (runtime only).
@export var auto_free := false
## Replays one-shot effects every few seconds while editing, as a preview.
@export var preview_loop_in_editor := true
## Replays one-shot effects every N seconds while the game runs (0 = never).
## Handy for showcases and ambient explosions.
@export_range(0.0, 60.0, 0.1, "suffix:s") var loop_interval := 0.0

var _built := {}
var _def := {}
var _time := 0.0
var _playing := false
var _rebuild_queued := false
var _rng := RandomNumberGenerator.new()
var _next_strike := 2.0
var _strike_t := -1.0


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_rng.randomize()
	_rebuild()
	if autoplay:
		play()


## Spawns an effect under `parent` (runtime helper for game code).
static func spawn(parent: Node, preset_name: String, at: Vector3, options: Dictionary = {}) -> Node3D:
	var fx = load("res://addons/vibe_vfx/vibe_vfx_3d.gd").new()
	fx.preset = preset_name
	fx.style = options.get("style", "realistic")
	fx.size = float(options.get("size", 1.0))
	fx.intensity = float(options.get("intensity", 1.0))
	if options.has("color"):
		fx.color = options.color
	var def := Library.get_preset(preset_name)
	fx.auto_free = bool(options.get("auto_free", def.get("one_shot", false)))
	fx.follow_camera = bool(options.get("follow_camera", def.get("follow_camera", false)))
	parent.add_child(fx)
	fx.global_position = at
	return fx


func play() -> void:
	_time = 0.0
	_playing = true
	for p in _built.get("particles", []):
		if is_instance_valid(p):
			p.emitting = emitting
			p.restart()
	for l in _built.get("lights", []):
		if is_instance_valid(l):
			l.light_energy = l.get_meta("base_energy", 1.0)


func stop() -> void:
	_playing = false
	for p in _built.get("particles", []):
		if is_instance_valid(p):
			p.emitting = false


func is_one_shot() -> bool:
	return bool(_def.get("one_shot", false))


func get_effect_radius() -> float:
	var s := size * float(_def.get("scale", 1.0))
	match str(_def.get("category", "")):
		"weather":
			return 12.0
		"impact":
			return 4.0 * s
	return maxf(1.5 * s, 1.0)


func get_info() -> Dictionary:
	return {
		"name": str(name), "type": "VibeVFX3D", "preset": preset, "style": style,
		"size": size, "intensity": intensity, "one_shot": is_one_shot(), "follow_camera": follow_camera,
		"position": global_position if is_inside_tree() else position,
		"color": ("#" + color.to_html(false)) if color.a > 0.0 else "",
		"description": _def.get("description", ""),
	}


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	if _rebuild_queued:
		_rebuild()
		if autoplay:
			play()


func _rebuild() -> void:
	_rebuild_queued = false
	for c in get_children(true):
		if c.get_meta("vibe_fx_internal", false) or _is_internal(c):
			remove_child(c)
			c.queue_free()
	_def = Library.get_preset(preset)
	if _def.is_empty():
		push_warning("VibeVFX3D '%s': unknown preset '%s'" % [name, preset])
		_built = {}
		return
	var opts := {"style": style, "scale": size, "intensity": intensity, "speed": speed}
	if color.a > 0.0:
		opts["color"] = Color(color.r, color.g, color.b, 1.0)
	_built = Builder.build(self, _def, opts)
	for arr in [_built.particles, _built.lights, _built.fx]:
		for n in arr:
			n.set_meta("vibe_fx_internal", true)
	for l in _built.lights:
		l.visible = light_enabled
	for p in _built.particles:
		p.emitting = emitting and (autoplay or not is_one_shot())
	_next_strike = _rng.randf_range(0.5, 2.5)


func _is_internal(n: Node) -> bool:
	return n.get_parent() == self and n.owner == null and n.get_meta("vibe_fx_internal", false)


func _process(delta: float) -> void:
	if _built.is_empty():
		return
	_time += delta
	if follow_camera:
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			var p := cam.global_position
			global_position = Vector3(p.x, p.y - 2.0, p.z)
	for l in _built.lights:
		if not is_instance_valid(l):
			continue
		var base: float = l.get_meta("base_energy", 1.0)
		var flicker: float = l.get_meta("flicker", 0.0)
		var decay: float = l.get_meta("decay", 0.0)
		var e := base
		if flicker > 0.0:
			e *= 1.0 + (sin(_time * 13.0) * 0.5 + sin(_time * 29.0 + 1.3) * 0.3 + sin(_time * 7.0 + 2.1) * 0.2) * flicker
		if decay > 0.0:
			e *= exp(-decay * _time)
		if str(preset) == "lightning":
			e = l.light_energy
		l.light_energy = maxf(e, 0.0)
	for fx in _built.fx:
		if not is_instance_valid(fx):
			continue
		match str(fx.get_meta("anim", "")):
			"shockwave":
				var dur := float(_def.get("duration", 1.2)) * 0.6
				var t := clampf(_time / dur, 0.0, 1.0)
				var mat := (fx as MeshInstance3D).material_override as ShaderMaterial
				mat.set_shader_parameter("progress", 1.0 - pow(1.0 - t, 2.2) if _playing else 1.0)
			"lightning":
				_update_lightning(fx, delta)
	if is_one_shot() and _playing and _time >= float(_def.get("duration", 2.0)):
		_playing = false
		finished.emit()
		if auto_free and not Engine.is_editor_hint():
			queue_free()
	if is_one_shot() and not _playing:
		var dur := float(_def.get("duration", 2.0))
		if Engine.is_editor_hint():
			if preview_loop_in_editor and _time > dur + 1.0:
				play()
		elif loop_interval > 0.0 and _time > maxf(loop_interval, dur):
			play()


func _update_lightning(fx: MeshInstance3D, delta: float) -> void:
	var s: float = fx.get_meta("scale", 1.0)
	var light: OmniLight3D = _built.lights[0] if not _built.lights.is_empty() else null
	if _strike_t < 0.0:
		_next_strike -= delta * speed
		fx.visible = false
		if light != null:
			light.light_energy = move_toward(light.light_energy, 0.0, delta * 40.0)
		if _next_strike <= 0.0 and emitting:
			_strike_t = 0.0
			fx.mesh = Builder.lightning_mesh(45.0 * s, 0.12 * s, _rng)
			if light != null:
				light.position = Vector3(0, 20.0 * s, 0)
	else:
		_strike_t += delta
		var on := fmod(_strike_t, 0.09) < 0.055
		fx.visible = on
		if light != null:
			light.light_energy = 14.0 if on else 3.0
		if _strike_t > 0.32:
			_strike_t = -1.0
			fx.visible = false
			_next_strike = _rng.randf_range(2.0, 6.0)
