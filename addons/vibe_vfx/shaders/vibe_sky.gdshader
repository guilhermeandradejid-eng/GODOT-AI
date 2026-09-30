// Vibe sky: artist gradient + atmosphere (horizon haze, sunward glow, Mie
// halo), lit cumulus clouds with cirrus streaks, sun disc with limb
// darkening, shaded moon, stars and the milky way.
// `toon` = 1 gives a crisp sun, two-tone hard-edged clouds and no halo;
// `bands` > 0 posterizes the gradient. No TIME usage, so the radiance map is
// only rebuilt when a parameter changes (cheap); the sun disc and the stars
// are left out of that radiance map (the sun light already gives highlights).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.24, 0.5, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.8, 0.91);
// Optional middle stop of the gradient (use_mid = 1), at mid_height (0..1 of
// the curved elevation): keeps sunsets orange -> peach -> blue instead of a
// muddy orange/blue mix.
uniform vec3 mid_color : source_color = vec3(0.5, 0.65, 0.88);
uniform float use_mid = 0.0;
uniform float mid_height = 0.35;
uniform vec3 ground_color : source_color = vec3(0.42, 0.39, 0.34);
uniform float horizon_sharpness = 2.2;
uniform float haze = 0.6;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.03;
uniform float sun_glow = 0.35;
uniform float moon = 0.0;
uniform float stars = 0.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.58, 0.64, 0.74);
uniform float cloud_scale = 1.0;
uniform float cloud_softness = 0.16;
uniform float cirrus = 0.25;
uniform vec2 cloud_offset = vec2(0.0);
uniform float bands = 0.0;
uniform float toon = 0.0;
uniform float energy = 1.0;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

