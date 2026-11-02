// SOPRO — ilhas de dunas: areia com brilho (glitter), ondulações do vento,
// areia molhada nas lagoas e arenito estratificado na "raiz" da ilha.
// Cores por vértice (geradas no Blender): R = oclusão, G = molhado, B = rocha, A = grama.
// Técnicas: brilho de areia "Journey" (John Edwards, GDC 2013 — reimplementado),
// luz envolvente (wrap) + rim de contraluz. Feito para o renderer Mobile (sem texturas
// pesadas: 1 textura de ruído compartilhada, o resto é procedural).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 sand_color : source_color = vec3(1.0, 0.94, 0.87);
uniform vec3 sand_shade : source_color = vec3(0.95, 0.85, 0.80);
uniform vec3 wet_color : source_color = vec3(0.80, 0.66, 0.58);
uniform vec3 grass_ground : source_color = vec3(0.60, 0.74, 0.55);
uniform vec3 rock_a : source_color = vec3(0.90, 0.60, 0.48);
uniform vec3 rock_b : source_color = vec3(0.95, 0.72, 0.56);
uniform vec3 rock_c : source_color = vec3(0.97, 0.82, 0.68);
uniform vec3 rock_d : source_color = vec3(0.62, 0.40, 0.46);
uniform vec3 cloud_bounce : source_color = vec3(1.0, 0.72, 0.70);
uniform float bounce_strength = 0.22;
uniform vec2 wind_dir = vec2(0.88, 0.47);
uniform float ripple_freq = 34.0;
uniform float ripple_strength = 0.16;
uniform float ripple_fade = 22.0;
uniform float glitter_density = 26.0;
uniform float glitter_strength = 2.2;
uniform float glitter_fade = 34.0;
uniform float wrap = 0.45;
uniform float sheen_strength = 0.55;
uniform vec3 sheen_color : source_color = vec3(1.0, 0.86, 0.72);
uniform float strata_scale = 2.6;

