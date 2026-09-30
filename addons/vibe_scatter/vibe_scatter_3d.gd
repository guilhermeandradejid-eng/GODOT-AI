@tool
@icon("res://addons/vibe_scatter/icons/scatter.svg")
class_name VibeScatter3D
extends Node3D
## Trees, bushes, rocks and props scattered over a [VibeTerrain3D].
##
## Pick a [member preset] (forest, pines, palms, jungle, birches, acacias,
## dead_trees, bushes, ferns, cacti, rocks, boulders, mushrooms, crystals,
## logs...), a [member style] and a [member density]; placement follows
## [member rules] (slope, height above water, groves, clearings) and an
## optional painted density map. Models are procedural (no assets needed),
## drawn with MultiMesh chunks, a far LOD and wind; trees and rocks collide.

const Builder = preload("res://addons/vibe_scatter/scatter_builder.gd")
const Presets = preload("res://addons/vibe_scatter/scatter_presets.gd")
const DataScript = preload("res://addons/vibe_scatter/vibe_scatter_data.gd")
const SHADER_LEAVES = preload("res://addons/vibe_scatter/shaders/veg_leaves.gdshader")
const SHADER_SOLID = preload("res://addons/vibe_scatter/shaders/veg_solid.gdshader")
const SHADER_SOLID_TOON = preload("res://addons/vibe_scatter/shaders/veg_solid_toon.gdshader")
const TEX_PATHS := {
	"broad": "res://addons/vibe_scatter/textures/leaves_broad.png",
	"clump": "res://addons/vibe_scatter/textures/leaves_clump.png",
	"needles": "res://addons/vibe_scatter/textures/needles.png",
	"frond": "res://addons/vibe_scatter/textures/frond.png",
	"fern": "res://addons/vibe_scatter/textures/fern.png",
	"bark": "res://addons/vibe_scatter/textures/bark.png",
}
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const GROUP := &"vibe_scatter"
const TERRAIN_GROUP := &"vibe_terrain"
const CHUNK := 64.0
const MAX_INSTANCES := 60000
const SMALL := ["bush", "fern", "pebbles", "mushroom", "barrel_cactus", "stump"]
const TREES := ["broadleaf", "birch", "acacia", "pine", "palm", "dead_tree", "cactus"]

## Terrain to grow on (empty = parent terrain or the first terrain in the scene).
@export var terrain_path: NodePath:
	set(v):
		terrain_path = v
		_queue_rebuild()
@export var preset := "forest":
	set(v):
		preset = v
		_queue_rebuild()
@export_enum("realistic", "stylized", "toon", "cel", "lowpoly") var style := "realistic":
	set(v):
		style = v if STYLES.has(v) else "realistic"
		_queue_rebuild()
## Multiplier of the preset's density.
@export_range(0.0, 5.0, 0.01) var density := 1.0:
	set(v):
		density = maxf(v, 0.0)
		_queue_rebuild()
@export var random_seed := 1:
	set(v):
		random_seed = v
		_queue_rebuild()
## Placement overrides: max_slope, min_slope, min_above_water, max_above_water,
## min_height_frac, max_height_frac, cluster (0..1), cluster_scale, water_margin, clearing.
@export var rules: Dictionary = {}:
	set(v):
		rules = v
		_queue_rebuild()
## Color palette (temperate, tropical, snowy, autumn, alien...); empty = the terrain's.
@export var palette := "":
	set(v):
		palette = v
		_queue_rebuild()
## Color overrides: {"leaves": ["#..", ...], "bark": "#..", "rock": "#..", "top": "#..", "top_amount": 0.5, "snow": 0.4}
@export var colors: Dictionary = {}:
	set(v):
		colors = v
		_queue_rebuild()
## Instance scale range (0, 0 = the preset's).
@export var scale_range := Vector2.ZERO:
	set(v):
		scale_range = v
		_queue_rebuild()
@export_group("Rendering")
@export_range(20.0, 5000.0, 1.0, "suffix:m") var view_distance := 520.0:
	set(v):
		view_distance = v
		_queue_rebuild()
@export_range(10.0, 2000.0, 1.0, "suffix:m") var lod_distance := 80.0:
	set(v):
		lod_distance = v
		_queue_rebuild()
@export_range(0.0, 3.0, 0.01) var wind_strength := 0.5:
	set(v):
		wind_strength = v
		for m in _materials.values():
			(m as ShaderMaterial).set_shader_parameter("wind_strength", v)
