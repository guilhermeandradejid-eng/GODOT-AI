extends Node3D
## Monta o conteúdo de jogo da receita (seção "content") sobre o terreno
## contínuo: partida, props, checkpoints, relíquias, coletáveis, lançadores,
## correntes de ar, trilhos, fendas, placas/portões, inimigos, cascatas de areia
## e o objetivo final. Alturas vêm direto do heightfield (sem física).
##
## Posições: [x, z] encaixa na superfície; [x, y, z] é absoluta. Quase todo item
## aceita "h" (altura acima do chão). Pontos de trilhos podem ser [x, z, h] com
## "relative": true (h acima do chão em cada ponto).

const ARENA_TOAST := "Faltam %d"

var level: Node3D
var builder: WorldBuilder
var terrain: SandTerrain
var data: Dictionary
var menu_focus: Node3D          ## o que a câmera do menu orbita
var goal: Node3D
var mote_field: MoteField
var _arenas := {}               ## arena id -> {"enemies": int, "relic": Node3D}
var _quality := 2


func build(lv: Node3D) -> void:
	level = lv
	builder = lv.builder
	terrain = builder.terrain
	data = builder.recipe.get("content", {})
	menu_focus = Node3D.new()
	menu_focus.name = "FocoDoMenu"
	add_child(menu_focus)
	menu_focus.position = pos_of(data.get("menu_focus", data.get("spawn", [0, 0])), 4.0)
	_props()
	_goal()
	_checkpoints()
	_relics()
	_launchers()
	_bounce_pads()
	_updrafts()
	_rails()
	_rifts()
	_plates_and_gates()
	_enemies()
	_sandfalls()
	_motes()
	_place_heroes.call_deferred()
	set_quality(Game.quality)


# ---------------------------------------------------------------------------- positions
func ground(x: float, z: float) -> Vector3:
	return terrain.surface(x, z)


func pos_of(a, extra_h := 0.0) -> Vector3:
	if a is Dictionary:
		return pos_of(a.get("at", [0, 0]), float(a.get("h", extra_h)))
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return ground(float(a[0]), float(a[1])) + Vector3.UP * extra_h


## Posição de um item: "at" + "h" opcional (altura acima do chão).
func item_pos(e: Dictionary, default_h := 0.0, key := "at") -> Vector3:
	return pos_of(e[key], float(e.get("h", default_h)))


func spawn_point() -> Vector3:
	return pos_of(data.get("spawn", [0, 0]), 0.4)


func spawn_yaw() -> float:
	return deg_to_rad(float(data.get("spawn_yaw", 180.0)))


func _place_heroes() -> void:
	if level.party == null:
		return
	var sp := spawn_point()
	for h in Game.heroes:
		h.teleport(sp + h.spawn_offset + Vector3.UP * 0.3, spawn_yaw())
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
		var node := PropLib.make(t, e.get("unique", []))
		holder.add_child(node)
		node.global_position = item_pos(e) + Vector3.DOWN * float(e.get("sink", 0.0))
		node.rotation.y = deg_to_rad(float(e.get("rot", 0.0)))
		if e.has("tilt"):
			node.rotation.x = deg_to_rad(float(e["tilt"][0]))
			node.rotation.z = deg_to_rad(float(e["tilt"][1]))
		node.scale = Vector3.ONE * float(e.get("scale", 1.0))
		var vis := float(e.get("visible_to", 0.0))
		for m in PropLib.meshes(node):
			if vis > 0.0:
				m.visibility_range_end = vis
				m.visibility_range_end_margin = vis * 0.1
				m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		match String(e.get("collide", "trimesh")):
			"trimesh": PropLib.add_collision(node, "trimesh")
			"convex": PropLib.add_collision(node, "convex")
			_: pass
		if e.has("name"):
			node.name = String(e["name"])


func _goal() -> void:
	if not data.has("goal"):
		return
	var e: Dictionary = data["goal"]
	var g := VaelGate.new()
	g.name = "PortaoDeVael"
	goal = _add(g, item_pos(e), float(e.get("rot", 0.0)))
	g.finished.connect(_on_goal_complete)


func _checkpoints() -> void:
	for e in data.get("checkpoints", []):
		var t := Interactables.Waystone.new()
		_add(t, item_pos(e) + Vector3.DOWN * 0.1, float(e.get("rot", 0.0)))


# ---------------------------------------------------------------------------- relics / arenas
func _relics() -> void:
	for e in data.get("relics", []):
		var s := Interactables.Relic.new()
		s.seed_id = e["id"]
		s.name = "Reliquia_" + String(e["id"])
		if e.has("gate") or e.has("arena") or bool(e.get("hidden", false)):
			s.hidden_until_revealed = true
		_add(s, item_pos(e, 0.6))
		if e.has("arena"):
			_arenas[e["arena"]] = {"enemies": 0, "relic": s}
		if e.has("gate"):
			s.set_meta("gate", e["gate"])