float sky_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Cloud density (0..1 shape value before thresholding) at a sky uv. Toon
// clouds use a blurrier (mip-biased) base and no edge erosion: rounder puffs.
float cloud_shape(vec2 uv) {
	if (toon > 0.5) {
		return texture(cloud_tex, uv * 0.7, 2.0).r * 1.04 - 0.04;
	}
	float base = texture(cloud_tex, uv).r;
	float det = texture(cloud_tex, uv * 3.7 + vec2(0.37, 0.11)).g;
	return base - (1.0 - det) * 0.2;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float hc = max(h, 0.0);
	bool is_toon = toon > 0.5;
	vec3 L = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.3, 0.7, 0.3);
	float mu = dot(d, L);
	float sun_h = L.y;
	bool night = moon > 0.5;
	// 1 when the sun is near the horizon (sunset/dawn light).
	float low_sun = 1.0 - smoothstep(0.02, 0.5, sun_h);

	// --- Gradient + atmosphere ---------------------------------------------
	float t = pow(hc, 1.0 / horizon_sharpness);
	if (bands > 0.5) {
		t = floor(t * bands + 0.5) / bands;
	}
	vec3 col;
	if (use_mid > 0.5) {
		float m = clamp(mid_height, 0.05, 0.95);
		col = t < m ? mix(horizon_color, mid_color, smoothstep(0.0, 1.0, t / m))
			: mix(mid_color, top_color, smoothstep(0.0, 1.0, (t - m) / (1.0 - m)));
	} else {
		col = mix(horizon_color, top_color, t);
	}
	// Bright, slightly desaturated haze band right above the horizon.
	float hz = exp(-hc * 16.0);
	col = mix(col, horizon_color * 1.1 + sun_color * 0.04, hz * haze * 0.55);
	// Warm glow on the sun side of the horizon (strong at sunset/dawn).
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 lh = normalize(L.xz + vec2(1e-5));
	float az = dot(dh, lh) * 0.5 + 0.5;
	float glow_amount = night ? 0.1 : 1.0;
	col += sun_color * pow(az, 4.0) * exp(-hc * 4.5) * low_sun * sun_glow * 0.5 * glow_amount;
	// Mie halo around the sun (Henyey-Greenstein).
	float g = is_toon ? 0.6 : 0.8;
	float hg = (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * mu, 1e-4), 1.5);
	vec3 halo = sun_color * hg * 0.01 * sun_glow * glow_amount * (1.0 + low_sun);
	if (is_toon) {
		halo = sun_color * step(0.985, mu) * 0.25 * sun_glow;
	}
	col += halo * 0.7;
	if (h < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, 0.2, -h));
	}

	// --- Stars and milky way (behind everything) ------------------------------
	if (stars > 0.0 && h > -0.05 && !AT_CUBEMAP_PASS) {
		float vis = smoothstep(-0.02, 0.25, h) * stars;
		vec3 sd = d * 260.0;
		vec3 cell = floor(sd);
		float rnd = sky_hash(cell);
		vec3 mw_n = normalize(vec3(0.35, 0.55, 0.76));
		float band = exp(-pow(dot(d, mw_n), 2.0) * 20.0);
		// More (faint) stars inside the milky way band.
		float star = step(0.994 - band * 0.012, rnd) * (1.0 - smoothstep(0.08, 0.45, length(fract(sd) - 0.5)));
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), fract(rnd * 57.3));
		col += tint * star * (0.4 + 1.6 * pow(fract(rnd * 91.7), 4.0)) * vis;
		vec3 bd = d * 90.0;
		float rb = sky_hash(floor(bd) + 7.0);
		float big = step(0.9975, rb) * (1.0 - smoothstep(0.02, 0.3, length(fract(bd) - 0.5)));
		col += vec3(1.0, 0.97, 0.92) * big * 2.2 * vis;
		// Milky way: a band along a great circle, broken up by noise.
		vec2 mw_uv = vec2(atan(d.z, d.x) * 0.9, d.y * 1.6 + dot(d, mw_n) * 2.0);
		float dust = texture(cloud_tex, mw_uv * 0.6).r;
		float lanes = texture(cloud_tex, mw_uv * 1.7 + vec2(0.3)).g;
		col += vec3(0.62, 0.66, 0.85) * band * smoothstep(0.35, 0.9, dust) * (0.35 + 0.65 * lanes) * 0.1 * vis;
	}

	// --- Sun disc / moon ---------------------------------------------------------
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {
		float ang = acos(clamp(mu, -1.0, 1.0));
		float above = smoothstep(-0.03, 0.01, h);
		if (night) {
			float r = max(sun_size, 0.005);
			if (ang < r * 1.05) {
				vec3 right = normalize(cross(L, vec3(0.0, 1.0, 0.0)) + vec3(1e-5, 0.0, 0.0));
				vec3 upv = cross(right, L);
				vec2 q = vec2(dot(d, right), dot(d, upv)) / sin(r);
				float z = sqrt(max(1.0 - dot(q, q), 0.0));
				float lit = clamp(dot(vec3(q, z), normalize(vec3(0.55, 0.3, 0.78))), 0.0, 1.0);
				float maria = texture(cloud_tex, q * 0.3 + vec2(0.5)).a;
				float craters = texture(cloud_tex, q * 0.55 + vec2(0.2, 0.7)).g;
				vec3 mc = vec3(0.92, 0.94, 1.0) * mix(0.62, 1.0, smoothstep(0.3, 0.75, maria)) * mix(0.8, 1.05, craters);
				mc *= is_toon ? mix(0.35, 1.25, step(0.25, lit)) : (0.06 + 1.3 * pow(lit, 0.8));
				float edge = 1.0 - smoothstep(0.96, 1.0, length(q));
				col = mix(col, mc, edge * above);
			}
			col += vec3(0.45, 0.55, 0.9) * (pow(max(mu, 0.0), 900.0) * 0.5 + pow(max(mu, 0.0), 60.0) * 0.08) * above;
		} else {
			float r = sun_size;
			float disc = is_toon ? step(ang, r) : 1.0 - smoothstep(r * 0.85, r, ang);
			float limb = sqrt(max(1.0 - pow(ang / max(r, 1e-4), 2.0), 0.0));
			col += sun_color * disc * (is_toon ? 2.2 : 9.0 * (0.5 + 0.5 * limb)) * above;
		}
	}

	// --- Clouds ---------------------------------------------------------------
	if (h > -0.02 && cloud_coverage > 0.001) {
		vec2 uv = d.xz / (hc + 0.1) * 0.11 * cloud_scale + cloud_offset;
		float weather = texture(cloud_tex, uv * 0.11 + vec2(0.17, 0.43)).a;
		float cov = clamp(cloud_coverage + (weather - 0.5) * 0.3, 0.0, 1.0);
		float thr = 1.0 - cov;
		float n = cloud_shape(uv);
		float soft = cloud_softness * (1.0 + 2.5 * exp(-hc * 9.0));
		float c = smoothstep(thr, thr + soft, n);
		// Light marching toward the sun: two samples of the density ahead.
		vec2 sdir = lh * 0.03 * (1.0 + 2.0 * low_sun);
		float n1 = cloud_shape(uv + sdir);
		float n2 = cloud_shape(uv + sdir * 2.5);
		float occl = clamp((n1 - thr) * 2.2, 0.0, 1.0) * 0.6 + clamp((n2 - thr) * 2.2, 0.0, 1.0) * 0.4;
		float thick = smoothstep(thr, thr + 0.35, n);
		float lit = 1.0 - occl * 0.8;
		// Thin clouds let more light through (bright edges, "powder" core).
		lit = mix(lit, 1.0, (1.0 - thick) * 0.45);
		vec3 ccol;
		if (is_toon) {
			float lb = step(0.5, lit);
			ccol = mix(cloud_shade, cloud_color, lb);
			c = smoothstep(0.45, 0.55, c);
		} else {
			ccol = mix(cloud_shade, cloud_color, lit);
			// Silver lining: forward scattering at thin edges toward the sun.
			ccol += sun_color * pow(max(mu, 0.0), 10.0) * (1.0 - thick) * 1.6 * sun_glow * glow_amount;
			ccol *= 0.92 + 0.16 * texture(cloud_tex, uv * 7.1).g;
		}
		// Distant clouds sink into the horizon haze.
		float far = exp(-hc * 7.0);
		ccol = mix(ccol, horizon_color * 1.05, far * 0.5);
		float alpha = c * smoothstep(-0.02, 0.06, h) * mix(0.97, 0.75, far);
		col = mix(col, ccol, alpha);

		// Cirrus: high, thin streaks (under the cumulus threshold too).
		if (cirrus > 0.0) {
			vec2 cuv = d.xz / (hc + 0.25) * 0.05 * cloud_scale + cloud_offset * 0.6 + vec2(0.31, 0.77);
			float ci = texture(cloud_tex, cuv).b * texture(cloud_tex, cuv * 0.37 + vec2(0.5)).a;
			float ca = smoothstep(0.28, 0.6, ci) * cirrus * smoothstep(0.02, 0.2, h) * (1.0 - alpha);
			if (is_toon) {
				ca = step(0.35, ca) * 0.6 * cirrus;
			}
			col = mix(col, mix(cloud_color, cloud_shade, 0.25) + sun_color * pow(max(mu, 0.0), 6.0) * 0.4 * glow_amount, ca * 0.7);
		}
	}
	// A little of the halo glows over the clouds too (bright air near the sun).
	col += halo * 0.3;
	COLOR = col * energy;
}
