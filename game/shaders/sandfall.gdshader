// Cascata de areia: cortina vertical com fios de areia rolando (ruído em
// rolagem), bordas macias, brilho do sol nos grãos e névoa clara no pé.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sand_top : source_color = vec3(0.93, 0.62, 0.42);
uniform vec3 sand_bottom : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float speed = 0.55;
uniform float density = 0.85;
uniform float aspect = 3.0;          // altura / largura (escala dos fios)
uniform vec3 sun_dir = vec3(-0.45, 0.36, -0.82);   // direção PARA o sol (mundo)

void fragment() {
	vec2 uv = UV;                                     // y: 0 topo -> 1 base
	float fall = uv.y * uv.y * 0.6 + uv.y * 0.4;      // accelerates as it falls
	vec2 q = vec2(uv.x * 2.2, fall * aspect * 0.5 - TIME * speed);
	float strands = texture(noise_tex, q * vec2(1.0, 0.25)).r;
	strands = mix(strands, texture(noise_tex, q * vec2(2.7, 0.4) + 0.37).g, 0.45);
	float fine = texture(noise_tex, vec2(uv.x * 9.0, fall * aspect * 1.4 - TIME * speed * 1.8)).b;
	float sheet = smoothstep(0.32, 0.75, strands) * 0.75 + fine * 0.35;
	// soft sides that widen at the bottom (the curtain spreads and thins)
	float spread = mix(0.42, 0.5, uv.y);
	float side = smoothstep(spread, spread - 0.22, abs(uv.x - 0.5));
	float top = smoothstep(0.0, 0.06, uv.y);
	float bottom = 1.0 - smoothstep(0.82, 1.0, uv.y);
	float a = sheet * side * top * bottom * density;
	vec3 col = mix(sand_top, sand_bottom, uv.y);
	col += sun_color * pow(fine, 6.0) * 0.8;          // sparkling grains
	// backlit curtain: sand glows when you look toward the sun through it
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fwd = pow(clamp(dot(-vw, normalize(sun_dir)), 0.0, 1.0), 6.0);
	col += sun_color * fwd * 1.3;
	a *= 1.0 + fwd * 0.35;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
