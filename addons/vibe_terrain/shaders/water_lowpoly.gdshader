// Vibe water — low poly: big faceted waves (flat shading) and depth tones.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.55, 0.95);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.7, 0.75, 0.85);
uniform float depth_fade = 4.0;
uniform float wave_height = 0.35;
uniform float wave_speed = 0.8;
uniform float flow_speed = 0.0;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform float cell_size = 1.0;
uniform float terrain_half_size = 128.0;
uniform bool has_terrain = false;

varying vec3 v_local;
varying vec3 v_world;
// Depth at the provoking vertex: one flat color per facet (no pixel stair-steps).
varying flat float v_depth;

float ground_height(vec2 xz) {
	if (!has_terrain) {
		return -1000.0;
	}
	ivec2 size = textureSize(heightmap, 0);
	vec2 t_raw = (xz + vec2(terrain_half_size)) / cell_size;
	// Beyond the heightmap the seabed continues from the border and keeps
	// sinking, so there is no hard line in the water at the terrain edge.
	vec2 t = clamp(t_raw, vec2(0.0), vec2(size - ivec2(1)));
	float sink = length(t_raw - t) * cell_size * 0.25;
	return texelFetch(heightmap, clamp(ivec2(t), ivec2(0), size - 1), 0).r - sink;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float w = sin(v_world.x * 0.21 + t) * 0.6 + sin(v_world.z * 0.17 - t * 1.3) * 0.4 + sin((v_world.x + v_world.z) * 0.37 + t * 0.7) * 0.3;
	VERTEX.y += w * wave_height;
	v_local = VERTEX;
	v_depth = VERTEX.y - ground_height(VERTEX.xz);
}

void fragment() {
	float d = clamp(v_depth / depth_fade, 0.0, 1.0);
	vec4 col = mix(shallow_color, deep_color, d);
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
}

// Wrap lighting (every facet stays readable) + a small crisp highlight.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.3, 0.9, ndl) * ATTENUATION;
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	DIFFUSE_LIGHT += mix(vec3(0.42, 0.5, 0.72) * 0.5 * floor_k, vec3(1.0), lit) * LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += step(0.985, dot(NORMAL, hv)) * 0.5 * ATTENUATION * LIGHT_COLOR;
}
