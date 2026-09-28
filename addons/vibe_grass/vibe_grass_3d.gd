@tool
@icon("res://addons/vibe_grass/icons/grass.svg")
class_name VibeGrass3D
extends Node3D
## GPU grass that grows on a [VibeTerrain3D] (or on a flat area).
##
## Clumps are MultiMesh instances on a jittered grid; the shader lifts them to
## the terrain surface, culls them with the painted density map, fades them
## with distance and animates wind. Painting density is instant (texture
## upload only). Styles: realistic, stylized, toon, cel, lowpoly.

const DataScript = preload("res://addons/vibe_grass/vibe_grass_data.gd")
const Presets = preload("res://addons/vibe_grass/grass_presets.gd")
const MeshBuilder = preload("res://addons/vibe_grass/grass_mesh_builder.gd")
const SHADERS := {
	"realistic": preload("res://addons/vibe_grass/shaders/grass_realistic.gdshader"),
	"stylized": preload("res://addons/vibe_grass/shaders/grass_stylized.gdshader"),
	"toon": preload("res://addons/vibe_grass/shaders/grass_toon.gdshader"),
	"cel": preload("res://addons/vibe_grass/shaders/grass_toon.gdshader"),
	"lowpoly": preload("res://addons/vibe_grass/shaders/grass_lowpoly.gdshader"),
}
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const GROUP := &"vibe_grass"
const TERRAIN_GROUP := &"vibe_terrain"
const VARIANTS := 4
const FAR_FRACTION := 0.35

## Terrain to grow on (empty = parent terrain or the first terrain in the scene).
@export var terrain_path: NodePath:
	set(v):
		terrain_path = v
		_queue_rebuild()
@export var data: DataScript:
	set(v):
		if data == v:
			return
		data = v
		_queue_rebuild()
## Grass type: meadow, lush, tall, dry, flowers, wheat, tundra, savanna, reeds, alien.
@export var preset := "meadow":
	set(v):
		preset = v
		if is_node_ready() and not _applying:
			apply_preset(v)
@export_enum("realistic", "stylized", "toon", "cel", "lowpoly") var style := "realistic":
	set(v):
		style = v if STYLES.has(v) else "realistic"
		_queue_rebuild()

@export_group("Blades")
@export_range(1, 16) var blades_per_clump := 6:
	set(v):
		blades_per_clump = v
		_queue_rebuild()
@export_range(0.05, 4.0, 0.01, "suffix:m") var blade_height := 0.45:
	set(v):
		blade_height = v
		_queue_rebuild()
@export_range(0.005, 0.3, 0.001, "suffix:m") var blade_width := 0.045:
	set(v):
		blade_width = v
		_queue_rebuild()
@export_range(0.0, 1.5, 0.01) var blade_curve := 0.35:
	set(v):
		blade_curve = v
		_queue_rebuild()
## Clumps per square meter where the density map is 1.
@export_range(0.1, 40.0, 0.1) var density_per_m2 := 6.0:
	set(v):
		density_per_m2 = v
		_queue_rebuild()
@export_range(0.0, 1.0, 0.01) var flower_chance := 0.0:
	set(v):
		flower_chance = v
		_queue_rebuild()
@export_range(0.01, 0.3, 0.005) var flower_size := 0.05:
	set(v):
		flower_size = v
		_queue_rebuild()
@export var wheat := false:
	set(v):
		wheat = v
		_queue_rebuild()

@export_group("Color")
@export var color_base := Color("#1b3510"):
	set(v):
		color_base = v
		_update_material()
@export var color_tip := Color("#86a84a"):
	set(v):
		color_tip = v
		_update_material()
@export var dry_color := Color("#a1904c"):
	set(v):
		dry_color = v
		_update_material()
@export_range(0.0, 1.0, 0.01) var dry_amount := 0.22:
	set(v):
		dry_amount = v
		_update_material()
@export var sss_color := Color("#d6e27a"):
	set(v):
		sss_color = v
		_update_material()
@export_range(0.0, 8.0, 0.05) var emission := 0.0:
	set(v):
		emission = v
		_update_material()
@export var flower_colors := PackedColorArray([Color("#ffe14d"), Color("#ff5f9e"), Color("#ffffff"), Color("#b27bff")]):
	set(v):
		flower_colors = v
		_update_material()

