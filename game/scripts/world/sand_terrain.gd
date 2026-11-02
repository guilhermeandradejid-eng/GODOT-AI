class_name SandTerrain
extends Node3D
## Terreno contínuo do mundo, otimizado para celular:
##  * LOD contínuo estilo CDLOD (Strugar, 2009): uma quadtree escolhe nós por
##    distância à câmera; todos os nós usam a MESMA grade, desenhada por
##    MultiMesh (2 draw calls + sombras), com "morph" no vertex shader (sem
##    rachaduras nem saltos entre níveis).
##  * Alturas vêm de height.bin (gerado por game/tools/gen_terrain.py); fora do
##    mapa jogável o shader continua com dunas procedurais até o horizonte.
##  * Colisão: HeightMapShape3D com as mesmas alturas. Consultas de altura/normal
##    para a jogabilidade sem física.

signal built

const GRID_HIGH := 32                ## quads por lado da grade de um nó (qualidade alta: 1 m)
const GRID_LOW := 16                 ## celulares mais simples: 2 m perto da câmera
const LEAF_SIZE := 32.0              ## tamanho (m) do nó mais fino (1 m por vértice)
const WORLD_SPAN := 8192.0           ## área coberta pela quadtree (inclui o horizonte)

@export var data_dir := "res://game/world/aurelith_terrain"
@export var material: ShaderMaterial
@export var lod_base_range := 56.0   ## raio do LOD mais fino (dobra a cada nível)
@export var cast_shadows := true
@export var shadow_range := 90.0     ## só os nós até aqui projetam sombra (passe de sombra barato)
@export var grid := GRID_HIGH

var resolution := 0
var cell_size := 1.0
var size := 0.0
var half := 0.0
var heights := PackedFloat32Array()
var height_min := 0.0
var height_max := 0.0
var height_tex: ImageTexture
var normal_tex: Texture2D
var masks_tex: Texture2D
var _mm_full: MultiMeshInstance3D
var _mm_quad: MultiMeshInstance3D
var _sh_full: MultiMeshInstance3D
var _sh_quad: MultiMeshInstance3D
var _sel_sh_full: Array = []
var _sel_sh_quad: Array = []
var _ranges: Array[float] = []
var _levels := 0
var _last_cam := Vector3(INF, INF, INF)
var _sel_full: Array = []
var _sel_quad: Array = []
var body: StaticBody3D


func _ready() -> void:
	_load_data()
	_build_textures()
	_build_meshes()
	_build_collision()
	built.emit()


# ------------------------------------------------------------------------- data
func _load_data() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("meta.json")))
	resolution = int(meta["resolution"])
	cell_size = float(meta["cell_size"])
	size = float(meta["size"])
	half = size * 0.5
	height_min = float(meta["height_min"])
	height_max = float(meta["height_max"])
	var bytes := FileAccess.get_file_as_bytes(data_dir.path_join("height.bin"))
	heights = bytes.to_float32_array()
	if heights.size() != resolution * resolution:
		push_error("height.bin com tamanho inesperado (%d)" % heights.size())
	masks_tex = load(data_dir.path_join("masks.png"))


func _build_textures() -> void:
	var img := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, heights.to_byte_array())
	height_tex = ImageTexture.create_from_image(img)
	normal_tex = load(data_dir.path_join("normals.png"))
	if material != null:
		material.set_shader_parameter("heightmap", height_tex)
		material.set_shader_parameter("normalmap", normal_tex)
		material.set_shader_parameter("masks", masks_tex)
		material.set_shader_parameter("map_half", half)
		material.set_shader_parameter("map_res", float(resolution))
		material.set_shader_parameter("cell_size", cell_size)
		material.set_shader_parameter("height_range", Vector2(height_min, height_max))


