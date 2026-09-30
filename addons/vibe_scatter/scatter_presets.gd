@tool
extends RefCounted
## vibe_scatter presets: which models grow, how dense, where (placement
## rules) and in which colors, plus the default vegetation of every terrain
## palette (used by recipes and prompts when nothing is specified).
##
## density = instances per square meter at density 1.0.
## Rules: max_slope/min_slope (deg), min_above_water/max_above_water (m over
## the water level), min_height_frac/max_height_frac (0..1 of the terrain
## height range), cluster (0 = even, 1 = tight groves), cluster_scale (m),
## water_margin (m), clearing (m kept free around effects and characters).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const PRESETS := {
	"forest": {"desc": "floresta de árvores folhosas (carvalhos e bétulas)", "items": {"broadleaf": 0.8, "birch": 0.2},
		"density": 0.012, "scale": [0.8, 1.3], "rules": {"max_slope": 32, "cluster": 0.55, "cluster_scale": 60.0, "max_height_frac": 0.8}},
	"autumn": {"desc": "floresta de outono (laranja, vermelho e amarelo)", "items": {"broadleaf": 1.0},
		"density": 0.012, "scale": [0.8, 1.3], "rules": {"max_slope": 32, "cluster": 0.5}, "palette": "autumn"},
	"pines": {"desc": "pinheiros / coníferas", "items": {"pine": 1.0}, "density": 0.011, "scale": [0.7, 1.35],
		"rules": {"max_slope": 38, "cluster": 0.5, "cluster_scale": 50.0, "max_height_frac": 0.72}},
	"palms": {"desc": "coqueiros / palmeiras perto da água", "items": {"palm": 1.0}, "density": 0.006, "scale": [0.8, 1.2],
		"rules": {"max_slope": 24, "max_above_water": 12.0, "cluster": 0.35, "water_margin": 0.6}},
	"jungle": {"desc": "selva densa (árvores, palmeiras e samambaias)", "items": {"broadleaf": 0.5, "palm": 0.2, "fern": 0.3},
		"density": 0.025, "scale": [0.8, 1.4], "rules": {"max_slope": 34, "cluster": 0.4}},
	"birches": {"desc": "bosque de bétulas (troncos brancos)", "items": {"birch": 1.0}, "density": 0.014, "scale": [0.8, 1.25],
		"rules": {"max_slope": 30, "cluster": 0.6}},
	"acacias": {"desc": "acácias de savana (copa achatada)", "items": {"acacia": 1.0}, "density": 0.0025, "scale": [0.8, 1.3],
		"rules": {"max_slope": 22, "cluster": 0.25}},
	"dead_trees": {"desc": "árvores secas / mortas", "items": {"dead_tree": 1.0}, "density": 0.004, "scale": [0.7, 1.3],
		"rules": {"max_slope": 34, "cluster": 0.3}},
	"bushes": {"desc": "arbustos", "items": {"bush": 1.0}, "density": 0.02, "scale": [0.6, 1.5], "rules": {"max_slope": 36, "cluster": 0.5}},
	"ferns": {"desc": "samambaias", "items": {"fern": 1.0}, "density": 0.05, "scale": [0.7, 1.4], "rules": {"max_slope": 34, "cluster": 0.6}},
	"cacti": {"desc": "cactos (saguaro e barril)", "items": {"cactus": 0.6, "barrel_cactus": 0.4}, "density": 0.003, "scale": [0.7, 1.3],
		"rules": {"max_slope": 26, "cluster": 0.2}},
	"rocks": {"desc": "rochas e seixos", "items": {"rock": 0.7, "pebbles": 0.3}, "density": 0.01, "scale": [0.6, 1.8],
		"rules": {"max_slope": 60, "cluster": 0.45, "water_margin": -0.3}, "align": 0.8, "sink": 0.12},
	"boulders": {"desc": "matacões (rochas grandes)", "items": {"boulder": 1.0}, "density": 0.0012, "scale": [0.7, 1.6],
		"rules": {"max_slope": 50, "cluster": 0.4, "water_margin": -0.5}, "align": 0.6, "sink": 0.2},
	"mushrooms": {"desc": "cogumelos", "items": {"mushroom": 1.0}, "density": 0.015, "scale": [0.7, 1.6], "rules": {"max_slope": 30, "cluster": 0.7}},
	"crystals": {"desc": "cristais brilhantes", "items": {"crystal": 1.0}, "density": 0.004, "scale": [0.6, 1.6],
		"rules": {"max_slope": 45, "cluster": 0.55}, "align": 0.5},
	"logs": {"desc": "troncos caídos e tocos", "items": {"log": 0.6, "stump": 0.4}, "density": 0.0015, "scale": [0.8, 1.2],
		"rules": {"max_slope": 20, "cluster": 0.4}, "align": 1.0},
	"alien_trees": {"desc": "árvores alienígenas", "items": {"broadleaf": 0.6, "acacia": 0.4}, "density": 0.008, "scale": [0.8, 1.5],
		"rules": {"max_slope": 32, "cluster": 0.5}, "palette": "alien"},
}

