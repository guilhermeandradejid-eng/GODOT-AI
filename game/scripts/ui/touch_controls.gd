class_name TouchControls
extends Control
## Controles de toque (multitoque): analógico flutuante à esquerda, botões à
## direita (Pular, Ação, Dupla, Trocar) e arrasto livre para girar a câmera.
## Escreve em InputSources (estado estático lido pelo jogador 1).

signal pause_requested

const BTN := {
	"jump": {"label": "PULAR", "pos": Vector2(-120, -120), "r": 74.0, "color": Color(0.12, 0.66, 0.64)},
	"action": {"label": "AÇÃO", "pos": Vector2(-280, -86), "r": 58.0, "color": Color(0.96, 0.46, 0.58)},
	"special": {"label": "DUPLA", "pos": Vector2(-236, -236), "r": 50.0, "color": Color(1.0, 0.72, 0.3)},
	"swap": {"label": "TROCAR", "pos": Vector2(-96, -290), "r": 40.0, "color": Color(0.6, 0.5, 0.9)},
}

var stick_radius := 96.0
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _btn_fingers := {}            ## finger -> button id
var _pressed := {}                ## button id -> bool
var _font: Font
var show_swap := true
var special_hint := false         ## pulsa o botão Dupla quando a dupla pode agir junta
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SoproTheme.font(700)


func _scale() -> float:
	var vs := get_viewport_rect().size
	return clampf(vs.y / 720.0, 0.75, 1.6)


func _btn_center(id: String) -> Vector2:
	var vs := get_viewport_rect().size
	return vs + (BTN[id]["pos"] as Vector2) * _scale()


func _hit_button(p: Vector2) -> String:
	for id in BTN:
		if id == "swap" and not show_swap:
			continue
		if p.distance_to(_btn_center(id)) <= float(BTN[id]["r"]) * _scale() * 1.15:
			return id
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			# pause button (top-right corner)
			if e.position.x > vs.x - 110 * _scale() and e.position.y < 100 * _scale():
				pause_requested.emit()
				return
			var b := _hit_button(e.position)
			if b != "":
				_btn_fingers[e.index] = b
				_pressed[b] = true
				InputSources.touch_events.append(b)
				if b == "jump":
					InputSources.touch_jump = true
				elif b == "action":
					InputSources.touch_action = true
				Game.vibrate(8)
			elif e.position.x < vs.x * 0.42 and _stick_finger < 0:
				_stick_finger = e.index
				_stick_origin = e.position
				_stick_pos = e.position
			elif _look_finger < 0:
				_look_finger = e.index
		else:
			if e.index == _stick_finger:
				_stick_finger = -1
				InputSources.touch_move = Vector2.ZERO
			elif e.index == _look_finger:
				_look_finger = -1
			elif _btn_fingers.has(e.index):
				var b: String = _btn_fingers[e.index]
				_btn_fingers.erase(e.index)
				_pressed[b] = false
				if b == "jump":
					InputSources.touch_jump = false
				elif b == "action":
					InputSources.touch_action = false
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			_stick_pos = d.position
			var v := (_stick_pos - _stick_origin) / (stick_radius * _scale())
			if v.length() > 1.0:
				# drag the base along so the thumb never "loses" the stick
				_stick_origin = _stick_pos - v.normalized() * stick_radius * _scale()
				v = v.normalized()
			InputSources.touch_move = v
			queue_redraw()
		elif d.index == _look_finger:
			InputSources.touch_look += d.relative * 0.0062 / _scale()


func release_all() -> void:
	_stick_finger = -1
	_look_finger = -1
	_btn_fingers.clear()
	_pressed.clear()
	InputSources.touch_move = Vector2.ZERO
	InputSources.touch_jump = false
	InputSources.touch_action = false
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if special_hint:
		queue_redraw()


func _draw() -> void:
	var s := _scale()
	var vs := get_viewport_rect().size
	# stick
	if _stick_finger >= 0:
		draw_circle(_stick_origin, stick_radius * s, Color(1, 1, 1, 0.16))
		draw_arc(_stick_origin, stick_radius * s, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0 * s, true)
		var knob := _stick_origin + InputSources.touch_move * stick_radius * s
		draw_circle(knob, 40 * s, Color(1, 0.97, 0.92, 0.7))
	else:
		var hint := Vector2(170, vs.y / s - 150) * s
		draw_arc(hint, stick_radius * s * 0.8, 0, TAU, 48, Color(1, 1, 1, 0.22), 3.0 * s, true)
		draw_circle(hint, 34 * s, Color(1, 1, 1, 0.18))
	# buttons
	for id in BTN:
		if id == "swap" and not show_swap:
			continue
		var c := _btn_center(id)
		var r: float = float(BTN[id]["r"]) * s
		var col: Color = BTN[id]["color"]
		var pressed: bool = _pressed.get(id, false)
		var pulse := 0.0
		if id == "special" and special_hint:
			pulse = 0.5 + 0.5 * sin(_t * 6.0)
			draw_circle(c, r * (1.12 + 0.08 * pulse), Color(1, 0.9, 0.5, 0.25 + 0.2 * pulse))
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.78 if pressed else 0.42))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.75), 3.0 * s, true)
		var label: String = BTN[id]["label"]
		var fs := int((20 if r > 45 * s else 15) * s)
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	# pause
	var pc := Vector2(vs.x - 60 * s, 52 * s)
	draw_circle(pc, 30 * s, Color(1, 1, 1, 0.3))
	draw_rect(Rect2(pc + Vector2(-11, -12) * s, Vector2(7, 24) * s), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(pc + Vector2(4, -12) * s, Vector2(7, 24) * s), Color(1, 1, 1, 0.9))