# ---------------------------------------------------------------------------- traversal
func _launchers() -> void:
	for e in data.get("launchers", []):
		var c := Interactables.Launcher.new()
		c.target = pos_of(e["target"], float(e.get("target_h", 0.0)))
		c.flight_time = float(e.get("time", 2.4))
		var p := item_pos(e) + Vector3.DOWN * 0.1
		_add(c, p)
		var to := c.target - p
		c.rotation.y = atan2(to.x, to.z)


func _bounce_pads() -> void:
	for e in data.get("bounce_pads", []):
		var j := Interactables.BouncePad.new()
		j.size = float(e.get("size", 1.6))
		j.bob = float(e.get("bob", 0.0))
		j.power = float(e.get("power", 15.5))
		_add(j, item_pos(e, 0.2))


func _updrafts() -> void:
	for e in data.get("updrafts", []):
		var u := Interactables.Updraft.new()
		u.radius = float(e.get("radius", 3.0))
		u.height = float(e.get("height", 20.0))
		u.strength = float(e.get("strength", 30.0))
		_add(u, item_pos(e))


func _rails() -> void:
	for e in data.get("rails", []):
		var r := Interactables.SandRail.new()
		var pts: Array[Vector3] = []
		var rel := bool(e.get("relative", true))
		var dh := float(e.get("h", 2.5))
		for a in e["points"]:
			if rel and a.size() >= 3:
				pts.append(ground(float(a[0]), float(a[1])) + Vector3.UP * float(a[2]))
			else:
				pts.append(pos_of(a, dh))
		r.points = pts
		r.speed = float(e.get("speed", 15.0))
		add_child(r)


func _rifts() -> void:
	for e in data.get("rifts", []):
		var pt := Interactables.Portal.new()
		pt.add_to_group(&"portals")
		pt.exit_pos = pos_of(e["exit"], float(e.get("exit_h", 0.5)))
		pt.exit_yaw = deg_to_rad(float(e.get("exit_rot", 0.0)))
		_add(pt, item_pos(e), float(e.get("rot", 0.0)))


func _plates_and_gates() -> void:
	for e in data.get("plates", []):
		var pl := Interactables.PressurePlate.new()
		pl.heavy = bool(e.get("heavy", false))
		pl.group_id = e.get("group", "g1")
		_add(pl, item_pos(e) + Vector3.DOWN * 0.08)
	for e in data.get("gates", []):
		var g := Interactables.StoneGate.new()
		g.group_id = e.get("group", "g1")
		for s in get_tree().get_nodes_in_group(&"relics"):
			if s.seed_id == e.get("relic", ""):
				g.seed = s
		_add(g, item_pos(e) + Vector3.DOWN * 0.1, float(e.get("rot", 0.0)))


# ---------------------------------------------------------------------------- enemies
func _enemies() -> void:
	var idx := 0
	for e in data.get("enemies", []):
		var b := Silente.new()
		b.name = "Inimigo_%d" % idx
		idx += 1
		_add(b, item_pos(e))
		b.wander_radius = float(e.get("wander", 6.0))
		if e.has("arena"):
			var aid: String = e["arena"]
			if not _arenas.has(aid):
				_arenas[aid] = {"enemies": 0, "relic": null}
			_arenas[aid]["enemies"] += 1
			b.defeated.connect(func(_b): _arena_enemy_down(aid))


func _arena_enemy_down(aid: String) -> void:
	var a: Dictionary = _arenas[aid]
	a["enemies"] -= 1
	if a["enemies"] <= 0 and a["relic"] != null:
		Game.show_toast("A relíquia apareceu!", 2.5)
		a["relic"].reveal()
	elif a["enemies"] > 0:
		Game.show_toast(ARENA_TOAST % a["enemies"], 1.4)


# ---------------------------------------------------------------------------- sand
func _sandfalls() -> void:
	var sun: Color = level.atmosphere.sun.light_color if level.atmosphere != null else Color(1.0, 0.85, 0.62)
	for e in data.get("sandfalls", []):
		var top := pos_of(e["top"], float(e.get("h", 0.0)))
		add_child(SandFx.sandfall(top, float(e.get("height", 20.0)), float(e.get("width", 6.0)),
			float(e.get("facing", 0.0)), sun))


# ---------------------------------------------------------------------------- collectibles
func _motes() -> void:
	var pts: Array[Vector3] = []
	for e in data.get("motes", []):
		var n := int(e.get("n", 1))
		var h := float(e.get("h", 1.0))
		if e.has("line"):
			var a: Array = e["line"]
			for i in n:
				var t := float(i) / maxf(n - 1, 1)
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
				pts.append(ground(x, z) + Vector3.UP * h)
		elif e.has("points"):
			for a in e["points"]:
				pts.append(pos_of(a, h))
	mote_field = MoteField.new()
	mote_field.name = "Coletaveis"
	mote_field.add_to_group(&"motes")
	add_child(mote_field)
	mote_field.setup(pts)


# ---------------------------------------------------------------------------- misc
func set_quality(q: int) -> void:
	_quality = q


func _on_goal_complete() -> void:
	level.atmosphere.sky_material.set_shader_parameter("cloud_wind", Vector2(0.02, 0.008))
