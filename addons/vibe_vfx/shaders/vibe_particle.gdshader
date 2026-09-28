// Vibe particle shader (stylized / toon / cel particles).
// Billboarded sprite whose shape is eroded by scrolling noise as the particle
// fades (alpha erosion), giving painterly fire/smoke instead of plain fades.
// Alpha erosion technique after GDQuest's stylized fire (MIT) / Minions Art.
// blend_premul_alpha lets one shader do both "add" (additive = 1) and "mix".
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D mask_tex : source_color, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int frames = 1;
uniform float additive : hint_range(0.0, 1.0) = 0.0;
uniform float emission_strength = 1.0;
uniform float edge_softness : hint_range(0.005, 1.0) = 0.12;
uniform float erosion : hint_range(0.0, 1.0) = 0.7;
uniform float posterize = 0.0;
uniform float noise_scale = 0.8;
uniform vec2 noise_speed = vec2(0.05, -0.35);
uniform bool billboard = true;
uniform float fake_light = 0.0;
uniform vec3 shade_color : source_color = vec3(0.55, 0.55, 0.7);

varying float v_seed;

void vertex() {
	if (billboard) {
		mat4 mat_world = mat4(
			normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0].xyz),
			normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1].xyz),
			normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2].xyz),
			MODEL_MATRIX[3]);
		mat_world = mat_world * mat4(
			vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	float f = float(max(frames, 1));
	float frame = floor(fract(INSTANCE_CUSTOM.z) * f * f);
	UV = (UV + vec2(mod(frame, f), floor(frame / f))) / f;
	v_seed = fract(INSTANCE_CUSTOM.z * 7.31);
}

void fragment() {
	vec4 mask = texture(mask_tex, UV);
	vec2 nuv = UV * noise_scale + noise_speed * TIME + vec2(v_seed * 3.7, v_seed * 1.3);
	float n = texture(noise_tex, nuv).r;
	float life_alpha = COLOR.a;
	// Erode the shape instead of fading it uniformly.
	float shape = mask.a * mix(1.0, n * 1.6, erosion);
	float a = shape + (life_alpha - 1.0) * mix(0.0, 1.2, erosion);
	a = mix(mask.a * life_alpha, a, erosion);
	a = smoothstep(0.0, edge_softness, clamp(a, 0.0, 1.0));
	vec3 col = COLOR.rgb * mix(vec3(1.0), mask.rgb, 0.5);
	if (fake_light > 0.0) {
		float lit = clamp(0.5 + (0.5 - UV.y) * 1.2 + (n - 0.5) * 0.6, 0.0, 1.0);
		col *= mix(shade_color, vec3(1.0), mix(1.0, lit, fake_light));
	}
	if (posterize > 0.5) {
		col = floor(col * posterize + 0.5) / posterize;
	}
	col *= emission_strength;
	ALBEDO = col * a;
	ALPHA = a * (1.0 - additive);
}
