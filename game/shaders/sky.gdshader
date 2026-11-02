// céu de fim de tarde em tons pastel (pêssego → rosa → lavanda),
// sol com halo largo, nuvens pintadas iluminadas por trás (bordas douradas),
// cirros e estrelas tênues no zênite. As nuvens são calculadas no passe de
// meia resolução e só aparecem no fundo (não no cubemap de radiância): barato no celular.
shader_type sky;
render_mode use_half_res_pass;

uniform sampler2D cloud_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 zenith : source_color = vec3(0.36, 0.42, 0.78);
uniform vec3 upper : source_color = vec3(0.64, 0.58, 0.88);
uniform vec3 mid : source_color = vec3(0.98, 0.66, 0.74);
uniform vec3 horizon : source_color = vec3(1.0, 0.83, 0.66);
uniform vec3 below : source_color = vec3(0.98, 0.74, 0.74);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.93, 0.80);
uniform vec3 halo_tint : source_color = vec3(1.0, 0.62, 0.42);
uniform float sun_size = 0.035;
uniform float sun_energy = 9.0;
uniform float halo_energy = 0.55;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.86, 0.76);
uniform vec3 cloud_shadow : source_color = vec3(0.72, 0.56, 0.78);
uniform vec3 cloud_rim : source_color = vec3(1.0, 0.80, 0.52);
uniform float cloud_coverage = 0.48;
uniform float cloud_softness = 0.3;
uniform float cloud_scale = 0.35;
uniform float cirrus_amount = 0.55;
uniform vec2 cloud_wind = vec2(0.004, 0.0015);
uniform float star_amount = 0.25;
uniform float exposure = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 gradient(vec3 dir, vec3 sun_dir) {
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		float t = pow(y, 0.5);
		col = mix(horizon, mid, smoothstep(0.0, 0.28, t));
		col = mix(col, upper, smoothstep(0.22, 0.62, t));
		col = mix(col, zenith, smoothstep(0.55, 1.0, t));
	} else {
		col = mix(horizon, below, smoothstep(0.0, -0.25, y));
	}
	float d = max(dot(dir, sun_dir), 0.0);
	float side = pow(d, 4.0) * (1.0 - smoothstep(0.0, 0.7, abs(y)));
	col += halo_tint * side * 0.25;
	col += halo_tint * (pow(d, 18.0) * 0.55 + pow(d, 120.0) * 1.2) * halo_energy;
	return col;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.4, 0.3, -0.8));
	float d = max(dot(dir, sun_dir), 0.0);
	if (AT_HALF_RES_PASS) {
		// ------------------------------------------------ clouds (half resolution)
		vec3 col = gradient(dir, sun_dir);
		float yy = max(dir.y, 0.0);
		vec2 uv = dir.xz / (yy + 0.12) * cloud_scale;
		vec2 wind = cloud_wind * TIME;
		float base = texture(cloud_noise, uv * 0.35 + wind).r;
		float detail = texture(cloud_noise, uv * 1.3 + wind * 2.3).g;
		float weather = texture(cloud_noise, uv * 0.08 + wind * 0.3).a;
		float dens = base * 0.75 + detail * 0.3 + (weather - 0.5) * 0.5;
		float band = smoothstep(-0.01, 0.06, dir.y) * (1.0 - smoothstep(0.35, 0.75, yy));
		float a = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, dens) * band;
		vec2 sdir = normalize(sun_dir.xz + 1e-4);
		float dens2 = texture(cloud_noise, (uv + sdir * 0.06) * 0.35 + wind).r * 0.75 + detail * 0.3 + (weather - 0.5) * 0.5;
		float lit = clamp(0.55 + (dens - dens2) * 3.0, 0.0, 1.0);
		vec3 ccol = mix(cloud_shadow, cloud_lit, lit);
		ccol = mix(ccol, col * 1.05, 0.25 + 0.4 * (1.0 - band));
		float edge = smoothstep(cloud_coverage + cloud_softness, cloud_coverage, dens);
		ccol += cloud_rim * pow(d, 6.0) * edge * 2.2;
		ccol += cloud_rim * pow(d, 30.0) * 1.5;
		// cirrus streaks
		float ci = texture(cloud_noise, vec2(uv.x * 0.25, uv.y * 0.9) * 0.6 + wind * 0.6).b;
		float ca = smoothstep(0.55, 0.85, ci) * smoothstep(0.08, 0.35, yy) * cirrus_amount * 0.6;
		vec3 cir = mix(col, vec3(1.0, 0.9, 0.86), 0.7) + cloud_rim * pow(d, 10.0);
		float alpha = clamp(a + ca * (1.0 - a), 0.0, 1.0);
		vec3 outc = mix(cir, ccol, a / max(alpha, 1e-3));
		COLOR = clamp(outc, vec3(0.0), vec3(8.0)) * exposure;
		ALPHA = clamp(alpha, 0.0, 1.0);
	} else {
		vec3 col = gradient(dir, sun_dir);
		float disk = smoothstep(cos(sun_size * 1.25), cos(sun_size), d);
		if (!AT_CUBEMAP_PASS) {
			vec4 cl = HALF_RES_COLOR;
			cl.a = clamp(cl.a, 0.0, 1.0);
			cl.rgb = max(cl.rgb, vec3(0.0));
			// faint stars towards the zenith
			if (star_amount > 0.0) {
				vec2 sp = dir.xz / (dir.y + 1.0) * 220.0;
				float s = hash12(floor(sp));
				float tw = 0.6 + 0.4 * sin(TIME * 2.0 + s * 40.0);
				col += vec3(1.0, 0.95, 1.0) * step(0.9975, s) * smoothstep(0.45, 0.9, dir.y) * tw * star_amount;
			}
			col = mix(col * exposure, cl.rgb, cl.a) / max(exposure, 1e-3);
			disk *= clamp(1.0 - cl.a * 0.85, 0.0, 1.0);
		}
		col += sun_tint * disk * sun_energy;
		COLOR = max(col, vec3(0.0)) * exposure;
	}
}
