// SOPRO — águas-vivas do céu: sino translúcido iridescente que pulsa
// (contrai/expande), fresnel brilhante, padrão interno de veios e um núcleo de
// luz. "squash" é animado por script quando alguém quica em cima.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;

uniform vec3 inner : source_color = vec3(0.75, 0.92, 1.0);
uniform vec3 rim : source_color = vec3(1.0, 0.75, 0.95);
uniform vec3 core : source_color = vec3(1.0, 0.9, 0.7);
uniform float glow = 1.4;
uniform float pulse_speed = 1.6;
uniform float phase = 0.0;
uniform float squash = 0.0;
uniform float alpha_base = 0.55;

varying vec3 l_pos;

void vertex() {
	l_pos = VERTEX;
	float t = TIME * pulse_speed + phase;
	float beat = sin(t) * 0.5 + 0.5;
	float rimw = smoothstep(0.9, 0.0, VERTEX.y);
	VERTEX.xz *= 1.0 + 0.08 * beat * rimw - 0.04 * (1.0 - beat) * (1.0 - rimw) + squash * 0.35;
	VERTEX.y *= 1.0 - 0.06 * beat - squash * 0.4;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float a = atan(l_pos.z, l_pos.x);
	float veins = smoothstep(0.85, 1.0, sin(a * 8.0 + l_pos.y * 3.0) * 0.5 + 0.5);
	vec3 base = mix(inner, rim, smoothstep(0.2, 1.0, l_pos.y) * 0.5 + fres * 0.5);
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (fres * 0.8 + vec3(0.0, 0.33, 0.67)) + TIME * 0.3);
	vec3 col = base + irid * fres * 0.35 + veins * 0.15;
	float corem = smoothstep(0.55, 0.0, length(l_pos - vec3(0.0, 0.55, 0.0)));
	ALBEDO = col;
	EMISSION = (col * fres * glow) + core * corem * glow * 0.8 + veins * rim * 0.4;
	ALPHA = clamp(alpha_base + fres * 0.45 + corem * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.2;
	SPECULAR = 0.8;
}
