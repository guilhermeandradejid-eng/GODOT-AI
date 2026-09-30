@tool
extends RefCounted
## Lighting / sky / fog presets ("atmospheres") and per-style post settings.
## Creates or updates a WorldEnvironment named "VibeEnvironment" and a
## DirectionalLight3D named "VibeSun" in the scene.
##
## Quality levels (project setting vibe/graphics/quality or env.set quality=):
##   low     sky + fog + glow only
##   medium  + SSAO, soft shadows
##   high    + SSIL, volumetric fog (god rays)          (default)
##   ultra   + SDFGI global illumination, bigger shadow range
## Forward+-only effects are harmless on Mobile/Compatibility (ignored there).

const SKY_SHADER = preload("res://addons/vibe_vfx/shaders/vibe_sky.gdshader")
const CLOUD_TEX_PATH := "res://addons/vibe_vfx/textures/cloud_noise.png"
const QUALITY_SETTING := "vibe/graphics/quality"
const QUALITIES := ["low", "medium", "high", "ultra"]
## Sun properties touched by apply() (for undo/redo).
const SUN_PROPS := ["rotation_degrees", "light_color", "light_energy", "shadow_enabled", "shadow_blur", "shadow_bias",
	"shadow_normal_bias", "light_angular_distance", "directional_shadow_max_distance", "directional_shadow_blend_splits",
	"directional_shadow_fade_start", "light_volumetric_fog_energy"]

