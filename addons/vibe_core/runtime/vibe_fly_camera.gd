extends Camera3D
## Fly camera used by `camera.add {"type": "fly"}` to explore generated worlds.
##
## Hold the RIGHT mouse button to look around, WASD / arrows to move,
## E / Q (or Space / Ctrl) to go up / down, Shift to go faster and the mouse
## wheel to change the base speed. The camera never goes below the terrain.

@export var speed := 18.0
@export var fast_multiplier := 4.0
@export var mouse_sensitivity := 0.2
@export var min_height_above_ground := 1.6

var _yaw := 0.0
var _pitch := 0.0
var _looking := false


func _ready() -> void:
	var euler := global_transform.basis.get_euler()
	_pitch = rad_to_deg(euler.x)
	_yaw = rad_to_deg(euler.y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, 2000.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, 0.5)
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -89.0, 89.0)
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_looking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir -= global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir += global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * s * delta
	for t in get_tree().get_nodes_in_group(&"vibe_terrain"):
		if t.has_method("get_height_at_world"):
			var ground: float = t.get_height_at_world(global_position)
			if global_position.y < ground + min_height_above_ground:
				global_position.y = ground + min_height_above_ground
			break
