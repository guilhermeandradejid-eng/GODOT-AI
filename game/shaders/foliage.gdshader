// SOPRO — folhas de carnaúba e capim: dupla face, translucidez quando a luz
// vem por trás (folha "acende" no contraluz), vento por altura (alfa do vértice)
// com rajadas que atravessam o mundo.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 1.0;
uniform float wind_speed = 1.9;
uniform vec2 wind_dir = vec2(0.88, 0.47);
uniform vec3 translucency : source_color = vec3(0.75, 0.95, 0.45);
uniform float gust_scale = 0.03;

varying vec3 w_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.a;
	float t = TIME * wind_speed;
	float gust = 0.6 + 0.4 * sin(dot(wp.xz, wind_dir) * gust_scale - t * 0.7);
	float ph = wp.x * 0.37 + wp.z * 0.29;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (sin(t + ph) * 0.5 + 0.6) * gust;
	off += vec3(sin(t * 2.7 + ph * 3.0), 0.0, cos(t * 3.1 + ph * 2.0)) * 0.25;
	off.y = -0.2 * abs(sin(t + ph));
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off * w * w * 0.18 * wind_strength, 0.0)).xyz;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = translucency * 0.6;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + 0.6) / 1.6, 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += translucency * pow(back, 3.0) * 0.7 * ATTENUATION * LIGHT_COLOR / PI;
}
