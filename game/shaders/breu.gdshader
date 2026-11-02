// SOPRO — "Breu": criatura de piche escuro com brilho iridescente (como óleo
// na água), corpo que borbulha e treme, e que se dissolve em luz ao ser vencido.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.16, 0.10, 0.22);
uniform float wobble = 1.0;
uniform float dissolve = 0.0;
uniform float hurt = 0.0;

varying vec3 l_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	l_pos = VERTEX;
	float t = TIME * 3.0;
	float n = sin(VERTEX.x * 9.0 + t) * sin(VERTEX.y * 7.0 + t * 1.3) * sin(VERTEX.z * 8.0 - t * 0.7);
	VERTEX += NORMAL * n * 0.06 * wobble;
	VERTEX.y *= 1.0 + 0.06 * sin(t * 1.7) * wobble;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (fres * 1.3 + vec3(0.0, 0.33, 0.67)) + TIME * 0.5);
	vec3 col = base_color + irid * fres * 0.45;
	col = mix(col, vec3(1.0, 0.5, 0.6), hurt);
	if (dissolve > 0.0) {
		float h = hash13(floor(l_pos * 18.0));
		if (h < dissolve) discard;
		col = mix(col, vec3(1.0, 0.9, 0.7) * 3.0, smoothstep(dissolve, dissolve + 0.15, h) < 1.0 ? 1.0 : 0.0);
	}
	ALBEDO = col;
	ROUGHNESS = 0.15;
	SPECULAR = 0.9;
	EMISSION = irid * fres * 0.25;
}
