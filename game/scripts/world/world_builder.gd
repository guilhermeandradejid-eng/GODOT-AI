class_name WorldBuilder
extends Node3D
## Monta o mundo contínuo a partir da receita (seção "terrain" + "content"):
## terreno SandTerrain (alturas geradas por game/tools/gen_terrain.py), areia
## estilo Journey, rastros na areia e faixas de areia levadas pelo vento.
## O conteúdo de jogo (props, interativos, inimigos...) é montado por level_content.gd.

const SAND_SHADER := preload("res://game/shaders/sand_terrain.gdshader")
const CLOUD_NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")

var recipe_path := "res://game/world/aurelith.json"
var recipe: Dictionary
var terrain: SandTerrain
var trails: SandTrails
var sand_material: ShaderMaterial
var kill_y := -60.0
var islands := {}            ## compat: não há ilhas no mundo contínuo


func build(atmosphere: Node) -> void:
	recipe = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	var T: Dictionary = recipe.get("terrain", {})
	sand_material = ShaderMaterial.new()
	sand_material.shader = SAND_SHADER
	sand_material.set_shader_parameter("noise_tex", CLOUD_NOISE)
	if atmosphere != null and atmosphere.get("sun_direction") != null:
		sand_material.set_shader_parameter("wind_dir", Vector2(cos(deg_to_rad(float(T.get("wind_deg", 25.0)))), sin(deg_to_rad(float(T.get("wind_deg", 25.0))))))
	terrain = SandTerrain.new()
	terrain.name = "Terreno"
	terrain.data_dir = String(T.get("data_dir", recipe_path.get_basename() + "_terrain"))
	terrain.material = sand_material
	add_child(terrain)
	terrain.set_param("far_base", _border_mean())
	kill_y = terrain.height_min - 40.0
	trails = SandTrails.new()
	trails.name = "Rastros"
	add_child(trails)
	trails.setup(terrain)
	add_child(SandStreamers.new())


func _border_mean() -> float:
	var r := terrain.resolution
	var sum := 0.0
	var n := 0
	for i in range(0, r, 8):
		sum += terrain.heights[i] + terrain.heights[(r - 1) * r + i] + terrain.heights[i * r] + terrain.heights[i * r + r - 1]
		n += 4
	return sum / maxf(n, 1)


## Compat com o construtor antigo (câmera / mar de nuvens).
func follow_camera(_cam_pos: Vector3) -> void:
	pass


func follow_player(p: Vector3) -> void:
	if trails != null:
		trails.follow(p)


func ground(x: float, z: float) -> Vector3:
	return terrain.surface(x, z) if terrain != null else Vector3(x, 0.0, z)


func set_quality(q: int) -> void:
	if terrain != null:
		terrain.lod_base_range = [40.0, 52.0, 64.0][clampi(q, 0, 2)]
		terrain.cast_shadows = q > 0
		for mi in terrain.get_children():
			if mi is MultiMeshInstance3D:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Faixas de areia levadas pelo vento perto da câmera (cristas "fumegando").
class SandStreamers extends GPUParticles3D:
	func _ready() -> void:
		name = "AreiaNoVento"
		amount = 70
		lifetime = 2.6
		preprocess = 2.6
		local_coords = false
		visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(26, 1.5, 26)
		pm.direction = Vector3(0.9, 0.12, 0.43)
		pm.spread = 12.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 9.0
		pm.gravity = Vector3(0, -0.6, 0)
		pm.damping_min = 0.5
		pm.damping_max = 1.0
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0))
		curve.add_point(Vector2(0.25, 1))
		curve.add_point(Vector2(1, 0))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
		pm.color = Color(1.0, 0.86, 0.66, 0.22)
		process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(2.4, 0.22)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = preload("res://game/assets/textures/streak.png")
		m.vertex_color_use_as_albedo = true
		q.material = m
		draw_pass_1 = q
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			global_position = cam.global_position + (-cam.global_transform.basis.z) * 14.0 + Vector3.DOWN * 3.0
