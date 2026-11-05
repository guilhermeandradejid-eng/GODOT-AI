class_name HeroParty
extends Node
## A dupla: cria as duas personagens (papéis agile e strong; nomes em HeroDefs),
## distribui controles conforme o modo e cuida da
## câmera. Solo: um herói é seu e o outro segue pela IA (botão Trocar alterna).
## Co-op local: aperte START/A num controle para o jogador 2 entrar (o forte).
## Co-op em rede: cada aparelho controla um herói (NetCoop sincroniza).
## Itens (itens.md 7.2): TROCAR numa placa ou perto de um sino faz o herói
## deixado Segurar Posto; jogando de Hulvar no solo, o USAR e o chip da
## Lanterna viram Pedido para o Sael da IA; DUPLA do líder chama quem segura.

signal controlled_changed(hero: Hero)
signal p2_joined

var agile: Hero
var strong: Hero
var camera: CoopCamera
var active: Hero
var p1: InputSources
var p2: InputSources
var p2_hero: Hero
var _join_prev := {}
var _raw_prev := {}


func setup(parent: Node3D, spawn: Vector3, spawn_yaw: float) -> void:
	agile = Hero.new()
	agile.hero_id = "agile"
	agile.name = HeroDefs.display_name("agile")
	strong = Hero.new()
	strong.hero_id = "strong"
	strong.name = HeroDefs.display_name("strong")
	parent.add_child(agile)
	parent.add_child(strong)
	var right := Vector3(cos(spawn_yaw), 0, -sin(spawn_yaw))
	agile.spawn_offset = -right * 0.9
	strong.spawn_offset = right * 1.1
	agile.teleport(spawn + agile.spawn_offset + Vector3.UP * 0.5, spawn_yaw)
	strong.teleport(spawn + strong.spawn_offset + Vector3.UP * 0.5, spawn_yaw)
	Game.heroes = [agile, strong]
	camera = CoopCamera.new()
	camera.name = "CameraDupla"
	parent.add_child(camera)
	camera.yaw = spawn_yaw + PI
	var schemes: Array[String] = ["kb1", "touch"]
	for d in Input.get_connected_joypads():
		schemes.append("pad:%d" % d)
	p1 = InputSources.new(schemes)
	match Game.mode:
		Game.Mode.LOCAL_COOP:
			_assign_local_coop()
		Game.Mode.NET_HOST, Game.Mode.NET_CLIENT:
			pass   # NetCoop assigns controllers
		_:
			_assign_solo(agile)
	Input.joy_connection_changed.connect(_on_joy)


func _assign_solo(h: Hero) -> void:
	active = h
	var other := strong if h == agile else agile
	h.controller = p1
	h.player_index = 0
	other.controller = CompanionAI.new(h)
	other.player_index = -1
	camera.targets = [h]
	camera.shared = false
	h.intent.clear()
	other.intent.clear()
	controlled_changed.emit(h)


func _assign_local_coop(pad := -1) -> void:
	Game.mode = Game.Mode.LOCAL_COOP
	if pad < 0:
		var pads := Input.get_connected_joypads()
		pad = pads[pads.size() - 1] if not pads.is_empty() else -1
	var s2: Array[String] = []
	if pad >= 0:
		s2.append("pad:%d" % pad)
		p1.schemes.erase("pad:%d" % pad)
	else:
		s2.append("kb2")
	p2 = InputSources.new(s2)
	active = agile
	agile.controller = p1
	agile.player_index = 0
	strong.controller = p2
	strong.player_index = 1
	p2_hero = strong
	camera.targets = [agile, strong]
	camera.shared = true
	controlled_changed.emit(agile)
	p2_joined.emit()
	Game.show_toast("Jogador 2 entrou: %s!" % HeroDefs.display_name("strong"), 2.5)
	Sfx.play("join")


## Rede: este aparelho controla `mine`; o outro herói vira marionete.
func assign_network(mine: Hero, remote_controller: Object) -> void:
	active = mine
	var other := strong if mine == agile else agile
	mine.controller = p1
	mine.player_index = 0
	mine.is_remote = false
	other.controller = remote_controller
	other.player_index = -1
	other.is_remote = true
	camera.targets = [mine]
	camera.shared = false
	controlled_changed.emit(mine)


func swap() -> void:
	if Game.mode != Game.Mode.SOLO:
		return
	var old := active
	var other := strong if active == agile else agile
	if active.state == Hero.S.RIDE or other.state == Hero.S.RIDE:
		pass
	var post := _post_of(old)
	_assign_solo(other)
	Fx.burst("ring_light", other.global_position + Vector3.UP * 0.4, Color(0.8, 0.7, 1.0), 0.8)
	Sfx.play("swap")
	# Segurar Posto: o herói deixado numa placa (ou perto de um sino) fica lá
	if not post.is_empty() and old.controller is CompanionAI:
		(old.controller as CompanionAI).hold_at(old.global_position, String(post["group"]))
		Game.show_toast("Agora você é %s · %s segura o posto" % [HeroDefs.display_name(other.hero_id),
				HeroDefs.display_name(old.hero_id)], 2.2)
	else:
		Game.show_toast("Agora você é %s" % HeroDefs.display_name(other.hero_id), 1.6)


