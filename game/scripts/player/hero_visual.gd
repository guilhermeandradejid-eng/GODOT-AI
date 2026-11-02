class_name HeroVisual
extends Node3D
## Modelo animado de um herói (GLB gerado no Blender) com materiais toon pelos
## nomes vindos do Blender (skin, cloth, stone, metal, glow, eye), olhos
## procedurais que piscam, física secundária (SpringBoneSimulator3D) e uma
## AnimationTree com locomoção sincronizada (idle/walk/run) e estados com
## crossfade. Tudo o que muda de uma personagem para outra vem de HeroDefs.

const TOON := preload("res://game/shaders/hero_toon.gdshader")
const OUTLINE := preload("res://game/shaders/hero_outline.gdshader")
const EYE := preload("res://game/shaders/hero_eye.gdshader")

## Animações em laço; as demais tocam uma vez.
const LOOPS := ["idle", "walk", "run", "fall", "glide", "ride", "swim", "sit", "surf", "launch", "brace"]
const LOCO := ["idle", "walk", "run"]
## Animações de uma vez que voltam sozinhas para a locomoção ao terminar.
const AUTO_RETURN := ["land", "brace", "ram", "celebrate"]

@export var hero := "agile"

var def: Dictionary
var model: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var anim: AnimationPlayer
var tree: AnimationTree
var springs: SpringBoneSimulator3D
var eye_materials: Array[ShaderMaterial] = []
var body_materials: Array[ShaderMaterial] = []
var glyph_material: ShaderMaterial
var states: Array[String] = ["loco"]
var state := "loco"
var base_lid := 0.06
var _blink_t := 2.0
var _blink := 0.0
var _flash := 0.0
var _expression_happy := 0.0
var _oneshot_left := 0.0


func _ready() -> void:
	def = HeroDefs.def_of(hero)
	var path: String = def.get("model", "")
	if not ResourceLoader.exists(path):
		path = def.get("fallback", "")
	var scene := load(path) as PackedScene
	model = scene.instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D") as Skeleton3D
	mesh = _find(model, "MeshInstance3D") as MeshInstance3D
	anim = _find(model, "AnimationPlayer") as AnimationPlayer
	base_lid = float(def.get("base_lid", 0.06))
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
	outline.set_shader_parameter("width", float(def.get("outline", 0.003)))
	if def.has("outline_color"):
		outline.set_shader_parameter("outline_color", def["outline_color"])
	var overrides: Dictionary = def.get("materials", {})
	var m := mesh.mesh
	for i in m.get_surface_count():
		var src := m.surface_get_material(i)
		var mname := src.resource_name if src != null else ""
		var mat := ShaderMaterial.new()
		var base := mname.get_slice(".", 0)
		match base:
			"eye":
				mat.shader = EYE
				for k in def.get("eye", {}):
					mat.set_shader_parameter(k, def["eye"][k])
				eye_materials.append(mat)
			"glow":
				mat.shader = TOON
				mat.set_shader_parameter("vertex_glow", 2.6)
				mat.set_shader_parameter("rim_strength", 0.4)
				mat.set_shader_parameter("emission_color", Color(0.05, 0.12, 0.12))
				body_materials.append(mat)
			"metal":
				mat.shader = TOON
				mat.set_shader_parameter("sheen", 0.65)
				mat.set_shader_parameter("rim_strength", 1.15)
				mat.set_shader_parameter("sss_strength", 0.05)
				mat.next_pass = outline
				body_materials.append(mat)
			"glyph":
				# the missing dot of the duo's emblem: lit only while the partner is aboard
				mat.shader = TOON
				mat.set_shader_parameter("vertex_glow", 0.0)
				mat.set_shader_parameter("emission_color", Color(0.0, 0.0, 0.0))
				glyph_material = mat
				body_materials.append(mat)
			"stone":
				mat.shader = TOON
				mat.set_shader_parameter("sheen", 0.12)
				mat.set_shader_parameter("sss_strength", 0.08)
				mat.set_shader_parameter("rim_strength", 0.95)
				mat.next_pass = outline
				body_materials.append(mat)
			"cloth":
				mat.shader = TOON
				mat.set_shader_parameter("sss_strength", 0.15)
				mat.set_shader_parameter("rim_strength", 0.7)
				mat.set_shader_parameter("sheen", 0.08)
				mat.next_pass = outline
				body_materials.append(mat)
			_:
				mat.shader = TOON
				mat.next_pass = outline
				body_materials.append(mat)
		for k in overrides.get(base, {}):
			mat.set_shader_parameter(k, overrides[base][k])
		mesh.set_surface_override_material(i, mat)


