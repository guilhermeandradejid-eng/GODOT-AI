@tool
extends RefCounted
## Biome palettes: 4 surface layers + auto-paint rules for each biome.
##
## Layer order convention: 0 = base ground, 1 = secondary (dirt/sand/beach),
## 2 = cliffs (rock), 3 = peaks/special (snow, lava, crystals...).

const PALETTES := {
	"temperate": {
		"description": "Campos verdes, terra, rocha e neve nos picos / green fields, dirt, rock, snowy peaks",
		"layers": [
			{"name": "Grama", "color_a": "#34521f", "color_b": "#5a7a2e", "noise_scale": 0.12, "roughness": 0.92},
			{"name": "Terra", "color_a": "#4f3b29", "color_b": "#76593b", "noise_scale": 0.5, "roughness": 0.95},
			{"name": "Rocha", "color_a": "#5d5955", "color_b": "#8e8983", "noise_scale": 0.25, "strata": 0.35, "roughness": 0.85},
			{"name": "Neve", "color_a": "#dfe7f0", "color_b": "#ffffff", "noise_scale": 0.3, "roughness": 0.55},
		],
		"rules": {"beach_layer": 1, "cliff_layer": 2, "cliff_slope": 36.0, "steep_layer": 1, "steep_slope": 29.0, "peak_layer": 3, "peak_height": 0.82},
	},
	"tropical": {
		"description": "Verde exuberante, areia clara, rocha escura e musgo / lush green, white sand, dark rock, moss",
		"layers": [
			{"name": "Grama tropical", "color_a": "#2c5a1f", "color_b": "#4f7f2a", "noise_scale": 0.14, "roughness": 0.9},
			{"name": "Areia", "color_a": "#c9b27e", "color_b": "#e2d3a4", "noise_scale": 0.6, "roughness": 0.97},
			{"name": "Rocha vulcânica", "color_a": "#3c3a38", "color_b": "#5f5a55", "noise_scale": 0.3, "strata": 0.15, "roughness": 0.8},
			{"name": "Musgo", "color_a": "#1f4222", "color_b": "#355f2a", "noise_scale": 0.2, "roughness": 0.9},
		],
		"rules": {"beach_layer": 1, "beach_band": 2.2, "cliff_layer": 2, "cliff_slope": 40.0, "steep_layer": 3, "steep_slope": 26.0, "peak_layer": -1},
	},
	"snowy": {
		"description": "Neve, cascalho congelado, rocha e gelo / snow, frozen gravel, rock, ice",
		"layers": [
			{"name": "Neve", "color_a": "#e6edf5", "color_b": "#ffffff", "noise_scale": 0.2, "roughness": 0.5},
			{"name": "Cascalho", "color_a": "#6f6d6b", "color_b": "#9c9894", "noise_scale": 0.7, "roughness": 0.9},
			{"name": "Rocha", "color_a": "#4d4a48", "color_b": "#7b7672", "noise_scale": 0.25, "strata": 0.4, "roughness": 0.85},
			{"name": "Gelo", "color_a": "#a9cde6", "color_b": "#d8ecf7", "noise_scale": 0.15, "roughness": 0.15},
		],
		# Snow sticks to fairly steep slopes (and covers the upper half even
		# steeper): only real cliffs show rock.
		"rules": {"beach_layer": 3, "beach_band": 1.5, "cliff_layer": 2, "cliff_slope": 52.0, "steep_layer": 1, "steep_slope": 44.0,
			"peak_layer": 0, "peak_height": 0.45, "peak_max_slope": 60.0},
	},
	"desert": {
		"description": "Areia dourada, cascalho, arenito e rocha escura / golden sand, gravel, sandstone, dark rock",
		"layers": [
			{"name": "Areia", "color_a": "#d4a95f", "color_b": "#e9c98a", "noise_scale": 0.35, "roughness": 0.95},
			{"name": "Cascalho", "color_a": "#9c7a4e", "color_b": "#b8935f", "noise_scale": 0.8, "roughness": 0.95},
			{"name": "Arenito", "color_a": "#b0673a", "color_b": "#d08d58", "noise_scale": 0.2, "strata": 0.7, "roughness": 0.85},
			{"name": "Rocha escura", "color_a": "#5a4336", "color_b": "#7a5c49", "noise_scale": 0.3, "strata": 0.3, "roughness": 0.8},
		],
		"rules": {"beach_layer": 1, "beach_band": 1.0, "cliff_layer": 2, "cliff_slope": 30.0, "steep_layer": 1, "steep_slope": 18.0, "peak_layer": 3, "peak_height": 0.85},
	},
	"canyon": {
		"description": "Areia vermelha, terra alaranjada, rocha em camadas / red sand, orange dirt, banded rock",
		"layers": [
			{"name": "Areia vermelha", "color_a": "#b25b33", "color_b": "#d27f4b", "noise_scale": 0.4, "roughness": 0.95},
			{"name": "Terra", "color_a": "#8a4a2b", "color_b": "#a8663e", "noise_scale": 0.6, "roughness": 0.95},
			{"name": "Rocha em camadas", "color_a": "#9e4d2c", "color_b": "#e0a070", "noise_scale": 0.15, "strata": 1.0, "roughness": 0.85},
			{"name": "Rocha clara", "color_a": "#c9a27a", "color_b": "#e8cfa8", "noise_scale": 0.2, "strata": 0.5, "roughness": 0.8},
		],
		"rules": {"beach_layer": 1, "beach_band": 1.5, "cliff_layer": 2, "cliff_slope": 28.0, "steep_layer": 2, "steep_slope": 20.0, "peak_layer": 3, "peak_height": 0.9},
	},
	"volcanic": {
		"description": "Cinzas, basalto, rocha escura e lava brilhante / ash, basalt, dark rock, glowing lava",
		"layers": [
			{"name": "Cinzas", "color_a": "#2b2927", "color_b": "#4a4541", "noise_scale": 0.3, "roughness": 0.95},
			{"name": "Basalto", "color_a": "#171514", "color_b": "#2e2a28", "noise_scale": 0.5, "roughness": 0.7},
			{"name": "Rocha", "color_a": "#3b2e27", "color_b": "#5c463a", "noise_scale": 0.25, "strata": 0.3, "roughness": 0.85},
			{"name": "Lava", "color_a": "#ff4a00", "color_b": "#ffc233", "noise_scale": 0.4, "roughness": 0.4, "emission": 4.0},
		],
		"rules": {"beach_layer": 1, "beach_band": 1.5, "cliff_layer": 2, "cliff_slope": 34.0, "steep_layer": 1, "steep_slope": 22.0, "peak_layer": 3, "peak_height": 0.86, "peak_max_slope": 40.0},
	},
	"autumn": {
		"description": "Grama alaranjada, terra, rocha e folhas vermelhas / orange grass, dirt, rock, red leaves",
		"layers": [
			{"name": "Grama de outono", "color_a": "#7a5a26", "color_b": "#a37a34", "noise_scale": 0.15, "roughness": 0.92},
			{"name": "Terra", "color_a": "#5a3f2a", "color_b": "#7c5a3c", "noise_scale": 0.5, "roughness": 0.95},
			{"name": "Rocha", "color_a": "#5e5a55", "color_b": "#8a847d", "noise_scale": 0.25, "strata": 0.3, "roughness": 0.85},
			{"name": "Folhas", "color_a": "#9b2f14", "color_b": "#d6621f", "noise_scale": 0.4, "roughness": 0.9},
		],
		"rules": {"beach_layer": 1, "cliff_layer": 2, "cliff_slope": 36.0, "steep_layer": 1, "steep_slope": 24.0, "peak_layer": -1, "patch_layer": 3, "patch_amount": 0.35},
	},
	"alien": {
		"description": "Planeta alienígena: grama roxa, solo azul-petróleo, cristais brilhantes / purple grass, teal soil, glowing crystals",
		"layers": [
			{"name": "Grama alien", "color_a": "#4a2470", "color_b": "#7d42ad", "noise_scale": 0.15, "roughness": 0.8},
			{"name": "Solo", "color_a": "#14535a", "color_b": "#237a78", "noise_scale": 0.5, "roughness": 0.9},
			{"name": "Rocha", "color_a": "#2a2440", "color_b": "#4b3f6e", "noise_scale": 0.25, "strata": 0.4, "roughness": 0.7},
			{"name": "Cristal", "color_a": "#00e5ff", "color_b": "#b8ffff", "noise_scale": 0.6, "roughness": 0.2, "emission": 2.5},
		],
		"rules": {"beach_layer": 1, "cliff_layer": 2, "cliff_slope": 36.0, "steep_layer": 1, "steep_slope": 24.0, "peak_layer": 3, "peak_height": 0.82},
	},
	"lunar": {
		"description": "Regolito cinza, poeira escura e rocha clara / gray regolith, dark dust, light rock",
		"layers": [
			{"name": "Regolito", "color_a": "#6d6d6d", "color_b": "#9a9a9a", "noise_scale": 0.3, "roughness": 0.98},
			{"name": "Poeira escura", "color_a": "#3e3e40", "color_b": "#58585b", "noise_scale": 0.5, "roughness": 0.98},
			{"name": "Rocha", "color_a": "#8a8886", "color_b": "#b8b5b1", "noise_scale": 0.2, "strata": 0.2, "roughness": 0.9},
			{"name": "Ejecta", "color_a": "#c8c8c8", "color_b": "#ececec", "noise_scale": 0.4, "roughness": 0.95},
		],
		"rules": {"beach_layer": 1, "cliff_layer": 2, "cliff_slope": 30.0, "steep_layer": 1, "steep_slope": 16.0, "peak_layer": 3, "peak_height": 0.85},
	},
	"swamp": {
		"description": "Pântano: musgo escuro, lama, rocha e algas / dark moss, mud, rock, algae",
		"layers": [
			{"name": "Musgo", "color_a": "#2c3b1c", "color_b": "#4a5a2a", "noise_scale": 0.2, "roughness": 0.85},
			{"name": "Lama", "color_a": "#2e2419", "color_b": "#4a3a28", "noise_scale": 0.5, "roughness": 0.5},
			{"name": "Rocha", "color_a": "#454842", "color_b": "#666a60", "noise_scale": 0.25, "strata": 0.2, "roughness": 0.85},
			{"name": "Algas", "color_a": "#3d5f1f", "color_b": "#6b8f2a", "noise_scale": 0.3, "roughness": 0.6},
		],
		"rules": {"beach_layer": 1, "beach_band": 3.0, "cliff_layer": 2, "cliff_slope": 38.0, "steep_layer": 1, "steep_slope": 20.0, "peak_layer": -1, "patch_layer": 3, "patch_amount": 0.3},
	},
	"savanna": {
		"description": "Savana: capim amarelo, terra vermelha, rocha / yellow grass, red earth, rock",
		"layers": [
			{"name": "Capim seco", "color_a": "#8a7a3a", "color_b": "#b09a50", "noise_scale": 0.15, "roughness": 0.93},
			{"name": "Terra vermelha", "color_a": "#8a4a2a", "color_b": "#a8603a", "noise_scale": 0.5, "roughness": 0.95},
			{"name": "Rocha", "color_a": "#6a5f55", "color_b": "#958778", "noise_scale": 0.25, "strata": 0.3, "roughness": 0.85},
			{"name": "Grama verde", "color_a": "#4a6726", "color_b": "#667f32", "noise_scale": 0.2, "roughness": 0.9},
		],
		"rules": {"beach_layer": 1, "cliff_layer": 2, "cliff_slope": 34.0, "steep_layer": 1, "steep_slope": 20.0, "peak_layer": -1, "patch_layer": 3, "patch_amount": 0.25},
	},
}

