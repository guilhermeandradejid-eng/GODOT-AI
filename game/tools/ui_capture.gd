extends Node
## Captura o menu principal e o HUD com controles de toque (como no celular),
## e mede o custo de renderização (draw calls, primitivas) em vistas de jogo.
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/ui_capture.tscn -- --out DIR

var _out := "user://ui"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--out" in args:
		_out = args[args.find("--out") + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	Game.touch_enabled = true
	Game.quality = 1
	var main: Node = load("res://game/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred(main)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("SHOT ", name)


func _stats(tag: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("STATS %s draw_calls=%d primitives=%d objects=%d" % [tag, dc, prim, obj])


func _run(main: Node) -> void:
	for i in 90:
		await get_tree().process_frame
	await _shot("menu")
	await _stats("menu")
	main.call("_start", Game.Mode.SOLO)
	for i in 150:
		await get_tree().process_frame
	await _shot("hud")
	await _stats("play_spawn")
	var level = main.get("level")
	var h: Hero = level.party.agile
	h.teleport(Vector3(4, 5, 4), PI)
	for i in 40:
		await get_tree().process_frame
	await _stats("play_center")
	await _shot("hud_center")
	get_tree().quit()
