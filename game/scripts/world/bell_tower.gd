class_name BellTower
extends Node3D
## Torre do Grande Sino: três nichos acendem conforme as Sementes de Sopro são
## coletadas; com as três, chegar à praça toca o sino e devolve o vento ao
## mundo (cutscene com câmera orbitando, ondas de luz, pipas e bandeirinhas
## agitadas, música crescendo).

signal wind_returned

var prop: Node3D
var bell: Node3D
var _sockets: Array[Node3D] = []
var _socket_lights: Array[OmniLight3D] = []
var _ready_to_ring := false
var _rung := false
var _swing := 0.0
var _swing_v := 0.0
var _beam: MeshInstance3D


func _ready() -> void:
	prop = PropLib.make("tower", ["glow"])
	add_child(prop)
	PropLib.add_collision(prop, "trimesh")
	var glow: ShaderMaterial = (prop.get_meta("materials") as Dictionary)["glow"]
	glow.set_shader_parameter("active", 0.0)
	for c in prop.get_children():
		if String(c.name).begins_with("socket_"):
			_sockets.append(c)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.5)
			l.light_energy = 0.0
			l.omni_range = 5.0
			l.position = Vector3(0, 0.8, 0)
			c.add_child(l)
			_socket_lights.append(l)
			# each socket needs its own glow material to light up independently
			for mi in PropLib.meshes(c):
				for i in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(i)
					if src != null and src.resource_name == "glow":
						var m := PropLib.shared_material("glow").duplicate() as ShaderMaterial
						m.set_shader_parameter("active", 0.0)
						mi.set_surface_override_material(i, m)
						c.set_meta("glow", m)
	bell = PropLib.make("bell")
	bell.position = Vector3(0, 20.4, 0)
	add_child(bell)
	Game.seed_collected.connect(_on_seed)
	Game.all_seeds_collected.connect(func():
		_ready_to_ring = true
		_show_beam()
		await get_tree().create_timer(3.2, false).timeout
		Game.show_toast("Levem as sementes ao Grande Sino!", 3.5))


func _on_seed(_id: String, total: int) -> void:
	for i in _sockets.size():
		if i < total:
			var m: ShaderMaterial = _sockets[i].get_meta("glow", null)
			if m != null:
				m.set_shader_parameter("active", 1.0)
			create_tween().tween_property(_socket_lights[i], "light_energy", 2.2, 1.0)
			if i == total - 1:
				_add_seed_visual(_sockets[i])


func _add_seed_visual(socket: Node3D) -> void:
	var s := PropLib.make("seed")
	s.scale = Vector3.ONE * 0.6
	s.position = Vector3(0, 0.55, 0)
	socket.add_child(s)
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "rotation:y", TAU, 6.0).from(0.0)


func _show_beam() -> void:
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 2.6
	cyl.height = 60.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam.mesh = cyl
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float fres = 1.0 - abs(dot(NORMAL, VIEW));
	float v = 1.0 - UV.y;
	float flow = 0.6 + 0.4 * sin(UV.y * 30.0 - TIME * 3.0);
	ALBEDO = vec3(1.0, 0.82, 0.5) * (1.0 - fres) * v * v * flow * 0.6;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_beam.material_override = m
	_beam.position = Vector3(0, 30.0, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func _physics_process(delta: float) -> void:
	_swing_v += (-_swing * 6.0 - _swing_v * 0.35) * delta
	_swing += _swing_v * delta
	bell.rotation.x = _swing
	if not _ready_to_ring or _rung:
		return
	for h in Game.heroes:
		if is_instance_valid(h) and Vector2(h.global_position.x - global_position.x, h.global_position.z - global_position.z).length() < 9.0 \
				and absf(h.global_position.y - global_position.y) < 3.0:
			_ring()
			return


func _ring() -> void:
	_rung = true
	Game.ring_bell()
	for h in Game.heroes:
		h.set_state(Hero.S.CUTSCENE)
		h.visual.set_happy(1.0)
	var cams := get_tree().get_nodes_in_group(&"cameras")
	var cam: CoopCamera = cams[0] if not cams.is_empty() else null
	if cam != null:
		cam.start_cinematic(bell, 26.0, -4.0)
	await get_tree().create_timer(1.2, false).timeout
	for k in 3:
		_swing_v += 1.4 if k % 2 == 0 else -1.4
		Sfx.play_at("bell", bell.global_position, 1.0 - k * 0.05, 4.0)
		get_tree().call_group(&"cameras", &"shake", 0.35)
		Fx.burst("ring_light", bell.global_position + Vector3.DOWN * 1.5, Color(1, 0.85, 0.5), 6.0)
		Game.vibrate(70)
		await get_tree().create_timer(1.3, false).timeout
	wind_returned.emit()
	Sfx.music("vento", 3.0)
	Game.show_toast("O Sopro voltou aos Lençóis do Céu!", 4.0)
	await get_tree().create_timer(4.5, false).timeout
	Game.show_toast("Obrigado por jogar o MVP de SOPRO ♥  Continue explorando!", 5.0)
	if cam != null:
		cam.stop_cinematic()
	for h in Game.heroes:
		h.set_state(Hero.S.AIR)
		h.visual.set_happy(0.0)
	if _beam != null:
		create_tween().tween_property(_beam, "scale", Vector3(0.01, 1, 0.01), 2.0)
