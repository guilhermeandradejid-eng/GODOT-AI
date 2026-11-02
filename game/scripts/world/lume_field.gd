class_name LumeField
extends MultiMeshInstance3D
## Todos os lumes da fase num único MultiMesh. A coleta é por distância (sem
## corpos de física): ímã quando o herói chega perto, voo até ele, brilho,
## nota musical ascendente (filas de lumes viram melodia) e contagem no HUD.

const SHADER := preload("res://game/shaders/lume.gdshader")
const DOT := preload("res://game/assets/textures/soft_dot.png")
const MAGNET := 2.8
const PICK := 0.7

var points: Array[Vector3] = []
var alive: Array[bool] = []
var _flying := {}            ## idx -> {"t": float, "from": Vector3, "hero": Hero}
var _grid := {}              ## cell -> Array[int]
const CELL := 8.0


func setup(pts: Array[Vector3]) -> void:
	points = pts
	alive.resize(pts.size())
	alive.fill(true)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
		mm.set_instance_custom_data(i, Color(randf(), 0, 0, 0))
		var c := _cell(pts[i])
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(i)
	multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("dot_tex", DOT)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = _aabb()


func _aabb() -> AABB:
	if points.is_empty():
		return AABB()
	var a := AABB(points[0], Vector3.ZERO)
	for p in points:
		a = a.expand(p)
	return a.grow(2.0)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _physics_process(delta: float) -> void:
	for h in Game.heroes:
		if not is_instance_valid(h) or h.is_remote:
			continue
		var hp: Vector3 = h.global_position + Vector3.UP * 0.5
		var c := _cell(hp)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var lst: Array = _grid.get(c + Vector2i(dx, dz), [])
				for i in lst:
					if alive[i] and not _flying.has(i) and points[i].distance_to(hp) < MAGNET:
						_flying[i] = {"t": 0.0, "from": points[i], "hero": h}
	var done: Array = []
	for i in _flying:
		var f: Dictionary = _flying[i]
		var hero: Hero = f["hero"]
		f["t"] += delta / 0.22
		var target := hero.global_position + Vector3.UP * 0.55
		var t: float = minf(f["t"], 1.0)
		var p: Vector3 = (f["from"] as Vector3).lerp(target, t * t) + Vector3.UP * sin(t * PI) * 0.5
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * (1.0 - 0.4 * t)), p))
		if t >= 1.0 or p.distance_to(target) < PICK * 0.5:
			done.append(i)
	for i in done:
		_collect(i, _flying[i]["hero"])
		_flying.erase(i)


func _collect(i: int, hero: Hero) -> void:
	alive[i] = false
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), points[i]))
	Game.add_lumes(1)
	if has_meta("net"):
		get_meta("net").send_lume(i)
	Fx.burst("sparkle", hero.global_position + Vector3.UP * 0.6, Color(1, 0.9, 0.55), 0.5)
	Sfx.play_note("lume", hero.global_position)
	if Game.lumes % 50 == 0:
		Game.show_toast("%d lumes!" % Game.lumes, 1.5)
		hero.visual.set_happy(1.0)
		await get_tree().create_timer(0.8, false).timeout
		hero.visual.set_happy(0.0)


## Ponto de lumes extra (ex.: Breu vencido solta lumes).
func spawn_burst(at: Vector3, n: int) -> void:
	var start := points.size()
	var mm := multimesh
	var old_count := mm.instance_count
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for i in old_count:
		xforms.append(mm.get_instance_transform(i))
		customs.append(mm.get_instance_custom_data(i))
	for k in n:
		var a := TAU * k / n
		var p := at + Vector3(cos(a) * 1.4, 0.6 + randf() * 0.4, sin(a) * 1.4)
		points.append(p)
		alive.append(true)
		xforms.append(Transform3D(Basis(), p))
		customs.append(Color(randf(), 0, 0, 0))
		var c := _cell(p)
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(start + k)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	custom_aabb = _aabb()
