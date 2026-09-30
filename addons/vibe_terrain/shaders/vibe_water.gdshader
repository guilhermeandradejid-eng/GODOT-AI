// Vibe water (realistic): sea, lakes and river ribbons.
// - Gerstner swell on the sea mesh (fades where the mesh is coarse and in
//   shallow water), plus scrolling normal maps for the small ripples.
// - What lies under the surface is refracted (screen texture) and absorbed
//   with depth (red first), then mixed with the scattering color.
// - Depth comes from the terrain heightmap (no depth texture), so shores,
//   foam lines and whitecaps look the same in every renderer.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.26, 0.94);
uniform vec4 shallow_color : source_color = vec4(0.1, 0.52, 0.55, 0.55);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
// Meters of water it takes to reach the deep color.
uniform float depth_fade = 5.0;
uniform float foam_width = 0.9;
// Swell height (sea); rivers and lakes use small values.
uniform float wave_height = 0.12;
uniform float wave_speed = 0.7;
uniform float swell = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float flow_speed = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float refraction = 0.03;
uniform float ripple_strength = 1.0;
uniform float whitecaps : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform float cell_size = 1.0;
uniform float terrain_half_size = 128.0;
uniform bool has_terrain = false;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_normal_w;
varying float v_crest;

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

// One Gerstner wave (GPU Gems / Catlike Coding form). p = world xz.
vec3 gerstner(vec2 p, vec2 dir, float wavelength, float steep, float t, inout vec3 tangent, inout vec3 binormal, inout float crest) {
	float k = 6.2831853 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	float s = sin(f);
	float co = cos(f);
	tangent += vec3(-d.x * d.x * steep * s, d.x * steep * co, -d.x * d.y * steep * s);
	binormal += vec3(-d.x * d.y * steep * s, d.y * steep * co, -d.y * d.y * steep * s);
	crest += s * steep;
	return vec3(d.x * a * co, a * s, d.y * a * co);
}

