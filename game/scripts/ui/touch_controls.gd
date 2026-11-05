class_name TouchControls
extends Control
## Controles de toque (multitoque): analógico flutuante à esquerda, botões à
## direita (Pular, Ação, Dupla, Trocar) e arrasto livre para girar a câmera.
## Escreve em InputSources (estado estático lido pelo jogador 1).
## Itens (itens.md 3.1): USAR (arpéu/concha, segurar mantém o balanço) e o chip
## da Lanterna (liga/desliga). Só aparecem quando o Sael tem o item (o HUD liga).

signal pause_requested

const BTN := {
	"jump": {"label": "PULAR", "pos": Vector2(-120, -120), "r": 74.0, "color": Color(0.12, 0.66, 0.64)},
	"action": {"label": "AÇÃO", "pos": Vector2(-280, -86), "r": 58.0, "color": Color(0.96, 0.46, 0.58)},
	"special": {"label": "DUPLA", "pos": Vector2(-236, -236), "r": 50.0, "color": Color(1.0, 0.72, 0.3)},
	"swap": {"label": "TROCAR", "pos": Vector2(-96, -290), "r": 40.0, "color": Color(0.6, 0.5, 0.9)},
	"use": {"label": "USAR", "pos": Vector2(-392, -196), "r": 52.0, "color": Color(0.98, 0.78, 0.36)},
	"lamp": {"label": "", "pos": Vector2(-470, -262), "r": 28.0, "color": Color(1.0, 0.71, 0.35)},
}
const BRASS := Color(0.83, 0.64, 0.25)

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
var show_use := false             ## o Sael tem o Arpéu (ou a Concha)
var show_lamp := false            ## o Sael tem a Lanterna
var use_icon := "empty"           ## "hook" (alvo destacado) | "shell" (Concha) | "empty" (arremesso vazio)
var lamp_on := false              ## lanterna acesa: halo âmbar no chip
var use_hint := false             ## pulsa o USAR: alvo de quebra-cabeça válido a até 10 m
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.font(700)


func _scale() -> float:
	var vs := get_viewport_rect().size
	return clampf(vs.y / 720.0, 0.75, 1.6)


func _btn_center(id: String) -> Vector2:
	var vs := get_viewport_rect().size
	return vs + (BTN[id]["pos"] as Vector2) * _scale()


func _btn_visible(id: String) -> bool:
	match id:
		"swap": return show_swap
		"use": return show_use
		"lamp": return show_lamp
	return true


func _hit_button(p: Vector2) -> String:
	for id in BTN:
		if not _btn_visible(id):
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
				elif b == "use":
					InputSources.touch_use = true
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
				elif b == "use":
					InputSources.touch_use = false
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
	InputSources.touch_use = false
	queue_redraw()


## O USAR sumiu com o dedo em cima (troca de herói, item perdido): solta o segurado.
func _drop_hidden() -> void:
	for f in _btn_fingers.keys():
		var b: String = _btn_fingers[f]
		if not _btn_visible(b):
			_btn_fingers.erase(f)
			_pressed[b] = false
			if b == "use":
				InputSources.touch_use = false


