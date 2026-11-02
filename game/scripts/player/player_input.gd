class_name PlayerInput
extends RefCounted
## Intenção de um jogador num tick de física. As fontes (teclado, controle,
## toque, IA, rede) preenchem; o herói consome. "Pressed" fica travado até ser
## consumido, então um toque curto no celular nunca se perde entre frames.

var move := Vector2.ZERO        ## x direita, y para baixo (frente = -y)
var look := Vector2.ZERO        ## giro de câmera acumulado neste frame (radianos)
var jump := false
var action := false
var _jump_pressed := false
var _action_pressed := false
var _special_pressed := false
var _swap_pressed := false


func press(what: String) -> void:
	match what:
		"jump": _jump_pressed = true
		"action": _action_pressed = true
		"special": _special_pressed = true
		"swap": _swap_pressed = true


func take(what: String) -> bool:
	var v := false
	match what:
		"jump":
			v = _jump_pressed
			_jump_pressed = false
		"action":
			v = _action_pressed
			_action_pressed = false
		"special":
			v = _special_pressed
			_special_pressed = false
		"swap":
			v = _swap_pressed
			_swap_pressed = false
	return v


func peek(what: String) -> bool:
	match what:
		"jump": return _jump_pressed
		"action": return _action_pressed
		"special": return _special_pressed
		"swap": return _swap_pressed
	return false


func clear() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	jump = false
	action = false
	_jump_pressed = false
	_action_pressed = false
	_special_pressed = false
	_swap_pressed = false


## Serialização compacta para a rede.
func to_packet() -> PackedFloat32Array:
	var flags := (1 if jump else 0) | (2 if action else 0) | (4 if _jump_pressed else 0) \
		| (8 if _action_pressed else 0) | (16 if _special_pressed else 0)
	return PackedFloat32Array([move.x, move.y, float(flags)])


func from_packet(p: PackedFloat32Array) -> void:
	if p.size() < 3:
		return
	move = Vector2(p[0], p[1])
	var f := int(p[2])
	jump = f & 1 != 0
	action = f & 2 != 0
	if f & 4:
		_jump_pressed = true
	if f & 8:
		_action_pressed = true
	if f & 16:
		_special_pressed = true
