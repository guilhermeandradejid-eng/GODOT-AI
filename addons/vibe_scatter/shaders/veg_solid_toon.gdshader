shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, world_vertex_coords;

// vibe_scatter solids with stylized lighting (soft = 1) or bands (toon / cel).

#include "res://addons/vibe_scatter/shaders/veg_common.gdshaderinc"
#include "res://addons/vibe_scatter/shaders/veg_solid_common.gdshaderinc"

uniform float soft : hint_range(0.0, 1.0) = 0.0;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform vec3 shadow_tint : source_color = vec3(0.45, 0.5, 0.82);
uniform float rim_strength = 0.2;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	VERTEX += veg_wind(VERTEX, origin, scale, COLOR.a, UV2.x, 0.0);
	v_rand = INSTANCE_CUSTOM.x;
	v_rand2 = INSTANCE_CUSTOM.y;
	v_wpos = VERTEX - origin;
	v_wnrm = NORMAL;
}

void fragment() {
	vec3 col;
	float rough;
	vec3 emis;
	solid_surface(UV, COLOR.rgb, col, rough, emis);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emis;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float hl = ndl * 0.5 + 0.5;
	float q = hl * ATTENUATION * bands;
	float stepped = clamp((floor(q) + smoothstep(0.46, 0.54, fract(q))) / bands, 0.0, 1.0);
	float lit = mix(stepped, hl * hl * ATTENUATION, soft);
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shade = mix(shadow_tint * 0.45 * floor_k, vec3(1.0), lit);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * rim_strength * lit;
	DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
}
