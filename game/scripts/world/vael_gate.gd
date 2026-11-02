class_name VaelGate
extends Node3D
## Portão de Vael (objetivo final), ao pé da Agulha de Vael. Cada Pedra das Horas
## coletada acende um encaixe, enche um terço da costura dourada da Agulha e
## avança o sol uma hora. Com as três, chegar ao portão encaixa as pedras e
## começa "A Última Hora": o sol enfim se põe (time-lapse), a música do final
## toca e a câmera orbita a Agulha.

signal finished

var prop: Node3D
var _sockets: Array[Node3D] = []
var _socket_lights: Array[OmniLight3D] = []
var _gems: Array[Node3D] = []
var _ready_to_finish := false
var _done := false


func _ready() -> void:
	prop = PropLib.make("portao_vael", ["glow"])
	add_child(prop)
	PropLib.add_collision(prop, "trimesh", ["Portao"])
	var glow: ShaderMaterial = (prop.get_meta("materials") as Dictionary).get("glow")
	if glow != null:
		glow.set_shader_parameter("active", 0.25)
	for i in 3:
		var s := prop.find_child("socket_%d" % i, true, false) as Node3D
		if s == null:
			s = Node3D.new()
			s.position = Vector3((i - 1) * 3.6, 4.5, 0)
			prop.add_child(s)
		_sockets.append(s)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 0.0
		l.omni_range = 6.0
		l.shadow_enabled = false
		s.add_child(l)
		_socket_lights.append(l)
	_set_seam(0.0, 0.0)
	Game.relic_collected.connect(_on_relic)
	Game.all_relics_collected.connect(func():
		_ready_to_finish = true
		await get_tree().create_timer(3.2, false).timeout
		Game.show_toast("Levem as Pedras das Horas ao Portão de Vael!", 3.5))


func _set_seam(fill: float, dur: float) -> void:
	var m := PropLib.shared_material("seam")
	if dur <= 0.0:
		m.set_shader_parameter("fill", fill)
	else:
		var from := float(m.get_shader_parameter("fill"))
		create_tween().tween_method(func(v: float): m.set_shader_parameter("fill", v), from, fill, dur)


func _on_relic(id: String, total: int) -> void:
	var i := clampi(total - 1, 0, 2)
	var gem := PropLib.make("relic", ["glow"])
	var col: Color = Interactables.Relic.RELIC_COLORS.get(id, Color(1, 0.85, 0.5))
	(gem.get_meta("materials") as Dictionary)["glow"].set_shader_parameter("tint", col)
	gem.scale = Vector3.ONE * 0.9
	gem.position = Vector3(0, -0.4, 0)
	_sockets[i].add_child(gem)
	_gems.append(gem)
	var tw := gem.create_tween().set_loops()
	tw.tween_property(gem, "rotation:y", TAU, 6.0).from(0.0)
	_socket_lights[i].light_color = col
	create_tween().tween_property(_socket_lights[i], "light_energy", 1.8, 1.2)
	_set_seam(total / 3.0 * 0.999, 2.5)
	var atmo = Game.level.get("atmosphere") if Game.level != null else null
	if atmo != null and atmo.has_method("set_hour"):
		atmo.set_hour(total, 5.0)


func _physics_process(_delta: float) -> void:
	if not _ready_to_finish or _done:
		return
	for h in Game.heroes:
		if is_instance_valid(h) and Vector2(h.global_position.x - global_position.x, h.global_position.z - global_position.z).length() < 10.0 \
				and absf(h.global_position.y - global_position.y) < 4.0:
			_finale()
			return


func _finale() -> void:
	_done = true
	Game.start_finale()
	for h in Game.heroes:
		h.set_state(Hero.S.CUTSCENE)
		h.visual.set_happy(1.0)
		h.visual.restart_state("celebrate")
	var cams := get_tree().get_nodes_in_group(&"cameras")
	var cam: CoopCamera = cams[0] if not cams.is_empty() else null
	if cam != null:
		cam.start_cinematic(self, 46.0, 22.0)
	Sfx.music("finale", 2.0)
	for g in _gems:
		Fx.burst("ring_light", g.global_position, Color(1.0, 0.85, 0.6), 2.5)
	get_tree().call_group(&"cameras", &"shake", 0.3)
	Game.vibrate(70)
	_set_seam(1.2, 2.0)
	await get_tree().create_timer(1.6, false).timeout
	var atmo = Game.level.get("atmosphere") if Game.level != null else null
	if atmo != null and atmo.has_method("set_hour"):
		atmo.set_hour(4, 7.0)
	Game.show_toast("A Agulha de Vael volta a marcar as horas...", 3.5)
	await get_tree().create_timer(3.8, false).timeout
	finished.emit()
	Game.show_toast("...e o sol, enfim, se põe sobre Ylvaar.", 3.5)
	await get_tree().create_timer(3.6, false).timeout
	Game.show_toast("Obrigado por jogar o MVP de Ylvaar ♥  Continue explorando!", 5.0)
	if cam != null:
		cam.stop_cinematic()
	for h in Game.heroes:
		h.set_state(Hero.S.AIR)
		h.visual.set_happy(0.0)
