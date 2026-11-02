class_name GameHUD
extends CanvasLayer
## HUD minimalista (estilo Sky): contador de centelhas, 3 Pedras das Horas, losangos de vida
## de cada herói, avisos que aparecem e somem, controles de toque e pausa.

signal resume_requested
signal restart_requested
signal menu_requested

var party: HeroParty
var touch: TouchControls
var _mote_label: Label
var _mote_pop := 0.0
var _seed_slots: Array[Control] = []
var _toast: Label
var _toast_t := 0.0
var _who: Label
var _petals := {}
var _pause: Control
var _quality_btn: Button
var _root: Control
var _t := 0.0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)
	# centelhas
	var mote_box := HBoxContainer.new()
	mote_box.position = Vector2(34, 26)
	mote_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(mote_box)
	var icon := _MoteIcon.new()
	icon.custom_minimum_size = Vector2(44, 44)
	mote_box.add_child(icon)
	_mote_label = UITheme.label("0", 34, Color(1, 1, 1), 700)
	_mote_label.add_theme_color_override("font_outline_color", Color(0.45, 0.25, 0.35, 0.6))
	_mote_label.add_theme_constant_override("outline_size", 8)
	mote_box.add_child(_mote_label)
	# Pedras das Horas
	var seeds := HBoxContainer.new()
	seeds.set_anchors_preset(Control.PRESET_CENTER_TOP)
	seeds.position = Vector2(-80, 22)
	seeds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seeds.add_theme_constant_override("separation", 18)
	_root.add_child(seeds)
	for i in Game.RELICS_TOTAL:
		var s := _SeedSlot.new()
		s.custom_minimum_size = Vector2(40, 52)
		seeds.add_child(s)
		_seed_slots.append(s)
	# vida (pontos do emblema) por herói
	var hp := VBoxContainer.new()
	hp.position = Vector2(34, 84)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.add_theme_constant_override("separation", 6)
	_root.add_child(hp)
	for id in ["agile", "strong"]:
		var p := _Petals.new()
		p.hero_id = id
		p.custom_minimum_size = Vector2(150, 30)
		hp.add_child(p)
		_petals[id] = p
	# who am I
	_who = UITheme.label("", 20, Color(1, 1, 1, 0.9), 600)
	_who.add_theme_color_override("font_outline_color", Color(0.45, 0.25, 0.35, 0.5))
	_who.add_theme_constant_override("outline_size", 6)
	_who.position = Vector2(34, 160)
	_root.add_child(_who)
	# toast
	_toast = UITheme.label("", 30, Color(1, 1, 1), 600)
	_toast.add_theme_color_override("font_outline_color", Color(0.45, 0.22, 0.35, 0.55))
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-400, 96)
	_toast.size = Vector2(800, 60)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	# touch
	touch = TouchControls.new()
	touch.visible = Game.touch_enabled
	touch.pause_requested.connect(toggle_pause)
	_root.add_child(touch)
	_build_pause()
	Game.motes_changed.connect(_on_motes)
	Game.relic_collected.connect(_on_seed)
	Game.toast.connect(show_toast)


func bind(p: HeroParty) -> void:
	party = p
	p.controlled_changed.connect(func(h: Hero): _who.text = "Você: " + HeroDefs.display_name(h.hero_id))
	_who.text = "Você: " + HeroDefs.display_name("agile")
	for h in [p.agile, p.strong]:
		h.hurt_taken.connect(func(_n): (_petals[h.hero_id] as _Petals).queue_redraw())
		h.respawned.connect(func(): (_petals[h.hero_id] as _Petals).queue_redraw())
		(_petals[h.hero_id] as _Petals).hero = h


func _on_motes(total: int) -> void:
	_mote_label.text = str(total)
	_mote_pop = 1.0


func _on_seed(id: String, total: int) -> void:
	for i in _seed_slots.size():
		var slot := _seed_slots[i] as _SeedSlot
		if i == total - 1:
			slot.color = Interactables.Relic.RELIC_COLORS.get(id, Color(1.0, 0.86, 0.45))
		slot.filled = i < total
		slot.queue_redraw()


func show_toast(text: String, seconds := 3.0) -> void:
	_toast.text = text
	_toast_t = seconds


func _process(delta: float) -> void:
	_t += delta
	_mote_pop = maxf(0.0, _mote_pop - delta * 4.0)
	_mote_label.scale = Vector2.ONE * (1.0 + 0.25 * _mote_pop)
	_mote_label.pivot_offset = _mote_label.size * 0.5
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = minf(1.0, _toast.modulate.a + delta * 4.0) if _toast_t > 0.4 else maxf(0.0, _toast_t / 0.4)
	else:
		_toast.modulate.a = 0.0
	if party != null and touch.visible:
		var hint := party.team_hint()
		if hint != touch.special_hint:
			touch.special_hint = hint
			touch.queue_redraw()
		touch.show_swap = Game.mode == Game.Mode.SOLO
	for s in _seed_slots:
		s.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START and Game.mode != Game.Mode.SOLO):
		toggle_pause()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ pause
