@tool
extends RefCounted
## Lighting / sky / fog presets ("atmospheres") and per-style post settings.
## Creates or updates a WorldEnvironment named "VibeEnvironment" and a
## DirectionalLight3D named "VibeSun" in the scene.

const SKY_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_sky.gdshader")
const NOISE_PATH := "res://addons/vibe_vfx/textures/noise_fbm.webp"

const PRESETS := {
	"day": {
		"description": "Dia ensolarado / sunny day",
		"sun_elevation": 48.0, "sun_azimuth": -35.0, "sun_color": "#fff3df", "sun_energy": 1.3,
		"sky_top": "#2f6fc9", "sky_horizon": "#a8cbe6", "ground": "#6a6155", "sun_size": 0.028, "sun_glow": 0.35,
		"clouds": 0.38, "cloud_color": "#ffffff", "stars": 0.0, "moon": 0.0,
		"ambient": 0.45, "fog_density": 0.0004, "fog_color": "#b7d0e8", "glow": 0.12, "exposure": 0.88,
	},
	"sunset": {
		"description": "Pôr do sol dourado / golden sunset",
		"sun_elevation": 11.0, "sun_azimuth": -70.0, "sun_color": "#ffc390", "sun_energy": 1.55,
		"sky_top": "#3a4f8f", "sky_horizon": "#ff9656", "ground": "#40302c", "sun_size": 0.035, "sun_glow": 0.9,
		"clouds": 0.45, "cloud_color": "#ffb58a", "stars": 0.0, "moon": 0.0,
		"ambient": 0.78, "fog_density": 0.0005, "fog_color": "#c4a08e", "glow": 0.3, "exposure": 1.05,
	},
	"dawn": {
		"description": "Amanhecer suave / soft dawn",
		"sun_elevation": 11.0, "sun_azimuth": 65.0, "sun_color": "#ffd0ae", "sun_energy": 1.2,
		"sky_top": "#5470b0", "sky_horizon": "#ffc6a6", "ground": "#4a4450", "sun_size": 0.032, "sun_glow": 0.6,
		"clouds": 0.3, "cloud_color": "#ffd8c8", "stars": 0.0, "moon": 0.0,
		"ambient": 0.5, "fog_density": 0.0016, "fog_color": "#d6c4d4", "glow": 0.3, "exposure": 1.0,
	},
	"night": {
		"description": "Noite de lua cheia / moonlit night",
		"sun_elevation": 38.0, "sun_azimuth": 25.0, "sun_color": "#9fb4ff", "sun_energy": 0.5,
		"sky_top": "#03061a", "sky_horizon": "#16224a", "ground": "#04050a", "sun_size": 0.05, "sun_glow": 0.1,
		"clouds": 0.18, "cloud_color": "#2a3458", "stars": 1.0, "moon": 1.0,
		"ambient": 0.3, "fog_density": 0.0012, "fog_color": "#0c1430", "glow": 0.65, "exposure": 1.25,
	},
	"overcast": {
		"description": "Nublado / overcast",
		"sun_elevation": 45.0, "sun_azimuth": -20.0, "sun_color": "#e6e9ee", "sun_energy": 0.55,
		"sky_top": "#7d8894", "sky_horizon": "#b4bcc4", "ground": "#55585c", "sun_size": 0.0, "sun_glow": 0.05,
		"clouds": 0.92, "cloud_color": "#c9ced4", "stars": 0.0, "moon": 0.0,
		"ambient": 0.75, "fog_density": 0.0018, "fog_color": "#a9b1ba", "glow": 0.1, "exposure": 1.0,
	},
	"foggy": {
		"description": "Neblina misteriosa / misty fog",
		"sun_elevation": 30.0, "sun_azimuth": -40.0, "sun_color": "#dfe6ee", "sun_energy": 0.6,
		"sky_top": "#8a96a3", "sky_horizon": "#c9d0d7", "ground": "#707478", "sun_size": 0.02, "sun_glow": 0.2,
		"clouds": 0.8, "cloud_color": "#d0d6dc", "stars": 0.0, "moon": 0.0,
		"ambient": 0.7, "fog_density": 0.012, "fog_color": "#c3cbd3", "glow": 0.15, "exposure": 1.0,
	},
	"stormy": {
		"description": "Tempestade / storm",
		"sun_elevation": 35.0, "sun_azimuth": 10.0, "sun_color": "#aab4c4", "sun_energy": 0.35,
		"sky_top": "#1d242e", "sky_horizon": "#4a5563", "ground": "#22262c", "sun_size": 0.0, "sun_glow": 0.0,
		"clouds": 1.0, "cloud_color": "#3a424e", "stars": 0.0, "moon": 0.0,
		"ambient": 0.45, "fog_density": 0.0045, "fog_color": "#3e4753", "glow": 0.3, "exposure": 1.1,
	},
	"alien": {
		"description": "Céu alienígena / alien sky",
		"sun_elevation": 25.0, "sun_azimuth": -50.0, "sun_color": "#8affd8", "sun_energy": 1.1,
		"sky_top": "#1d0b3d", "sky_horizon": "#ff5da2", "ground": "#1a0c24", "sun_size": 0.06, "sun_glow": 0.7,
		"clouds": 0.35, "cloud_color": "#b86bff", "stars": 0.5, "moon": 0.0,
		"ambient": 0.55, "fog_density": 0.0012, "fog_color": "#7a2f8f", "glow": 0.6, "exposure": 1.05,
	},
}

