// AURELITH — areia do deserto contínuo, no espírito do Journey (thatgamecompany):
// técnicas da palestra de John Edwards "Sand Rendering in Journey" (GDC 2013),
// reimplementadas para o renderer Mobile do Godot:
//   * difuso com "contraste" (normal achatada em Y: encostas dominam a luz),
//   * normais de grão (ruído fino) + ondulações do vento (só nas encostas suaves),
//   * "ocean specular": brilho largo e ondulante nas dunas voltadas ao sol,
//   * glitter: microfacetas aleatórias que cintilam quando refletem o sol,
//   * rim de contraluz nas cristas, cor por distância/altura, arenito estratificado.
// Geometria: LOD contínuo estilo CDLOD (nós em MultiMesh com morph) + dunas
// procedurais infinitas fora do mapa jogável. Rastros: textura dinâmica (SandTrails).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D masks : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D trail_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 trail_rect = vec4(-64.0, -64.0, 128.0, 128.0);   // x, z, size, strength
uniform float map_half = 512.0;
uniform float map_res = 1025.0;
uniform float cell_size = 1.0;
uniform vec2 height_range = vec2(0.0, 60.0);
uniform float grid_dim = 32.0;
uniform vec4 lod_ranges_0 = vec4(56.0, 112.0, 224.0, 448.0);
uniform vec4 lod_ranges_1 = vec4(896.0, 1792.0, 3584.0, 7168.0);
uniform vec4 lod_ranges_2 = vec4(14336.0, 28672.0, 0.0, 0.0);
uniform float far_base = 20.0;          // average height of the map border (horizon dunes)
uniform float far_amplitude = 26.0;
uniform vec2 wind_dir = vec2(0.9, 0.43);

// palette (pastel desert at golden hour)
uniform vec3 sand_light : source_color = vec3(1.0, 0.80, 0.52);
uniform vec3 sand_mid : source_color = vec3(0.96, 0.62, 0.40);
uniform vec3 sand_deep : source_color = vec3(0.86, 0.49, 0.38);
uniform vec3 packed_color : source_color = vec3(0.84, 0.58, 0.46);
uniform vec3 glass_color : source_color = vec3(0.92, 0.86, 0.98);
uniform vec3 rock_a : source_color = vec3(0.80, 0.46, 0.38);
uniform vec3 rock_b : source_color = vec3(0.93, 0.66, 0.52);
uniform vec3 rock_c : source_color = vec3(0.70, 0.40, 0.42);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.52, 0.86);
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.70);
uniform vec3 spec_color : source_color = vec3(1.0, 0.90, 0.74);
uniform vec3 glitter_color : source_color = vec3(1.0, 0.97, 0.90);
uniform float diffuse_contrast = 4.0;   // Journey: saturate(4 * dot(N * (1, .3, 1), L))
uniform float detail_contrast = 1.6;    // ripples/grain/trails: real tilt, not amplified 4x
uniform float normal_y_squash = 0.3;
uniform float grain_strength = 0.18;
uniform float ripple_strength = 0.2;
uniform float ripple_freq = 34.0;
uniform float ocean_spec_power = 42.0;
uniform float ocean_spec_strength = 0.42;
uniform float rim_power = 4.0;
uniform float rim_strength = 0.45;
uniform float glitter_density = 30.0;
uniform float glitter_fraction = 0.22;
uniform float glitter_strength = 3.2;

varying vec3 w_pos;
varying vec3 v_wn;          // world normal (vertex, for outside the map)
varying float v_inside;
varying vec3 v_detail_wn;
varying vec3 v_macro_wn;   // world normal with grain/ripples (fragment -> light)
varying float v_glint;
varying vec3 v_glint_vn;
varying float v_sand;       // 1 sand, 0 rock
varying float v_ocean;      // ocean specular mask (dry sand on gentle slopes)

float lod_range(int l) {
	if (l < 4) return lod_ranges_0[l];
	if (l < 8) return lod_ranges_1[l - 4];
	return lod_ranges_2[l - 8];
}

