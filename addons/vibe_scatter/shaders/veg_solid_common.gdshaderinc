// Surface of vibe_scatter solids (include after veg_common).

uniform vec4 albedo : source_color = vec4(0.36, 0.28, 0.21, 1.0);
uniform vec4 albedo2 : source_color = vec4(0.3, 0.24, 0.18, 1.0);
uniform sampler2D bark_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float bark_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec2 bark_scale = vec2(1.0, 1.4);
uniform float birch = 0.0;
uniform float ring_bands = 0.0;
uniform float rock_detail : hint_range(0.0, 1.0) = 0.0;
uniform vec4 top_color : source_color = vec4(0.34, 0.44, 0.2, 1.0);
uniform float top_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;


void solid_surface(vec2 uv, vec3 vcol, out vec3 col, out float rough, out vec3 emis) {
	vec3 base = mix(albedo.rgb, albedo2.rgb, v_rand);
	float detail = 1.0;
	if (bark_amount > 0.0) {
		float b = texture(bark_tex, uv * bark_scale).r;
		detail = mix(1.0, 0.5 + 0.7 * b, bark_amount);
		if (birch > 0.5) {
			float dash = step(0.8, fract(uv.y * 2.3 + sin(uv.x * 25.13) * 0.08)) * step(0.35, fract(uv.x * 4.0 + uv.y * 0.6));
			base = mix(vec3(0.86, 0.84, 0.8), vec3(0.1, 0.09, 0.08), dash);
			detail = mix(1.0, detail, 0.35);
		}
		if (ring_bands > 0.0) {
			detail *= 1.0 - ring_bands * smoothstep(0.7, 1.0, fract(uv.y * 3.2));
		}
	}
	if (rock_detail > 0.0) {
		vec3 p = v_wpos * 1.7;
		vec3 w = pow(abs(v_wnrm), vec3(4.0));
		w /= (w.x + w.y + w.z);
		float n = veg_fbm(vec3(p.yz, 0.0)) * w.x + veg_fbm(vec3(p.xz, 3.0)) * w.y + veg_fbm(vec3(p.xy, 7.0)) * w.z;
		detail *= mix(1.0, 0.62 + 0.75 * n, rock_detail);
		base *= mix(1.0, 0.85 + 0.3 * veg_noise(v_wpos * 0.6 + vec3(v_rand * 10.0)), rock_detail);
	}
	col = base * detail * vcol;
	float up = v_wnrm.y + (veg_noise(v_wpos * 2.5 + vec3(v_rand * 20.0)) - 0.5) * 0.5;
	float top = smoothstep(0.35, 0.75, up) * top_amount;
	col = mix(col, top_color.rgb * mix(0.85, 1.05, veg_noise(v_wpos * 5.0)), top);
	rough = mix(roughness_value, 0.95, top);
	emis = emission_color.rgb * emission_energy * vcol;
}
