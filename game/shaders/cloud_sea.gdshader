// SOPRO — mar de nuvens sob as ilhas. Ruído em camadas rolando devagar,
// "normal" estimada do próprio ruído para iluminar os topos com o sol baixo
// (dourado) e sombrear as dobras (malva), contraluz prateado na direção do sol,
// e fusão suave com a raiz das ilhas pelo depth buffer (sem quina dura).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D cloud_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 lit_color : source_color = vec3(1.0, 0.86, 0.78);
uniform vec3 mid_color : source_color = vec3(0.98, 0.70, 0.74);
uniform vec3 shadow_color : source_color = vec3(0.66, 0.52, 0.76);
uniform vec3 rim_color : source_color = vec3(1.0, 0.78, 0.52);
uniform vec3 far_color : source_color = vec3(0.98, 0.76, 0.76);
uniform vec3 sun_dir = vec3(-0.45, 0.32, -0.83);
uniform float scale = 0.011;
uniform vec2 drift = vec2(0.0035, 0.0012);
uniform float soft_depth = 7.0;
uniform float far_fade = 1600.0;
uniform float brightness = 1.0;

varying vec3 w_pos;

float dens(vec2 p, float t) {
	float a = texture(cloud_noise, p + drift * t).r;
	float b = texture(cloud_noise, p * 2.7 - drift * t * 1.6).g;
	float c = texture(cloud_noise, p * 0.31 + drift * t * 0.4).a;
	return a * 0.6 + b * 0.25 + c * 0.45;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = w_pos.xz * scale;
	float e = 0.004;
	float h = dens(p, t);
	float hx = dens(p + vec2(e, 0.0), t);
	float hz = dens(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3((h - hx) * 16.0, 1.0, (h - hz) * 16.0));
	vec3 sd = normalize(sun_dir);
	float ndl = clamp(dot(n, sd) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(shadow_color, mid_color, smoothstep(0.15, 0.6, ndl));
	col = mix(col, lit_color, smoothstep(0.55, 0.95, ndl) * smoothstep(0.35, 0.8, h));
	// silver lining when looking towards the sun
	vec3 view_w = normalize(CAMERA_POSITION_WORLD - w_pos);
	float back = pow(clamp(dot(-view_w, sd), 0.0, 1.0), 6.0);
	col += rim_color * back * (1.0 - smoothstep(0.3, 0.8, h)) * 0.9;
	// deeper valleys between puffs
	col *= 0.72 + 0.42 * smoothstep(0.2, 0.8, h);
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	col = mix(col, far_color, smoothstep(far_fade * 0.3, far_fade, dist) * 0.85);
	ALBEDO = col * brightness;

	// soft intersection with the islands
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_d = -vpos.z;
	float frag_d = -VERTEX.z;
	float soft = clamp((scene_d - frag_d) / soft_depth, 0.0, 1.0);
	ALPHA = soft * smoothstep(0.05, 0.3, h + 0.15);
}
