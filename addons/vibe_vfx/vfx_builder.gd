@tool
extends RefCounted
## Turns VFX preset data into nodes (GPUParticles3D, lights, meshes) for a
## given art style:
##   realistic -> textured sprites (StandardMaterial3D, soft particles, lit smoke)
##   stylized  -> alpha-eroded painterly sprites (vibe_particle shader)
##   toon/cel  -> hard-edged, posterized sprites
##   lowpoly   -> flat-shaded low-poly mesh particles

const Library = preload("res://addons/vibe_vfx/vfx_library.gd")
const PARTICLE_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_particle.gdshader")
const PORTAL_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_portal.gdshader")
const SHOCKWAVE_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_shockwave.gdshader")
const FORCEFIELD_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_forcefield.gdshader")
const MAGIC_CIRCLE_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_magic_circle.gdshader")
const NOISE_PATH := "res://addons/vibe_vfx/textures/noise_fbm.webp"

const STYLE_PARAMS := {
	"stylized": {"edge_softness": 0.2, "erosion": 0.55, "posterize": 0.0, "fake_light": 0.55},
	"toon": {"edge_softness": 0.05, "erosion": 0.8, "posterize": 4.0, "fake_light": 0.8},
	"cel": {"edge_softness": 0.015, "erosion": 0.9, "posterize": 3.0, "fake_light": 1.0},
}

static var _tex_cache := {}
static var _mesh_cache := {}


static func texture(path: String) -> Texture2D:
	if _tex_cache.has(path) and is_instance_valid(_tex_cache[path]):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		# Fallback when textures were not imported yet (e.g. headless CLI on a fresh clone).
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		t = g
	_tex_cache[path] = t
	return t


