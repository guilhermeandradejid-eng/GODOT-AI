class_name SoproLevelBuilder
extends Node3D
## Monta o mundo a partir da receita game/world/lencois.json: ilhas (malhas
## geradas no Blender), colisão, lagoas, mar de nuvens e ilhas distantes.
## Props e objetos de jogo são adicionados por SoproLevelContent.

const RECIPE: JSON = preload("res://game/world/lencois.json")
const ISLAND_SHADER := preload("res://game/shaders/island.gdshader")
const LAGOON_SHADER := preload("res://game/shaders/lagoon.gdshader")
const CLOUD_SEA_SHADER := preload("res://game/shaders/cloud_sea.gdshader")
const CLOUD_NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")
const WATER_NORMAL := preload("res://addons/vibe_terrain/textures/water_normal.png")

const ISLAND_SCENES := {
	"IlhaSino": preload("res://game/assets/world/IlhaSino.glb"),
	"IlhaAguasVivas": preload("res://game/assets/world/IlhaAguasVivas.glb"),
	"IlhaCataVentos": preload("res://game/assets/world/IlhaCataVentos.glb"),
	"IlhaFita": preload("res://game/assets/world/IlhaFita.glb"),
	"IlhotaSegredo": preload("res://game/assets/world/IlhotaSegredo.glb"),
}
const FAR_ISLANDS := preload("res://game/assets/world/far_islands.glb")

var recipe: Dictionary
var islands := {}            ## name -> {"node": Node3D, "data": Dictionary}
var island_material: ShaderMaterial
var lagoon_material: ShaderMaterial
var cloud_material: ShaderMaterial
var cloud_sea: MeshInstance3D
var water_level := 0.6
var kill_y := -30.0


func build(atmosphere: SoproAtmosphere) -> void:
	recipe = RECIPE.data
	water_level = float(recipe.get("water_level", 0.6))
	kill_y = float(recipe.get("kill_y", -30.0))
	_make_materials(atmosphere)
	for d in recipe.get("islands", []):
		_build_island(d)
	_build_far_islands()
	_build_cloud_sea(float(recipe.get("cloud_sea_y", -34.0)))


func _make_materials(atmosphere: SoproAtmosphere) -> void:
	island_material = ShaderMaterial.new()
	island_material.shader = ISLAND_SHADER
	island_material.set_shader_parameter("noise_tex", CLOUD_NOISE)
	lagoon_material = ShaderMaterial.new()
	lagoon_material.shader = LAGOON_SHADER
	lagoon_material.set_shader_parameter("noise_tex", CLOUD_NOISE)
	lagoon_material.set_shader_parameter("wave_normal", WATER_NORMAL)
	lagoon_material.render_priority = 1
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SEA_SHADER
	cloud_material.set_shader_parameter("cloud_noise", CLOUD_NOISE)
	cloud_material.render_priority = -1
	if atmosphere != null:
		atmosphere.apply_to_material(lagoon_material)
		atmosphere.apply_to_material(cloud_material)


static func vec3_of(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _build_island(d: Dictionary) -> void:
	var island_name: String = d["name"]
	var scene: PackedScene = ISLAND_SCENES.get(island_name)
	if scene == null:
		push_warning("Ilha sem malha: %s (rode game/blender/build_world.py)" % island_name)
		return
	var root := Node3D.new()
	root.name = island_name
	root.position = vec3_of(d["center"])
	add_child(root)
	var inst := scene.instantiate()
	root.add_child(inst)
	for mi in _meshes(inst):
		mi.material_override = island_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var body := StaticBody3D.new()
		body.name = "Ground"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		mi.add_child(body)
	# lagoons
	for lg in d.get("lagoons", []):
		var r: float = float(lg["r"])
		var water := MeshInstance3D.new()
		water.name = "Lagoa"
		var pm := PlaneMesh.new()
		pm.size = Vector2(r * 2.9, r * 2.9)
		pm.subdivide_width = 18
		pm.subdivide_depth = 18
		water.mesh = pm
		water.material_override = lagoon_material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water.position = Vector3(float(lg["at"][0]), water_level, float(lg["at"][1]))
		root.add_child(water)
		var area := Area3D.new()
		area.name = "Agua"
		area.collision_layer = 8
		area.collision_mask = 0
		area.monitorable = true
		area.add_to_group(&"water")
		var acs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 1.05
		cyl.height = float(lg["depth"]) + 1.0
		acs.shape = cyl
		acs.position.y = -cyl.height * 0.5
		area.add_child(acs)
		water.add_child(area)
	islands[island_name] = {"node": root, "data": d}


func _build_far_islands() -> void:
	var inst := FAR_ISLANDS.instantiate()
	inst.name = "IlhasDistantes"
	add_child(inst)
	for mi in _meshes(inst):
		mi.material_override = island_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_cloud_sea(y: float) -> void:
	cloud_sea = MeshInstance3D.new()
	cloud_sea.name = "MarDeNuvens"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3600, 3600)
	cloud_sea.mesh = pm
	cloud_sea.material_override = cloud_material
	cloud_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_sea.position = Vector3(0, y, 0)
	cloud_sea.extra_cull_margin = 4000.0
	add_child(cloud_sea)


## Mantém o mar de nuvens sob a câmera (o padrão usa coordenadas de mundo).
func follow_camera(cam_pos: Vector3) -> void:
	if cloud_sea != null:
		cloud_sea.position.x = snappedf(cam_pos.x, 50.0)
		cloud_sea.position.z = snappedf(cam_pos.z, 50.0)


func island_center(island_name: String) -> Vector3:
	var info: Dictionary = islands.get(island_name, {})
	if info.is_empty():
		return Vector3.ZERO
	return (info["node"] as Node3D).position


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
