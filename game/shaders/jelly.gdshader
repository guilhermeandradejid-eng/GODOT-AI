// Membrana do tambor de bronze (trampolim): couro claro esticado, runa ciano da
// pintura (alfa do vértice < 1 = brilho) e um afundamento elástico quando alguém
// quica ("squash", animado por script). "phase" dessincroniza o leve pulsar.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 hide : source_color = vec3(0.95, 0.89, 0.78);
uniform vec3 rune : source_color = vec3(0.55, 1.0, 0.95);
uniform float glow = 1.8;
uniform float pulse_speed = 1.6;
uniform float phase = 0.0;
uniform float squash = 0.0;

varying vec3 l_pos;

void vertex() {
	l_pos = VERTEX;
	float r = length(VERTEX.xz);
	// the membrane dips in the middle when bounced on
	VERTEX.y -= squash * 0.35 * smoothstep(1.2, 0.0, r);
}

void fragment() {
	float beat = 0.75 + 0.25 * sin(TIME * pulse_speed + phase);
	float r = length(l_pos.xz);
	vec3 col = hide * (0.9 + 0.1 * smoothstep(1.1, 0.2, r));
	float g = 1.0 - COLOR.a;
	ALBEDO = mix(col, rune, g * 0.6);
	EMISSION = rune * g * glow * (beat + squash * 2.0);
	ROUGHNESS = 0.75;
}
