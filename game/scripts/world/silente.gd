class_name Silente
extends Node3D
## Inimigo "Silente": diabrete de vidro escuro em forma de ampulheta, com um
## olho âmbar — poeira que ganhou forma onde a areia parou. Vaga perto de casa e
## persegue heróis próximos. Vence-se pulando em cima, com o Rodopio, o Aríete
## ou a Barrigada. Ao ser vencido se desfaz em brilho e solta centelhas.
##
## Velado (itens.md, seção 5.7): fora da luz da lanterna é um vulto meio
## transparente, invulnerável ("tink") e que só vaga; dentro da luz fica exposto
## (opaco, olho aceso, persegue) e tem 2 PV. A rajada da Concha empurra e atordoa;
## o arpéu arrasta 3 m na direção do Sael.

signal defeated(who: Silente)
signal hit(who: Silente, dmg: int)      ## golpe local que tirou PV (a rede repassa)

## Dano por tipo de golpe (o maior entre este e o dmg enviado pelo herói).
const KIND_DMG := {"spin": 1, "staff1": 1, "staff2": 1, "staff3": 2, "staff_spin": 1, "stomp": 1,
	"bump": 2, "pound": 2, "wave": 2}
const VEIL_DISSOLVE := 0.55
const VEIL_HINT := "Os Silentes se escondem na névoa... uma luz os revelaria."

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
var hp := 1
var veiled := false
var _exposed := false
var _was_exposed := false
var _light_linger := 0.0
var _veil_v := 0.0                      ## dissolve atual do véu (0 exposto, 0,55 velado)
var stun_t := 0.0
var _push := Vector3.ZERO               ## empurrão horizontal (m/s), decai
var _lift := 0.0
var _lift_v := 0.0
var _retreat_t := 0.0
var _retreat_dir := Vector3.ZERO
var _drag_to := Vector3.ZERO
var _drag_t := 0.0
var _hit_frame := {}                    ## herói -> [quadro, dano] (um golpe por quadro)
var _hit_time := {}                     ## herói -> último golpe (s), para o contato
var _eye_mat: StandardMaterial3D
var _remote := false
var hook_mode := "enemy"
var hook_range := 12.0


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
	add_to_group(&"wind_listeners")
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
	_eye_mat = em
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
	if veiled:
		hp = maxi(hp, 2)
		_veil_v = VEIL_DISSOLVE
		_apply_veil()


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	_mat.set_shader_parameter("hurt", _hurt)
	_update_veil(delta)
	_lift_v -= 20.0 * delta
	_lift = maxf(0.0, _lift + _lift_v * delta)
	if _lift <= 0.0:
		_lift_v = 0.0
	if _drag_t > 0.0:
		_drag_t -= delta
		var dd := _drag_to - global_position
		dd.y = 0.0
		global_position += dd * minf(1.0, delta * 12.0)
	if _push.length() > 0.05:
		global_position += _push * delta
		_push = _push.move_toward(Vector3.ZERO, 16.0 * delta)
	if stun_t > 0.0:
		stun_t -= delta
		_stick_to_ground(delta)
		_body.position.y = _lift
		_body.rotation.z = sin(_t * 25.0) * 0.12 * minf(stun_t * 3.0, 1.0)
		_check_heroes()
		return
	_body.rotation.z = 0.0
	var nearest: Hero = null
	var nd := 7.5
	var can_chase := not veiled or _exposed
	for h in Game.heroes:
		if not can_chase:
			break
		if not is_instance_valid(h) or h.state == Hero.S.RIDE and h.mount == null:
			continue
		var d: float = h.global_position.distance_to(global_position)
		if d < nd and h.global_position.distance_to(home) < wander_radius + 9.0:
			nd = d
			nearest = h
	var spd := speed * (1.0 if can_chase else 0.6)
	if _retreat_t > 0.0:
		_retreat_t -= delta
		_target = global_position + _retreat_dir * 2.0
		spd = 3.0
	elif nearest != null:
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
	_stick_to_ground(delta)
	# little hops while moving (squishy)
	_hop = absf(sin(_t * (9.0 if nearest else 6.0)))
	_body.position.y = _hop * 0.12 * size + _lift
	_body.scale = Vector3(1.0 + (1.0 - _hop) * 0.1, 1.0 - (1.0 - _hop) * 0.12, 1.0 + (1.0 - _hop) * 0.1)
	_check_heroes()


