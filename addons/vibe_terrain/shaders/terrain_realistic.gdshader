// Vibe terrain — realistic: PBR texture layers (albedo+height, normal+roughness)
// with height blending, detiling, triplanar cliffs and macro variation.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://addons/vibe_terrain/shaders/terrain_common.gdshaderinc"

void fragment() {
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(detail_fade_distance * 0.25, detail_fade_distance, dist);
	vec4 w = raw_weights();
	vec3 n_ws = normalize(v_normal_ws);
	vec3 p = v_local;

	vec4 a0 = vec4(0.0); vec4 a1 = vec4(0.0); vec4 a2 = vec4(0.0); vec4 a3 = vec4(0.0);
	vec3 n0 = n_ws; vec3 n1 = n_ws; vec3 n2 = n_ws; vec3 n3 = n_ws;
	float r0 = layer0_roughness; float r1 = layer1_roughness; float r2 = layer2_roughness; float r3 = layer3_roughness;

	if (w.x > 0.003) {
		if (layer0_use_albedo) {
			a0 = sample_layer(layer0_albedo, layer0_normal, layer0_use_normal, layer0_uv_scale, p, n_ws, layer0_roughness, n0, r0);
			a0.rgb *= layer0_tint;
		} else {
			a0 = procedural_layer(layer0_color_a, layer0_color_b, layer0_noise_scale, layer0_strata, layer0_emission, p, detail);
		}
	}
	if (w.y > 0.003) {
		if (layer1_use_albedo) {
			a1 = sample_layer(layer1_albedo, layer1_normal, layer1_use_normal, layer1_uv_scale, p, n_ws, layer1_roughness, n1, r1);
			a1.rgb *= layer1_tint;
		} else {
			a1 = procedural_layer(layer1_color_a, layer1_color_b, layer1_noise_scale, layer1_strata, layer1_emission, p, detail);
		}
	}
	if (w.z > 0.003) {
		if (layer2_use_albedo) {
			a2 = sample_layer(layer2_albedo, layer2_normal, layer2_use_normal, layer2_uv_scale, p, n_ws, layer2_roughness, n2, r2);
			a2.rgb *= layer2_tint;
		} else {
			a2 = procedural_layer(layer2_color_a, layer2_color_b, layer2_noise_scale, layer2_strata, layer2_emission, p, detail);
		}
	}
	if (w.w > 0.003) {
		if (layer3_use_albedo) {
			a3 = sample_layer(layer3_albedo, layer3_normal, layer3_use_normal, layer3_uv_scale, p, n_ws, layer3_roughness, n3, r3);
			a3.rgb *= layer3_tint;
		} else {
			a3 = procedural_layer(layer3_color_a, layer3_color_b, layer3_noise_scale, layer3_strata, layer3_emission, p, detail);
		}
	}

	vec4 hb = height_blend_weights(w, vec4(a0.a, a1.a, a2.a, a3.a), 0.22);
	vec3 albedo = a0.rgb * hb.x + a1.rgb * hb.y + a2.rgb * hb.z + a3.rgb * hb.w;
	vec3 wn = normalize(n0 * hb.x + n1 * hb.y + n2 * hb.z + n3 * hb.w);
	float rough = r0 * hb.x + r1 * hb.y + r2 * hb.z + r3 * hb.w;
	float height = dot(vec4(a0.a, a1.a, a2.a, a3.a), hb);

	vec3 emission = vec3(0.0);
	emission += a0.rgb * layer0_emission * hb.x * pow(1.0 - a0.a, 2.0);
	emission += a1.rgb * layer1_emission * hb.y * pow(1.0 - a1.a, 2.0);
	emission += a2.rgb * layer2_emission * hb.z * pow(1.0 - a2.a, 2.0);
	emission += a3.rgb * layer3_emission * hb.w * pow(1.0 - a3.a, 2.0);
	emission *= 0.85 + 0.15 * sin(TIME * 1.7 + v_local.x * 0.13);

	// Macro variation: large, soft brightness/hue patches that hide tiling.
	float m1 = t_fbm(v_local * 0.008);
	float m2 = t_fbm(v_local * 0.023 + vec3(3.1));
	albedo *= mix(1.0 - macro_variation, 1.0 + macro_variation * 0.5, m1);
	albedo *= mix(vec3(0.94, 0.96, 1.0), vec3(1.04, 1.02, 0.96), m2);

	AO = mix(0.55, 1.0, clamp(height * 1.3, 0.0, 1.0));
	AO_LIGHT_AFFECT = 0.25;
	ALBEDO = brush_overlay(albedo, emission);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = rough;
	EMISSION = emission;
}
