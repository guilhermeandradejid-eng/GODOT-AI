@tool
@icon("res://addons/vibe_terrain/icons/terrain.svg")
class_name VibeTerrain3D
extends Node3D
## Heightmap terrain with GPU displacement, 4 paintable surface layers,
## collision, water (sea, lakes and rivers) and editor brushes.
##
## The terrain is centered on this node: it spans [-size/2, size/2] on X and Z.
## Heights live in [member data] ([VibeTerrainData]); the look comes from the
## 4 [VibeTerrainLayer] resources (procedural or textured).

signal heights_changed(rect: Rect2i)
signal splat_changed(rect: Rect2i)

const DataScript = preload("res://addons/vibe_terrain/vibe_terrain_data.gd")
const LayerScript = preload("res://addons/vibe_terrain/vibe_terrain_layer.gd")
const Palettes = preload("res://addons/vibe_terrain/terrain_palettes.gd")
const TERRAIN_SHADERS := {
	"realistic": preload("res://addons/vibe_terrain/shaders/terrain_realistic.gdshader"),
	"stylized": preload("res://addons/vibe_terrain/shaders/terrain_stylized.gdshader"),
	"toon": preload("res://addons/vibe_terrain/shaders/terrain_toon.gdshader"),
	"cel": preload("res://addons/vibe_terrain/shaders/terrain_toon.gdshader"),
	"lowpoly": preload("res://addons/vibe_terrain/shaders/terrain_lowpoly.gdshader"),
}
const WATER_SHADERS := {
	"realistic": preload("res://addons/vibe_terrain/shaders/vibe_water.gdshader"),
	"stylized": preload("res://addons/vibe_terrain/shaders/water_toon.gdshader"),
	"toon": preload("res://addons/vibe_terrain/shaders/water_toon.gdshader"),
	"cel": preload("res://addons/vibe_terrain/shaders/water_toon.gdshader"),
	"lowpoly": preload("res://addons/vibe_terrain/shaders/water_lowpoly.gdshader"),
}
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const WATER_NORMAL_PATH := "res://addons/vibe_terrain/textures/water_normal.png"

const GROUP := &"vibe_terrain"
const LOD_STEPS := [2, 4, 8]
## Converts a switch distance (m) into ArrayMesh LOD keys (see mesh_surface_get_lod).
const LOD_KEY_PER_METER := 0.0012

@export var data: DataScript:
	set(value):
		if data == value:
			return
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = value
		if data != null:
			data.changed.connect(_on_data_changed)
		_queue_rebuild()

@export_group("Mesh")
## Quads per chunk side (chunks are culled and LOD'ed individually).
@export_range(8, 128, 8) var chunk_size := 32:
	set(value):
		chunk_size = clampi(value, 8, 128)
		_queue_rebuild()
@export var lod_enabled := true:
	set(value):
		lod_enabled = value
		_queue_rebuild()
## Distance at which chunks start using half resolution (doubles for each LOD).
@export_range(5.0, 5000.0, 1.0, "suffix:m") var lod_distance := 90.0:
	set(value):
		lod_distance = value
		_queue_rebuild()
## Extends the terrain border to the horizon (only when there is no sea).
@export var horizon_enabled := true:
	set(value):
		horizon_enabled = value
		_queue_rebuild()
## How far the horizon ring goes, in terrain half-sizes.
@export_range(2.0, 64.0, 0.5) var horizon_extent := 12.0:
	set(value):
		horizon_extent = value
		_queue_rebuild()
@export var cast_shadows := true:
	set(value):
		cast_shadows = value
		_apply_shadow_setting()

@export_group("Collision")
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_queue_rebuild()
@export_flags_3d_physics var collision_layer := 1:
	set(value):
		collision_layer = value
		if _body != null:
			_body.collision_layer = value
@export_flags_3d_physics var collision_mask := 1:
	set(value):
		collision_mask = value
		if _body != null:
			_body.collision_mask = value

@export_group("Surface")
## Art style: realistic (PBR textures), stylized (painterly), toon, cel, lowpoly (faceted).
@export_enum("realistic", "stylized", "toon", "cel", "lowpoly") var style := "realistic":
	set(value):
		style = value if STYLES.has(value) else "realistic"
		_queue_rebuild()
## Low poly style: vertex spacing of the faceted mesh (in terrain cells).
@export_enum("1:1", "2:2", "4:4", "8:8") var lowpoly_step := 4:
	set(value):
		lowpoly_step = value
		if style == "lowpoly":
			_queue_rebuild()
## Biome palette (temperate, tropical, snowy, desert, canyon, volcanic, autumn,
## alien, lunar, swamp, savanna). Changing it in the inspector re-colors the layers.
@export var palette := "temperate":
	set(value):
		palette = value
		if is_node_ready() and not _applying_palette:
			apply_palette(value)
@export var layer_0: LayerScript:
	set(value):
		_swap_layer(layer_0, value)
		layer_0 = value
		_update_material()
@export var layer_1: LayerScript:
	set(value):
		_swap_layer(layer_1, value)
		layer_1 = value
		_update_material()
@export var layer_2: LayerScript:
	set(value):
		_swap_layer(layer_2, value)
		layer_2 = value
		_update_material()
@export var layer_3: LayerScript:
	set(value):
		_swap_layer(layer_3, value)
		layer_3 = value
		_update_material()
@export_range(0.5, 6.0, 0.1) var blend_sharpness := 1.6:
	set(value):
		blend_sharpness = value
		_update_material()
## Optional: your own ShaderMaterial (use the uniforms of shaders/terrain_common.gdshaderinc).
@export var custom_material: ShaderMaterial:
	set(value):
		custom_material = value
		_queue_rebuild()

