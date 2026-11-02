class_name CoopCamera
extends Node3D
## Câmera em terceira pessoa que segue um herói (solo) ou enquadra os dois
## (co-op local, estilo câmera compartilhada). Suaviza com molas, não "pula"
## junto com o personagem (só acompanha a altura do chão), realinha atrás do
## movimento quando o jogador não mexe na câmera, evita atravessar o terreno,
## abre o FOV com a velocidade e treme em impactos.

const LAYER_WORLD := 1

var targets: Array = []
var shared := false
var yaw := 0.0
var pitch := -0.32
var distance := 4.9
var cam: Camera3D
var _pivot := Vector3.ZERO
var _ground_y := 0.0
var _look_idle := 10.0
var _trauma := 0.0
var _shake_t := 0.0
var _ahead := Vector3.ZERO
var _cur_dist := 4.9
var _fov_base := 64.0
var cinematic: Node3D = null      ## alvo de cutscene (ou null)
var _cine_pos := Vector3.ZERO
var _blend_from := Transform3D.IDENTITY
var _blend_t := 1.0
var blend_time := 1.8


func _ready() -> void:
	add_to_group(&"cameras")
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = _fov_base
	cam.near = 0.08
	cam.far = 2500.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.make_current()


func snap_to_targets() -> void:
	if targets.is_empty():
		return
	_pivot = _center()
	_ground_y = _pivot.y
	_cur_dist = distance
	_place(1.0, 0.016)


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Giro de câmera vindo do jogador (radianos).
func add_look(v: Vector2) -> void:
	if v.length_squared() < 1e-8:
		return
	yaw -= v.x * Game.camera_sensitivity
	var dy := v.y * Game.camera_sensitivity * (-1.0 if Game.invert_camera else 1.0)
	pitch = clampf(pitch - dy, -1.15, 0.35)
	_look_idle = 0.0


func _center() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for t in targets:
		if is_instance_valid(t):
			c += (t as Node3D).get_global_transform_interpolated().origin
			n += 1
	return c / maxf(n, 1)


func _process(delta: float) -> void:
	if targets.is_empty():
		return
	delta = minf(delta, 0.05)
	_look_idle += delta
	if cinematic != null:
		_cine(delta)
		return
	var lead: Hero = targets[0]
	var center := _center()
	# vertical: follow the ground, not every jump (classic platformer camera)
	var grounded := true
	for t in targets:
		if is_instance_valid(t) and not (t.state in [Hero.S.GROUND, Hero.S.SWIM, Hero.S.RIDE, Hero.S.GRIND]):
			grounded = false
	if grounded:
		_ground_y = lerpf(_ground_y, center.y, 1.0 - exp(-6.0 * delta))
	else:
		if center.y < _ground_y - 0.5:
			_ground_y = lerpf(_ground_y, center.y + 0.5, 1.0 - exp(-8.0 * delta))
		elif center.y > _ground_y + 3.2:
			_ground_y = lerpf(_ground_y, center.y - 3.2, 1.0 - exp(-5.0 * delta))
	var vel := Vector3.ZERO
	for t in targets:
		if is_instance_valid(t):
			vel += (t as Hero).velocity
	vel /= maxf(targets.size(), 1)
	var hv := Vector3(vel.x, 0, vel.z)
	_ahead = _ahead.lerp(hv * 0.22, 1.0 - exp(-2.5 * delta))
	var want := Vector3(center.x, _ground_y, center.z) + _ahead
	_pivot.x = lerpf(_pivot.x, want.x, 1.0 - exp(-9.0 * delta))
	_pivot.z = lerpf(_pivot.z, want.z, 1.0 - exp(-9.0 * delta))
	_pivot.y = lerpf(_pivot.y, want.y, 1.0 - exp(-7.0 * delta))
	# shared framing
	var want_dist := distance
	if shared and targets.size() > 1:
		var spread := 0.0
		for t in targets:
			spread = maxf(spread, (t as Node3D).global_position.distance_to(center))
		want_dist = clampf(6.5 + spread * 1.6, 7.0, 22.0)
	elif lead.state == Hero.S.GLIDE:
		want_dist = distance * 1.25
	_cur_dist = lerpf(_cur_dist, want_dist, 1.0 - exp(-3.0 * delta))
	# auto-align behind the movement when the player isn't steering the camera
	var speed := hv.length()
	if _look_idle > 1.3 and speed > 2.5 and not shared:
		var move_yaw := atan2(-hv.x, -hv.z)
		var diff := wrapf(move_yaw - yaw, -PI, PI)
		if absf(diff) < 2.4:
			yaw += diff * (1.0 - exp(-0.9 * delta)) * clampf(speed / 6.0, 0.0, 1.0)
		pitch = lerpf(pitch, -0.3, 1.0 - exp(-0.8 * delta))
	cam.fov = lerpf(cam.fov, _fov_base + clampf(speed / 9.0, 0.0, 1.0) * 7.0, 1.0 - exp(-3.0 * delta))
	_place(1.0, delta)
	for t in targets:
		(t as Hero).cam_yaw = yaw


func _place(_w: float, delta: float) -> void:
	var look_at_pos := _pivot + Vector3.UP * 0.95
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, 1)
	var desired := look_at_pos + dir * _cur_dist
	# keep the camera out of the ground / cliffs
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(look_at_pos, desired, LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] + (hit["normal"] as Vector3) * 0.35
	# shake
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	_shake_t += delta * 30.0
	var sh := _trauma * _trauma
	var off := Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 1.0), 0) * sh * 0.25
	global_position = desired
	look_at(look_at_pos, Vector3.UP)
	cam.position = off
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / blend_time)
		var k := ease(_blend_t, -2.2)
		global_transform = _blend_from.interpolate_with(global_transform, k)


## Cutscene: câmera orbitando um ponto.
func start_cinematic(target: Node3D, radius := 18.0, height := 9.0) -> void:
	cinematic = target
	_cine_pos = global_position
	set_meta("cine_r", radius)
	set_meta("cine_h", height)
	set_meta("cine_t", 0.0)


func stop_cinematic(smooth := true) -> void:
	cinematic = null
	_blend_from = global_transform
	snap_to_targets()
	if smooth:
		_blend_t = 0.0
		global_transform = _blend_from


func _cine(delta: float) -> void:
	var t: float = get_meta("cine_t") + delta
	set_meta("cine_t", t)
	var r: float = get_meta("cine_r")
	var h: float = get_meta("cine_h")
	var c := cinematic.global_position
	var a := yaw + t * 0.25
	var want := c + Vector3(sin(a) * r, h, cos(a) * r)
	global_position = global_position.lerp(want, 1.0 - exp(-1.5 * delta))
	look_at(c + Vector3.UP * h * 0.4, Vector3.UP)
	cam.position = Vector3.ZERO