const ALIASES := {
	"floresta": "forest", "florestas": "forest", "arvores": "forest", "arvore": "forest", "trees": "forest", "tree": "forest",
	"bosque": "forest", "mata": "forest", "carvalhos": "forest", "oaks": "forest", "woods": "forest",
	"outono": "autumn", "fall": "autumn", "pinheiros": "pines", "pinheiro": "pines", "pinhais": "pines", "coniferas": "pines",
	"pine": "pines", "pine_trees": "pines", "conifers": "pines", "abetos": "pines", "firs": "pines",
	"palmeiras": "palms", "palmeira": "palms", "coqueiros": "palms", "coqueiro": "palms", "palm": "palms", "palm_trees": "palms",
	"selva": "jungle", "floresta_tropical": "jungle", "rainforest": "jungle", "betulas": "birches", "birch": "birches",
	"acacia": "acacias", "arvores_secas": "dead_trees", "arvores_mortas": "dead_trees", "dead": "dead_trees", "galhos": "dead_trees",
	"arbustos": "bushes", "arbusto": "bushes", "moitas": "bushes", "shrubs": "bushes", "bush": "bushes",
	"samambaias": "ferns", "fern": "ferns", "cactos": "cacti", "cacto": "cacti", "cactus": "cacti", "cactuses": "cacti",
	"rochas": "rocks", "rocha": "rocks", "pedras": "rocks", "pedra": "rocks", "stones": "rocks", "rock": "rocks", "seixos": "rocks",
	"matacoes": "boulders", "pedregulhos": "boulders", "boulder": "boulders", "rochedos": "boulders",
	"cogumelos": "mushrooms", "cogumelo": "mushrooms", "mushroom": "mushrooms", "fungos": "mushrooms",
	"cristais": "crystals", "cristal": "crystals", "crystal": "crystals", "troncos": "logs", "toras": "logs", "tocos": "logs", "log": "logs",
	"arvores_alienigenas": "alien_trees",
}

