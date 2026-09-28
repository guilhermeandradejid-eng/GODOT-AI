// Shared code for every Vibe terrain style: heightmap displacement, splat
// weights, noise helpers, textured (PBR) layer sampling, the distant-hills
// horizon ring and the ground tint painted by grass layers.
//
// Techniques adapted from Terrain3D (MIT, Cory Petkovsek, Roope Palmroos and
// contributors, github.com/TokisanGames/Terrain3D): height-based blending,
// UV detiling by random rotation per tile and macro variation; triplanar
// normal blending after Ben Golus ("Normal Mapping for a Triplanar Shader").

uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D splatmap : filter_linear, repeat_disable;
uniform float cell_size = 1.0;
uniform float terrain_half_size = 128.0;
uniform float skirt_depth = 2.0;
uniform float blend_sharpness : hint_range(0.5, 6.0) = 1.6;
uniform float height_blend : hint_range(0.0, 1.0) = 0.6;
uniform float macro_variation : hint_range(0.0, 0.6) = 0.18;
uniform float detail_fade_distance = 350.0;
// Textured layers blend to a larger-scale sample and then toward their average
// color between these distances (hides tiling and the detiling mosaic far away).
uniform float far_start = 35.0;
uniform float far_end = 260.0;
// Low poly: random horizontal offset of the grid vertices (breaks the grid look).
uniform float vertex_jitter = 0.0;

uniform vec3 layer0_color_a : source_color = vec3(0.2, 0.32, 0.12);
uniform vec3 layer0_color_b : source_color = vec3(0.35, 0.48, 0.18);
uniform vec3 layer0_tint : source_color = vec3(1.0);
uniform float layer0_noise_scale = 0.12;
uniform float layer0_strata = 0.0;
uniform float layer0_roughness = 0.9;
uniform float layer0_emission = 0.0;
uniform float layer0_uv_scale = 4.0;
uniform bool layer0_use_albedo = false;
uniform bool layer0_use_normal = false;
uniform sampler2D layer0_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer0_normal : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 layer1_color_a : source_color = vec3(0.31, 0.23, 0.16);
uniform vec3 layer1_color_b : source_color = vec3(0.46, 0.35, 0.23);
uniform vec3 layer1_tint : source_color = vec3(1.0);
uniform float layer1_noise_scale = 0.5;
uniform float layer1_strata = 0.0;
uniform float layer1_roughness = 0.95;
uniform float layer1_emission = 0.0;
uniform float layer1_uv_scale = 4.0;
uniform bool layer1_use_albedo = false;
uniform bool layer1_use_normal = false;
uniform sampler2D layer1_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer1_normal : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 layer2_color_a : source_color = vec3(0.36, 0.35, 0.33);
uniform vec3 layer2_color_b : source_color = vec3(0.56, 0.54, 0.51);
uniform vec3 layer2_tint : source_color = vec3(1.0);
uniform float layer2_noise_scale = 0.25;
uniform float layer2_strata = 0.35;
uniform float layer2_roughness = 0.85;
uniform float layer2_emission = 0.0;
uniform float layer2_uv_scale = 6.0;
uniform bool layer2_use_albedo = false;
uniform bool layer2_use_normal = false;
uniform sampler2D layer2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer2_normal : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 layer3_color_a : source_color = vec3(0.87, 0.9, 0.94);
uniform vec3 layer3_color_b : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 layer3_tint : source_color = vec3(1.0);
uniform float layer3_noise_scale = 0.3;
uniform float layer3_strata = 0.0;
uniform float layer3_roughness = 0.55;
uniform float layer3_emission = 0.0;
uniform float layer3_uv_scale = 5.0;
uniform bool layer3_use_albedo = false;
uniform bool layer3_use_normal = false;
uniform sampler2D layer3_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer3_normal : filter_linear_mipmap_anisotropic, repeat_enable;

// Editor brush cursor (terrain local space). radius <= 0 hides it.
uniform vec3 brush_position = vec3(0.0);
uniform float brush_radius = 0.0;
uniform vec4 brush_color : source_color = vec4(1.0, 0.75, 0.2, 1.0);

