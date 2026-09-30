// Shared by the vibe_scatter shaders (world_vertex_coords): wind, noise, colors.
// COLOR.a = flexibility (0 = rigid base, 1 = tips), UV2.x = sway phase,
// UV2.y = 1 on foliage cards. INSTANCE_CUSTOM.x/y = random per instance.

uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sway_amount : hint_range(0.0, 2.0) = 0.35;
uniform float flutter : hint_range(0.0, 0.3) = 0.035;

varying float v_rand;
varying float v_rand2;
varying vec3 v_wpos;
varying vec3 v_wnrm;

float veg_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float veg_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(veg_hash(i), veg_hash(i + vec3(1, 0, 0)), f.x), mix(veg_hash(i + vec3(0, 1, 0)), veg_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(veg_hash(i + vec3(0, 0, 1)), veg_hash(i + vec3(1, 0, 1)), f.x), mix(veg_hash(i + vec3(0, 1, 1)), veg_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float veg_fbm(vec3 p) {
	return veg_noise(p) * 0.55 + veg_noise(p * 2.13) * 0.28 + veg_noise(p * 4.37) * 0.17;
}

// World-space offset of a vertex (height scaled by the instance scale).
vec3 veg_wind(vec3 wpos, vec3 origin, float scale, float flex, float phase, float leaf) {
	vec2 wd = normalize(wind_direction + vec2(0.0001));
	float t = TIME * wind_speed;
	float p = dot(origin.xz, vec2(0.071, 0.113)) + phase;
	float gust = 0.55 + 0.45 * sin(t * 0.37 + dot(origin.xz, vec2(0.013, 0.011)));
	float sway = (sin(t * 1.1 + p) * 0.65 + sin(t * 2.3 + p * 1.7) * 0.35) * gust + 0.35 * gust;
	float bend = flex * flex;
	vec3 off = vec3(wd.x, 0.0, wd.y) * sway * bend * sway_amount * wind_strength * scale;
	off.y -= length(off) * 0.3;
	if (leaf > 0.5) {
		vec3 w = wpos * 2.3 + vec3(phase);
		off += vec3(sin(t * 7.0 + w.x), cos(t * 6.1 + w.z) * 0.6, sin(t * 5.3 + w.y)) * flutter * wind_strength * flex * gust;
	}
	return off;
}