## Realistic style: built-in PBR texture set, tint and meters per tile for each layer.
const TEXTURES := {
	"temperate": [["grass_ground", "#95bd8c", 3.0], ["dirt", "#ffffff", 3.0], ["rock", "#aba7a1", 6.0], ["snow", "#ffffff", 5.0]],
	"tropical": [["grass_ground", "#72ba70", 3.0], ["sand", "#ffffff", 4.0], ["rock", "#8a847e", 6.0], ["moss", "#ffffff", 3.0]],
	"snowy": [["snow", "#ffffff", 5.0], ["gravel", "#c8d0dc", 2.5], ["rock", "#8e949c", 6.0], ["ice", "#ffffff", 5.0]],
	"desert": [["sand", "#ffffff", 4.0], ["gravel", "#e0c098", 2.5], ["sandstone", "#ffffff", 7.0], ["rock", "#a07a5c", 6.0]],
	"canyon": [["sand", "#f0a878", 4.0], ["dirt", "#e09a68", 3.0], ["sandstone", "#ffffff", 7.0], ["sandstone", "#f4dcc0", 5.0]],
	"volcanic": [["ash", "#ffffff", 3.0], ["gravel", "#5a524a", 2.5], ["rock", "#6a5a52", 6.0], ["lava", "#ffffff", 5.0]],
	"autumn": [["grass_ground", "#e8b888", 3.0], ["dirt", "#ffffff", 3.0], ["rock", "#aba7a1", 6.0], ["moss", "#e07040", 3.0]],
	"alien": [["moss", "#c080ff", 3.0], ["dirt", "#60d0d0", 3.0], ["rock", "#9070d0", 6.0], ["crystal", "#ffffff", 4.0]],
	"lunar": [["regolith", "#ffffff", 5.0], ["ash", "#a0a0a0", 3.0], ["rock", "#d0d0d0", 6.0], ["regolith", "#f0f0f0", 3.0]],
	"swamp": [["moss", "#8a9a6a", 3.0], ["mud", "#ffffff", 3.0], ["rock", "#8a9080", 6.0], ["moss", "#a8c070", 2.5]],
	"savanna": [["grass_ground", "#f0d890", 3.0], ["dirt", "#f09868", 3.0], ["rock", "#c4b8a6", 6.0], ["grass_ground", "#95bd8c", 3.0]],
}

