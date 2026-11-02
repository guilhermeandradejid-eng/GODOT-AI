class_name Decor
extends RefCounted
## Decoração viva do mundo (sem física): bandeirinhas, pipas, cata-ventos,
## capim, partículas de luz, feixes de sol, nuvens fofas e águas-vivas gigantes.

const FLAG_SHADER := preload("res://game/shaders/flag.gdshader")
const FLAG_ATLAS := preload("res://game/assets/textures/bandeirinhas.png")
const DOT := preload("res://game/assets/textures/soft_dot.png")
const NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")

static var _flag_mat: ShaderMaterial


static func flag_material() -> ShaderMaterial:
	if _flag_mat == null:
		_flag_mat = ShaderMaterial.new()
		_flag_mat.shader = FLAG_SHADER
		_flag_mat.set_shader_parameter("atlas", FLAG_ATLAS)
	return _flag_mat


# ============================================================================ bandeirinhas
static func flag_string(a: Vector3, b: Vector3, sag := 0.8, spacing := 0.55) -> Node3D:
	var root := Node3D.new()
	root.name = "Bandeirinhas"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := a.distance_to(b)
	var n := maxi(2, int(L / spacing))
	var palette := [Color(1, 1, 1), Color(1, 0.95, 0.9), Color(0.95, 1, 1), Color(1, 1, 0.92)]
	var side := (b - a).cross(Vector3.UP).normalized()
	for i in n:
		var t0 := (i + 0.15) / n
		var t1 := (i + 0.85) / n
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var h := 0.42
		var mid := (p0 + p1) * 0.5
		var tip := mid + Vector3.DOWN * h * 0.7
		var q0 := p0 + Vector3.DOWN * h
		var q1 := p1 + Vector3.DOWN * h
		var u0 := float(i % 4) * 0.25
		var u1 := u0 + 0.25
		var c: Color = palette[i % palette.size()]
		var s := float(i) * spacing
		# flag with a V notch: (p0, p1, q1, tip, q0)
		var verts := [p0, p1, q1, p0, q1, tip, p0, tip, q0]
		var uvs := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 0), Vector2(u1, 1),
			Vector2((u0 + u1) * 0.5, 0.7), Vector2(u0, 0), Vector2((u0 + u1) * 0.5, 0.7), Vector2(u0, 1)]
		for k in verts.size():
			var v: Vector3 = verts[k]
			var w := clampf((p0.y - v.y) / h, 0.0, 1.0)
			st.set_color(Color(c.r, c.g, c.b, w))
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(s, 0))
			st.set_normal(side)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = flag_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# cord
	var cord := MeshInstance3D.new()
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := 24
	for i in m:
		var t0 := float(i) / m
		var t1 := float(i + 1) / m
		var c0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var c1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var up := Vector3.UP * 0.02
		cst.add_vertex(c0 - up); cst.add_vertex(c1 - up); cst.add_vertex(c1 + up)
		cst.add_vertex(c0 - up); cst.add_vertex(c1 + up); cst.add_vertex(c0 + up)
	cord.mesh = cst.commit()
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.35, 0.25, 0.25)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cord.material_override = cm
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cord)
	return root


static func pole(pos: Vector3, height := 3.2) -> Node3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.08
	cyl.height = height
	cyl.radial_segments = 8
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.44, 0.32)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3.UP * height * 0.5
	return mi


