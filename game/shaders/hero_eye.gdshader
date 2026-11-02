// SOPRO — olhos procedurais: esclera, íris com gradiente e anel, pupila,
// dois brilhos especulares fixos (leitura "fofa"), pálpebra superior animável
// (piscar / olhar sonolento) e direção do olhar. UV: centro = frente do olho.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec3 sclera : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 iris_outer : source_color = vec3(0.35, 0.18, 0.08);
uniform vec3 iris_inner : source_color = vec3(0.95, 0.62, 0.20);
uniform vec3 pupil_color : source_color = vec3(0.05, 0.03, 0.04);
uniform vec3 lid_color : source_color = vec3(0.24, 0.14, 0.13);
uniform float iris_size = 0.36;
uniform float pupil_size = 0.17;
uniform vec2 look = vec2(0.0, 0.0);
uniform float lid = 0.0;            // 0 open .. 1 closed
uniform float lid_tilt = 0.0;       // sad/angry tilt
uniform float happy = 0.0;          // ^ ^ closed happy eyes

void fragment() {
	vec2 uv = UV;
	vec2 c = vec2(0.5) + look * 0.18;
	vec2 d = (uv - c) * vec2(1.0, 0.82);
	float r = length(d);
	float aa = fwidth(r) * 1.2 + 0.004;
	vec3 col = sclera;
	float iris = 1.0 - smoothstep(iris_size - aa, iris_size + aa, r);
	vec3 icol = mix(iris_inner, iris_outer, smoothstep(0.0, iris_size, r * 1.15));
	icol = mix(icol, iris_outer * 0.6, smoothstep(iris_size * 0.8, iris_size, r));
	col = mix(col, icol, iris);
	float pupil = 1.0 - smoothstep(pupil_size - aa, pupil_size + aa, r);
	col = mix(col, pupil_color, pupil);
	// highlights
	float h1 = 1.0 - smoothstep(0.075 - aa, 0.075 + aa, length(uv - c - vec2(-0.11, -0.12)));
	float h2 = 1.0 - smoothstep(0.035 - aa, 0.035 + aa, length(uv - c - vec2(0.1, 0.1)));
	col = mix(col, vec3(1.0), max(h1, h2 * 0.85));
	// upper lid (closes from the top, uv.y grows downwards)
	float lid_line = mix(-0.05, 1.05, lid) + (uv.x - 0.5) * lid_tilt;
	float lidm = 1.0 - smoothstep(lid_line - aa, lid_line + aa, uv.y);
	col = mix(col, lid_color, lidm);
	// happy "^" eyes
	if (happy > 0.01) {
		float arc = abs(length((uv - vec2(0.5, 0.75)) * vec2(1.0, 1.4)) - 0.32);
		float m = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, arc);
		m *= step(uv.y, 0.62);
		col = mix(col, mix(lid_color, pupil_color, m), happy);
	}
	ALBEDO = col;
}