const ALIASES := {
	"temperado": "temperate", "padrao": "temperate", "default": "temperate", "floresta": "temperate", "forest": "temperate",
	"tropico": "tropical", "selva": "tropical", "jungle": "tropical", "praia": "tropical", "beach": "tropical",
	"neve": "snowy", "snow": "snowy", "nevado": "snowy", "gelo": "snowy", "ice": "snowy", "arctic": "snowy", "artico": "snowy", "inverno": "snowy", "winter": "snowy",
	"deserto": "desert", "areia": "desert", "sand": "desert", "dunas": "desert",
	"canion": "canyon", "mesa": "canyon", "vermelho": "canyon",
	"vulcanico": "volcanic", "vulcao": "volcanic", "volcano": "volcanic", "lava": "volcanic",
	"outono": "autumn", "fall": "autumn",
	"alienigena": "alien", "fantasia": "alien", "fantasy": "alien", "magico": "alien",
	"lua": "lunar", "moon": "lunar",
	"pantano": "swamp", "brejo": "swamp",
	"savana": "savanna", "cerrado": "savanna",
}


const _ACCENTS := {"á": "a", "à": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ü": "u", "ç": "c"}


static func normalize(text: String) -> String:
	var n := text.to_lower().strip_edges()
	for k in _ACCENTS:
		n = n.replace(k, _ACCENTS[k])
	return n


static func resolve(palette_name: String) -> String:
	var n := normalize(palette_name)
	if PALETTES.has(n):
		return n
	return ALIASES.get(n, "")


static func names() -> Array:
	return PALETTES.keys()


static func get_palette(palette_name: String) -> Dictionary:
	var key := resolve(palette_name)
	return PALETTES.get(key, {})
