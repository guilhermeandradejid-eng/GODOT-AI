extends Node
## Autoload "Sfx": efeitos sonoros (gerados proceduralmente por
## game/tools/gen_audio.py) com pool de players 3D/2D, notas pentatônicas para
## sinos e lumes, e trilha ambiente com crossfade.

const SFX_DIR := "res://game/assets/audio/sfx"
## Lista de reserva (caso a listagem do diretório não funcione num build exportado).
const SFX_NAMES := ["bell", "bounce", "bump", "call", "checkpoint", "chime", "enemy_poof", "flower_load",
	"gate_open", "grind_start", "hurt_strong", "hurt_agile", "join", "jump2", "jump_strong", "jump_agile", "land",
	"launch", "lume", "mount", "plate_off", "plate_on", "portal", "pound", "respawn", "reveal", "seed", "spin",
	"splash", "step", "superjump", "surf", "surf_start", "swap", "ui_click", "whoosh"]
const MUSIC_DIR := "res://game/assets/audio/music"
## Pentatônica maior de Dó (C D E G A) em duas oitavas, como razão de pitch.
const PENTA := [1.0, 1.1225, 1.2599, 1.4983, 1.6818, 2.0, 2.2449, 2.5198]

var _streams := {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music2: AudioStreamPlayer
var _loops := {}
var _note_i := 0
var _note_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for path in ResourceLoader.list_directory(SFX_DIR):
		var file: String = path
		if file.ends_with("/"):
			continue
		var id := file.get_basename()
		var res := load(SFX_DIR.path_join(file))
		if res is AudioStream:
			_streams[id] = res
	for id in SFX_NAMES:
		if not _streams.has(id):
			var path := SFX_DIR.path_join(id + ".wav")
			if ResourceLoader.exists(path):
				_streams[id] = load(path)
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Master"
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 12000.0
		add_child(p)
		_pool3d.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool2d.append(p)
	_music = AudioStreamPlayer.new()
	_music2 = AudioStreamPlayer.new()
	add_child(_music)
	add_child(_music2)


func has(id: String) -> bool:
	return _streams.has(id)


func count() -> int:
	return _streams.size()


func play_at(id: String, pos: Vector3, pitch := 1.0, vol_db := 0.0) -> void:
	var s: AudioStream = _streams.get(id)
	if s == null:
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool3d:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool3d[0]
		_pool3d.push_back(_pool3d.pop_front())
	best.stream = s
	best.global_position = pos
	best.pitch_scale = pitch
	best.volume_db = vol_db + linear_to_db(maxf(Game.sfx_volume, 0.001))
	best.play()


func play(id: String, pitch := 1.0, vol_db := 0.0) -> void:
	var s: AudioStream = _streams.get(id)
	if s == null:
		return
	for p in _pool2d:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = vol_db + linear_to_db(maxf(Game.sfx_volume, 0.001))
			p.play()
			return


## Nota musical ascendente para sequências de coleta (lumes em fila soam como melodia).
func play_note(id: String, pos: Vector3, vol_db := -4.0) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _note_t > 1.2:
		_note_i = 0
	_note_t = now
	play_at(id, pos, PENTA[_note_i % PENTA.size()], vol_db)
	_note_i += 1


func play_chime(pos: Vector3, idx: int) -> void:
	play_at("chime", pos, PENTA[idx % PENTA.size()] * 0.5, -2.0)


func loop(id: String, on: bool, pos := Vector3.ZERO, vol_db := -8.0) -> void:
	var p: AudioStreamPlayer3D = _loops.get(id)
	if on:
		if p == null:
			var s: AudioStream = _streams.get(id)
			if s == null:
				return
			p = AudioStreamPlayer3D.new()
			p.stream = s
			p.unit_size = 8.0
			add_child(p)
			_loops[id] = p
		p.global_position = pos
		p.volume_db = vol_db
		if not p.playing:
			p.play()
	elif p != null and p.playing:
		p.stop()


func music(id: String, fade := 2.0) -> void:
	var path := MUSIC_DIR.path_join(id + ".ogg")
	if not ResourceLoader.exists(path):
		return
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if _music.stream == s and _music.playing:
		return
	var old := _music
	_music = _music2
	_music2 = old
	_music.stream = s
	_music.volume_db = -40.0
	_music.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music, "volume_db", linear_to_db(maxf(Game.music_volume, 0.001)) - 6.0, fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.chain().tween_callback(old.stop)


func set_music_volume(v: float) -> void:
	Game.music_volume = v
	if _music.playing:
		_music.volume_db = linear_to_db(maxf(v, 0.001)) - 6.0
