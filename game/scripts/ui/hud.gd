class_name GameHUD
extends CanvasLayer
## HUD minimalista (estilo Sky): contador de centelhas, 3 Pedras das Horas, losangos de vida
## de cada herói, avisos que aparecem e somem, controles de toque e pausa.
## Itens (itens.md 3.4): retículo no alvo do arpéu, faixa de item novo, ícones das
## ferramentas ao lado das Pedras das Horas; avisos de trava chegam pelo Game.toast.

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
var _items_box: HBoxContainer
var _item_icons := {}             ## id -> _ItemIcon
var _reticle: _Reticle
var _banner: PanelContainer
var _banner_icon: _ItemIcon
var _banner_title: Label
var _banner_lines: Label
var _banner_t := 0.0
var _banner_queue: Array[String] = []
const BANNER_TIME := 4.0


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
	# ferramentas obtidas, logo à direita das Pedras das Horas
	_items_box = HBoxContainer.new()
	_items_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_items_box.position = Vector2(92, 31)
	_items_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items_box.add_theme_constant_override("separation", 6)
	_root.add_child(_items_box)
	for id in Game.ITEM_IDS:
		var ic := _ItemIcon.new()
		ic.item = id
		ic.custom_minimum_size = Vector2(34, 34)
		ic.visible = Game.has_item(id)
		_items_box.add_child(ic)
		_item_icons[id] = ic
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
	_build_banner()
	# retículo do arpéu (atrás dos controles de toque)
	_reticle = _Reticle.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reticle)
	# touch
	touch = TouchControls.new()
	touch.visible = Game.touch_enabled
	touch.pause_requested.connect(toggle_pause)
	_root.add_child(touch)
	_build_pause()
	Game.motes_changed.connect(_on_motes)
	Game.relic_collected.connect(_on_seed)
	Game.toast.connect(show_toast)
	Game.item_collected.connect(_on_item)


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
	_update_tools(delta)
	_update_banner(delta)
	for s in _seed_slots:
		s.queue_redraw()


# ------------------------------------------------------------------ itens
## Item novo: ícone ao lado das Pedras, faixa de 4 s e os dois heróis comemoram.
func _on_item(id: String) -> void:
	var ic: _ItemIcon = _item_icons.get(id)
	if ic != null:
		ic.visible = true
		ic.pop = 1.0
	_banner_queue.append(id)
	Sfx.play("item_get" if Sfx.has("item_get") else "relic")
	if party == null:
		return
	for h in [party.agile, party.strong]:
		if h == null or not is_instance_valid(h) or h.visual == null or h.is_remote:
			continue
		if h.state == Hero.S.GROUND and h.visual.has_state("celebrate"):
			h.visual.restart_state("celebrate")


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UITheme.box(Color(1.0, 0.96, 0.9, 0.9), 26, Color(0.83, 0.64, 0.25, 0.95), 3))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.custom_minimum_size = Vector2(560, 0)
	_banner.position = Vector2(-280, 160)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	_banner.visible = false
	_root.add_child(_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	_banner_icon = _ItemIcon.new()
	_banner_icon.custom_minimum_size = Vector2(72, 72)
	_banner_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_banner_icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_banner_title = UITheme.label("", 30, UITheme.INK, 700)
	col.add_child(_banner_title)
	_banner_lines = UITheme.label("", 21, UITheme.INK.lightened(0.15), 500)
	_banner_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_banner_lines)


func _update_banner(delta: float) -> void:
	delta = minf(delta, 0.1)        # um engasgo de carregamento não engole a faixa
	if _banner_t <= 0.0 and not _banner_queue.is_empty():
		var id: String = _banner_queue.pop_front()
		var info: Dictionary = Game.ITEM_INFO.get(id, {})
		_banner_icon.item = id
		_banner_icon.queue_redraw()
		_banner_title.text = "Você encontrou: " + Game.item_name(id)
		_banner_lines.text = "\n".join(PackedStringArray(info.get("lines", [])))
		_banner_t = BANNER_TIME
		_banner.visible = true
		_banner.pivot_offset = _banner.size * 0.5
	if _banner_t <= 0.0:
		_banner.visible = false
		return
	_banner_t -= delta
	var age := BANNER_TIME - _banner_t
	# entra com escala elástica, sai com fade
	_banner.modulate.a = clampf(minf(age * 5.0, _banner_t / 0.4), 0.0, 1.0)
	var k := clampf(age / 0.35, 0.0, 1.0)
	_banner.scale = Vector2.ONE * lerpf(0.85, 1.0, k) * (1.0 + 0.06 * sin(k * PI))


## Herói ágil controlado neste aparelho (ou o Sael da IA no solo, para o Pedido).
func _local_agile() -> Hero:
	if party == null or party.agile == null or not is_instance_valid(party.agile):
		return null
	if party.agile.is_remote:
		return null
	return party.agile


## Botões de item visíveis? No co-op, quem joga de Hulvar não os vê; no solo
## jogando de Hulvar eles continuam (mandam o Sael da IA agir, itens.md 7.2).
func _items_for_me() -> bool:
	if party == null:
		return true
	if Game.mode == Game.Mode.SOLO:
		return true
	return party.active != null and party.active.hero_id == "agile"