@export var wind_direction := Vector2(1.0, 0.35):
	set(v):
		wind_direction = v
		for m in _materials.values():
			(m as ShaderMaterial).set_shader_parameter("wind_direction", v)
@export var cast_shadows := true:
	set(v):
		cast_shadows = v
		_queue_rebuild()
@export_group("Collision")
@export var collision := true:
	set(v):
		collision = v
		_queue_rebuild()
@export_flags_3d_physics var collision_layer := 1
@export_group("Painting")
@export var data: DataScript:
	set(v):
		data = v
		_queue_rebuild()

static var _textures := {}

var _terrain: Node = null
var _root: Node3D = null
var _bodies: Array = []
var _shapes: Array = []
var _materials := {}
var _counts := {}
var _rebuild_queued := false
var _connected_terrain: WeakRef = null


func _ready() -> void:
	add_to_group(GROUP)
	_queue_rebuild()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_TREE:
			_free_physics()
		NOTIFICATION_PREDELETE:
			_free_physics()
		NOTIFICATION_TRANSFORM_CHANGED, NOTIFICATION_ENTER_TREE:
			pass


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


func get_preset_data() -> Dictionary:
	return Presets.get_preset(preset)


func get_info() -> Dictionary:
	var total := 0
	for k in _counts:
		total += int(_counts[k])
	var t := get_terrain()
	return {"name": str(name), "type": "VibeScatter3D", "preset": preset, "style": style, "density": density,
		"instances": total, "per_kind": _counts.duplicate(), "palette": _palette_name(), "terrain": str(t.name) if t != null else "",
		"view_distance": view_distance, "collision": collision}


func _palette_name() -> String:
	if palette != "":
		return palette
	var p: Dictionary = get_preset_data()
	if p.has("palette"):
		return str(p.palette)
	var t := get_terrain()
	if t != null and "palette" in t:
		return str(t.palette)
	return "temperate"


# --- Painting ------------------------------------------------------------------------

func ensure_data() -> void:
	var t := get_terrain()
	var res := 256
	if t != null and t.data != null:
		res = clampi(int(t.data.resolution), 64, 1025)
	if data == null or not data.is_valid() or data.resolution != res:
		var d := DataScript.new()
		d.setup(res, 255)
		data = d


## Paints density (0..1) in a circle (world position); rebuilds the scatter.
func paint(world_pos: Vector3, radius: float, value: float, strength: float = 1.0) -> void:
	ensure_data()
	var t := get_terrain()
	if t == null:
		return
	var size: float = t.get_size()
	var local: Vector3 = (t as Node3D).global_transform.affine_inverse() * world_pos
	var res := data.resolution
	var cell := size / float(res - 1)
	var cx := (local.x + size * 0.5) / cell
	var cz := (local.z + size * 0.5) / cell
	var r := radius / cell
	var d := data.density
	for z in range(maxi(0, int(cz - r - 1)), mini(res, int(cz + r + 2))):
		for x in range(maxi(0, int(cx - r - 1)), mini(res, int(cx + r + 2))):
			var dist := Vector2(x - cx, z - cz).length()
			if dist > r:
				continue
			var f := (1.0 - smoothstep(r * 0.6, r, dist)) * strength
			var i := z * res + x
			d[i] = int(round(lerpf(d[i], clampf(value, 0.0, 1.0) * 255.0, f)))
	data.density = d
	rebuild()


func make_snapshot() -> Dictionary:
	ensure_data()
	return {"data": data.snapshot()}


func apply_snapshot(snap: Dictionary) -> void:
	ensure_data()
	if snap.has("data"):
		data.restore(snap.data)
	rebuild()


func save_external_data() -> Array:
	if data == null or data.resource_path == "" or data.resource_path.contains("::"):
		return []
	return [data.resource_path] if ResourceSaver.save(data, data.resource_path) == OK else []


# --- Building ------------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _connect_terrain(t: Node) -> void:
	if _connected_terrain != null and _connected_terrain.get_ref() == t:
		return
	if t.has_signal("heights_changed") and not t.heights_changed.is_connected(_on_terrain_changed):
		t.heights_changed.connect(_on_terrain_changed)
	_connected_terrain = weakref(t)


func _on_terrain_changed(_rect: Rect2i) -> void:
	_queue_rebuild()