func _setup_loops() -> void:
	if anim == null:
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var a := lib.get_animation(an)
			a.loop_mode = Animation.LOOP_LINEAR if an in LOOPS else Animation.LOOP_NONE
			if not (an in LOCO) and not (an in states):
				states.append(an)


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
	tr.input_count = states.size()
	tr.xfade_time = 0.14
	for i in states.size():
		tr.set_input_name(i, states[i])
		tr.set_input_reset(i, true)
		if states[i] != "loco":
			bt.add_node("a_" + states[i], _anim_node(states[i]))
	bt.add_node("state", tr)
	for i in states.size():
		bt.connect_node("state", i, "loco_speed" if states[i] == "loco" else "a_" + states[i])
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


## Resolve o nome pedido pelo controlador para uma animação que o modelo tem.
func resolve(s: String) -> String:
	if s in states:
		return s
	var alias: String = def.get("aliases", {}).get(s, "")
	if alias != "" and alias in states:
		return alias
	return "loco"


func has_state(s: String) -> bool:
	return s in states


func set_state(s: String, xfade := -1.0) -> void:
	if tree == null:
		return
	s = resolve(s)
	if s == state:
		return
	state = s
	if xfade >= 0.0:
		(tree.tree_root as AnimationNodeBlendTree).get_node("state").xfade_time = xfade
	tree.set("parameters/state/transition_request", s)
	_oneshot_left = anim.get_animation(s).length if s in AUTO_RETURN and anim.has_animation(s) else 0.0


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
	var chains: Array = []
	for c in def.get("springs", []):
		if skeleton.find_bone(c[0]) >= 0 and skeleton.find_bone(c[1]) >= 0:
			chains.append(c)
	if chains.is_empty():
		return
	springs = SpringBoneSimulator3D.new()
	springs.name = "Molas"
	skeleton.add_child(springs)
	springs.setting_count = chains.size()
	for i in chains.size():
		var c: Array = chains[i]
		_chain(springs, i, c[0], c[1], c[2], c[3], c[4], c[5], c[6] if c.size() > 6 else 0.06)


func set_springs_active(v: bool) -> void:
	if springs != null:
		springs.active = v


# ------------------------------------------------------------------ face
func flash(amount := 1.0) -> void:
	_flash = maxf(_flash, amount)


func set_happy(v: float) -> void:
	_expression_happy = v


func _process(delta: float) -> void:
	if _oneshot_left > 0.0:
		_oneshot_left -= delta
		if _oneshot_left <= 0.0 and state in AUTO_RETURN:
			set_state("loco", 0.22)
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
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		for m in body_materials:
			m.set_shader_parameter("flash", _flash)


## Acende (ou apaga) o ponto do glifo da dupla.
func set_glyph(on: bool) -> void:
	if glyph_material == null:
		return
	var from := float(glyph_material.get_shader_parameter("vertex_glow"))
	create_tween().tween_method(func(v: float):
		glyph_material.set_shader_parameter("vertex_glow", v)
		glyph_material.set_shader_parameter("emission_color", Color(0.35, 1.0, 0.94) * (v / 3.0)),
		from, 3.0 if on else 0.0, 0.5)


func look(dir: Vector2) -> void:
	for m in eye_materials:
		m.set_shader_parameter("look", dir)
