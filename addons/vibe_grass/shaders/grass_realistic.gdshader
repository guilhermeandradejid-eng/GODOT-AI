// Vibe grass — realistic: soft wrap diffuse, subsurface glow when looking
// toward the sun, base occlusion and a subtle specular sheen on the tips.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_burley, specular_schlick_ggx;

#include "res://addons/vibe_grass/shaders/grass_common.gdshaderinc"

void fragment() {
	NORMAL = grass_view_normal(VIEW_MATRIX);
	vec3 col = grass_albedo(0.0);
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.6, v_hf));
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.5, v_hf);
	// Low ambient specular: sky reflections at grazing angles washed meadows out.
	SPECULAR = 0.06;
	EMISSION = color_tip * emission_strength * v_hf * v_hf;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = pow(4.0, ndl) / 4.0;
	float sss = max(-dot(VIEW, LIGHT), 0.0) * 0.6 * v_hf;
	DIFFUSE_LIGHT += (vec3(diffuse) + sss * sss_color) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, hv), 0.0), 32.0) * 0.18 * v_hf;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR / PI;
}
