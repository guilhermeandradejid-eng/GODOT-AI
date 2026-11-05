class_name SandFx
extends RefCounted
## Efeitos de areia do mundo: cascatas de areia (de bordas de platô e ruínas)
## e redemoinhos. Tudo barato para celular (1 malha + 1 sistema de partículas).
## Uma cascata com `veil` é um Véu de Areia: a rajada da Concha a abre em V a
## partir do topo por `part_time` s (itens.md, seção 5.8).

const SANDFALL_SHADER := preload("res://game/shaders/sandfall.gdshader")
const NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")
const SOFT := preload("res://addons/vibe_vfx/textures/soft_circle.webp")


## Cascata de areia: `top` é o ponto de onde a areia cai; a cortina olha para `facing` (graus).
## Com `veil`, a cortina principal é feita de duas metades que se abrem (Sandfall.part).
static func sandfall(top: Vector3, height: float, width: float, facing_deg := 0.0, sun_color := Color(1.0, 0.85, 0.62),
		sun_dir := Vector3(-0.45, 0.36, -0.82), veil := false, part_time := 6.0) -> Node3D:
	var root := Sandfall.new()
	root.name = "CascataDeAreia"
	root.veil = veil
	root.part_time = part_time
	root.height = height
	root.width = width
	root.position = top
	root.rotation.y = deg_to_rad(facing_deg)
	var mat := ShaderMaterial.new()
	mat.shader = SANDFALL_SHADER
	mat.set_shader_parameter("noise_tex", NOISE)
	mat.set_shader_parameter("aspect", height / maxf(width, 0.5))
	mat.set_shader_parameter("sun_color", sun_color)
	mat.set_shader_parameter("sun_dir", sun_dir.normalized())
	root.material = mat
	for k in 2:
		if veil and k == 0:
			# main sheet split in two halves (continuous UVs) that lean apart when parted
			for side in [-1, 1]:
				var half := MeshInstance3D.new()
				half.mesh = _half_sheet(width, height, side)
				half.material_override = mat
				half.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				half.position = Vector3(0, -height, 0)
				root.add_child(half)
				root.halves.append(half)
			continue
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
		if k == 1:
			root.cross = mi
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
	root.dust = p
	return root


## Metade da cortina (side -1 = esquerda, +1 = direita) com a base em y = 0 e o topo
## em y = height; UV contínuo com a outra metade (o shader usa UV.y 0 no topo).
static func _half_sheet(width: float, height: float, side: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := 0.0 if side > 0 else -width * 0.5
	var x1 := width * 0.5 if side > 0 else 0.0
	var u0 := 0.5 if side > 0 else 0.0
	var u1 := u0 + 0.5
	var quad := [[Vector3(x0, height, 0), Vector2(u0, 0)], [Vector3(x1, height, 0), Vector2(u1, 0)],
		[Vector3(x1, 0, 0), Vector2(u1, 1)], [Vector3(x0, 0, 0), Vector2(u0, 1)]]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(quad[i][1])
		st.add_vertex(quad[i][0])
	return st.commit()


# ============================================================================ nó da cascata / véu
class Sandfall extends Node3D:
	## Nó de uma cascata. Com veil entra em "wind_listeners" e "sand_veils": a rajada
	## da Concha a até 10 m do topo abre a cortina em V por part_time s (as partículas
	## param) e ela fecha em 1,0 s.
	signal parted
	signal closed
	signal event_fired(kind: String)
	const OPEN_TIME := 0.45
	const CLOSE_TIME := 1.0
	var veil := false
	var veil_id := -1                   ## índice na lista sandfalls da receita
	var part_time := 6.0
	var height := 20.0
	var width := 6.0
	var material: ShaderMaterial
	var halves: Array[MeshInstance3D] = []
	var cross: MeshInstance3D
	var dust: GPUParticles3D
	var _open_left := 0.0
	var _amount := 0.0                  ## 0 fechada, 1 aberta
	var _remote := false

	func _ready() -> void:
		add_to_group(&"sandfalls")
		if veil:
			add_to_group(&"wind_listeners")
			add_to_group(&"sand_veils")
			add_to_group(&"puzzle_nodes")
		set_process(veil)

	## Aberta o bastante para puxar/pegar a relíquia de dentro.
	func is_open() -> bool:
		return veil and _amount > 0.5

	## Abre por `t` s (part_time por padrão).
	func part(t := -1.0) -> void:
		if not veil:
			return
		var was_open := _open_left > 0.0
		_open_left = part_time if t < 0.0 else t
		if was_open:
			return
		Sfx.play_at("veil_part" if Sfx.has("veil_part") else "whoosh", global_position)
		Fx.burst("dust", global_position, Color(1.0, 0.86, 0.66, 0.6), 1.6)
		parted.emit()
		if not _remote:
			event_fired.emit("parted")

	func close() -> void:
		_open_left = 0.0

	## Ponto para a mira automática da rajada (meio do topo da cortina).
	func gust_point() -> Vector3:
		return global_position + Vector3.DOWN * 0.5

	func net_event(kind: String) -> void:
		apply_event(kind)

	## Evento vindo da rede ("parted").
	func apply_event(kind: String) -> void:
		if kind == "parted":
			_remote = true
			part()
			_remote = false

	## Rajada da Concha (grupo "wind_listeners"): o topo precisa estar a até `length` m
	## e a cortina dentro do cone (com folga de meia largura).
	func on_gust(origin: Vector3, dir: Vector3, length := 10.0, half_angle := 25.0, _by = null) -> void:
		if not veil or origin.distance_to(global_position) > length:
			return
		for k in 4:
			var p := global_position + Vector3.DOWN * (height * 0.15 * k)
			if ToolPuzzles.in_cone(origin, dir, p, length + 2.0, half_angle, width * 0.5):
				part()
				return

	func _process(delta: float) -> void:
		var target := 0.0
		if _open_left > 0.0:
			_open_left -= delta
			target = 1.0
			if _open_left <= 0.0:
				Sfx.play_at("veil_close" if Sfx.has("veil_close") else "whoosh", global_position, 0.8)
				closed.emit()
		var prev := _amount
		_amount = move_toward(_amount, target, delta / (OPEN_TIME if target > _amount else CLOSE_TIME))
		if is_equal_approx(prev, _amount) and prev in [0.0, 1.0]:
			return
		var e := _amount * _amount * (3.0 - 2.0 * _amount)
		# V a partir do topo: cada metade inclina para fora (cisalhamento com base fixa)
		var g := (width * 0.5 + 0.6) * e
		for i in halves.size():
			var side := -1.0 if i == 0 else 1.0
			halves[i].transform.basis = Basis(Vector3.RIGHT, Vector3(side * g / maxf(height, 0.1), 1.0, 0.0), Vector3.BACK)
		if cross != null:
			cross.scale = Vector3(maxf(1.0 - e, 0.02), 1.0, 1.0)
			cross.visible = e < 0.98
		if material != null:
			material.set_shader_parameter("density", lerpf(0.85, 0.3, e))
		if dust != null:
			dust.emitting = _amount < 0.05
