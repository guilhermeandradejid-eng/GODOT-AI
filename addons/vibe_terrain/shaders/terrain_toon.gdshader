// Vibe terrain — toon / cel: flat color patches, crisp layer borders and
// banded lighting with tinted shadows and rim light.
// toon: bands = 3, band_softness ~0.05 | cel: bands = 2, band_softness ~0.01
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

#include "res://addons/vibe_terrain/shaders/terrain_common.gdshaderinc"

uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.05;
uniform vec3 shadow_tint : source_color = vec3(0.45, 0.5, 0.85);
uniform float rim_strength = 0.2;
uniform float patch_contrast : hint_range(0.0, 1.0) = 0.6;

vec4 toon_layer(vec3 ca, vec3 cb, float scale, float strata, vec3 p) {
	float n = t_fbm(p * scale * 0.6);
	vec3 col = mix(ca, cb, step(0.55, n) * patch_contrast + (1.0 - patch_contrast) * 0.5);
	if (strata > 0.0) {
		float band = step(0.5, fract(p.y * 0.18 + t_fbm(p * 0.03) * 1.5));
		col = mix(col, mix(ca, cb, band), strata);
	}
	return vec4(col, n);
}

void fragment() {
	vec4 w = raw_weights();
	vec3 p = v_local;
	vec4 c0 = w.x > 0.003 ? toon_layer(layer0_color_a, layer0_color_b, layer0_noise_scale, layer0_strata, p) : vec4(0.0);
	vec4 c1 = w.y > 0.003 ? toon_layer(layer1_color_a, layer1_color_b, layer1_noise_scale, layer1_strata, p) : vec4(0.0);
	vec4 c2 = w.z > 0.003 ? toon_layer(layer2_color_a, layer2_color_b, layer2_noise_scale, layer2_strata, p) : vec4(0.0);
	vec4 c3 = w.w > 0.003 ? toon_layer(layer3_color_a, layer3_color_b, layer3_noise_scale, layer3_strata, p) : vec4(0.0);
	vec4 hb = height_blend_weights(w, vec4(c0.a, c1.a, c2.a, c3.a), 0.04);
	// Hard borders: keep only the dominant layer.
	float mx = max(max(hb.x, hb.y), max(hb.z, hb.w));
	hb = step(vec4(mx - 0.0001), hb);
	hb /= max(hb.x + hb.y + hb.z + hb.w, 1.0);
	vec3 albedo = c0.rgb * hb.x + c1.rgb * hb.y + c2.rgb * hb.z + c3.rgb * hb.w;
	vec3 emission = c0.rgb * layer0_emission * hb.x + c1.rgb * layer1_emission * hb.y
		+ c2.rgb * layer2_emission * hb.z + c3.rgb * layer3_emission * hb.w;
	float grass = 0.0;
	albedo = apply_grass(albedo, length(v_world - CAMERA_POSITION_WORLD), v_splat_uv, 1.0, 0.5, grass);
	// Deep creases get one crisp darker step.
	albedo *= mix(1.0, 0.84, step(0.45, v_cavity) * cavity_strength);
	ALBEDO = brush_overlay(albedo * 1.1, emission);
	ROUGHNESS = 1.0;
	EMISSION = emission;
}

void light() {
	float hl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = hl * ATTENUATION;
	float q = lit * bands;
	float stepped = clamp((floor(q) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(q))) / bands, 0.0, 1.0);
	// The tinted shadow floor only applies inside a local light's range.
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shade = mix(shadow_tint * 0.45 * floor_k, vec3(1.0), stepped);
	float rim = step(0.82, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)) * rim_strength * stepped;
	DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
}
