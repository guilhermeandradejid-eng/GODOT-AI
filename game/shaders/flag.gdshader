// SOPRO — bandeirinhas de festa junina e rabiolas: tecido que tremula
// (onda ao longo do cordão + balanço da ponta), dupla face, textura em atlas.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float wind_strength = 1.0;
uniform float wind_speed = 3.0;

void vertex() {
	float w = COLOR.a;               // 0 at the cord, 1 at the flag tip
	float s = UV2.x;                 // distance along the cord
	float t = TIME * wind_speed;
	VERTEX.z += sin(t + s * 1.7) * 0.12 * w * wind_strength;
	VERTEX.x += sin(t * 1.3 + s * 2.3) * 0.04 * w * wind_strength;
	VERTEX.y += cos(t * 0.9 + s) * 0.03 * w * wind_strength;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.8;
	BACKLIGHT = c.rgb * 0.5;
}