func _free_physics() -> void:
	for b in _bodies:
		PhysicsServer3D.free_rid(b)
	for s in _shapes:
		PhysicsServer3D.free_rid(s)
	_bodies.clear()
	_shapes.clear()


## Rebuilds every instance now (placement + meshes + collision).
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "ScatterChunks"
		_root.top_level = true
		add_child(_root, false, Node.INTERNAL_MODE_BACK)
	for c in _root.get_children(true):
		_root.remove_child(c)
		c.queue_free()
	_free_physics()
	_counts.clear()
	_materials.clear()
	var t := get_terrain()
	if t == null or t.data == null:
		return
	_connect_terrain(t)
	_root.global_transform = (t as Node3D).global_transform
	var p: Dictionary = get_preset_data()
	if p.is_empty():
		push_warning("VibeScatter3D: unknown preset '%s'" % preset)
		return
	var placements := _place(t, p)
	_build_nodes(t, p, placements)


func _rule(p: Dictionary, key: String, default: Variant) -> Variant:
	if rules.has(key):
		return rules[key]
	var pr: Dictionary = p.get("rules", {})
	return pr.get(key, default)


## Returns {"kind/variant": [Transform3D local to the terrain, ...]}.
func _place(t: Node, p: Dictionary) -> Dictionary:
	var td = t.data
	var size: float = t.get_size()
	var half := size * 0.5
	var per_m2: float = float(p.get("density", 0.01)) * density
	if per_m2 <= 0.0:
		return {}
	var cell := maxf(1.0 / sqrt(per_m2), size / sqrt(float(MAX_INSTANCES)))
	var n := int(ceil(size / cell))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([random_seed, preset])
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / maxf(float(_rule(p, "cluster_scale", 55.0)), 1.0)
	noise.fractal_octaves = 3
	var cluster := clampf(float(_rule(p, "cluster", 0.4)), 0.0, 1.0)
	var max_slope := float(_rule(p, "max_slope", 35.0))
	var min_slope := float(_rule(p, "min_slope", 0.0))
	var margin := float(_rule(p, "water_margin", 0.8))
	var min_above := float(_rule(p, "min_above_water", -INF))
	var max_above := float(_rule(p, "max_above_water", INF))
	var hr: Vector2 = td.height_range()
	var min_frac := float(_rule(p, "min_height_frac", 0.0))
	var max_frac := float(_rule(p, "max_height_frac", 1.0))
	var clearing := float(_rule(p, "clearing", 5.0 if _is_tree_preset(p) else 1.5))
	var has_water: bool = bool(t.water_enabled)
	var wl: float = float(t.water_level)
	var lakes: Array = t.lakes
	var rivers: Array = t.rivers
	var align := float(p.get("align", 0.05))
	var sink := float(p.get("sink", 0.0))
	var sr: Vector2 = scale_range if scale_range != Vector2.ZERO else Vector2(p.get("scale", [0.8, 1.2])[0], p.get("scale", [0.8, 1.2])[1])
	var items: Dictionary = p.get("items", {})
	var kinds: Array = items.keys()
	var weights: Array = []
	var total_w := 0.0
	for k in kinds:
		total_w += float(items[k])
		weights.append(total_w)
	# Clearings around effects and characters (campfires, portals, heroes...).
	var clear_pts: Array = []
	if clearing > 0.0 and is_inside_tree():
		var inv := (t as Node3D).global_transform.affine_inverse()
		for g in [&"vibe_vfx", &"vibe_character"]:
			for node in get_tree().get_nodes_in_group(g):
				if node is Node3D and not bool(node.get("follow_camera") if "follow_camera" in node else false):
					var lp: Vector3 = inv * (node as Node3D).global_position
					clear_pts.append(Vector2(lp.x, lp.z))
	var out := {}
	var count := 0
	for gz in n:
		for gx in n:
			var lx := -half + (gx + rng.randf()) * cell
			var lz := -half + (gz + rng.randf()) * cell
			var roll := rng.randf()
			var pick := rng.randf() * total_w
			var variant := rng.randi() % Builder.VARIANTS
			var s := rng.randf_range(sr.x, sr.y)
			var yaw := rng.randf() * TAU
			if absf(lx) > half - 2.0 or absf(lz) > half - 2.0:
				continue
			var fx: float = (lx + half) / td.cell_size
			var fz: float = (lz + half) / td.cell_size
			var h: float = td.sample(fx, fz)
			if has_water and h < wl + margin:
				continue
			if has_water and (h - wl < min_above or h - wl > max_above):
				continue
			var frac := (h - hr.x) / maxf(hr.y - hr.x, 0.001)
			if frac < min_frac or frac > max_frac:
				continue
			var nrm: Vector3 = td.sample_normal(fx, fz)
			var slope := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
			if slope > max_slope or slope < min_slope:
				continue
			var prob := 1.0
			if cluster > 0.0:
				var v := noise.get_noise_2d(lx, lz) * 0.5 + 0.5
				prob *= smoothstep(cluster * 0.55 - 0.12, cluster * 0.55 + 0.12, v)
			if data != null and data.is_valid():
				var res := data.resolution
				prob *= data.sample((lx + half) / size * (res - 1), (lz + half) / size * (res - 1))
			if roll > prob:
				continue
			var blocked := false
			for lake in lakes:
				if Vector2(lx, lz).distance_to(lake.center) < float(lake.radius) * 1.2 + margin and h < float(lake.level) + margin + 0.5:
					blocked = true
					break
			if not blocked:
				for river in rivers:
					var pts: PackedVector2Array = river.points
					var w: float = float(river.get("width", 6.0)) * 0.5 + 1.5
					for i in range(pts.size() - 1):
						if _seg_dist(Vector2(lx, lz), pts[i], pts[i + 1]) < w:
							blocked = true
							break
					if blocked:
						break
			if not blocked:
				for cp in clear_pts:
					if Vector2(lx, lz).distance_to(cp) < clearing:
						blocked = true
						break
			if blocked:
				continue
			var ki := 0
			while ki < weights.size() - 1 and pick > float(weights[ki]):
				ki += 1
			var kind: String = kinds[ki]
			var up := Vector3.UP.lerp(nrm, align if not TREES.has(kind) else 0.05).normalized()
			var basis := _basis_up(up, yaw).scaled(Vector3.ONE * s)
			var model := Builder.get_model(kind, variant, style)
			var pos := Vector3(lx, h - sink * s * float(model.height), lz)
			var key := "%s/%d" % [kind, variant]
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append(Transform3D(basis, pos))
			count += 1
	return out


