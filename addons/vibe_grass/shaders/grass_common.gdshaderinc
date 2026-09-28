// Shared placement / wind / color code for every Vibe grass style.
// Instances are laid out on a flat grid (MultiMesh); this code lifts each clump
// onto the terrain heightmap, culls it by the painted density map and fades
// it with distance. Wind gusts, clumping and the subsurface light term are
// adapted from GodotGrass by Ethan Truong (MIT): github.com/2Retr0/GodotGrass
//
// Requires: render_mode world_vertex_coords;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D density_map : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform mat4 world_to_terrain = mat4(1.0);
uniform mat4 terrain_to_world = mat4(1.0);
uniform float cell_size = 1.0;
uniform float terrain_half_size = 128.0;
uniform bool has_terrain = false;
uniform float water_level = -100000.0;
uniform float view_distance = 70.0;
uniform float fade_length = 18.0;
uniform float width_scale = 1.0;
uniform float height_scale = 1.0;
uniform float clumping : hint_range(0.0, 1.0) = 0.6;

uniform vec3 color_base : source_color = vec3(0.1, 0.2, 0.06);
uniform vec3 color_tip : source_color = vec3(0.52, 0.66, 0.29);
uniform vec3 dry_color : source_color = vec3(0.63, 0.56, 0.3);
uniform float dry_amount : hint_range(0.0, 1.0) = 0.2;
uniform vec3 sss_color : source_color = vec3(0.84, 0.88, 0.48);
uniform float emission_strength = 0.0;
uniform vec3 flower_color_0 : source_color = vec3(1.0, 0.88, 0.3);
uniform vec3 flower_color_1 : source_color = vec3(1.0, 0.37, 0.62);
uniform vec3 flower_color_2 : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 flower_color_3 : source_color = vec3(0.7, 0.48, 1.0);

uniform float wind_strength = 0.35;
uniform float wind_speed = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
// xyz = position of something that pushes grass (e.g. the player), w = radius (0 = off).
uniform vec4 pusher = vec4(0.0, -100000.0, 0.0, 0.0);

varying float v_hf;
varying float v_rand;
varying float v_dry;
varying float v_petal;
varying float v_center;
varying vec3 v_flower;
varying float v_dist;
varying vec3 v_normal_w;

float g_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float g_ground(vec2 texel) {
	ivec2 size = textureSize(heightmap, 0);
	vec2 t = clamp(texel, vec2(0.0), vec2(size - ivec2(1)));
	ivec2 c = ivec2(floor(t));
	vec2 f = fract(t);
	ivec2 m = size - ivec2(1);
	float h00 = texelFetch(heightmap, clamp(c, ivec2(0), m), 0).r;
	float h10 = texelFetch(heightmap, clamp(c + ivec2(1, 0), ivec2(0), m), 0).r;
	float h01 = texelFetch(heightmap, clamp(c + ivec2(0, 1), ivec2(0), m), 0).r;
	float h11 = texelFetch(heightmap, clamp(c + ivec2(1, 1), ivec2(0), m), 0).r;
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float r0 = g_hash12(inst.xz);
	float r1 = g_hash12(inst.zx + vec2(17.31, 5.17));
	vec3 tl = (world_to_terrain * vec4(inst, 1.0)).xyz;
	float ground_local = has_terrain ? g_ground((tl.xz + vec2(terrain_half_size)) / cell_size) : tl.y;
	vec3 ground = (terrain_to_world * vec4(tl.x, ground_local, tl.z, 1.0)).xyz;
	vec2 duv = (tl.xz + vec2(terrain_half_size)) / (2.0 * terrain_half_size);
	bool inside = duv.x >= 0.0 && duv.y >= 0.0 && duv.x <= 1.0 && duv.y <= 1.0;
	float density = texture(density_map, duv).r;
	float keep = (inside && r0 < density && ground_local > water_level + 0.15) ? 1.0 : 0.0;

	float dist = distance(ground, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(view_distance - fade_length, view_distance, dist);
	float clump = textureLod(noise_tex, inst.xz * 0.045, 0.0).r;
	float size_var = mix(0.65, 1.3, mix(r1, clump, clumping));
	float grow = keep * fade * size_var * height_scale;

	vec3 rel = VERTEX - inst;
	float hf = COLOR.r;
	rel.y *= grow;
	rel.xz *= mix(1.0, grow, 0.5) * width_scale;

	// Wind: large gusts from scrolling noise + small per-blade flutter.
	vec2 wdir = normalize(wind_direction + vec2(0.0001));
	float t = TIME * wind_speed;
	float gust = textureLod(noise_tex, inst.xz * 0.012 - wdir * t * 0.06, 0.0).r;
	float flutter = sin(t * 3.3 + r0 * 6.2831 + hf * 2.0) * 0.12;
	float bend = (gust * 1.5 - 0.25 + flutter) * wind_strength * hf * hf;
	vec3 away = inst - pusher.xyz;
	float pd = length(away.xz);
	float push = pusher.w > 0.0 ? (1.0 - smoothstep(pusher.w * 0.3, pusher.w, pd)) * hf : 0.0;
	vec2 push_dir = pd > 0.001 ? away.xz / pd : vec2(0.0);
	float blade_len = length(rel);
	rel.xz += (wdir * bend + push_dir * push * 0.9) * blade_len;
	rel.y -= (abs(bend) * 0.35 + push * 0.6) * blade_len;

	VERTEX = ground + rel;
	v_dist = dist;
	v_normal_w = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.5 + 0.4 * smoothstep(8.0, view_distance, dist)));
	NORMAL = v_normal_w;
	v_hf = hf;
	v_rand = COLOR.g * 0.5 + r1 * 0.5;
	v_petal = COLOR.a;
	v_center = COLOR.b * COLOR.a;
	v_dry = smoothstep(0.38, 0.72, textureLod(noise_tex, inst.xz * 0.017 + vec2(0.37, 0.71), 0.0).r) * dry_amount;
	float fi = floor(fract(r1 * 7.13 + COLOR.g) * 3.999);
	v_flower = fi < 1.0 ? flower_color_0 : (fi < 2.0 ? flower_color_1 : (fi < 3.0 ? flower_color_2 : flower_color_3));
}

vec3 grass_albedo(float bands) {
	float h = v_hf;
	float g = h * h * (3.0 - 2.0 * h);
	if (bands > 0.0) {
		g = floor(g * bands + 0.5) / bands;
	}
	vec3 col = mix(color_base, color_tip, g);
	col = mix(col, dry_color * mix(0.75, 1.0, h), v_dry);
	col *= 0.84 + 0.32 * v_rand;
	if (v_petal > 0.5) {
		// Petals; the flower center (COLOR.b = 1 at the middle vertex) turns golden.
		col = mix(v_flower, vec3(1.0, 0.78, 0.2), smoothstep(0.55, 0.95, v_center));
	}
	return col;
}

// Normal that ignores the back-face flip of double sided geometry.
vec3 grass_view_normal(mat4 view_matrix) {
	return normalize((view_matrix * vec4(v_normal_w, 0.0)).xyz);
}
