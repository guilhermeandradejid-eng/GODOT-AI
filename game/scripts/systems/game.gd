extends Node
## Autoload "Game": estado da partida (coletáveis, relíquias, checkpoints), modo
## de jogo (solo com companheiro IA, co-op local ou co-op em rede), qualidade
## gráfica e configurações salvas em user://settings.cfg.

signal motes_changed(total: int)
signal relic_collected(seed_id: String, total: int)
signal all_relics_collected
signal finale_started
signal toast(text: String, seconds: float)
signal quality_changed(level: int)
signal mode_changed(mode: String)

const SETTINGS := "user://settings.cfg"
const RELICS_TOTAL := 3
const QUALITY_NAMES := ["Baixa", "Média", "Alta"]

enum Mode { SOLO, LOCAL_COOP, NET_HOST, NET_CLIENT }

var mode: int = Mode.SOLO
var motes := 0
var relics: Array[String] = []
var finale_done := false
var quality := 1
var touch_enabled := true
var invert_camera := false
var camera_sensitivity := 1.0
var vibration := true
var music_volume := 0.8
var sfx_volume := 1.0
var level: Node = null              ## fase atual
var heroes: Array = []              ## Hero nodes (agile, strong)
var checkpoint := Vector3.ZERO
var net_peer_hero := ""             ## herói controlado por este peer na rede


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	quality = 1 if is_mobile else 2
	touch_enabled = is_mobile or DisplayServer.is_touchscreen_available()
	_load_settings()
	if is_mobile:
		Engine.max_fps = 60


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func reset_run() -> void:
	motes = 0
	relics.clear()
	finale_done = false
	checkpoint = Vector3.ZERO


func add_motes(n: int) -> void:
	motes += n
	motes_changed.emit(motes)


func collect_relic(seed_id: String) -> void:
	if seed_id in relics:
		return
	relics.append(seed_id)
	relic_collected.emit(seed_id, relics.size())
	if relics.size() >= RELICS_TOTAL:
		all_relics_collected.emit()


func start_finale() -> void:
	if finale_done:
		return
	finale_done = true
	finale_started.emit()


func show_toast(text: String, seconds := 3.0) -> void:
	toast.emit(text, seconds)


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	quality_changed.emit(quality)
	save_settings()


func vibrate(ms: int) -> void:
	if vibration and is_mobile():
		Input.vibrate_handheld(ms)


func hero(id: String) -> Node:
	for h in heroes:
		if is_instance_valid(h) and h.hero_id == id:
			return h
	return null


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return
	quality = int(cf.get_value("video", "quality", quality))
	invert_camera = bool(cf.get_value("input", "invert_camera", invert_camera))
	camera_sensitivity = float(cf.get_value("input", "camera_sensitivity", camera_sensitivity))
	vibration = bool(cf.get_value("input", "vibration", vibration))
	music_volume = float(cf.get_value("audio", "music", music_volume))
	sfx_volume = float(cf.get_value("audio", "sfx", sfx_volume))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "quality", quality)
	cf.set_value("input", "invert_camera", invert_camera)
	cf.set_value("input", "camera_sensitivity", camera_sensitivity)
	cf.set_value("input", "vibration", vibration)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.save(SETTINGS)
