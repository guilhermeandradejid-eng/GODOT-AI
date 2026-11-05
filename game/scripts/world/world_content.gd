extends Node3D
## Monta o conteúdo de jogo da receita (seção "content") sobre o terreno
## contínuo: partida, props, checkpoints, relíquias, coletáveis, lançadores,
## correntes de ar, trilhos, fendas, placas/portões, travas das ferramentas
## (itens, argolas, cabos, olhos de brasa, sinos, dunas-tampão, avisos), inimigos,
## cascatas de areia e o objetivo final. Alturas vêm direto do heightfield (sem física).
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
var puzzle_groups: ToolPuzzles.PuzzleGroups
var sandfall_nodes: Array = []  ## índice da receita -> nó da cascata (SandFx.Sandfall)
var _arenas := {}               ## arena id -> {"enemies": int, "relic": Node3D, "reveal": [nós com reveal()]}
var _props_holder: Node3D
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
	puzzle_groups = ToolPuzzles.PuzzleGroups.new()
	puzzle_groups.name = "PuzzleGroups"
	add_child(puzzle_groups)
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
	_items()
	_hook_rings()
	_ziplines()
	_braziers()
	_chimes()
	_drifts()
	_hints()
	_enemies()
	_sandfalls()
	_link_veils()
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
	_props_holder = holder
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
		if e.has("gate") or e.has("arena") or e.has("group") or bool(e.get("hidden", false)):
			s.hidden_until_revealed = true
		s.veil_index = int(e.get("veil", -1))
		s.pull = bool(e.get("pull", false))
		_add(s, item_pos(e, 0.6))
		if e.has("arena"):
			_arena(e["arena"])["reveal"].append(s)
			_arenas[e["arena"]]["relic"] = s
		if e.has("group"):
			ToolPuzzles.PuzzleGroups.add_reveal(String(e["group"]), s)
		if e.has("gate"):
			s.set_meta("gate", e["gate"])


func _arena(aid: String) -> Dictionary:
	if not _arenas.has(aid):
		_arenas[aid] = {"enemies": 0, "relic": null, "reveal": []}
	return _arenas[aid]


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
	var i := 0
	for e in data.get("plates", []):
		var pl := Interactables.PressurePlate.new()
		pl.name = "Placa_%d" % i
		i += 1
		pl.heavy = bool(e.get("heavy", false))
		pl.group_id = e.get("group", "g1")
		pl.latch = bool(e.get("latch", false))
		_add(pl, item_pos(e) + Vector3.DOWN * 0.08)
	i = 0
	for e in data.get("gates", []):
		var g := Interactables.StoneGate.new()
		g.name = "Portao_%d" % i
		i += 1
		g.group_id = e.get("group", "g1")
		for s in get_tree().get_nodes_in_group(&"relics"):
			if s.seed_id == e.get("relic", ""):
				g.seed = s
		_add(g, item_pos(e) + Vector3.DOWN * 0.1, float(e.get("rot", 0.0)))


# ---------------------------------------------------------------------------- tool puzzles
## Relicários de ferramenta (itens.md 5.1). "at" [x, z] + "h" (1,0) ou [x, y, z] absoluto.
func _items() -> void:
	for e in data.get("items", []):
		var t := ToolPuzzles.ToolPedestal.new()
		t.item_id = String(e["id"])
		t.name = "Item_" + t.item_id
		var a: Array = e["at"]
		t.find_floor = a.size() >= 3
		t.item_h = 0.0 if t.find_floor else float(e.get("h", 1.0))
		t.hidden_until_revealed = e.has("group") or e.has("arena")
		_add(t, ground(float(a[0]), float(a[1])) if not t.find_floor else pos_of(a))
		if e.has("group"):
			ToolPuzzles.PuzzleGroups.add_reveal(String(e["group"]), t)
		if e.has("arena"):
			_arena(String(e["arena"]))["reveal"].append(t)


## Argolas do arpéu (5.2): swing / zip / pull; "at" sempre absoluto.
func _hook_rings() -> void:
	for e in data.get("hook_rings", []):
		var r := ToolPuzzles.HookRing.new()
		r.ring_id = String(e.get("id", ""))
		r.name = "Argola_" + r.ring_id
		r.mode = String(e.get("mode", "swing"))
		r.chain_next = String(e.get("chain_next", ""))
		r.ai = bool(e.get("ai", false))
		r.heavy = bool(e.get("heavy", false))
		r.group_id = String(e.get("group", ""))
		r.last = bool(e.get("last", false))
		r.travel = float(e.get("travel", 0.6))
		var p := pos_of(e["at"], float(e.get("h", 0.0)))
		var rot := float(e.get("rot", 0.0))
		if r.mode == "pull" and not e.has("rot"):
			# aro preso num portão: a placa do aro olha para a frente do portão
			for g in get_children():
				if g is Interactables.StoneGate and Vector2(g.position.x - p.x, g.position.z - p.z).length() < 4.0:
					rot = rad_to_deg(g.rotation.y)
		_add(r, p, rot)


