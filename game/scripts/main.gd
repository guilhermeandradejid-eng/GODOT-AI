extends Node
## Cena principal: o mundo roda ao fundo (câmera orbitando a Torre do Sino) e
## o menu fica por cima. "Jogar" desce a câmera até a dupla sem carregamento.

const LEVEL := preload("res://game/scenes/level.tscn")

var level: SoproLevel
var ui: CanvasLayer
var _root: Control
var _main_panel: Control
var _sub_panel: PanelContainer
var _quality_btn: Button
var _net: Node


func _ready() -> void:
	Game.reset_run()
	level = LEVEL.instantiate()
	level.menu_mode = true
	add_child(level)
	_build_ui()
	level.postfx.set_fade(1.0)
	var tw := create_tween()
	tw.tween_method(level.postfx.set_fade, 1.0, 0.0, 2.2).set_delay(0.2)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = SoproTheme.theme()
	ui.add_child(_root)
	# soft gradient behind the title for legibility
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.92, 0.88, 0.0))
	g.set_color(1, Color(0.42, 0.24, 0.4, 0.38))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.8, 0.0)
	gt.fill_to = Vector2(0.0, 0.0)
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(grad)

	_main_panel = VBoxContainer.new()
	_main_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_main_panel.offset_left = 70
	_main_panel.offset_top = 60
	_main_panel.offset_right = 560
	_main_panel.add_theme_constant_override("separation", 12)
	_root.add_child(_main_panel)
	var title := SoproTheme.label("SOPRO", 124, Color(1.0, 0.97, 0.92), 700)
	title.add_theme_color_override("font_outline_color", Color(0.55, 0.3, 0.45, 0.55))
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_shadow_color", Color(0.4, 0.15, 0.35, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 6)
	_main_panel.add_child(title)
	var sub := SoproTheme.label("Juba & Caju nos Lençóis do Céu", 30, Color(1.0, 0.95, 0.9), 600)
	sub.add_theme_color_override("font_outline_color", Color(0.5, 0.28, 0.42, 0.5))
	sub.add_theme_constant_override("outline_size", 8)
	_main_panel.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	_main_panel.add_child(spacer)
	_button("Jogar", func(): _start(Game.Mode.SOLO), true)
	_button("Co-op local (2 jogadores)", _coop_local_panel)
	_button("Co-op na rede (Wi-Fi)", _net_panel)
	_quality_btn = _button("Gráficos: " + Game.QUALITY_NAMES[Game.quality], func():
		Game.set_quality((Game.quality + 1) % 3)
		_quality_btn.text = "Gráficos: " + Game.QUALITY_NAMES[Game.quality])
	_button("Créditos", _credits)
	if not Game.is_mobile():
		_button("Demos da Vibe Suite", func(): get_tree().change_scene_to_file("res://demos/demo_hub.tscn"))
		_button("Sair", func(): get_tree().quit())
	var hint := SoproTheme.label("Toque e arraste à esquerda para andar • Botões à direita para pular, agir e trocar de herói", 18, Color(1, 1, 1, 0.85), 500)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-520, -54)
	hint.size = Vector2(1040, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not Game.touch_enabled:
		hint.text = "WASD andar • Espaço pular (segure para planar) • J ação • K/E dupla • Tab trocar • botão direito do mouse gira a câmera"
	_root.add_child(hint)


func _button(text: String, cb: Callable, focus := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func():
		Sfx.play("ui_click")
		cb.call())
	_main_panel.add_child(b)
	if focus:
		b.grab_focus.call_deferred()
	return b


func _start(mode: int) -> void:
	_close_sub()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): ui.visible = false)
	level.begin_play(mode)


func _close_sub() -> void:
	if _sub_panel != null:
		_sub_panel.queue_free()
		_sub_panel = null


func _panel(title_text: String) -> VBoxContainer:
	_close_sub()
	_sub_panel = PanelContainer.new()
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_sub_panel.custom_minimum_size = Vector2(560, 0)
	_sub_panel.position = Vector2(-640, -240)
	_root.add_child(_sub_panel)
	var col := VBoxContainer.new()
	_sub_panel.add_child(col)
	var t := SoproTheme.label(title_text, 36, SoproTheme.INK, 700)
	col.add_child(t)
	return col


