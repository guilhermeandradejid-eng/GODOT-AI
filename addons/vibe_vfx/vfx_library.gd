@tool
extends RefCounted
## VFX preset library. Every preset is plain data (JSON-compatible) so new
## effects can be written by hand or by Claude (`vfx.define`) and saved as
## res://vfx_presets/<name>.json.
##
## Preset keys:
##   description, category, one_shot, duration (s, one-shots), follow_camera,
##   light: {color, energy, range, flicker, decay}, mesh_fx: ["campfire_base", ...],
##   layers: [ emitter, ... ]
## Emitter keys (all optional):
##   name, amount, lifetime, explosiveness, randomness, preprocess, local_coords,
##   shape (point|sphere|box|ring|disc), radius, extents [x,y,z], offset [x,y,z],
##   direction [x,y,z], spread (deg), velocity [min,max], gravity [x,y,z],
##   damping [min,max], radial_accel [min,max], tangential_accel [min,max],
##   orbit [min,max], turbulence {strength, scale, speed}, angle [min,max],
##   spin [min,max] (deg/s), scale [min,max], scale_curve [[t,v],...],
##   color_ramp [[t,"#rrggbbaa"],...], hue_variation [min,max],
##   sprite (soft_circle|smoke|flame|spark|flare|sparkle|ring|drop|snowflake|leaf),
##   blend (add|mix), align (billboard|velocity|none), stretch, emissive, lit,
##   lowpoly_mesh (sphere|box|prism|quad).

const SPRITES := {
	"soft_circle": {"path": "res://addons/vibe_vfx/textures/soft_circle.webp", "frames": 1},
	"smoke": {"path": "res://addons/vibe_vfx/textures/smoke_atlas.webp", "frames": 2},
	"flame": {"path": "res://addons/vibe_vfx/textures/flame_atlas.webp", "frames": 2},
	"spark": {"path": "res://addons/vibe_vfx/textures/spark.webp", "frames": 1},
	"flare": {"path": "res://addons/vibe_vfx/textures/flare.webp", "frames": 1},
	"sparkle": {"path": "res://addons/vibe_vfx/textures/sparkle.webp", "frames": 1},
	"ring": {"path": "res://addons/vibe_vfx/textures/ring.webp", "frames": 1},
	"drop": {"path": "res://addons/vibe_vfx/textures/drop.webp", "frames": 1},
	"snowflake": {"path": "res://addons/vibe_vfx/textures/snowflake.webp", "frames": 1},
	"leaf": {"path": "res://addons/vibe_vfx/textures/leaf_atlas.webp", "frames": 2},
}

const _FLAMES := {
	"name": "flames", "amount": 42, "lifetime": 0.9, "shape": "box", "extents": [0.22, 0.04, 0.22],
	"direction": [0, 1, 0], "spread": 10, "velocity": [0.7, 1.5], "gravity": [0, 1.4, 0], "damping": [0.3, 0.8],
	"angle": [-25, 25], "spin": [-40, 40], "scale": [0.55, 0.95], "scale_curve": [[0, 0.35], [0.25, 1.0], [1, 0.15]],
	"color_ramp": [[0, "#ffd98aff"], [0.2, "#ffa030ff"], [0.5, "#f0501acc"], [1, "#3c0e0400"]],
	"sprite": "flame", "blend": "add", "emissive": 1.7, "turbulence": {"strength": 0.5, "scale": 2.2, "speed": 1.2},
	"lowpoly_mesh": "prism",
}
const _FIRE_SMOKE := {
	"name": "smoke", "amount": 16, "lifetime": 3.0, "shape": "sphere", "radius": 0.2, "offset": [0, 0.9, 0],
	"direction": [0, 1, 0], "spread": 12, "velocity": [0.35, 0.8], "gravity": [0, 0.5, 0], "damping": [0.1, 0.3],
	"angle": [0, 360], "spin": [-20, 20], "scale": [0.7, 1.2], "scale_curve": [[0, 0.45], [1, 2.2]],
	"color_ramp": [[0, "#2d2a2800"], [0.15, "#2a272599"], [0.6, "#4a464266"], [1, "#6a666200"]],
	"sprite": "smoke", "blend": "mix", "lit": true, "turbulence": {"strength": 0.4, "scale": 1.5, "speed": 0.5},
	"lowpoly_mesh": "sphere",
}
const _EMBERS := {
	"name": "embers", "amount": 14, "lifetime": 2.0, "shape": "sphere", "radius": 0.3,
	"direction": [0, 1, 0], "spread": 30, "velocity": [0.8, 2.4], "gravity": [0, 0.7, 0], "damping": [0.2, 0.5],
	"scale": [0.03, 0.07], "color_ramp": [[0, "#ffe08aff"], [0.6, "#ff7a1aff"], [1, "#ff3a0000"]],
	"sprite": "soft_circle", "blend": "add", "emissive": 5.0, "turbulence": {"strength": 1.4, "scale": 3.0, "speed": 1.5},
	"lowpoly_mesh": "box",
}