## Cabos de vidro (5.3): de "from" a "to", cabo a from_h / to_h acima do chão nos postes.
func _ziplines() -> void:
	for e in data.get("ziplines", []):
		var z := ToolPuzzles.Zipline.new()
		z.zip_id = String(e.get("id", ""))
		z.name = "Cabo_" + z.zip_id
		z.from_ground = pos_of(e["from"])
		z.to_ground = pos_of(e["to"])
		z.from_h = float(e.get("from_h", 2.2))
		z.to_h = float(e.get("to_h", 3.0))
		z.min_speed = float(e.get("min_speed", 10.0))
		z.max_speed = float(e.get("max_speed", 19.0))
		z.brake = float(e.get("brake", 8.0))
		_add(z, z.from_ground)


## Olhos de Brasa (5.4).
func _braziers() -> void:
	var i := 0
	for e in data.get("braziers", []):
		var b := ToolPuzzles.Brazier.new()
		b.name = "Braseiro_%d" % i
		i += 1
		b.group_id = String(e.get("group", ""))
		b.mount = String(e.get("mount", "floor"))
		b.props_root = _props_holder
		_add(b, pos_of(e["at"], float(e.get("h", 0.0))))


## Sinos de Cristal e o Cristal-Eco (5.5).
func _chimes() -> void:
	var i := 0
	for e in data.get("chimes", []):
		var c := ToolPuzzles.Chime.new()
		c.name = "Sino_%d" % i
		c.index = i
		i += 1
		c.group_id = String(e.get("group", ""))
		c.need = Array(e.get("need", ["any"]))
		c.window = float(e.get("window", 1.2))
		c.slam_radius = float(e.get("slam_radius", 9.0))
		c.dark = bool(e.get("dark", false))
		c.latch = bool(e.get("latch", false))
		c.last = bool(e.get("last", false))
		c.size = float(e.get("size", 1.0))
		_add(c, item_pos(e), float(e.get("rot", 0.0)))


## Dunas-tampão (5.6): cobrem a placa mais próxima dentro do raio.
func _drifts() -> void:
	var i := 0
	for e in data.get("drifts", []):
		var d := ToolPuzzles.SandDrift.new()
		d.name = "Duna_%d" % i
		i += 1
		d.group_id = String(e.get("group", ""))
		d.radius = float(e.get("radius", 1.6))
		d.height = float(e.get("height", 1.2))
		var p := item_pos(e)
		var best := d.radius
		for pl in get_tree().get_nodes_in_group(&"plates"):
			if pl.get("is_plate") == true:
				var dd := Vector2(pl.global_position.x - p.x, pl.global_position.z - p.z).length()
				if dd <= best:
					best = dd
					d.covers = pl
		_add(d, p)


## Avisos de trava (5.9).
func _hints() -> void:
	var i := 0
	for e in data.get("hints", []):
		var hz := ToolPuzzles.HintZone.new()
		hz.name = "Aviso_%d" % i
		i += 1
		hz.radius = float(e.get("r", 8.0))
		hz.needs = String(e.get("needs", ""))
		hz.group_id = String(e.get("group", ""))
		hz.text = String(e.get("text", ""))
		_add(hz, item_pos(e))


# ---------------------------------------------------------------------------- enemies
func _enemies() -> void:
	var idx := 0
	for e in data.get("enemies", []):
		var b := Silente.new()
		b.name = "Inimigo_%d" % idx
		idx += 1
		b.veiled = bool(e.get("veiled", false))
		_add(b, item_pos(e))
		b.wander_radius = float(e.get("wander", 6.0))
		if e.has("arena"):
			var aid: String = e["arena"]
			_arena(aid)["enemies"] += 1
			b.defeated.connect(func(_b): _arena_enemy_down(aid))


func _arena_enemy_down(aid: String) -> void:
	var a: Dictionary = _arenas[aid]
	a["enemies"] -= 1
	if a["enemies"] <= 0 and not a["reveal"].is_empty():
		Game.show_toast("Algo apareceu!" if a["relic"] == null else "A relíquia apareceu!", 2.5)
		for n in a["reveal"]:
			if is_instance_valid(n) and n.has_method("reveal"):
				n.reveal()
		a["reveal"] = []
	elif a["enemies"] > 0:
		Game.show_toast(ARENA_TOAST % a["enemies"], 1.4)


# ---------------------------------------------------------------------------- sand
func _sandfalls() -> void:
	var sun: Color = level.atmosphere.sun.light_color if level.atmosphere != null else Color(1.0, 0.85, 0.62)
	for e in data.get("sandfalls", []):
		var top := pos_of(e["top"], float(e.get("h", 0.0)))
		var sf := SandFx.sandfall(top, float(e.get("height", 20.0)), float(e.get("width", 6.0)),
			float(e.get("facing", 0.0)), sun, level.atmosphere.sun_direction if level.atmosphere != null else Vector3(-0.45, 0.36, -0.82),
			bool(e.get("veil", false)), float(e.get("part_time", 6.0)))
		sf.name = "CascataDeAreia_%d" % sandfall_nodes.size()
		sf.set("veil_id", sandfall_nodes.size())
		add_child(sf)
		sandfall_nodes.append(sf)


## Relíquias com "veil": liga o nó da cascata (o véu fechado bloqueia o toque e o puxão).
func _link_veils() -> void:
	for s in get_tree().get_nodes_in_group(&"relics"):
		var vi: int = s.get("veil_index") if s.get("veil_index") != null else -1
		if vi >= 0 and vi < sandfall_nodes.size():
			s.veil_node = sandfall_nodes[vi]


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