func _text(col: VBoxContainer, s: String, size := 22) -> void:
	var l := SoproTheme.label(s, size, SoproTheme.INK, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	col.add_child(l)


func _coop_local_panel() -> void:
	var col := _panel("Co-op local")
	_text(col, "Jogador 1 é o Juba (toque na tela, teclado ou controle). Jogador 2 é o Caju: conecte um controle (Bluetooth no celular) e aperte START.")
	_text(col, "Juntos: o Juba sobe nas costas do Caju (botão DUPLA) e o Caju pode lançá-lo longe. Placas pesadas só descem com o Caju!", 20)
	var b := Button.new()
	b.text = "Começar em dupla"
	b.pressed.connect(func(): _start(Game.Mode.LOCAL_COOP))
	col.add_child(b)
	var c := Button.new()
	c.text = "Voltar"
	c.pressed.connect(_close_sub)
	col.add_child(c)


func _net_panel() -> void:
	var col := _panel("Co-op na rede (Wi-Fi)")
	if not ClassDB.class_exists("ENetMultiplayerPeer"):
		_text(col, "Rede indisponível nesta build.")
		return
	_text(col, "Os dois aparelhos precisam estar na mesma rede Wi-Fi. Quem cria a sala joga com o Juba; quem entra joga com o Caju.", 20)
	var status := SoproTheme.label("", 20, SoproTheme.TEAL, 600)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(500, 0)
	var host := Button.new()
	host.text = "Criar sala"
	col.add_child(host)
	var find := Button.new()
	find.text = "Procurar salas"
	col.add_child(find)
	var list := VBoxContainer.new()
	col.add_child(list)
	col.add_child(status)
	var back := Button.new()
	back.text = "Voltar"
	back.pressed.connect(func():
		if _net != null:
			_net.call("stop")
		_close_sub())
	col.add_child(back)
	_net = _ensure_net()
	host.pressed.connect(func():
		var ip: String = _net.call("host")
		status.text = "Sala criada em %s — esperando o Caju entrar..." % ip)
	find.pressed.connect(func():
		status.text = "Procurando salas na rede..."
		_net.call("discover"))
	_net.connect("hosts_changed", func(hosts: Array):
		for c in list.get_children():
			c.queue_free()
		for h in hosts:
			var jb := Button.new()
			jb.text = "Entrar: " + str(h)
			jb.pressed.connect(func():
				status.text = "Conectando a %s..." % str(h)
				_net.call("join", str(h)))
			list.add_child(jb)
		if hosts.is_empty():
			status.text = "Nenhuma sala encontrada ainda.")
	_net.connect("connected", func(as_host: bool):
		status.text = "Conectado!"
		_start(Game.Mode.NET_HOST if as_host else Game.Mode.NET_CLIENT)
		_net.call("start_game", level))
	_net.connect("failed", func(msg: String): status.text = msg)


func _ensure_net() -> Node:
	if _net != null:
		return _net
	var script := load("res://game/scripts/net/sopro_net.gd") as GDScript
	_net = script.new()
	_net.name = "Rede"
	get_tree().root.add_child(_net)
	return _net


func _credits() -> void:
	var col := _panel("Créditos")
	_text(col, "SOPRO — MVP de aventura co-op feito com Godot 4.7 + Blender (tudo gerado por código neste repositório).", 20)
	_text(col, "Personagens, mundo, props, shaders, texturas, efeitos, sons e músicas: criação original (CC0).", 18)
	_text(col, "Fonte Fredoka — Milena Brandão & Hafontia (SIL OFL 1.1). Texturas de ruído e água: Godot Vibe Suite (CC0).", 18)
	_text(col, "Inspirações: o brilho da areia de Journey/Sky (thatgamecompany), plataforma co-op clássica e os Lençóis Maranhenses.", 18)
	var c := Button.new()
	c.text = "Voltar"
	c.pressed.connect(_close_sub)
	col.add_child(c)
