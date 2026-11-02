extends Node3D
## Prévia de um GLB qualquer (personagens/props) com os shaders do jogo:
## folha com várias vistas para validar modelagem sem abrir o editor.
##
##   xvfb-run -a godot --path . --rendering-method mobile res://game/tools/model_preview.tscn -- \
##       --glb /caminho/modelo.glb --out /tmp/prev [--views front,q34,side,back,close] [--anim idle --t 0.3] [--cell 384]
##       [--hero agile|strong]   (materiais/olhos/contorno de HeroDefs; detectado pelo nome do GLB)

const TOON := preload("res://game/shaders/hero_toon.gdshader")
const EYE := preload("res://game/shaders/hero_eye.gdshader")

var _glb := ""
var _out := "user://prev"
var _views: Array = ["front", "q34", "side", "back", "close"]
var _anim := ""
var _t := 0.0
var _cell := 384
var _props := false
var _hero := ""
var _model: Node3D
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--glb": _glb = args[i + 1]; i += 1
			"--out": _out = args[i + 1]; i += 1
			"--views": _views = Array(args[i + 1].split(",")); i += 1
			"--anim": _anim = args[i + 1]; i += 1
			"--t": _t = float(args[i + 1]); i += 1
			"--cell": _cell = int(args[i + 1]); i += 1
			"--props": _props = true
			"--hero": _hero = args[i + 1]; i += 1
		i += 1
	DirAccess.make_dir_recursive_absolute(_out)
	var atmo := Atmosphere.new()
	add_child(atmo)
	atmo.camera_attributes.dof_blur_far_enabled = false
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.93, 0.74, 0.55)
	fm.roughness = 1.0
	floor_mi.material_override = fm
	add_child(floor_mi)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(_glb, state)
	if err != OK:
		push_error("não consegui ler %s" % _glb)
		get_tree().quit(1)
		return
	_model = doc.generate_scene(state)
	add_child(_model)
	if _props:
		for mi in PropLib.meshes(_model):
			for si in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(si)
				mi.set_surface_override_material(si, PropLib.shared_material(src.resource_name if src != null else "stone"))
	else:
		if _hero == "":
			for role in HeroDefs.DEFS:
				if String(HeroDefs.DEFS[role]["model"]).get_file() == _glb.get_file():
					_hero = role
		if _hero != "":
			apply_hero_materials(_model, _hero)
		else:
			apply_materials(_model)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	add_child(_cam)
	_cam.make_current()
	get_window().size = Vector2i(_cell * 2, _cell * 2)
	_run.call_deferred()


## Materiais do jogo pelos nomes vindos do Blender.
static func apply_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var src := m.surface_get_material(s)
			var mname := src.resource_name if src != null else ""
			var mat := ShaderMaterial.new()
			if mname.begins_with("eye"):
				mat.shader = EYE
			else:
				mat.shader = TOON
				if mname.begins_with("glow"):
					mat.set_shader_parameter("emission_color", Color(0.6, 0.9, 1.0))
			(mi as MeshInstance3D).set_surface_override_material(s, mat)


## Os mesmos materiais do jogo (HeroVisual + HeroDefs: olhos, contorno, glow, glifo).
static func apply_hero_materials(root: Node, role: String) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var hv := HeroVisual.new()
		hv.def = HeroDefs.def_of(role)
		hv.mesh = mi as MeshInstance3D
		hv._setup_materials()
		for m in hv.eye_materials:
			m.set_shader_parameter("lid", float(hv.def.get("base_lid", 0.06)))
		hv.free()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _snap() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(_cell, _cell, Image.INTERPOLATE_LANCZOS)
	return img


func _run() -> void:
	var ap := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		var an := _anim if _anim != "" and ap.has_animation(_anim) else ("idle" if ap.has_animation("idle") else "")
		if an != "":
			ap.play(an)
			ap.seek(_t * ap.get_animation(an).length, true)
			ap.pause()
	for f in 6:
		await get_tree().process_frame
	var box := _aabb(_model)
	var h := maxf(box.size.y, 0.3)
	var center := box.get_center()
	var sheet := Image.create(_cell * _views.size(), _cell, false, Image.FORMAT_RGBA8)
	for k in _views.size():
		var v: String = _views[k]
		var target := center
		var dist := h * 2.3
		var dir := Vector3(0, 0.12, 1)
		match v:
			"front": dir = Vector3(0, 0.12, 1)
			"q34": dir = Vector3(0.8, 0.25, 1)
			"side": dir = Vector3(1, 0.1, 0)
			"back": dir = Vector3(-0.3, 0.2, -1)
			"top": dir = Vector3(0.2, 1.6, 0.6)
			"close":
				target = Vector3(center.x, box.position.y + h * 0.8, center.z)
				dist = h * 1.0
				dir = Vector3(0.35, 0.08, 1)
		_cam.look_at_from_position(target + dir.normalized() * dist, target)
		for f in 3:
			await get_tree().process_frame
		var img: Image = await _snap()
		sheet.blit_rect(img, Rect2i(0, 0, _cell, _cell), Vector2i(k * _cell, 0))
	var path := _out.path_join(_glb.get_file().get_basename() + "_views.png")
	sheet.save_png(path)
	print("SHEET ", path)
	get_tree().quit()