// Ground tint where grass grows, set by VibeGrass3D nodes (up to 3 layers).
// near = ground color under the blades, far = average blade color seen from
// afar (rgb, strength in alpha); range = that grass layer's view distance.
uniform sampler2D grass_map_0 : filter_linear, repeat_disable;
uniform sampler2D grass_map_1 : filter_linear, repeat_disable;
uniform sampler2D grass_map_2 : filter_linear, repeat_disable;
uniform vec4 grass_near_0 : source_color = vec4(0.0);
uniform vec4 grass_near_1 : source_color = vec4(0.0);
uniform vec4 grass_near_2 : source_color = vec4(0.0);
uniform vec4 grass_far_0 : source_color = vec4(0.0);
uniform vec4 grass_far_1 : source_color = vec4(0.0);
uniform vec4 grass_far_2 : source_color = vec4(0.0);
uniform float grass_range_0 = 70.0;
uniform float grass_range_1 = 70.0;
uniform float grass_range_2 = 70.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec2 v_splat_uv;
varying vec3 v_normal_ws;
// Per-triangle (provoking vertex) data for the low-poly style.
varying flat vec4 v_flat_splat;
varying flat float v_flat_rand;
varying flat vec2 v_flat_uv;
// 1 on steep slopes of the horizon hills (painted with the cliff layer).
varying float v_ring_rock;

