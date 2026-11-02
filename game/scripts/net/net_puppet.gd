class_name NetPuppet
extends RefCounted
## Controlador do herói remoto: interpola a posição recebida pela rede (com uma
## pequena extrapolação pela velocidade) e repassa estado/animação.

var target_pos := Vector3.ZERO
var target_vel := Vector3.ZERO
var target_facing := 0.0
var state := 0
var vis := "loco"
var _age := 0.0
var _has := false


func push(pos: Vector3, vel: Vector3, facing: float, st: int, v: String) -> void:
	target_pos = pos
	target_vel = vel
	target_facing = facing
	state = st
	vis = v
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
