shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Vibe character, physically based (realistic / low poly styles).
// Vertex COLOR.rgb = albedo (sRGB), COLOR.a = material:
//   1.0 cloth | 0.8 skin | 0.6 leather/rubber | 0.4 metal | 0.2 glow | 0.0 eyes
// UV / UV2 carry the rest-pose position, so fabric detail sticks to the body.

uniform vec4 tint : source_color = vec4(1.0);
uniform float fabric_detail : hint_range(0.0, 1.0) = 0.35;
uniform float cloth_sheen : hint_range(0.0, 1.0) = 0.35;
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;

varying float v_mat;
varying vec3 v_rest;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_mat = COLOR.a;
	v_rest = vec3(UV.x, UV.y, UV2.x);
}

void fragment() {
	vec3 c = COLOR.rgb * tint.rgb;
	if (!OUTPUT_IS_SRGB) {
		c = srgb_to_linear(c);
	}
	float m = v_mat;
	float rough = 0.9;
	float metal = 0.0;
	float spec = 0.4;
	vec3 emission = vec3(0.0);
	float n1 = vnoise(v_rest * 90.0);
	float n2 = vnoise(v_rest * 420.0);
	if (m > 0.9) {
		// Cloth: soft weave, a little sheen at grazing angles.
		c *= mix(1.0, 0.86 + 0.22 * n1 + 0.1 * (n2 - 0.5), fabric_detail);
		rough = 0.86 + 0.1 * n2;
		spec = 0.3;
		RIM = cloth_sheen;
		RIM_TINT = 0.6;
	} else if (m > 0.7) {
		// Skin: subtle blotches, satin highlight.
		c *= mix(1.0, 0.93 + 0.12 * n1, fabric_detail);
		rough = 0.52 + 0.1 * n2;
		spec = 0.35;
		RIM = 0.25;
		RIM_TINT = 0.8;
	} else if (m > 0.5) {
		c *= mix(1.0, 0.9 + 0.15 * n1, fabric_detail);
		rough = 0.36 + 0.2 * n2;
		spec = 0.45;
	} else if (m > 0.3) {
		rough = 0.25 + 0.2 * n1;
		metal = 0.9;
		spec = 0.6;
	} else if (m > 0.1) {
		emission = c * glow_energy;
		rough = 0.3;
	} else {
		rough = 0.06;
		spec = 0.9;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emission;
}
