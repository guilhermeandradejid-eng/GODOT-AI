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
		"fallback": "res://game/assets/characters/juba.glb",
		"base_lid": 0.08,
		"outline": 0.0026,
		"outline_color": Color("1b2350"),
		"eye": {"iris_inner": Color("ffb13b"), "iris_outer": Color("c2621e"), "pupil_color": Color("1b1530"),
			"lid_color": Color("17808e"), "iris_size": 0.4, "pupil_size": 0.18},
		## [raiz, fim, rigidez, arrasto, gravidade, raio, comprimento da ponta]
		"springs": [],
		"materials": {},
		"aliases": {"swim": "fall", "sit": "idle", "flop": "spin"},
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
