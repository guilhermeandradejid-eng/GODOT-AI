// SOPRO — props (pedra, madeira, bronze, folhas): cor por vértice, areia que
// se acumula nas faces voltadas para cima, luz envolvente com sombras lavanda,
// contraluz dourado e vento (alfa do vértice = quanto aquela parte balança).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 sand_color : source_color = vec3(1.0, 0.93, 0.85);
uniform float sand_amount = 0.75;
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.6;
uniform float metallic_look = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.85, 0.66);
uniform float rim_strength = 0.6;
uniform float wrap = 0.5;
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wind_strength > 0.0) {
		float w = COLOR.a;
		float t = TIME * wind_speed;
		float ph = w_pos.x * 0.21 + w_pos.z * 0.17;
		vec3 off = vec3(sin(t + ph) + 0.4 * sin(t * 2.3 + ph * 2.0), 0.0, cos(t * 0.8 + ph) * 0.6) * 0.12;
		off.y = -abs(off.x) * 0.3;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(off * wind_strength * w, 0.0)).xyz;
		w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb * tint;
	float n = texture(noise_tex, w_pos.xz * 0.35).r;
	float up = smoothstep(0.55, 0.9, normalize(w_nrm).y + (n - 0.5) * 0.35);
	col = mix(col, sand_color, up * sand_amount);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.35, metallic_look);
	METALLIC = metallic_look * 0.6;
	SPECULAR = 0.3 + metallic_look * 0.4;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	SPECULAR_LIGHT += rim_color * pow(1.0 - ndv, 3.0) * (0.2 + 0.8 * back) * rim_strength * LIGHT_COLOR / PI * ALBEDO;
	if (metallic_look > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 40.0) * metallic_look * 2.0 * LIGHT_COLOR / PI * ATTENUATION;
	}
}
