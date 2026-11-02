// lumes (coletáveis): billboards de luz quente que flutuam e cintilam,
// desenhados num único MultiMesh (1 draw call para centenas de lumes).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D dot_tex : source_color, filter_linear_mipmap;
uniform vec3 color : source_color = vec3(1.0, 0.85, 0.45);
uniform float energy = 2.6;
uniform float size = 0.55;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	float t = TIME * 2.2 + v_phase * 6.2831;
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	center.y += sin(t) * 0.12;
	// camera-facing billboard
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float s = size * length(MODEL_MATRIX[0].xyz) * (1.0 + 0.12 * sin(t * 1.7));
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 d = texture(dot_tex, UV);
	float twinkle = 0.85 + 0.15 * sin(TIME * 7.0 + v_phase * 40.0);
	ALBEDO = color * energy * d.a * twinkle + vec3(1.0) * pow(d.a, 6.0) * 1.5;
}