@export_group("Wind")
@export_range(0.0, 3.0, 0.01) var wind_strength := 0.35:
	set(v):
		wind_strength = v
		_update_material()
@export_range(0.0, 5.0, 0.01) var wind_speed := 1.0:
	set(v):
		wind_speed = v
		_update_material()
@export var wind_direction := Vector2(1.0, 0.35):
	set(v):
		wind_direction = v
		_update_material()
## Optional node (e.g. the player) that pushes the grass aside.
@export var interact_node: NodePath
@export_range(0.1, 10.0, 0.1) var interact_radius := 1.2

@export_group("Rendering")
@export_range(10.0, 500.0, 1.0, "suffix:m") var view_distance := 70.0:
	set(v):
		view_distance = v
		_queue_rebuild()
@export_range(4.0, 64.0, 1.0, "suffix:m") var chunk_size := 16.0:
	set(v):
		chunk_size = v
		_queue_rebuild()
@export var cast_shadows := false:
	set(v):
		cast_shadows = v
		_queue_rebuild()

@export_group("Flat mode (no terrain)")
@export_range(4.0, 4096.0, 1.0, "suffix:m") var area_size := 64.0:
	set(v):
		area_size = v
		_queue_rebuild()

var _terrain: Node = null
var _root: Node3D = null
var _mesh: ArrayMesh
var _near_mm: Array = []
var _far_mm: Array = []
var _mat_near: ShaderMaterial
var _mat_far: ShaderMaterial
var _density_tex: ImageTexture
var _noise_tex: NoiseTexture2D
var _chunks: Array = []
var _rebuild_queued := false
var _applying := false
var _last_xform := Transform3D()
var _tinted_terrain: WeakRef = null


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if blades_per_clump <= 0:
		apply_preset(preset)
	_rebuild()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_externalize_data()
		NOTIFICATION_VISIBILITY_CHANGED:
			_register_ground_tint()
		NOTIFICATION_EXIT_TREE:
			_unregister_ground_tint()


func _process(_delta: float) -> void:
	if _root == null:
		return
	var xf := _space_transform()
	if not xf.is_equal_approx(_last_xform):
		_last_xform = xf
		_root.global_transform = xf
		_update_material()
	if not interact_node.is_empty() and _mat_near != null:
		var n := get_node_or_null(interact_node) as Node3D
		if n != null:
			var p := n.global_position
			_mat_near.set_shader_parameter("pusher", Vector4(p.x, p.y, p.z, interact_radius))
			_mat_far.set_shader_parameter("pusher", Vector4(p.x, p.y, p.z, interact_radius))


# --- Public API ---------------------------------------------------------------------

func get_terrain() -> Node:
	if _terrain != null and is_instance_valid(_terrain) and _terrain.is_inside_tree():
		return _terrain
	_terrain = null
	if not terrain_path.is_empty():
		var n := get_node_or_null(terrain_path)
		if n != null and n.is_in_group(TERRAIN_GROUP):
			_terrain = n
	if _terrain == null:
		var p := get_parent()
		while p != null:
			if p.is_in_group(TERRAIN_GROUP):
				_terrain = p
				break
			p = p.get_parent()
	if _terrain == null and is_inside_tree():
		var scene := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if scene == null:
			scene = get_tree().root
		for t in get_tree().get_nodes_in_group(TERRAIN_GROUP):
			if scene == t or scene.is_ancestor_of(t):
				_terrain = t
				break
	return _terrain


## Half size (local units) of the area covered by grass.
func get_half_size() -> float:
	var t := get_terrain()
	return t.get_size() * 0.5 if t != null and t.data != null else area_size * 0.5


func apply_preset(preset_name: String) -> bool:
	var key := Presets.resolve(preset_name)
	if key == "":
		return false
	var p: Dictionary = Presets.PRESETS[key]
	_applying = true
	blades_per_clump = int(p.get("blades", 6))
	blade_height = float(p.get("height", 0.45))
	blade_width = float(p.get("width", 0.045))
	blade_curve = float(p.get("curve", 0.35))
	density_per_m2 = float(p.get("density", 6.0))
	flower_chance = float(p.get("flowers", 0.0))
	flower_size = float(p.get("flower_size", 0.05))
	wheat = bool(p.get("wheat", false))
	color_base = Color.html(p.get("color_base", "#1b3510"))
	color_tip = Color.html(p.get("color_tip", "#86a84a"))
	dry_color = Color.html(p.get("dry_color", "#a1904c"))
	dry_amount = float(p.get("dry_amount", 0.2))
	sss_color = Color.html(p.get("sss_color", "#d6e27a"))
	emission = float(p.get("emission", 0.0))
	wind_strength = float(p.get("wind_strength", 0.35))
	var fc := PackedColorArray()
	for c in p.get("flower_colors", ["#ffe14d", "#ff5f9e", "#ffffff", "#b27bff"]):
		fc.append(Color.html(c))
	while fc.size() < 4:
		fc.append(fc[fc.size() - 1] if fc.size() > 0 else Color.WHITE)
	flower_colors = fc
	preset = key
	_applying = false
	_queue_rebuild()
	return true