varying vec3 w_pos;
varying vec3 w_nrm;
varying float v_rock;
varying float v_glint;
varying vec3 v_glint_n;
varying float v_sand;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 c = COLOR;
	float ao = c.r;
	float wet = c.g;
	float rock = smoothstep(0.35, 0.65, c.b);
	float grass = c.a;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	vec3 wn = normalize(w_nrm);

	// ---------------------------------------------------------------- sand
	float big = texture(noise_tex, w_pos.xz * 0.013).a;
	float mid = texture(noise_tex, w_pos.xz * 0.06).r;
	vec3 sand = mix(sand_shade, sand_color, smoothstep(0.25, 0.8, big * 0.6 + mid * 0.5));
	// ripples (normal only), along the wind, fading with distance, slope and water
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float rfade = (1.0 - smoothstep(ripple_fade * 0.35, ripple_fade, dist)) * (1.0 - smoothstep(0.25, 0.6, slope)) * (1.0 - wet);
	vec2 rp = w_pos.xz;
	float warp = texture(noise_tex, rp * 0.045).g * 2.2 + texture(noise_tex, rp * 0.13).r * 0.8;
	float ph = dot(rp, wind_dir) * ripple_freq + warp * 2.6;
	// anti-aliasing: fade the ripples where they get smaller than ~2 pixels
	float pw = fwidth(ph) / 6.2831853;
	rfade *= 1.0 - smoothstep(0.15, 0.4, pw);
	// smooth asymmetric ripple (gentle windward, steeper lee): h = sin + 0.25 sin2
	float dh = cos(ph) + 0.5 * cos(2.0 * ph);
	vec2 grad = wind_dir * dh * ripple_strength * rfade * (0.65 + 0.35 * mid);
	vec3 pn = normalize(wn + vec3(-grad.x, 0.0, -grad.y) * (1.0 - rock));
	sand *= 1.0 - 0.025 * rfade * (0.5 + 0.5 * sin(ph + 1.2));

	vec3 wetc = mix(wet_color, wet_color * vec3(0.78, 0.92, 0.95), smoothstep(0.6, 1.0, wet));
	vec3 top = mix(sand, wetc, smoothstep(0.15, 0.8, wet));
	top = mix(top, grass_ground * (0.85 + 0.3 * mid), smoothstep(0.1, 0.8, grass) * 0.55);

	// ---------------------------------------------------------------- sandstone
	float n1 = texture(noise_tex, vec2(w_pos.x + w_pos.z, w_pos.y * 0.3) * 0.03).r;
	float band = w_pos.y / strata_scale + n1 * 2.4 + texture(noise_tex, w_pos.xz * 0.02).a * 1.4 + texture(noise_tex, vec2(w_pos.x - w_pos.z, w_pos.y) * 0.08).g * 0.5;
	float f = fract(band);
	float idx = mod(floor(band), 4.0);
	vec3 s0 = idx < 1.0 ? rock_a : (idx < 2.0 ? rock_b : (idx < 3.0 ? rock_c : rock_b));
	vec3 s1 = idx < 1.0 ? rock_b : (idx < 2.0 ? rock_c : (idx < 3.0 ? rock_b : rock_a));
	vec3 strata = mix(s0, s1, smoothstep(0.82, 0.95, f));
	strata = mix(strata, rock_d, smoothstep(0.55, 0.0, f) * 0.18);
	// vertical drip stains
	float drip = texture(noise_tex, vec2((w_pos.x - w_pos.z) * 0.18, w_pos.y * 0.012)).g;
	strata *= 1.0 - 0.22 * smoothstep(0.55, 0.85, drip);
	// darker deeper down (less sky light), warm towards the top
	float depth01 = clamp(-w_pos.y / 55.0, 0.0, 1.0);
	strata = mix(strata, rock_d, depth01 * 0.45);

	vec3 col = mix(top, strata, rock);
	col *= mix(0.62, 1.0, ao);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, wet * (1.0 - rock));
	AO = mix(1.0, ao, 0.85);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);
	// warm bounce light from the sunlit cloud sea below
	float down = clamp(-wn.y, 0.0, 1.0);
	EMISSION = cloud_bounce * col * down * bounce_strength * (0.4 + 0.6 * depth01);

	// glitter: random micro-facets on the dry sand
	vec3 cell = floor(w_pos * glitter_density);
	vec3 h = hash33(cell);
	vec3 fc = fract(w_pos * glitter_density) - 0.5;
	float dotm = smoothstep(0.32, 0.12, length(fc - (h - 0.5) * 0.3));
	float sparkle_cell = step(0.86, h.x) * dotm;
	vec3 gn = normalize(vec3(h.y * 2.0 - 1.0, 1.6, h.z * 2.0 - 1.0));
	v_glint_n = normalize((VIEW_MATRIX * vec4(normalize(mix(gn, pn, 0.25)), 0.0)).xyz);
	v_glint = sparkle_cell * (1.0 - rock) * (1.0 - smoothstep(0.1, 0.5, wet)) * (1.0 - smoothstep(glitter_fade * 0.4, glitter_fade, dist)) * (1.0 - grass);
	v_rock = rock;
	v_sand = 1.0 - rock;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	// soft "ocean" sheen on the sand when looking towards the light (backlit crests)
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 4.0) * (0.25 + 0.75 * back * back);
	SPECULAR_LIGHT += sheen_color * rim * sheen_strength * v_sand * ATTENUATION * LIGHT_COLOR / PI;
	// glitter
	vec3 hv = normalize(LIGHT + VIEW);
	float g = pow(clamp(dot(v_glint_n, hv), 0.0, 1.0), 180.0);
	SPECULAR_LIGHT += vec3(1.0, 0.97, 0.9) * g * v_glint * glitter_strength * ATTENUATION * LIGHT_COLOR;
}