func _stick_to_ground(delta: float) -> void:
	_ray.from = global_position + Vector3.UP * 3.0
	_ray.to = global_position + Vector3.DOWN * 6.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		global_position.y = lerpf(global_position.y, (hit["position"] as Vector3).y, 1.0 - exp(-12.0 * delta))


func _check_heroes() -> void:
	for h in Game.heroes:
		if not is_instance_valid(h) or h.is_remote:
			continue
		var d: Vector3 = h.global_position - global_position
		var flat := Vector2(d.x, d.z).length()
		if flat > 1.0 * size + 0.3:
			continue
		if d.y > 0.35 * size and h.velocity.y < 0.5 and h.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.POUND, Hero.S.LAUNCH]:
			# pisão (a Barrigada em cima vale como a onda)
			var pound: bool = h.state == Hero.S.POUND
			if is_vulnerable():
				_damage(h, 2 if pound else 1, "pound" if pound else "stomp")
			else:
				_tink(h)
			if not pound:
				h.bounce(10.5 if is_vulnerable() or dead else 8.0)
			return
		if absf(d.y) < 1.0 * size:
			if h.is_attacking():
				# contato durante o golpe: só se o golpe explícito ainda não contou
				if ToolPuzzles.now() - float(_hit_time.get(h, -10.0)) > 0.45:
					_damage(h, 2 if (h.state == Hero.S.POUND or h.hero_id == "strong") else 1, "contact")
			elif stun_t <= 0.0:
				h.take_hit(global_position)
			return


## Golpe do herói. dmg vem do herói (bastão 1/1/2); o tipo também dá o dano mínimo.
## Devolve true se acertou (inclusive o "tink" do velado) — o herói usa no Ricochete.
func on_attack(center: Vector3, radius: float, by, kind: String, dmg := 1) -> bool:
	if dead:
		return false
	if center.distance_to(global_position + Vector3.UP * 0.4) >= radius + 0.5 * size:
		return false
	_damage(by, maxi(dmg, int(KIND_DMG.get(kind, 1))), kind)
	return true


## Onda da Barrigada: dano 2.
func on_shockwave(pos: Vector3, radius: float, by) -> void:
	if dead:
		return
	if pos.distance_to(global_position) < radius:
		_damage(by, 2, "wave")


func is_vulnerable() -> bool:
	return not veiled or _exposed


func is_exposed() -> bool:
	return is_vulnerable()


func _damage(by, dmg: int, kind: String) -> bool:
	if dead:
		return false
	var key = by if by != null else self
	_hit_time[key] = ToolPuzzles.now()
	# um golpe por quadro e por herói (a Barrigada chega como onda e como golpe)
	var frame := Engine.get_physics_frames()
	var prev: Array = _hit_frame.get(key, [-1, 0])
	if prev[0] == frame:
		if dmg <= prev[1]:
			return true
		var extra: int = dmg - int(prev[1])
		_hit_frame[key] = [frame, dmg]
		dmg = extra
	else:
		_hit_frame[key] = [frame, dmg]
	if not is_vulnerable():
		_tink(by)
		return true
	if not _remote:
		hit.emit(self, dmg)
	hp -= dmg
	if hp <= 0:
		defeat(by)
		return true
	# sobreviveu (velado exposto com 2 PV): cambaleia e recua
	_hurt = 1.0
	stun_t = maxf(stun_t, 0.3)
	if by != null and is_instance_valid(by):
		var away: Vector3 = global_position - (by as Node3D).global_position
		away.y = 0.0
		_push = away.normalized() * 5.0 if away.length() > 0.01 else Vector3.ZERO
	Fx.burst("sparkle", global_position + Vector3.UP * 0.7, Color(1, 0.75, 0.45), 0.6)
	ToolPuzzles.sfx("crack", global_position, "enemy_poof", 1.3, -4.0)
	Game.vibrate(15)
	return true


## Golpe vindo da rede (`_enemy_hit`): aplica sem reemitir.
func apply_hit(dmg: int) -> void:
	_remote = true
	var was := veiled
	veiled = false
	_damage(null, dmg, "net")
	veiled = was
	_remote = false


