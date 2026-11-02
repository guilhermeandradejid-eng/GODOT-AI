class_name Silente
extends Node3D
## Inimigo "Silente": diabrete de vidro escuro em forma de ampulheta, com um
## olho âmbar — poeira que ganhou forma onde a areia parou. Vaga perto de casa e
## persegue heróis próximos. Vence-se pulando em cima, com o Rodopio, o Aríete
## ou a Barrigada. Ao ser vencido se desfaz em brilho e solta centelhas.

signal defeated(who: Silente)

const SHADER := preload("res://game/shaders/silente.gdshader")

var home := Vector3.ZERO
var wander_radius := 6.0
var speed := 2.6
var chase_speed := 3.6
var size := 1.0
var dead := false
var _target := Vector3.ZERO
var _t := 0.0
var _retarget := 0.0
var _mat: ShaderMaterial
var _body: MeshInstance3D
var _eyes: Node3D
var _hurt := 0.0
var _ray: PhysicsRayQueryParameters3D
var _hop := 0.0


## Ampulheta de vidro escuro (torno): dois bulbos unidos por uma cintura fina.
static func _hourglass_mesh(sz: float) -> ArrayMesh:
	var prof := [Vector2(0.0, 0.0), Vector2(0.30, 0.04), Vector2(0.43, 0.18), Vector2(0.41, 0.34),
		Vector2(0.24, 0.48), Vector2(0.13, 0.57), Vector2(0.22, 0.66), Vector2(0.40, 0.80),
		Vector2(0.45, 0.96), Vector2(0.35, 1.10), Vector2(0.17, 1.19), Vector2(0.0, 1.22)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 18
	for i in prof.size() - 1:
		var a: Vector2 = prof[i] * sz
		var b: Vector2 = prof[i + 1] * sz
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
	st.generate_normals()
	return st.commit()


func _ready() -> void:
	add_to_group(&"enemies")
	home = global_position
	_target = home
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_body = MeshInstance3D.new()
	_body.mesh = _hourglass_mesh(size)
	_body.material_override = _mat
	add_child(_body)
	# one amber eye in the upper bulb
	_eyes = Node3D.new()
	_eyes.position = Vector3(0, 0.93 * size, 0.33 * size)
	add_child(_eyes)
	var e := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 0.15 * size
	es.height = 0.24 * size
	es.radial_segments = 12
	es.rings = 6
	e.mesh = es
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.0, 0.86, 0.55)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.62, 0.22)
	em.emission_energy_multiplier = 2.2
	e.material_override = em
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes.add_child(e)
	var pmesh := MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = 0.05 * size
	ps.height = 0.2 * size
	ps.radial_segments = 8
	ps.rings = 4
	pmesh.mesh = ps
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.12, 0.05, 0.12)
	pmesh.material_override = pm
	pmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmesh.position = Vector3(0, 0, 0.11 * size)
	_eyes.add_child(pmesh)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	_mat.set_shader_parameter("hurt", _hurt)
	var nearest: Hero = null
	var nd := 7.5
	for h in Game.heroes:
		if not is_instance_valid(h) or h.state == Hero.S.RIDE and h.mount == null:
			continue
		var d: float = h.global_position.distance_to(global_position)
		if d < nd and h.global_position.distance_to(home) < wander_radius + 9.0:
			nd = d
			nearest = h
	var spd := speed
	if nearest != null:
		_target = nearest.global_position
		spd = chase_speed
	else:
		_retarget -= delta
		if _retarget <= 0.0 or global_position.distance_to(_target) < 0.6:
			var a := randf() * TAU
			_target = home + Vector3(cos(a), 0, sin(a)) * randf() * wander_radius
			_retarget = randf_range(2.0, 4.5)
	var to := _target - global_position
	to.y = 0.0
	if to.length() > 0.3:
		var step := to.normalized() * spd * delta
		global_position += step
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-6.0 * delta))
	# stick to the ground
	_ray.from = global_position + Vector3.UP * 3.0
	_ray.to = global_position + Vector3.DOWN * 6.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		global_position.y = lerpf(global_position.y, (hit["position"] as Vector3).y, 1.0 - exp(-12.0 * delta))
	# little hops while moving (squishy)
	_hop = absf(sin(_t * (9.0 if nearest else 6.0)))
	_body.position.y = _hop * 0.12 * size
	_body.scale = Vector3(1.0 + (1.0 - _hop) * 0.1, 1.0 - (1.0 - _hop) * 0.12, 1.0 + (1.0 - _hop) * 0.1)
	_check_heroes()


func _check_heroes() -> void:
	for h in Game.heroes:
		if not is_instance_valid(h) or h.is_remote:
			continue
		var d: Vector3 = h.global_position - global_position
		var flat := Vector2(d.x, d.z).length()
		if flat > 1.0 * size + 0.3:
			continue
		if d.y > 0.35 * size and h.velocity.y < 0.5 and h.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.POUND, Hero.S.LAUNCH]:
			defeat(h)
			if h.state != Hero.S.POUND:
				h.bounce(10.5)
			return
		if absf(d.y) < 1.0 * size:
			if h.is_attacking():
				defeat(h)
			else:
				h.take_hit(global_position)
			return


func on_attack(center: Vector3, radius: float, by: Hero, _kind: String) -> void:
	if dead:
		return
	if center.distance_to(global_position + Vector3.UP * 0.4) < radius + 0.5 * size:
		defeat(by)


func on_shockwave(pos: Vector3, radius: float, by: Hero) -> void:
	if dead:
		return
	if pos.distance_to(global_position) < radius:
		defeat(by)


func defeat(by: Hero) -> void:
	if dead:
		return
	dead = true
	remove_from_group(&"enemies")
	_eyes.visible = false
	Fx.burst("poof", global_position + Vector3.UP * 0.5)
	Fx.burst("sparkle", global_position + Vector3.UP * 0.6, Color(1, 0.9, 0.6), 1.0)
	Sfx.play_at("enemy_poof", global_position, randf_range(0.9, 1.1))
	Game.vibrate(30)
	var tw := create_tween()
	tw.tween_method(func(v: float): _mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.6)
	tw.tween_callback(queue_free)
	defeated.emit(self)
	var field := get_tree().get_first_node_in_group(&"motes")
	if field != null:
		field.spawn_burst(global_position, 5)