const ALIASES := {
	"dia": "day", "ensolarado": "day", "sunny": "day", "noon": "day",
	"por_do_sol": "sunset", "entardecer": "sunset", "crepusculo": "sunset", "dusk": "sunset",
	"amanhecer": "dawn", "alvorada": "dawn", "sunrise": "dawn", "manha": "dawn",
	"noite": "night", "noturno": "night", "luar": "night",
	"nublado": "overcast", "cloudy": "overcast", "neblina": "foggy", "nevoa": "foggy", "fog": "foggy", "mist": "foggy",
	"tempestade": "stormy", "storm": "stormy", "alienigena": "alien", "fantasia": "alien",
}

## Post-processing flavor for each art style.
const STYLE_POST := {
	"realistic": {"tonemap": "filmic", "saturation": 1.0, "contrast": 1.0, "sky_bands": 0.0, "ssao": true, "glow_mul": 1.0, "fog_mul": 1.0, "ambient_mul": 1.0},
	"stylized": {"tonemap": "filmic", "saturation": 1.1, "contrast": 1.04, "sky_bands": 0.0, "ssao": true, "glow_mul": 1.3, "fog_mul": 0.8, "ambient_mul": 1.1},
	# Linear tonemapping keeps toon colors pure, so the exposure is lowered to avoid clipping.
	"toon": {"tonemap": "linear", "exposure_mul": 0.66, "saturation": 1.05, "contrast": 1.05, "sky_bands": 0.0, "sky_toon": 1.0, "ssao": false, "glow_mul": 1.1, "fog_mul": 0.6, "ambient_mul": 1.0},
	"cel": {"tonemap": "linear", "exposure_mul": 0.66, "saturation": 1.08, "contrast": 1.08, "sky_bands": 0.0, "sky_toon": 1.0, "ssao": false, "glow_mul": 0.9, "fog_mul": 0.5, "ambient_mul": 1.05},
	"lowpoly": {"tonemap": "filmic", "saturation": 1.12, "contrast": 1.02, "sky_bands": 0.0, "ssao": true, "glow_mul": 0.9, "fog_mul": 1.2, "ambient_mul": 1.1},
}


static func resolve(preset_name: String) -> String:
	var n := preset_name.to_lower().strip_edges().replace(" ", "_")
	for k in {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}.keys():
		n = n.replace(k, {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}[k])
	if PRESETS.has(n):
		return n
	return ALIASES.get(n, "")


static func _c(v: Variant, fallback: String) -> Color:
	if v is Color:
		return v
	return Color.html(str(v)) if str(v).is_valid_html_color() else Color.html(fallback)


