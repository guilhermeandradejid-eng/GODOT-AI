// Procedural glowing magic circle / rune ring for the ground.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(0.6, 0.36, 1.0);
uniform float intensity = 2.0;
uniform float speed = 0.3;
uniform float bands = 0.0;

float line(float x, float w) {
	return 1.0 - smoothstep(0.0, w, abs(x));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + TIME * speed;
	float v = line(r - 0.95, 0.018) + line(r - 0.82, 0.01) + line(r - 0.5, 0.012) * 0.8;
	float runes = step(0.5, fract(ang * 24.0 / 6.2831)) * step(0.84, r) * step(r, 0.93);
	runes *= step(0.3, fract(sin(floor(ang * 24.0 / 6.2831) * 12.9898) * 43758.5453));
	float star = 0.0;
	for (int i = 0; i < 5; i++) {
		float a = ang * 1.0 + float(i) * 1.2566;
		vec2 dir = vec2(cos(a), sin(a));
		star += line(dot(p, vec2(-dir.y, dir.x)) + 0.0, 0.008) * step(r, 0.82) * step(0.1, r);
	}
	v += runes * 0.6 + star * 0.35;
	v *= 0.75 + 0.25 * sin(TIME * 3.0);
	v *= step(r, 1.0);
	if (bands > 0.5) {
		v = step(0.3, v);
	}
	ALBEDO = color * v * intensity;
}
