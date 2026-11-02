class_name HeroDefs
extends RefCounted
## Dados das duas personagens: nome exibido, modelo (GLB gerado no Blender),
## olhos, contorno, molas (física secundária), ajustes de material e apelidos
## de animação. O código de jogo usa os papéis "agile" (a pequena e ágil) e
## "strong" (o grande e forte); nomes e aparência ficam só aqui.

const DEFS := {
	"agile": {
		"name": "Saeli",
		"model": "res://game/assets/characters/saeli.glb",
		"fallback": "res://game/assets/characters/saeli.glb",
		"base_lid": 0.08,
		"outline": 0.0026,
		"outline_color": Color("1b2350"),
		"eye": {"sclera": Color("fffdf6"), "iris_inner": Color("ffb13b"), "iris_outer": Color("c2621e"),
			"pupil_color": Color("1b1530"), "lid_color": Color("17808e"), "iris_size": 0.6, "pupil_size": 0.28},
		## [raiz, fim, rigidez, arrasto, gravidade, raio, comprimento da ponta, grupo]
		"springs": [
			["earfin_L_1", "earfin_L_2", 2.4, 0.3, 0.15, 0.02, 0.04, "ears"],
			["earfin_R_1", "earfin_R_2", 2.4, 0.3, 0.15, 0.02, 0.04, "ears"],
			["tail_1", "board", 1.4, 0.35, 0.5, 0.03, 0.06, "tail"],
		],
		## grupos de molas desligados nestes estados (poses autorais)
		"spring_off": {"tail": ["surf", "glide", "launch", "spin", "ride", "double_jump"]},
		"materials": {"glow": {"vertex_glow": 2.4, "rim_strength": 0.9}},
		"aliases": {"swim": "fall", "sit": "idle", "flop": "spin", "brace": "ride"},
		## passada medida nos clipes (metros por ciclo) para os pés não deslizarem
		"walk_stride": 0.49, "run_stride": 1.0, "max_cps": 3.4,
	},
	"strong": {
		"name": "Hulvar",
		"model": "res://game/assets/characters/hulvar.glb",
		"fallback": "res://game/assets/characters/hulvar.glb",
		"base_lid": 0.15,
		"outline": 0.0032,
		"outline_color": Color("141a3f"),
		"eye": {"sclera": Color("f8fbff"), "iris_inner": Color("3fe6d8"), "iris_outer": Color("1e8c93"),
			"pupil_color": Color("10233a"), "lid_color": Color("343c96"), "iris_size": 0.55, "pupil_size": 0.24},
		"springs": [
			["chain_1", "anchor", 1.0, 0.22, 1.4, 0.06, 0.1, "anchor"],
			["nest", "nest", 5.0, 0.45, 0.0, 0.05, 0.22, "nest"],
		],
		"spring_off": {"anchor": ["brace", "slam", "surf", "celebrate"], "nest": ["brace", "slam"]},
		"materials": {},
		"aliases": {"swim": "fall", "flop": "slam", "sit": "brace", "spin": "ram"},
		"walk_stride": 0.62, "run_stride": 2.9, "max_cps": 2.6,
	},
}


static func def_of(role: String) -> Dictionary:
	return DEFS.get(role, DEFS["agile"])


static func display_name(role: String) -> String:
	return String(def_of(role).get("name", role))
