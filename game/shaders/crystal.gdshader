// Cristal facetado de Kesrin: facetas planas com lilás profundo -> claro (cor por
// vértice R = altura), brilho interno ciano nas bordas (fresnel), cintilação nas
// facetas viradas para o sol e um leve brilho que respira. Barato (sem texturas).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 deep : source_color = vec3(0.42, 0.30, 0.74);
uniform vec3 pale : source_color = vec3(0.90, 0.84, 1.0);
uniform vec3 inner : source_color = vec3(0.50, 1.0, 0.94);
uniform float glow = 0.55;
uniform float sparkle = 1.6;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = mix(deep, pale, clamp(COLOR.r, 0.0, 1.0));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float breathe = 0.85 + 0.15 * sin(TIME * 1.3 + w_pos.x * 0.2 + w_pos.z * 0.15);
	ALBEDO = base * 0.55;
	ROUGHNESS = 0.12;
	SPECULAR = 0.9;
	EMISSION = inner * (0.2 + 0.8 * fres) * glow * clamp(COLOR.g, 0.0, 1.0) * breathe + base * 0.12;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += mix(vec3(0.55, 0.5, 0.8) * 0.4, vec3(1.0), smoothstep(0.0, 0.6, ndl)) * LIGHT_COLOR / PI * ATTENUATION;
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 90.0) * sparkle * LIGHT_COLOR * ATTENUATION;
}
