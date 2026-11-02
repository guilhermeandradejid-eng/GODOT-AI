class_name Hero
extends CharacterBody3D
## Herói jogável. Movimento de plataforma com aceleração, coyote time, buffer
## de pulo, pulo variável, gravidade mais forte na queda, inclinação nas curvas,
## squash & stretch e surfe nas dunas. Papéis (nomes/aparência em HeroDefs):
##   agile  – pulo duplo, planar, giro, subir no parceiro, ser lançada.
##   strong – pancada no chão (onda de choque), investida, placas pesadas,
##            carregar a parceira e lançá-la como um canhão.

signal jumped(kind: String)
signal landed(impact: float)
signal hurt_taken(petals_left: int)
signal respawned

enum S { GROUND, AIR, GLIDE, POUND, RIDE, LAUNCH, GRIND, SWIM, HURT, CUTSCENE, SURF }

const CONFIG := {
	"agile": {"speed": 8.2, "accel": 46.0, "decel": 58.0, "air_accel": 22.0, "turn": 13.0, "jump": 11.6,
		"jump2": 10.4, "gravity": 30.0, "fall_mult": 1.6, "low_jump": 2.1, "max_fall": 26.0,
		"glide_fall": 2.3, "glide_speed": 9.2, "swim_speed": 3.6, "radius": 0.28, "height": 0.95,
		"surf_max": 21.0, "surf_grip": 2.7,
		"walk_v": 2.0, "run_v": 7.5},
	"strong": {"speed": 7.0, "accel": 34.0, "decel": 46.0, "air_accel": 14.0, "turn": 9.0, "jump": 10.4,
		"jump2": 0.0, "gravity": 32.0, "fall_mult": 1.7, "low_jump": 2.0, "max_fall": 30.0,
		"pound_speed": 28.0, "swim_speed": 6.0, "radius": 0.4, "height": 0.85,
		"surf_max": 18.5, "surf_grip": 1.9,
		"walk_v": 1.8, "run_v": 6.5},
}
const LAYER_WORLD := 1
const LAYER_HEROES := 2
const LAYER_WATER := 8

@export var hero_id := "agile"

var intent := PlayerInput.new()
var controller: Object = null          ## InputSources | CompanionAI | NetPuppet
var player_index := -1                 ## 0/1 humanos locais, -1 IA/remoto
var is_remote := false
var cfg: Dictionary
var visual: HeroVisual
var shape: CollisionShape3D
var cam_yaw := 0.0
var state := S.AIR
var facing := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var air_jumps := 1
var air_spin := true
var action_t := 0.0
var invuln := 0.0
var state_t := 0.0
var petals := 3
var mount: Hero = null
var rider: Hero = null
var updraft := 0.0
var grind = null
var grind_offset := 0.0
var water_surface := -INF
var spawn_offset := Vector3.ZERO
var _lean := Vector2.ZERO
var _squash := 1.0
var _squash_v := 0.0
var _was_floor := false
var _fall_speed := 0.0
var _step_t := 0.0
var _turn_rate := 0.0
var _prev_facing := 0.0
var _trail_prev := Vector3.ZERO
var _water_q: PhysicsPointQueryParameters3D


func _ready() -> void:
	cfg = CONFIG[hero_id]
	add_to_group(&"heroes")
	collision_layer = LAYER_HEROES
	collision_mask = LAYER_WORLD
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	safe_margin = 0.02
	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = cfg["radius"]
	cap.height = cfg["height"]
	shape.shape = cap
	shape.position.y = cfg["height"] * 0.5
	add_child(shape)
	visual = HeroVisual.new()
	visual.hero = hero_id
	visual.name = "Visual"
	add_child(visual)
	_water_q = PhysicsPointQueryParameters3D.new()
	_water_q.collide_with_areas = true
	_water_q.collide_with_bodies = false
	_water_q.collision_mask = LAYER_WATER