@export_group("Water")
@export var water_enabled := false:
	set(value):
		water_enabled = value
		_queue_water()
@export var water_level := 0.0:
	set(value):
		water_level = value
		_queue_water()
@export var water_deep_color := Color(0.02, 0.16, 0.26, 0.94):
	set(value):
		water_deep_color = value
		_update_water_material()
@export var water_shallow_color := Color(0.1, 0.52, 0.55, 0.55):
	set(value):
		water_shallow_color = value
		_update_water_material()
## Rivers: [{"points": PackedVector2Array (local xz), "levels": PackedFloat32Array, "width": float}]
@export_storage var rivers: Array = []
## Lakes: [{"center": Vector2 (local xz), "radius": float, "level": float}]
@export_storage var lakes: Array = []

var _material: ShaderMaterial
var _water_material: ShaderMaterial
var _lake_material: ShaderMaterial
var _river_material: ShaderMaterial
var _height_tex: ImageTexture
var _splat_tex: ImageTexture
var _chunk_root: Node3D
var _water_root: Node3D
var _chunks: Array = []
var _chunk_rects: Array = []
var _body: StaticBody3D
var _shape_node: CollisionShape3D
var _rebuild_queued := false
var _water_queued := false
var _built_resolution := -1
var _applying_palette := false
var _grass_overlays: Array = []


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if data == null:
		var d := DataScript.new()
		d.setup(257, 1.0)
		data = d
	if layer_0 == null or layer_1 == null or layer_2 == null or layer_3 == null:
		apply_palette(palette)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_externalize_data()


## Editor: keeps the (large) terrain data in its own binary .res file instead
## of embedding it in the .tscn, and saves pending edits.
func _externalize_data() -> void:
	if data == null:
		return
	var path := data.resource_path
	if path == "" or path.contains("::"):
		var root := get_tree().edited_scene_root if is_inside_tree() else null
		var dir := "res://vibe_data/untitled"
		if root != null and root.scene_file_path != "":
			# Next to the scene: res://levels/ilha.tscn -> res://levels/ilha_data/
			var file := root.scene_file_path
			dir = file.get_base_dir().path_join(file.get_file().get_basename().to_lower().replace(" ", "_") + "_data")
		elif root != null:
			dir = "res://vibe_data/" + str(root.name).to_lower().replace(" ", "_")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		path = dir.path_join("%s_terrain.res" % Palettes.normalize(str(name)).replace(" ", "_"))
		var n := 2
		while FileAccess.file_exists(path):
			path = dir.path_join("%s_terrain_%d.res" % [Palettes.normalize(str(name)).replace(" ", "_"), n])
			n += 1
		data.take_over_path(path)
	ResourceSaver.save(data, path)


# --- Public API -------------------------------------------------------------------------

func get_size() -> float:
	return data.get_size() if data != null else 0.0


## Terrain size in world units (accounts for node scale).
func get_world_size() -> float:
	var s := global_transform.basis.get_scale().x if is_inside_tree() else scale.x
	return get_size() * s


## Min/max height in local units.
func get_height_range() -> Vector2:
	return data.height_range() if data != null else Vector2.ZERO


func local_to_texel(local: Vector3) -> Vector2:
	var half := get_size() * 0.5
	return Vector2(local.x + half, local.z + half) / data.cell_size


func texel_to_local(t: Vector2) -> Vector3:
	var half := get_size() * 0.5
	return Vector3(t.x * data.cell_size - half, data.sample(t.x, t.y), t.y * data.cell_size - half)


func _to_local_safe(world: Vector3) -> Vector3:
	return to_local(world) if is_inside_tree() else transform.affine_inverse() * world


func _to_global_safe(local: Vector3) -> Vector3:
	return to_global(local) if is_inside_tree() else transform * local


func world_to_texel(world: Vector3) -> Vector2:
	return local_to_texel(_to_local_safe(world))


func texel_to_world(t: Vector2) -> Vector3:
	return _to_global_safe(texel_to_local(t))


func get_height_at_world(world: Vector3) -> float:
	if data == null:
		return global_position.y
	var local := _to_local_safe(world)
	var t := local_to_texel(local)
	return _to_global_safe(Vector3(local.x, data.sample(t.x, t.y), local.z)).y


func get_normal_at_world(world: Vector3) -> Vector3:
	var t := world_to_texel(world)
	var n: Vector3 = data.sample_normal(t.x, t.y)
	return (global_transform.basis * n).normalized() if is_inside_tree() else n


func get_slope_at_world(world: Vector3) -> float:
	var n := get_normal_at_world(world)
	return rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0)))


func is_inside_terrain(world: Vector3) -> bool:
	var t := world_to_texel(world)
	return t.x >= 0.0 and t.y >= 0.0 and t.x <= data.resolution - 1 and t.y <= data.resolution - 1