const PRESETS := {
	"day": {
		"description": "Dia ensolarado / sunny day",
		"sun_elevation": 48.0, "sun_azimuth": -35.0, "sun_color": "#fff1dc", "sun_energy": 1.35,
		"sky_top": "#2a62c2", "sky_mid": "#7eaade", "sky_horizon": "#b4d0e6", "ground": "#5a636c", "sun_size": 0.028, "sun_glow": 0.35,
		"clouds": 0.4, "cloud_color": "#ffffff", "cloud_shade": "#a3adbd", "cirrus": 0.35, "haze": 0.6,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.45, "fog_density": 0.00045, "fog_color": "#b5cde4", "glow": 0.12, "exposure": 0.9,
		"volumetric": 0.0012, "grade": ["#f4f6ff", "#fff8ec"],
	},
	"sunset": {
		"description": "Pôr do sol dourado / golden sunset",
		"sun_elevation": 11.0, "sun_azimuth": -70.0, "sun_color": "#ffc08a", "sun_energy": 1.6,
		"sky_top": "#3d5f9f", "sky_mid": "#e9b8a2", "sky_horizon": "#ff9a52", "mid_height": 0.3, "ground": "#3c3440", "sun_size": 0.035, "sun_glow": 0.9,
		"clouds": 0.45, "cloud_color": "#ffb07e", "cloud_shade": "#6e4c6c", "cirrus": 0.55, "haze": 0.7,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.72, "fog_density": 0.0005, "fog_color": "#c79c86", "fog_sun_scatter": 0.25, "glow": 0.3, "exposure": 1.05,
		"volumetric": 0.0022, "grade": ["#e8e4ff", "#fff0dc"],
	},
	"dawn": {
		"description": "Amanhecer suave / soft dawn",
		"sun_elevation": 14.0, "sun_azimuth": 65.0, "sun_color": "#ffd0ae", "sun_energy": 1.25,
		"sky_top": "#5c82c2", "sky_mid": "#eed6d2", "sky_horizon": "#ffc49c", "mid_height": 0.3, "ground": "#4c4a58", "sun_size": 0.032, "sun_glow": 0.6,
		"clouds": 0.3, "cloud_color": "#ffd8c8", "cloud_shade": "#8a7c9c", "cirrus": 0.5, "haze": 0.75,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.5, "fog_density": 0.0008, "fog_color": "#d6c4d4", "fog_sun_scatter": 0.18, "glow": 0.3, "exposure": 0.95,
		"fog_height": 6.0, "fog_height_density": 0.04, "volumetric": 0.003, "grade": ["#eee8ff", "#fff2e6"],
	},
	"night": {
		"description": "Noite de lua cheia / moonlit night",
		"sun_elevation": 38.0, "sun_azimuth": 25.0, "sun_color": "#9fb4ff", "sun_energy": 0.5,
		"sky_top": "#03061a", "sky_mid": "#0b1434", "sky_horizon": "#1b2a55", "ground": "#04050a", "sun_size": 0.05, "sun_glow": 0.1,
		"clouds": 0.2, "cloud_color": "#3a4668", "cloud_shade": "#10162a", "cirrus": 0.2, "haze": 0.4,
		"stars": 1.0, "moon": 1.0,
		"ambient": 0.3, "fog_density": 0.0012, "fog_color": "#0c1430", "glow": 0.65, "exposure": 1.25,
		"volumetric": 0.0015, "grade": ["#e2e8ff", "#f0f4ff"],
	},
	"overcast": {
		"description": "Nublado / overcast",
		"sun_elevation": 45.0, "sun_azimuth": -20.0, "sun_color": "#e6e9ee", "sun_energy": 0.55,
		"sky_top": "#7d8894", "sky_horizon": "#b4bcc4", "ground": "#55585c", "sun_size": 0.0, "sun_glow": 0.05,
		"clouds": 0.92, "cloud_color": "#b7bdc6", "cloud_shade": "#79818c", "cirrus": 0.0, "haze": 0.5,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.75, "fog_density": 0.0018, "fog_color": "#a9b1ba", "glow": 0.1, "exposure": 1.0,
		"volumetric": 0.0, "grade": ["#f2f4f8", "#f8f8f6"],
	},
	"foggy": {
		"description": "Neblina misteriosa / misty fog",
		"sun_elevation": 30.0, "sun_azimuth": -40.0, "sun_color": "#dfe6ee", "sun_energy": 0.6,
		"sky_top": "#8a96a3", "sky_horizon": "#c9d0d7", "ground": "#707478", "sun_size": 0.02, "sun_glow": 0.2,
		"clouds": 0.8, "cloud_color": "#d0d6dc", "cloud_shade": "#9aa2ab", "cirrus": 0.0, "haze": 0.9,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.7, "fog_density": 0.009, "fog_color": "#c3cbd3", "glow": 0.15, "exposure": 1.0,
		"fog_height": 12.0, "fog_height_density": 0.08, "volumetric": 0.006, "grade": ["#eef2f6", "#f6f6f4"],
	},
	"stormy": {
		"description": "Tempestade / storm",
		"sun_elevation": 35.0, "sun_azimuth": 10.0, "sun_color": "#aab4c4", "sun_energy": 0.35,
		"sky_top": "#1d242e", "sky_horizon": "#4a5563", "ground": "#22262c", "sun_size": 0.0, "sun_glow": 0.0,
		"clouds": 1.0, "cloud_color": "#4a5462", "cloud_shade": "#1a1f26", "cirrus": 0.0, "haze": 0.5,
		"stars": 0.0, "moon": 0.0,
		"ambient": 0.45, "fog_density": 0.0045, "fog_color": "#3e4753", "glow": 0.3, "exposure": 1.1,
		"volumetric": 0.002, "grade": ["#e6ecf4", "#eef0f2"],
	},
	"alien": {
		"description": "Céu alienígena / alien sky",
		"sun_elevation": 25.0, "sun_azimuth": -50.0, "sun_color": "#8affd8", "sun_energy": 1.1,
		"sky_top": "#1d0b3d", "sky_mid": "#8a3aa8", "sky_horizon": "#ff5da2", "ground": "#1a0c24", "sun_size": 0.06, "sun_glow": 0.7,
		"clouds": 0.35, "cloud_color": "#c07aff", "cloud_shade": "#4a2a7a", "cirrus": 0.6, "haze": 0.7,
		"stars": 0.5, "moon": 0.0,
		"ambient": 0.55, "fog_density": 0.0012, "fog_color": "#7a2f8f", "fog_sun_scatter": 0.2, "glow": 0.6, "exposure": 1.05,
		"volumetric": 0.0025, "grade": ["#f0e6ff", "#e6fff6"],
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
## tonemap "agx" (env.set tonemap=agx) falls back to ACES before Godot 4.4.
const STYLE_POST := {
	"realistic": {"tonemap": "aces", "saturation": 1.0, "contrast": 1.03, "sky_bands": 0.0, "ssao": true, "ssil": true,
		"volumetric": 1.0, "glow_mul": 1.0, "fog_mul": 1.0, "ambient_mul": 1.0, "exposure_mul": 1.0, "soft_shadows": 0.6, "grade": 1.0},
	"stylized": {"tonemap": "filmic", "saturation": 1.14, "contrast": 1.05, "sky_bands": 0.0, "ssao": true, "ssil": true,
		"volumetric": 0.8, "glow_mul": 1.3, "fog_mul": 0.8, "ambient_mul": 1.1, "soft_shadows": 0.4, "grade": 1.3},
	# Linear tonemapping keeps toon colors pure, so the exposure is lowered to avoid clipping.
	"toon": {"tonemap": "linear", "exposure_mul": 0.66, "saturation": 1.05, "contrast": 1.05, "sky_bands": 0.0, "sky_toon": 1.0,
		"ssao": false, "ssil": false, "volumetric": 0.0, "glow_mul": 1.1, "fog_mul": 0.6, "ambient_mul": 1.0, "soft_shadows": 0.0, "grade": 0.0},
	"cel": {"tonemap": "linear", "exposure_mul": 0.66, "saturation": 1.08, "contrast": 1.08, "sky_bands": 0.0, "sky_toon": 1.0,
		"ssao": false, "ssil": false, "volumetric": 0.0, "glow_mul": 0.9, "fog_mul": 0.5, "ambient_mul": 1.05, "soft_shadows": 0.0, "grade": 0.0},
	"lowpoly": {"tonemap": "filmic", "saturation": 1.12, "contrast": 1.02, "sky_bands": 0.0, "ssao": true, "ssil": true,
		"volumetric": 1.2, "glow_mul": 0.9, "fog_mul": 1.2, "ambient_mul": 1.1, "soft_shadows": 0.2, "grade": 1.2},
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


## Project-wide default quality (vibe/graphics/quality).
static func default_quality() -> String:
	var q := str(ProjectSettings.get_setting(QUALITY_SETTING, "high"))
	return q if q in QUALITIES else "high"


## True when the project renders with Forward+ (its feature tags, written by
## the editor, win over the engine's default rendering method).
static func project_uses_forward_plus() -> bool:
	var feats := PackedStringArray(ProjectSettings.get_setting("application/config/features", PackedStringArray()))
	if feats.has("Forward Plus"):
		return true
	if feats.has("Mobile") or feats.has("GL Compatibility"):
		return false
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "forward_plus"


## Returns the preset merged with `overrides` (numbers/colors).
static func resolve_settings(preset_name: String, overrides: Dictionary) -> Dictionary:
	var key := resolve(preset_name)
	var s: Dictionary = PRESETS.get(key if key != "" else "day", PRESETS.day).duplicate()
	for k in overrides:
		s[k] = overrides[k]
	s["preset"] = key if key != "" else "day"
	return s


## Tonemapper constant; AgX (4) only exists from Godot 4.4 on.
static func _tonemapper(name: String) -> int:
	match name:
		"linear":
			return Environment.TONE_MAPPER_LINEAR
		"filmic":
			return Environment.TONE_MAPPER_FILMIC
		"agx":
			var v := Engine.get_version_info()
			if int(v.major) > 4 or int(v.minor) >= 4:
				return 4
			return Environment.TONE_MAPPER_ACES
		_:
			return Environment.TONE_MAPPER_ACES


## Split toning as a 1D color-correction LUT: shadows lean to grade[0],
## highlights to grade[1] (display space, subtle).
static func _grade_texture(grade: Array, amount: float) -> GradientTexture1D:
	var sh := _c(grade[0], "#ffffff")
	var hi := _c(grade[1], "#ffffff")
	var g := Gradient.new()
	var offsets := PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	var colors := PackedColorArray()
	for x in offsets:
		var tint := sh.lerp(hi, smoothstep(0.15, 0.85, x))
		# Deviation from white, strongest in the mid tones.
		var w := sin(x * PI) * 0.5 + 0.15
		var c := Color(x, x, x).lerp(Color(x * tint.r, x * tint.g, x * tint.b), w * amount * 4.0)
		if x >= 1.0:
			c = Color(tint.r, tint.g, tint.b).lerp(Color.WHITE, 1.0 - amount)
		colors.append(Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	tex.use_hdr = false
	return tex


## Applies settings to the given WorldEnvironment + DirectionalLight3D.
static func apply(env_node: WorldEnvironment, sun: DirectionalLight3D, s: Dictionary, style: String) -> void:
	var post: Dictionary = STYLE_POST.get(style, STYLE_POST.realistic)
	var quality := str(s.get("quality", default_quality()))
	if not (quality in QUALITIES):
		quality = "high"
	var q := QUALITIES.find(quality)
	# Forward+-only effects stay off in projects set to Mobile/Compatibility.
	# The project decides (not the running renderer), so headless builds match
	# the editor.
	var fplus := project_uses_forward_plus()
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
	if ResourceLoader.exists(CLOUD_TEX_PATH):
		mat.set_shader_parameter("cloud_tex", load(CLOUD_TEX_PATH))
	mat.set_shader_parameter("top_color", _c(s.get("sky_top"), "#2f6fc9"))
	mat.set_shader_parameter("horizon_color", _c(s.get("sky_horizon"), "#a8cbe6"))
	mat.set_shader_parameter("use_mid", 1.0 if s.has("sky_mid") else 0.0)
	mat.set_shader_parameter("mid_color", _c(s.get("sky_mid"), "#7eaade"))
	mat.set_shader_parameter("mid_height", float(s.get("mid_height", 0.35)))
	mat.set_shader_parameter("ground_color", _c(s.get("ground"), "#6a6155"))
	mat.set_shader_parameter("sun_color", _c(s.get("sun_color"), "#fff3df"))
	mat.set_shader_parameter("sun_size", float(s.get("sun_size", 0.03)))
	mat.set_shader_parameter("sun_glow", float(s.get("sun_glow", 0.35)))
	mat.set_shader_parameter("haze", float(s.get("haze", 0.6)))
	mat.set_shader_parameter("moon", float(s.get("moon", 0.0)))
	mat.set_shader_parameter("stars", float(s.get("stars", 0.0)))
	mat.set_shader_parameter("cloud_coverage", clampf(float(s.get("clouds", 0.3)), 0.0, 1.0))
	mat.set_shader_parameter("cloud_color", _c(s.get("cloud_color"), "#ffffff"))
	mat.set_shader_parameter("cloud_shade", _c(s.get("cloud_shade"), "#a3adbd"))
	mat.set_shader_parameter("cloud_scale", float(s.get("cloud_scale", 1.0)))
	mat.set_shader_parameter("cirrus", float(s.get("cirrus", 0.25)))
	mat.set_shader_parameter("cloud_offset", Vector2(float(s.get("cloud_offset_x", 0.0)), float(s.get("cloud_offset_y", 0.0))))
	mat.set_shader_parameter("bands", float(post.sky_bands))
	mat.set_shader_parameter("toon", float(post.get("sky_toon", 0.0)))

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(s.get("ambient", 1.0)) * float(post.ambient_mul)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = _tonemapper(str(s.get("tonemap", post.tonemap))) as Environment.ToneMapper
	env.tonemap_exposure = float(s.get("exposure", 1.0)) * float(post.get("exposure_mul", 1.0))
	env.tonemap_white = 6.0 if env.tonemap_mode == Environment.TONE_MAPPER_FILMIC else (1.0 if env.tonemap_mode == Environment.TONE_MAPPER_LINEAR else 8.0)

	# Distance fog (every renderer) + height fog for mist in the valleys.
	var fog_density := float(s.get("fog_density", 0.002)) * float(post.fog_mul)
	env.fog_enabled = fog_density > 0.0
	env.fog_light_color = _c(s.get("fog_color"), "#b7d0e8")
	env.fog_density = fog_density
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.4
	env.fog_sun_scatter = float(s.get("fog_sun_scatter", 0.05))
	env.fog_height = float(s.get("fog_height", 0.0))
	env.fog_height_density = float(s.get("fog_height_density", 0.0))

	# Volumetric fog: light shafts through trees/mountains (Forward+).
	var vol := float(s.get("volumetric", 0.0015)) * float(post.volumetric)
	env.volumetric_fog_enabled = fplus and q >= 2 and vol > 0.0
	env.volumetric_fog_density = vol
	env.volumetric_fog_albedo = _c(s.get("fog_color"), "#b7d0e8").lerp(Color.WHITE, 0.4)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 160.0 if q < 3 else 256.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.5

	var glow := float(s.get("glow", 0.2)) * float(post.glow_mul)
	env.glow_enabled = glow > 0.0
	env.glow_intensity = 0.4 + glow * 0.8
	env.glow_bloom = glow * 0.08
	env.glow_hdr_threshold = 1.0

	# Contact shadows and bounced light between objects (Forward+).
	env.ssao_enabled = fplus and bool(post.ssao) and q >= 1
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = fplus and bool(post.ssil) and q >= 2
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.9
	env.sdfgi_enabled = fplus and q >= 3 and style != "toon" and style != "cel"
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_energy = 0.9

	env.adjustment_enabled = true
	env.adjustment_saturation = float(post.saturation)
	env.adjustment_contrast = float(post.contrast)
	env.adjustment_brightness = 1.0
	var grade_amount := float(post.get("grade", 0.0)) * float(s.get("grade_amount", 1.0))
	var grade = s.get("grade", [])
	if grade is Array and grade.size() >= 2 and grade_amount > 0.0:
		env.adjustment_color_correction = _grade_texture(grade, clampf(grade_amount * 0.25, 0.0, 1.0))
	else:
		env.adjustment_color_correction = null

	sun.rotation_degrees = Vector3(-float(s.get("sun_elevation", 50.0)), float(s.get("sun_azimuth", -30.0)), 0.0)
	sun.light_color = _c(s.get("sun_color"), "#fff3df")
	sun.light_energy = float(s.get("sun_energy", 1.0))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = float(s.get("shadow_distance", 300.0 if q < 3 else 500.0))
	sun.directional_shadow_blend_splits = q >= 2
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	# Soft penumbras (PCSS) that widen with distance from the caster.
	sun.light_angular_distance = float(post.soft_shadows) if q >= 1 else 0.0
	sun.shadow_blur = 1.5 if style in ["realistic", "stylized"] else 0.5
	sun.light_volumetric_fog_energy = 1.2 if s.get("moon", 0.0) == 0.0 else 0.6
	env_node.set_meta("vibe_preset", s.get("preset", "day"))
	env_node.set_meta("vibe_style", style)
	env_node.set_meta("vibe_quality", quality)