const PRESETS := {
	"fire": {
		"description": "Fogo / fire", "category": "fire",
		"layers": [_FLAMES, _FIRE_SMOKE, _EMBERS],
		"light": {"color": "#ff9a3c", "energy": 1.6, "range": 7.0, "flicker": 0.35, "offset": [0, 0.8, 0]},
	},
	"campfire": {
		"description": "Fogueira com lenha e pedras / campfire", "category": "fire",
		"layers": [_FLAMES, _FIRE_SMOKE, _EMBERS],
		"light": {"color": "#ff8a2e", "energy": 1.8, "range": 8.0, "flicker": 0.4, "offset": [0, 0.8, 0]},
		"mesh_fx": ["campfire_base"],
	},
	"torch": {
		"description": "Tocha / torch", "category": "fire", "scale": 0.45,
		"layers": [_FLAMES, _EMBERS],
		"light": {"color": "#ffa04a", "energy": 1.8, "range": 6.0, "flicker": 0.3, "offset": [0, 0.5, 0]},
		"mesh_fx": ["torch_stick"], "base_offset": [0, 1.35, 0],
	},
	"embers": {
		"description": "Brasas flutuando / floating embers", "category": "fire",
		"layers": [{
			"name": "embers", "amount": 40, "lifetime": 4.0, "shape": "box", "extents": [1.5, 0.3, 1.5],
			"direction": [0, 1, 0], "spread": 40, "velocity": [0.3, 1.2], "gravity": [0, 0.3, 0],
			"scale": [0.03, 0.08], "color_ramp": [[0, "#ffd27a00"], [0.15, "#ffb04aff"], [0.8, "#ff5a1aff"], [1, "#ff3a0000"]],
			"sprite": "soft_circle", "blend": "add", "emissive": 5.0, "turbulence": {"strength": 1.8, "scale": 2.0, "speed": 1.0},
			"lowpoly_mesh": "box"}],
	},
	"sparks": {
		"description": "Faíscas / sparks", "category": "fire",
		"layers": [{
			"name": "sparks", "amount": 50, "lifetime": 0.9, "explosiveness": 0.25, "shape": "sphere", "radius": 0.1,
			"direction": [0, 1, 0], "spread": 55, "velocity": [3.0, 6.5], "gravity": [0, -9.8, 0], "damping": [0.5, 1.0],
			"scale": [0.03, 0.05], "stretch": 5.0, "align": "velocity",
			"color_ramp": [[0, "#fff6c8ff"], [0.5, "#ffb13dff"], [1, "#ff4a0000"]],
			"sprite": "spark", "blend": "add", "emissive": 6.0, "lowpoly_mesh": "box"}],
		"light": {"color": "#ffb45a", "energy": 1.0, "range": 4.0, "flicker": 0.8},
	},
	"smoke": {
		"description": "Coluna de fumaça / smoke column", "category": "smoke",
		"layers": [{
			"name": "smoke", "amount": 32, "lifetime": 6.0, "shape": "sphere", "radius": 0.5,
			"direction": [0, 1, 0], "spread": 8, "velocity": [0.8, 1.6], "gravity": [0.25, 0.35, 0], "damping": [0.05, 0.2],
			"angle": [0, 360], "spin": [-15, 15], "scale": [1.2, 2.0], "scale_curve": [[0, 0.4], [1, 3.0]],
			"color_ramp": [[0, "#3a383600"], [0.12, "#3a3836aa"], [0.7, "#6a676455"], [1, "#8a878400"]],
			"sprite": "smoke", "blend": "mix", "lit": true, "turbulence": {"strength": 0.5, "scale": 1.2, "speed": 0.4},
			"lowpoly_mesh": "sphere"}],
	},
	"steam": {
		"description": "Vapor / steam", "category": "smoke",
		"layers": [{
			"name": "steam", "amount": 24, "lifetime": 2.2, "shape": "disc", "radius": 0.4,
			"direction": [0, 1, 0], "spread": 10, "velocity": [1.0, 2.0], "gravity": [0, 0.8, 0], "damping": [0.5, 1.0],
			"angle": [0, 360], "spin": [-30, 30], "scale": [0.6, 1.0], "scale_curve": [[0, 0.3], [1, 2.4]],
			"color_ramp": [[0, "#ffffff00"], [0.15, "#f2f6ff88"], [1, "#ffffff00"]],
			"sprite": "smoke", "blend": "mix", "lit": true, "turbulence": {"strength": 0.6, "scale": 1.8, "speed": 0.8},
			"lowpoly_mesh": "sphere"}],
	},
	"explosion": {
		"description": "Explosão (uma vez) / explosion (one shot)", "category": "impact", "one_shot": true, "duration": 3.5,
		"layers": [
			{"name": "flash", "amount": 1, "lifetime": 0.25, "explosiveness": 1.0, "shape": "point", "velocity": [0, 0],
				"scale": [6.0, 6.0], "scale_curve": [[0, 0.4], [0.3, 1.0], [1, 0.0]], "color_ramp": [[0, "#fffbe8ff"], [1, "#ffd08000"]],
				"sprite": "flare", "blend": "add", "emissive": 6.0, "lowpoly_mesh": "sphere"},
			{"name": "fireball", "amount": 28, "lifetime": 0.9, "explosiveness": 1.0, "shape": "sphere", "radius": 0.4,
				"direction": [0, 1, 0], "spread": 180, "velocity": [2.0, 5.5], "gravity": [0, 1.5, 0], "damping": [3.0, 5.0],
				"angle": [0, 360], "spin": [-90, 90], "scale": [1.2, 2.2], "scale_curve": [[0, 0.3], [0.2, 1.0], [1, 0.6]],
				"color_ramp": [[0, "#fff7d0ff"], [0.2, "#ffc040ff"], [0.5, "#ff5010dd"], [1, "#2a0a0400"]],
				"sprite": "flame", "blend": "add", "emissive": 3.5, "lowpoly_mesh": "sphere"},
			{"name": "smoke", "amount": 22, "lifetime": 3.2, "explosiveness": 0.9, "shape": "sphere", "radius": 0.8,
				"direction": [0, 1, 0], "spread": 180, "velocity": [1.0, 3.0], "gravity": [0, 0.8, 0], "damping": [1.5, 2.5],
				"angle": [0, 360], "spin": [-20, 20], "scale": [1.8, 3.0], "scale_curve": [[0, 0.3], [1, 1.6]],
				"color_ramp": [[0, "#2a262200"], [0.1, "#2a2622cc"], [0.7, "#4a464288"], [1, "#6a666200"]],
				"sprite": "smoke", "blend": "mix", "lit": true, "lowpoly_mesh": "sphere"},
			{"name": "sparks", "amount": 70, "lifetime": 1.3, "explosiveness": 1.0, "shape": "sphere", "radius": 0.3,
				"direction": [0, 1, 0], "spread": 180, "velocity": [7.0, 15.0], "gravity": [0, -9.8, 0], "damping": [1.0, 2.0],
				"scale": [0.04, 0.07], "stretch": 6.0, "align": "velocity",
				"color_ramp": [[0, "#fff6c8ff"], [0.6, "#ffa03aff"], [1, "#ff300000"]],
				"sprite": "spark", "blend": "add", "emissive": 6.0, "lowpoly_mesh": "box"},
		],
		"light": {"color": "#ffb060", "energy": 10.0, "range": 16.0, "decay": 1.6},
		"mesh_fx": ["shockwave"],
	},
	"volcano_plume": {
		"description": "Pluma vulcânica (fumaça + brasas) / volcanic plume", "category": "smoke", "scale": 6.0,
		"layers": [
			{"name": "plume", "amount": 40, "lifetime": 9.0, "shape": "sphere", "radius": 0.6, "preprocess": 6.0,
				"direction": [0, 1, 0], "spread": 12, "velocity": [1.2, 2.2], "gravity": [0.35, 0.25, 0.1], "damping": [0.05, 0.15],
				"angle": [0, 360], "spin": [-8, 8], "scale": [1.4, 2.2], "scale_curve": [[0, 0.4], [1, 3.2]],
				"color_ramp": [[0, "#1c1a1900"], [0.1, "#23201ecc"], [0.6, "#3c3835aa"], [1, "#55504c00"]],
				"sprite": "smoke", "blend": "mix", "lit": true, "turbulence": {"strength": 0.35, "scale": 0.8, "speed": 0.25},
				"lowpoly_mesh": "sphere"},
			{"name": "embers", "amount": 30, "lifetime": 3.0, "shape": "sphere", "radius": 0.5,
				"direction": [0, 1, 0], "spread": 35, "velocity": [2.0, 4.0], "gravity": [0, -1.5, 0],
				"scale": [0.05, 0.1], "color_ramp": [[0, "#ffe08aff"], [0.7, "#ff5a1aff"], [1, "#ff200000"]],
				"sprite": "soft_circle", "blend": "add", "emissive": 6.0, "turbulence": {"strength": 1.0, "scale": 1.0, "speed": 1.0},
				"lowpoly_mesh": "box"},
		],
		"light": {"color": "#ff5a1a", "energy": 3.0, "range": 25.0, "flicker": 0.25},
	},
	"magic_aura": {
		"description": "Aura mágica / magic aura", "category": "magic",
		"layers": [
			{"name": "sparkles", "amount": 40, "lifetime": 1.8, "shape": "ring", "radius": 0.9,
				"direction": [0, 1, 0], "spread": 5, "velocity": [0.6, 1.4], "gravity": [0, 0.4, 0], "orbit": [0.2, 0.4],
				"scale": [0.08, 0.16], "scale_curve": [[0, 0.0], [0.2, 1.0], [1, 0.0]],
				"color_ramp": [[0, "#e0c8ffff"], [0.5, "#9a5cffff"], [1, "#4a2aff00"]],
				"sprite": "sparkle", "blend": "add", "emissive": 4.0, "lowpoly_mesh": "prism"},
			{"name": "wisps", "amount": 12, "lifetime": 2.5, "shape": "ring", "radius": 0.7,
				"direction": [0, 1, 0], "spread": 10, "velocity": [0.2, 0.5], "tangential_accel": [1.0, 2.0],
				"scale": [0.5, 0.8], "scale_curve": [[0, 0.2], [0.4, 1.0], [1, 0.0]],
				"color_ramp": [[0, "#b07bff00"], [0.3, "#8a4dff66"], [1, "#4a2aff00"]],
				"sprite": "soft_circle", "blend": "add", "emissive": 2.5, "lowpoly_mesh": "sphere"},
		],
		"light": {"color": "#9a5cff", "energy": 1.5, "range": 5.0, "flicker": 0.15, "offset": [0, 0.8, 0]},
		"mesh_fx": ["magic_circle"],
	},
	"portal": {
		"description": "Portal mágico / magic portal", "category": "magic",
		"layers": [{
			"name": "swirl", "amount": 70, "lifetime": 1.6, "shape": "ring", "radius": 1.6, "offset": [0, 1.9, 0], "ring_axis": [0, 0, 1],
			"direction": [0, 0, 1], "spread": 0, "velocity": [0.0, 0.2], "radial_accel": [-2.5, -1.5], "tangential_accel": [2.0, 3.0],
			"scale": [0.06, 0.12], "scale_curve": [[0, 0.0], [0.3, 1.0], [1, 0.0]],
			"color_ramp": [[0, "#9ff3ffff"], [0.5, "#8a5cffff"], [1, "#ff4fd800"]],
			"sprite": "sparkle", "blend": "add", "emissive": 5.0, "lowpoly_mesh": "prism", "local_coords": true}],
		"light": {"color": "#8a5cff", "energy": 2.5, "range": 8.0, "flicker": 0.1, "offset": [0, 1.9, 0]},
		"mesh_fx": ["portal"],
	},
	"heal": {
		"description": "Cura (brilhos verdes subindo) / healing", "category": "magic",
		"layers": [{
			"name": "heal", "amount": 30, "lifetime": 1.6, "shape": "disc", "radius": 0.8,
			"direction": [0, 1, 0], "spread": 5, "velocity": [0.8, 1.6], "gravity": [0, 0.5, 0],
			"scale": [0.1, 0.2], "scale_curve": [[0, 0.0], [0.2, 1.0], [1, 0.0]],
			"color_ramp": [[0, "#d8ffd0ff"], [0.5, "#5cff7aff"], [1, "#1aff5000"]],
			"sprite": "sparkle", "blend": "add", "emissive": 4.0, "lowpoly_mesh": "prism"}],
		"light": {"color": "#5cff7a", "energy": 1.2, "range": 4.0, "flicker": 0.1, "offset": [0, 0.8, 0]},
		"mesh_fx": ["magic_circle"],
	},
	"fireflies": {
		"description": "Vagalumes / fireflies", "category": "ambient",
		"layers": [{
			"name": "fireflies", "amount": 40, "lifetime": 7.0, "preprocess": 7.0, "shape": "box", "extents": [7.0, 1.2, 7.0], "offset": [0, 1.3, 0],
			"direction": [0, 1, 0], "spread": 180, "velocity": [0.05, 0.3], "gravity": [0, 0, 0],
			"scale": [0.05, 0.09], "turbulence": {"strength": 1.6, "scale": 0.6, "speed": 0.4},
			"color_ramp": [[0, "#e8ff7a00"], [0.1, "#e8ff7aff"], [0.25, "#b8ff5a22"], [0.4, "#e8ff7aff"], [0.6, "#c8ff6a33"], [0.75, "#e8ff7aff"], [1, "#e8ff7a00"]],
			"sprite": "soft_circle", "blend": "add", "emissive": 8.0, "lowpoly_mesh": "box"}],
	},
	"rain": {
		"description": "Chuva (segue a câmera) / rain (follows camera)", "category": "weather", "follow_camera": true,
		"layers": [{
			"name": "rain", "amount": 1600, "lifetime": 1.1, "preprocess": 1.1, "shape": "box", "extents": [18.0, 0.5, 18.0], "offset": [0, 12, 0],
			"direction": [0.05, -1, 0], "spread": 2, "velocity": [18.0, 22.0], "gravity": [0, -4, 0],
			"scale": [0.02, 0.03], "stretch": 22.0, "align": "velocity",
			"color_ramp": [[0, "#b8ccff55"], [1, "#b8ccff55"]], "sprite": "drop", "blend": "mix", "lowpoly_mesh": "box"}],
	},
	"snowfall": {
		"description": "Neve caindo (segue a câmera) / snowfall", "category": "weather", "follow_camera": true,
		"layers": [{
			"name": "snow", "amount": 1400, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": [18.0, 0.5, 18.0], "offset": [0, 10, 0],
			"direction": [0, -1, 0], "spread": 10, "velocity": [0.8, 1.6], "gravity": [0, -0.4, 0],
			"scale": [0.05, 0.11], "turbulence": {"strength": 0.8, "scale": 0.5, "speed": 0.3},
			"angle": [0, 360], "spin": [-60, 60],
			"color_ramp": [[0, "#ffffff00"], [0.05, "#ffffffee"], [0.9, "#ffffffee"], [1, "#ffffff00"]],
			"sprite": "snowflake", "blend": "mix", "lowpoly_mesh": "prism"}],
	},
	"dust": {
		"description": "Poeira no ar (segue a câmera) / dust motes", "category": "weather", "follow_camera": true,
		"layers": [{
			"name": "dust", "amount": 260, "lifetime": 8.0, "preprocess": 8.0, "shape": "box", "extents": [14.0, 5.0, 14.0], "offset": [0, 3, 0],
			"direction": [1, 0.1, 0], "spread": 30, "velocity": [0.3, 1.2], "gravity": [0, 0, 0],
			"scale": [0.03, 0.08], "turbulence": {"strength": 0.8, "scale": 0.4, "speed": 0.3},
			"color_ramp": [[0, "#d8c09a00"], [0.2, "#d8c09a88"], [0.8, "#d8c09a88"], [1, "#d8c09a00"]],
			"sprite": "soft_circle", "blend": "mix", "lowpoly_mesh": "box"}],
	},
	"leaves": {
		"description": "Folhas caindo / falling leaves", "category": "weather", "follow_camera": true,
		"layers": [{
			"name": "leaves", "amount": 70, "lifetime": 9.0, "preprocess": 9.0, "shape": "box", "extents": [14.0, 1.0, 14.0], "offset": [0, 9, 0],
			"direction": [0.3, -1, 0], "spread": 20, "velocity": [0.6, 1.4], "gravity": [0.2, -0.6, 0],
			"scale": [0.12, 0.2], "angle": [0, 360], "spin": [-120, 120], "turbulence": {"strength": 1.2, "scale": 0.4, "speed": 0.4},
			"hue_variation": [-0.08, 0.06],
			"color_ramp": [[0, "#e0782a00"], [0.05, "#e0782aff"], [0.9, "#c0521cff"], [1, "#c0521c00"]],
			"sprite": "leaf", "blend": "mix", "lit": true, "lowpoly_mesh": "quad"}],
	},
	"mist": {
		"description": "Névoa rasteira / ground mist", "category": "weather",
		"layers": [{
			"name": "mist", "amount": 36, "lifetime": 12.0, "preprocess": 12.0, "shape": "box", "extents": [14.0, 0.4, 14.0], "offset": [0, 0.8, 0],
			"direction": [1, 0, 0], "spread": 180, "velocity": [0.1, 0.4], "gravity": [0, 0, 0],
			"angle": [0, 360], "spin": [-5, 5], "scale": [6.0, 10.0],
			"color_ramp": [[0, "#e8eef400"], [0.3, "#e8eef430"], [0.7, "#e8eef430"], [1, "#e8eef400"]],
			"sprite": "smoke", "blend": "mix", "lit": true, "lowpoly_mesh": "sphere"}],
	},
	"fountain": {
		"description": "Fonte de água / fountain", "category": "water",
		"layers": [
			{"name": "jet", "amount": 160, "lifetime": 1.5, "shape": "disc", "radius": 0.08,
				"direction": [0, 1, 0], "spread": 7, "velocity": [6.0, 7.0], "gravity": [0, -9.8, 0],
				"scale": [0.04, 0.07], "stretch": 4.0, "align": "velocity",
				"color_ramp": [[0, "#dff4ffcc"], [1, "#9fd8ff44"]], "sprite": "drop", "blend": "mix", "lowpoly_mesh": "box"},
			{"name": "mist", "amount": 20, "lifetime": 1.5, "shape": "disc", "radius": 0.8,
				"direction": [0, 1, 0], "spread": 60, "velocity": [0.3, 0.8], "gravity": [0, 0.2, 0],
				"angle": [0, 360], "scale": [0.6, 1.0], "scale_curve": [[0, 0.3], [1, 1.5]],
				"color_ramp": [[0, "#ffffff00"], [0.3, "#ffffff44"], [1, "#ffffff00"]],
				"sprite": "smoke", "blend": "mix", "lit": true, "lowpoly_mesh": "sphere"},
		],
	},
	"waterfall": {
		"description": "Cachoeira (água caindo + névoa) / waterfall", "category": "water", "scale": 2.0,
		"layers": [
			{"name": "water", "amount": 500, "lifetime": 1.6, "shape": "box", "extents": [1.5, 0.05, 0.1], "offset": [0, 3.5, 0],
				"direction": [0, -0.2, 1], "spread": 4, "velocity": [1.5, 2.2], "gravity": [0, -9.8, 0],
				"scale": [0.08, 0.14], "stretch": 5.0, "align": "velocity",
				"color_ramp": [[0, "#e8f7ffdd"], [1, "#a8dcff88"]], "sprite": "drop", "blend": "mix", "lowpoly_mesh": "box"},
			{"name": "mist", "amount": 30, "lifetime": 2.2, "shape": "box", "extents": [1.8, 0.2, 0.6], "offset": [0, 0.3, 1.2],
				"direction": [0, 1, 0.3], "spread": 40, "velocity": [0.5, 1.5], "gravity": [0, 0.3, 0],
				"angle": [0, 360], "scale": [1.0, 1.6], "scale_curve": [[0, 0.4], [1, 2.0]],
				"color_ramp": [[0, "#ffffff00"], [0.2, "#ffffff66"], [1, "#ffffff00"]],
				"sprite": "smoke", "blend": "mix", "lit": true, "lowpoly_mesh": "sphere"},
		],
	},
	"bubbles": {
		"description": "Bolhas / bubbles", "category": "water",
		"layers": [{
			"name": "bubbles", "amount": 30, "lifetime": 3.0, "shape": "disc", "radius": 0.6,
			"direction": [0, 1, 0], "spread": 8, "velocity": [0.5, 1.2], "gravity": [0, 0.4, 0],
			"scale": [0.08, 0.18], "turbulence": {"strength": 0.6, "scale": 1.5, "speed": 1.0},
			"color_ramp": [[0, "#d8f4ff00"], [0.1, "#d8f4ffcc"], [0.9, "#d8f4ffaa"], [1, "#ffffff00"]],
			"sprite": "ring", "blend": "mix", "lowpoly_mesh": "sphere"}],
	},
	"lightning": {
		"description": "Raios (flashes periódicos) / lightning strikes", "category": "weather",
		"layers": [],
		"light": {"color": "#cfe0ff", "energy": 0.0, "range": 60.0},
		"mesh_fx": ["lightning"],
	},
	"shockwave": {
		"description": "Onda de choque (uma vez) / shockwave", "category": "impact", "one_shot": true, "duration": 1.2,
		"layers": [], "mesh_fx": ["shockwave"],
	},
	"force_field": {
		"description": "Campo de força / force field bubble", "category": "magic",
		"layers": [{
			"name": "motes", "amount": 20, "lifetime": 2.0, "shape": "sphere", "radius": 1.9, "offset": [0, 1.0, 0],
			"direction": [0, 1, 0], "spread": 180, "velocity": [0.05, 0.2],
			"scale": [0.05, 0.08], "color_ramp": [[0, "#7fe8ff00"], [0.5, "#7fe8ffff"], [1, "#7fe8ff00"]],
			"sprite": "soft_circle", "blend": "add", "emissive": 4.0, "lowpoly_mesh": "box"}],
		"mesh_fx": ["force_field"],
		"light": {"color": "#7fe8ff", "energy": 1.0, "range": 5.0, "offset": [0, 1.0, 0]},
	},
	"confetti": {
		"description": "Confete (uma vez) / confetti burst", "category": "impact", "one_shot": true, "duration": 4.0,
		"layers": [{
			"name": "confetti", "amount": 120, "lifetime": 3.5, "explosiveness": 0.95, "shape": "sphere", "radius": 0.2,
			"direction": [0, 1, 0], "spread": 50, "velocity": [5.0, 9.0], "gravity": [0, -5.0, 0], "damping": [1.5, 2.5],
			"scale": [0.06, 0.1], "angle": [0, 360], "spin": [-400, 400], "hue_variation": [-0.5, 0.5],
			"color_ramp": [[0, "#ff4f6aff"], [0.85, "#ff4f6aff"], [1, "#ff4f6a00"]],
			"sprite": "soft_circle", "blend": "mix", "lit": true, "lowpoly_mesh": "quad"}],
	},
}

