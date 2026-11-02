// SOPRO — pós-processamento de tela cheia (CanvasLayer acima do 3D, abaixo do HUD).
// Lê a imagem final do 3D (já com glow/tonemap do Environment) e aplica:
// raios de sol radiais a partir da posição do sol na tela, gradação de cor
// "hora dourada" (sombras lavanda, luzes pêssego), vinheta, aberração cromática
// nas bordas, grão fino e um véu de luz quente. Barato: ~16 amostras no máximo.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 sun_screen = vec2(0.5, 0.3);   // UV of the sun on screen
uniform float sun_visible = 1.0;            // 0..1 (behind camera / occluded → 0)
uniform vec3 shaft_color : source_color = vec3(1.0, 0.82, 0.60);
uniform float shaft_strength = 0.45;
uniform float shaft_threshold = 0.88;
uniform int shaft_samples = 14;
uniform float shaft_length = 0.55;
uniform vec3 shadow_tint : source_color = vec3(0.93, 0.88, 1.08);
uniform vec3 highlight_tint : source_color = vec3(1.06, 0.99, 0.92);
uniform float saturation = 1.06;
uniform float contrast = 1.04;
uniform float vignette = 0.32;
uniform vec3 vignette_color : source_color = vec3(0.32, 0.20, 0.36);
uniform float aberration = 0.0018;
uniform float grain = 0.025;
uniform float haze = 0.03;
uniform vec3 haze_color : source_color = vec3(1.0, 0.86, 0.76);
uniform float fade = 0.0;                   // fade to white (transitions)
uniform vec3 fade_color : source_color = vec3(1.0, 0.97, 0.93);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_c = uv - 0.5;
	float r2 = dot(from_c, from_c);
	// chromatic aberration grows towards the edges
	vec2 off = from_c * aberration * (0.4 + r2 * 3.0);
	vec3 col;
	col.r = textureLod(screen_tex, uv + off, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - off, 0.0).b;

	// radial sun shafts: only bright samples close to the sun on screen count,
	// so silhouettes in front of the sun cut dark streaks into the light
	if (shaft_strength > 0.001 && sun_visible > 0.01) {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 to_sun = sun_screen - uv;
		vec2 step_v = to_sun * shaft_length / float(shaft_samples);
		float jitter = hash12(FRAGCOORD.xy + fract(TIME) * 61.0);
		vec2 p = uv + step_v * jitter;
		float acc = 0.0;
		for (int i = 0; i < 32; i++) {
			if (i >= shaft_samples) break;
			vec3 s = textureLod(screen_tex, p, 2.0).rgb;
			vec2 ds = (p - sun_screen) * vec2(aspect, 1.0);
			float near_sun = smoothstep(0.42, 0.0, length(ds));
			acc += smoothstep(shaft_threshold, 1.0, luma(s)) * near_sun;
			p += step_v;
		}
		acc /= float(shaft_samples);
		vec2 dsun = to_sun * vec2(aspect, 1.0);
		float fall = 1.0 / (1.0 + dot(dsun, dsun) * 4.0);
		col += shaft_color * acc * shaft_strength * sun_visible * fall * 1.6;
	}

	// golden-hour grading: split toning by luminance
	float l = luma(col);
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.85, l));
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	// warm haze lifting the blacks a little (dreamy, Sky-like)
	col = mix(col, haze_color, haze * (1.0 - l));
	// vignette (tinted, not black)
	float v = smoothstep(0.85, 0.2, length(from_c * vec2(1.0, 0.85)) * 1.25);
	col = mix(col * mix(vignette_color, vec3(1.0), 0.55), col, mix(1.0 - vignette, 1.0, v));
	// film grain
	float g = hash12(FRAGCOORD.xy * 0.9 + fract(TIME * 7.13) * 113.0) - 0.5;
	col += g * grain * (1.0 - l * 0.6);
	col = mix(col, fade_color, fade);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