static func _v3(v: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func _range(v: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is float or v is int:
		return Vector2(float(v), float(v))
	return fallback


## Shifts the hue of a color toward `target` (keeps value, blends saturation).
static func tint(c: Color, target: Color, ref_hue: float) -> Color:
	var h := fposmod(c.h + (target.h - ref_hue), 1.0)
	var s := lerpf(c.s, target.s, 0.5) if target.s > 0.05 else c.s * 0.15
	return Color.from_hsv(h, s, c.v, c.a)


static func _ref_hue(stops: Array) -> float:
	var best := 0.0
	var best_s := -1.0
	for st in stops:
		var c := Color.html(str(st[1]))
		if c.a > 0.3 and c.s > best_s:
			best_s = c.s
			best = c.h
	return best


static func _gradient(stops: Array, tint_color: Variant, ref_hue: float) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for st in stops:
		var c := Color.html(str(st[1]))
		if tint_color is Color:
			c = tint(c, tint_color, ref_hue)
		offsets.append(float(st[0]))
		colors.append(c)
	if offsets.is_empty():
		offsets = PackedFloat32Array([0.0, 1.0])
		colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	var max_v := 1.0
	for p in points:
		max_v = maxf(max_v, float(p[1]))
	c.max_value = max_v
	for p in points:
		c.add_point(Vector2(float(p[0]), float(p[1])))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Low-poly meshes with flat (per-face) normals.
static func lowpoly_mesh(kind: String) -> Mesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var m: Mesh
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = Vector3.ONE * 0.8
			m = b
		"prism":
			var p := PrismMesh.new()
			p.size = Vector3(0.8, 1.0, 0.8)
			m = p
		"quad":
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			m = q
		_:
			m = _icosahedron(0.55)
	_mesh_cache[kind] = m
	return m


static func _icosahedron(r: float) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for f in faces:
		var a: Vector3 = v[f[0]].normalized() * r
		var b: Vector3 = v[f[1]].normalized() * r
		var c: Vector3 = v[f[2]].normalized() * r
		var n := (b - a).cross(c - a).normalized()
		# Godot front faces are clockwise: emit a, c, b.
		verts.append_array([a, c, b])
		normals.append_array([n, n, n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Builds every node of a preset under `host`. opts: style, color (Color or null),
## scale, intensity, speed. Returns {"particles": [], "lights": [], "fx": []}.
static func build(host: Node3D, preset: Dictionary, opts: Dictionary) -> Dictionary:
	var style := str(opts.get("style", "realistic"))
	var scale := float(opts.get("scale", 1.0)) * float(preset.get("scale", 1.0))
	var intensity := float(opts.get("intensity", 1.0))
	var tint_color = opts.get("color", null)
	var out := {"particles": [], "lights": [], "fx": []}
	var base_offset := _v3(preset.get("base_offset", null)) * scale
	var ref_hue := 0.0
	var all_stops: Array = []
	for layer in preset.get("layers", []):
		all_stops.append_array(layer.get("color_ramp", []))
	ref_hue = _ref_hue(all_stops)
	for layer in preset.get("layers", []):
		var p := _build_emitter(layer, preset, style, scale, intensity, tint_color, ref_hue)
		p.position += base_offset
		p.speed_scale = float(opts.get("speed", 1.0))
		host.add_child(p, false, Node.INTERNAL_MODE_BACK)
		out.particles.append(p)
	var light_def = preset.get("light", null)
	if light_def is Dictionary:
		var l := OmniLight3D.new()
		var lc := Color.html(str(light_def.get("color", "#ffffff")))
		if tint_color is Color:
			lc = tint(lc, tint_color, ref_hue)
		l.light_color = lc
		l.light_energy = float(light_def.get("energy", 1.0))
		l.omni_range = float(light_def.get("range", 5.0)) * sqrt(scale)
		l.position = _v3(light_def.get("offset", null), Vector3(0, 0.5, 0)) * scale + base_offset
		l.shadow_enabled = false
		l.set_meta("base_energy", l.light_energy)
		l.set_meta("flicker", float(light_def.get("flicker", 0.0)))
		l.set_meta("decay", float(light_def.get("decay", 0.0)))
		host.add_child(l, false, Node.INTERNAL_MODE_BACK)
		out.lights.append(l)
	for fx in preset.get("mesh_fx", []):
		var node := _build_mesh_fx(str(fx), style, scale, tint_color, ref_hue)
		if node != null:
			host.add_child(node, false, Node.INTERNAL_MODE_BACK)
			out.fx.append(node)
	return out


static func _build_emitter(layer: Dictionary, preset: Dictionary, style: String, scale: float, intensity: float, tint_color: Variant, ref_hue: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = str(layer.get("name", "emitter")).capitalize().replace(" ", "")
	p.amount = maxi(1, int(round(float(layer.get("amount", 16)) * intensity)))
	p.lifetime = maxf(0.05, float(layer.get("lifetime", 1.0)))
	p.one_shot = bool(preset.get("one_shot", false))
	p.explosiveness = float(layer.get("explosiveness", 0.0))
	p.randomness = float(layer.get("randomness", 0.2))
	# Continuous effects start "warmed up" (full flame/smoke on the first frame).
	p.preprocess = float(layer.get("preprocess", 0.0 if p.one_shot else minf(p.lifetime, 3.0)))
	p.local_coords = bool(layer.get("local_coords", false))
	p.fixed_fps = 0
	p.position = _v3(layer.get("offset", null)) * scale
	var align := str(layer.get("align", "billboard"))
	var additive := str(layer.get("blend", "mix")) == "add"
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX if additive else GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	if align == "velocity" and style != "lowpoly":
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

	var pm := ParticleProcessMaterial.new()
	var shape := str(layer.get("shape", "point"))
	match shape:
		"sphere":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = float(layer.get("radius", 0.5)) * scale
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = _v3(layer.get("extents", null), Vector3.ONE * 0.5) * scale
		"ring", "disc":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			var r := float(layer.get("radius", 0.5)) * scale
			pm.emission_ring_radius = r
			pm.emission_ring_inner_radius = r * 0.92 if shape == "ring" else 0.0
			pm.emission_ring_height = 0.0
			pm.emission_ring_axis = _v3(layer.get("ring_axis", null), Vector3.UP)
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = _v3(layer.get("direction", null), Vector3.UP)
	pm.spread = float(layer.get("spread", 15.0))
	var vel := _range(layer.get("velocity", null), Vector2(1, 1)) * scale
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.gravity = _v3(layer.get("gravity", null), Vector3.ZERO) * scale
	var damp := _range(layer.get("damping", null))
	pm.damping_min = damp.x * scale
	pm.damping_max = damp.y * scale
	var ra := _range(layer.get("radial_accel", null))
	pm.radial_accel_min = ra.x * scale
	pm.radial_accel_max = ra.y * scale
	var ta := _range(layer.get("tangential_accel", null))
	pm.tangential_accel_min = ta.x * scale
	pm.tangential_accel_max = ta.y * scale
	var ang := _range(layer.get("angle", null))
	pm.angle_min = ang.x
	pm.angle_max = ang.y
	var spin := _range(layer.get("spin", null))
	pm.angular_velocity_min = spin.x
	pm.angular_velocity_max = spin.y
	var sc := _range(layer.get("scale", null), Vector2.ONE)
	pm.scale_min = sc.x * scale
	pm.scale_max = sc.y * scale
	if layer.has("scale_curve"):
		pm.scale_curve = _curve(layer.scale_curve)
	pm.color_ramp = _gradient(layer.get("color_ramp", []), tint_color, ref_hue)
	var hv := _range(layer.get("hue_variation", null))
	pm.hue_variation_min = hv.x
	pm.hue_variation_max = hv.y
	var turb = layer.get("turbulence", null)
	if turb is Dictionary:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(turb.get("strength", 1.0))
		pm.turbulence_noise_scale = float(turb.get("scale", 1.0)) * scale
		pm.turbulence_noise_speed = Vector3(0, float(turb.get("speed", 0.5)), 0)
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	var sprite: Dictionary = Library.SPRITES.get(str(layer.get("sprite", "soft_circle")), Library.SPRITES.soft_circle)
	var frames := int(sprite.get("frames", 1))
	if frames > 1:
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0
	p.process_material = pm

	var stretch := float(layer.get("stretch", 1.0))
	var emissive := float(layer.get("emissive", 1.0))
	var lit := bool(layer.get("lit", false))
	if style == "lowpoly":
		p.draw_pass_1 = lowpoly_mesh(str(layer.get("lowpoly_mesh", "sphere")))
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		if additive or emissive > 1.5:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(emissive, emissive, emissive) if emissive > 1.0 else Color.WHITE
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p.material_override = m
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, stretch) if align == "velocity" else Vector2.ONE
		p.draw_pass_1 = quad
		var tex := texture(str(sprite.path))
		if style == "realistic":
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.disable_receive_shadows = true
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if align == "velocity" else BaseMaterial3D.BILLBOARD_PARTICLES
			m.billboard_keep_scale = true
			m.particles_anim_h_frames = frames
			m.particles_anim_v_frames = frames
			m.particles_anim_loop = false
			if emissive > 1.0 and not lit:
				m.albedo_color = Color(emissive, emissive, emissive)
			if not additive:
				m.proximity_fade_enabled = true
				m.proximity_fade_distance = 0.6 * scale
			p.material_override = m
		else:
			var sp: Dictionary = STYLE_PARAMS.get(style, STYLE_PARAMS.stylized)
			var m := ShaderMaterial.new()
			m.shader = PARTICLE_SHADER
			m.set_shader_parameter("mask_tex", tex)
			m.set_shader_parameter("noise_tex", texture(NOISE_PATH))
			m.set_shader_parameter("frames", frames)
			m.set_shader_parameter("additive", 1.0 if additive else 0.0)
			m.set_shader_parameter("emission_strength", emissive if (additive or emissive > 1.0) else 1.0)
			m.set_shader_parameter("edge_softness", sp.edge_softness)
			m.set_shader_parameter("erosion", sp.erosion)
			m.set_shader_parameter("posterize", sp.posterize)
			m.set_shader_parameter("fake_light", sp.fake_light if lit else 0.0)
			m.set_shader_parameter("billboard", align != "velocity")
			p.material_override = m

	# Conservative culling box.
	var reach := (vel.y * p.lifetime + absf(pm.gravity.y) * p.lifetime * p.lifetime * 0.5) + sc.y * scale * 3.0
	var ext := _v3(layer.get("extents", null), Vector3.ONE * float(layer.get("radius", 0.5))) * scale
	var e := Vector3(ext.x + reach, ext.y + reach, ext.z + reach)
	p.visibility_aabb = AABB(-e, e * 2.0)
	return p


static func _material(color: Color, style: String, roughness: float = 0.9) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if style == "toon" or style == "cel":
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.rim_enabled = true
		m.rim = 0.4
	return m


static func _build_mesh_fx(kind: String, style: String, scale: float, tint_color: Variant, ref_hue: float) -> Node3D:
	var noise := texture(NOISE_PATH)
	var bands := 3.0 if style == "cel" else (4.0 if style == "toon" else 0.0)
	var low := style == "lowpoly"
	match kind:
		"campfire_base":
			var root := Node3D.new()
			root.name = "CampfireBase"
			var wood := _material(Color("#5a3a22"), style)
			var charred := _material(Color("#2a1c14"), style)
			for i in 3:
				var wood_log := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.07 * scale
				cyl.bottom_radius = 0.08 * scale
				cyl.height = 0.95 * scale
				cyl.radial_segments = 6 if low else 12
				cyl.rings = 1
				wood_log.mesh = cyl
				wood_log.material_override = wood if i != 1 else charred
				var a := TAU * i / 3.0
				wood_log.position = Vector3(cos(a) * 0.18, 0.2, sin(a) * 0.18) * scale
				wood_log.rotation = Vector3(0.0, -a, deg_to_rad(62.0))
				root.add_child(wood_log)
			var stone_mat := _material(Color("#6d6863"), style)
			for i in 9:
				var st := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.13 * scale
				sph.height = 0.16 * scale
				sph.radial_segments = 6 if low else 12
				sph.rings = 3 if low else 6
				st.mesh = sph
				st.material_override = stone_mat
				var a := TAU * i / 9.0
				st.position = Vector3(cos(a) * 0.62, 0.04, sin(a) * 0.62) * scale
				st.scale = Vector3(1.0 + 0.3 * sin(i * 2.3), 1.0, 1.0 + 0.2 * cos(i * 1.7))
				root.add_child(st)
			return root
		"torch_stick":
			var root := Node3D.new()
			root.name = "TorchStick"
			var stick := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.04 * scale / 0.45
			cyl.bottom_radius = 0.03 * scale / 0.45
			cyl.height = 1.4 * scale / 0.45
			cyl.radial_segments = 6 if low else 10
			stick.mesh = cyl
			stick.material_override = _material(Color("#4a3020"), style)
			stick.position = Vector3(0, cyl.height * 0.5, 0)
			root.add_child(stick)
			var cup := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.09 * scale / 0.45
			cone.bottom_radius = 0.045 * scale / 0.45
			cone.height = 0.14 * scale / 0.45
			cone.radial_segments = 6 if low else 12
			cup.mesh = cone
			cup.material_override = _material(Color("#3a3a3e"), style, 0.4)
			cup.position = Vector3(0, cyl.height - 0.02, 0)
			root.add_child(cup)
			return root
		"shockwave":
			var mi := MeshInstance3D.new()
			mi.name = "Shockwave"
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE * 9.0 * scale
			mi.mesh = plane
			var m := ShaderMaterial.new()
			m.shader = SHOCKWAVE_SHADER
			var c := Color("#ffcc88")
			if tint_color is Color:
				c = tint(c, tint_color, ref_hue)
			m.set_shader_parameter("color", c)
			m.set_shader_parameter("bands", bands)
			mi.material_override = m
			mi.position = Vector3(0, 0.08 * scale, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_meta("anim", "shockwave")
			return mi
		"portal":
			var root := Node3D.new()
			root.name = "Portal"
			var disc := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(3.4, 3.4) * scale
			disc.mesh = quad
			var m := ShaderMaterial.new()
			m.shader = PORTAL_SHADER
			m.set_shader_parameter("noise_tex", noise)
			var inner := Color("#9ff3ff")
			var outer := Color("#8a5cff")
			if tint_color is Color:
				inner = tint(inner, tint_color, ref_hue)
				outer = tint(outer, tint_color, ref_hue)
			m.set_shader_parameter("color_inner", inner)
			m.set_shader_parameter("color_outer", outer)
			m.set_shader_parameter("bands", bands)
			disc.material_override = m
			disc.position = Vector3(0, 1.9 * scale, 0)
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(disc)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 1.6 * scale
			torus.outer_radius = 1.95 * scale
			torus.rings = 12 if low else 48
			torus.ring_segments = 5 if low else 12
			ring.mesh = torus
			ring.material_override = _material(Color("#5d5a66"), style)
			ring.position = Vector3(0, 1.9 * scale, 0)
			ring.rotation_degrees = Vector3(90, 0, 0)
			root.add_child(ring)
			return root
		"force_field":
			var mi := MeshInstance3D.new()
			mi.name = "ForceField"
			var sph := SphereMesh.new()
			sph.radius = 2.0 * scale
			sph.height = 4.0 * scale
			sph.radial_segments = 16 if low else 48
			sph.rings = 8 if low else 24
			mi.mesh = sph
			var m := ShaderMaterial.new()
			m.shader = FORCEFIELD_SHADER
			m.set_shader_parameter("noise_tex", noise)
			var c := Color("#7fe8ff")
			if tint_color is Color:
				c = tint(c, tint_color, ref_hue)
			m.set_shader_parameter("color", c)
			m.set_shader_parameter("bands", bands)
			mi.material_override = m
			mi.position = Vector3(0, 1.0 * scale, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return mi
		"magic_circle":
			var mi := MeshInstance3D.new()
			mi.name = "MagicCircle"
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE * 2.6 * scale
			mi.mesh = plane
			var m := ShaderMaterial.new()
			m.shader = MAGIC_CIRCLE_SHADER
			var c := Color("#9a5cff")
			if tint_color is Color:
				c = tint(c, tint_color, ref_hue)
			m.set_shader_parameter("color", c)
			m.set_shader_parameter("bands", bands)
			mi.material_override = m
			mi.position = Vector3(0, 0.03, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return mi
		"lightning":
			var mi := MeshInstance3D.new()
			mi.name = "Lightning"
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(3.0, 3.4, 4.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			mi.set_meta("anim", "lightning")
			mi.set_meta("scale", scale)
			return mi
	return null


## Random jagged bolt from the sky to the ground (two crossed ribbons).
static func lightning_mesh(height: float, width: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var pts: Array = [Vector3(rng.randf_range(-6, 6), height, rng.randf_range(-6, 6))]
	var steps := 18
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var prev: Vector3 = pts[i - 1]
		pts.append(Vector3(prev.x * 0.85 + rng.randf_range(-2.5, 2.5), height * (1.0 - t), prev.z * 0.85 + rng.randf_range(-2.5, 2.5)))
	var verts := PackedVector3Array()
	for side in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var w := width * (1.0 - float(i) / pts.size() * 0.5)
			verts.append_array([a - side * w, a + side * w, b + side * w, a - side * w, b + side * w, b - side * w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
