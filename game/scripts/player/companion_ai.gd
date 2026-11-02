class_name CompanionAI
extends RefCounted
## Companheiro controlado pela IA (quando só há um jogador). Segue o líder sem
## grudar, pula obstáculos e buracos, plana (ágil), sobe na carona quando
## chamado, ocupa a placa de pressão livre quando o líder está na outra e, se
## ficar para trás ou cair, reaparece perto do líder como um rastro de luz.

var leader: Hero
var follow_dist := 2.4
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _repath_t := 0.0
var _jump_cd := 0.0
var _plate_target = null
var _idle_t := 0.0


func _init(l: Hero) -> void:
	leader = l


func poll(intent: PlayerInput, me: Hero, delta: float) -> void:
	intent.move = Vector2.ZERO
	intent.jump = false
	intent.action = false
	if leader == null or not is_instance_valid(leader):
		return
	_jump_cd = maxf(0.0, _jump_cd - delta)
	if me.state == Hero.S.RIDE:
		# rider: stays put; jumps off if the leader launches far away
		return
	var target := leader.global_position
	# help with pressure plates: go to the free partner plate
	_plate_target = _find_plate(me)
	if _plate_target != null:
		target = _plate_target.global_position
	var to := target - me.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	# teleport if too far / fell / leader on another island
	if dist > 26.0 or to.y > 8.0 or (me.global_position.y < leader.global_position.y - 12.0):
		_warp(me)
		return
	var want := follow_dist if _plate_target == null else 0.15
	if dist > want:
		var dir := flat / dist
		var speed01 := clampf((dist - want) / 4.0, 0.25, 1.0)
		var cam_basis := Basis(Vector3.UP, me.cam_yaw)
		var local := cam_basis.inverse() * (dir * speed01)
		intent.move = Vector2(local.x, local.z)
		_idle_t = 0.0
	else:
		_idle_t += delta
	# obstacles & gaps
	if intent.move.length() > 0.1 and me.state == Hero.S.GROUND and _jump_cd <= 0.0:
		var fwd := Vector3(sin(me.facing), 0, cos(me.facing))
		var space := me.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3.UP * 0.35,
				me.global_position + Vector3.UP * 0.35 + fwd * 0.9, Hero.LAYER_WORLD)
		var wall := space.intersect_ray(q)
		var ahead := me.global_position + fwd * 1.4 + Vector3.UP * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 3.5, Hero.LAYER_WORLD)
		var ground := space.intersect_ray(q2)
		var leader_higher := to.y > 1.2 and dist < 6.0
		if not wall.is_empty() or ground.is_empty() or leader_higher:
			intent.press("jump")
			intent.jump = true
			_jump_cd = 0.6
	if me.state in [Hero.S.AIR, Hero.S.GLIDE]:
		intent.jump = me.velocity.y > 0.0 or (me.hero_id == "agile" and me.global_position.y > target.y + 0.5 and dist > 3.0)
		if me.hero_id == "agile" and me.state == Hero.S.AIR and me.velocity.y < -2.0 and dist > 3.0 and me.air_jumps > 0:
			intent.press("jump")
	# stuck detection
	if intent.move.length() > 0.3:
		if me.global_position.distance_to(_last_pos) < 0.02:
			_stuck_t += delta
		else:
			_stuck_t = 0.0
		if _stuck_t > 1.6:
			_warp(me)
	_last_pos = me.global_position
	# idle agile hops on strong if the leader is strong and standing still for a while
	if me.hero_id == "agile" and leader.hero_id == "strong" and leader.rider == null and _idle_t > 6.0 \
			and leader.velocity.length() < 0.2 and dist < 2.6:
		_idle_t = 0.0
		me.mount_on(leader)


func _find_plate(me: Hero):
	var plates := me.get_tree().get_nodes_in_group(&"plates")
	var leader_plate = null
	for p in plates:
		if p.has_method("occupied_by") and p.occupied_by(leader):
			leader_plate = p
			break
	if leader_plate == null:
		return null
	var best = null
	var bd := 18.0
	for p in plates:
		if p == leader_plate or p.group_id != leader_plate.group_id:
			continue
		if p.heavy and not me.is_heavy():
			continue
		var d: float = p.global_position.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = p
	return best


func _warp(me: Hero) -> void:
	_stuck_t = 0.0
	var back := -Vector3(sin(leader.facing), 0, cos(leader.facing)) * 1.8 + Vector3(0.8, 0, 0)
	var p := leader.global_position + back + Vector3.UP * 1.2
	Fx.burst("wisp", me.global_position + Vector3.UP * 0.5)
	me.teleport(p, leader.facing)
	me.set_state(Hero.S.AIR)
	Fx.burst("wisp", p)