float t_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float t_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float t_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(t_hash13(i), t_hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(t_hash13(i + vec3(0.0, 1.0, 0.0)), t_hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(t_hash13(i + vec3(0.0, 0.0, 1.0)), t_hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(t_hash13(i + vec3(0.0, 1.0, 1.0)), t_hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float t_fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * t_vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s / 0.875;
}

// Procedural surface color for layers without texture (and for stylized styles).
// Returns rgb + a pseudo height in alpha (used for height blending).
vec4 procedural_layer(vec3 ca, vec3 cb, float scale, float strata, float emission, vec3 p, float detail) {
	vec3 q = p;
	if (emission > 0.0) {
		q += vec3(TIME * 0.12, 0.0, TIME * 0.05);
	}
	float n = mix(0.5, t_fbm(q * scale), detail);
	float grain = mix(0.5, t_vnoise(q * scale * 9.0), detail * 0.6);
	vec3 col = mix(ca, cb, smoothstep(0.1, 0.9, n));
	col *= 0.92 + 0.16 * grain;
	if (strata > 0.0) {
		float warp = t_fbm(p * 0.035) * 7.0;
		float band = sin(p.y * 1.3 + warp) * 0.5 + 0.5;
		float band2 = sin(p.y * 0.37 + warp * 0.5 + 1.7) * 0.5 + 0.5;
		vec3 banded = mix(ca, cb, band * 0.65 + band2 * 0.35);
		col = mix(col, banded * (0.85 + 0.3 * grain), strata);
	}
	return vec4(col, n * 0.8 + grain * 0.2);
}

// Splat weights with a little noise break-up, before height blending.
vec4 raw_weights() {
	vec4 w = texture(splatmap, v_splat_uv);
	w = mix(w, vec4(0.0, 0.0, 1.0, 0.0), v_ring_rock);
	float breakup = t_fbm(v_local * 0.3);
	w = max(w + (breakup - 0.5) * 0.3 * w * (1.0 - w) * 4.0, vec4(0.0));
	return w / max(w.x + w.y + w.z + w.w, 0.0001);
}

// Height-based blending: layers with higher "height" win at transitions.
vec4 height_blend_weights(vec4 w, vec4 h, float depth) {
	vec4 b = w + h * height_blend;
	float ma = max(max(b.x, b.y), max(b.z, b.w)) - depth;
	vec4 r = max(b - vec4(ma), vec4(0.0)) * step(vec4(0.0005), w);
	r = pow(r, vec4(blend_sharpness * 0.6));
	return r / max(r.x + r.y + r.z + r.w, 0.0001);
}

// Random rotation per tile to hide texture repetition (detiling).
vec2 detile(vec2 uv, out mat2 rot) {
	vec2 cell = floor(uv + 0.5);
	float a = (t_hash12(cell) * 2.0 - 1.0) * 3.14159;
	float c = cos(a);
	float s = sin(a);
	rot = mat2(vec2(c, s), vec2(-s, c));
	return rot * (uv - cell) + cell + t_hash12(cell + 7.1);
}

vec3 unpack_normal(vec4 nr) {
	vec3 n = nr.rgb * 2.0 - 1.0;
	return normalize(vec3(n.x, n.y, max(n.z, 0.05)));
}

// Samples a packed layer (albedo+height / normal+roughness) with triplanar
// projection on steep terrain. dpdx/dpdy are the screen-space derivatives of p,
// taken once in uniform control flow (so mip selection stays valid inside
// branches and across detiling cells). far (0..1) blends to a larger-scale
// sample and toward the average color of the texture.
// Returns albedo+height; out world normal & roughness.
vec4 sample_layer(sampler2D alb_tex, sampler2D nrm_tex, bool has_normal, float uv_scale, vec3 p, vec3 dpdx, vec3 dpdy,
		vec3 n_ws, float fallback_rough, float far, out vec3 out_normal, out float out_rough) {
	vec3 blend = pow(abs(n_ws), vec3(6.0));
	blend /= (blend.x + blend.y + blend.z);
	float inv = 1.0 / uv_scale;
	mat2 rot;
	vec2 uv_y = detile(p.xz * inv, rot);
	vec2 gx = rot * (dpdx.xz * inv);
	vec2 gy = rot * (dpdy.xz * inv);
	vec4 alb = textureGrad(alb_tex, uv_y, gx, gy);
	vec4 nr = has_normal ? textureGrad(nrm_tex, uv_y, gx, gy) : vec4(0.5, 0.5, 1.0, fallback_rough);
	vec3 tn_y = unpack_normal(nr);
	// Rotate the tangent-space normal back (inverse of the detile UV rotation).
	tn_y.xy = tn_y.xy * rot;
	vec3 wn = vec3(tn_y.x + n_ws.x, n_ws.y * tn_y.z, tn_y.y * -1.0 + n_ws.z);
	float rough = nr.a;
	if (blend.y < 0.98) {
		vec2 uv_x = p.zy * inv;
		vec2 uv_z = p.xy * inv;
		vec2 gxx = dpdx.zy * inv;
		vec2 gxy = dpdy.zy * inv;
		vec2 gzx = dpdx.xy * inv;
		vec2 gzy = dpdy.xy * inv;
		// Cliffs: two scales mixed by a soft noise mask, so big rock faces do
		// not show the texture grid.
		float k2 = 0.43;
		float mask = smoothstep(0.3, 0.7, t_vnoise(p * 0.045));
		vec4 alb_x = mix(textureGrad(alb_tex, uv_x, gxx, gxy), textureGrad(alb_tex, uv_x * k2 + 0.37, gxx * k2, gxy * k2), mask);
		vec4 alb_z = mix(textureGrad(alb_tex, uv_z, gzx, gzy), textureGrad(alb_tex, uv_z * k2 + 0.61, gzx * k2, gzy * k2), mask);
		vec4 nr_x = has_normal ? mix(textureGrad(nrm_tex, uv_x, gxx, gxy), textureGrad(nrm_tex, uv_x * k2 + 0.37, gxx * k2, gxy * k2), mask) : vec4(0.5, 0.5, 1.0, fallback_rough);
		vec4 nr_z = has_normal ? mix(textureGrad(nrm_tex, uv_z, gzx, gzy), textureGrad(nrm_tex, uv_z * k2 + 0.61, gzx * k2, gzy * k2), mask) : vec4(0.5, 0.5, 1.0, fallback_rough);
		vec3 tn_x = unpack_normal(nr_x);
		vec3 tn_z = unpack_normal(nr_z);
		// UDN blend (Ben Golus)
		// Green is "up" in OpenGL normal maps (= -v), hence the minus signs.
		vec3 wx = vec3(n_ws.x, -tn_x.y + n_ws.y, tn_x.x + n_ws.z);
		vec3 wz = vec3(tn_z.x + n_ws.x, -tn_z.y + n_ws.y, n_ws.z);
		alb = alb_x * blend.x + alb * blend.y + alb_z * blend.z;
		wn = wx * blend.x + wn * blend.y + wz * blend.z;
		rough = nr_x.a * blend.x + rough * blend.y + nr_z.a * blend.z;
	}
	if (far > 0.001) {
		// Far away: a larger-scale sample, then the texture's average color (no
		// repetition toward the horizon). Steep faces use the average directly.
		float k = 0.21;
		vec2 uv_m = p.xz * inv * k + vec2(0.37, 0.61);
		vec4 alb_m = textureGrad(alb_tex, uv_m, dpdx.xz * inv * k, dpdy.xz * inv * k);
		vec4 avg = textureLod(alb_tex, vec2(0.5), 14.0);
		alb_m = mix(alb_m, avg, max(0.3 + 0.7 * smoothstep(0.35, 1.0, far), 1.0 - blend.y));
		float fm = smoothstep(0.0, 0.6, far);
		alb = mix(alb, alb_m, fm);
		wn = mix(normalize(wn), n_ws, fm * 0.7);
	}
	out_normal = normalize(wn);
	out_rough = has_normal ? rough : fallback_rough;
	return alb;
}

// One grass layer painted over the ground color. hard = 1 gives flat,
// crisp-edged patches (toon / cel / low poly). variation (0..1, e.g. the
// texture height) keeps some light/dark detail under the tint; it does not
// depend on the color space (Compatibility runs fragment() in sRGB, Forward+
// in linear), so both renderers look alike.
vec3 grass_over(vec3 col, inout float amount, sampler2D map, vec4 near_c, vec4 far_c, float range, float dist, vec2 uv, float hard, float variation) {
	if (far_c.a <= 0.0) {
		return col;
	}
	float d = textureLod(map, uv, 0.0).r;
	float cover = mix(smoothstep(0.03, 0.6, d), step(0.3, d), hard);
	vec4 c = mix(near_c, far_c, smoothstep(range * 0.3, range * 0.95, dist));
	float a = cover * c.a;
	amount = max(amount, a);
	vec3 target = c.rgb * mix(1.0, 0.8 + 0.4 * variation, 1.0 - hard);
	return mix(col, target, a);
}

// Ground color where grass grows, so the terrain reads as grass from afar
// (where blades are no longer drawn). amount = strongest grass coverage.
vec3 apply_grass(vec3 col, float dist, vec2 uv, float hard, float variation, out float amount) {
	amount = 0.0;
	col = grass_over(col, amount, grass_map_0, grass_near_0, grass_far_0, grass_range_0, dist, uv, hard, variation);
	col = grass_over(col, amount, grass_map_1, grass_near_1, grass_far_1, grass_range_1, dist, uv, hard, variation);
	col = grass_over(col, amount, grass_map_2, grass_near_2, grass_far_2, grass_range_2, dist, uv, hard, variation);
	return col;
}

void vertex() {
	vec3 mesh_normal = NORMAL;
	// Horizon ring vertices lie outside the heightmap square; their VERTEX.y
	// holds the extra height of the distant hills and NORMAL their normal.
	bool ring = max(abs(VERTEX.x), abs(VERTEX.z)) > terrain_half_size + 0.01;
	ivec2 size = textureSize(heightmap, 0);
	vec2 texel = (VERTEX.xz + vec2(terrain_half_size)) / cell_size;
	ivec2 c = clamp(ivec2(round(texel)), ivec2(0), size - 1);
	float h = texelFetch(heightmap, c, 0).r;
	float hl = texelFetch(heightmap, clamp(c + ivec2(-1, 0), ivec2(0), size - 1), 0).r;
	float hr = texelFetch(heightmap, clamp(c + ivec2(1, 0), ivec2(0), size - 1), 0).r;
	float hd = texelFetch(heightmap, clamp(c + ivec2(0, -1), ivec2(0), size - 1), 0).r;
	float hu = texelFetch(heightmap, clamp(c + ivec2(0, 1), ivec2(0), size - 1), 0).r;
	vec3 n = normalize(vec3(hl - hr, 2.0 * cell_size, hd - hu));
	if (ring) {
		VERTEX.y = h + VERTEX.y;
		n = normalize(mesh_normal);
	} else {
		// Skirt vertices have y = -1: pushed down to hide cracks between LODs.
		VERTEX.y = h + VERTEX.y * skirt_depth;
	}
	if (!ring && vertex_jitter > 0.0) {
		vec2 j = vec2(t_hash12(vec2(c) + 3.7), t_hash12(vec2(c) + 11.3)) - 0.5;
		// The outer border stays straight so it still meets the horizon ring.
		j *= vec2((c.x > 0 && c.x < size.x - 1) ? 1.0 : 0.0, (c.y > 0 && c.y < size.y - 1) ? 1.0 : 0.0);
		VERTEX.xz += j * vertex_jitter;
	}
	v_ring_rock = ring ? 1.0 - smoothstep(0.72, 0.88, n.y) : 0.0;
	NORMAL = n;
	TANGENT = normalize(cross(n, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(n, TANGENT));
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_splat_uv = (vec2(c) + 0.5) / vec2(size);
	v_normal_ws = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	v_flat_splat = mix(textureLod(splatmap, v_splat_uv, 0.0), vec4(0.0, 0.0, 1.0, 0.0), v_ring_rock);
	v_flat_rand = t_hash12(ring ? floor(VERTEX.xz) : vec2(c));
	v_flat_uv = v_splat_uv;
}

vec3 brush_overlay(vec3 albedo, inout vec3 emission) {
	if (brush_radius > 0.0) {
		float d = distance(v_local.xz, brush_position.xz);
		float width = max(brush_radius * 0.025, cell_size * 0.4);
		float ring = 1.0 - smoothstep(0.0, width, abs(d - brush_radius));
		float inner = (1.0 - smoothstep(0.0, brush_radius, d)) * 0.15;
		emission += brush_color.rgb * (ring * 0.8 + inner) * brush_color.a;
		return mix(albedo, brush_color.rgb, ring * 0.6);
	}
	return albedo;
}
