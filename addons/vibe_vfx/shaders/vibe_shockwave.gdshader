// Expanding shockwave ring (horizontal plane). `progress` 0..1 is animated
// by VibeVFX3D.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.8, 0.55);
uniform float intensity = 2.0;
uniform float thickness = 0.12;
uniform float bands = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float front = progress;
	float d = abs(r - front);
	float ring = 1.0 - smoothstep(0.0, thickness * (0.4 + progress), d);
	float inner = (1.0 - smoothstep(0.0, max(front, 0.001), r)) * 0.25 * (1.0 - progress);
	float v = (ring + inner) * (1.0 - progress) * step(r, 1.0);
	if (bands > 0.5) {
		v = step(0.35, v) * 0.9;
	}
	ALBEDO = color * v * intensity;
}
