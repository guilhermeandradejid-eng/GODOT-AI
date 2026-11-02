extends Node3D
## Autoload "Fx": explosões de partículas com pool (poeira de areia, anéis de
## pouso, brilhos de coleta, respingos, pétalas, fumaça de breu, rastro de luz).
## Partículas GPU leves (billboards com sprite suave), pensadas para o celular.

const DOT := preload("res://game/assets/textures/soft_dot.png")
const STREAK := preload("res://game/assets/textures/streak.png")

var _pools := {}
var _defs := {}
var _scale := 1.0      ## multiplicador de quantidade (qualidade gráfica)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_defs = {
		"dust": {"amount": 10, "life": 0.7, "color": Color(1.0, 0.94, 0.88, 0.42), "size": [0.12, 0.3],
			"vel": [0.6, 2.0], "spread": 70.0, "dir": Vector3.UP, "grav": Vector3(0, -0.8, 0), "damp": 2.0, "add": false},
		"dust_ring": {"amount": 22, "life": 0.8, "color": Color(1.0, 0.92, 0.84, 0.8), "size": [0.25, 0.6],
			"vel": [3.0, 5.5], "spread": 90.0, "dir": Vector3.UP, "flat": true, "grav": Vector3(0, -0.5, 0), "damp": 5.0, "add": false},
		"sparkle": {"amount": 14, "life": 0.7, "color": Color(1.0, 0.9, 0.55, 1.0), "size": [0.06, 0.16],
			"vel": [1.5, 4.0], "spread": 180.0, "dir": Vector3.UP, "grav": Vector3(0, -2.0, 0), "damp": 1.5, "add": true},
		"seed": {"amount": 60, "life": 1.6, "color": Color(1.0, 0.86, 0.45, 1.0), "size": [0.08, 0.28],
			"vel": [2.0, 7.0], "spread": 180.0, "dir": Vector3.UP, "grav": Vector3(0, -1.5, 0), "damp": 1.2, "add": true},
		"poof": {"amount": 18, "life": 0.9, "color": Color(0.35, 0.22, 0.45, 0.9), "size": [0.25, 0.55],
			"vel": [1.0, 3.0], "spread": 180.0, "dir": Vector3.UP, "grav": Vector3(0, 1.5, 0), "damp": 2.0, "add": false,
			"end_color": Color(1.0, 0.9, 0.7, 0.0)},
		"splash": {"amount": 16, "life": 0.7, "color": Color(0.85, 1.0, 1.0, 0.9), "size": [0.08, 0.2],
			"vel": [2.5, 5.0], "spread": 35.0, "dir": Vector3.UP, "grav": Vector3(0, -12.0, 0), "damp": 0.2, "add": false},
		"petals": {"amount": 20, "life": 1.4, "color": Color(1.0, 0.62, 0.72, 1.0), "size": [0.1, 0.2],
			"vel": [2.0, 5.0], "spread": 120.0, "dir": Vector3.UP, "grav": Vector3(0, -2.0, 0), "damp": 1.0, "add": false},
		"wisp": {"amount": 30, "life": 1.2, "color": Color(1.0, 0.95, 0.8, 1.0), "size": [0.08, 0.22],
			"vel": [0.5, 2.5], "spread": 180.0, "dir": Vector3.UP, "grav": Vector3(0, 2.5, 0), "damp": 1.0, "add": true},
		"ring_light": {"amount": 26, "life": 0.6, "color": Color(1.0, 0.95, 0.75, 1.0), "size": [0.06, 0.12],
			"vel": [4.0, 5.0], "spread": 90.0, "dir": Vector3.UP, "flat": true, "grav": Vector3.ZERO, "damp": 4.0, "add": true},
	}


func set_quality(q: int) -> void:
	_scale = [0.5, 0.8, 1.0][clampi(q, 0, 2)]


func burst(kind: String, pos: Vector3, color := Color(0, 0, 0, 0), scale := 1.0) -> void:
	if not _defs.has(kind) or not is_inside_tree():
		return
	var p := _take(kind)
	p.global_position = pos
	p.scale = Vector3.ONE * scale
	if color.a > 0.0:
		(p.process_material as ParticleProcessMaterial).color = color
	else:
		(p.process_material as ParticleProcessMaterial).color = _defs[kind]["color"]
	p.restart()
	p.emitting = true


func _take(kind: String) -> GPUParticles3D:
	var pool: Array = _pools.get(kind, [])
	for p in pool:
		if not p.emitting:
			return p
	var np := _make(kind)
	pool.append(np)
	_pools[kind] = pool
	return np


func _make(kind: String) -> GPUParticles3D:
	var d: Dictionary = _defs[kind]
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(4, int(d["amount"] * _scale))
	p.lifetime = d["life"]
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var m := ParticleProcessMaterial.new()
	m.direction = d["dir"]
	m.spread = d["spread"]
	if d.get("flat", false):
		m.direction = Vector3(1, 0, 0)
		m.spread = 180.0
		m.flatness = 1.0
	m.initial_velocity_min = d["vel"][0]
	m.initial_velocity_max = d["vel"][1]
	m.gravity = d["grav"]
	m.damping_min = d["damp"]
	m.damping_max = d["damp"]
	m.scale_min = d["size"][0]
	m.scale_max = d["size"][1]
	m.color = d["color"]
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, d.get("end_color", Color(1, 1, 1, 0)))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if d["add"] else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = DOT
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p
