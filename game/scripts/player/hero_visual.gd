class_name HeroVisual
extends Node3D
## Modelo animado de um herói (GLB do Blender) + materiais toon, olhos que piscam,
## física secundária (rabo, cachecol, orelhas, caju) e uma AnimationTree com
## locomoção sincronizada (idle/walk/run) e estados com crossfade.

const TOON := preload("res://game/shaders/hero_toon.gdshader")
const OUTLINE := preload("res://game/shaders/hero_outline.gdshader")
const EYE := preload("res://game/shaders/hero_eye.gdshader")
const CHITA := preload("res://game/assets/textures/chita.png")

const MODELS := {
	"juba": preload("res://game/assets/characters/juba.glb"),
	"caju": preload("res://game/assets/characters/caju.glb"),
}
const LOOPS := ["idle", "walk", "run", "fall", "glide", "ride", "swim", "sit"]
const STATES := {
	"juba": ["loco", "jump", "fall", "land", "double_jump", "glide", "spin", "ride", "celebrate", "hurt", "swim"],
	"caju": ["loco", "jump", "fall", "land", "flop", "swim", "sit", "hurt"],
}

@export var hero := "juba"

var model: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var anim: AnimationPlayer
var tree: AnimationTree
var springs: SpringBoneSimulator3D
var eye_materials: Array[ShaderMaterial] = []
var fur_material: ShaderMaterial
var state := "loco"
var base_lid := 0.06
var _blink_t := 2.0
var _blink := 0.0
var _flash := 0.0
var _expression_happy := 0.0


func _ready() -> void:
	model = MODELS[hero].instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	mesh = _find(model, "MeshInstance3D") as MeshInstance3D
	anim = _find(model, "AnimationPlayer") as AnimationPlayer
	base_lid = 0.06 if hero == "juba" else 0.4
	_setup_materials()
	_setup_loops()
	_setup_tree()
	_setup_springs()


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


# ------------------------------------------------------------------ materials
func _setup_materials() -> void:
	if mesh == null:
		return
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("width", 0.0026 if hero == "juba" else 0.0032)
	var m := mesh.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i)
		var mname := src.resource_name if src != null else ""
		var mat := ShaderMaterial.new()
		match mname:
			"eye":
				mat.shader = EYE
				if hero == "caju":
					mat.set_shader_parameter("iris_outer", Color(0.12, 0.07, 0.05))
					mat.set_shader_parameter("iris_inner", Color(0.45, 0.28, 0.16))
					mat.set_shader_parameter("lid_color", Color(0.47, 0.28, 0.18))
					mat.set_shader_parameter("iris_size", 0.4)
					mat.set_shader_parameter("pupil_size", 0.2)
				eye_materials.append(mat)
			"chita":
				mat.shader = TOON
				mat.set_shader_parameter("use_texture", true)
				mat.set_shader_parameter("albedo_tex", CHITA)
				mat.set_shader_parameter("sheen", 0.05)
				mat.next_pass = outline
			"mane":
				mat.shader = TOON
				mat.set_shader_parameter("rim_strength", 1.2)
				mat.set_shader_parameter("sheen", 0.3)
				mat.set_shader_parameter("sss_strength", 0.5)
			"cloth":
				mat.shader = TOON
				mat.set_shader_parameter("sss_strength", 0.15)
				mat.set_shader_parameter("rim_strength", 0.7)
				mat.next_pass = outline
			_:
				mat.shader = TOON
				mat.next_pass = outline
				fur_material = mat
		mesh.set_surface_override_material(i, mat)


func _setup_loops() -> void:
	if anim == null:
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var a := lib.get_animation(an)
			a.loop_mode = Animation.LOOP_LINEAR if an in LOOPS else Animation.LOOP_NONE


# ------------------------------------------------------------------ animation tree
func _anim_node(n: String, stretch_len := 0.0) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	if stretch_len > 0.0:
		a.use_custom_timeline = true
		a.timeline_length = stretch_len
		a.stretch_time_scale = true
		a.loop_mode = Animation.LOOP_LINEAR
	return a


