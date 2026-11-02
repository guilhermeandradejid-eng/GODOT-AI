class_name PropLib
extends RefCounted
## Instancia os props (GLB do Blender) trocando os materiais pelos shaders do
## jogo conforme o nome do material (stone, wood, bronze, glow, crystal, seam,
## cloth, jelly) e cria colisões simples quando pedido.

const NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")
const PROP_SHADER := preload("res://game/shaders/prop.gdshader")
const GLOW := preload("res://game/shaders/glow.gdshader")
const JELLY := preload("res://game/shaders/jelly.gdshader")
const CRYSTAL := preload("res://game/shaders/crystal.gdshader")
const SEAM := preload("res://game/shaders/seam.gdshader")

## Props com nomes fixos (os demais vêm de game/assets/props/<nome>.glb).
const SCENES := {}

static var _shared := {}


static func shared_material(kind: String) -> ShaderMaterial:
	if _shared.has(kind):
		return _shared[kind]
	var m := ShaderMaterial.new()
	match kind:
		"stone":
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
		"wood":
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
			m.set_shader_parameter("sand_amount", 0.15)
		"wood_sway":
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
			m.set_shader_parameter("sand_amount", 0.0)
			m.set_shader_parameter("wind_strength", 1.0)
		"bronze":
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
			m.set_shader_parameter("sand_amount", 0.05)
			m.set_shader_parameter("metallic_look", 1.0)
		"cloth":
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
			m.set_shader_parameter("sand_amount", 0.0)
			m.set_shader_parameter("rim_strength", 0.9)
		"glow":
			m.shader = GLOW
		"jelly":
			m.shader = JELLY
			m.render_priority = 2
		"crystal":
			m.shader = CRYSTAL
		"seam":
			m.shader = SEAM
		_:
			m.shader = PROP_SHADER
			m.set_shader_parameter("noise_tex", NOISE)
	_shared[kind] = m
	return m


## Instancia um prop. unique: lista de materiais que recebem cópia própria
## (ex.: ["glow"] para runas que acendem só neste prop).
static var _loaded := {}


## Cena do prop: as da lista fixa ou qualquer game/assets/props/<nome>.glb.
static func scene_of(prop: String) -> PackedScene:
	if SCENES.has(prop):
		return SCENES[prop]
	if not _loaded.has(prop):
		var path := "res://game/assets/props/%s.glb" % prop
		_loaded[prop] = load(path) if ResourceLoader.exists(path) else null
	return _loaded[prop]


static func make(prop: String, unique: Array = []) -> Node3D:
	var scene: PackedScene = scene_of(prop)
	if scene == null:
		push_warning("Prop desconhecido: " + prop)
		return Node3D.new()
	var inst: Node3D = scene.instantiate()
	inst.name = prop.to_pascal_case()
	var sway := false
	var uniq := {}
	for mi in meshes(inst):
		var m := mi.mesh
		for i in m.get_surface_count():
			var src := m.surface_get_material(i)
			var kind := src.resource_name if src != null else "stone"
			if kind == "wood" and sway:
				kind = "wood_sway"
			var mat: Material
			if kind in unique:
				if not uniq.has(kind):
					uniq[kind] = shared_material(kind).duplicate()
				mat = uniq[kind]
			else:
				mat = shared_material(kind)
			mi.set_surface_override_material(i, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not uniq.is_empty():
		inst.set_meta("materials", uniq)
	return inst


static func meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(meshes(c))
	return out


## Colisão estática: "trimesh" (forma exata) ou "convex". only = nomes de malhas.
static func add_collision(node: Node3D, mode := "trimesh", only: Array = []) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Colisao"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	for mi in meshes(node):
		if not only.is_empty() and not (String(mi.name) in only or String(mi.get_parent().name) in only):
			continue
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape() if mode == "trimesh" else mi.mesh.create_convex_shape(true, true)
		cs.transform = rel_xform(mi, node)
		body.add_child(cs)
	return body


static func rel_xform(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
