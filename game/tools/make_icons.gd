extends Node3D
## Gera os ícones do app (Android) renderizando a Saeli com os shaders do jogo.
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/make_icons.tscn
## Saída: game/assets/icons/icon_512.png, icon_192.png, icon_fg_432.png (fundo
## transparente), icon_bg_432.png (céu e duna) e icon_mono_432.png (silhueta).

const OUT := "res://game/assets/icons"

var _vis: HeroVisual
var _cam: Camera3D
var _env: WorldEnvironment


func _ready() -> void:
	get_window().size = Vector2i(864, 864)
	get_viewport().transparent_bg = true
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.95)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	_env.environment = e
	add_child(_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-35, -150, 0)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.7, 0.85, 1.0)
	rim.light_energy = 0.6
	rim.rotation_degrees = Vector3(-10, 20, 0)
	add_child(rim)
	_vis = HeroVisual.new()
	_vis.hero = "agile"
	add_child(_vis)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _run() -> void:
	for f in 6:
		await get_tree().process_frame
	if _vis.tree != null:
		_vis.tree.active = false
	if _vis.anim != null:
		_vis.anim.active = true
		_vis.anim.play("idle")
		_vis.anim.seek(0.0, true)
		_vis.anim.pause()
	_vis.set_happy(0.0)
	var head := Vector3(0, 0.72, 0)
	var sk := _vis.skeleton
	if sk != null and sk.find_bone("head") >= 0:
		head = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin + Vector3(0, 0.12, 0)
	_cam.look_at_from_position(head + Vector3(0.28, 0.06, 1.0).normalized() * 1.05, head)
	for f in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var fg := get_viewport().get_texture().get_image()
	fg.convert(Image.FORMAT_RGBA8)
	var bg := _background(fg.get_width())
	var full := bg.duplicate() as Image
	full.blend_rect(fg, Rect2i(Vector2i.ZERO, fg.get_size()), Vector2i.ZERO)
	_save(full, "icon_512.png", 512)
	_save(full, "icon_192.png", 192)
	# adaptive: the safe zone is the inner 66% -> shrink the character a little
	var fg_pad := Image.create(fg.get_width(), fg.get_height(), false, Image.FORMAT_RGBA8)
	var small := fg.duplicate() as Image
	small.resize(int(fg.get_width() * 0.78), int(fg.get_height() * 0.78), Image.INTERPOLATE_LANCZOS)
	var off := (fg.get_width() - small.get_width()) / 2
	fg_pad.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(off, off + 10))
	_save(fg_pad, "icon_fg_432.png", 432)
	_save(bg, "icon_bg_432.png", 432)
	var mono := fg_pad.duplicate() as Image
	for y in mono.get_height():
		for x in mono.get_width():
			var a := mono.get_pixel(x, y).a
			mono.set_pixel(x, y, Color(1, 1, 1, a))
	_save(mono, "icon_mono_432.png", 432)
	print("ICONS OK")
	get_tree().quit()


## Céu pastel em cima, dunas douradas embaixo (mesma paleta do jogo).
func _background(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var t := float(y) / n
		var sky := Color(0.36, 0.52, 0.86).lerp(Color(1.0, 0.80, 0.66), smoothstep(0.0, 0.62, t))
		for x in n:
			var dune := 0.66 + 0.06 * sin(float(x) / n * 6.0 + 1.2) + 0.03 * sin(float(x) / n * 17.0)
			var c := sky
			if t > dune:
				var d := clampf((t - dune) * 3.0, 0.0, 1.0)
				c = Color(0.98, 0.76, 0.54).lerp(Color(0.86, 0.55, 0.42), d)
			img.set_pixel(x, y, c)
	return img


func _save(img: Image, file: String, size: int) -> void:
	var out := img.duplicate() as Image
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	out.save_png(ProjectSettings.globalize_path(OUT.path_join(file)))
