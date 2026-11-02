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
	},
	"strong": {
		"name": "Hulvar",
		"model": "res://game/assets/characters/hulvar.glb",
		"fallback": "res://game/assets/characters/caju.glb",
		"base_lid": 0.3,
		"outline": 0.0032,
		"outline_color": Color("141a3f"),
		"eye": {"iris_inner": Color("3fe6d8"), "iris_outer": Color("1e8c93"), "pupil_color": Color("10233a"),
			"lid_color": Color("343c96"), "iris_size": 0.42, "pupil_size": 0.2},
		"springs": [],
		"materials": {},
		"aliases": {"swim": "fall", "flop": "slam", "sit": "brace", "spin": "ram"},
	},
}


static func def_of(role: String) -> Dictionary:
	return DEFS.get(role, DEFS["agile"])


static func display_name(role: String) -> String:
	return String(def_of(role).get("name", role))
