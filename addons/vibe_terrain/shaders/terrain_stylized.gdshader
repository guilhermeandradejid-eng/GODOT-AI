// Vibe terrain — stylized (painterly): procedural color layers, height-blended
// soft transitions, warm light / cool colored shadows and a gentle rim.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

#include "res://addons/vibe_terrain/shaders/terrain_common.gdshaderinc"

uniform vec3 shadow_tint : source_color = vec3(0.5, 0.56, 0.86);
uniform float rim_strength = 0.12;

void fragment() {
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(detail_fade_distance * 0.25, detail_fade_distance, dist);
	vec4 w = raw_weights();
	vec3 p = v_local;
	vec4 c0 = w.x > 0.003 ? procedural_layer(layer0_color_a, layer0_color_b, layer0_noise_scale, layer0_strata, layer0_emission, p, detail) : vec4(0.0);
	vec4 c1 = w.y > 0.003 ? procedural_layer(layer1_color_a, layer1_color_b, layer1_noise_scale, layer1_strata, layer1_emission, p, detail) : vec4(0.0);
	vec4 c2 = w.z > 0.003 ? procedural_layer(layer2_color_a, layer2_color_b, layer2_noise_scale, layer2_strata, layer2_emission, p, detail) : vec4(0.0);
	vec4 c3 = w.w > 0.003 ? procedural_layer(layer3_color_a, layer3_color_b, layer3_noise_scale, layer3_strata, layer3_emission, p, detail) : vec4(0.0);
	vec4 hb = height_blend_weights(w, vec4(c0.a, c1.a, c2.a, c3.a), 0.3);
	vec3 albedo = c0.rgb * hb.x + c1.rgb * hb.y + c2.rgb * hb.z + c3.rgb * hb.w;
	vec3 emission = c0.rgb * layer0_emission * hb.x + c1.rgb * layer1_emission * hb.y
		+ c2.rgb * layer2_emission * hb.z + c3.rgb * layer3_emission * hb.w;
	float grass = 0.0;
	albedo = apply_grass(albedo, dist, v_splat_uv, 0.0, dot(vec4(c0.a, c1.a, c2.a, c3.a), hb), grass);
	float m = t_fbm(v_local * 0.01);
	albedo = mix(albedo * vec3(0.92, 0.95, 1.06), albedo * vec3(1.08, 1.04, 0.92), m);
	ALBEDO = brush_overlay(albedo, emission);
	ROUGHNESS = 1.0;
	EMISSION = emission;
}

void light() {
	// Soft wrap: painterly, but slopes still show their form.
	float lit = smoothstep(-0.15, 0.75, dot(NORMAL, LIGHT)) * ATTENUATION;
	// The tinted shadow floor only applies inside a local light's range.
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shade = mix(shadow_tint * 0.4 * floor_k, vec3(1.0), lit);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * rim_strength * lit;
	DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
}
