// Shared code for every Vibe terrain style: heightmap displacement, splat
// weights, noise helpers and textured (PBR) layer sampling.
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

varying vec3 v_local;
varying vec3 v_world;
varying vec2 v_splat_uv;
varying vec3 v_normal_ws;
// Per-triangle (provoking vertex) data for the low-poly style.
varying flat vec4 v_flat_splat;
varying flat float v_flat_rand;

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
// projection on steep terrain. Returns albedo+height; out world normal & roughness.
vec4 sample_layer(sampler2D alb_tex, sampler2D nrm_tex, bool has_normal, float uv_scale, vec3 p, vec3 n_ws,
		float fallback_rough, out vec3 out_normal, out float out_rough) {
	vec3 blend = pow(abs(n_ws), vec3(6.0));
	blend /= (blend.x + blend.y + blend.z);
	mat2 rot;
	vec2 uv_y = detile(p.xz / uv_scale, rot);
	vec4 alb = texture(alb_tex, uv_y);
	vec4 nr = has_normal ? texture(nrm_tex, uv_y) : vec4(0.5, 0.5, 1.0, fallback_rough);
	vec3 tn_y = unpack_normal(nr);
	// Rotate the tangent-space normal back (inverse of the detile UV rotation).
	tn_y.xy = tn_y.xy * rot;
	vec3 wn = vec3(tn_y.x + n_ws.x, n_ws.y * tn_y.z, tn_y.y * -1.0 + n_ws.z);
	float rough = nr.a;
	if (blend.y < 0.98) {
		vec2 uv_x = p.zy / uv_scale;
		vec2 uv_z = p.xy / uv_scale;
		vec4 alb_x = texture(alb_tex, uv_x);
		vec4 alb_z = texture(alb_tex, uv_z);
		vec4 nr_x = has_normal ? texture(nrm_tex, uv_x) : vec4(0.5, 0.5, 1.0, fallback_rough);
		vec4 nr_z = has_normal ? texture(nrm_tex, uv_z) : vec4(0.5, 0.5, 1.0, fallback_rough);
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
	out_normal = normalize(wn);
	out_rough = has_normal ? rough : fallback_rough;
	return alb;
}

void vertex() {
	ivec2 size = textureSize(heightmap, 0);
	vec2 texel = (VERTEX.xz + vec2(terrain_half_size)) / cell_size;
	ivec2 c = clamp(ivec2(round(texel)), ivec2(0), size - 1);
	float h = texelFetch(heightmap, c, 0).r;
	float hl = texelFetch(heightmap, clamp(c + ivec2(-1, 0), ivec2(0), size - 1), 0).r;
	float hr = texelFetch(heightmap, clamp(c + ivec2(1, 0), ivec2(0), size - 1), 0).r;
	float hd = texelFetch(heightmap, clamp(c + ivec2(0, -1), ivec2(0), size - 1), 0).r;
	float hu = texelFetch(heightmap, clamp(c + ivec2(0, 1), ivec2(0), size - 1), 0).r;
	vec3 n = normalize(vec3(hl - hr, 2.0 * cell_size, hd - hu));
	float skirt = VERTEX.y;
	VERTEX.y = h + skirt * skirt_depth;
	NORMAL = n;
	TANGENT = normalize(cross(n, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(n, TANGENT));
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_splat_uv = (vec2(c) + 0.5) / vec2(size);
	v_normal_ws = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	v_flat_splat = textureLod(splatmap, v_splat_uv, 0.0);
	v_flat_rand = t_hash12(vec2(c));
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