vec3 unpack_n(vec4 s) {
	return vec3(s.r * 2.0 - 1.0, s.g * 2.0 - 1.0, s.b * 2.0 - 1.0);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	float crest = 0.0;
	vec3 disp = vec3(0.0);
	if (swell > 0.0 && flow_speed == 0.0) {
		// Waves shorter than ~3 mesh cells cannot be drawn: fade them out.
		float spacing = max(UV.x, 0.5);
		float depth = VERTEX.y - ground_height(VERTEX.xz);
		float amp = swell * clamp(wave_height / 0.12, 0.0, 3.0) * clamp(depth / 5.0, 0.12, 1.0);
		float t = TIME * wave_speed;
		vec2 wd = normalize(wind_direction + vec2(1e-4));
		vec2 wp = vec2(-wd.y, wd.x);
		vec2 p = world.xz;
		disp += gerstner(p, wd, 42.0, 0.11 * amp * smoothstep(3.0, 8.0, 42.0 / spacing), t, tangent, binormal, crest);
		disp += gerstner(p, wd + wp * 0.6, 23.0, 0.11 * amp * smoothstep(3.0, 8.0, 23.0 / spacing), t, tangent, binormal, crest);
		disp += gerstner(p, wd - wp * 0.9, 13.0, 0.09 * amp * smoothstep(3.0, 8.0, 13.0 / spacing), t, tangent, binormal, crest);
		disp += gerstner(p, -wd * 0.3 + wp, 7.5, 0.07 * amp * smoothstep(3.0, 8.0, 7.5 / spacing), t, tangent, binormal, crest);
	}
	VERTEX += disp;
	v_crest = crest;
	v_normal_w = normalize(cross(binormal, tangent));
	NORMAL = v_normal_w;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - v_world);
	vec2 wd = normalize(wind_direction + vec2(1e-4));

	// --- Ripples: two scrolling samples (+ a slow large one), fading with distance.
	vec2 p;
	vec2 flow = vec2(0.0);
	if (flow_speed != 0.0) {
		p = vec2(UV.x * 1.5, UV.y);
		flow = vec2(0.0, -t * flow_speed);
	} else {
		p = v_world.xz;
	}
	vec3 r1 = unpack_n(texture(normal_tex, p * 0.061 + wd * t * 0.021 * wave_speed + flow * 0.6));
	vec3 r2 = unpack_n(texture(normal_tex, p * 0.147 - vec2(wd.y, -wd.x) * t * 0.033 * wave_speed + flow));
	// The large sample is rotated (no alignment with the others) and fades far
	// away, where its tiling would show from the air.
	vec2 p3 = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * p;
	vec3 r3 = unpack_n(texture(normal_tex, p3 * 0.0117 + wd * t * 0.006 * wave_speed + flow * 0.2));
	float detail = (1.0 - smoothstep(30.0, 300.0, dist)) * ripple_strength;
	float far_fade = 1.0 - smoothstep(350.0, 1500.0, dist) * 0.7;
	vec2 slope = (r1.xy * 0.55 + r2.xy * 0.35) * detail + r3.xy * 0.45 * ripple_strength * far_fade;
	// Green points to -v (OpenGL maps, uv = world xz): world normal = (x, up, -y).
	vec3 n_w = normalize(v_normal_w + vec3(slope.x, 0.0, -slope.y) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);

	// --- Depth under the surface and through the water toward the eye.
	float depth = v_local.y - ground_height(v_local.xz);
	float path = max(depth, 0.0) / max(abs(view_w.y), 0.12);

	// --- Refraction + absorption.
	vec2 offs = n_w.xz * refraction * clamp(depth * 0.6, 0.0, 1.0) / (1.0 + dist * 0.02);
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	if (OUTPUT_IS_SRGB) {
		behind = pow(max(behind, vec3(0.0)), vec3(2.2));
	}
	vec3 absorb = -log(clamp(shallow_color.rgb, vec3(0.02), vec3(0.98))) / max(depth_fade * 0.6, 0.1);
	vec3 trans = exp(-absorb * path);
	float trans_avg = dot(trans, vec3(0.333));
	float fog = 1.0 - exp(-path / max(depth_fade, 0.1) * 1.4);
	vec3 scatter = mix(shallow_color.rgb * 0.55, deep_color.rgb, smoothstep(0.0, depth_fade * 1.5, depth));

	// --- Foam: contact line, lines rolling in toward the shore, whitecaps.
	float fn = texture(normal_tex, v_world.xz * 0.23 + vec2(t * 0.013, -t * 0.009) + flow * 0.8).a;
	float fn2 = texture(normal_tex, v_world.xz * 0.61 - vec2(t * 0.02, t * 0.017) + flow).a;
	float foam_pat = smoothstep(0.35, 0.75, fn * 0.6 + fn2 * 0.4);
	float contact = 1.0 - smoothstep(0.0, foam_width * 0.45, depth + (fn - 0.5) * 0.25);
	float shore_zone = 1.0 - smoothstep(0.0, foam_width * 3.0, depth);
	float lines = smoothstep(0.55, 1.0, sin(depth / max(foam_width, 0.05) * 4.2 + t * 1.7 + fn * 5.0)) * shore_zone;
	float foam = clamp(max(contact, lines * foam_pat * 0.85), 0.0, 1.0) * step(-0.25, depth);
	if (flow_speed != 0.0) {
		float streak = texture(normal_tex, vec2(UV.x * 0.9, UV.y * 0.25) + flow * 1.3).a;
		foam = max(foam, smoothstep(0.62, 0.85, streak) * 0.55);
	}
	float caps = smoothstep(0.1, 0.3, v_crest) * smoothstep(0.5, 0.78, fn2) * whitecaps;
	foam = max(foam, caps * (1.0 - smoothstep(150.0, 500.0, dist)));

	// --- Compose. The water surface reflects (Fresnel, handled by the
	// specular term); the rest is refraction + scattering.
	float ndv = clamp(dot(n_w, view_w), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	// Light through thin wave crests (broken up by noise so the interference
	// pattern of the swell does not show as a grid of blobs).
	vec3 crest_glow = shallow_color.rgb * smoothstep(0.12, 0.35, v_crest) * 0.22 * smoothstep(0.3, 0.8, fn) * (1.0 - smoothstep(60.0, 400.0, dist));
	vec3 body = behind * trans * (1.0 - fog) ;
	ALBEDO = mix((scatter * fog + crest_glow) * (1.0 - fresnel), foam_color, foam);
	EMISSION = body * (1.0 - fresnel) * (1.0 - foam);
	ALPHA = clamp(smoothstep(-0.05, 0.12, depth) + foam, 0.0, 1.0);
	ROUGHNESS = mix(roughness + smoothstep(80.0, 800.0, dist) * 0.06, 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
