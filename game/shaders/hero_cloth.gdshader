// Tecido fino dos heróis (o cachecol simulado): o mesmo toon, visto dos dois lados.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

#define DOUBLE_SIDED
#include "res://game/shaders/hero_toon.gdshaderinc"