func _update_tools(_delta: float) -> void:
	var sael := _local_agile()
	var tools: Object = sael.get("tools") if sael != null else null
	var tgt := _tool_target(sael, tools)
	var mine := _items_for_me()
	# retículo: só para quem joga com o Sael (no solo de Hulvar, mostra a mira do Pedido)
	if mine and not tgt.is_empty():
		_reticle.set_target(tgt["pos"], float(tgt["dist"]), float(tgt["range"]), _perfect_window(sael, tools))
	else:
		_reticle.clear_target()
	if touch == null or not touch.visible:
		return
	var su := mine and (Game.has_item("arpeu") or Game.has_item("concha"))
	var sl := mine and Game.has_item("lanterna")
	var icon := "hook" if not tgt.is_empty() else ("shell" if Game.has_item("concha") else "empty")
	var lit := Game.lantern_lit()
	if tools != null and tools.get("lamp_on") is bool:
		lit = tools.get("lamp_on")
	var hint := false
	if tools != null and tools.get("puzzle_hint") is bool:
		hint = tools.get("puzzle_hint")
	elif not tgt.is_empty():
		hint = float(tgt.get("dist", INF)) <= 10.0 and not (str(tgt.get("kind", "")) in ["hulvar", "strong", "hero", "enemy", "silente"])
	if su != touch.show_use or sl != touch.show_lamp or icon != touch.use_icon or lit != touch.lamp_on or hint != touch.use_hint:
		touch.show_use = su
		touch.show_lamp = sl
		touch.use_icon = icon
		touch.lamp_on = lit
		touch.use_hint = su and hint
		touch.queue_redraw()


## Lê o alvo travado do HeroTools sem depender da forma exata: aceita um método
## `reticle_target()` / `get_target()`, ou a propriedade `target` como Dictionary
## (`pos`/`point`/`position`/`node`, `kind`, `range`) ou Node3D.
## Devolve {} sem alvo, ou {pos, dist, range, kind, perfect}.
func _tool_target(sael: Hero, tools: Object) -> Dictionary:
	if sael == null or tools == null:
		return {}
	var t: Variant = null
	for m in ["reticle_target", "get_target"]:
		if tools.has_method(m):
			t = tools.call(m)
			break
	if t == null:
		for prop in ["target", "locked", "_target"]:
			var v: Variant = tools.get(prop)
			if v != null:
				t = v
				break
	var out := {}
	var node: Variant = null
	if t is Dictionary:
		var d: Dictionary = t
		if d.is_empty():
			return {}
		for k in ["pos", "point", "position", "at"]:
			if d.get(k) is Vector3:
				out["pos"] = d[k]
				break
		node = d.get("node", d.get("target"))
		out["kind"] = str(d.get("kind", d.get("type", d.get("class", ""))))
		var rg: Variant = d.get("range", d.get("reach"))
		if rg != null:
			out["range"] = float(rg)
	elif t is Node3D:
		node = t
	elif t is Vector3:
		out["pos"] = t
	if not out.has("pos") and node is Node3D and is_instance_valid(node):
		out["pos"] = (node as Node3D).global_position
	if not out.has("pos"):
		return {}
	var p: Vector3 = out["pos"]
	if not p.is_finite():
		return {}
	if node is Hero and str(out.get("kind", "")) == "":
		out["kind"] = "hulvar"
	out["dist"] = sael.global_position.distance_to(p)
	if not out.has("range"):
		out["range"] = 14.0
	return out


## Janela de soltura perfeita do balanço (θ 35°–55°): o retículo pisca dourado.
func _perfect_window(sael: Hero, tools: Object) -> bool:
	for o in [tools, sael]:
		if o == null:
			continue
		if o.has_method("in_perfect_window"):
			return bool(o.call("in_perfect_window"))
		var v: Variant = o.get("perfect_window")
		if v is bool:
			return v
	return false


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



