// Corpo comum do toon dos heróis (incluído por hero_toon.gdshader e hero_cloth.gdshader).
// Defina DOUBLE_SIDED antes do #include para tecidos finos vistos dos dois lados.
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.52, 0.78);
uniform vec3 sss_color : source_color = vec3(1.0, 0.45, 0.32);
uniform float sss_strength = 0.35;
uniform float shadow_level = 0.55;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float rim_strength = 0.9;
uniform float rim_power = 3.0;
uniform float band_softness = 0.18;
uniform float sheen = 0.18;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float flash = 0.0;          // hit flash / power-up glow
uniform vec3 flash_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float vertex_glow = 2.2;   // vertex alpha < 1 marks glowing paint (sdfkit: alpha = 1 - emission)
uniform float glow_pulse = 0.0;

// Textura de detalhe (opcional): projeção triplanar na POSIÇÃO DE REPOUSO do vértice
// (CUSTOM0 = posição, CUSTOM1 = normal, gravados pelo HeroVisual), então a textura não
// "escorrega" quando o esqueleto deforma a malha. A luminância modula a cor do vértice
// (as zonas de cor continuam vindo do Blender) e o mapa normal entra em espaço de repouso,
// girado para a normal deformada.
uniform bool use_detail = false;
uniform sampler2D detail_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 2.5;           // repetições por metro
uniform float detail_albedo_mix = 0.45;     // força da modulação de cor
uniform float detail_mean = 0.5;            // luminância média da textura (mantém o tom)
uniform float detail_normal_strength = 0.6;
uniform float detail_sharp = 4.0;           // nitidez da mistura entre as três projeções
varying vec3 v_rest_pos;
varying vec3 v_rest_nrm;
varying vec3 v_skin_nrm;

// Brilho de cabelo anisotrópico (Kajiya-Kay, dois lóbulos): a direção do fio vem do UV0.v
// (0 na raiz → 1 na ponta de cada mecha, gravado no Blender) por derivadas de tela.
uniform float hair_band = 0.0;              // 0 desliga
uniform vec3 hair_band_color : source_color = vec3(1.0, 0.86, 0.7);
uniform float hair_shift = 0.12;            // desloca o lóbulo primário em direção à raiz
uniform float hair_exp = 80.0;
varying vec3 v_strand;

void vertex() {
	v_rest_pos = CUSTOM0.xyz;
	v_rest_nrm = CUSTOM1.xyz;
	v_skin_nrm = NORMAL;
}

void fragment() {
#ifdef DOUBLE_SIDED
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	vec3 base = COLOR.rgb * tint;
	if (use_texture) {
		base = texture(albedo_tex, UV).rgb * tint;
	}
	if (use_detail) {
		vec3 rn = normalize(v_rest_nrm + vec3(1e-5));
		vec3 w = pow(abs(rn), vec3(detail_sharp));
		w /= max(w.x + w.y + w.z, 1e-4);
		vec3 p = v_rest_pos * detail_scale;
		// v da textura cresce para baixo na Godot: inverte para a imagem ficar em pé e o
		// mapa normal OpenGL (+Y) iluminar o relevo do lado certo
		vec2 ux = vec2(p.z, -p.y);
		vec2 uy = vec2(p.x, -p.z);
		vec2 uz = vec2(p.x, -p.y);
		vec3 ta = texture(detail_albedo, ux).rgb * w.x + texture(detail_albedo, uy).rgb * w.y
			+ texture(detail_albedo, uz).rgb * w.z;
		float lum = dot(ta, vec3(0.299, 0.587, 0.114));
		base *= mix(1.0, lum / max(detail_mean, 0.05), detail_albedo_mix);
		// triplanar normal mapping, "whiteout" blend (rest object space)
		vec3 nx = texture(detail_normal, ux).rgb * 2.0 - 1.0;
		vec3 ny = texture(detail_normal, uy).rgb * 2.0 - 1.0;
		vec3 nz = texture(detail_normal, uz).rgb * 2.0 - 1.0;
		nx = vec3(nx.xy + rn.zy, abs(nx.z) * rn.x);
		ny = vec3(ny.xy + rn.xz, abs(ny.z) * rn.y);
		nz = vec3(nz.xy + rn.xy, abs(nz.z) * rn.z);
		vec3 dn = normalize(nx.zyx * w.x + ny.xzy * w.y + nz.xyz * w.z);
		// rotate from the rest normal to the skinned normal (Rodrigues), then to view space
		vec3 sn = normalize(v_skin_nrm);
		vec3 k = cross(rn, sn);
		float c = dot(rn, sn);
		vec3 rdn = dn * c + cross(k, dn) + k * (dot(k, dn) / (1.0 + c + 1e-4));
		vec3 nview = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(rdn, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, nview, detail_normal_strength));
	}
	if (hair_band > 0.0) {
		// direção em que UV.y cresce (bitangente pelo "cotangent frame" de derivadas de tela)
		vec3 dp1 = dFdx(VERTEX);
		vec3 dp2 = dFdy(VERTEX);
		vec2 duv1 = dFdx(UV);
		vec2 duv2 = dFdy(UV);
		vec3 dp2perp = cross(dp2, NORMAL);
		vec3 dp1perp = cross(NORMAL, dp1);
		vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
		float bl = length(b);
		v_strand = bl > 1e-8 ? b / bl : vec3(0.0);
	} else {
		v_strand = vec3(0.0);
	}
	ALBEDO = base;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float vglow = (1.0 - COLOR.a) * vertex_glow * (1.0 + glow_pulse * sin(TIME * 3.0) * 0.35);
	EMISSION = emission_color + flash_color * flash * (0.4 + fres) + base * vglow;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl - 0.05);
	float shadow = mix(0.0, 1.0, lit * ATTENUATION);
	vec3 diffuse = mix(shadow_tint * shadow_level, vec3(1.0), shadow);
	// warm scattering where light turns into shadow
	float term = (1.0 - abs(ndl)) * smoothstep(-0.4, 0.2, ndl);
	diffuse += sss_color * term * sss_strength;
	DIFFUSE_LIGHT += diffuse * LIGHT_COLOR / PI;
	// rim: strongest when the light comes from behind the character
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float back = clamp(dot(-VIEW, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power) * (0.3 + 0.7 * back) * smoothstep(-0.3, 0.4, ndl + back * 0.5);
	SPECULAR_LIGHT += rim_color * rim * rim_strength * LIGHT_COLOR / PI * ALBEDO * 1.6;
	// soft fur sheen
	vec3 h = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(clamp(dot(NORMAL, h), 0.0, 1.0), 12.0) * sheen * LIGHT_COLOR / PI * ATTENUATION;
	if (hair_band > 0.0 && dot(v_strand, v_strand) > 0.5) {
		vec3 t1 = normalize(v_strand + NORMAL * hair_shift);
		vec3 t2 = normalize(v_strand - NORMAL * hair_shift * 1.6);
		float th1 = dot(t1, h);
		float th2 = dot(t2, h);
		float k1 = pow(sqrt(max(0.0, 1.0 - th1 * th1)), hair_exp);
		float k2 = pow(sqrt(max(0.0, 1.0 - th2 * th2)), hair_exp * 0.35) * 0.35;
		float lit_side = smoothstep(-0.1, 0.3, ndl) * ATTENUATION;
		SPECULAR_LIGHT += (hair_band_color * k1 + ALBEDO * k2 * 2.0) * hair_band * lit_side * LIGHT_COLOR / PI;
	}
}
