extends Node
## Ferramenta de captura de telas para validar o visual sem abrir o editor.
##
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/capture.tscn -- \
##       --out /tmp/shots --views hero,aerial --frames 40 --size 1280x720
##
## Views: nomes do dicionário VIEWS abaixo ou "px,py,pz>tx,ty,tz".
## Com --player a câmera do jogo é usada (sem câmera de captura).

const LEVEL := "res://game/scenes/level.tscn"
const VIEWS := {
	"hero": [Vector3(-14, 9, 52), Vector3(2, 6, -10)],
	"spawn": [Vector3(4, 5.5, 50), Vector3(0, 4, 20)],
	"aerial": [Vector3(70, 70, 120), Vector3(-10, 0, -20)],
	"lagoon": [Vector3(34, 4.5, 26), Vector3(20, 0.5, 10)],
	"cliff": [Vector3(30, -8, 80), Vector3(0, -10, 0)],
	"sunset": [Vector3(10, 6, 30), Vector3(-30, 14, -60)],
	"east": [Vector3(60, 9, 12), Vector3(112, 6, -10)],
	"north": [Vector3(-2, 10, -40), Vector3(-6, 16, -120)],
	"west": [Vector3(-40, 8, 20), Vector3(-120, 4, 14)],
	"top": [Vector3(0, 260, 1), Vector3(0, 0, 0)],
}

var _out := "user://shots"
var _views: Array = []
var _frames := 40
var _level: Node
var _cam: Camera3D
var _use_player := false
var _bot := ""
var _wait := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		match a:
			"--out": _out = args[i + 1]; i += 1
			"--views": _views = Array(args[i + 1].split(";" if ";" in args[i + 1] else ",")); i += 1
			"--frames": _frames = int(args[i + 1]); i += 1
			"--size":
				var p: PackedStringArray = args[i + 1].split("x")
				get_window().size = Vector2i(int(p[0]), int(p[1]))
				i += 1
			"--player": _use_player = true
			"--bot": _bot = args[i + 1]; i += 1
			"--wait": _wait = float(args[i + 1]); i += 1
		i += 1
	if _views.is_empty():
		_views = ["hero"]
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: PackedScene = load(LEVEL)
	_level = scene.instantiate()
	if _level.has_method("set_capture_mode"):
		_level.call("set_capture_mode", true)
	add_child(_level)
	if not _use_player:
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_cam.far = 3000.0
		add_child(_cam)
	_run.call_deferred()


func _run() -> void:
	if _bot != "":
		await get_tree().process_frame
		var party = _level.get("party")
		if party != null:
			var bot := _CaptureBot.new()
			bot.script_name = _bot
			party.active.controller = bot
	if _wait > 0.0:
		await get_tree().create_timer(_wait).timeout
	for v in _views:
		var view: String = str(v)
		if _cam != null:
			var pair: Array = VIEWS.get(view, [])
			if pair.is_empty() and ">" in view:
				var parts := view.split(">")
				pair = [_parse_v3(parts[0]), _parse_v3(parts[1])]
			if pair.is_empty():
				push_warning("view desconhecida: " + view)
				continue
			_cam.look_at_from_position(pair[0], pair[1])
			_cam.make_current()
		for f in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var safe := view.replace(">", "_").replace(",", "_")
		var path := _out.path_join("%s.png" % safe)
		img.save_png(path)
		var c := get_viewport().get_camera_3d()
		print("CAPTURE ", path, "  cam ", c.global_position if c != null else Vector3.ZERO,
			" -> ", (c.global_position - c.global_transform.basis.z * 10.0) if c != null else Vector3.ZERO)
	get_tree().quit()


func _parse_v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))



## Bot de captura: anda/pula para gerar quadros de ação.
class _CaptureBot extends RefCounted:
	var script_name := "run"
	var t := 0.0
	func poll(intent: PlayerInput, me, delta: float) -> void:
		t += delta
		match script_name:
			"run":
				intent.move = Vector2(0.25 * sin(t * 0.7), -1.0)
				intent.jump = fmod(t, 2.2) < 0.5
				if fmod(t, 2.2) < delta * 1.5:
					intent.press("jump")
			"glide":
				intent.move = Vector2(0.2, -1.0)
				intent.jump = true
				if fmod(t, 3.0) < delta * 1.5 or fmod(t, 3.0) - 0.35 < delta * 1.5 and fmod(t, 3.0) > 0.35:
					intent.press("jump")
			"surf":
				intent.move = Vector2(0.45 * sin(t * 0.9), -1.0)
			"idle":
				intent.move = Vector2.ZERO