# ------------------------------------------------------------------------- meshes
func _grid_mesh(n: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in n + 1:
		for x in n + 1:
			verts.append(Vector3(float(x) / n, 0.0, float(z) / n))
			normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	for z in n:
		for x in n:
			var a := z * (n + 1) + x
			var b := a + 1
			var c := a + n + 2
			var d := a + n + 1
			if (x + z) % 2 == 0:
				idx.append_array([a, b, c, a, c, d])
			else:
				idx.append_array([a, b, d, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_mm(grid_dim: int, label: String, shadow_only := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _grid_mesh(grid_dim)
	mm.instance_count = 512
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = label
	mi.multimesh = mm
	# instances are re-selected every rendered frame: physics interpolation would
	# blend stale node data (holes/overlaps for a frame)
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := material.duplicate() as ShaderMaterial if material != null else null
	if mat != null:
		mat.set_shader_parameter("grid_dim", float(grid_dim))
	mi.material_override = mat
	if shadow_only:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.visible = cast_shadows
	else:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-WORLD_SPAN, height_min - 200.0, -WORLD_SPAN), Vector3(WORLD_SPAN * 2.0, height_max - height_min + 400.0, WORLD_SPAN * 2.0))
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


func _build_meshes() -> void:
	_levels = int(round(log(WORLD_SPAN / LEAF_SIZE) / log(2.0)))
	_ranges.clear()
	for l in _levels + 1:
		_ranges.append(lod_base_range * pow(2.0, l))
	for mi in [_mm_full, _mm_quad, _sh_full, _sh_quad]:
		if mi != null:
			mi.queue_free()
	_mm_full = _make_mm(grid, "TerrenoNos")
	_mm_quad = _make_mm(grid / 2, "TerrenoQuadrantes")
	_sh_full = _make_mm(grid, "SombraNos", true)
	_sh_quad = _make_mm(grid / 2, "SombraQuadrantes", true)
	for mi in [_mm_full, _mm_quad, _sh_full, _sh_quad]:
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("lod_ranges_0", Vector4(_ranges[0], _ranges[1], _ranges[2], _ranges[3]))
		m.set_shader_parameter("lod_ranges_1", Vector4(_ranges[4], _ranges[5], _ranges[6], _ranges[7]))
		m.set_shader_parameter("lod_ranges_2", Vector4(_ranges[mini(8, _levels)], _ranges[mini(8, _levels)] * 2.0, 0.0, 0.0))


## Qualidade: grade (1 m ou 2 m perto da câmera), sombras e alcance do LOD.
func configure(new_grid: int, shadows: bool, base_range: float) -> void:
	var rebuild := new_grid != grid or not is_equal_approx(base_range, lod_base_range)
	grid = new_grid
	cast_shadows = shadows
	lod_base_range = base_range
	if rebuild and is_inside_tree():
		var params := {}
		if _mm_full != null:
			var m: ShaderMaterial = _mm_full.material_override
			for p in ["trail_tex", "trail_rect", "far_base", "wind_dir"]:
				params[p] = m.get_shader_parameter(p)
		_build_meshes()
		for p in params:
			set_param(p, params[p])
	for mi in [_sh_full, _sh_quad]:
		if mi != null:
			mi.visible = shadows
	_last_cam = Vector3(INF, INF, INF)


## Materiais efetivos (os MultiMesh têm cópias com grid_dim diferente).
func materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for mi in [_mm_full, _mm_quad, _sh_full, _sh_quad]:
		if mi != null and is_instance_valid(mi) and mi.material_override != null:
			out.append(mi.material_override)
	return out


func set_param(param: String, value) -> void:
	for m in materials():
		m.set_shader_parameter(param, value)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	if p.distance_squared_to(_last_cam) < 1.0:
		return
	_last_cam = p
	_select(p, cam)


func _select(cam_pos: Vector3, cam: Camera3D) -> void:
	_sel_full.clear()
	_sel_quad.clear()
	_lod_select(Vector2(-WORLD_SPAN * 0.5, -WORLD_SPAN * 0.5), WORLD_SPAN, _levels, cam_pos)
	_upload(_mm_full, _sel_full)
	_upload(_mm_quad, _sel_quad)
	if cast_shadows:
		_sel_sh_full = _sel_full.filter(func(e): return _node_min_dist(e[0], e[1], cam_pos) < shadow_range)
		_sel_sh_quad = _sel_quad.filter(func(e): return _node_min_dist(e[0], e[1], cam_pos) < shadow_range)
		_upload(_sh_full, _sel_sh_full)
		_upload(_sh_quad, _sel_sh_quad)


func _node_min_dist(origin: Vector2, s: float, cam: Vector3) -> float:
	var dx := maxf(maxf(origin.x - cam.x, 0.0), cam.x - (origin.x + s))
	var dz := maxf(maxf(origin.y - cam.z, 0.0), cam.z - (origin.y + s))
	var hy := 0.0
	if cam.y > height_max:
		hy = cam.y - height_max
	elif cam.y < height_min - 60.0:
		hy = height_min - 60.0 - cam.y
	return sqrt(dx * dx + dz * dz + hy * hy)


func _lod_select(origin: Vector2, s: float, level: int, cam: Vector3) -> bool:
	if level < _levels and _node_min_dist(origin, s, cam) > _ranges[level]:
		return false
	if level == 0:
		_sel_full.append([origin, s, level])
		return true
	if _node_min_dist(origin, s, cam) > _ranges[level - 1]:
		_sel_full.append([origin, s, level])
		return true
	var hs := s * 0.5
	for q in 4:
		var co := origin + Vector2(hs * (q % 2), hs * (q / 2))
		if not _lod_select(co, hs, level - 1, cam):
			# quadrant drawn at this node's LOD with the half-resolution grid
			_sel_quad.append([co, hs, level])
	return true


func _upload(mi: MultiMeshInstance3D, sel: Array) -> void:
	var mm := mi.multimesh
	if sel.size() > mm.instance_count:
		mm.instance_count = sel.size() + 64
	mm.visible_instance_count = sel.size()
	for i in sel.size():
		var e: Array = sel[i]
		var o: Vector2 = e[0]
		var s: float = e[1]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(o.x, o.y, s, float(e[2])))


# ------------------------------------------------------------------------- collision & queries
func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "ColisaoTerreno"
	body.collision_layer = 1 | 16
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = resolution
	shape.map_depth = resolution
	shape.map_data = heights
	cs.shape = shape
	# HeightMapShape3D is centered on the node and uses 1 unit per sample.
	cs.scale = Vector3(cell_size, 1.0, cell_size)
	body.add_child(cs)
	add_child(body)


func inside(x: float, z: float) -> bool:
	return absf(x) <= half and absf(z) <= half


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / cell_size, 0.0, resolution - 1.001)
	var fz := clampf((z + half) / cell_size, 0.0, resolution - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * resolution + x0
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + resolution]
	var h11 := heights[i + resolution + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell_size
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func slope_deg_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


## Ponto na superfície (x, z) → Vector3.
func surface(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)