## Colors per terrain palette: leaves (up to 3), bark, rock, top (moss/snow)
## amount on rocks and wood, snow on foliage, cactus and crystal colors.
const PALETTES := {
	"temperate": {"leaves": ["#355f1f", "#4f7a26", "#40692a"], "bark": ["#5a4535", "#4a3a2e"], "rock": ["#7a746a", "#6a665e"], "top": "#4f6a30", "top_amount": 0.35},
	"tropical": {"leaves": ["#2a6a20", "#448a26", "#347a32"], "bark": ["#7a634c", "#6a5440"], "rock": ["#8a8174", "#7a7266"], "top": "#557a35", "top_amount": 0.3},
	"snowy": {"leaves": ["#27402c", "#2f4a33", "#33503a"], "bark": ["#4a3a2e", "#3a2e24"], "rock": ["#86868c", "#75757c"], "top": "#f2f4f8", "top_amount": 0.7, "snow": 0.55},
	"desert": {"leaves": ["#6a7a34", "#7f8a3a", "#5f6a2e"], "bark": ["#7a6a55", "#6a5a48"], "rock": ["#b8875a", "#a47a52"], "top": "#c8a070", "top_amount": 0.0, "cactus": ["#5a8a40", "#4a7a3a"]},
	"canyon": {"leaves": ["#6f7a34", "#8a8a3e", "#5f6a2e"], "bark": ["#8a7a6a", "#6a5a4a"], "rock": ["#a0582f", "#8a4a2a"], "top": "#b87a4a", "top_amount": 0.15, "cactus": ["#5a8a40", "#4a7a3a"]},
	"volcanic": {"leaves": ["#3a4a2a", "#4a5530", "#303a24"], "bark": ["#2e2a28", "#241f1c"], "rock": ["#3a3634", "#2e2a28"], "top": "#6b6660", "top_amount": 0.3},
	"autumn": {"leaves": ["#c8641e", "#e0a52c", "#a8321e"], "bark": ["#4a3a2e", "#3e3024"], "rock": ["#7a746a", "#6a665e"], "top": "#6b6a3a", "top_amount": 0.35},
	"alien": {"leaves": ["#9a3ad8", "#3ad8c0", "#d83aa8"], "bark": ["#3a2a5a", "#2a2048"], "rock": ["#4a3a6a", "#3a2e58"], "top": "#7a4ad8", "top_amount": 0.3, "crystal": "#7a5aff"},
	"lunar": {"leaves": ["#6a6a6a", "#7a7a7a", "#5a5a5a"], "bark": ["#5a5a5a", "#4a4a4a"], "rock": ["#8a8a8a", "#7a7a7a"], "top": "#9a9a9a", "top_amount": 0.2},
	"swamp": {"leaves": ["#3f4f24", "#4a5a2a", "#36441f"], "bark": ["#3a3a30", "#2e2e26"], "rock": ["#5a5a4a", "#4a4a3e"], "top": "#3a4a2a", "top_amount": 0.55},
	"savanna": {"leaves": ["#5f6f2a", "#7a7a30", "#4f5f24"], "bark": ["#5a4a3a", "#4a3e30"], "rock": ["#9a8a6a", "#8a7a5e"], "top": "#8a7a4a", "top_amount": 0.15},
}

## Default vegetation per terrain palette: [preset, density].
const PALETTE_DEFAULTS := {
	"temperate": [["forest", 1.0], ["bushes", 0.6], ["rocks", 0.6], ["logs", 0.4]],
	"tropical": [["palms", 1.0], ["jungle", 0.35], ["bushes", 0.5], ["rocks", 0.4]],
	"snowy": [["pines", 1.0], ["rocks", 0.8], ["boulders", 0.5]],
	"desert": [["cacti", 1.0], ["rocks", 0.7], ["boulders", 0.4]],
	"canyon": [["rocks", 1.0], ["boulders", 0.7], ["dead_trees", 0.5], ["bushes", 0.3]],
	"volcanic": [["rocks", 1.0], ["boulders", 0.8], ["dead_trees", 0.6]],
	"autumn": [["autumn", 1.0], ["bushes", 0.4], ["rocks", 0.5], ["mushrooms", 0.5], ["logs", 0.5]],
	"alien": [["crystals", 1.0], ["alien_trees", 0.7], ["rocks", 0.4]],
	"lunar": [["rocks", 1.0], ["boulders", 0.9]],
	"swamp": [["dead_trees", 1.0], ["mushrooms", 0.8], ["bushes", 0.5], ["logs", 0.6]],
	"savanna": [["acacias", 1.0], ["bushes", 0.6], ["rocks", 0.4]],
}


static func resolve(name: String) -> String:
	var k := Util.slugify(name)
	if PRESETS.has(k):
		return k
	if ALIASES.has(k):
		return ALIASES[k]
	if k.ends_with("s") and PRESETS.has(k.trim_suffix("s")):
		return k.trim_suffix("s")
	return ""


static func get_preset(name: String) -> Dictionary:
	var k := resolve(name)
	return PRESETS.get(k, {})


static func palette_colors(palette: String) -> Dictionary:
	return PALETTES.get(palette, PALETTES.temperate)


static func defaults_for(palette: String) -> Array:
	return PALETTE_DEFAULTS.get(palette, PALETTE_DEFAULTS.temperate)
