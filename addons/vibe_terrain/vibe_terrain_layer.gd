@tool
@icon("res://addons/vibe_terrain/icons/terrain_layer.svg")
class_name VibeTerrainLayer
extends Resource
## One of the 4 paintable surface layers of a [VibeTerrain3D].
##
## Works without any texture: the shader draws a procedural surface that
## blends [member color_a] and [member color_b] with noise. Assign
## [member albedo_texture] (and optionally [member normal_texture]) to use
## real textures instead.

@export var name := "Layer":
	set(v):
		name = v
		emit_changed()
@export var color_a := Color(0.3, 0.45, 0.2):
	set(v):
		color_a = v
		emit_changed()
@export var color_b := Color(0.4, 0.55, 0.25):
	set(v):
		color_b = v
		emit_changed()
## Size of the color variation patches (smaller = bigger patches).
@export_range(0.01, 4.0, 0.01) var noise_scale := 0.35:
	set(v):
		noise_scale = v
		emit_changed()
## Horizontal banding (sedimentary rock look).
@export_range(0.0, 1.0, 0.01) var strata := 0.0:
	set(v):
		strata = v
		emit_changed()
@export_range(0.0, 1.0, 0.01) var roughness := 0.9:
	set(v):
		roughness = v
		emit_changed()
## Glow (lava, crystals). 0 = no emission.
@export_range(0.0, 16.0, 0.01) var emission := 0.0:
	set(v):
		emission = v
		emit_changed()
## Built-in PBR texture set used by the "realistic" style (grass_ground, rock,
## sandstone, sand, snow, dirt, gravel, mud, ash, lava, ice, moss, crystal, regolith).
@export var texture_set := "":
	set(v):
		texture_set = v
		emit_changed()
## Multiplies the texture color (realistic style).
@export var tint := Color(1, 1, 1):
	set(v):
		tint = v
		emit_changed()
## Custom albedo (RGB) + height (A) texture. Overrides [member texture_set].
@export var albedo_texture: Texture2D:
	set(v):
		albedo_texture = v
		emit_changed()
## Custom normal (RGB, OpenGL) + roughness (A) texture.
@export var normal_texture: Texture2D:
	set(v):
		normal_texture = v
		emit_changed()
## Meters covered by one texture tile.
@export_range(0.1, 100.0, 0.1) var uv_scale := 4.0:
	set(v):
		uv_scale = v
		emit_changed()


func to_dict() -> Dictionary:
	return {
		"name": name, "color_a": "#" + color_a.to_html(false), "color_b": "#" + color_b.to_html(false),
		"noise_scale": noise_scale, "strata": strata, "roughness": roughness, "emission": emission,
		"texture_set": texture_set, "tint": "#" + tint.to_html(false),
		"albedo_texture": albedo_texture.resource_path if albedo_texture else "",
		"normal_texture": normal_texture.resource_path if normal_texture else "",
		"uv_scale": uv_scale,
	}


const TEXTURE_DIR := "res://addons/vibe_terrain/textures"
const TEXTURE_SETS := ["grass_ground", "rock", "sandstone", "sand", "snow", "dirt", "gravel", "mud", "ash", "lava", "ice", "moss", "crystal", "regolith"]


## Albedo+height texture to use in the realistic style (custom or built-in set), or null.
func resolve_albedo() -> Texture2D:
	if albedo_texture != null:
		return albedo_texture
	return _load_set("albedo_height")


func resolve_normal() -> Texture2D:
	if normal_texture != null:
		return normal_texture
	if albedo_texture != null:
		return null
	return _load_set("normal_rough")


func _load_set(kind: String) -> Texture2D:
	if texture_set == "":
		return null
	var path := TEXTURE_DIR.path_join("%s_%s.webp" % [texture_set, kind])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
