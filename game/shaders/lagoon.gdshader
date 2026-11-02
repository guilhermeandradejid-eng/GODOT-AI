// SOPRO — lagoa turquesa dos Lençóis: cor pela profundidade (raso verde-água,
// fundo azul), cáusticas projetadas no fundo (posição reconstruída do depth
// buffer), espuma na beira, reflexo do céu pelo fresnel e brilho do sol.
// Sem leitura da tela (só profundidade) para ficar leve no renderer Mobile.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.42, 0.96, 0.82);
uniform vec3 deep : source_color = vec3(0.06, 0.55, 0.66);
uniform vec3 sky_reflect : source_color = vec3(1.0, 0.80, 0.80);
uniform vec3 foam_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 sun_dir = vec3(-0.45, 0.32, -0.83);
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.65);
uniform float depth_scale = 1.6;
uniform float clarity = 0.7;
uniform float foam_width = 0.35;
uniform float caustic_strength = 0.55;
uniform float wave_scale = 0.12;
uniform float ambient = 0.85;

varying vec3 w_pos;

float caustics(vec2 p, float t) {
	// two layers of warped cellular noise from the texture's Worley channel
	vec2 q = p + vec2(sin(t * 0.7 + p.y * 0.8), cos(t * 0.6 + p.x * 0.7)) * 0.12;
	float a = texture(noise_tex, q * 0.22 + vec2(t * 0.02, -t * 0.015)).g;
	float b = texture(noise_tex, q * 0.31 - vec2(t * 0.018, t * 0.022)).g;
	float c = min(a, b);
	return pow(1.0 - c, 7.0);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	VERTEX.y += (sin(w_pos.x * 0.7 + t * 1.3) + cos(w_pos.z * 0.6 + t * 1.1)) * 0.025;
}

void fragment() {
	float t = TIME;
	// scene depth -> world position of the lagoon floor
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	vec3 floor_w = (INV_VIEW_MATRIX * vec4(vpos.xyz, 1.0)).xyz;
	float water_depth = max(w_pos.y - floor_w.y, 0.0);
	float view_len = length(VERTEX) - length(vpos.xyz);
	float dd = clamp(water_depth / depth_scale, 0.0, 1.0);

	// surface normal from two scrolling normal maps
	vec2 uv1 = w_pos.xz * wave_scale + vec2(t * 0.03, t * 0.02);
	vec2 uv2 = w_pos.xz * wave_scale * 1.7 - vec2(t * 0.025, -t * 0.035);
	vec3 n1 = texture(wave_normal, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal, uv2).xyz * 2.0 - 1.0;
	vec3 wn = normalize(vec3(n1.x + n2.x, 6.0, n1.y + n2.y));

	vec3 view_w = normalize(CAMERA_POSITION_WORLD - w_pos);
	float fres = pow(1.0 - clamp(dot(wn, view_w), 0.0, 1.0), 4.0);

	vec3 water = mix(shallow, deep, smoothstep(0.0, 1.0, dd));
	float cau = caustics(floor_w.xz, t) * caustic_strength * (1.0 - dd) * smoothstep(0.02, 0.25, water_depth);
	water += vec3(1.0, 1.0, 0.92) * cau;
	water *= ambient;
	vec3 col = mix(water, sky_reflect, fres * 0.5);
	// sun glint
	vec3 h = normalize(normalize(sun_dir) + view_w);
	float spec = pow(clamp(dot(wn, h), 0.0, 1.0), 260.0) * 6.0 + pow(clamp(dot(wn, h), 0.0, 1.0), 30.0) * 0.25;
	col += sun_color * spec;
	// foam on the shore line
	float fn = texture(noise_tex, w_pos.xz * 0.35 + vec2(t * 0.05, 0.0)).r;
	float shore = 1.0 - smoothstep(0.0, foam_width, water_depth + (fn - 0.5) * 0.12);
	float foam_line = smoothstep(0.35, 0.65, sin((water_depth / foam_width) * 9.0 - t * 2.2) * 0.5 + 0.5) * shore;
	float foam = clamp(shore * 0.55 + foam_line * 0.5, 0.0, 1.0) * smoothstep(0.3, 0.6, fn + shore * 0.4);
	col = mix(col, foam_color, foam * 0.85);

	ALBEDO = col;
	float alpha = mix(1.0 - clarity, 1.0, smoothstep(0.0, 1.0, dd));
	alpha = max(alpha, fres * 0.6);
	alpha = max(alpha, foam * 0.9);
	// soft edge where the water meets the sand
	alpha *= smoothstep(0.0, 0.06, water_depth);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
