class_name Atmosphere
extends Node3D
## Céu, sol, névoa, glow e gradação do mar de areia de Ylvaar (hora dourada).
## Cria o WorldEnvironment + DirectionalLight3D, expõe a direção do sol para os
## shaders e o pós-processamento e anima as "horas" (set_hour).

const SKY_SHADER := preload("res://game/shaders/sky.gdshader")
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
	e.fog_sun_scatter = 0.1
	e.fog_density = 0.00068
	e.fog_aerial_perspective = 0.2
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
	camera_attributes.dof_blur_far_enabled = OS.get_environment("GAME_NO_DOF") == ""
	camera_attributes.dof_blur_far_distance = 260.0
	camera_attributes.dof_blur_far_transition = 220.0
	camera_attributes.dof_blur_amount = 0.04
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


## Horas do mundo (enxerto "progressão das horas"): cada Pedra das Horas devolvida
## baixa o sol e esfria a luz (dourado -> rosa -> violeta); a 4ª é o crepúsculo do final.
const HOURS := [
	{"elev": 21.0, "sun": Color(1.0, 0.80, 0.58), "energy": 1.5, "zenith": Color(0.27, 0.45, 0.80),
		"mid": Color(0.98, 0.72, 0.64), "horizon": Color(1.0, 0.86, 0.64), "below": Color(0.96, 0.76, 0.60),
		"fog": Color(1.0, 0.84, 0.70), "stars": 0.0},
	{"elev": 18.0, "sun": Color(1.0, 0.75, 0.55), "energy": 1.45, "zenith": Color(0.28, 0.41, 0.78),
		"mid": Color(1.0, 0.67, 0.62), "horizon": Color(1.0, 0.81, 0.63), "below": Color(0.96, 0.72, 0.61),
		"fog": Color(1.0, 0.80, 0.69), "stars": 0.0},
	{"elev": 15.0, "sun": Color(1.0, 0.68, 0.56), "energy": 1.38, "zenith": Color(0.30, 0.36, 0.74),
		"mid": Color(0.99, 0.60, 0.64), "horizon": Color(1.0, 0.74, 0.64), "below": Color(0.93, 0.65, 0.64),
		"fog": Color(0.99, 0.74, 0.70), "stars": 0.05},
	{"elev": 12.5, "sun": Color(0.99, 0.62, 0.60), "energy": 1.28, "zenith": Color(0.28, 0.30, 0.66),
		"mid": Color(0.90, 0.54, 0.66), "horizon": Color(0.99, 0.68, 0.66), "below": Color(0.84, 0.60, 0.68),
		"fog": Color(0.93, 0.68, 0.72), "stars": 0.12},
	{"elev": 3.0, "sun": Color(0.96, 0.50, 0.56), "energy": 0.75, "zenith": Color(0.10, 0.12, 0.34),
		"mid": Color(0.52, 0.34, 0.58), "horizon": Color(0.86, 0.50, 0.55), "below": Color(0.52, 0.40, 0.58),
		"fog": Color(0.56, 0.46, 0.64), "stars": 1.0},
]
var hour := 0
var _hour_tween: Tween


## Avança o mundo para a hora h (0..4) em `dur` segundos.
func set_hour(h: int, dur := 4.0) -> void:
	h = clampi(h, 0, HOURS.size() - 1)
	hour = h
	var H: Dictionary = HOURS[h]
	var az := Vector2(sun_direction.x, sun_direction.z).normalized()
	var e := deg_to_rad(float(H["elev"]))
	var to_dir := Vector3(az.x * cos(e), sin(e), az.y * cos(e)).normalized()
	if _hour_tween != null:
		_hour_tween.kill()
	_hour_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hour_tween.tween_method(_set_sun_dir, sun_direction, to_dir, dur)
	_hour_tween.tween_property(sun, "light_color", H["sun"], dur)
	_hour_tween.tween_property(sun, "light_energy", H["energy"], dur)
	_hour_tween.tween_property(environment, "fog_light_color", H["fog"], dur)
	for k in ["zenith", "mid", "horizon", "below"]:
		_hour_tween.tween_method(func(c: Color): sky_material.set_shader_parameter(k, c),
			sky_material.get_shader_parameter(k), H[k], dur)
	var sa = sky_material.get_shader_parameter("star_amount")
	_hour_tween.tween_method(func(v: float): sky_material.set_shader_parameter("star_amount", v),
		0.25 if sa == null else float(sa), maxf(float(H["stars"]), 0.25), dur)


func _set_sun_dir(d: Vector3) -> void:
	sun_direction = d.normalized()
	_orient_sun()
	if Game.level != null and Game.level.get("postfx") != null:
		Game.level.postfx.sun_direction = sun_direction


## Parâmetros compartilhados com materiais (água, nuvens...).
func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("sun_dir", sun_direction)
