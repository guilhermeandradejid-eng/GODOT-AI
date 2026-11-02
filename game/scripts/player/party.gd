class_name SoproParty
extends Node
## A dupla: cria Juba e Caju, distribui controles conforme o modo e cuida da
## câmera. Solo: um herói é seu e o outro segue pela IA (botão Trocar alterna).
## Co-op local: aperte START/A num controle para o jogador 2 entrar (Caju).
## Co-op em rede: cada aparelho controla um herói (SoproNet sincroniza).

signal controlled_changed(hero: Hero)
signal p2_joined

var juba: Hero
var caju: Hero
var camera: CoopCamera
var active: Hero
var p1: InputSources
var p2: InputSources
var p2_hero: Hero
var _join_prev := {}


func setup(parent: Node3D, spawn: Vector3, spawn_yaw: float) -> void:
	juba = Hero.new()
	juba.hero_id = "juba"
	juba.name = "Juba"
	caju = Hero.new()
	caju.hero_id = "caju"
	caju.name = "Caju"
	parent.add_child(juba)
	parent.add_child(caju)
	var right := Vector3(cos(spawn_yaw), 0, -sin(spawn_yaw))
	juba.spawn_offset = -right * 0.9
	caju.spawn_offset = right * 1.1
	juba.teleport(spawn + juba.spawn_offset + Vector3.UP * 0.5, spawn_yaw)
	caju.teleport(spawn + caju.spawn_offset + Vector3.UP * 0.5, spawn_yaw)
	Game.heroes = [juba, caju]
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
			pass   # SoproNet assigns controllers
		_:
			_assign_solo(juba)
	Input.joy_connection_changed.connect(_on_joy)


func _assign_solo(h: Hero) -> void:
	active = h
	var other := caju if h == juba else juba
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
	active = juba
	juba.controller = p1
	juba.player_index = 0
	caju.controller = p2
	caju.player_index = 1
	p2_hero = caju
	camera.targets = [juba, caju]
	camera.shared = true
	controlled_changed.emit(juba)
	p2_joined.emit()
	Game.show_toast("Jogador 2 entrou: Caju!", 2.5)
	Sfx.play("join")


## Rede: este aparelho controla `mine`; o outro herói vira marionete.
func assign_network(mine: Hero, remote_controller: Object) -> void:
	active = mine
	var other := caju if mine == juba else juba
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
	var other := caju if active == juba else juba
	if active.state == Hero.S.RIDE or other.state == Hero.S.RIDE:
		pass
	_assign_solo(other)
	Fx.burst("ring_light", other.global_position + Vector3.UP * 0.4, Color(0.8, 0.7, 1.0), 0.8)
	Sfx.play("swap")
	Game.show_toast("Agora você é %s" % ("o Juba" if other == juba else "o Caju"), 1.6)


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
	var hint := juba.global_position.distance_to(caju.global_position) < 2.4 and juba.state != Hero.S.RIDE


func team_hint() -> bool:
	if juba == null or caju == null:
		return false
	return (juba.global_position.distance_to(caju.global_position) < 2.4 and juba.state != Hero.S.RIDE) \
		or caju.rider != null


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