## Ray against the heightmap (does not need collision). Returns a world position or null.
func raycast(from: Vector3, dir: Vector3, max_distance: float = 10000.0) -> Variant:
	if data == null or dir.length_squared() < 0.000001:
		return null
	var inv := global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()
	var o: Vector3 = inv * from
	var d: Vector3 = (inv.basis * dir).normalized()
	var half := get_size() * 0.5
	var r := data.height_range()
	# Clip the ray to the terrain bounding box.
	var box := AABB(Vector3(-half, r.x - 1.0, -half), Vector3(half * 2.0, r.y - r.x + 2.0, half * 2.0))
	var t0 := 0.0
	var t1 := max_distance
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if o[axis] < box.position[axis] or o[axis] > box.end[axis]:
				return null
			continue
		var ta := (box.position[axis] - o[axis]) / d[axis]
		var tb := (box.end[axis] - o[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return null
	var step := maxf(data.cell_size * 0.5, 0.05)
	var t := t0
	var prev_t := t0
	var prev_above := true
	while t <= t1:
		var p := o + d * t
		var tx := local_to_texel(p)
		var above := p.y > data.sample(tx.x, tx.y)
		if not above:
			if t == t0 and not prev_above:
				return null
			# Refine with bisection.
			var lo := prev_t
			var hi := t
			for _i in 12:
				var mid := (lo + hi) * 0.5
				var pm := o + d * mid
				var tm := local_to_texel(pm)
				if pm.y > data.sample(tm.x, tm.y):
					lo = mid
				else:
					hi = mid
			var hit := o + d * hi
			return global_transform * hit if is_inside_tree() else transform * hit
		prev_above = above
		prev_t = t
		t += step
	return null


## Named positions: center, north/south/east/west (+ne/nw/se/sw), peak, valley,
## flat, beach, water, random. Returns a world position or null.
func find_anchor(anchor: String, seed_value: int = 0) -> Variant:
	if data == null:
		return null
	var a := Palettes.normalize(anchor)
	var half := get_size() * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a) + seed_value * 7919
	var off := half * 0.55
	var dirs := {
		"center": Vector2.ZERO, "centro": Vector2.ZERO, "middle": Vector2.ZERO, "meio": Vector2.ZERO, "origin": Vector2.ZERO,
		"north": Vector2(0, -off), "norte": Vector2(0, -off), "south": Vector2(0, off), "sul": Vector2(0, off),
		"east": Vector2(off, 0), "leste": Vector2(off, 0), "west": Vector2(-off, 0), "oeste": Vector2(-off, 0),
		"northeast": Vector2(off, -off) * 0.75, "nordeste": Vector2(off, -off) * 0.75,
		"northwest": Vector2(-off, -off) * 0.75, "noroeste": Vector2(-off, -off) * 0.75,
		"southeast": Vector2(off, off) * 0.75, "sudeste": Vector2(off, off) * 0.75,
		"southwest": Vector2(-off, off) * 0.75, "sudoeste": Vector2(-off, off) * 0.75,
	}
	var land_min := water_level + 0.4 if (water_enabled or not lakes.is_empty()) else -INF
	var local := Vector2.ZERO
	if dirs.has(a):
		local = dirs[a]
		if seed_value > 0:
			local += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * half * 0.08
		return _surface_point(local)
	match a:
		"peak", "topo", "pico", "highest", "summit", "cume", "top":
			var best := Vector2.ZERO
			var best_h := -INF
			var res: int = data.resolution
			var m := int(res * 0.05)
			for z in range(m, res - m):
				for x in range(m, res - m):
					var hh: float = data.heights[z * res + x]
					if hh > best_h:
						best_h = hh
						best = Vector2(x, z)
			if seed_value > 0:
				best += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * res * 0.02
			var lp := texel_to_local(best)
			return _surface_point(Vector2(lp.x, lp.z))
		"valley", "vale", "lowest", "low", "baixada":
			return _pick(rng, 500, func(p: Vector2, h: float, s: float) -> float:
				return -h - s * 0.2 if h > land_min else -INF)
		"flat", "plano", "plana", "camp", "clearing", "clareira":
			return _pick(rng, 400, func(p: Vector2, h: float, s: float) -> float:
				if h <= land_min:
					return -INF
				return -s * 3.0 - p.length() / half * 6.0 + rng.randf() * 4.0)
		"beach", "praia", "shore", "costa", "margem", "coast":
			var wl := water_level
			return _pick(rng, 800, func(p: Vector2, h: float, s: float) -> float:
				if h <= wl + 0.3 or h > wl + 3.5:
					return -INF
				return -s + rng.randf() * 10.0)
		"water", "agua", "sea", "mar", "lake", "lago":
			var wl2 := water_level
			return _pick(rng, 500, func(p: Vector2, h: float, s: float) -> float:
				return rng.randf() if h < wl2 - 0.5 else -INF, true)
		"random", "aleatorio", "anywhere", "qualquer":
			return _pick(rng, 60, func(p: Vector2, h: float, s: float) -> float:
				return rng.randf() - (0.0 if h > land_min else 10.0))
	return null


func _pick(rng: RandomNumberGenerator, samples: int, score: Callable, on_water: bool = false) -> Variant:
	var half := get_size() * 0.5
	var best = null
	var best_score := -INF
	for _i in samples:
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)) * 0.85
		var t := local_to_texel(Vector3(p.x, 0, p.y))
		var h: float = data.sample(t.x, t.y)
		var n: Vector3 = data.sample_normal(t.x, t.y)
		var slope := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
		var sc: float = score.call(p, h, slope)
		if sc > best_score:
			best_score = sc
			best = p
	if best == null or best_score == -INF:
		best = Vector2.ZERO
	if on_water:
		return _to_global_safe(Vector3(best.x, water_level, best.y))
	return _surface_point(best)


func _surface_point(local_xz: Vector2) -> Vector3:
	var t := local_to_texel(Vector3(local_xz.x, 0, local_xz.y))
	return _to_global_safe(Vector3(local_xz.x, data.sample(t.x, t.y), local_xz.y))


func get_heightmap_texture() -> Texture2D:
	_ensure_textures()
	return _height_tex


func get_splat_texture() -> Texture2D:
	_ensure_textures()
	return _splat_tex


func get_layers() -> Array:
	return [layer_0, layer_1, layer_2, layer_3]