## Paints density around a world position. target 0..1, strength 0..1. Returns the changed texel rect.
func paint(world_pos: Vector3, radius: float, target: float, strength: float = 1.0, hardness: float = 0.5) -> Rect2i:
	_ensure_data()
	var c := world_to_texel(world_pos)
	var cell := _texel_size()
	var r := radius / maxf(cell, 0.0001)
	var res := data.resolution
	var x0 := maxi(0, int(floor(c.x - r)))
	var z0 := maxi(0, int(floor(c.y - r)))
	var x1 := mini(res - 1, int(ceil(c.x + r)))
	var z1 := mini(res - 1, int(ceil(c.y + r)))
	var d := data.density
	var tv := clampf(target, 0.0, 1.0) * 255.0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var dist := Vector2(x, z).distance_to(c)
			if dist >= r:
				continue
			var t := dist / r
			var f := 1.0 if t <= hardness else 1.0 - smoothstep(hardness, 1.0, t)
			var i := z * res + x
			d[i] = int(round(lerpf(float(d[i]), tv, clampf(f * strength, 0.0, 1.0))))
	data.density = d
	update_density()
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


## Fills the density map from rules (height, slope, terrain layer, water, patches).
func fill(rules: Dictionary = {}) -> float:
	_ensure_data()
	var t := get_terrain()
	var res := data.resolution
	var value := clampf(float(rules.get("density", 1.0)), 0.0, 1.0)
	var min_h := float(rules.get("min_height", -INF))
	var max_h := float(rules.get("max_height", INF))
	var max_slope := float(rules.get("max_slope", 38.0))
	var min_slope := float(rules.get("min_slope", 0.0))
	var layer := int(rules.get("layer", -1))
	var min_w := float(rules.get("min_layer_weight", 0.35))
	var avoid_water := bool(rules.get("avoid_water", true))
	var margin := float(rules.get("water_margin", 0.4))
	var patchiness := clampf(float(rules.get("patchiness", 0.3)), 0.0, 1.0)
	var mode := str(rules.get("mode", "replace"))
	var noise := FastNoiseLite.new()
	noise.seed = int(rules.get("seed", 5))
	noise.frequency = 1.0 / maxf(float(rules.get("patch_scale", 18.0)), 0.5)
	noise.fractal_octaves = 3
	var d := data.density
	var half := get_half_size()
	var cell := _texel_size()
	var has_water := t != null and bool(t.water_enabled)
	var wl: float = t.water_level if t != null else 0.0
	var lakes: Array = t.lakes if t != null else []
	for z in res:
		for x in res:
			var v := value
			var lx := x * cell - half
			var lz := z * cell - half
			if t != null:
				var td = t.data
				var fx: float = (lx + half) / td.cell_size
				var fz: float = (lz + half) / td.cell_size
				var h: float = td.sample(fx, fz)
				if h < min_h or h > max_h:
					v = 0.0
				elif avoid_water and has_water and h < wl + margin:
					v = 0.0
				else:
					var n: Vector3 = td.sample_normal(fx, fz)
					var slope := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
					if slope > max_slope or slope < min_slope:
						v *= 1.0 - smoothstep(max_slope, max_slope + 6.0, slope) if slope > max_slope else 0.0
					if layer >= 0:
						var w: float = td.sample_weight(fx, fz, layer)
						v *= smoothstep(min_w - 0.15, min_w + 0.15, w)
					if avoid_water:
						for lake in lakes:
							if Vector2(lx, lz).distance_to(lake.center) < float(lake.radius) * 1.25 and h < float(lake.level) + margin:
								v = 0.0
			if patchiness > 0.0 and v > 0.0:
				var pn := noise.get_noise_2d(lx, lz) * 0.5 + 0.5
				v *= smoothstep(patchiness * 0.85, patchiness * 0.85 + 0.3, pn + (1.0 - patchiness) * 0.35)
			var i := z * res + x
			var nv := int(round(clampf(v, 0.0, 1.0) * 255.0))
			match mode:
				"add":
					d[i] = mini(255, d[i] + nv)
				"max":
					d[i] = maxi(d[i], nv)
				"min":
					d[i] = mini(d[i], nv)
				"multiply":
					d[i] = int(round(d[i] * nv / 255.0))
				_:
					d[i] = nv
	data.density = d
	update_density()
	return data.coverage()


