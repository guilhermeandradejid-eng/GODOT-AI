// pelagem/pele dos heróis: toon suave (2 faixas com transição macia),
// "subsurface" quente no terminador, rim light forte de contraluz (estilo Sky),
// leve brilho de pelo (sheen) e cor vinda dos vértices (gerada no Blender).
// Técnica de rim/bandas inspirada em FlexibleToonShaderGD (MIT, reescrito).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://game/shaders/hero_toon.gdshaderinc"