## Returns the preset merged with `overrides` (numbers/colors).
static func resolve_settings(preset_name: String, overrides: Dictionary) -> Dictionary:
	var key := resolve(preset_name)
	var s: Dictionary = PRESETS.get(key if key != "" else "day", PRESETS.day).duplicate()
	for k in overrides:
		s[k] = overrides[k]
	s["preset"] = key if key != "" else "day"
	return s


## Applies settings to the given WorldEnvironment + DirectionalLight3D.
static func apply(env_node: WorldEnvironment, sun: DirectionalLight3D, s: Dictionary, style: String) -> void:
	var post: Dictionary = STYLE_POST.get(style, STYLE_POST.realistic)
	var env := env_node.environment
	if env == null:
		env = Environment.new()
		env_node.environment = env
	env.background_mode = Environment.BG_SKY
	var sky := env.sky
	if sky == null:
		sky = Sky.new()
		env.sky = sky
	var mat := sky.sky_material as ShaderMaterial
	if mat == null or mat.shader != SKY_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = SKY_SHADER
		sky.sky_material = mat
	if ResourceLoader.exists(NOISE_PATH):
		mat.set_shader_parameter("noise_tex", load(NOISE_PATH))
	mat.set_shader_parameter("top_color", _c(s.get("sky_top"), "#2f6fc9"))
	mat.set_shader_parameter("horizon_color", _c(s.get("sky_horizon"), "#a8cbe6"))
	mat.set_shader_parameter("ground_color", _c(s.get("ground"), "#6a6155"))
	mat.set_shader_parameter("sun_color", _c(s.get("sun_color"), "#fff3df"))
	mat.set_shader_parameter("sun_size", float(s.get("sun_size", 0.03)))
	mat.set_shader_parameter("sun_glow", float(s.get("sun_glow", 0.35)))
	mat.set_shader_parameter("moon", float(s.get("moon", 0.0)))
	mat.set_shader_parameter("stars", float(s.get("stars", 0.0)))
	mat.set_shader_parameter("cloud_coverage", float(s.get("clouds", 0.3)))
	mat.set_shader_parameter("cloud_color", _c(s.get("cloud_color"), "#ffffff"))
	mat.set_shader_parameter("bands", float(post.sky_bands))
	mat.set_shader_parameter("toon", float(post.get("sky_toon", 0.0)))

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(s.get("ambient", 1.0)) * float(post.ambient_mul)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	match str(post.tonemap):
		"linear":
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		_:
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(s.get("exposure", 1.0)) * float(post.get("exposure_mul", 1.0))
	env.tonemap_white = 6.0 if env.tonemap_mode == Environment.TONE_MAPPER_FILMIC else 1.0
	var fog_density := float(s.get("fog_density", 0.002)) * float(post.fog_mul)
	env.fog_enabled = fog_density > 0.0
	env.fog_light_color = _c(s.get("fog_color"), "#b7d0e8")
	env.fog_density = fog_density
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.4
	var glow := float(s.get("glow", 0.2)) * float(post.glow_mul)
	env.glow_enabled = glow > 0.0
	env.glow_intensity = 0.4 + glow * 0.8
	env.glow_bloom = glow * 0.08
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = bool(post.ssao)
	env.adjustment_enabled = absf(float(post.saturation) - 1.0) > 0.001 or absf(float(post.contrast) - 1.0) > 0.001
	env.adjustment_saturation = float(post.saturation)
	env.adjustment_contrast = float(post.contrast)

	sun.rotation_degrees = Vector3(-float(s.get("sun_elevation", 50.0)), float(s.get("sun_azimuth", -30.0)), 0.0)
	sun.light_color = _c(s.get("sun_color"), "#fff3df")
	sun.light_energy = float(s.get("sun_energy", 1.0))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = float(s.get("shadow_distance", 250.0))
	sun.shadow_blur = 1.5 if style in ["realistic", "stylized"] else 0.5
	env_node.set_meta("vibe_preset", s.get("preset", "day"))
	env_node.set_meta("vibe_style", style)