func clear() -> void:
	_ensure_data()
	data.density.fill(0)
	update_density()


func world_to_texel(world: Vector3) -> Vector2:
	var local: Vector3 = _space_transform().affine_inverse() * world
	var half := get_half_size()
	var cell := _texel_size()
	return Vector2((local.x + half) / cell, (local.z + half) / cell)


func update_density() -> void:
	if data == null:
		return
	if _density_tex != null and _density_tex.get_width() == data.resolution:
		_density_tex.update(data.image())
	else:
		_density_tex = ImageTexture.create_from_image(data.image())
		_update_material()


func get_info() -> Dictionary:
	var t := get_terrain()
	return {
		"name": str(name), "type": "VibeGrass3D", "preset": preset, "style": style,
		"terrain": str(t.name) if t != null else "",
		"coverage": snappedf(data.coverage(), 0.001) if data != null else 0.0,
		"blade_height": blade_height, "density_per_m2": density_per_m2,
		"view_distance": view_distance, "chunks": _chunks.size(),
		"data_file": data.resource_path if data != null else "",
	}


func make_snapshot() -> Dictionary:
	_ensure_data()
	return {"data": data.snapshot()}


func apply_snapshot(snap: Dictionary) -> void:
	_ensure_data()
	if snap.has("data"):
		data.restore(snap.data)
	update_density()


func save_external_data() -> Array:
	if data == null or data.resource_path == "" or data.resource_path.contains("::"):
		return []
	return [data.resource_path] if ResourceSaver.save(data, data.resource_path) == OK else []


# --- Building ------------------------------------------------------------------------

func _texel_size() -> float:
	var res := data.resolution if data != null else 2
	return get_half_size() * 2.0 / float(maxi(res - 1, 1))


func _space_transform() -> Transform3D:
	var t := get_terrain()
	if t != null:
		return (t as Node3D).global_transform if t.is_inside_tree() else (t as Node3D).transform
	return global_transform if is_inside_tree() else transform


func _ensure_data() -> void:
	var t := get_terrain()
	var res: int = t.data.resolution if t != null and t.data != null else maxi(3, int(area_size) + 1)
	if data == null:
		data = DataScript.new()
		data.setup(res, 0)
	elif not data.is_valid():
		data.setup(res, 0)
	elif data.resolution != res:
		data.resample(res)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	if _rebuild_queued:
		_rebuild()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_ensure_data()
	var t := get_terrain()
	if t != null and not t.heights_changed.is_connected(_on_terrain_heights_changed):
		t.heights_changed.connect(_on_terrain_heights_changed)
	if _noise_tex == null:
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 256
		_noise_tex.height = 256
		_noise_tex.seamless = true
		_noise_tex.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 3
		_noise_tex.noise = fn
	_density_tex = ImageTexture.create_from_image(data.image())
	_mesh = MeshBuilder.build({
		"blades": blades_per_clump, "height": blade_height, "width": blade_width, "curve": blade_curve,
		"flowers": flower_chance, "flower_size": flower_size, "wheat": wheat, "style": style, "seed": hash(str(name)) % 1000,
	})
	_build_multimeshes()
	_mat_near = ShaderMaterial.new()
	_mat_near.shader = SHADERS.get(style, SHADERS.realistic)
	_mat_far = ShaderMaterial.new()
	_mat_far.shader = _mat_near.shader
	_update_material()
	_build_chunks()


