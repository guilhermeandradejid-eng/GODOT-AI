// Costura dourada da Agulha de Vael: acende da base para a ponta conforme o
// progresso (cada Pedra das Horas devolvida = 1/3). Alfa do vértice = posição
// ao longo da lâmina (0 base .. 1 ponta). Ignora a névoa para ser lida de longe.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 lit : source_color = vec3(1.0, 0.82, 0.42);
uniform vec3 dim : source_color = vec3(0.42, 0.34, 0.26);
uniform float fill = 0.0;
uniform float energy = 3.2;

void fragment() {
	float t = COLOR.a;
	float on = 1.0 - smoothstep(fill - 0.015, fill + 0.015, t);
	float wave = 0.85 + 0.15 * sin(TIME * 2.4 - t * 18.0);
	ALBEDO = mix(dim, lit, on);
	EMISSION = lit * energy * on * wave;
}