func get_layer(index: int) -> LayerScript:
	return get_layers()[clampi(index, 0, 3)]


func set_layer(index: int, layer: LayerScript) -> void:
	match clampi(index, 0, 3):
		0:
			layer_0 = layer
		1:
			layer_1 = layer
		2:
			layer_2 = layer
		3:
			layer_3 = layer


## Replaces the 4 layers with the given biome palette. Returns false if unknown.
func apply_palette(palette_name: String) -> bool:
	var key := Palettes.resolve(palette_name)
	if key == "":
		return false
	var pal: Dictionary = Palettes.PALETTES[key]
	for i in 4:
		var def: Dictionary = pal.layers[i]
		var layer := LayerScript.new()
		layer.name = def.get("name", "Layer %d" % i)
		layer.color_a = Color.html(def.get("color_a", "#808080"))
		layer.color_b = Color.html(def.get("color_b", "#a0a0a0"))
		layer.noise_scale = def.get("noise_scale", 0.3)
		layer.strata = def.get("strata", 0.0)
		layer.roughness = def.get("roughness", 0.9)
		layer.emission = def.get("emission", 0.0)
		var tex: Array = Palettes.TEXTURES.get(key, [])
		if i < tex.size():
			layer.texture_set = str(tex[i][0])
			layer.tint = Color.html(str(tex[i][1]))
			layer.uv_scale = float(tex[i][2])
		set_layer(i, layer)
	_applying_palette = true
	palette = key
	_applying_palette = false
	return true


func get_palette_rules() -> Dictionary:
	var pal := Palettes.get_palette(palette)
	return pal.get("rules", {}).duplicate()


func get_info() -> Dictionary:
	var info := {"name": str(name), "type": "VibeTerrain3D"}
	if data == null:
		return info
	var r := data.height_range()
	info.merge({
		"size": get_size(),
		"resolution": data.resolution,
		"cell_size": data.cell_size,
		"height_min": snappedf(r.x, 0.01),
		"height_max": snappedf(r.y, 0.01),
		"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)] if is_inside_tree() else [0, 0, 0],
		"palette": palette,
		"layers": get_layers().map(func(l): return l.name if l != null else ""),
		"water": {"enabled": water_enabled, "level": water_level, "rivers": rivers.size(), "lakes": lakes.size()},
		"collision": collision_enabled,
		"data_file": data.resource_path,
	})
	return info


# --- Editing notifications ---------------------------------------------------------------

## Call after changing data.heights (rect = changed texel area, empty = all).
func notify_heights_changed(rect: Rect2i = Rect2i(), update_collision: bool = true) -> void:
	if data == null:
		return
	if _height_tex == null or _built_resolution != data.resolution:
		_rebuild()
		heights_changed.emit(rect)
		return
	_height_tex.update(data.height_image())
	_update_chunk_aabbs(rect)
	if update_collision:
		_update_collision()
	heights_changed.emit(rect)


func notify_splat_changed(rect: Rect2i = Rect2i()) -> void:
	if data == null:
		return
	if _splat_tex == null or _built_resolution != data.resolution:
		_rebuild()
	else:
		_splat_tex.update(data.splat_image())
	splat_changed.emit(rect)


func update_collision_now() -> void:
	_update_collision()


## Snapshot of everything commands/brushes can change (used for undo/redo).
func make_snapshot() -> Dictionary:
	return {
		"data": data.snapshot(),
		"rivers": rivers.duplicate(true),
		"lakes": lakes.duplicate(true),
		"water_enabled": water_enabled,
		"water_level": water_level,
	}


func apply_snapshot(snap: Dictionary) -> void:
	if snap.has("data"):
		data.restore(snap.data)
	elif snap.has("heights"):
		data.restore(snap)
	if snap.has("rivers"):
		rivers = snap.rivers.duplicate(true)
		lakes = snap.lakes.duplicate(true)
		water_enabled = snap.water_enabled
		water_level = snap.water_level
	_rebuild()
	heights_changed.emit(Rect2i())
	splat_changed.emit(Rect2i())


## Saves the external terrain data file (called when the scene is saved).
func save_external_data() -> Array:
	if data == null or data.resource_path == "" or data.resource_path.contains("::"):
		return []
	var err := ResourceSaver.save(data, data.resource_path)
	return [data.resource_path] if err == OK else []


func add_river(points_local: PackedVector2Array, levels: PackedFloat32Array, width: float) -> void:
	rivers.append({"points": points_local, "levels": levels, "width": width})
	_queue_water()


func add_lake(center_local: Vector2, radius: float, level: float) -> void:
	lakes.append({"center": center_local, "radius": radius, "level": level})
	_queue_water()


func clear_water_features() -> void:
	rivers = []
	lakes = []
	_queue_water()


## Shows the circular brush cursor (local position) on the terrain surface.
## Ground tint painted by grass layers (called by VibeGrass3D). Up to 3 grass
## layers tint the terrain, so grassy areas keep their color far away where the
## blades are no longer drawn. Colors: rgb + strength in alpha.
func set_grass_overlay(owner_id: int, density: Texture2D, near_color: Color, far_color: Color, view_distance: float) -> void:
	var entry := {"id": owner_id, "tex": density, "near": near_color, "far": far_color, "range": view_distance}
	for o in _grass_overlays:
		if o.id == owner_id:
			o.merge(entry, true)
			_apply_grass_overlays()
			return
	_grass_overlays.append(entry)
	_apply_grass_overlays()


func remove_grass_overlay(owner_id: int) -> void:
	for i in range(_grass_overlays.size() - 1, -1, -1):
		if _grass_overlays[i].id == owner_id:
			_grass_overlays.remove_at(i)
	_apply_grass_overlays()


