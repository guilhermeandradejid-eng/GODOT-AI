// SOPRO — "fenda": disco de portal com espiral de cores, estrelas sugadas para
// o centro e borda que respira. Cores em tons de lavanda e dourado.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color_a : source_color = vec3(0.55, 0.45, 1.0);
uniform vec3 color_b : source_color = vec3(1.0, 0.75, 0.55);
uniform vec3 color_c : source_color = vec3(0.35, 0.95, 0.9);
uniform float energy = 2.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float t = TIME;
	float swirl = sin(a * 3.0 + r * 9.0 - t * 2.5) * 0.5 + 0.5;
	float swirl2 = sin(a * 5.0 - r * 14.0 + t * 1.7) * 0.5 + 0.5;
	vec3 col = mix(color_a, color_b, swirl);
	col = mix(col, color_c, swirl2 * 0.4);
	col *= 0.55 + 0.6 * (1.0 - r);
	// stars falling inwards
	vec2 sp = vec2(a * 4.0, log(r + 0.001) * 3.0 + t * 1.2);
	float s = step(0.985, hash12(floor(sp * 6.0)));
	col += vec3(1.0) * s * (1.0 - r);
	float rim = smoothstep(0.75, 0.98, r) * (0.8 + 0.2 * sin(t * 3.0));
	col += color_b * rim * 1.5;
	ALBEDO = col * energy;
}