## Ícone de ferramenta (ao lado das Pedras e na faixa): arpéu, bastão, lanterna ou concha.
class _ItemIcon extends Control:
	var item := "arpeu"
	var pop := 0.0
	func _process(d: float) -> void:
		if pop > 0.0:
			pop = maxf(0.0, pop - d * 1.5)
			queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var brass := Color(0.83, 0.64, 0.25)
		var col: Color = Game.ITEM_INFO.get(item, {}).get("color", brass)
		var k := 1.0 + 0.35 * pop
		draw_circle(c, r * 0.95 * k, Color(col.r, col.g, col.b, 0.22 + 0.4 * pop))
		draw_arc(c, r * 0.95 * k, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
		var w := maxf(1.5, r * 0.11)
		r *= 0.62
		match item:
			"arpeu":
				draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.5), brass, w, true)
				draw_arc(c + Vector2(-r * 0.42, r * 0.42), r * 0.42, 0.0, PI * 0.75, 10, brass, w, true)
				draw_arc(c + Vector2(r * 0.42, r * 0.42), r * 0.42, PI * 0.25, PI, 10, brass, w, true)
				draw_arc(c + Vector2(0, -r * 0.75), r * 0.3, 0, TAU, 12, Color(0.55, 0.27, 0.2), w * 0.8, true)
			"bastao":
				var a := c + Vector2(-r, r)
				var b := c + Vector2(r, -r)
				draw_line(a, b, Color(0.93, 0.86, 0.70), w * 1.6, true)
				draw_line(b.lerp(a, 0.12), b, brass, w * 1.8, true)
				for f in [0.68, 0.76, 0.84]:
					var q := b.lerp(a, f)
					draw_circle(q, w * 0.9, Color(0.55, 0.4, 0.25))
			"lanterna":
				draw_circle(c + Vector2(0, r * 0.1), r * 0.8, Color(1.0, 0.86, 0.55, 0.35))
				draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.5), Vector2(r * 0.9, r * 1.15)), Color(1.0, 0.71, 0.35))
				draw_circle(c + Vector2(0, r * 0.12), r * 0.2, Color(1, 0.97, 0.85))
				draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.62), Vector2(r * 1.2, r * 0.16)), brass)
				draw_rect(Rect2(c + Vector2(-r * 0.6, r * 0.62), Vector2(r * 1.2, r * 0.16)), brass)
				draw_arc(c + Vector2(0, -r * 0.62), r * 0.38, PI, TAU, 12, brass, w * 0.8, true)
			"concha":
				var pts := PackedVector2Array()
				for i in 36:
					var t := float(i) / 35.0
					var an := t * TAU * 2.6
					pts.append(c + Vector2(cos(an), sin(an)) * r * (0.12 + 0.88 * t))
				draw_circle(c, r * 0.95, Color(0.98, 0.8, 0.82))
				draw_polyline(pts, Color(0.62, 0.36, 0.42), w, true)
				draw_circle(c + Vector2(r * 0.95, 0), r * 0.22, brass)
			_:
				draw_circle(c, r * 0.5, col)


## Retículo do arpéu: losango de latão de 24 px projetado no alvo travado, com um
## arco fino de alcance (cheio = perto; vazio = no limite). Pisca dourado na
## janela de soltura perfeita.
class _Reticle extends Control:
	var _has := false
	var _world := Vector3.ZERO
	var _screen := Vector2.ZERO
	var _shown := 0.0
	var _dist := 0.0
	var _range := 14.0
	var perfect := false
	var _t := 0.0
	func set_target(p: Vector3, dist: float, rng: float, is_perfect: bool) -> void:
		if not _has or p.distance_to(_world) > 3.0:
			_shown = 0.0        # alvo novo: entra com um pequeno "zoom"
		_has = true
		_world = p
		_dist = dist
		_range = maxf(rng, 0.1)
		perfect = is_perfect
	func clear_target() -> void:
		_has = false
		perfect = false
	func _process(d: float) -> void:
		_t += d
		var cam := get_viewport().get_camera_3d()
		var on := _has and cam != null and not cam.is_position_behind(_world)
		if on:
			var sp := cam.unproject_position(_world)
			_screen = sp if _shown <= 0.0 or _screen.distance_to(sp) > 160.0 else _screen.lerp(sp, 1.0 - exp(-30.0 * d))
			_shown = minf(1.0, _shown + d * 7.0)
		else:
			_shown = maxf(0.0, _shown - d * 8.0)
		if _shown > 0.0 or on:
			queue_redraw()
	func _draw() -> void:
		if _shown <= 0.0:
			return
		var s := clampf(get_viewport_rect().size.y / 720.0, 0.75, 1.6)
		var a := _shown
		var col := Color(0.83, 0.64, 0.25)
		if perfect:
			var f := 0.5 + 0.5 * sin(_t * 30.0)
			col = Color(1.0, 0.84, 0.3).lerp(Color(1, 1, 0.85), f)
		var hr := 12.0 * s * (1.6 - 0.6 * a) * (1.15 if perfect else 1.0)   # 24 px de altura
		var c := _screen
		var d := PackedVector2Array([c + Vector2(0, -hr), c + Vector2(hr * 0.8, 0), c + Vector2(0, hr), c + Vector2(-hr * 0.8, 0)])
		draw_colored_polygon(d, Color(col.r, col.g, col.b, 0.35 * a))
		d.append(d[0])
		draw_polyline(d, Color(0.2, 0.12, 0.08, 0.5 * a), 4.5 * s, true)
		draw_polyline(d, Color(col.r, col.g, col.b, a), 2.5 * s, true)
		draw_circle(c, 2.5 * s, Color(1, 1, 1, 0.95 * a))
		# arco de alcance
		var rr := hr + 9.0 * s
		var frac := clampf(1.0 - _dist / _range, 0.0, 1.0)
		draw_arc(c, rr, 0, TAU, 40, Color(1, 1, 1, 0.18 * a), 1.5 * s, true)
		if frac > 0.01:
			draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, Color(col.r, col.g, col.b, 0.9 * a), 2.0 * s, true)