## Posto do herói: placa ocupada (`occupied_by`) ou sino a até 2 m, de grupo
## ainda não resolvido. Devolve {"group": ...} ou {} quando não há posto.
func _post_of(h: Hero) -> Dictionary:
	if h == null or h.state == Hero.S.RIDE:
		return {}
	for p in get_tree().get_nodes_in_group(&"plates"):
		var kind := CompanionAI.lock_kind(p)
		var g := String(p.get("group_id"))
		if CompanionAI.group_done(g):
			continue
		if kind == "plate" and p.occupied_by(h):
			return {"group": g}
		if kind == "chime":
			var d: Vector3 = p.global_position - h.global_position
			var sz = p.get("size")
			var r := 2.0 + 1.2 * (float(sz) - 1.0 if sz != null else 0.0)
			if Vector2(d.x, d.z).length() <= r:
				return {"group": g}
	return {}


## Controlador IA do herói que não é o ativo (solo), ou null.
func companion() -> CompanionAI:
	if active == null:
		return null
	var other := strong if active == agile else agile
	return other.controller as CompanionAI if other.controller is CompanionAI else null


## Borda de subida de um botão lido direto das fontes do P1 (teclado/controle
## pelo estado de `_prev` e toque pelos eventos pendentes). Não depende de o
## herói consumir ou não a intenção (a HeroParty roda antes dos heróis).
func _raw_edge(kind: String, keys: Array) -> bool:
	if p1 == null:
		return false
	var now := false
	var prev = p1.get("_prev")
	if prev is Dictionary:
		for k in prev:
			for suffix in keys:
				if String(k).ends_with(suffix) and prev[k]:
					now = true
	var was: bool = _raw_prev.get(kind, false)
	_raw_prev[kind] = now
	return (now and not was) or (p1.has_scheme("touch") and kind in InputSources.touch_events)


## Solo: DUPLA do líder chama quem segura o posto; de Hulvar, USAR e chip
## viram Pedido para o Sael da IA.
func _solo_requests() -> void:
	var ai := companion()
	var call := _raw_edge("special", ["kb1_special", "_b"])
	var use := _raw_edge("use", ["kb1_use", "_rb"])
	var lamp := _raw_edge("lamp", ["kb1_lamp", "_lb"])
	if ai == null:
		return
	if call:
		ai.on_leader_call()
	if active == strong:
		# o Hulvar não tem itens: limpa a intenção e repassa ao Sael da IA
		active.intent.take("use")
		active.intent.take("lamp")
		if use:
			ai.request_use()
		if lamp:
			ai.request_lamp()


func _on_joy(_device: int, _connected: bool) -> void:
	if Game.mode == Game.Mode.SOLO:
		var schemes: Array[String] = ["kb1", "touch"]
		for d in Input.get_connected_joypads():
			schemes.append("pad:%d" % d)
		p1.schemes = schemes


func _physics_process(_delta: float) -> void:
	if active == null:
		return
	if active.intent.take("swap"):
		swap()
	if Game.mode == Game.Mode.SOLO:
		_solo_requests()
	# local drop-in: START/A on a pad that isn't driving player 1 alone
	if Game.mode == Game.Mode.SOLO:
		var pads := Input.get_connected_joypads()
		for d in pads:
			var pressed := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
			var was: bool = _join_prev.get(d, false)
			_join_prev[d] = pressed
			if pressed and not was and (pads.size() > 1 or Game.touch_enabled):
				_assign_local_coop(d)
				break
		if Input.is_physical_key_pressed(KEY_F2):
			_assign_local_coop(-1)
	# team-up hint (shown on the touch button)
	var hint := agile.global_position.distance_to(strong.global_position) < 2.4 and agile.state != Hero.S.RIDE


func team_hint() -> bool:
	if agile == null or strong == null:
		return false
	return (agile.global_position.distance_to(strong.global_position) < 2.4 and agile.state != Hero.S.RIDE) \
		or strong.rider != null


func _process(delta: float) -> void:
	if camera == null:
		return
	if p1 != null:
		camera.add_look(p1.poll_look(delta))
	if p2 != null and Game.mode == Game.Mode.LOCAL_COOP:
		camera.add_look(p2.poll_look(delta))


func _unhandled_input(event: InputEvent) -> void:
	if p1 == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		p1.mouse_look += (event as InputEventMouseMotion).relative * 0.0045