func _process(delta: float) -> void:
	_t += delta
	_drop_hidden()
	if special_hint or (show_use and use_hint) or (show_lamp and lamp_on):
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
		if not _btn_visible(id):
			continue
		var c := _btn_center(id)
		var r: float = float(BTN[id]["r"]) * s
		var col: Color = BTN[id]["color"]
		var pressed: bool = _pressed.get(id, false)
		var pulse := 0.0
		if (id == "special" and special_hint) or (id == "use" and use_hint):
			pulse = 0.5 + 0.5 * sin(_t * 6.0)
			draw_circle(c, r * (1.12 + 0.08 * pulse), Color(1, 0.9, 0.5, 0.25 + 0.2 * pulse))
		if id == "lamp" and lamp_on:
			# halo âmbar da lanterna acesa (cintila como a luz no mundo)
			var fl := 0.5 + 0.5 * sin(_t * TAU * 3.0)
			draw_circle(c, r * (1.45 + 0.06 * fl), Color(1.0, 0.71, 0.35, 0.16))
			draw_circle(c, r * (1.22 + 0.04 * fl), Color(1.0, 0.78, 0.45, 0.3))
		var fill := 0.78 if pressed or (id == "lamp" and lamp_on) else 0.42
		draw_circle(c, r, Color(col.r, col.g, col.b, fill))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.75), 3.0 * s, true)
		var label: String = BTN[id]["label"]
		var fs := int((20 if r > 45 * s else 15) * s)
		if id == "use":
			_draw_use_icon(c + Vector2(0, -r * 0.2), r * 0.42, s)
			fs = int(15 * s)
			var tu := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(_font, c + Vector2(-tu * 0.5, r * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
			continue
		if id == "lamp":
			_draw_lamp_icon(c, r * 0.62, s)
			continue
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	# pause
	var pc := Vector2(vs.x - 60 * s, 52 * s)
	draw_circle(pc, 30 * s, Color(1, 1, 1, 0.3))
	draw_rect(Rect2(pc + Vector2(-11, -12) * s, Vector2(7, 24) * s), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(pc + Vector2(4, -12) * s, Vector2(7, 24) * s), Color(1, 1, 1, 0.9))


# ------------------------------------------------------------------ ícones
## Ícone do USAR conforme o contexto: losango de latão (alvo de arpéu),
## concha espiral (rajada) ou arpéu cinza (arremesso vazio).
func _draw_use_icon(c: Vector2, r: float, s: float) -> void:
	match use_icon:
		"hook":
			var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
			draw_colored_polygon(d, BRASS)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c]), BRASS.lightened(0.4))
			d.append(d[0])
			draw_polyline(d, Color(1, 1, 1, 0.95), 2.5 * s, true)
			draw_circle(c, r * 0.16, Color(0.31, 0.89, 0.84))
		"shell":
			# espiral de nácar (3 voltas) com bocal de latão
			var pts := PackedVector2Array()
			for i in 40:
				var t := float(i) / 39.0
				var a := t * TAU * 2.6
				pts.append(c + Vector2(cos(a), sin(a)) * r * (0.12 + 0.88 * t))
			draw_circle(c, r * 0.95, Color(0.98, 0.8, 0.82, 0.85))
			draw_polyline(pts, Color(0.62, 0.36, 0.42), 2.5 * s, true)
			draw_circle(c + Vector2(r * 0.95, 0), r * 0.2, BRASS)
		_:
			# arpéu cinza: haste + 3 garras curvas
			var g := Color(0.82, 0.82, 0.84, 0.9)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.45), g, 3.0 * s, true)
			draw_circle(c + Vector2(0, -r), r * 0.16, g)
			draw_arc(c + Vector2(-r * 0.42, r * 0.38), r * 0.42, 0.0, PI * 0.75, 10, g, 3.0 * s, true)
			draw_arc(c + Vector2(r * 0.42, r * 0.38), r * 0.42, PI * 0.25, PI, 10, g, 3.0 * s, true)
			draw_line(c + Vector2(0, r * 0.45), c + Vector2(0, r * 0.85), g, 3.0 * s, true)


## Ícone do chip: lanterna de gaiola de latão com vidro âmbar (aceso = brilha).
func _draw_lamp_icon(c: Vector2, r: float, s: float) -> void:
	var glass := Color(1.0, 0.71, 0.35) if lamp_on else Color(0.62, 0.48, 0.32)
	var body := Rect2(c + Vector2(-r * 0.45, -r * 0.5), Vector2(r * 0.9, r * 1.15))
	if lamp_on:
		draw_circle(c + Vector2(0, r * 0.08), r * 0.75, Color(1.0, 0.86, 0.55, 0.45))
	draw_rect(body, glass)
	if lamp_on:
		draw_circle(c + Vector2(0, r * 0.12), r * 0.2, Color(1, 0.97, 0.85))
	for x in [-0.45, 0.0, 0.45]:
		draw_line(c + Vector2(r * x, -r * 0.5), c + Vector2(r * x, r * 0.65), BRASS.lightened(0.25), 1.6 * s, true)
	draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.62), Vector2(r * 1.2, r * 0.16)), BRASS)
	draw_rect(Rect2(c + Vector2(-r * 0.6, r * 0.62), Vector2(r * 1.2, r * 0.16)), BRASS)
	draw_arc(c + Vector2(0, -r * 0.62), r * 0.38, PI, TAU, 12, Color(1, 1, 1, 0.9), 2.0 * s, true)
