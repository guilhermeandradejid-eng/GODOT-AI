class_name GameHUD
extends CanvasLayer
## HUD minimalista (estilo Sky): contador de centelhas, 3 Pedras das Horas, pétalas de vida
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
	var icon := _LumeIcon.new()
	icon.custom_minimum_size = Vector2(44, 44)
	mote_box.add_child(icon)
	_mote_label = UITheme.label("0", 34, Color(1, 1, 1), 700)
	_mote_label.add_theme_color_override("font_outline_color", Color(0.45, 0.25, 0.35, 0.6))
	_mote_label.add_theme_constant_override("outline_size", 8)
	mote_box.add_child(_mote_label)
	# seeds
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
	# petals (health) per hero
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


func _on_seed(_id: String, total: int) -> void:
	for i in _seed_slots.size():
		(_seed_slots[i] as _SeedSlot).filled = i < total
		_seed_slots[i].queue_redraw()


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
class _LumeIcon extends Control:
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.32 * (1.0 + 0.06 * sin(t * 4.0))
		draw_circle(c, r * 1.6, Color(1.0, 0.85, 0.5, 0.25))
		draw_circle(c, r, Color(1.0, 0.92, 0.65))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.9))


class _SeedSlot extends Control:
	var filled := false
	func _draw() -> void:
		var c := size * 0.5
		var t := Time.get_ticks_msec() * 0.001
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			var rx := size.x * 0.36
			var ry := size.y * 0.44
			pts.append(c + Vector2(cos(a) * rx * (0.75 + 0.25 * sin(a)), sin(a) * ry))
		if filled:
			draw_circle(c, size.x * (0.7 + 0.05 * sin(t * 3.0)), Color(1.0, 0.86, 0.45, 0.35))
			draw_colored_polygon(pts, Color(1.0, 0.86, 0.45))
			draw_circle(c + Vector2(-4, -8), 5, Color(1, 1, 1, 0.9))
		else:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.18))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 3.0, true)


class _Petals extends Control:
	var hero_id := "agile"
	var hero: Node = null
	func _draw() -> void:
		var col := Color(1.0, 0.62, 0.2) if hero_id == "agile" else Color(0.72, 0.48, 0.3)
		draw_circle(Vector2(14, 15), 12, col)
		draw_arc(Vector2(14, 15), 12, 0, TAU, 32, Color(1, 1, 1, 0.9), 2.5, true)
		var n: int = hero.petals if hero != null else 3
		for i in 3:
			var c := Vector2(44 + i * 30, 15)
			var on := i < n
			for k in 5:
				var a := TAU * k / 5.0 - PI * 0.5
				draw_circle(c + Vector2(cos(a), sin(a)) * 6.0, 5.5, Color(1.0, 0.55, 0.65, 0.95) if on else Color(1, 1, 1, 0.25))
			draw_circle(c, 4.0, Color(1.0, 0.9, 0.4) if on else Color(1, 1, 1, 0.3))
