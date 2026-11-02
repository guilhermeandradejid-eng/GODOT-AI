class_name GameLevel
extends Node3D
## Fase "Ylvaar": monta atmosfera, terreno contínuo, conteúdo, heróis, câmera,
## pós-processamento e HUD, e aplica a qualidade gráfica escolhida.

const SPAWN := Vector3(0, 3.2, 38)
const SPAWN_YAW := PI          ## olhando para o norte (Grande Sino)

var atmosphere: Atmosphere
var builder: WorldBuilder
var content: Node3D
var party: HeroParty
var hud: GameHUD
var postfx: PostFX
var capture_mode := false
var menu_mode := false             ## true: câmera orbitando a torre, sem HUD (menu principal)
var kill_y := -30.0


func set_capture_mode(v: bool) -> void:
	capture_mode = v


func _ready() -> void:
	Game.level = self
	get_tree().physics_interpolation = true
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosfera"
	add_child(atmosphere)
	builder = WorldBuilder.new()
	builder.name = "Mundo"
	add_child(builder)
	builder.build(atmosphere)
	kill_y = builder.kill_y
	var content_script := load("res://game/scripts/world/world_content.gd") as GDScript
	if content_script != null:
		content = content_script.new()
		content.name = "Conteudo"
		add_child(content)
		content.call("build", self)
	Game.checkpoint = SPAWN
	party = HeroParty.new()
	party.name = "Dupla"
	add_child(party)
	party.setup(self, SPAWN, SPAWN_YAW)
	postfx = PostFX.new()
	postfx.name = "PosProcesso"
	postfx.sun_direction = atmosphere.sun_direction
	add_child(postfx)
	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(party)
	hud.restart_requested.connect(func():
		for h in Game.heroes:
			h.respawn())
	hud.menu_requested.connect(func(): get_tree().change_scene_to_file("res://game/main.tscn"))
	if capture_mode or menu_mode:
		hud.visible = false
	Game.quality_changed.connect(apply_quality)
	apply_quality(Game.quality)
	party.camera.snap_to_targets.call_deferred()
	Sfx.music("explore")
	if menu_mode:
		_enter_menu.call_deferred()
	elif not capture_mode:
		_intro.call_deferred()


func _enter_menu() -> void:
	var focus: Node3D = null
	for i in 30:
		await get_tree().process_frame
		if content != null and content.get("menu_focus") != null:
			focus = content.get("goal") if content.get("goal") != null else content.get("menu_focus")
			break
	if not menu_mode:
		return
	for h in Game.heroes:
		h.set_state(Hero.S.CUTSCENE)
	if focus != null:
		party.camera.yaw = 2.6
		party.camera.start_cinematic(focus, 34.0, 13.0)


## Sai do menu e começa a jogar (transição suave da câmera, sem carregamento).
func begin_play(mode: int) -> void:
	menu_mode = false
	Game.mode = mode
	if mode == Game.Mode.LOCAL_COOP:
		party._assign_local_coop()
	elif mode == Game.Mode.SOLO:
		party._assign_solo(party.agile)
	for h in Game.heroes:
		h.set_state(Hero.S.AIR)
	party.camera.yaw = SPAWN_YAW + PI
	party.camera.stop_cinematic(true)
	hud.visible = true
	_intro()


func _intro() -> void:
	await get_tree().create_timer(1.2, false).timeout
	Game.show_toast("O tempo parou em Ylvaar, uma hora antes do pôr do sol…", 3.5)
	await get_tree().create_timer(3.8, false).timeout
	Game.show_toast("Encontrem as 3 Pedras das Horas e levem à Agulha de Vael!", 4.0)


func apply_quality(q: int) -> void:
	var vp := get_viewport()
	var e := atmosphere.environment
	match q:
		0:
			vp.scaling_3d_scale = 0.72
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			atmosphere.sun.shadow_enabled = false
			atmosphere.camera_attributes.dof_blur_far_enabled = false
			e.glow_enabled = true
			e.set_glow_level(5, 0.0)
		1:
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			atmosphere.sun.shadow_enabled = true
			atmosphere.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			atmosphere.sun.directional_shadow_max_distance = 45.0
			atmosphere.camera_attributes.dof_blur_far_enabled = false
			e.glow_enabled = true
			e.set_glow_level(5, 0.7)
		_:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			atmosphere.sun.shadow_enabled = true
			atmosphere.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			atmosphere.sun.directional_shadow_max_distance = 80.0
			atmosphere.camera_attributes.dof_blur_far_enabled = true
			e.glow_enabled = true
			e.set_glow_level(5, 0.7)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	postfx.set_quality(q)
	Fx.set_quality(q)
	builder.set_quality(q)
	if content != null and content.has_method("set_quality"):
		content.call("set_quality", q)


func _process(_delta: float) -> void:
	if not Game.heroes.is_empty() and is_instance_valid(Game.heroes[0]):
		builder.follow_player((Game.heroes[0] as Node3D).global_position)
