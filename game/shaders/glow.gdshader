// SOPRO — partes que emitem luz (runas, sementes, núcleo das flores): cor por
// vértice como emissão HDR (alimenta o glow), pulso suave e borda mais clara.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 2.2;
uniform float pulse = 0.25;
uniform float pulse_speed = 2.0;
uniform float active = 1.0;           // 0 = apagado (runas antes de ativar)
uniform vec3 off_color : source_color = vec3(0.45, 0.4, 0.42);

void fragment() {
	float p = 1.0 + pulse * sin(TIME * pulse_speed + NODE_POSITION_WORLD.x * 0.7);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 on = COLOR.rgb * tint * energy * p * (0.8 + 0.6 * fres);
	ALBEDO = mix(off_color, on, active);
}
