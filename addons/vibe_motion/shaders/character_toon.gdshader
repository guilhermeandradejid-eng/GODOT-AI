shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Vibe character, stylized lighting (stylized / toon / cel styles).
// soft = 1: smooth wrap lighting (stylized); soft = 0: banded (toon / cel).
// Vertex COLOR.rgb = albedo (sRGB), COLOR.a = material (see character.gdshader).

uniform vec4 tint : source_color = vec4(1.0);
uniform float soft : hint_range(0.0, 1.0) = 0.0;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.04;
uniform vec3 shadow_tint : source_color = vec3(0.45, 0.5, 0.85);
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.45;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.6;
uniform float glow_energy : hint_range(0.0, 16.0) = 3.0;

varying float v_mat;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_mat = COLOR.a;
}

void fragment() {
	vec3 c = COLOR.rgb * tint.rgb;
	if (!OUTPUT_IS_SRGB) {
		c = srgb_to_linear(c);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (v_mat > 0.1 && v_mat < 0.3) {
		EMISSION = c * glow_energy;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float hl = ndl * 0.5 + 0.5;
	float lit_soft = hl * hl * ATTENUATION;
	float q = hl * ATTENUATION * bands;
	float stepped = clamp((floor(q) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(q))) / bands, 0.0, 1.0);
	float lit = mix(stepped, lit_soft, soft);
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shade = mix(shadow_tint * shadow_floor * floor_k, vec3(1.0), lit);
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_mask = mix(step(0.72, fres), pow(fres, 3.0), soft);
	float rim = rim_mask * rim_strength * lit;
	DIFFUSE_LIGHT += (shade + rim) * LIGHT_COLOR / PI;
	// Glossy highlight on eyes, leather and metal.
	float gloss = v_mat < 0.1 ? 1.0 : (v_mat > 0.3 && v_mat < 0.7 ? 0.45 : 0.0);
	if (gloss > 0.0) {
		float h = dot(normalize(LIGHT + VIEW), NORMAL);
		float spec = mix(smoothstep(0.93, 0.95, h), pow(max(h, 0.0), 60.0), soft);
		SPECULAR_LIGHT += spec * gloss * spec_strength * ATTENUATION * LIGHT_COLOR;
	}
}