func _apply_grass_overlays() -> void:
	var mat := _active_material()
	if mat == null:
		return
	for i in 3:
		var o: Dictionary = _grass_overlays[i] if i < _grass_overlays.size() else {}
		mat.set_shader_parameter("grass_map_%d" % i, o.get("tex", null))
		mat.set_shader_parameter("grass_near_%d" % i, o.get("near", Color(0, 0, 0, 0)))
		mat.set_shader_parameter("grass_far_%d" % i, o.get("far", Color(0, 0, 0, 0)))
		mat.set_shader_parameter("grass_range_%d" % i, float(o.get("range", 70.0)))


func show_brush(local_pos: Vector3, radius: float, color: Color = Color(1.0, 0.75, 0.2)) -> void:
	var mat := _active_material()
	if mat == null:
		return
	mat.set_shader_parameter("brush_position", local_pos)
	mat.set_shader_parameter("brush_radius", radius)
	mat.set_shader_parameter("brush_color", color)


func hide_brush() -> void:
	var mat := _active_material()
	if mat != null:
		mat.set_shader_parameter("brush_radius", 0.0)


# --- Building ------------------------------------------------------------------------------

func _on_data_changed() -> void:
	if not is_inside_tree():
		_queue_rebuild()
		return
	if _built_resolution != data.resolution or _height_tex == null:
		_queue_rebuild()
	else:
		notify_heights_changed()
		notify_splat_changed()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	if _rebuild_queued:
		_rebuild()


func _queue_water() -> void:
	if _water_queued or not is_inside_tree():
		return
	_water_queued = true
	_build_water.call_deferred()


func _swap_layer(old: Resource, new: Resource) -> void:
	if old != null and old.changed.is_connected(_update_material):
		old.changed.disconnect(_update_material)
	if new != null and not new.changed.is_connected(_update_material):
		new.changed.connect(_update_material)


func _active_material() -> ShaderMaterial:
	return custom_material if custom_material != null else _material


func _ensure_textures() -> void:
	if data == null or not data.is_valid():
		return
	if _height_tex == null or _built_resolution != data.resolution:
		_height_tex = ImageTexture.create_from_image(data.height_image())
		_splat_tex = ImageTexture.create_from_image(data.splat_image())
		_built_resolution = data.resolution


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree() or data == null:
		return
	if not data.is_valid():
		push_warning("VibeTerrain3D '%s': invalid terrain data (resolution %d)" % [name, data.resolution])
		return
	_built_resolution = -1
	_ensure_textures()
	if _material == null:
		_material = ShaderMaterial.new()
	_material.shader = TERRAIN_SHADERS.get(style, TERRAIN_SHADERS.realistic)
	_update_material()
	_build_chunks()
	_update_collision()
	_build_water()


func _update_material() -> void:
	var mat := _active_material()
	if mat == null or data == null:
		return
	_ensure_textures()
	mat.set_shader_parameter("heightmap", _height_tex)
	mat.set_shader_parameter("splatmap", _splat_tex)
	mat.set_shader_parameter("cell_size", data.cell_size)
	mat.set_shader_parameter("terrain_half_size", get_size() * 0.5)
	mat.set_shader_parameter("skirt_depth", maxf(2.0, data.cell_size * 4.0))
	mat.set_shader_parameter("blend_sharpness", blend_sharpness)
	mat.set_shader_parameter("vertex_jitter", data.cell_size * lowpoly_step * 0.4 if style == "lowpoly" else 0.0)
	match style:
		"cel":
			mat.set_shader_parameter("bands", 2.0)
			mat.set_shader_parameter("band_softness", 0.01)
			mat.set_shader_parameter("rim_strength", 0.3)
			mat.set_shader_parameter("patch_contrast", 0.7)
		"toon":
			mat.set_shader_parameter("bands", 3.0)
			mat.set_shader_parameter("band_softness", 0.05)
			mat.set_shader_parameter("rim_strength", 0.2)
			mat.set_shader_parameter("patch_contrast", 0.55)
	var textured := style == "realistic"
	var layers := get_layers()
	for i in 4:
		var l: LayerScript = layers[i]
		if l == null:
			continue
		var p := "layer%d_" % i
		mat.set_shader_parameter(p + "color_a", l.color_a)
		mat.set_shader_parameter(p + "color_b", l.color_b)
		mat.set_shader_parameter(p + "noise_scale", l.noise_scale)
		mat.set_shader_parameter(p + "strata", l.strata)
		mat.set_shader_parameter(p + "roughness", l.roughness)
		mat.set_shader_parameter(p + "emission", l.emission)
		mat.set_shader_parameter(p + "tint", l.tint)
		var alb: Texture2D = l.resolve_albedo() if textured else null
		var nrm: Texture2D = l.resolve_normal() if textured and alb != null else null
		mat.set_shader_parameter(p + "use_albedo", alb != null)
		mat.set_shader_parameter(p + "albedo", alb)
		mat.set_shader_parameter(p + "use_normal", nrm != null)
		mat.set_shader_parameter(p + "normal", nrm)
		mat.set_shader_parameter(p + "uv_scale", l.uv_scale)
	_apply_grass_overlays()


