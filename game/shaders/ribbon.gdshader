// "fita de vento": trilho translúcido que flui (chevrons andando no
// sentido do trilho), bordas douradas brilhantes e ondulação suave.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 core_color : source_color = vec3(0.35, 0.95, 0.9);
uniform vec3 edge_color : source_color = vec3(1.0, 0.85, 0.5);
uniform float flow_speed = 1.6;
uniform float intensity = 1.2;

void vertex() {
	VERTEX.y += sin(UV.y * 0.6 - TIME * 2.0) * 0.06;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.75, 0.98, across);
	float chev = fract(UV.y * 0.9 - across * 0.35 - TIME * flow_speed);
	float arrows = smoothstep(0.0, 0.08, chev) * (1.0 - smoothstep(0.12, 0.35, chev));
	float body = (1.0 - smoothstep(0.85, 1.0, across)) * 0.35;
	vec3 col = core_color * (body + arrows * 0.9) + edge_color * edge * 1.4;
	float fade = smoothstep(0.0, 3.0, UV.y);
	ALBEDO = col * intensity * fade;
}
