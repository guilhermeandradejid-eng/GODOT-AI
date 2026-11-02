extends Node3D
## Prévia dos heróis: folhas de poses (6 quadros por animação) para validar
## modelagem, materiais e animações sem abrir o editor.
##
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/char_preview.tscn -- \
##       --hero agile --anims idle,run,glide --out /tmp/prev [--frames 6] [--cell 256] [--turntable]

var _hero := "agile"
var _anims: Array = []
var _out := "user://prev"
var _frames := 6
var _cell := 256
var _turntable := false
var _closeup := false
var _vis: HeroVisual
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--hero": _hero = args[i + 1]; i += 1
			"--anims": _anims = Array(args[i + 1].split(",")); i += 1
			"--out": _out = args[i + 1]; i += 1
			"--frames": _frames = int(args[i + 1]); i += 1
			"--cell": _cell = int(args[i + 1]); i += 1
			"--turntable": _turntable = true
			"--closeup": _closeup = true
		i += 1
	DirAccess.make_dir_recursive_absolute(_out)
	var atmo := SoproAtmosphere.new()
	add_child(atmo)
	atmo.camera_attributes.dof_blur_far_enabled = false
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.98, 0.9, 0.82)
	floor_mi.material_override = fm
	add_child(floor_mi)
	_vis = HeroVisual.new()
	_vis.hero = _hero
	add_child(_vis)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	add_child(_cam)
	var target := Vector3(0, 0.5, 0) if _hero == "agile" else Vector3(0, 0.45, -0.1)
	var dist := 3.0 if _hero == "agile" else 3.6
	if _closeup:
		target = Vector3(0, 0.8, 0) if _hero == "agile" else Vector3(0, 0.6, 0.5)
		dist = 1.1 if _hero == "agile" else 1.4
	var dirv := Vector3(0.9, 0.35, 1.0) if not _closeup else Vector3(0.45, 0.15, 1.0)
	_cam.look_at_from_position(target + dirv.normalized() * dist, target)
	_cam.make_current()
	get_window().size = Vector2i(_cell * 2, _cell * 2)
	_run.call_deferred()


func _snap() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(_cell, _cell, Image.INTERPOLATE_LANCZOS)
	return img


func _run() -> void:
	for f in 8:
		await get_tree().process_frame
	_vis.tree.active = false
	_vis.anim.active = true
	_vis.set_springs_active(false)
	if _turntable:
		var sheet := Image.create(_cell * 4, _cell, false, Image.FORMAT_RGBA8)
		_vis.anim.play("idle")
		_vis.anim.seek(0.0, true)
		_vis.anim.pause()
		for k in 4:
			_vis.rotation.y = k * PI * 0.5
			for f in 3:
				await get_tree().process_frame
			var img: Image = await _snap()
			sheet.blit_rect(img, Rect2i(0, 0, _cell, _cell), Vector2i(k * _cell, 0))
		sheet.save_png(_out.path_join("%s_turntable.png" % _hero))
		_vis.rotation.y = 0.0
		print("SHEET ", _out.path_join("%s_turntable.png" % _hero))
	if _anims.is_empty():
		_anims = Array(_vis.anim.get_animation_list())
	var rows := _anims.size()
	var sheet2 := Image.create(_cell * _frames, _cell * rows, false, Image.FORMAT_RGBA8)
	for r in rows:
		var an: String = _anims[r]
		if not _vis.anim.has_animation(an):
			continue
		var length := _vis.anim.get_animation(an).length
		_vis.anim.play(an)
		for k in _frames:
			var t := length * k / float(_frames)
			_vis.anim.seek(t, true)
			_vis.anim.pause()
			for f in 2:
				await get_tree().process_frame
			var img: Image = await _snap()
			sheet2.blit_rect(img, Rect2i(0, 0, _cell, _cell), Vector2i(k * _cell, r * _cell))
	var path := _out.path_join("%s_%s.png" % [_hero, "_".join(_anims) if _anims.size() <= 3 else "anims"])
	sheet2.save_png(path)
	print("SHEET ", path)
	get_tree().quit()
