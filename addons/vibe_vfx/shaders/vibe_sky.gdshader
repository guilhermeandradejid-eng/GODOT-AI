// Vibe sky: gradient + sun/moon + clouds + stars. `bands` > 0 gives a toon
// look. No TIME usage, so the radiance map is only rebuilt when a parameter
// changes (cheap).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.24, 0.5, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.8, 0.91);
uniform vec3 ground_color : source_color = vec3(0.42, 0.39, 0.34);
uniform float horizon_sharpness = 2.2;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.03;
uniform float sun_glow = 0.35;
uniform float moon = 0.0;
uniform float stars = 0.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec2 cloud_offset = vec2(0.0);
uniform float bands = 0.0;
uniform float energy = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 1.0 / horizon_sharpness);
		if (bands > 0.5) {
			t = floor(t * bands + 0.5) / bands;
		}
		col = mix(horizon_color, top_color, t);
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float cosang = dot(d, LIGHT0_DIRECTION);
		float ang = acos(clamp(cosang, -1.0, 1.0));
		if (moon > 0.5) {
			float disc = 1.0 - smoothstep(sun_size * 0.92, sun_size, ang);
			vec2 muv = (d.xz - LIGHT0_DIRECTION.xz) / sun_size;
			float craters = texture(noise_tex, muv * 0.35 + vec2(0.3)).r;
			col = mix(col, vec3(0.86, 0.89, 0.97) * (0.8 + 0.25 * craters), disc);
			col += vec3(0.45, 0.55, 0.85) * pow(max(cosang, 0.0), 300.0) * 0.35;
		} else {
			float disc = bands > 0.5 ? step(ang, sun_size) : 1.0 - smoothstep(sun_size * 0.75, sun_size, ang);
			col += sun_color * disc * 6.0;
			float glow = pow(max(cosang, 0.0), bands > 0.5 ? 24.0 : 10.0) * sun_glow * (bands > 0.5 ? 0.6 : 1.0);
			col += sun_color * glow * clamp(h + 0.25, 0.0, 1.0);
		}
	}
	if (h > 0.0 && cloud_coverage > 0.001) {
		vec2 uv = d.xz / (h + 0.15) * 0.22 + cloud_offset;
		float n = texture(noise_tex, uv).r * 0.62 + texture(noise_tex, uv * 2.9 + vec2(0.31, 0.77)).r * 0.38;
		float c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, n);
		if (bands > 0.5) {
			c = step(0.45, c) * 0.95;
		}
		float lit = 0.72 + 0.4 * n;
		vec3 cc = cloud_color * lit;
		col = mix(col, cc, c * smoothstep(0.0, 0.12, h) * 0.92);
	}
	if (stars > 0.0 && h > 0.0) {
		vec3 sd = d * 190.0;
		vec3 cell = floor(sd);
		float rnd = fract(sin(dot(cell, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
		float star = step(0.9962, rnd) * (1.0 - smoothstep(0.05, 0.42, length(fract(sd) - 0.5)));
		col += vec3(star) * stars * (0.55 + 0.45 * fract(rnd * 91.7)) * smoothstep(0.0, 0.2, h);
	}
	COLOR = col * energy;
}
