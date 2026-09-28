// Vibe water: sea plane, lakes and river ribbons.
// Depth/shore detection reads the terrain heightmap directly (no depth
// texture), so it works the same in every renderer.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.26, 0.94);
uniform vec4 shallow_color : source_color = vec4(0.1, 0.52, 0.55, 0.55);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float depth_fade = 5.0;
uniform float foam_width = 0.9;
uniform float wave_height = 0.12;
uniform float wave_speed = 0.7;
uniform float flow_speed = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform float cell_size = 1.0;
uniform float terrain_half_size = 128.0;
uniform bool has_terrain = false;

varying vec3 v_local;
varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float waves(vec2 p, float t) {
	float h = noise2(p * 0.35 + vec2(t * 0.21, t * 0.13)) * 0.6;
	h += noise2(p * 0.9 - vec2(t * 0.17, -t * 0.29)) * 0.3;
	h += noise2(p * 2.3 + vec2(-t * 0.4, t * 0.33)) * 0.1;
	return h;
}

float ground_height(vec2 local_xz) {
	if (!has_terrain) {
		return -1000.0;
	}
	ivec2 size = textureSize(heightmap, 0);
	vec2 t_raw = (local_xz + vec2(terrain_half_size)) / cell_size;
	// Beyond the heightmap the seabed continues from the border and keeps
	// sinking, so there is no hard line in the water at the terrain edge.
	vec2 t = clamp(t_raw, vec2(0.0), vec2(size - ivec2(1)));
	float sink = length(t_raw - t) * cell_size * 0.25;
	ivec2 c = ivec2(floor(t));
	vec2 f = fract(t);
	ivec2 m = size - 1;
	float h00 = texelFetch(heightmap, clamp(c, ivec2(0), m), 0).r;
	float h10 = texelFetch(heightmap, clamp(c + ivec2(1, 0), ivec2(0), m), 0).r;
	float h01 = texelFetch(heightmap, clamp(c + ivec2(0, 1), ivec2(0), m), 0).r;
	float h11 = texelFetch(heightmap, clamp(c + ivec2(1, 1), ivec2(0), m), 0).r;
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y) - sink;
}

void vertex() {
	NORMAL = vec3(0.0, 1.0, 0.0);
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += (waves(v_world.xz * 0.25, t) - 0.5) * wave_height * 2.0;
	v_local = VERTEX;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 flow = vec2(0.0);
	if (flow_speed != 0.0) {
		flow = vec2(0.0, -TIME * flow_speed);
	}
	vec2 p = (flow_speed != 0.0) ? (UV * vec2(2.0, 1.0) * 6.0 + flow) : v_world.xz;
	float e = 0.15;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3(h0 - hx, e * 2.5, h0 - hz));
	float view_dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(25.0, 220.0, view_dist);
	NORMAL_MAP = normalize(vec3(n.x, -n.z, n.y)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.15 + 0.45 * detail;

	float depth = v_local.y - ground_height(v_local.xz);
	float shallow = 1.0 - smoothstep(0.0, depth_fade, depth);
	vec4 col = mix(deep_color, shallow_color, shallow);
	float foam_noise = noise2(v_world.xz * 1.7 + vec2(t * 0.6, -t * 0.4));
	float foam = (1.0 - smoothstep(0.0, foam_width, depth + (foam_noise - 0.5) * foam_width * 0.8)) * step(-0.2, depth);
	if (flow_speed != 0.0) {
		float streak = noise2(vec2(UV.x * 8.0, UV.y * 1.5 - TIME * flow_speed * 1.3));
		foam = max(foam, smoothstep(0.78, 0.95, streak) * 0.5);
	}
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(col.rgb, foam_color, foam * 0.85);
	float opaque = smoothstep(depth_fade * 0.5, depth_fade * 2.5, depth);
	ALPHA = clamp(max(mix(col.a, 1.0, opaque) + fresnel * 0.3, foam), 0.0, 1.0);
	ROUGHNESS = mix(roughness, 0.6, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
