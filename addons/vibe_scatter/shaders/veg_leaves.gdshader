shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, world_vertex_coords, alpha_to_coverage;

// Foliage cards (and low poly canopies) of vibe_scatter. Lighting per style:
// mode 0 = realistic (wrap diffuse + translucency), 1 = stylized (soft),
// 2 = toon / cel (bands). The texture is grayscale shading + alpha, tinted
// with the leaf colors (per instance variation).

#include "res://addons/vibe_scatter/shaders/veg_common.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable, hint_default_white;
uniform bool use_texture = true;
uniform vec4 leaf_color : source_color = vec4(0.27, 0.45, 0.16, 1.0);
uniform vec4 leaf_color2 : source_color = vec4(0.42, 0.55, 0.18, 1.0);
uniform vec4 leaf_color3 : source_color = vec4(0.27, 0.45, 0.16, 1.0);
uniform float variation : hint_range(0.0, 1.0) = 0.6;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float brightness = 1.25;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec4 snow_color : source_color = vec4(0.93, 0.95, 1.0, 1.0);
uniform int mode = 0;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform vec3 shadow_tint : source_color = vec3(0.45, 0.52, 0.8);
uniform float translucency : hint_range(0.0, 2.0) = 0.7;
uniform vec4 translucency_color : source_color = vec4(1.0, 1.1, 0.55, 1.0);
uniform float emission : hint_range(0.0, 8.0) = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	VERTEX += veg_wind(VERTEX, origin, scale, COLOR.a, UV2.x, 1.0);
	v_rand = INSTANCE_CUSTOM.x;
	v_rand2 = INSTANCE_CUSTOM.y;
	v_wpos = VERTEX;
	v_wnrm = NORMAL;
}

void fragment() {
	float shade = 1.0;
	float a = 1.0;
	vec2 tex_size = vec2(textureSize(leaf_tex, 0));
	if (use_texture) {
		vec4 tex = texture(leaf_tex, UV);
		shade = tex.r;
		a = tex.a;
		// Mipmaps average the alpha down, so distant canopies would thin out:
		// scale it back up with the mip level (Ben Golus, "Anti-aliased Alpha Test").
		vec2 dx = dFdx(UV * tex_size);
		vec2 dy = dFdy(UV * tex_size);
		float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
		a *= 1.0 + mip * 0.22;
	}
	float k = fract(v_rand * 7.13 + UV2.x * 0.37);
	vec3 base = mix(leaf_color.rgb, leaf_color2.rgb, smoothstep(0.15, 0.85, k) * variation);
	base = mix(base, leaf_color3.rgb, step(0.66, fract(v_rand2 * 3.7 + UV2.x * 0.21)) * variation);
	vec3 col = base * shade * COLOR.rgb * brightness;
	float s = snow * smoothstep(0.15, 0.6, v_wnrm.y + (veg_noise(v_wpos * 3.0) - 0.5) * 0.4);
	col = mix(col, snow_color.rgb * mix(0.8, 1.0, shade), s);
	ALBEDO = col;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// Soft, anti-aliased leaf edges with MSAA (alpha to coverage).
	ALPHA_ANTIALIASING_EDGE = use_texture ? 0.3 : 0.0;
	ALPHA_TEXTURE_COORDINATE = UV * tex_size;
	// No ambient (sky) specular: at grazing angles its Fresnel term turned
	// whole leaf cards pale grey. light() adds a small sun sheen instead.
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	EMISSION = col * emission;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float floor_k = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float lit;
	if (mode == 2) {
		float q = (ndl * 0.5 + 0.5) * ATTENUATION * bands;
		lit = clamp((floor(q) + smoothstep(0.45, 0.55, fract(q))) / bands, 0.0, 1.0);
	} else if (mode == 1) {
		float hl = ndl * 0.5 + 0.5;
		lit = hl * hl * ATTENUATION;
	} else {
		lit = clamp((ndl + 0.45) / 1.45, 0.0, 1.0) * ATTENUATION;
	}
	vec3 shade = mix(shadow_tint * (mode == 0 ? 0.32 : 0.42) * floor_k, vec3(1.0), lit);
	// Light through the leaves when the sun is behind them.
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 4.0) * translucency * ATTENUATION;
	DIFFUSE_LIGHT += (shade + back * translucency_color.rgb) * LIGHT_COLOR / PI;
	if (mode == 0) {
		float h = max(dot(normalize(LIGHT + VIEW), NORMAL), 0.0);
		// Faint, leaf-tinted sheen (a white one lit whole cards up).
		SPECULAR_LIGHT += pow(h, 20.0) * 0.02 * ATTENUATION * LIGHT_COLOR * (0.3 + ALBEDO * 2.0);
	}
}