const ALIASES := {
	"fogo": "fire", "chamas": "fire", "chama": "fire", "flames": "fire", "flame": "fire",
	"fogueira": "campfire", "bonfire": "campfire", "acampamento": "campfire",
	"tocha": "torch", "archote": "torch",
	"brasas": "embers", "brasa": "embers", "cinzas": "embers",
	"faiscas": "sparks", "faisca": "sparks", "fagulhas": "sparks",
	"fumaca": "smoke", "vapor": "steam", "geiser": "steam", "geyser": "steam",
	"explosao": "explosion", "bomba": "explosion", "boom": "explosion",
	"vulcao": "volcano_plume", "pluma": "volcano_plume", "volcano": "volcano_plume",
	"magia": "magic_aura", "magic": "magic_aura", "aura": "magic_aura", "feitico": "magic_aura",
	"vortice": "portal", "teleporte": "portal",
	"cura": "heal", "healing": "heal",
	"vagalumes": "fireflies", "vagalume": "fireflies", "pirilampos": "fireflies", "firefly": "fireflies",
	"chuva": "rain", "chovendo": "rain",
	"neve": "snowfall", "nevando": "snowfall", "snow": "snowfall", "nevasca": "snowfall",
	"poeira": "dust", "folhas": "leaves", "nevoa": "mist", "neblina": "mist", "fog": "mist",
	"fonte": "fountain", "chafariz": "fountain", "cachoeira": "waterfall", "cascata": "waterfall",
	"bolhas": "bubbles", "raio": "lightning", "raios": "lightning", "relampago": "lightning", "trovao": "lightning",
	"onda_de_choque": "shockwave", "impacto": "shockwave", "escudo": "force_field", "campo_de_forca": "force_field",
	"shield": "force_field", "confete": "confetti",
}