# ============================================================================ pipa (kite)
class Kite extends Node3D:
	var anchor := Vector3.ZERO
	var height := 18.0
	var drift_dir := Vector3(0.8, 0, 0.45)
	var colors: Array = [Color(0.95, 0.2, 0.3), Color(1.0, 0.82, 0.2), Color(0.12, 0.5, 0.95), Color(1, 1, 1)]
	var _kite: MeshInstance3D
	var _line: MeshInstance3D
	var _tail: MeshInstance3D
	var _t := 0.0
	var wind := 1.0

	func _ready() -> void:
		_t = randf() * 10.0
		_kite = MeshInstance3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := Vector3(0, 0.75, 0)
		var right := Vector3(0.62, 0.1, 0)
		var bottom := Vector3(0, -0.65, 0)
		var left := Vector3(-0.62, 0.1, 0)
		var mid := Vector3(0, 0.1, -0.08)
		var quads := [[top, right], [right, bottom], [bottom, left], [left, top]]
		for i in 4:
			st.set_color(colors[i])
			st.add_vertex(mid)
			st.add_vertex(quads[i][0])
			st.add_vertex(quads[i][1])
		st.generate_normals()
		_kite.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 0.5
		_kite.material_override = m
		_kite.scale = Vector3.ONE * 1.6
		_kite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_kite)
		_line = MeshInstance3D.new()
		_line.mesh = ImmediateMesh.new()
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1, 1, 1, 0.55)
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_line.material_override = lm
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_line)
		_tail = MeshInstance3D.new()
		_tail.mesh = ImmediateMesh.new()
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.vertex_color_use_as_albedo = true
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tail.material_override = tm
		_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_tail)
		var stake := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.06
		cyl.height = 0.8
		stake.mesh = cyl
		stake.position = Vector3.UP * 0.4
		stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(stake)

	func _process(delta: float) -> void:
		_t += delta * wind
		var base := anchor + drift_dir.normalized() * height * 0.55 + Vector3.UP * height
		var sway := Vector3(sin(_t * 0.7) * 2.5, sin(_t * 1.1) * 1.2, cos(_t * 0.5) * 2.0) * wind
		var kp := base + sway
		_kite.global_position = kp
		_kite.look_at(anchor, Vector3.UP)
		_kite.rotate_object_local(Vector3.FORWARD, sin(_t * 1.7) * 0.35)
		var lm := _line.mesh as ImmediateMesh
		lm.clear_surfaces()
		lm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 13:
			var t := float(i) / 12.0
			var p := anchor.lerp(kp, t) + Vector3.DOWN * sin(t * PI) * 1.4
			lm.surface_add_vertex(to_local(p))
		lm.surface_end()
		var tm := _tail.mesh as ImmediateMesh
		tm.clear_surfaces()
		tm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var down := (kp - anchor).normalized() * -1.0
		var bottom := kp + _kite.global_transform.basis.y * -1.05
		for i in 10:
			var p := bottom + Vector3.DOWN * i * 0.32 + drift_dir.normalized() * -i * 0.12 + Vector3(sin(_t * 5.0 - i * 0.6), 0, cos(_t * 4.0 - i * 0.5)) * 0.12 * i
			var c: Color = colors[i % 3]
			var w := 0.12
			var lp := to_local(p)
			tm.surface_set_color(c)
			tm.surface_add_vertex(lp + Vector3(-w, 0.06, 0))
			tm.surface_add_vertex(lp)
			tm.surface_add_vertex(lp + Vector3(-w, -0.06, 0))
			tm.surface_add_vertex(lp + Vector3(w, 0.06, 0))
			tm.surface_add_vertex(lp + Vector3(w, -0.06, 0))
			tm.surface_add_vertex(lp)
		tm.surface_end()


# ============================================================================ cata-vento
class Pinwheel extends Node3D:
	var spin := 3.0
	var big := 1.0
	var _blades: Node3D

	func _ready() -> void:
		var p := PropLib.make("pinwheel")
		p.scale = Vector3.ONE * big
		add_child(p)
		if big < 2.0:
			for m in PropLib.meshes(p):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blades = p.find_child("blades", true, false)

	func _process(delta: float) -> void:
		if _blades != null:
			_blades.rotate_object_local(Vector3.UP, spin * delta)


# ============================================================================ capim nas lagoas
static func grass_field(island_mesh: MeshInstance3D, max_count: int, seed_v: int) -> MultiMeshInstance3D:
	var mesh := island_mesh.mesh
	if mesh == null or not (mesh is ArrayMesh):
		return null
	var arrays := mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_COLOR] == null or arrays[Mesh.ARRAY_INDEX] == null:
		return null
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if cols.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var xforms: Array[Transform3D] = []
	var tris := idx.size() / 3
	for tri in tris:
		var i0 := idx[tri * 3]
		var i1 := idx[tri * 3 + 1]
		var i2 := idx[tri * 3 + 2]
		var g := (cols[i0].a + cols[i1].a + cols[i2].a) / 3.0
		if g < 0.3:
			continue
		var a := verts[i0]
		var b := verts[i1]
		var c := verts[i2]
		var area := (b - a).cross(c - a).length() * 0.5
		var expected := area * g * 1.6
		var n := int(expected) + (1 if rng.randf() < fmod(expected, 1.0) else 0)
		for k in n:
			var r1 := sqrt(rng.randf())
			var r2 := rng.randf()
			var p := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4) * (0.6 + g * 0.6))
			xforms.append(Transform3D(basis, p))
	if xforms.is_empty():
		return null
	xforms.shuffle()
	if xforms.size() > max_count:
		xforms.resize(max_count)
	var grass_scene := PropLib.make("grass")
	var gm: MeshInstance3D = PropLib.meshes(grass_scene)[0]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = gm.mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Capim"
	mmi.multimesh = mm
	mmi.material_override = PropLib.shared_material("grass")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 90.0
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	grass_scene.free()
	return mmi


