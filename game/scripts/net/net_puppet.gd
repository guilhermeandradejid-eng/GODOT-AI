class_name NetPuppet
extends RefCounted
## Controlador do herói remoto: interpola a posição recebida pela rede (com uma
## pequena extrapolação pela velocidade) e repassa estado/animação.
## Itens: `tool_bits` (1 lanterna acesa, 2 erguida, 4 corda) e `rope_to` fazem o
## par desenhar a corda e a luz da lanterna (e, no cliente, alimentam
## `Game.lantern_pos`, para os Silentes velados e os sinos `dark` verem a luz).

const LAMP_COLOR := Color(1.0, 0.706, 0.353)   # #FFB45A

var target_pos := Vector3.ZERO
var target_vel := Vector3.ZERO
var target_facing := 0.0
var state := 0
var vis := "loco"
var tool_bits := 0
var rope_to := Vector3.ZERO
var _age := 0.0
var _has := false
var _t := 0.0
var _lamp: OmniLight3D
var _rope: MeshInstance3D
var _lamp_was := false


func push(pos: Vector3, vel: Vector3, facing: float, st: int, v: String, bits := 0, rope := Vector3.ZERO) -> void:
	target_pos = pos
	target_vel = vel
	target_facing = facing
	state = st
	vis = v
	tool_bits = bits
	rope_to = rope
	_age = 0.0
	_has = true


func poll(intent: PlayerInput, me: Hero, delta: float) -> void:
	intent.clear()
	if not _has:
		return
	_age += delta
	var predicted := target_pos + target_vel * minf(_age, 0.15)
	if me.global_position.distance_to(predicted) > 6.0:
		me.teleport(predicted)
	else:
		me.global_position = me.global_position.lerp(predicted, 1.0 - exp(-14.0 * delta))
	me.velocity = target_vel
	me.facing = lerp_angle(me.facing, target_facing, 1.0 - exp(-14.0 * delta))
	me.state = state
	if me.visual != null and vis != me.visual.state:
		me.visual.set_state(vis)
	_apply_tools(me, delta)


## Luz e corda do par remoto. Se o HeroTools souber se desenhar a partir do
## estado de rede (`apply_net_state`), ele cuida; senão a marionete desenha.
func _apply_tools(me: Hero, delta: float) -> void:
	_t += delta
	var lit := tool_bits & 1 != 0
	var raised := tool_bits & 2 != 0
	var tools = me.get("tools")
	var own := not (tools != null and tools.has_method("apply_net_state"))
	if not own:
		tools.apply_net_state(tool_bits, rope_to)
	var lamp_p := _lamp_point(me, raised)
	# os Silentes e sinos deste aparelho consultam Game.lantern_pos
	if "lantern_pos" in Game:
		if lit:
			Game.set("lantern_pos", lamp_p)
			Game.set("lantern_radius", 9.0 if raised else 7.0)
		elif _lamp_was:
			Game.set("lantern_pos", Vector3.INF)
	_lamp_was = lit
	if not own:
		return
	# lanterna: OmniLight sem sombra, cintila ±6% a 3 Hz, mais forte com as horas
	if lit:
		if not is_instance_valid(_lamp):
			_lamp = OmniLight3D.new()
			_lamp.light_color = LAMP_COLOR
			_lamp.omni_attenuation = 1.2
			_lamp.shadow_enabled = false
			_lamp.top_level = true
			me.add_child(_lamp)
		_lamp.visible = true
		_lamp.global_position = lamp_p
		_lamp.omni_range = (9.0 if raised else 7.0) + 2.0
		var hours := float(Game.relics.size())
		_lamp.light_energy = 1.8 * (1.0 + 0.6 * hours / 3.0) * (1.0 + 0.06 * sin(_t * TAU * 3.0))
	elif is_instance_valid(_lamp):
		_lamp.visible = false
	# corda
	if tool_bits & 4 != 0 and rope_to != Vector3.ZERO:
		if not is_instance_valid(_rope):
			_rope = MeshInstance3D.new()
			_rope.top_level = true
			_rope.mesh = ImmediateMesh.new()
			_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(0.62, 0.3, 0.22)
			m.emission_enabled = true
			m.emission = Color(0.31, 0.89, 0.84)
			m.emission_energy_multiplier = 0.4
			_rope.material_override = m
			me.add_child(_rope)
		_rope.visible = true
		_rope.global_transform = Transform3D.IDENTITY
		CompanionAI.rope_strip(_rope.mesh as ImmediateMesh, _hand_point(me), rope_to)
	elif is_instance_valid(_rope):
		_rope.visible = false


## Onde fica a lanterna: osso `grip_L` (acesa na mão) se existir; senão perto
## do quadril. Erguida (Farol no cesto) fica mais alta.
func _lamp_point(me: Hero, raised: bool) -> Vector3:
	var p := _bone_point(me, "grip_L")
	if p == Vector3.INF:
		p = me.global_position + Vector3.UP * 0.9
	return p + Vector3.UP * (0.5 if raised else 0.0)


func _hand_point(me: Hero) -> Vector3:
	var p := _bone_point(me, "grip_R")
	return p if p != Vector3.INF else me.global_position + Vector3.UP * 1.0


func _bone_point(me: Hero, bone: String) -> Vector3:
	if me.visual == null or me.visual.skeleton == null:
		return Vector3.INF
	var sk: Skeleton3D = me.visual.skeleton
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.INF
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin


## Some com a luz e a corda (o par saiu da rede).
func release() -> void:
	_has = false
	if _lamp_was and "lantern_pos" in Game:
		Game.set("lantern_pos", Vector3.INF)
	_lamp_was = false
	tool_bits = 0
	if is_instance_valid(_lamp):
		_lamp.queue_free()
	if is_instance_valid(_rope):
		_rope.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_lamp):
			_lamp.queue_free()
		if is_instance_valid(_rope):
			_rope.queue_free()
