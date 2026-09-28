// Force field bubble: fresnel rim + animated hex-like cells + pulse.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.5, 0.9, 1.0);
uniform float intensity = 1.6;
uniform float rim_power = 3.0;
uniform float cell_scale = 9.0;
uniform float bands = 0.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 p = normalize(v_obj);
	vec2 uv = vec2(atan(p.z, p.x) / 6.2831, p.y * 0.5 + 0.5) * vec2(2.0, 1.0) * cell_scale;
	vec2 cell = fract(uv) - 0.5;
	float edge = smoothstep(0.38, 0.5, max(abs(cell.x), abs(cell.y)));
	float n = texture(noise_tex, uv * 0.07 + vec2(TIME * 0.05, TIME * 0.11)).r;
	float scan = smoothstep(0.96, 1.0, sin(p.y * 10.0 - TIME * 2.5) * 0.5 + 0.5);
	float v = fres * 1.2 + edge * 0.25 * n + scan * 0.35;
	v *= 0.8 + 0.2 * sin(TIME * 2.0);
	if (bands > 0.5) {
		v = floor(v * bands) / bands;
	}
	ALBEDO = color * v * intensity;
}