const CUSTOM_DIR := "res://vfx_presets"


static func normalize(text: String) -> String:
	var n := text.to_lower().strip_edges().replace(" ", "_").replace("-", "_")
	for k in {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}.keys():
		n = n.replace(k, {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}[k])
	return n


static func resolve(preset_name: String) -> String:
	var n := normalize(preset_name)
	if PRESETS.has(n) or _custom_path(n) != "":
		return n
	return ALIASES.get(n, "")


static func _custom_path(n: String) -> String:
	var p := CUSTOM_DIR.path_join(n + ".json")
	return p if FileAccess.file_exists(p) else ""


## Returns the preset definition (built-in or custom JSON), or {} if unknown.
static func get_preset(preset_name: String) -> Dictionary:
	var key := resolve(preset_name)
	if key == "":
		return {}
	var custom := _custom_path(key)
	if custom != "":
		var f := FileAccess.open(custom, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				return parsed
	return PRESETS.get(key, {}).duplicate(true)


static func names() -> Array:
	var out: Array = PRESETS.keys()
	var dir := DirAccess.open(CUSTOM_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				var n := f.get_basename()
				if not out.has(n):
					out.append(n)
	return out


static func save_custom(preset_name: String, definition: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CUSTOM_DIR))
	var path := CUSTOM_DIR.path_join(normalize(preset_name) + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(definition, "  "))
	f.close()
	return path
