@tool
extends RefCounted
## Grass types. Every value can be overridden per node / per command.

const PRESETS := {
	"meadow": {
		"description": "Grama de campo / meadow grass",
		"blades": 6, "height": 0.45, "width": 0.045, "curve": 0.35, "density": 6.0,
		"color_base": "#26451a", "color_tip": "#8db04e", "dry_color": "#a1904c", "dry_amount": 0.22,
		"sss_color": "#d6e27a", "wind_strength": 0.35,
	},
	"lush": {
		"description": "Grama verde e densa / lush dense grass",
		"blades": 7, "height": 0.55, "width": 0.05, "curve": 0.3, "density": 7.5,
		"color_base": "#1c4214", "color_tip": "#66b042", "dry_color": "#8c9a3c", "dry_amount": 0.08,
		"sss_color": "#b6f07a", "wind_strength": 0.3,
	},
	"tall": {
		"description": "Capim alto / tall grass",
		"blades": 5, "height": 1.05, "width": 0.04, "curve": 0.55, "density": 4.5,
		"color_base": "#26380f", "color_tip": "#aab55c", "dry_color": "#c2a864", "dry_amount": 0.35,
		"sss_color": "#e6e28a", "wind_strength": 0.6,
	},
	"dry": {
		"description": "Capim seco / dry grass",
		"blades": 6, "height": 0.5, "width": 0.04, "curve": 0.45, "density": 5.0,
		"color_base": "#453716", "color_tip": "#cfb068", "dry_color": "#e2c98a", "dry_amount": 0.55,
		"sss_color": "#f2d890", "wind_strength": 0.4,
	},
	"flowers": {
		"description": "Flores silvestres / wildflowers",
		"blades": 6, "height": 0.38, "width": 0.035, "curve": 0.3, "density": 4.5,
		"color_base": "#2a4a18", "color_tip": "#86ad4c", "dry_color": "#a1904c", "dry_amount": 0.1,
		"sss_color": "#d6e27a", "wind_strength": 0.3,
		"flowers": 0.35, "flower_size": 0.06,
		"flower_colors": ["#ffe14d", "#ff5f9e", "#ffffff", "#b27bff"],
	},
	"wheat": {
		"description": "Trigo / wheat field",
		"blades": 6, "height": 0.95, "width": 0.025, "curve": 0.2, "density": 8.0, "wheat": true,
		"flower_size": 0.03, "color_base": "#6b5a22", "color_tip": "#e6c56a", "dry_color": "#f0d58a", "dry_amount": 0.3,
		"sss_color": "#ffe29a", "wind_strength": 0.5, "flower_colors": ["#e0b75c", "#d9a94a", "#eccb76", "#c9994a"],
	},
	"tundra": {
		"description": "Vegetação rasteira fria / tundra",
		"blades": 5, "height": 0.22, "width": 0.035, "curve": 0.3, "density": 3.5,
		"color_base": "#2f3a26", "color_tip": "#9da583", "dry_color": "#b6ad8a", "dry_amount": 0.4,
		"sss_color": "#c8d0a0", "wind_strength": 0.45,
	},
	"savanna": {
		"description": "Capim de savana / savanna grass",
		"blades": 5, "height": 0.8, "width": 0.035, "curve": 0.5, "density": 4.0,
		"color_base": "#54461c", "color_tip": "#d8bf6c", "dry_color": "#e8d08c", "dry_amount": 0.45,
		"sss_color": "#f6dc8a", "wind_strength": 0.5,
	},
	"reeds": {
		"description": "Juncos de pântano / swamp reeds",
		"blades": 4, "height": 1.4, "width": 0.03, "curve": 0.12, "density": 2.5, "wheat": true,
		"flower_size": 0.045, "color_base": "#233112", "color_tip": "#8a9b48", "dry_color": "#9a8c4a", "dry_amount": 0.2,
		"sss_color": "#c8d27a", "wind_strength": 0.35, "flower_colors": ["#4a2e18", "#5a3a1e", "#3e2614", "#6a4424"],
	},
	"alien": {
		"description": "Grama alienígena brilhante / glowing alien grass",
		"blades": 5, "height": 0.6, "width": 0.05, "curve": 0.6, "density": 5.0,
		"color_base": "#1f0b38", "color_tip": "#c27bff", "dry_color": "#2fd6ff", "dry_amount": 0.3,
		"sss_color": "#ff8cf0", "wind_strength": 0.4, "emission": 1.4,
		"flowers": 0.25, "flower_size": 0.06, "flower_colors": ["#00f0ff", "#ff4fd8", "#9dff6a", "#ffffff"],
	},
}

const ALIASES := {
	"grama": "meadow", "campo": "meadow", "gramado": "meadow", "grass": "meadow", "default": "meadow",
	"exuberante": "lush", "densa": "lush", "tropical": "lush",
	"alta": "tall", "capim": "tall", "capim_alto": "tall", "mato": "tall",
	"seca": "dry", "capim_seco": "dry", "palha": "dry",
	"flores": "flowers", "flor": "flowers", "florido": "flowers", "wildflowers": "flowers",
	"trigo": "wheat", "plantacao": "wheat",
	"neve": "tundra", "fria": "tundra", "snow": "tundra",
	"savana": "savanna", "cerrado": "savanna",
	"juncos": "reeds", "pantano": "reeds", "swamp": "reeds",
	"alienigena": "alien", "magica": "alien", "fantasia": "alien",
}


static func resolve(preset_name: String) -> String:
	var n := preset_name.to_lower().strip_edges().replace(" ", "_")
	for k in {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}.keys():
		n = n.replace(k, {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}[k])
	if PRESETS.has(n):
		return n
	return ALIASES.get(n, "")


static func names() -> Array:
	return PRESETS.keys()