float map_height(vec2 xz) {
	vec2 t = clamp((xz + vec2(map_half)) / cell_size, vec2(0.0), vec2(map_res - 1.001));
	ivec2 i = ivec2(floor(t));
	vec2 f = t - vec2(i);
	float h00 = texelFetch(heightmap, i, 0).r;
	float h10 = texelFetch(heightmap, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(heightmap, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

float dune_prof(float ph) {
	// windward rise over 75% of the wavelength, lee face over 25%; C1-smooth crest/trough
	float fr = fract(ph);
	return fr < 0.75 ? smoothstep(0.0, 0.75, fr) : smoothstep(1.0, 0.75, fr);
}

float far_dunes(vec2 xz, vec2 cam) {
	vec2 w = normalize(wind_dir);
	float along = dot(xz, w);
	float across = dot(xz, vec2(-w.y, w.x));
	float warp = (textureLod(noise_tex, xz * 0.0009, 0.0).r - 0.5) * 260.0;
	float big = dune_prof((along + warp + sin(across * 0.0035) * 70.0) / 420.0);
	float fine = dune_prof((along + warp * 0.6 + sin(across * 0.006) * 40.0 + 37.0) / 170.0);
	// the fine octave fades out where the LOD grid gets too coarse to carry it
	float fine_k = 1.0 - smoothstep(450.0, 1100.0, distance(xz, cam));
	float amp = far_amplitude * (0.35 + textureLod(noise_tex, xz * 0.0006 + 0.3, 0.0).a);
	float prof = big * 0.8 + fine * 0.4 * fine_k;
	return far_base + prof * amp + (textureLod(noise_tex, xz * 0.0004, 0.0).g - 0.5) * 40.0;
}

float inside_k(vec2 xz) {
	return smoothstep(map_half, map_half - 48.0, max(abs(xz.x), abs(xz.y)));
}

float world_height(vec2 xz, vec2 cam) {
	float k = inside_k(xz);
	if (k >= 0.999) {
		return map_height(xz);
	}
	float hf = far_dunes(xz, cam);
	if (k <= 0.001) {
		return hf;
	}
	return mix(hf, map_height(xz), k);
}

vec2 map_uv(vec2 xz) {
	return ((xz + vec2(map_half)) / cell_size + 0.5) / map_res;
}

void vertex() {
	vec4 inst = INSTANCE_CUSTOM;
	vec2 origin = inst.xy;
	float nsize = inst.z;
	int level = int(inst.w + 0.5);
	vec2 g = VERTEX.xz;
	vec2 xz = origin + g * nsize;
	float h0 = world_height(xz, CAMERA_POSITION_WORLD.xz);
	float r1 = lod_range(level);
	float r0 = level > 0 ? lod_range(level - 1) : 0.0;
	float m_start = mix(r0, r1, 0.68);
	float dist = distance(CAMERA_POSITION_WORLD, vec3(xz.x, h0, xz.y));
	float k = clamp((dist - m_start) / max(r1 - m_start, 1.0), 0.0, 1.0);
	vec2 frac_part = fract(g * grid_dim * 0.5) * 2.0 / grid_dim;
	xz -= frac_part * nsize * k;
	float h = world_height(xz, CAMERA_POSITION_WORLD.xz);
	VERTEX = vec3(xz.x, h, xz.y);
	float ik = inside_k(xz);
	v_inside = ik;
	vec3 n;
	if (ik > 0.999) {
		n = normalize(textureLod(normalmap, map_uv(xz), 0.0).xyz * 2.0 - 1.0);
	} else {
		float e = max(nsize / grid_dim, 2.0);
		float hx = world_height(xz + vec2(e, 0.0), CAMERA_POSITION_WORLD.xz) - world_height(xz - vec2(e, 0.0), CAMERA_POSITION_WORLD.xz);
		float hz = world_height(xz + vec2(0.0, e), CAMERA_POSITION_WORLD.xz) - world_height(xz - vec2(0.0, e), CAMERA_POSITION_WORLD.xz);
		n = normalize(vec3(-hx, 2.0 * e, -hz));
	}
	NORMAL = n;
	v_wn = n;
	w_pos = VERTEX;
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void fragment() {
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	vec2 uv = map_uv(w_pos.xz);
	vec3 wn = v_wn;
	vec4 m = vec4(0.0, 0.0, 0.0, 0.6);
	if (v_inside > 0.001) {
		vec3 mn = normalize(texture(normalmap, uv).xyz * 2.0 - 1.0);
		wn = normalize(mix(v_wn, mn, v_inside));
		m = mix(m, texture(masks, uv), v_inside);
	}
	float rock = smoothstep(0.25, 0.6, m.r);
	float packed = m.g;
	float glass = m.b;
	float windy = m.a;
	float sand = 1.0 - rock;
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);

	// ---------------------------------------------------------------- sand detail
	float near = 1.0 - smoothstep(20.0, 70.0, dist);
	float n_big = texture(noise_tex, w_pos.xz * 0.006).a;
	float n_mid = texture(noise_tex, w_pos.xz * 0.045).r;
	// wind ripples: only on gentle slopes, AA by derivative
	vec2 wd = normalize(wind_dir);
	float warp = texture(noise_tex, w_pos.xz * 0.04).g * 2.0 + texture(noise_tex, w_pos.xz * 0.11).r * 0.7;
	float ph = dot(w_pos.xz, wd) * ripple_freq + warp * 3.0;
	float pw = fwidth(ph) / 6.2831853;
	float rfade = near * (1.0 - smoothstep(0.12, 0.38, pw)) * (1.0 - smoothstep(0.18, 0.45, slope)) * sand * (1.0 - packed * 0.7);
	rfade *= 0.55 + 0.45 * windy;
	float dh = cos(ph) + 0.5 * cos(2.0 * ph);
	vec2 rgrad = wd * dh * ripple_strength * rfade;
	// grain normal (tiny random bumps)
	vec2 gr = (texture(noise_tex, w_pos.xz * 1.7).rg - 0.5) * 2.0;
	vec2 ggrad = gr * grain_strength * (1.0 - smoothstep(6.0, 40.0, dist)) * sand;
	// trails (footprints / surf grooves)
	vec2 tuv = (w_pos.xz - trail_rect.xy) / trail_rect.z;
	float trail = 0.0;
	vec2 tgrad = vec2(0.0);
	if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) {
		float edge = smoothstep(0.0, 0.08, min(min(tuv.x, tuv.y), min(1.0 - tuv.x, 1.0 - tuv.y)));
		trail = texture(trail_tex, tuv).r * edge * trail_rect.w;
		float px = 1.0 / 512.0;
		float tx = texture(trail_tex, tuv + vec2(px, 0.0)).r - texture(trail_tex, tuv - vec2(px, 0.0)).r;
		float tz = texture(trail_tex, tuv + vec2(0.0, px)).r - texture(trail_tex, tuv - vec2(0.0, px)).r;
		tgrad = vec2(tx, tz) * 4.0 * edge * trail_rect.w;
		rgrad *= 1.0 - trail;
	}
	vec3 dn = normalize(wn + vec3(-(rgrad.x + ggrad.x - tgrad.x), 0.0, -(rgrad.y + ggrad.y - tgrad.y)));

	// ---------------------------------------------------------------- albedo
	float hk = clamp((w_pos.y - height_range.x) / max(height_range.y - height_range.x, 1.0), 0.0, 1.0);
	vec3 sandc = mix(sand_deep, sand_mid, smoothstep(0.0, 0.55, hk));
	sandc = mix(sandc, sand_light, smoothstep(0.35, 1.0, hk) * 0.7 + n_big * 0.25);
	sandc *= 0.94 + 0.12 * n_mid;
	sandc = mix(sandc, packed_color, packed * 0.6);
	sandc = mix(sandc, glass_color, glass * 0.55);
	sandc *= 1.0 - 0.3 * clamp(trail, 0.0, 1.0);
	// sandstone strata on cliffs
	float band = w_pos.y / 2.4 + texture(noise_tex, vec2(w_pos.x + w_pos.z, w_pos.y * 0.3) * 0.03).r * 2.4;
	float f = fract(band);
	float bi = mod(floor(band), 3.0);
	vec3 s0 = bi < 1.0 ? rock_a : (bi < 2.0 ? rock_b : rock_c);
	vec3 s1 = bi < 1.0 ? rock_b : (bi < 2.0 ? rock_c : rock_a);
	vec3 strata = mix(s0, s1, smoothstep(0.8, 0.95, f));
	strata *= 0.85 + 0.2 * texture(noise_tex, vec2((w_pos.x - w_pos.z) * 0.15, w_pos.y * 0.02)).g;
	vec3 albedo = mix(sandc, strata, rock);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.95, 0.85, rock);
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(dn, 0.0)).xyz);
	v_detail_wn = dn;
	v_macro_wn = wn;
	v_sand = sand;
	v_ocean = sand * (1.0 - smoothstep(0.3, 0.6, slope)) * (1.0 - trail * 0.6) * (1.0 - packed * 0.5);
	// glitter: sparse random micro facets (world-space cells)
	vec3 cell = floor(w_pos * glitter_density);
	vec3 hsh = hash33(cell);
	vec3 fc = fract(w_pos * glitter_density) - 0.5;
	float dotm = smoothstep(0.34, 0.1, length(fc.xz));
	vec3 gn = normalize(vec3(hsh.x * 2.0 - 1.0, 1.2, hsh.y * 2.0 - 1.0));
	v_glint_vn = normalize((VIEW_MATRIX * vec4(gn, 0.0)).xyz);
	v_glint = step(1.0 - (glitter_fraction + glass * 0.4), hsh.z) * dotm * sand
		* (1.0 - smoothstep(18.0, 60.0, dist)) * (1.0 - trail);
}

