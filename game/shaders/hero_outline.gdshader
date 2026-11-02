// contorno "casco invertido" dos heróis (segundo passe): engrossa a malha
// pela normal e desenha só as faces de trás numa cor escura quente, com espessura
// constante em pixels (compensada pela distância). Lê melhor no celular.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec3 outline_color : source_color = vec3(0.30, 0.15, 0.14);
uniform float width = 0.0035;
uniform float max_width = 0.02;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = max(-view_pos.z, 0.5);
	float w = min(width * dist, max_width);
	VERTEX += NORMAL * w;
}

void fragment() {
	ALBEDO = outline_color;
}