# =================================================================== physics
func _physics_process(delta: float) -> void:
	if controller != null:
		if controller is InputSources:
			(controller as InputSources).poll(intent)
		elif controller.has_method("poll"):
			controller.poll(intent, self, delta)
	if is_remote:
		_update_visual(delta)
		return
	state_t += delta
	invuln = maxf(0.0, invuln - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	if intent.take("jump"):
		jump_buffer = 0.14
	_check_water()
	match state:
		S.GROUND: _st_ground(delta)
		S.AIR: _st_air(delta)
		S.GLIDE: _st_glide(delta)
		S.POUND: _st_pound(delta)
		S.RIDE: _st_ride(delta)
		S.LAUNCH: _st_launch(delta)
		S.GRIND: _st_grind(delta)
		S.SWIM: _st_swim(delta)
		S.HURT: _st_hurt(delta)
		S.CUTSCENE: _st_cutscene(delta)
		S.SURF: _st_surf(delta)
	updraft = 0.0
	if Game.level != null and global_position.y < Game.level.kill_y:
		respawn()
	_world_bounds()
	_sand_trail()
	_update_visual(delta)


## Mundo contínuo: atrás das dunas altas da borda, uma parede invisível macia
## (a colisão do terreno termina na borda do mapa).
func _world_bounds() -> void:
	if Game.level == null or Game.level.get("builder") == null or Game.level.builder.terrain == null:
		return
	var lim: float = Game.level.builder.terrain.half - 14.0
	var p := global_position
	if absf(p.x) > lim:
		global_position.x = signf(p.x) * lim
		if signf(velocity.x) == signf(p.x):
			velocity.x = 0.0
	if absf(p.z) > lim:
		global_position.z = signf(p.z) * lim
		if signf(velocity.z) == signf(p.z):
			velocity.z = 0.0


## Sulco contínuo na areia atrás do herói (fino andando, largo surfando).
func _sand_trail() -> void:
	var p := global_position
	var grounded := (state == S.GROUND and is_on_floor()) or state == S.SURF
	if grounded and _trail_prev.distance_squared_to(p) < 9.0 and _trail_prev.distance_squared_to(p) > 0.0004:
		var big := hero_id != "agile"
		var r := (0.55 if big else 0.4) if state == S.SURF else (0.26 if big else 0.17)
		var st := 0.2 if state == S.SURF else (0.14 if big else 0.11)
		get_tree().call_group(&"sand_trails", &"stroke", _trail_prev, p, r, st)
	_trail_prev = p


func wish_dir() -> Vector3:
	var m := intent.move
	return Vector3(m.x, 0.0, m.y).rotated(Vector3.UP, cam_yaw)


func set_state(s: int) -> void:
	if s == state:
		return
	if state == S.SURF:
		Sfx.loop("surf", false)
	state = s
	state_t = 0.0


# ------------------------------------------------------------------- ground
func _horizontal(delta: float, accel: float, decel: float, speed: float, turn: float, keep_momentum := false) -> void:
	var wish := wish_dir()
	var hv := Vector2(velocity.x, velocity.z)
	if keep_momentum and hv.length() > speed + 0.5:
		# airborne after surfing: steer the momentum, let it decay slowly
		var mag := maxf(speed, hv.length() - 3.0 * delta)
		var dir := hv.normalized()
		if wish.length() > 0.08:
			dir = dir.slerp(Vector2(wish.x, wish.z).normalized(), clampf(1.6 * delta, 0.0, 1.0))
		hv = dir * mag
		velocity.x = hv.x
		velocity.z = hv.y
		facing = rotate_toward(facing, atan2(hv.x, hv.y), turn * delta)
		return
	var tv := Vector2(wish.x, wish.z) * speed
	var a := accel if tv.length() > 0.05 else decel
	# turning hard at speed costs momentum (skid) – reads as weight
	if tv.length() > 0.1 and hv.length() > 3.0 and hv.normalized().dot(tv.normalized()) < -0.3:
		a *= 1.6
	hv = hv.move_toward(tv, a * delta)
	velocity.x = hv.x
	velocity.z = hv.y
	if wish.length() > 0.08:
		var target := atan2(wish.x, wish.z)
		facing = rotate_toward(facing, target, turn * delta)


func _st_ground(delta: float) -> void:
	coyote = 0.12
	air_jumps = 1
	air_spin = true
	action_t = maxf(0.0, action_t - delta)
	_horizontal(delta, cfg["accel"], cfg["decel"], cfg["speed"] * (1.25 if action_t > 0.0 and hero_id == "strong" else 1.0), cfg["turn"])
	velocity.y = -2.0
	if jump_buffer > 0.0:
		_jump(cfg["jump"], "jump")
		return
	if intent.take("action"):
		_action_ground()
	if intent.take("special"):
		_special()
		if state != S.GROUND:
			return
	move_and_slide()
	if _check_bounce():
		return
	if not is_on_floor():
		set_state(S.AIR)
	else:
		_footsteps(delta)
		_maybe_surf()


## Encosta de areia íngreme + descendo rápido = começa a surfar (como no Journey).
func _maybe_surf() -> void:
	var n := get_floor_normal()
	if n.y > 0.96:
		return
	var downhill := Vector3(n.x, 0.0, n.z).normalized()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var slope := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
	if (slope > 17.0 and hv.dot(downhill) > 3.6) or (slope > 27.0 and hv.dot(downhill) > 1.0):
		set_state(S.SURF)
		Sfx.play_at("surf_start", global_position, randf_range(0.95, 1.05))


func _st_surf(delta: float) -> void:
	action_t = maxf(0.0, action_t - delta)
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	var slope_sin := sqrt(maxf(0.0, 1.0 - n.y * n.y))
	var downhill := Vector3(n.x, 0.0, n.z)
	if downhill.length() > 0.001:
		downhill = downhill.normalized()
	var v := Vector3(velocity.x, 0.0, velocity.z)
	v += downhill * cfg["gravity"] * slope_sin * 0.78 * delta
	var wish := wish_dir()
	if wish.length() > 0.1 and v.length() > 0.5:
		var ang := v.normalized().signed_angle_to(wish.normalized(), Vector3.UP)
		v = v.rotated(Vector3.UP, clampf(ang, -1.0, 1.0) * cfg["surf_grip"] * delta)
		# carving into the turn bleeds a little speed (feels grounded)
		v *= 1.0 - absf(clampf(ang, -1.0, 1.0)) * 0.25 * delta
	var drag := 0.08 if slope_sin > 0.22 else 0.9
	v *= 1.0 - drag * delta
	v = v.limit_length(cfg["surf_max"])
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -6.0
	if v.length() > 0.5:
		facing = rotate_toward(facing, atan2(v.x, v.z), 9.0 * delta)
	if jump_buffer > 0.0:
		var keep := v
		_jump(cfg["jump"] * 1.05, "jump")
		velocity.x = keep.x
		velocity.z = keep.z
		return
	if intent.take("action"):
		_action_ground()
	_fall_speed = velocity.y
	move_and_slide()
	if not is_on_floor():
		# launched off a crest: keep the momentum in the air
		set_state(S.AIR)
		visual.set_state("fall", 0.2)
		return
	var sp := v.length()
	if sp < 4.0 and slope_sin < 0.3 or (sp < 2.5):
		set_state(S.GROUND)
		visual.set_state("loco", 0.25)
		return
	# sand spray, groove in the sand, sliding sound
	if Engine.get_physics_frames() % 5 == 0:
		Fx.burst("dust", global_position - v.normalized() * 0.4 + Vector3.UP * 0.1, Color(1.0, 0.86, 0.66, 0.5), 0.5 + sp / 20.0)
	Sfx.loop("surf", true, global_position, -14.0 + sp * 0.4)


func _footsteps(delta: float) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp < 1.0:
		_step_t = 0.0
		return
	_step_t -= delta * sp
	if _step_t <= 0.0:
		_step_t = 1.6 if hero_id == "agile" else 1.4
		Fx.burst("dust", global_position + Vector3(0, 0.05, 0), Color(0, 0, 0, 0), 0.6 if hero_id == "agile" else 0.9)
		Sfx.play_at("step", global_position, randf_range(0.9, 1.15), -12.0)


# ------------------------------------------------------------------- air
func _st_air(delta: float) -> void:
	coyote = maxf(0.0, coyote - delta)
	action_t = maxf(0.0, action_t - delta)
	var g: float = cfg["gravity"]
	if velocity.y < 0.0:
		g *= cfg["fall_mult"]
	elif not intent.jump:
		g *= cfg["low_jump"]
	if absf(velocity.y) < 2.5 and intent.jump:
		g *= 0.55
	velocity.y = maxf(velocity.y - g * delta, -cfg["max_fall"])
	velocity.y += updraft * delta * 0.35
	_horizontal(delta, cfg["air_accel"], cfg["air_accel"] * 0.35, cfg["speed"], cfg["turn"] * 0.7, true)
	if jump_buffer > 0.0:
		if coyote > 0.0:
			_jump(cfg["jump"], "jump")
			return
		if hero_id == "agile":
			if air_jumps > 0:
				air_jumps -= 1
				_jump(cfg["jump2"], "double")
				return
			jump_buffer = 0.0
			set_state(S.GLIDE)
			return
	if hero_id == "agile" and intent.jump and air_jumps == 0 and velocity.y < -1.0 and state_t > 0.12:
		set_state(S.GLIDE)
		return
	if intent.take("action"):
		_action_air()
		if state != S.AIR:
			return
	if intent.take("special"):
		_special()
		if state != S.AIR:
			return
	_fall_speed = velocity.y
	move_and_slide()
	if _check_bounce():
		return
	if is_on_floor():
		_land()


func _jump(v: float, kind: String) -> void:
	velocity.y = v
	jump_buffer = 0.0
	coyote = 0.0
	set_state(S.AIR)
	_squash_v = 5.0 if kind == "jump" else 3.0
	_squash = 1.18
	if kind == "double":
		visual.restart_state("double_jump")
		Fx.burst("ring_light", global_position + Vector3(0, 0.3, 0), Color(1, 0.9, 0.6), 0.7)
		Sfx.play_at("jump2", global_position)
	else:
		visual.restart_state("jump")
		Fx.burst("dust", global_position, Color(0, 0, 0, 0), 0.8)
		Sfx.play_at("jump_" + hero_id, global_position, randf_range(0.95, 1.08))
	jumped.emit(kind)


func _land() -> void:
	var impact := clampf(-_fall_speed / 20.0, 0.0, 1.0)
	set_state(S.GROUND)
	_squash = 1.0 - 0.28 * impact - 0.06
	_squash_v = 0.0
	visual.restart_state("land")
	if impact > 0.25:
		Fx.burst("dust_ring", global_position + Vector3(0, 0.05, 0), Color(0, 0, 0, 0), 0.5 + impact * 0.7)
		Sfx.play_at("land", global_position, 1.1 - impact * 0.3, -6.0 + impact * 4.0)
		if impact > 0.6 and player_index >= 0:
			Game.vibrate(25)
	landed.emit(impact)
	_back_to_loco_later(0.18)


func _back_to_loco_later(t: float) -> void:
	var st := state_t
	await get_tree().create_timer(t, false).timeout
	if state == S.GROUND and visual.state in ["land", "jump"]:
		visual.set_state("loco")


func _check_bounce() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if col is Node and (col as Node).is_in_group(&"bouncy") and c.get_normal().y > 0.55:
			var power: float = col.get_meta("bounce", 15.0)
			if col.has_method("on_bounced"):
				col.on_bounced(self)
			bounce(power)
			return true
	return false


func bounce(power: float) -> void:
	velocity.y = power
	air_jumps = 1
	air_spin = true
	set_state(S.AIR)
	_squash = 1.25
	_squash_v = 4.0
	visual.restart_state("jump" if hero_id == "strong" else "double_jump")
	Sfx.play_at("bounce", global_position, randf_range(0.95, 1.1))


# ------------------------------------------------------------------- glide (agile)
func _st_glide(delta: float) -> void:
	var target_fall: float = -cfg["glide_fall"]
	if updraft > 0.0:
		velocity.y = move_toward(velocity.y, minf(9.0, updraft * 0.6), updraft * delta)
	else:
		velocity.y = move_toward(velocity.y, target_fall, 22.0 * delta)
	var wish := wish_dir()
	var hv := Vector2(velocity.x, velocity.z)
	var fwd := Vector2(sin(facing), cos(facing))
	var tv: Vector2
	if wish.length() > 0.1:
		tv = Vector2(wish.x, wish.z).normalized() * cfg["glide_speed"] * maxf(0.55, wish.length())
		facing = rotate_toward(facing, atan2(wish.x, wish.z), cfg["turn"] * 0.42 * delta)
	else:
		tv = fwd * maxf(hv.length() * 0.98, 3.0)
	hv = hv.move_toward(tv, 12.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.y
	if not intent.jump or intent.take("jump"):
		set_state(S.AIR)
		return
	if intent.take("action"):
		set_state(S.AIR)
		_action_air()
		return
	_fall_speed = velocity.y
	move_and_slide()
	if _check_bounce():
		return
	if is_on_floor():
		_land()


# ------------------------------------------------------------------- actions
func _action_ground() -> void:
	if hero_id == "agile":
		_spin()
	else:
		# investida: arrancada curta que derruba inimigos e quebra coisas
		action_t = 0.28
		visual.restart_state("ram")
		var f := Vector3(sin(facing), 0, cos(facing))
		velocity.x = f.x * 11.0
		velocity.z = f.z * 11.0
		Fx.burst("dust", global_position, Color(0, 0, 0, 0), 1.0)
		Sfx.play_at("bump", global_position)
		_attack(global_position + f * 0.6 + Vector3.UP * 0.4, 1.1, "bump")


func _action_air() -> void:
	if hero_id == "agile":
		if air_spin:
			air_spin = false
			velocity.y = maxf(velocity.y, 5.0)
		_spin()
	else:
		set_state(S.POUND)
		velocity = Vector3.ZERO
		visual.restart_state("flop")
		Sfx.play_at("whoosh", global_position, 0.8)


func _spin() -> void:
	action_t = 0.4
	visual.restart_state("spin")
	Sfx.play_at("spin", global_position, randf_range(0.95, 1.1))
	_attack(global_position + Vector3.UP * 0.5, 1.45, "spin")


func _attack(center: Vector3, radius: float, kind: String) -> void:
	get_tree().call_group(&"enemies", &"on_attack", center, radius, self, kind)
	get_tree().call_group(&"breakable", &"on_attack", center, radius, self, kind)


func _st_pound(delta: float) -> void:
	if state_t < 0.14:
		velocity = Vector3(0, 1.5, 0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = -cfg["pound_speed"]
	move_and_slide()
	if is_on_floor() or (state_t > 0.14 and get_slide_collision_count() > 0 and get_floor_normal().y > 0.3):
		_pound_impact()


func _pound_impact() -> void:
	var p := global_position
	Fx.burst("dust_ring", p + Vector3(0, 0.1, 0), Color(0, 0, 0, 0), 2.0)
	Fx.burst("dust", p, Color(0, 0, 0, 0), 2.0)
	Sfx.play_at("pound", p)
	Game.vibrate(45)
	get_tree().call_group(&"cameras", &"shake", 0.55)
	get_tree().call_group(&"enemies", &"on_shockwave", p, 3.4, self)
	get_tree().call_group(&"pound_listeners", &"on_pound", p, self)
	_attack(p + Vector3.UP * 0.3, 2.2, "pound")
	velocity.y = 6.0
	set_state(S.AIR)
	_squash = 0.62
	_squash_v = 0.0


# ------------------------------------------------------------------- team-up
func _special() -> void:
	if hero_id == "agile":
		var strong := Game.hero("strong") as Hero
		if strong != null and strong.rider == null and strong.state in [S.GROUND, S.SWIM] \
				and global_position.distance_to(strong.global_position) < 2.4:
			mount_on(strong)
	else:
		if rider != null:
			catapult()
		else:
			var agile := Game.hero("agile") as Hero
			if agile != null and agile.player_index < 0 and agile.global_position.distance_to(global_position) < 9.0:
				agile.call_deferred("mount_on", self)
				Sfx.play_at("call", global_position)


func mount_on(strong: Hero) -> void:
	if strong == null or strong.rider != null:
		return
	mount = strong
	strong.rider = self
	shape.disabled = true
	set_state(S.RIDE)
	visual.set_state("ride", 0.2)
	Sfx.play_at("mount", global_position)
	Fx.burst("sparkle", global_position + Vector3.UP * 0.6, Color(1, 0.9, 0.6), 0.6)


func dismount(push := Vector3.ZERO) -> void:
	if mount != null:
		mount.rider = null
	mount = null
	shape.disabled = false
	velocity = push
	air_jumps = 1
	air_spin = true
	set_state(S.AIR)
	visual.restart_state("jump")


func catapult() -> void:
	if rider == null:
		return
	var r := rider
	var f := Vector3(sin(facing), 0, cos(facing))
	var v := f * 9.5 + Vector3.UP * 15.0
	if r.is_remote:
		var net := get_tree().root.get_node_or_null("Rede")
		if net != null:
			net.request_catapult(v)
		rider = null
	else:
		r.dismount(v)
		r.set_state(S.LAUNCH)
		r.visual.restart_state("double_jump")
	Sfx.play_at("launch", global_position)
	Fx.burst("petals", global_position + Vector3.UP * 0.8, Color(1, 0.8, 0.4), 0.8)


func saddle_transform() -> Transform3D:
	var t := global_transform
	var yaw_basis := Basis(Vector3.UP, facing)
	var bob := 0.0
	if visual != null and visual.skeleton != null:
		var bi := visual.skeleton.find_bone("spine")
		if bi >= 0:
			var gp := visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bi)
			bob = gp.origin.y - global_position.y - 0.45
	return Transform3D(yaw_basis, t.origin + Vector3.UP * (0.36 + bob) + yaw_basis * Vector3(0, 0, -0.06))


func _st_ride(delta: float) -> void:
	if mount == null or not is_instance_valid(mount):
		dismount()
		return
	var st := mount.saddle_transform()
	global_position = st.origin
	facing = mount.facing
	velocity = mount.velocity
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		var push := mount.velocity * 0.6
		push.y = 16.5
		dismount(push)
		visual.restart_state("double_jump")
		Fx.burst("ring_light", global_position + Vector3(0, 0.2, 0), Color(1, 0.85, 0.5), 1.0)
		Sfx.play_at("superjump", global_position)
		jumped.emit("super")
		return
	if intent.take("special"):
		dismount(Vector3(sin(facing), 0, cos(facing)) * -2.0 + Vector3.UP * 6.0)
		return
	if intent.take("action"):
		_spin()
		visual.set_state("ride")


# ------------------------------------------------------------------- launch / grind
func launch(v: Vector3, lock := 0.35) -> void:
	if state == S.RIDE:
		dismount()
	global_position += Vector3.UP * 0.2
	velocity = v
	set_state(S.LAUNCH)
	state_t = -lock
	air_jumps = 1
	air_spin = true
	visual.restart_state("double_jump" if hero_id == "agile" else "jump")
	if v.x != 0.0 or v.z != 0.0:
		facing = atan2(v.x, v.z)


func _st_launch(delta: float) -> void:
	velocity.y -= cfg["gravity"] * delta
	_fall_speed = velocity.y
	move_and_slide()
	if state_t > 0.0 and velocity.y < 0.0:
		set_state(S.AIR)
		visual.set_state("fall")
		return
	if state_t > 0.05 and is_on_floor():
		_land()


func start_grind(ribbon, offset: float) -> void:
	if state == S.GRIND or state == S.RIDE:
		return
	grind = ribbon
	grind_offset = offset
	set_state(S.GRIND)
	visual.set_state("glide" if hero_id == "agile" else "fall", 0.12)
	Sfx.play_at("grind_start", global_position)


func _st_grind(delta: float) -> void:
	if grind == null:
		set_state(S.AIR)
		return
	var speed: float = grind.speed
	grind_offset += speed * delta
	var length: float = grind.length()
	if grind_offset >= length:
		var exit_v: Vector3 = grind.tangent_at(length) * speed + Vector3.UP * 7.0
		grind = null
		launch(exit_v, 0.2)
		return
	var xf: Transform3D = grind.transform_at(grind_offset)
	global_position = xf.origin + Vector3.UP * 0.15
	var tan: Vector3 = grind.tangent_at(grind_offset)
	velocity = tan * speed
	facing = atan2(tan.x, tan.z)
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		grind = null
		velocity.y = cfg["jump"]
		set_state(S.AIR)
		visual.restart_state("jump")
		Sfx.play_at("jump_" + hero_id, global_position)


# ------------------------------------------------------------------- water
func _check_water() -> void:
	if state in [S.RIDE, S.GRIND, S.CUTSCENE, S.LAUNCH]:
		return
	var space := get_world_3d().direct_space_state
	_water_q.position = global_position + Vector3.UP * 0.35
	var hits := space.intersect_point(_water_q, 1)
	if hits.is_empty():
		water_surface = -INF
		if state == S.SWIM:
			set_state(S.AIR)
		return
	var area: Node3D = hits[0]["collider"]
	water_surface = area.get_parent().global_position.y if area.get_parent() is Node3D else area.global_position.y
	if state != S.SWIM and global_position.y < water_surface - 0.25 and state != S.POUND:
		set_state(S.SWIM)
		visual.set_state("swim", 0.15)
		Fx.burst("splash", Vector3(global_position.x, water_surface, global_position.z), Color(0, 0, 0, 0), 1.0)
		Sfx.play_at("splash", global_position)


func _st_swim(delta: float) -> void:
	var float_y := water_surface - (0.42 if hero_id == "strong" else 0.62)
	velocity.y = move_toward(velocity.y, (float_y - global_position.y) * 6.0, 30.0 * delta)
	_horizontal(delta, 20.0, 14.0, cfg["swim_speed"], cfg["turn"] * 0.8)
	if jump_buffer > 0.0:
		jump_buffer = 0.0
		velocity.y = cfg["jump"] * 0.85
		set_state(S.AIR)
		visual.restart_state("jump")
		Fx.burst("splash", global_position + Vector3.UP * 0.4, Color(0, 0, 0, 0), 0.8)
		Sfx.play_at("splash", global_position, 1.2)
		return
	if intent.take("special"):
		_special()
		if state != S.SWIM:
			return
	if Engine.get_physics_frames() % 12 == 0 and Vector2(velocity.x, velocity.z).length() > 1.0:
		Fx.burst("splash", Vector3(global_position.x, water_surface, global_position.z), Color(0, 0, 0, 0), 0.35)
	move_and_slide()


# ------------------------------------------------------------------- damage
func take_hit(from: Vector3) -> void:
	if invuln > 0.0 or state in [S.RIDE, S.CUTSCENE]:
		return
	petals -= 1
	invuln = 1.6
	var away := (global_position - from)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -Vector3(sin(facing), 0, cos(facing))
	velocity = away * 7.0 + Vector3.UP * 6.0
	set_state(S.HURT)
	visual.restart_state("hurt")
	visual.flash(1.0)
	Sfx.play_at("hurt_" + hero_id, global_position)
	Game.vibrate(60)
	get_tree().call_group(&"cameras", &"shake", 0.3)
	hurt_taken.emit(petals)
	if petals <= 0:
		petals = 3
		await get_tree().create_timer(0.5, false).timeout
		respawn()


func _st_hurt(delta: float) -> void:
	velocity.y -= cfg["gravity"] * delta
	velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	move_and_slide()
	if state_t > 0.45:
		set_state(S.GROUND if is_on_floor() else S.AIR)
		visual.set_state("loco" if is_on_floor() else "fall")


func respawn() -> void:
	if rider != null:
		rider.dismount()
	if mount != null:
		dismount()
	Fx.burst("wisp", global_position, Color(0, 0, 0, 0), 1.0)
	global_position = Game.checkpoint + spawn_offset
	velocity = Vector3.ZERO
	invuln = 1.2
	set_state(S.AIR)
	visual.set_state("fall")
	reset_physics_interpolation()
	Fx.burst("wisp", global_position + Vector3.UP * 0.5, Color(0, 0, 0, 0), 1.2)
	Sfx.play_at("respawn", global_position)
	respawned.emit()


func teleport(pos: Vector3, yaw := NAN) -> void:
	global_position = pos
	if not is_nan(yaw):
		facing = yaw
	velocity = Vector3.ZERO
	reset_physics_interpolation()


# ------------------------------------------------------------------- cutscene
func _st_cutscene(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	velocity.y -= cfg["gravity"] * delta
	move_and_slide()


func add_updraft(strength: float) -> void:
	updraft = maxf(updraft, strength)


func is_heavy() -> bool:
	return hero_id == "strong" or state == S.RIDE


func is_attacking() -> bool:
	return action_t > 0.0 or state == S.POUND


# =================================================================== visual
func _update_visual(delta: float) -> void:
	if visual == null:
		return
	# yaw + lean into turns (roll) and acceleration (pitch)
	var dyaw := wrapf(facing - _prev_facing, -PI, PI)
	_prev_facing = facing
	_turn_rate = lerpf(_turn_rate, dyaw / maxf(delta, 1e-4), 1.0 - exp(-10.0 * delta))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var roll := clampf(-_turn_rate * hspeed * 0.022, -0.45, 0.45)
	var pitch := 0.0
	if state in [S.GROUND, S.AIR, S.SWIM]:
		pitch = clampf(hspeed / cfg["speed"], 0.0, 1.0) * (0.12 if hero_id == "agile" else 0.06)
	if state == S.GLIDE:
		pitch = 0.18
		roll *= 1.6
	elif state == S.SURF:
		pitch = -0.05
		roll = clampf(-_turn_rate * hspeed * 0.04, -0.6, 0.6)
	_lean = _lean.lerp(Vector2(pitch, roll), 1.0 - exp(-8.0 * delta))
	visual.rotation = Vector3(_lean.x, facing, _lean.y)
	# squash & stretch spring
	var k := 220.0
	var c := 16.0
	var acc := (1.0 - _squash) * k - _squash_v * c
	_squash_v += acc * delta
	_squash += _squash_v * delta
	if state in [S.AIR, S.LAUNCH] and not is_remote:
		_squash = lerpf(_squash, 1.0 + clampf(velocity.y / 60.0, -0.08, 0.1), 0.15)
	var s := clampf(_squash, 0.55, 1.4)
	visual.scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))
	if invuln > 0.0 and state != S.CUTSCENE:
		visual.visible = int(invuln * 14.0) % 2 == 0 or invuln < 0.2
	else:
		visual.visible = true
	# animation state
	var speed01 := 0.0
	var cps := 1.0
	if hspeed > 0.15:
		var walk_v: float = cfg["walk_v"]
		var run_v: float = cfg["run_v"]
		speed01 = clampf(0.3 * hspeed / walk_v, 0.0, 0.3) if hspeed < walk_v else lerpf(0.3, 1.0, clampf((hspeed - walk_v) / (run_v - walk_v), 0.0, 1.0))
		var natural := lerpf(1.25, 2.0, clampf((speed01 - 0.3) / 0.7, 0.0, 1.0))
		var ref_v := lerpf(walk_v, run_v, clampf((speed01 - 0.3) / 0.7, 0.0, 1.0))
		cps = natural * clampf(hspeed / ref_v, 0.6, 1.9)
	visual.set_locomotion(speed01, cps)
	match state:
		S.GROUND:
			if visual.state in ["fall", "glide", "swim", "double_jump", "hurt", "flop"] or (visual.state == "spin" and action_t <= 0.0):
				visual.set_state("loco")
			elif visual.state == "jump" and state_t > 0.2:
				visual.set_state("loco")
		S.AIR, S.LAUNCH:
			if velocity.y < -1.5 and visual.state in ["loco", "jump", "land"] and state_t > 0.15:
				visual.set_state("fall", 0.25)
			if visual.state == "spin" and action_t <= 0.0:
				visual.set_state("fall", 0.2)
		S.GLIDE:
			visual.set_state("glide", 0.18)
		S.RIDE:
			if visual.state != "spin" or action_t <= 0.0:
				visual.set_state("ride")
		S.SWIM:
			visual.set_state("swim")
		S.SURF:
			visual.set_state("surf" if visual.has_state("surf") else "fall", 0.2)