void light() {
	vec3 Lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
	vec3 Vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 n = normalize(v_detail_wn);
	vec3 nm = normalize(v_macro_wn);
	// Journey diffuse contrast on the dune shape: flatten Y so slopes facing the sun pop
	float d = clamp(diffuse_contrast * dot(normalize(nm * vec3(1.0, normal_y_squash, 1.0)), Lw), 0.0, 1.0);
	float wrap = clamp(dot(nm, Lw) * 0.5 + 0.5, 0.0, 1.0);
	d = mix(d, wrap, 0.25);
	// small-scale relief (ripples, grain, footprints) shaded by its real tilt
	d = clamp(d + (dot(n, Lw) - dot(nm, Lw)) * detail_contrast, 0.0, 1.0) * ATTENUATION;
	DIFFUSE_LIGHT += mix(shadow_tint * 0.18, vec3(1.0), d) * LIGHT_COLOR / PI;
	// ocean specular: broad, wavy highlight on dunes facing the sun
	vec3 h = normalize(Lw + Vw);
	float nh = clamp(dot(n, h), 0.0, 1.0);
	SPECULAR_LIGHT += spec_color * pow(nh, ocean_spec_power) * ocean_spec_strength * v_ocean * ATTENUATION * LIGHT_COLOR / PI;
	// rim: bright crests against the sky, strongest when backlit
	float ndv = clamp(dot(n, Vw), 0.0, 1.0);
	float back = clamp(dot(-Vw, Lw) * 0.5 + 0.5, 0.0, 1.0);
	SPECULAR_LIGHT += rim_color * pow(1.0 - ndv, rim_power) * rim_strength * (0.35 + 0.65 * back) * v_sand * LIGHT_COLOR / PI;
	// glitter
	vec3 hv = normalize(LIGHT + VIEW);
	float g = pow(clamp(dot(v_glint_vn, hv), 0.0, 1.0), 220.0);
	SPECULAR_LIGHT += glitter_color * g * v_glint * glitter_strength * ATTENUATION * LIGHT_COLOR;
}
