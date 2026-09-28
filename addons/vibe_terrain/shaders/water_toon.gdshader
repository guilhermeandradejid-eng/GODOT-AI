// Vibe water — toon / stylized / cel: flat color bands by depth, crisp foam
// lines on the shore and a hard specular sparkle (Wind Waker-like).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_disabled;

uniform vec4 deep_color : source_color = vec4(0.05, 0.3, 0.55, 0.95);
uniform vec4 shallow_color : source_color = vec4(0.25, 0.75, 0.8, 0.8);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float depth_fade = 4.0;
uniform float foam_width = 1.2;
uniform float wave_height = 0.08;
uniform float wave_speed = 0.6;
uniform float flow_speed = 0.0;
uniform float color_bands = 3.0;
uniform float softness : hint_range(0.0, 0.3) = 0.02;

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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ground_height(vec2 xz) {
	if (!has_terrain) {
		return -1000.0;
	}
	ivec2 size = textureSize(heightmap, 0);
	vec2 t = (xz + vec2(terrain_half_size)) / cell_size;
	if (t.x < 0.0 || t.y < 0.0 || t.x > float(size.x - 1) || t.y > float(size.y - 1)) {
		return -1000.0;
	}
	ivec2 c = ivec2(floor(t));
	vec2 f = fract(t);
	ivec2 m = size - 1;
	float h00 = texelFetch(heightmap, clamp(c, ivec2(0), m), 0).r;
	float h10 = texelFetch(heightmap, clamp(c + ivec2(1, 0), ivec2(0), m), 0).r;
	float h01 = texelFetch(heightmap, clamp(c + ivec2(0, 1), ivec2(0), m), 0).r;
	float h11 = texelFetch(heightmap, clamp(c + ivec2(1, 1), ivec2(0), m), 0).r;
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

void vertex() {
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += sin(v_world.x * 0.35 + t) * cos(v_world.z * 0.3 + t * 0.8) * wave_height;
	v_local = VERTEX;
}

void fragment() {
	float depth = v_local.y - ground_height(v_local.xz);
	float d = clamp(depth / depth_fade, 0.0, 1.0);
	float stepped = floor(d * color_bands) / max(color_bands - 1.0, 1.0);
	vec4 col = mix(shallow_color, deep_color, clamp(stepped, 0.0, 1.0));
	vec2 fuv = (flow_speed != 0.0) ? vec2(UV.x * 6.0, UV.y * 2.0 - TIME * flow_speed * 2.0) : v_world.xz * 0.5 + vec2(TIME * 0.05, TIME * 0.03);
	float n = noise2(fuv * 1.5) * 0.6 + noise2(fuv * 4.0 + 3.1) * 0.4;
	float shore = 1.0 - depth / foam_width;
	float foam_line = smoothstep(0.5 - softness, 0.5 + softness, shore + (n - 0.5) * 0.6) * step(-0.3, depth);
	float near_shore = 1.0 - smoothstep(foam_width, foam_width * 2.2, depth);
	float ripple = smoothstep(0.86 - softness, 0.86 + softness, sin(depth * 5.0 - TIME * 1.6) * 0.5 + 0.5) * near_shore * step(foam_width * 0.9, depth) * 0.55;
	float sparkle = step(0.93, noise2(v_world.xz * 2.0 + TIME * 0.4)) * 0.6;
	float foam = clamp(max(foam_line, ripple), 0.0, 1.0);
	ALBEDO = mix(col.rgb, foam_color, foam);
	ALPHA = mix(col.a, 1.0, foam);
	EMISSION = foam_color * sparkle * (1.0 - foam) * 0.4;
	ROUGHNESS = 0.9;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += mix(0.6, 1.0, step(0.3, ndl)) * LIGHT_COLOR / PI;
}
