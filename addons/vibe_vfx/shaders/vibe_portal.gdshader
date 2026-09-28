// Swirling portal disc (use on a QuadMesh / vertical plane).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 color_inner : source_color = vec3(0.62, 0.95, 1.0);
uniform vec3 color_outer : source_color = vec3(0.54, 0.36, 1.0);
uniform float intensity = 2.5;
uniform float swirl = 3.0;
uniform float speed = 0.6;
uniform float bands = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float twist = ang + swirl * (1.0 - r) + TIME * speed;
	vec2 suv = vec2(twist / 6.2831, r * 0.8 - TIME * speed * 0.3);
	float n = texture(noise_tex, suv).r;
	float n2 = texture(noise_tex, suv * 2.3 + vec2(0.3, 0.7)).r;
	float ring = (1.0 - smoothstep(0.82, 1.0, r)) * smoothstep(0.0, 0.35, r + n * 0.15);
	float glow = pow(clamp(1.0 - r, 0.0, 1.0), 1.5);
	float v = clamp(ring * (0.35 + n * 0.9 + n2 * 0.35) + glow * 0.6, 0.0, 2.0);
	if (bands > 0.5) {
		v = floor(v * bands) / bands;
	}
	vec3 col = mix(color_outer, color_inner, clamp(1.0 - r + n * 0.3, 0.0, 1.0));
	ALBEDO = col * v * intensity * (1.0 - smoothstep(0.9, 1.0, r));
}