func _is_tree_preset(p: Dictionary) -> bool:
	for k in p.get("items", {}):
		if TREES.has(k):
			return true
	return false


static func _seg_dist(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return pt.distance_to(a)
	return pt.distance_to(a + ab * clampf((pt - a).dot(ab) / l2, 0.0, 1.0))


static func _basis_up(up: Vector3, yaw: float) -> Basis:
	var b := Basis(Vector3.UP, yaw)
	if up.dot(Vector3.UP) > 0.9999:
		return b
	var q := Quaternion(Vector3.UP, up)
	return Basis(q) * b


func _build_nodes(t: Node, p: Dictionary, placements: Dictionary) -> void:
	var pal := Presets.palette_colors(_palette_name())
	var shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var space: RID = get_world_3d().space if is_inside_tree() else RID()
	var xf := (t as Node3D).global_transform
	for key in placements:
		var kind: String = str(key).get_slice("/", 0)
		var variant := int(str(key).get_slice("/", 1))
		var model := Builder.get_model(kind, variant, style)
		var list: Array = placements[key]
		_counts[kind] = int(_counts.get(kind, 0)) + list.size()
		var small := SMALL.has(kind)
		var near_end := minf(lod_distance * (0.6 if small else 1.0), view_distance)
		var far_end := view_distance * (0.3 if small else 1.0)
		# Group by chunk.
		var chunks := {}
		for x in list:
			var tr: Transform3D = x
			var ck := Vector2i(int(floor(tr.origin.x / CHUNK)), int(floor(tr.origin.z / CHUNK)))
			if not chunks.has(ck):
				chunks[ck] = []
			(chunks[ck] as Array).append(tr)
		for ck in chunks:
			var xforms: Array = chunks[ck]
			for lod in ["near", "far"]:
				if lod == "far" and small:
					continue
				var parts: Dictionary = model[lod]
				for part in ["solid", "leaves"]:
					var mesh: ArrayMesh = parts[part]
					if mesh == null:
						continue
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.use_custom_data = true
					# Instance colors (white) too: the Compatibility renderer draws
					# custom-data-only MultiMeshes black.
					mm.use_colors = true
					mm.mesh = mesh
					mm.instance_count = xforms.size()
					var rng := RandomNumberGenerator.new()
					rng.seed = hash([ck.x, ck.y, key])
					for i in xforms.size():
						mm.set_instance_transform(i, xforms[i])
						mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
						mm.set_instance_color(i, Color.WHITE)
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.material_override = _material(kind, part, pal, lod == "far")
					mmi.cast_shadow = shadows if not (small and kind != "stump") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if lod == "near":
						mmi.visibility_range_end = small_or(near_end, small, far_end)
						mmi.visibility_range_end_margin = 8.0
						if small:
							mmi.visibility_range_end = far_end
					else:
						mmi.visibility_range_begin = near_end
						mmi.visibility_range_begin_margin = 8.0
						mmi.visibility_range_end = far_end
						mmi.visibility_range_end_margin = 20.0
					_root.add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		if collision and space.is_valid() and not (model.collider as Array).is_empty() and not small:
			_add_colliders(space, xf, model.collider, list)


static func small_or(v: float, small: bool, far_end: float) -> float:
	return far_end if small else v


func _add_colliders(space: RID, xf: Transform3D, col: Array, list: Array) -> void:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, collision_layer)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	_bodies.append(body)
	var kind := str(col[0])
	for x in list:
		var tr: Transform3D = x
		var s := tr.basis.get_scale().y
		var shape: RID
		var local := Transform3D(Basis(), tr.origin)
		match kind:
			"cylinder":
				shape = PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(shape, {"radius": float(col[1]) * s, "height": float(col[2]) * s})
				local.origin.y += float(col[2]) * s * 0.5
			"sphere":
				shape = PhysicsServer3D.sphere_shape_create()
				PhysicsServer3D.shape_set_data(shape, float(col[1]) * s)
				local.origin.y += float(col[1]) * s * 0.4
			"box":
				shape = PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape, Vector3(float(col[1]) * 0.5, float(col[2]) * 0.5, float(col[2]) * 0.5) * s)
				local = Transform3D(tr.basis.orthonormalized(), tr.origin + Vector3.UP * float(col[2]) * s * 0.5)
			_:
				continue
		_shapes.append(shape)
		PhysicsServer3D.body_add_shape(body, shape, local)


