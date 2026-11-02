extends Node3D
## Monta o conteúdo de jogo da receita (seção "content" de lencois.json):
## props, lumes, sementes, trampolins de água-viva, flores-canhão, fita de
## vento, portais, placas, portão-flor, correntes de ar, inimigos, totens e a
## decoração viva. Posições [x, z] encaixam no chão das ilhas por raycast.

const TERRAIN_MASK := 16

var level: Node3D
var data: Dictionary
var lume_field: LumeField
var _space: PhysicsDirectSpaceState3D
var _arenas := {}            ## arena id -> {"enemies": int, "seed": WindSeed}
var _motes: GPUParticles3D
var _kites: Array = []
var _pinwheels: Array = []
var _grass: Array[MultiMeshInstance3D] = []
var _quality := 2


func build(lv: Node3D) -> void:
	level = lv
	var builder: SoproLevelBuilder = lv.builder
	data = builder.recipe.get("content", {})
	for info in builder.islands.values():
		for mi in SoproLevelBuilder._meshes(info["node"]):
			var body := mi.get_node_or_null("Ground") as StaticBody3D
			if body != null:
				body.collision_layer = 1 | TERRAIN_MASK
	_build_now()


func ground(x: float, z: float, fallback := 2.0) -> Vector3:
	if _space == null:
		_space = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 220.0, z), Vector3(x, -120.0, z), TERRAIN_MASK)
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return Vector3(x, fallback, z)
	return hit["position"]


func pos_of(a, extra_h := 0.0) -> Vector3:
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return ground(float(a[0]), float(a[1])) + Vector3.UP * extra_h


func _build_now() -> void:
	# physics needs one step before raycasts see the island colliders
	_space = get_world_3d().direct_space_state
	var probe := ground(0, 38, -999.0)
	if probe.y < -900.0:
		await get_tree().physics_frame
		await get_tree().physics_frame
		_space = get_world_3d().direct_space_state
	var sun_dir: Vector3 = level.atmosphere.sun_direction
	_props()
	_tower()
	_seeds()
	_jellies()
	_cannons()
	_ribbons()
	_portals()
	_plates_and_gates()
	_updrafts()
	_enemies()
	_totems()
	_chimes()
	_decor(sun_dir)
	_lumes()
	_grass_fields()
	set_quality(Game.quality)
	if level.party != null and level.party.juba != null:
		var sp := pos_of(data.get("spawn", [0, 38]), 0.4)
		for h in Game.heroes:
			h.teleport(sp + h.spawn_offset + Vector3.UP * 0.3, h.facing)
		Game.checkpoint = sp + Vector3.UP * 0.5
		level.party.camera.snap_to_targets()


## Posiciona ANTES de entrar na árvore (vários nós guardam a posição inicial no _ready).
func _add(n: Node3D, p: Vector3, rot_deg := 0.0, sc := 1.0) -> Node3D:
	n.position = p
	n.rotation.y = deg_to_rad(rot_deg)
	if sc != 1.0:
		n.scale = Vector3.ONE * sc
	add_child(n)
	return n


# ---------------------------------------------------------------------------- props
func _props() -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	add_child(holder)
	for e in data.get("props", []):
		var t: String = e["type"]
		var p := pos_of(e["at"])
		var node := PropLib.make(t)
		holder.add_child(node)
		node.global_position = p + Vector3.DOWN * (0.15 if t.begins_with("rock") or t == "arch" or t == "pillar" else 0.0)
		node.rotation.y = deg_to_rad(float(e.get("rot", 0.0)))
		var sc := float(e.get("scale", 1.0))
		node.scale = Vector3.ONE * sc
		if t.begins_with("palm"):
			_palm_collision(node)
			for m in PropLib.meshes(node):
				m.visibility_range_end = 240.0
		elif t.begins_with("rock"):
			PropLib.add_collision(node, "convex")
		else:
			PropLib.add_collision(node, "trimesh")
	if data.has("spire"):
		var sp := PropLib.make("spire")
		_add(sp, pos_of(data["spire"]["at"]) + Vector3.DOWN * 0.3)
		PropLib.add_collision(sp, "trimesh")
	for e in data.get("floating_rocks", []):
		var r := PropLib.make(e.get("prop", "rock_1"))
		_add(r, pos_of(e["at"]), 0.0, float(e.get("scale", 3.0)))
		PropLib.add_collision(r, "convex")