func _setup_tree() -> void:
	if anim == null:
		return
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 1.0
	bs.add_blend_point(_anim_node("idle"), 0.0)
	bs.add_blend_point(_anim_node("walk", 1.0), 0.3)
	bs.add_blend_point(_anim_node("run", 1.0), 1.0)
	bt.add_node("loco", bs)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("loco_speed", ts)
	bt.connect_node("loco_speed", 0, "loco")
	var tr := AnimationNodeTransition.new()
	var names: Array = STATES[hero]
	tr.input_count = names.size()
	tr.xfade_time = 0.14
	for i in names.size():
		tr.set_input_name(i, names[i])
		tr.set_input_reset(i, true)
		if names[i] != "loco":
			bt.add_node("a_" + names[i], _anim_node(names[i]))
	bt.add_node("state", tr)
	for i in names.size():
		bt.connect_node("state", i, "loco_speed" if names[i] == "loco" else "a_" + names[i])
	bt.connect_node("output", 0, "state")
	tree.tree_root = bt
	tree.active = true
	anim.active = false


## speed01: 0 idle .. 0.3 walk .. 1 run.  cycles: locomotion cycles per second.
func set_locomotion(speed01: float, cycles_per_second: float) -> void:
	if tree == null:
		return
	tree.set("parameters/loco/blend_position", clampf(speed01, 0.0, 1.0))
	tree.set("parameters/loco_speed/scale", maxf(cycles_per_second, 0.05) if speed01 > 0.02 else 1.0)


func set_state(s: String, xfade := -1.0) -> void:
	if tree == null or s == state:
		return
	if not (s in STATES[hero]):
		s = "loco"
	state = s
	if xfade >= 0.0:
		(tree.tree_root as AnimationNodeBlendTree).get_node("state").xfade_time = xfade
	tree.set("parameters/state/transition_request", s)


func restart_state(s: String) -> void:
	state = ""
	set_state(s)


# ------------------------------------------------------------------ secondary motion
func _chain(sb: SpringBoneSimulator3D, i: int, root: String, end: String, stiff: float, drag: float, grav: float,
		radius: float, end_len := 0.06) -> void:
	sb.set_root_bone_name(i, root)
	sb.set_end_bone_name(i, end)
	sb.set_extend_end_bone(i, true)
	sb.set_end_bone_length(i, end_len)
	sb.set_stiffness(i, stiff)
	sb.set_drag(i, drag)
	sb.set_gravity(i, grav)
	sb.set_radius(i, radius)


func _setup_springs() -> void:
	if skeleton == null:
		return
	springs = SpringBoneSimulator3D.new()
	springs.name = "Molas"
	skeleton.add_child(springs)
	if hero == "juba":
		springs.setting_count = 2
		_chain(springs, 0, "tail_1", "tail_7", 2.2, 0.35, 0.0, 0.025, 0.08)
		_chain(springs, 1, "scarf_1", "scarf_5", 0.9, 0.3, 0.8, 0.03, 0.06)
	else:
		springs.setting_count = 3
		_chain(springs, 0, "ear_L", "ear_L", 3.5, 0.25, 0.0, 0.02, 0.05)
		_chain(springs, 1, "ear_R", "ear_R", 3.5, 0.25, 0.0, 0.02, 0.05)
		_chain(springs, 2, "fruit", "fruit", 2.0, 0.12, 0.1, 0.04, 0.1)


func set_springs_active(v: bool) -> void:
	if springs != null:
		springs.active = v


# ------------------------------------------------------------------ face
func flash(amount := 1.0) -> void:
	_flash = maxf(_flash, amount)


func set_happy(v: float) -> void:
	_expression_happy = v


func _process(delta: float) -> void:
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(1.8, 4.5)
	_blink = maxf(0.0, _blink - delta * 7.0)
	var closed := sin(_blink * PI)
	var lid := lerpf(base_lid, 1.0, closed)
	for m in eye_materials:
		m.set_shader_parameter("lid", lid)
		m.set_shader_parameter("happy", _expression_happy)
	if fur_material != null and _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		fur_material.set_shader_parameter("flash", _flash)


func look(dir: Vector2) -> void:
	for m in eye_materials:
		m.set_shader_parameter("look", dir)
