shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Wood, rocks, cacti, mushrooms and crystals of vibe_scatter (realistic /
// low poly). Bark relief from a tiling texture along the trunk, triplanar
// noise on rocks, moss or snow on upward faces.

#include "res://addons/vibe_scatter/shaders/veg_common.gdshaderinc"
#include "res://addons/vibe_scatter/shaders/veg_solid_common.gdshaderinc"

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
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = emis;
}