## Velado e no escuro: "tink", o herói quica e o aviso aparece.
func _tink(by) -> void:
	ToolPuzzles.sfx("tink", global_position, "plate_off", 1.6, -2.0)
	Fx.burst("sparkle", global_position + Vector3.UP * 0.6, Color(0.6, 0.55, 0.9), 0.5)
	ToolPuzzles.toast_once(VEIL_HINT, 3.0, 20.0)
	if by != null and is_instance_valid(by) and by is Hero:
		var h := by as Hero
		var away: Vector3 = h.global_position - global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		if h.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.LAUNCH]:
			h.velocity = Vector3(away.x * 4.0, maxf(h.velocity.y, 6.0), away.z * 4.0)
		elif h.state == Hero.S.GROUND:
			h.velocity += away * 6.0


## Exposição pela luz da lanterna (com 0,3 s de folga para não piscar).
func _update_veil(delta: float) -> void:
	if not veiled:
		return
	if ToolPuzzles.in_light(global_position + Vector3.UP * 0.6):
		_light_linger = 0.3
	else:
		_light_linger -= delta
	var now := _light_linger > 0.0
	if now != _exposed:
		_exposed = now
		if now:
			Fx.burst("sparkle", global_position + Vector3.UP * 0.8, Color(1.0, 0.75, 0.4), 0.8)
			Sfx.play_at("reveal", global_position, 1.4, -6.0)
			if not _was_exposed:
				# 1ª exposição: atordoa 1,2 s e recua a 3 m/s por 0,5 s
				_was_exposed = true
				stun_t = maxf(stun_t, 1.2)
				_retreat_t = 0.5      # conta depois do atordoamento
				var away := global_position - ToolPuzzles.lantern_pos()
				away.y = 0.0
				_retreat_dir = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var goal := 0.0 if _exposed else VEIL_DISSOLVE
	if not is_equal_approx(_veil_v, goal):
		_veil_v = move_toward(_veil_v, goal, delta * 1.5)
		_apply_veil()


func _apply_veil() -> void:
	_mat.set_shader_parameter("dissolve", _veil_v)
	if _eye_mat != null:
		var k := 1.0 - _veil_v / VEIL_DISSOLVE
		_eye_mat.emission_energy_multiplier = 2.2 * k
		_eye_mat.albedo_color = Color(0.25, 0.2, 0.3).lerp(Color(1.0, 0.86, 0.55), k)


## Rajada da Concha (grupo "wind_listeners"): empurrão de 10 m/s + 2 para cima e
## atordoamento de 0,8 s, sem dano.
func on_gust(origin: Vector3, dir: Vector3, length := 10.0, half_angle := 25.0, _by = null) -> void:
	if dead or not ToolPuzzles.in_cone(origin, dir, global_position + Vector3.UP * 0.5, length, half_angle, 0.5 * size):
		return
	var f := Vector3(dir.x, 0, dir.z)
	if f.length() < 0.01:
		f = global_position - origin
		f.y = 0.0
	_push = f.normalized() * 10.0
	_lift_v = 2.0
	stun_t = maxf(stun_t, 0.8)
	Fx.burst("dust", global_position + Vector3.UP * 0.3, Color(1.0, 0.86, 0.66, 0.6), 0.8)


## Alvo do arpéu (o HeroTools varre o grupo "enemies").
func hook_point() -> Vector3:
	return global_position + Vector3.UP * 0.7 * size


func can_hook(_by = null) -> bool:
	return not dead


func on_hook(by) -> bool:
	return on_hook_pull(by)


## Puxão do arpéu: arrastado 3 m na direção do Sael e atordoado 0,6 s.
func on_hook_pull(by) -> bool:
	if dead or by == null or not is_instance_valid(by):
		return false
	var to: Vector3 = (by as Node3D).global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.01:
		return false
	_drag_to = global_position + to / d * minf(3.0, maxf(d - 1.2, 0.0))
	_drag_t = 0.3
	stun_t = maxf(stun_t, 0.6)
	Fx.burst("sparkle", hook_point(), Color(0.55, 1.0, 0.95), 0.5)
	return true


func defeat(by: Hero) -> void:
	if dead:
		return
	dead = true
	remove_from_group(&"enemies")
	remove_from_group(&"wind_listeners")
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
