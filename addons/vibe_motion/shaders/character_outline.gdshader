shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

// Inverted-hull outline for toon / cel characters (used as next_pass).
// The width grows a little with distance so the line stays readable.

uniform vec4 outline_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);
uniform float width : hint_range(0.0, 0.05) = 0.006;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += NORMAL * width * clamp(d * 0.15, 0.7, 4.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
