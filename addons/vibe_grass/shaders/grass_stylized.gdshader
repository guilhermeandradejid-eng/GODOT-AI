// Vibe grass — stylized (painterly): half-lambert light, saturated gradient,
// bright rim on the tips, soft color patches.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

#include "res://addons/vibe_grass/shaders/grass_common.gdshaderinc"

uniform float rim_strength = 0.35;
// Same colored shadow as the stylized terrain, so blades in shade do not go black.
uniform vec3 shadow_tint : source_color = vec3(0.5, 0.56, 0.86);

void fragment() {
	NORMAL = grass_view_normal(VIEW_MATRIX);
	vec3 col = grass_albedo(0.0);
	col = mix(col, col * vec3(1.08, 1.12, 0.95), v_hf);
	col *= mix(0.5, 1.0, smoothstep(0.0, 0.5, v_hf));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = color_tip * emission_strength * v_hf * v_hf;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float diffuse = half_lambert * half_lambert;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * rim_strength * v_hf;
	float sss = max(-dot(VIEW, LIGHT), 0.0) * 0.45 * v_hf;
	// The tinted shadow floor only applies inside a local light's range.
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shade = mix(shadow_tint * 0.4 * floor_k, vec3(1.0), diffuse * ATTENUATION);
	DIFFUSE_LIGHT += (shade + (vec3(rim) + sss * sss_color) * ATTENUATION) * LIGHT_COLOR / PI;
}