func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0.35, 0.2, 0.35, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.position = Vector2(-230, -250)
	_pause.add_child(panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)
	var title := UITheme.label("Pausa", 44, UITheme.INK, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var b1 := Button.new()
	b1.text = "Continuar"
	b1.pressed.connect(toggle_pause)
	col.add_child(b1)
	_quality_btn = Button.new()
	_quality_btn.pressed.connect(_cycle_quality)
	col.add_child(_quality_btn)
	var b3 := Button.new()
	b3.text = "Vibração: " + ("sim" if Game.vibration else "não")
	b3.pressed.connect(func():
		Game.vibration = not Game.vibration
		b3.text = "Vibração: " + ("sim" if Game.vibration else "não")
		Game.save_settings())
	col.add_child(b3)
	var b4 := Button.new()
	b4.text = "Câmera invertida: " + ("sim" if Game.invert_camera else "não")
	b4.pressed.connect(func():
		Game.invert_camera = not Game.invert_camera
		b4.text = "Câmera invertida: " + ("sim" if Game.invert_camera else "não")
		Game.save_settings())
	col.add_child(b4)
	var b5 := Button.new()
	b5.text = "Voltar ao último ponto"
	b5.pressed.connect(func():
		toggle_pause()
		restart_requested.emit())
	col.add_child(b5)
	var b6 := Button.new()
	b6.text = "Menu principal"
	b6.pressed.connect(func():
		get_tree().paused = false
		menu_requested.emit())
	col.add_child(b6)
	_update_quality_text()


func _cycle_quality() -> void:
	Game.set_quality((Game.quality + 1) % 3)
	_update_quality_text()


func _update_quality_text() -> void:
	_quality_btn.text = "Gráficos: " + Game.QUALITY_NAMES[Game.quality]


func toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	_pause.visible = p
	touch.release_all()
	touch.visible = Game.touch_enabled and not p
	Sfx.play("ui_click")
	if p:
		(_pause.get_child(1).get_child(0).get_child(1) as Button).grab_focus()


# ------------------------------------------------------------------ widgets
## Centelha: estrela de 4 pontas que pulsa.
class _MoteIcon extends Control:
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.42 * (1.0 + 0.06 * sin(t * 4.0))
		draw_circle(c, r * 0.9, Color(1.0, 0.88, 0.55, 0.22))
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI * 0.5
			var rr := r if i % 2 == 0 else r * 0.32
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, Color(1.0, 0.93, 0.7))
		draw_circle(c, r * 0.18, Color(1, 1, 1))


## Encaixe de uma Pedra das Horas: gema facetada na cor da relíquia quando cheia.
class _SeedSlot extends Control:
	var filled := false
	var color := Color(1.0, 0.86, 0.45)
	func _draw() -> void:
		var c := size * 0.5
		var t := Time.get_ticks_msec() * 0.001
		var w := size.x * 0.3
		var h := size.y * 0.46
		var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, -h * 0.3), c + Vector2(w * 0.8, h * 0.45),
			c + Vector2(0, h), c + Vector2(-w * 0.8, h * 0.45), c + Vector2(-w, -h * 0.3)])
		if filled:
			draw_circle(c, size.x * (0.62 + 0.05 * sin(t * 3.0)), Color(color.r, color.g, color.b, 0.3))
			draw_colored_polygon(pts, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, -h * 0.3), c]), color.lightened(0.35))
			draw_circle(c + Vector2(-w * 0.35, -h * 0.35), 3.5, Color(1, 1, 1, 0.9))
		else:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.16))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 2.5, true)


## Vida: selo na cor do herói + os 3 pontos do emblema da dupla.
class _Petals extends Control:
	var hero_id := "agile"
	var hero: Node = null
	func _draw() -> void:
		var col := Color("17808e") if hero_id == "agile" else Color("2c5e86")
		draw_circle(Vector2(14, 15), 12, col)
		draw_arc(Vector2(14, 15), 12, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.5, true)
		draw_circle(Vector2(14, 15), 4.0, Color("8ffff2"))
		var n: int = hero.petals if hero != null else 3
		for i in 3:
			var c := Vector2(42 + i * 24, 15)
			var on := i < n
			var d := PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0)])
			draw_colored_polygon(d, Color("8ffff2") if on else Color(1, 1, 1, 0.22))
			if on:
				draw_circle(c, 2.5, Color(1, 1, 1, 0.95))