func _clear_children(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children(true):
		root.remove_child(c)
		c.queue_free()


func _build_chunks() -> void:
	if _chunk_root == null:
		_chunk_root = Node3D.new()
		_chunk_root.name = "Chunks"
		add_child(_chunk_root, false, Node.INTERNAL_MODE_BACK)
	_clear_children(_chunk_root)
	_chunks.clear()
	_chunk_rects.clear()
	var quads: int = data.resolution - 1
	var cs := mini(chunk_size, quads)
	var mat := _active_material()
	for cz in range(0, quads, cs):
		for cx in range(0, quads, cs):
			var qw := mini(cs, quads - cx)
			var qh := mini(cs, quads - cz)
			var mi := MeshInstance3D.new()
			mi.mesh = _build_chunk_mesh(cx, cz, qw, qh)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_chunk_root.add_child(mi, false, Node.INTERNAL_MODE_BACK)
			_chunks.append(mi)
			_chunk_rects.append(Rect2i(cx, cz, qw, qh))
	_update_chunk_aabbs(Rect2i())
	if horizon_enabled and not water_enabled:
		var ring := MeshInstance3D.new()
		ring.name = "Horizon"
		ring.mesh = _build_horizon_mesh()
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk_root.add_child(ring, false, Node.INTERNAL_MODE_BACK)
	_built_resolution = data.resolution


## Ring of coarse geometry around the terrain: concentric square loops whose
## inner loop matches the terrain border. Points outside the heightmap sample
## the border texels in the shader, so the ground continues seamlessly, then
## rises into distant hills that frame the scene and fade into the fog.
## (VERTEX.y of ring vertices = extra hill height, see terrain_common.)
func _build_horizon_mesh() -> ArrayMesh:
	var half := get_size() * 0.5
	var far := maxf(half * horizon_extent, half + 200.0)
	var r := data.height_range()
	var relief := maxf(r.y - r.x, 12.0)
	var noise := FastNoiseLite.new()
	noise.seed = int(hash(str(name))) % 10000 + 17
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 4
	noise.frequency = 1.0 / maxf(half * 1.1, 60.0)
	var hills := func(x: float, z: float) -> float:
		var o := maxf(absf(x), absf(z)) - half
		var ramp := smoothstep(half * 0.35, half * 2.4, o)
		var amp := relief * (0.55 + 0.9 * smoothstep(half * 2.0, far * 0.6, o))
		var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
		return ramp * amp * (0.25 + 0.75 * n * n)
	var outs: Array = [0.0]
	var o := maxf(half * 0.05, data.cell_size * 4.0)
	while half + o < far:
		outs.append(o)
		o *= 1.32
	outs.append(far - half)
	var per_side := 48
	var loop_len := per_side * 4
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var top := r.y
	for k in outs.size():
		var e: float = half + float(outs[k])
		for i in loop_len:
			var side := floori(float(i) / float(per_side))
			var t := float(i % per_side) / float(per_side) * 2.0 - 1.0
			var x := 0.0
			var z := 0.0
			match side:
				0:
					x = t * e
					z = -e
				1:
					x = e
					z = t * e
				2:
					x = -t * e
					z = e
				_:
					x = -e
					z = -t * e
			var y: float = 0.0 if k == 0 else hills.call(x, z)
			top = maxf(top, r.y + y)
			var step := maxf(e * 0.02, 2.0)
			var dx: float = hills.call(x + step, z) - hills.call(x - step, z)
			var dz: float = hills.call(x, z + step) - hills.call(x, z - step)
			verts.append(Vector3(x, y, z))
			normals.append(Vector3(-dx, 2.0 * step, -dz).normalized() if k > 0 else Vector3.UP)
	var idx := PackedInt32Array()
	for k in outs.size() - 1:
		var a0 := k * loop_len
		var b0 := (k + 1) * loop_len
		for i in loop_len:
			var j := (i + 1) % loop_len
			# Clockwise seen from above (Godot front faces).
			idx.append_array([b0 + i, b0 + j, a0 + j, b0 + i, a0 + j, a0 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-far, r.x - 5.0, -far), Vector3(far * 2.0, top - r.x + 10.0, far * 2.0))
	return mesh


func _build_chunk_mesh(x0: int, z0: int, qw: int, qh: int) -> ArrayMesh:
	var cell: float = data.cell_size
	var half := get_size() * 0.5
	var vw := qw + 1
	var verts := PackedVector3Array()
	for z in qh + 1:
		for x in vw:
			verts.append(Vector3((x0 + x) * cell - half, 0.0, (z0 + z) * cell - half))
	# Skirt vertices (y = -1 marks "push down" in the shader) along the 4 edges.
	var north := verts.size()
	for x in vw:
		verts.append(Vector3((x0 + x) * cell - half, -1.0, z0 * cell - half))
	var south := verts.size()
	for x in vw:
		verts.append(Vector3((x0 + x) * cell - half, -1.0, (z0 + qh) * cell - half))
	var west := verts.size()
	for z in qh + 1:
		verts.append(Vector3(x0 * cell - half, -1.0, (z0 + z) * cell - half))
	var east := verts.size()
	for z in qh + 1:
		verts.append(Vector3((x0 + qw) * cell - half, -1.0, (z0 + z) * cell - half))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var base_step := 1
	if style == "lowpoly":
		base_step = lowpoly_step
		while base_step > 1 and (qw % base_step != 0 or qh % base_step != 0):
			base_step /= 2
	arrays[Mesh.ARRAY_INDEX] = _chunk_indices(vw, qw, qh, base_step, north, south, west, east)
	var lods := {}
	if lod_enabled:
		for s in LOD_STEPS:
			if s > base_step and qw % s == 0 and qh % s == 0 and qw >= s and qh >= s:
				var key: float = lod_distance * (float(s) / 2.0) * LOD_KEY_PER_METER
				lods[key] = _chunk_indices(vw, qw, qh, s, north, south, west, east)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh


func _chunk_indices(vw: int, qw: int, qh: int, s: int, north: int, south: int, west: int, east: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for z in range(0, qh, s):
		for x in range(0, qw, s):
			var a := z * vw + x
			var b := a + s
			var c := (z + s) * vw + x + s
			var d := (z + s) * vw + x
			idx.append_array([a, b, c, a, c, d])
	for x in range(0, qw, s):
		# North edge (z = 0), seen from -Z.
		var ta := x + s
		var tb := x
		idx.append_array([ta, tb, north + x, ta, north + x, north + x + s])
		# South edge (z = qh), seen from +Z.
		var sa := qh * vw + x
		var sb := qh * vw + x + s
		idx.append_array([sa, sb, south + x + s, sa, south + x + s, south + x])
	for z in range(0, qh, s):
		# West edge (x = 0), seen from -X.
		var wa := z * vw
		var wb := (z + s) * vw
		idx.append_array([wa, wb, west + z + s, wa, west + z + s, west + z])
		# East edge (x = qw), seen from +X.
		var ea := (z + s) * vw + qw
		var eb := z * vw + qw
		idx.append_array([ea, eb, east + z, ea, east + z, east + z + s])
	return idx


func _update_chunk_aabbs(rect: Rect2i) -> void:
	if data == null:
		return
	var cell: float = data.cell_size
	var half := get_size() * 0.5
	var skirt := maxf(2.0, cell * 4.0)
	for i in _chunks.size():
		var cr: Rect2i = _chunk_rects[i]
		if rect.size.x > 0 and not cr.grow(1).intersects(rect):
			continue
		var r: Vector2 = data.region_range(cr.position.x, cr.position.y, cr.end.x, cr.end.y)
		var mesh: ArrayMesh = (_chunks[i] as MeshInstance3D).mesh
		mesh.custom_aabb = AABB(
			Vector3(cr.position.x * cell - half, r.x - skirt - 0.5, cr.position.y * cell - half),
			Vector3(cr.size.x * cell, r.y - r.x + skirt + 1.0, cr.size.y * cell))


func _apply_shadow_setting() -> void:
	for mi in _chunks:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_collision() -> void:
	if not collision_enabled or data == null:
		if _body != null:
			_body.queue_free()
			_body = null
			_shape_node = null
		return
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "Collision"
		_body.collision_layer = collision_layer
		_body.collision_mask = collision_mask
		add_child(_body, false, Node.INTERNAL_MODE_BACK)
		_shape_node = CollisionShape3D.new()
		_body.add_child(_shape_node, false, Node.INTERNAL_MODE_BACK)
	var shape := _shape_node.shape as HeightMapShape3D
	if shape == null:
		shape = HeightMapShape3D.new()
	shape.map_width = data.resolution
	shape.map_depth = data.resolution
	shape.map_data = data.heights
	_shape_node.shape = shape
	_shape_node.scale = Vector3(data.cell_size, 1.0, data.cell_size)


func _update_water_material() -> void:
	if _water_material == null:
		return
	var deep := water_deep_color
	var shallow := water_shallow_color
	match style:
		"toon", "cel", "stylized":
			# Brighter, more saturated water for non-realistic styles.
			deep = Color.from_hsv(deep.h, minf(deep.s * 1.1, 1.0), clampf(deep.v * 1.9, 0.0, 1.0), 0.95)
			shallow = Color.from_hsv(shallow.h, minf(shallow.s * 1.1, 1.0), clampf(shallow.v * 1.3, 0.0, 1.0), 0.8)
		"lowpoly":
			deep = Color.from_hsv(deep.h, minf(deep.s * 0.95, 1.0), clampf(deep.v * 2.4, 0.0, 1.0), 0.96)
			shallow = Color.from_hsv(shallow.h, shallow.s, clampf(shallow.v * 1.35, 0.0, 1.0), 0.9)
	var normal_tex: Texture2D = load(WATER_NORMAL_PATH) if style == "realistic" and ResourceLoader.exists(WATER_NORMAL_PATH) else null
	for mat in [_water_material, _lake_material, _river_material]:
		if mat == null:
			continue
		mat.set_shader_parameter("deep_color", deep)
		mat.set_shader_parameter("shallow_color", shallow)
		if style in ["toon", "cel", "stylized"]:
			mat.set_shader_parameter("softness", 0.005 if style == "cel" else (0.1 if style == "stylized" else 0.02))
			mat.set_shader_parameter("color_bands", 2.0 if style == "cel" else (6.0 if style == "stylized" else 3.0))
		if normal_tex != null:
			mat.set_shader_parameter("normal_tex", normal_tex)
		if data != null:
			_ensure_textures()
			mat.set_shader_parameter("heightmap", _height_tex)
			mat.set_shader_parameter("cell_size", data.cell_size)
			mat.set_shader_parameter("terrain_half_size", get_size() * 0.5)
			mat.set_shader_parameter("has_terrain", true)
	if _lake_material != null:
		_lake_material.set_shader_parameter("swell", 0.0)
		_lake_material.set_shader_parameter("wave_height", 0.05)
	if _river_material != null:
		_river_material.set_shader_parameter("flow_speed", 0.35)
		_river_material.set_shader_parameter("wave_height", 0.03)
		_river_material.set_shader_parameter("swell", 0.0)


func _build_water() -> void:
	_water_queued = false
	if not is_inside_tree() or data == null:
		return
	if _water_root == null:
		_water_root = Node3D.new()
		_water_root.name = "Water"
		add_child(_water_root, false, Node.INTERNAL_MODE_BACK)
	_clear_children(_water_root)
	if not water_enabled and rivers.is_empty() and lakes.is_empty():
		return
	var shader: Shader = WATER_SHADERS.get(style, WATER_SHADERS.realistic)
	for key in ["_water_material", "_lake_material", "_river_material"]:
		if get(key) == null:
			set(key, ShaderMaterial.new())
		(get(key) as ShaderMaterial).shader = shader
	_update_water_material()
	if water_enabled:
		var sea := MeshInstance3D.new()
		if style == "lowpoly":
			# Subdivided so the faceted waves are visible, and big enough to reach the horizon.
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE * maxf(get_size() * 8.0, 2048.0)
			plane.subdivide_width = 255
			plane.subdivide_depth = 255
			plane.center_offset = Vector3(0, water_level, 0)
			sea.mesh = plane
		else:
			sea.mesh = _sea_mesh(water_level)
		sea.material_override = _water_material
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_root.add_child(sea, false, Node.INTERNAL_MODE_BACK)
	for lake in lakes:
		var mi := MeshInstance3D.new()
		mi.mesh = _disc_mesh(lake.center, float(lake.radius) * 1.35, float(lake.level))
		mi.material_override = _lake_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_root.add_child(mi, false, Node.INTERNAL_MODE_BACK)
	for river in rivers:
		var mesh := _ribbon_mesh(river.points, river.levels, float(river.width))
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _river_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water_root.add_child(mi, false, Node.INTERNAL_MODE_BACK)


## Sea surface: a fine grid over the terrain (so the swell and the shoreline
## are smooth) and square rings that get coarser out to the horizon. UV.x holds
## the local vertex spacing (the shader drops waves the grid cannot draw).
func _sea_mesh(level: float) -> ArrayMesh:
	var half := get_size() * 0.5
	var inner := half * 1.3 + 24.0
	var n := 200
	var s0 := inner * 2.0 / float(n)
	var far := maxf(get_size() * 16.0, 8192.0) * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for gz in n + 1:
		for gx in n + 1:
			verts.append(Vector3(-inner + gx * s0, level, -inner + gz * s0))
			uvs.append(Vector2(s0, 0.0))
	for gz in n:
		for gx in n:
			var a := gz * (n + 1) + gx
			idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	# Border loop of the grid, in the same order as the rings below.
	var loop_len := n * 4
	var prev := PackedInt32Array()
	for i in loop_len:
		var side := floori(float(i) / float(n))
		var k := i % n
		var gx := 0
		var gz := 0
		match side:
			0:
				gx = k
				gz = 0
			1:
				gx = n
				gz = k
			2:
				gx = n - k
				gz = n
			_:
				gx = 0
				gz = n - k
		prev.append(gz * (n + 1) + gx)
	var e := inner
	while e < far:
		var e2 := minf(e * 1.2, far) if e * 1.2 < far * 0.98 else far
		var spacing := maxf(e2 - e, e2 * 2.0 / float(n))
		var start := verts.size()
		for i in loop_len:
			var side := floori(float(i) / float(n))
			var t := float(i % n) / float(n) * 2.0 - 1.0
			var p := Vector2.ZERO
			match side:
				0:
					p = Vector2(t * e2, -e2)
				1:
					p = Vector2(e2, t * e2)
				2:
					p = Vector2(-t * e2, e2)
				_:
					p = Vector2(-e2, -t * e2)
			verts.append(Vector3(p.x, level, p.y))
			uvs.append(Vector2(spacing, 0.0))
		for i in loop_len:
			var j := (i + 1) % loop_len
			# Clockwise seen from above (Godot front faces), like the horizon ring.
			idx.append_array([start + i, start + j, prev[j], start + i, prev[j], prev[i]])
		for i in loop_len:
			prev[i] = start + i
		e = e2
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-far, level - 4.0, -far), Vector3(far * 2.0, 8.0, far * 2.0))
	return mesh


