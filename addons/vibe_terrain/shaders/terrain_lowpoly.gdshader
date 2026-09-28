// Vibe terrain — low poly: faceted (flat) shading on a coarse mesh and one
// color per triangle (dominant layer + small random variation).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled;

#include "res://addons/vibe_terrain/shaders/terrain_common.gdshaderinc"

uniform float color_jitter : hint_range(0.0, 0.3) = 0.08;
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.48, 0.78);

void fragment() {
	vec4 w = v_flat_splat;
	vec3 col;
	float emis = 0.0;
	float mx = max(max(w.x, w.y), max(w.z, w.w));
	if (w.x >= mx) {
		col = mix(layer0_color_a, layer0_color_b, v_flat_rand);
		emis = layer0_emission;
	} else if (w.y >= mx) {
		col = mix(layer1_color_a, layer1_color_b, v_flat_rand);
		emis = layer1_emission;
	} else if (w.z >= mx) {
		col = mix(layer2_color_a, layer2_color_b, v_flat_rand);
		emis = layer2_emission;
	} else {
		col = mix(layer3_color_a, layer3_color_b, v_flat_rand);
		emis = layer3_emission;
	}
	float grass = 0.0;
	col = apply_grass(col, 1e9, v_flat_uv, 1.0, grass);
	col *= 1.0 + (v_flat_rand - 0.5) * color_jitter * 2.0;
	vec3 emission = col * emis;
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ALBEDO = brush_overlay(col, emission);
	ROUGHNESS = 1.0;
	EMISSION = emission;
}

// Soft wrap lighting keeps every facet readable (even against a low sun) and
// tints the shadowed side, the classic low-poly look.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.2, 0.85, ndl) * ATTENUATION;
	vec3 shade = mix(shadow_tint * 0.38, vec3(1.0), lit);
	DIFFUSE_LIGHT += shade * LIGHT_COLOR / PI;
}
