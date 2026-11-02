// SOPRO — pelagem/pele dos heróis: toon suave (2 faixas com transição macia),
// "subsurface" quente no terminador, rim light forte de contraluz (estilo Sky),
// leve brilho de pelo (sheen) e cor vinda dos vértices (gerada no Blender).
// Técnica de rim/bandas inspirada em FlexibleToonShaderGD (MIT, reescrito).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.52, 0.78);
uniform vec3 sss_color : source_color = vec3(1.0, 0.45, 0.32);
uniform float sss_strength = 0.35;
uniform float shadow_level = 0.55;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float rim_strength = 0.9;
uniform float rim_power = 3.0;
uniform float band_softness = 0.18;
uniform float sheen = 0.18;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float flash = 0.0;          // hit flash / power-up glow
uniform vec3 flash_color : source_color = vec3(1.0, 0.95, 0.85);

void fragment() {
	vec3 base = COLOR.rgb * tint;
	if (use_texture) {
		base = texture(albedo_tex, UV).rgb * tint;
	}
	ALBEDO = base;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = emission_color + flash_color * flash * (0.4 + fres);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl - 0.05);
	float shadow = mix(0.0, 1.0, lit * ATTENUATION);
	vec3 diffuse = mix(shadow_tint * shadow_level, vec3(1.0), shadow);
	// warm scattering where light turns into shadow
	float term = (1.0 - abs(ndl)) * smoothstep(-0.4, 0.2, ndl);
	diffuse += sss_color * term * sss_strength;
	DIFFUSE_LIGHT += diffuse * LIGHT_COLOR / PI;
	// rim: strongest when the light comes from behind the character
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float back = clamp(dot(-VIEW, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power) * (0.3 + 0.7 * back) * smoothstep(-0.3, 0.4, ndl + back * 0.5);
	SPECULAR_LIGHT += rim_color * rim * rim_strength * LIGHT_COLOR / PI * ALBEDO * 1.6;
	// soft fur sheen
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 12.0) * sheen * LIGHT_COLOR / PI * ATTENUATION;
}