# --- Materials -------------------------------------------------------------------------

## Loaded lazily (a fresh clone imports the textures after parsing scripts).
static func tex(key: String) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = load(TEX_PATHS[key]) if ResourceLoader.exists(TEX_PATHS[key]) else null
	return _textures[key]

func _hex(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and (v as String).is_valid_html_color():
		return Color.html(v)
	return fallback


func _color_list(key: String, pal: Dictionary, fallback: Array) -> Array:
	var v = colors.get(key, pal.get(key, fallback))
	if v is String or v is Color:
		v = [v, v, v]
	var out: Array = []
	for i in 3:
		out.append(_hex(v[mini(i, v.size() - 1)] if v is Array and not v.is_empty() else fallback[mini(i, fallback.size() - 1)], Color(0.3, 0.5, 0.2)))
	return out


func _material(kind: String, part: String, pal: Dictionary, far: bool) -> ShaderMaterial:
	var key := "%s/%s/%s" % [kind, part, far]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	var toonish := style in ["toon", "cel", "stylized"]
	if part == "leaves":
		m.shader = SHADER_LEAVES
		var leaves := _color_list("leaves", pal, ["#3f6b24", "#5f8a2e", "#4a7a2c"])
		m.set_shader_parameter("leaf_color", leaves[0])
		m.set_shader_parameter("leaf_color2", leaves[1])
		m.set_shader_parameter("leaf_color3", leaves[2])
		var tkey := "clump" if toonish else "broad"
		match kind:
			"pine":
				tkey = "needles"
			"palm":
				tkey = "frond"
			"fern":
				tkey = "fern"
		m.set_shader_parameter("leaf_tex", tex(tkey))
		m.set_shader_parameter("use_texture", style != "lowpoly")
		m.set_shader_parameter("alpha_cut", 0.3 if far else (0.45 if kind != "pine" else 0.35))
		m.set_shader_parameter("mode", {"realistic": 0, "stylized": 1, "toon": 2, "cel": 2, "lowpoly": 1}.get(style, 0))
		m.set_shader_parameter("bands", 2.0 if style == "cel" else 3.0)
		m.set_shader_parameter("snow", float(colors.get("snow", pal.get("snow", 0.0))))
		m.set_shader_parameter("brightness", 1.05 if style == "realistic" else 1.0)
		if kind == "palm" or kind == "fern":
			m.set_shader_parameter("brightness", 0.95)
		if kind in ["pine", "palm"]:
			m.set_shader_parameter("translucency", 0.3)
		if _palette_name() == "alien":
			m.set_shader_parameter("emission", 0.25)
	else:
		m.shader = SHADER_SOLID_TOON if toonish else SHADER_SOLID
		if toonish:
			m.set_shader_parameter("soft", 1.0 if style == "stylized" else 0.0)
			m.set_shader_parameter("bands", 2.0 if style == "cel" else 3.0)
		var bark := _color_list("bark", pal, ["#5a4535", "#4a3a2e"])
		var rock := _color_list("rock", pal, ["#7a746a", "#6a665e"])
		m.set_shader_parameter("bark_tex", tex("bark"))
		m.set_shader_parameter("top_color", _hex(colors.get("top", pal.get("top", "#4f6a30")), Color(0.3, 0.4, 0.2)))
		match kind:
			"rock", "boulder", "pebbles":
				m.set_shader_parameter("albedo", rock[0])
				m.set_shader_parameter("albedo2", rock[1])
				m.set_shader_parameter("bark_amount", 0.0)
				m.set_shader_parameter("rock_detail", 0.0 if style == "lowpoly" else 1.0)
				m.set_shader_parameter("top_amount", float(colors.get("top_amount", pal.get("top_amount", 0.3))))
				m.set_shader_parameter("roughness_value", 0.9)
			"cactus", "barrel_cactus":
				var cac := _color_list("cactus", pal, ["#5a8a40", "#4a7a3a"])
				m.set_shader_parameter("albedo", cac[0])
				m.set_shader_parameter("albedo2", cac[1])
				m.set_shader_parameter("bark_amount", 0.25)
				m.set_shader_parameter("bark_scale", Vector2(2.0, 0.6))
				m.set_shader_parameter("top_amount", 0.0)
				m.set_shader_parameter("roughness_value", 0.6)
			"crystal":
				var cc := _hex(colors.get("crystal", pal.get("crystal", "#7a5aff")), Color(0.5, 0.35, 1.0))
				m.set_shader_parameter("albedo", cc)
				m.set_shader_parameter("albedo2", cc.lightened(0.25))
				m.set_shader_parameter("bark_amount", 0.0)
				m.set_shader_parameter("emission_color", cc)
				m.set_shader_parameter("emission_energy", 0.7)
				m.set_shader_parameter("roughness_value", 0.15)
			"mushroom":
				m.set_shader_parameter("albedo", Color(1, 1, 1))
				m.set_shader_parameter("albedo2", Color(0.9, 0.85, 0.8))
				m.set_shader_parameter("bark_amount", 0.0)
				m.set_shader_parameter("roughness_value", 0.5)
			"palm":
				m.set_shader_parameter("albedo", bark[0].lightened(0.15))
				m.set_shader_parameter("albedo2", bark[1].lightened(0.1))
				m.set_shader_parameter("ring_bands", 0.45)
				m.set_shader_parameter("bark_scale", Vector2(1.0, 0.8))
			"birch":
				m.set_shader_parameter("birch", 1.0)
				m.set_shader_parameter("albedo", bark[0])
				m.set_shader_parameter("albedo2", bark[1])
			_:
				m.set_shader_parameter("albedo", bark[0])
				m.set_shader_parameter("albedo2", bark[1])
				m.set_shader_parameter("top_amount", float(colors.get("top_amount", pal.get("top_amount", 0.3))) * 0.6)
		if style == "lowpoly":
			m.set_shader_parameter("bark_amount", 0.0)
	m.set_shader_parameter("wind_strength", wind_strength if not (kind in ["rock", "boulder", "pebbles", "crystal", "log", "stump", "mushroom"]) else 0.0)
	m.set_shader_parameter("wind_direction", wind_direction)
	m.set_shader_parameter("sway_amount", {"pine": 0.22, "palm": 0.5, "broadleaf": 0.3, "birch": 0.35, "acacia": 0.25, "bush": 0.25, "fern": 0.4, "dead_tree": 0.15}.get(kind, 0.1))
	_materials[key] = m
	return m
