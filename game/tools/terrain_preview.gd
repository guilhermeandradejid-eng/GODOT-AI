extends Node3D
## Prévia do terreno contínuo + areia (sem jogo): captura vistas fixas.
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/terrain_preview.tscn -- --out DIR --views a,b

const SAND := preload("res://game/shaders/sand_terrain.gdshader")
const NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")
const VIEWS := {
	"dunes": [Vector3(40, 30, 160), Vector3(-40, 10, 40)],
	"low": [Vector3(10, 8, 120), Vector3(-30, 6, 60)],
	"sunward": [Vector3(60, 20, 80), Vector3(-200, 10, -200)],
	"aerial": [Vector3(300, 220, 420), Vector3(0, 0, 0)],
	"close": [Vector3(4, 5, 40), Vector3(0, 2, 30)],
	"horizon": [Vector3(0, 40, 470), Vector3(0, 20, 900)],
}
var _out := "user://terrain"
var _views: Array = ["dunes"]
var terrain: SandTerrain
var cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--out" in args:
		_out = args[args.find("--out") + 1]
	if "--views" in args:
		_views = Array(args[args.find("--views") + 1].split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	var atmo := SoproAtmosphere.new()
	add_child(atmo)
	var mat := ShaderMaterial.new()
	mat.shader = SAND
	mat.set_shader_parameter("noise_tex", NOISE)
	terrain = SandTerrain.new()
	terrain.data_dir = "res://game/world/aurelith_terrain"
	terrain.material = mat
	add_child(terrain)
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.fov = 60.0
	add_child(cam)
	var post := SoproPostFX.new()
	post.sun_direction = atmo.sun_direction
	add_child(post)
	_run.call_deferred()

func _run() -> void:
	for v in _views:
		var pair: Array = VIEWS[v]
		cam.look_at_from_position(pair[0], pair[1])
		cam.make_current()
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join(v + ".png"))
		print("SHOT ", v)
	get_tree().quit()