## Lake surface: a square grid clipped to the circle (even triangles, so the
## faceted low-poly waves look right; the shore is where it meets the ground).
func _disc_mesh(center: Vector2, radius: float, level: float) -> ArrayMesh:
	var n := clampi(int(radius / 1.6), 12, 72)
	var step := radius * 2.0 / float(n)
	var origin := center - Vector2(radius, radius)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for gz in n + 1:
		for gx in n + 1:
			verts.append(Vector3(origin.x + gx * step, level, origin.y + gz * step))
			uvs.append(Vector2(float(gx) / n, float(gz) / n))
	for gz in n:
		for gx in n:
			var cc := origin + Vector2(gx + 0.5, gz + 0.5) * step
			if cc.distance_to(center) > radius + step * 0.75:
				continue
			var a := gz * (n + 1) + gx
			var b := a + 1
			var c := a + n + 2
			var d := a + n + 1
			if (gx + gz) % 2 == 0:
				idx.append_array([a, b, c, a, c, d])
			else:
				idx.append_array([a, b, d, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ribbon_mesh(points: PackedVector2Array, levels: PackedFloat32Array, width: float) -> ArrayMesh:
	var n := points.size()
	if n < 2:
		return null
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	var hw := width * 0.75
	for i in n:
		var p := points[i]
		var tangent := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-tangent.y, tangent.x) * hw
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		var lv := levels[i] if i < levels.size() else levels[levels.size() - 1]
		verts.append(Vector3(p.x + side.x, lv, p.y + side.y))
		verts.append(Vector3(p.x - side.x, lv, p.y - side.y))
		uvs.append(Vector2(0.0, along / maxf(width, 0.1)))
		uvs.append(Vector2(1.0, along / maxf(width, 0.1)))
	for i in n - 1:
		var a := i * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
