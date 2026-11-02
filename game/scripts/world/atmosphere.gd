class_name SoproAtmosphere
extends Node3D
## Céu, sol, névoa, glow e gradação do mundo "Lençóis do Céu".
## Cria o WorldEnvironment + DirectionalLight3D e expõe a direção do sol para
## os shaders (água, mar de nuvens) e para o pós-processamento.

const SKY_SHADER := preload("res://game/shaders/sky_lencois.gdshader")
const CLOUD_NOISE := preload("res://addons/vibe_vfx/textures/cloud_noise.png")

## Direção PARA o sol (normalizada no _ready).
@export var sun_direction := Vector3(-0.45, 0.36, -0.82)
@export var sun_color := Color(1.0, 0.80, 0.58)
@export var sun_energy := 1.5

var environment: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var camera_attributes: CameraAttributesPractical


func _ready() -> void:
	sun_direction = sun_direction.normalized()
	_build()


func _build() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", CLOUD_NOISE)
	# desert at golden hour: teal-blue zenith, warm gold horizon, pink-violet clouds
	sky_material.set_shader_parameter("zenith", Color(0.27, 0.45, 0.80))
	sky_material.set_shader_parameter("upper", Color(0.52, 0.60, 0.90))
	sky_material.set_shader_parameter("mid", Color(0.98, 0.72, 0.64))
	sky_material.set_shader_parameter("horizon", Color(1.0, 0.86, 0.64))
	sky_material.set_shader_parameter("below", Color(0.96, 0.76, 0.60))
	sky_material.set_shader_parameter("cloud_shadow", Color(0.68, 0.56, 0.80))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.35
	e.ambient_light_color = Color(0.44, 0.50, 0.88)
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.92
	e.tonemap_white = 4.5
	# soft dreamy glow (bloom)
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.32
	e.glow_strength = 0.95
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.glow_hdr_threshold = 1.0
	e.glow_hdr_scale = 1.6
	e.glow_hdr_luminance_cap = 16.0
	for i in 7:
		e.set_glow_level(i, [0.0, 0.0, 0.4, 0.7, 1.0, 0.7, 0.0][i])
	# atmospheric depth: pastel fog with sun scattering + aerial perspective
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(1.0, 0.84, 0.70)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.12
	e.fog_density = 0.0011
	e.fog_aerial_perspective = 0.28
	e.fog_sky_affect = 0.0
	e.fog_height = -14.0
	e.fog_height_density = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.04
	e.adjustment_saturation = 1.06
	environment = e

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = e
	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.dof_blur_far_enabled = OS.get_environment("SOPRO_NO_DOF") == ""
	camera_attributes.dof_blur_far_distance = 140.0
	camera_attributes.dof_blur_far_transition = 120.0
	camera_attributes.dof_blur_amount = 0.06
	world_env.camera_attributes = camera_attributes
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)
	_orient_sun()


func _orient_sun() -> void:
	var d := sun_direction.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	# the light shines along its -Z axis, i.e. away from the sun
	sun.basis = Basis.looking_at(-d, up)


## Parâmetros compartilhados com materiais (água, nuvens...).
func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("sun_dir", sun_direction)
