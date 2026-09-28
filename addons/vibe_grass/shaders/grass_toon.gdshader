// Vibe grass — toon / cel: banded color gradient and banded lighting.
// bands = 3 gives a soft toon look; bands = 2 + low softness gives cel shading.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled;

#include "res://addons/vibe_grass/shaders/grass_common.gdshaderinc"

uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.06;
uniform vec3 shadow_tint : source_color = vec3(0.55, 0.62, 0.85);
uniform float rim_strength = 0.4;
uniform float color_steps = 3.0;

void fragment() {
	NORMAL = grass_view_normal(VIEW_MATRIX);
	vec3 col = grass_albedo(color_steps);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = color_tip * emission_strength * step(0.6, v_hf);
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = ndl * ATTENUATION;
	float q = lit * bands;
	float stepped = (floor(q) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(q))) / bands;
	stepped = clamp(stepped, 0.0, 1.0);
	vec3 shade = mix(shadow_tint * 0.55, vec3(1.0), stepped);
	float rim = step(0.72, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)) * rim_strength * v_hf;
	DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
}
