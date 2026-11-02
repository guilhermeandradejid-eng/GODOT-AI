class_name SandFx
extends RefCounted
## Efeitos de areia do mundo: cascatas de areia (de bordas de platô e ruínas)
## e redemoinhos. Tudo barato para celular (1 malha + 1 sistema de partículas).

const SANDFALL_SHADER := preload("res://game/shaders/sandfall.gdshader")
const NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")
const SOFT := preload("res://addons/vibe_vfx/textures/soft_circle.webp")


## Cascata de areia: `top` é o ponto de onde a areia cai; a cortina olha para `facing` (graus).
static func sandfall(top: Vector3, height: float, width: float, facing_deg := 0.0, sun_color := Color(1.0, 0.85, 0.62)) -> Node3D:
	var root := Node3D.new()
	root.name = "CascataDeAreia"
	root.position = top
	root.rotation.y = deg_to_rad(facing_deg)
	var mat := ShaderMaterial.new()
	mat.shader = SANDFALL_SHADER
	mat.set_shader_parameter("noise_tex", NOISE)
	mat.set_shader_parameter("aspect", height / maxf(width, 0.5))
	mat.set_shader_parameter("sun_color", sun_color)
	for k in 2:
		# two crossed, slightly offset sheets give volume from any angle
		var q := QuadMesh.new()
		q.size = Vector2(width * (1.0 if k == 0 else 0.7), height)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, -height * 0.5, 0.25 * k)
		mi.rotation.y = 0.0 if k == 0 else deg_to_rad(70.0)
		root.add_child(mi)
	# dust cloud where it lands
	var p := GPUParticles3D.new()
	p.name = "Poeira"
	p.amount = 18
	p.lifetime = 2.4
	p.preprocess = 2.4
	p.position = Vector3(0, -height + 0.5, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = width * 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 2.5
	pm.scale_max = 5.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.88, 0.72, 0.0))
	grad.add_point(0.25, Color(1.0, 0.88, 0.72, 0.35))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 0.9, 0.78, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = SOFT
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-width * 2, -2, -width * 2), Vector3(width * 4, 10, width * 4))
	root.add_child(p)
	return root
