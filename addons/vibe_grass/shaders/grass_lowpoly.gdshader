// Vibe grass — low poly: flat shaded triangular tufts with per-blade colors.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

#include "res://addons/vibe_grass/shaders/grass_common.gdshaderinc"

uniform float bands : hint_range(1.0, 6.0) = 4.0;

void fragment() {
	vec3 col = mix(color_base, color_tip, 0.35 + 0.5 * v_rand);
	col = mix(col, dry_color, v_dry);
	if (v_petal > 0.5) {
		col = v_flower;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	NORMAL = grass_view_normal(VIEW_MATRIX);
	EMISSION = color_tip * emission_strength * 0.5;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0) * ATTENUATION;
	float stepped = floor(ndl * bands + 0.5) / bands;
	DIFFUSE_LIGHT += vec3(mix(0.35, 1.0, stepped)) * LIGHT_COLOR / PI;
}
