// SOPRO — pétalas (flor-canhão): dupla face, cor por vértice, translucidez
// rosada contra o sol e brilho suave nas bordas.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 sss : source_color = vec3(1.0, 0.55, 0.65);
uniform float glow = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = sss * 0.7;
	EMISSION = COLOR.rgb * glow;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += clamp((ndl + 0.5) / 1.5, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += sss * pow(back, 2.0) * 0.8 * ATTENUATION * LIGHT_COLOR / PI;
}
