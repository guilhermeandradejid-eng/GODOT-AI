class_name InputSources
extends RefCounted
## Fontes de entrada humanas: teclado (2 esquemas), controles por id e o
## estado compartilhado dos controles de toque.

const DEADZONE := 0.18

## Estado escrito pelos controles de toque (TouchControls) e lido pelo P1.
static var touch_move := Vector2.ZERO
static var touch_look := Vector2.ZERO
static var touch_jump := false
static var touch_action := false
static var touch_events: Array[String] = []

## Esquema: "kb1" (WASD+mouse), "kb2" (setas), "pad:N", "touch".
var schemes: Array[String] = []
var _prev := {}
var mouse_look := Vector2.ZERO


func _init(s: Array[String]) -> void:
	schemes = s


func has_scheme(s: String) -> bool:
	return s in schemes


func poll(intent: PlayerInput) -> void:
	var mv := Vector2.ZERO
	var jump := false
	var action := false
	for s in schemes:
		if s == "kb1":
			mv += Vector2(_k(KEY_D) - _k(KEY_A), _k(KEY_S) - _k(KEY_W))
			jump = jump or Input.is_physical_key_pressed(KEY_SPACE)
			action = action or Input.is_physical_key_pressed(KEY_J) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			_edge(intent, "jump", "kb1_jump", Input.is_physical_key_pressed(KEY_SPACE))
			_edge(intent, "action", "kb1_action", Input.is_physical_key_pressed(KEY_J) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
			_edge(intent, "special", "kb1_special", Input.is_physical_key_pressed(KEY_K) or Input.is_physical_key_pressed(KEY_E))
			_edge(intent, "swap", "kb1_swap", Input.is_physical_key_pressed(KEY_TAB) or Input.is_physical_key_pressed(KEY_Q))
		elif s == "kb2":
			mv += Vector2(_k(KEY_RIGHT) - _k(KEY_LEFT), _k(KEY_DOWN) - _k(KEY_UP))
			var j := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_0)
			var a := Input.is_physical_key_pressed(KEY_CTRL)
			jump = jump or j
			action = action or a
			_edge(intent, "jump", "kb2_jump", j)
			_edge(intent, "action", "kb2_action", Input.is_physical_key_pressed(KEY_CTRL))
			_edge(intent, "special", "kb2_special", Input.is_physical_key_pressed(KEY_KP_1) or Input.is_physical_key_pressed(KEY_SLASH))
		elif s.begins_with("pad:"):
			var dev := int(s.substr(4))
			var st := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
			if st.length() > DEADZONE:
				mv += st.normalized() * inverse_lerp(DEADZONE, 1.0, minf(st.length(), 1.0))
			var dp := Vector2(float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT)),
				float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP)))
			mv += dp
			var ja := Input.is_joy_button_pressed(dev, JOY_BUTTON_A)
			var jx := Input.is_joy_button_pressed(dev, JOY_BUTTON_X) or Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5
			jump = jump or ja
			action = action or jx
			_edge(intent, "jump", s + "_a", ja)
			_edge(intent, "action", s + "_x", jx)
			_edge(intent, "special", s + "_b", Input.is_joy_button_pressed(dev, JOY_BUTTON_B))
			_edge(intent, "swap", s + "_y", Input.is_joy_button_pressed(dev, JOY_BUTTON_Y) or Input.is_joy_button_pressed(dev, JOY_BUTTON_RIGHT_SHOULDER))
		elif s == "touch":
			mv += touch_move
			jump = jump or touch_jump
			action = action or touch_action
			for e in touch_events:
				intent.press(e)
			touch_events.clear()
	if mv.length() > 1.0:
		mv = mv.normalized()
	intent.move = mv
	intent.jump = jump
	intent.action = action


func _k(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0


func _edge(intent: PlayerInput, what: String, id: String, now: bool) -> void:
	var before: bool = _prev.get(id, false)
	if now and not before:
		intent.press(what)
	_prev[id] = now


## Giro de câmera deste jogador (lido a cada frame de render pela câmera).
func poll_look(delta: float) -> Vector2:
	var look := Vector2.ZERO
	for s in schemes:
		if s == "kb1":
			look += Vector2(_k(KEY_RIGHT if not has_scheme("kb2") else KEY_L) - _k(KEY_LEFT if not has_scheme("kb2") else KEY_H), 0.0) * 2.4 * delta
			look += mouse_look
			mouse_look = Vector2.ZERO
		elif s.begins_with("pad:"):
			var dev := int(s.substr(4))
			var rs := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
			if rs.length() > DEADZONE:
				look += rs * 2.8 * delta
		elif s == "touch":
			look += touch_look
			touch_look = Vector2.ZERO
	return look