func _build_multimeshes() -> void:
	_near_mm.clear()
	_far_mm.clear()
	var count := clampi(int(chunk_size * chunk_size * density_per_m2), 1, 40000)
	var far_count := maxi(1, int(count * FAR_FRACTION))
	for v in VARIANTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + v * 7919 + hash(str(name))
		var g := int(ceil(sqrt(float(count))))
		var cell := chunk_size / float(g)
		var xforms: Array = []
		for gz in g:
			for gx in g:
				if xforms.size() >= count:
					break
				var pos := Vector3((gx + rng.randf()) * cell, 0.0, (gz + rng.randf()) * cell)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
				xforms.append(Transform3D(basis, pos))
		# Shuffle so that any prefix (far LOD) stays evenly spread.
		for i in range(xforms.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = xforms[i]
			xforms[i] = xforms[j]
			xforms[j] = tmp
		var near := MultiMesh.new()
		near.transform_format = MultiMesh.TRANSFORM_3D
		near.mesh = _mesh
		near.instance_count = xforms.size()
		for i in xforms.size():
			near.set_instance_transform(i, xforms[i])
		var far := MultiMesh.new()
		far.transform_format = MultiMesh.TRANSFORM_3D
		far.mesh = _mesh
		far.instance_count = mini(far_count, xforms.size())
		for i in far.instance_count:
			far.set_instance_transform(i, xforms[i])
		_near_mm.append(near)
		_far_mm.append(far)


func _build_chunks() -> void:
	if _root == null:
		_root = Node3D.new()
		_root.name = "GrassChunks"
		_root.top_level = true
		add_child(_root, false, Node.INTERNAL_MODE_BACK)
	for c in _root.get_children(true):
		_root.remove_child(c)
		c.queue_free()
	_chunks.clear()
	_last_xform = _space_transform()
	_root.global_transform = _last_xform
	var half := get_half_size()
	var n := int(ceil(half * 2.0 / chunk_size))
	var near_end := view_distance * 0.45
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for cz in n:
		for cx in n:
			var origin := Vector3(-half + cx * chunk_size, 0.0, -half + cz * chunk_size)
			var variant := (cx * 7 + cz * 13) % VARIANTS
			var near := MultiMeshInstance3D.new()
			near.multimesh = _near_mm[variant]
			near.material_override = _mat_near
			near.position = origin
			near.visibility_range_end = near_end
			near.visibility_range_end_margin = chunk_size * 0.5
			near.cast_shadow = shadow
			_root.add_child(near, false, Node.INTERNAL_MODE_BACK)
			var far := MultiMeshInstance3D.new()
			far.multimesh = _far_mm[variant]
			far.material_override = _mat_far
			far.position = origin
			far.visibility_range_begin = near_end
			far.visibility_range_begin_margin = chunk_size * 0.5
			far.visibility_range_end = view_distance + chunk_size
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(far, false, Node.INTERNAL_MODE_BACK)
			_chunks.append({"near": near, "far": far, "origin": origin})
	_update_aabbs()


func _update_aabbs() -> void:
	var t := get_terrain()
	var half := get_half_size()
	var extra := blade_height * 2.0 + 1.0
	for c in _chunks:
		var origin: Vector3 = c.origin
		var lo := -1.0
		var hi := extra
		if t != null and t.data != null:
			var cell: float = t.data.cell_size
			var x0 := int((origin.x + half) / cell)
			var z0 := int((origin.z + half) / cell)
			var span := int(ceil(chunk_size / cell))
			var r: Vector2 = t.data.region_range(x0, z0, x0 + span, z0 + span)
			lo = r.x - 1.0
			hi = r.y + extra
		var box := AABB(Vector3(0, lo, 0), Vector3(chunk_size, hi - lo, chunk_size))
		(c.near as MultiMeshInstance3D).custom_aabb = box
		(c.far as MultiMeshInstance3D).custom_aabb = box


func _on_terrain_heights_changed(_rect: Rect2i) -> void:
	_update_aabbs()


func _update_material() -> void:
	if _mat_near == null:
		return
	var t := get_terrain()
	var xf := _space_transform()
	for m in [_mat_near, _mat_far]:
		var mat: ShaderMaterial = m
		mat.set_shader_parameter("density_map", _density_tex)
		mat.set_shader_parameter("noise_tex", _noise_tex)
		mat.set_shader_parameter("world_to_terrain", Projection(xf.affine_inverse()))
		mat.set_shader_parameter("terrain_to_world", Projection(xf))
		mat.set_shader_parameter("terrain_half_size", get_half_size())
		if t != null and t.data != null:
			mat.set_shader_parameter("heightmap", t.get_heightmap_texture())
			mat.set_shader_parameter("cell_size", t.data.cell_size)
			mat.set_shader_parameter("has_terrain", true)
			mat.set_shader_parameter("water_level", t.water_level if t.water_enabled else -100000.0)
			# The coarse low-poly terrain surface differs a bit from the heightmap near the shore.
			mat.set_shader_parameter("shore_margin", 0.9 if str(t.style) == "lowpoly" else 0.15)
		else:
			mat.set_shader_parameter("has_terrain", false)
			mat.set_shader_parameter("water_level", -100000.0)
		mat.set_shader_parameter("view_distance", view_distance)
		mat.set_shader_parameter("fade_length", minf(view_distance * 0.3, 25.0))
		mat.set_shader_parameter("color_base", color_base)
		mat.set_shader_parameter("color_tip", color_tip)
		mat.set_shader_parameter("dry_color", dry_color)
		mat.set_shader_parameter("dry_amount", dry_amount)
		mat.set_shader_parameter("sss_color", sss_color)
		mat.set_shader_parameter("emission_strength", emission)
		for i in 4:
			mat.set_shader_parameter("flower_color_%d" % i, flower_colors[i] if i < flower_colors.size() else Color.WHITE)
		mat.set_shader_parameter("wind_strength", wind_strength)
		mat.set_shader_parameter("wind_speed", wind_speed)
		mat.set_shader_parameter("wind_direction", wind_direction)
		match style:
			"cel":
				mat.set_shader_parameter("bands", 2.0)
				mat.set_shader_parameter("band_softness", 0.01)
				mat.set_shader_parameter("color_steps", 2.0)
				mat.set_shader_parameter("rim_strength", 0.5)
			"toon":
				mat.set_shader_parameter("bands", 3.0)
				mat.set_shader_parameter("band_softness", 0.06)
				mat.set_shader_parameter("color_steps", 3.0)
	_mat_far.set_shader_parameter("width_scale", 1.7)
	_mat_near.set_shader_parameter("width_scale", 1.0)
	_register_ground_tint()


## [near, far] colors of the ground under this grass (alpha = strength): the
## terrain uses them so grassy areas keep their color where blades are culled.
func ground_tint_colors() -> Array:
	if style in ["toon", "cel", "lowpoly"]:
		var flat := color_base.lerp(color_tip, 0.5)
		return [Color(flat, 1.0), Color(flat, 1.0)]
	var avg := color_base.lerp(color_tip, 0.6).lerp(dry_color, dry_amount * 0.45)
	if flower_chance > 0.0 and not flower_colors.is_empty():
		var fc := Color(0, 0, 0)
		for c in flower_colors:
			fc += c
		fc /= float(flower_colors.size())
		avg = avg.lerp(fc, clampf(flower_chance * 0.15, 0.0, 0.12))
	var near := color_base.lerp(color_tip, 0.2) * 0.85
	return [Color(near, 0.7), Color(avg, 0.9)]


func _register_ground_tint() -> void:
	if not is_inside_tree():
		return
	var t := get_terrain()
	var old: Node = _tinted_terrain.get_ref() if _tinted_terrain != null else null
	if old != null and old != t and old.has_method("remove_grass_overlay"):
		old.remove_grass_overlay(get_instance_id())
	_tinted_terrain = weakref(t) if t != null else null
	if t == null or not t.has_method("set_grass_overlay"):
		return
	if not is_visible_in_tree() or _density_tex == null:
		t.remove_grass_overlay(get_instance_id())
		return
	var cols := ground_tint_colors()
	t.set_grass_overlay(get_instance_id(), _density_tex, cols[0], cols[1], view_distance)


func _unregister_ground_tint() -> void:
	var t: Node = _tinted_terrain.get_ref() if _tinted_terrain != null else null
	if t != null and t.has_method("remove_grass_overlay"):
		t.remove_grass_overlay(get_instance_id())
	_tinted_terrain = null


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
		path = dir.path_join("%s_grass.res" % str(name).to_lower().replace(" ", "_"))
		var n := 2
		while FileAccess.file_exists(path):
			path = dir.path_join("%s_grass_%d.res" % [str(name).to_lower().replace(" ", "_"), n])
			n += 1
		data.take_over_path(path)
	ResourceSaver.save(data, path)