func _palm_collision(node: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 6.0
	cs.shape = cyl
	cs.position.y = 3.0
	body.add_child(cs)
	node.add_child(body)


func _tower() -> void:
	if not data.has("tower"):
		return
	var t := BellTower.new()
	t.name = "TorreDoSino"
	_add(t, pos_of(data["tower"]["at"]) + Vector3.DOWN * 0.05)
	t.wind_returned.connect(_on_wind_returned)


# ---------------------------------------------------------------------------- seeds / arenas
func _seeds() -> void:
	for e in data.get("seeds", []):
		var s := Interactables.WindSeed.new()
		s.seed_id = e["id"]
		s.name = "Semente_" + String(e["id"])
		if e.has("gate") or e.has("arena"):
			s.hidden_until_revealed = true
		var p := pos_of(e["at"], 0.6 if e["at"].size() < 3 else 0.0)
		_add(s, p)
		if e.has("arena"):
			_arenas[e["arena"]] = {"enemies": 0, "seed": s}
		if e.has("gate"):
			s.set_meta("gate", e["gate"])


# ---------------------------------------------------------------------------- traversal
func _jellies() -> void:
	for e in data.get("jellies", []):
		var j := Interactables.JellyPad.new()
		j.size = float(e.get("size", 1.6))
		j.bob = float(e.get("bob", 0.5))
		j.power = float(e.get("power", 15.5))
		var top := pos_of(e["top"])
		j.drift = Vector3(0.6, 0, 0.6)
		_add(j, top - Vector3.UP * 1.0 * j.size)


func _cannons() -> void:
	for e in data.get("cannons", []):
		var c := Interactables.FlowerCannon.new()
		c.target = pos_of(e["target"])
		c.flight_time = float(e.get("time", 2.4))
		var p := pos_of(e["at"]) + Vector3.DOWN * 0.1
		_add(c, p)
		var to := c.target - p
		c.rotation.y = atan2(to.x, to.z)


func _ribbons() -> void:
	for e in data.get("ribbons", []):
		var r := Interactables.WindRibbon.new()
		var pts: Array[Vector3] = []
		for a in e["points"]:
			pts.append(pos_of(a))
		r.points = pts
		r.speed = float(e.get("speed", 15.0))
		add_child(r)


func _portals() -> void:
	for e in data.get("portals", []):
		var pt := Interactables.Portal.new()
		pt.add_to_group(&"portals")
		pt.exit_pos = pos_of(e["exit"])
		pt.exit_yaw = deg_to_rad(float(e.get("exit_rot", 0.0)))
		_add(pt, pos_of(e["at"]), float(e.get("rot", 0.0)))


func _plates_and_gates() -> void:
	for e in data.get("plates", []):
		var pl := Interactables.PressurePlate.new()
		pl.heavy = bool(e.get("heavy", false))
		pl.group_id = e.get("group", "g1")
		_add(pl, pos_of(e["at"]) + Vector3.DOWN * 0.08)
	for e in data.get("gates", []):
		var g := Interactables.FlowerGate.new()
		g.group_id = e.get("group", "g1")
		for s in get_tree().get_nodes_in_group(&"seeds"):
			if s.seed_id == e.get("seed", ""):
				g.seed = s
		_add(g, pos_of(e["at"]) + Vector3.DOWN * 0.1)


func _updrafts() -> void:
	for e in data.get("updrafts", []):
		var u := Interactables.Updraft.new()
		u.radius = float(e.get("radius", 3.0))
		u.height = float(e.get("height", 20.0))
		u.strength = float(e.get("strength", 30.0))
		_add(u, pos_of(e["at"]))


# ---------------------------------------------------------------------------- enemies / totems / chimes
func _enemies() -> void:
	var idx := 0
	for e in data.get("enemies", []):
		var b := Breu.new()
		b.name = "Breu_%d" % idx
		idx += 1
		var p := pos_of(e["at"])
		_add(b, p)
		if e.has("arena"):
			var aid: String = e["arena"]
			if not _arenas.has(aid):
				_arenas[aid] = {"enemies": 0, "seed": null}
			_arenas[aid]["enemies"] += 1
			b.wander_radius = 4.0
			b.defeated.connect(func(_b): _arena_enemy_down(aid))


func _arena_enemy_down(aid: String) -> void:
	var a: Dictionary = _arenas[aid]
	a["enemies"] -= 1
	if a["enemies"] <= 0 and a["seed"] != null:
		Game.show_toast("Os Breus se foram... a semente apareceu!", 2.5)
		(a["seed"] as Interactables.WindSeed).reveal()
	elif a["enemies"] > 0:
		Game.show_toast("Faltam %d Breus" % a["enemies"], 1.4)


func _totems() -> void:
	for e in data.get("totems", []):
		var t := Interactables.Totem.new()
		_add(t, pos_of(e["at"]) + Vector3.DOWN * 0.1, float(e.get("rot", 0.0)))


func _chimes() -> void:
	for a in data.get("chimes", []):
		var c := Interactables.ChimePost.new()
		_add(c, pos_of(a) + Vector3.DOWN * 0.05, randf() * 360.0)


# ---------------------------------------------------------------------------- decor
func _decor(sun_dir: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "Decoracao"
	add_child(holder)
	# festa junina: strings from the tower balcony to poles around the plaza
	var tower_at: Vector3 = pos_of(data["tower"]["at"]) if data.has("tower") else Vector3.ZERO
	for pa in data.get("flag_poles", []):
		var gp := pos_of(pa)
		holder.add_child(Decor.pole(gp, 3.4))
		var dir := Vector3(gp.x - tower_at.x, 0, gp.z - tower_at.z).normalized()
		var top := tower_at + dir * 3.75 + Vector3.UP * 16.55
		holder.add_child(Decor.flag_string(top, gp + Vector3.UP * 3.35, 1.2, 0.6))
	var poles_ab := {}
	for pair in data.get("flag_strings", []):
		var a := pos_of(pair[0])
		var b := pos_of(pair[1])
		for p in [a, b]:
			var key := "%d_%d" % [int(p.x), int(p.z)]
			if not poles_ab.has(key):
				poles_ab[key] = true
				holder.add_child(Decor.pole(p, 3.2))
		holder.add_child(Decor.flag_string(a + Vector3.UP * 3.15, b + Vector3.UP * 3.15, 0.5))
	for e in data.get("kites", []):
		var k := Decor.Kite.new()
		k.anchor = pos_of(e["at"])
		k.height = float(e.get("h", 18.0))
		var palettes := [[Color(0.95, 0.2, 0.3), Color(1.0, 0.82, 0.2), Color(0.12, 0.5, 0.95), Color(1, 1, 1)],
			[Color(0.1, 0.7, 0.4), Color(1.0, 0.9, 0.2), Color(0.1, 0.3, 0.8), Color(1, 1, 1)],
			[Color(1.0, 0.5, 0.65), Color(0.6, 0.4, 0.95), Color(1.0, 0.85, 0.3), Color(0.3, 0.85, 0.85)]]
		k.colors = palettes[_kites.size() % palettes.size()]
		k.position = k.anchor
		holder.add_child(k)
		_kites.append(k)
	for e in data.get("pinwheels", []):
		var pw := Decor.Pinwheel.new()
		pw.big = float(e.get("scale", 1.0))
		pw.spin = float(e.get("spin", 3.0))
		pw.position = pos_of(e["at"])
		pw.rotation.y = randf() * TAU
		holder.add_child(pw)
		_pinwheels.append(pw)
	for e in data.get("giant_jellies", []):
		var gj := Decor.GiantJelly.new()
		gj.center = pos_of(e["center"])
		gj.path_radius = float(e.get("radius", 150.0))
		gj.speed = float(e.get("speed", 0.02))
		gj.scale = Vector3.ONE * float(e.get("scale", 12.0))
		gj.position = gj.center
		holder.add_child(gj)
	for b in data.get("sun_beams", []):
		holder.add_child(Decor.sun_beam(pos_of(b), sun_dir, 70.0, 5.5))
	# soft cloud puffs around the islands' roots and over the cloud sea
	var pts: Array = []
	var sizes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for info in level.builder.islands.values():
		var c: Vector3 = (info["node"] as Node3D).position
		var r: float = float(info["data"]["radius"])
		for k in 7:
			var a := TAU * k / 7.0 + rng.randf() * 0.5
			pts.append(c + Vector3(cos(a) * r * rng.randf_range(0.5, 1.1), rng.randf_range(-30.0, -14.0), sin(a) * r * rng.randf_range(0.5, 1.1)))
			sizes.append(rng.randf_range(r * 0.7, r * 1.2))
	for k in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(70.0, 300.0)
		pts.append(Vector3(cos(a) * d, rng.randf_range(-32.0, -22.0), sin(a) * d))
		sizes.append(rng.randf_range(40.0, 90.0))
	var puffs := Decor.cloud_puffs(pts, sizes)
	puffs.material_override.set_shader_parameter("sun_dir", sun_dir)
	holder.add_child(puffs)
	_motes = Decor.light_motes(140)
	add_child(_motes)


func _lumes() -> void:
	var pts: Array[Vector3] = []
	for e in data.get("lumes", []):
		var n := int(e.get("n", 1))
		var h := float(e.get("h", 1.0))
		if e.has("line"):
			var a: Array = e["line"]
			for i in n:
				var t := float(i) / maxf(n - 1, 1)
				if a[0].size() >= 3:
					pts.append(pos_of(a[0]).lerp(pos_of(a[1]), t))
				else:
					var x := lerpf(float(a[0][0]), float(a[1][0]), t)
					var z := lerpf(float(a[0][1]), float(a[1][1]), t)
					pts.append(ground(x, z) + Vector3.UP * h)
		elif e.has("arc"):
			var a: Array = e["arc"]
			var peak := float(e.get("peak", 2.5))
			for i in n:
				var t := float(i) / maxf(n - 1, 1)
				var x := lerpf(float(a[0][0]), float(a[1][0]), t)
				var z := lerpf(float(a[0][1]), float(a[1][1]), t)
				pts.append(ground(x, z) + Vector3.UP * (h + sin(t * PI) * peak))
		elif e.has("circle"):
			var c: Array = e["circle"]
			var r := float(e.get("r", 3.0))
			for i in n:
				var a := TAU * i / n
				var x := float(c[0]) + cos(a) * r
				var z := float(c[1]) + sin(a) * r
				if e.has("y"):
					pts.append(Vector3(x, float(e["y"]), z))
				else:
					pts.append(ground(x, z) + Vector3.UP * h)
		elif e.has("points"):
			for a in e["points"]:
				pts.append(pos_of(a, h))
	lume_field = LumeField.new()
	lume_field.name = "Lumes"
	lume_field.add_to_group(&"lume_field")
	add_child(lume_field)
	lume_field.setup(pts)


func _grass_fields() -> void:
	var seed_v := 1
	for info in level.builder.islands.values():
		for mi in SoproLevelBuilder._meshes(info["node"]):
			var g := Decor.grass_field(mi, 2600, seed_v)
			seed_v += 1
			if g != null:
				mi.add_child(g)
				_grass.append(g)


func set_quality(q: int) -> void:
	_quality = q
	for g in _grass:
		g.multimesh.visible_instance_count = int(g.multimesh.instance_count * [0.35, 0.65, 1.0][q])
		g.visibility_range_end = [45.0, 70.0, 95.0][q]
	if _motes != null:
		_motes.amount = [50, 100, 140][q]


func _on_wind_returned() -> void:
	for k in _kites:
		k.wind = 2.2
	for p in _pinwheels:
		p.spin *= 3.0
	PropLib.shared_material("leaf").set_shader_parameter("wind_strength", 2.2)
	PropLib.shared_material("grass").set_shader_parameter("wind_strength", 3.0)
	Decor.flag_material().set_shader_parameter("wind_strength", 2.5)
	level.atmosphere.sky_material.set_shader_parameter("cloud_wind", Vector2(0.02, 0.008))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _motes != null:
		_motes.global_position = cam.global_position + (-cam.global_transform.basis.z) * 12.0