# ============================================================================ partículas de luz no ar
static func light_motes(amount := 140) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "LuzesNoAr"
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -15, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 8, 28)
	pm.direction = Vector3(0.3, 1, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.05, 0.08, 0.02)
	pm.turbulence_enabled = false
	pm.scale_min = 0.025
	pm.scale_max = 0.07
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.3, 1))
	curve.add_point(Vector2(0.7, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color = Color(1.0, 0.92, 0.7, 0.9)
	p.process_material = pm
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = DOT
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.4, 1.0, 0.8)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# ============================================================================ feixes de sol (god rays)
static func sun_beam(pos: Vector3, sun_dir: Vector3, length := 70.0, width := 5.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "FeixeDeLuz"
	var q := QuadMesh.new()
	q.size = Vector2(width, length)
	mi.mesh = q
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.86, 0.62);
uniform float strength = 0.11;
uniform float seed = 0.0;
void vertex() {
	// billboard around the beam axis (local Y)
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(axis, to_cam));
	vec3 w = center + side * VERTEX.x * length(MODEL_MATRIX[0].xyz) + axis * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float shimmer = 0.75 + 0.25 * sin(TIME * 0.6 + seed + UV.y * 3.0);
	float a = pow(across, 2.2) * smoothstep(0.0, 0.25, along) * smoothstep(1.0, 0.55, along);
	ALBEDO = color * a * strength * shimmer;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("seed", randf() * 10.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# local Y axis along the sun direction, the beam's lower end at pos
	var y := (Vector3(sun_dir.x * 0.45, 0.0, sun_dir.z * 0.45) + Vector3.UP).normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length() < 0.1:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), pos + y * length * 0.5)
	mi.extra_cull_margin = 40.0
	return mi


# ============================================================================ nuvens fofas
static func cloud_puffs(points: Array, sizes: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * float(sizes[i])), points[i]))
		mm.set_instance_custom_data(i, Color(randf(), randf(), 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "NuvensFofas"
	mi.multimesh = mm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 lit : source_color = vec3(1.0, 0.9, 0.84);
uniform vec3 shade : source_color = vec3(0.86, 0.68, 0.84);
uniform vec3 sun_dir = vec3(-0.42, 0.27, -0.87);
varying vec2 v_rand;
varying vec3 v_center;
void vertex() {
	v_rand = INSTANCE_CUSTOM.xy;
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_center = center;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = center + (right * VERTEX.x + up * VERTEX.y * 0.6) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p * vec2(1.0, 1.25));
	float n = texture(noise_tex, UV * 0.6 + v_rand + TIME * 0.004).r;
	float body = smoothstep(1.0, 0.2, r + (n - 0.5) * 0.7);
	float lit_k = clamp(0.5 + 0.5 * dot(normalize(vec3(p.x, -p.y + 0.3, 0.5)), normalize(vec3(sun_dir.x, sun_dir.y, 0.3))), 0.0, 1.0);
	ALBEDO = mix(shade, lit, lit_k * 0.8 + n * 0.2);
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vp = INV_PROJECTION_MATRIX * ndc;
	vp.xyz /= vp.w;
	float soft = clamp((-vp.z - -VERTEX.z) / 6.0, 0.0, 1.0);
	ALPHA = body * 0.8 * soft;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", NOISE)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aabb := AABB(points[0], Vector3.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	mi.custom_aabb = aabb.grow(60.0)
	return mi


# ============================================================================ águas-vivas gigantes ao longe
class GiantJelly extends Node3D:
	var path_radius := 30.0
	var speed := 0.03
	var center := Vector3.ZERO
	var _t := 0.0
	var _v: Node3D

	func _ready() -> void:
		_t = randf() * TAU
		_v = PropLib.make("jelly", ["jelly"])
		add_child(_v)
		var m: ShaderMaterial = (_v.get_meta("materials") as Dictionary)["jelly"]
		m.set_shader_parameter("pulse_speed", 0.7)
		m.set_shader_parameter("glow", 2.0)
		m.set_shader_parameter("alpha_base", 0.35)
		m.set_shader_parameter("phase", randf() * 6.0)

	func _process(delta: float) -> void:
		_t += delta * speed
		global_position = center + Vector3(cos(_t) * path_radius, sin(_t * 3.0) * 3.0, sin(_t) * path_radius)
		rotation.z = sin(_t * 2.0) * 0.12
