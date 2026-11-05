class_name ToolPuzzles
extends RefCounted
## Travas e alvos das ferramentas do Sael (game/design/itens.md, seção 5).
## Cada classe interna é um Node3D autônomo, montado pelo world_content:
## relicário de ferramenta, argola do arpéu, cabo de vidro, olho de brasa, sino
## de cristal (e Cristal-Eco), duna-tampão e aviso de trava. PuzzleGroups junta as
## travas por grupo (todas entram no grupo de nós "plates", como as placas).
##
## Contrato comum das travas (`Lock`): group_id, pressed, heavy := false,
## is_plate := false, occupied_by(h) -> false, signal changed(pressed),
## signal event_fired(kind) (evento local, para a rede), apply_event(kind)
## (evento vindo da rede, sem reemitir) e force_done() (testes).
##
## Contrato dos alvos do arpéu: argolas no grupo "hook_targets" (mode swing | zip |
## pull), olhos de brasa em "braziers", cabos em "ziplines" (o HeroTools varre também
## "relics" e "enemies"). Todos têm hook_point(), can_target(by) / can_hook(by),
## los_exclude (colisores que não bloqueiam a linha de visão), set_highlight(on) e o
## efeito: on_hook_pull(by) (aro, relíquia, Silente) ou on_hook_light(by) (olho).
## A rede chama net_event(kind) (= apply_event).

const ITEM_INFO := {
	"arpeu": {"name": "Arpéu de Rumo", "hint": ["USAR: puxe-se até a argola!", "Segure USAR para balançar; PULAR solta."]},
	"bastao": {"name": "Bastão de Quilha", "hint": ["AÇÃO, AÇÃO, AÇÃO: combo de 3 golpes!", "No ar, o Rodopio quica nos Silentes."]},
	"lanterna": {"name": "Lanterna de Brasa", "hint": ["Toque no chip da lanterna para acender.", "A luz revela o que se esconde na névoa."]},
	"concha": {"name": "Concha dos Ventos", "hint": ["USAR sem alvo: uma rajada de vento.", "No ar, USAR dá a Lufada."]},
}
const BRASS := Color(0.83, 0.64, 0.25)
const CYAN := Color(0.31, 0.89, 0.84)
const AMBER := Color(1.0, 0.71, 0.35)
const LILAC := Color(0.72, 0.6, 1.0)
const SAND := Color(0.93, 0.74, 0.52)
const STAFF_KINDS := ["staff1", "staff2", "staff3", "staff_spin"]
const SLAM_KINDS := ["bump", "pound", "slam"]

static var _toast_t := {}


# ============================================================================ utilidades
static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## Aviso com limite: no máximo 1 vez a cada `every` s por texto.
static func toast_once(text: String, seconds := 2.5, every := 20.0) -> bool:
	var t := now()
	if t - float(_toast_t.get(text, -1000.0)) < every:
		return false
	_toast_t[text] = t
	Game.show_toast(text, seconds)
	return true


static func has_item(id: String) -> bool:
	if id == "":
		return true
	if Game.has_method("has_item"):
		return Game.has_item(id)
	var it = Game.get("items")
	return it is Array and id in it


## Posição da lanterna acesa (INF quando apagada ou quando o Game ainda não a tem).
static func lantern_pos() -> Vector3:
	var p = Game.get("lantern_pos")
	return p if p is Vector3 else Vector3(INF, INF, INF)


static func lantern_radius() -> float:
	var r = Game.get("lantern_radius")
	return float(r) if (r is float or r is int) else INF


static func lantern_on() -> bool:
	var p := lantern_pos()
	var r := lantern_radius()
	return p.is_finite() and is_finite(r) and r > 0.0


## Ponto dentro da luz da lanterna (raio de jogo + margem).
static func in_light(p: Vector3, margin := 0.0) -> bool:
	return lantern_on() and lantern_pos().distance_to(p) <= lantern_radius() + margin


## Cone horizontal da rajada: comprimento em 3D e ângulo medido no plano XZ.
## `slack` (m) folga o comprimento e o ângulo para alvos largos (duna, véu).
static func in_cone(origin: Vector3, dir: Vector3, p: Vector3, length: float, half_deg: float, slack := 0.0) -> bool:
	var to := p - origin
	if to.length() > length + slack or absf(to.y) > 6.0 + slack:
		return false
	var f := Vector2(dir.x, dir.z)
	var t2 := Vector2(to.x, to.z)
	if t2.length() < 0.6 + slack or f.length() < 0.01:
		return true
	var ang := rad_to_deg(absf(f.angle_to(t2)))
	return ang <= half_deg + rad_to_deg(atan2(slack, t2.length()))


static func sfx(id: String, pos: Vector3, fallback := "", pitch := 1.0, vol_db := 0.0) -> void:
	if Sfx.has(id):
		Sfx.play_at(id, pos, pitch, vol_db)
	elif fallback != "":
		Sfx.play_at(fallback, pos, pitch, vol_db)


## Prop do kit SDF, ou null se o GLB ainda não existe (a classe usa uma malha simples).
static func make_prop(prop: String, unique: Array = []) -> Node3D:
	if not ResourceLoader.exists("res://game/assets/props/%s.glb" % prop):
		return null
	return PropLib.make(prop, unique)


static func glow_of(prop: Node3D) -> ShaderMaterial:
	if prop == null or not prop.has_meta("materials"):
		return null
	return (prop.get_meta("materials") as Dictionary).get("glow")


static func emissive(col: Color, energy := 1.0, albedo := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo if albedo.a > 0.0 else col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m


static func solid(col: Color, metallic := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	return m


static func mesh_node(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func cylinder(r_top: float, r_bot: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func sphere(r: float, seg := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 4)
	return s


static func static_cylinder(parent: Node3D, r: float, h: float, y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position.y = y + h * 0.5
	body.add_child(cs)
	parent.add_child(body)
	return body


## Argola, aro ou relíquia por id ("proa_b1"...), para o `chain_next`.
static func ring(id: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(&"hook_rings"):
		if n.get("ring_id") == id:
			return n
	return null


static func solved(group: String) -> bool:
	return PuzzleGroups.solved(group)


# ============================================================================ grupos de travas
class PuzzleGroups extends Node:
	## Grupos de travas (nós do grupo "plates" com o mesmo group_id). Um grupo fica
	## resolvido (para sempre) quando todos os membros estão `pressed` ao mesmo tempo:
	## revela os itens/relíquias registrados e trava os sinos. Um nó por fase.
	signal group_solved(group: String)

	static var instance: PuzzleGroups = null
	var _solved := {}
	var _reveal := {}

	func _enter_tree() -> void:
		instance = self
		add_to_group(&"puzzle_groups")

	func _exit_tree() -> void:
		if instance == self:
			instance = null

	func _ready() -> void:
		# membros criados antes deste nó (ou sem chamar watch) entram no próximo quadro
		await get_tree().process_frame
		for n in get_tree().get_nodes_in_group(&"plates"):
			watch(n)

	static func _tree() -> SceneTree:
		return Engine.get_main_loop() as SceneTree

	## Travas e placas de um grupo.
	static func members(group: String) -> Array:
		var out: Array = []
		var tree := _tree()
		if tree == null or group == "":
			return out
		for n in tree.get_nodes_in_group(&"plates"):
			if not n.is_queued_for_deletion() and String(n.get("group_id")) == group:
				out.append(n)
		return out

	## Todos os outros membros do grupo de `node` estão feitos (para as travas `last`).
	static func done_except(node: Node) -> bool:
		for m in members(String(node.get("group_id"))):
			if m != node and not m.pressed:
				return false
		return true

	static func solved(group: String) -> bool:
		if group == "":
			return false
		if instance != null:
			return instance._solved.has(group)
		var ms := members(group)
		return not ms.is_empty() and ms.all(func(m): return m.pressed)

	## Passa a acompanhar o sinal `changed` de uma trava (idempotente).
	static func watch(node: Node) -> void:
		if instance == null or not node.has_signal("changed"):
			return
		var cb := instance._on_member_changed.bind(node)
		if not node.is_connected("changed", cb):
			node.connect("changed", cb)

	## Nó com reveal() que aparece quando o grupo for resolvido.
	static func add_reveal(group: String, node: Node) -> void:
		if instance == null or group == "":
			return
		if instance._solved.has(group):
			if node.has_method("reveal"):
				node.reveal()
			return
		if not instance._reveal.has(group):
			instance._reveal[group] = []
		instance._reveal[group].append(node)

	static func notify(group: String) -> void:
		if instance != null:
			instance._check(group)

	## Resolve à força (testes / rede).
	static func force_solve(group: String) -> void:
		if instance != null and not instance._solved.has(group):
			instance._solve(group)

	func _on_member_changed(_pressed: bool, node: Node) -> void:
		_check(String(node.get("group_id")))

	func _check(group: String) -> void:
		if group == "" or _solved.has(group):
			return
		var ms := members(group)
		if ms.is_empty():
			return
		for m in ms:
			if not m.pressed:
				return
		_solve(group)

	func _solve(group: String) -> void:
		_solved[group] = true
		var at := Vector3.ZERO
		var ms := members(group)
		for m in ms:
			at += (m as Node3D).global_position / ms.size()
			if m.has_method("lock_solved"):
				m.lock_solved()
		ToolPuzzles.sfx("chord_solved", at, "reveal")
		group_solved.emit(group)
		for n in _reveal.get(group, []):
			if is_instance_valid(n) and n.has_method("reveal"):
				n.reveal()
		_reveal.erase(group)


# ============================================================================ base das travas
class Lock extends Node3D:
	## Trava genérica do grupo "plates" (is_plate = false: a IA e os testes de placa a ignoram).
	signal changed(pressed: bool)
	signal event_fired(kind: String)
	var group_id := ""
	var pressed := false
	var heavy := false
	var is_plate := false
	var joins_plates := true
	var _remote := false

	func _ready() -> void:
		add_to_group(&"puzzle_nodes")
		if joins_plates and group_id != "":
			add_to_group(&"plates")
			PuzzleGroups.watch(self)

	func occupied_by(_h) -> bool:
		return false

	func _set_pressed(v: bool) -> void:
		if pressed == v:
			return
		pressed = v
		changed.emit(v)

	## Evento nascido aqui (a rede repassa); não reemite eventos vindos da rede.
	func _fire(kind: String) -> void:
		if not _remote:
			event_fired.emit(kind)

	## Evento vindo da rede (`_puzzle_event`): aplica sem reemitir.
	func apply_event(kind: String) -> void:
		_remote = true
		_on_event(kind)
		_remote = false

	func net_event(kind: String) -> void:
		apply_event(kind)

	## "latched" (grupo resolvido no anfitrião) vale para qualquer trava: fica feita.
	func _on_event(kind: String) -> void:
		if kind == "latched":
			force_done()

	func force_done() -> void:
		_set_pressed(true)

	func _done_others() -> bool:
		return PuzzleGroups.done_except(self)


# ============================================================================ relicário de ferramenta
class ToolPedestal extends Node3D:
	## Pedestal de arenito com a ferramenta flutuando. Só o Sael pega (o inventário
	## Game.items é da dupla, mas as ferramentas são dele). Com group/arena fica
	## escondido até o grupo ser resolvido ou a arena ser limpa.
	signal taken(id: String)
	const PICK_R := 1.2
	var item_id := "arpeu"
	var item_h := 1.0                   ## altura do item acima da base
	var find_floor := false             ## "at" absoluto: a base desce até o chão por raio
	var hidden_until_revealed := false
	var is_taken := false
	var _item: Node3D
	var _base: Node3D
	var _holder: Node3D
	var _t := 0.0
	var _rising := false
	var _body: StaticBody3D

	func _ready() -> void:
		add_to_group(&"tool_pedestals")
		add_to_group(&"puzzle_nodes")
		_holder = Node3D.new()
		add_child(_holder)
		_base = ToolPuzzles.make_prop("relicario")
		if _base == null:
			_base = Node3D.new()
			_base.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.3, 0.38, 0.8), PropLib.shared_material("stone"), Vector3(0, 0.4, 0)))
			_base.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.36, 0.34, 0.1), ToolPuzzles.solid(Color(0.17, 0.23, 0.53)), Vector3(0, 0.85, 0)))
			_base.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.39, 0.39, 0.04), ToolPuzzles.solid(ToolPuzzles.BRASS, 0.8, 0.35), Vector3(0, 0.9, 0)))
		_holder.add_child(_base)
		_item = ToolPuzzles.make_prop("item_" + item_id, ["glow"])
		if _item == null:
			_item = _fallback_item(item_id)
		_item.position.y = item_h
		_holder.add_child(_item)
		if not find_floor:
			_body = ToolPuzzles.static_cylinder(_base, 0.36, 0.9)
		if Game.has_signal("item_collected"):
			Game.connect("item_collected", _on_collected)
		if ToolPuzzles.has_item(item_id):
			_vanish(false)
		elif hidden_until_revealed:
			visible = false
		_set_solid(not hidden_until_revealed)
		if find_floor:
			_drop_base.call_deferred()

	## Escondido, o pedestal não pode virar um obstáculo invisível.
	func _set_solid(on: bool) -> void:
		if _body != null:
			_body.collision_layer = 1 if on else 0

	## Item absoluto (ex.: na palma do colosso): a base fica no chão logo abaixo, se houver.
	func _drop_base() -> void:
		await get_tree().physics_frame
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 3.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			_base.visible = false
			return
		var floor_y: float = (hit["position"] as Vector3).y
		if global_position.y - floor_y < 1.05:
			_base.visible = false     # sem espaço para o pedestal: o item flutua sozinho
			return
		_base.position.y = floor_y - global_position.y
		_body = ToolPuzzles.static_cylinder(_base, 0.36, 0.9)
		_set_solid(not hidden_until_revealed)

	static func _fallback_item(id: String) -> Node3D:
		var n := Node3D.new()
		var brass := ToolPuzzles.solid(ToolPuzzles.BRASS, 0.85, 0.3)
		match id:
			"arpeu":
				var t := TorusMesh.new()
				t.inner_radius = 0.07
				t.outer_radius = 0.13
				var coil := ToolPuzzles.mesh_node(t, ToolPuzzles.solid(Color(0.55, 0.25, 0.18)))
				coil.rotation.x = PI * 0.5
				n.add_child(coil)
				for k in 3:
					var c := ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.0, 0.025, 0.16, 6), brass)
					var a := TAU * k / 3.0
					c.position = Vector3(cos(a) * 0.07, 0.14, sin(a) * 0.07)
					c.rotation = Vector3(sin(a) * 0.6, 0, -cos(a) * 0.6)
					n.add_child(c)
			"bastao":
				var s := ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.025, 0.03, 0.95, 8), ToolPuzzles.solid(Color(0.86, 0.72, 0.52)))
				s.rotation.z = 0.5
				s.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.035, 0.03, 0.08, 8), brass, Vector3(0, 0.47, 0)))
				n.add_child(s)
			"lanterna":
				n.add_child(ToolPuzzles.mesh_node(ToolPuzzles.sphere(0.08), ToolPuzzles.emissive(ToolPuzzles.AMBER, 2.0)))
				n.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.1, 0.1, 0.02), brass, Vector3(0, 0.1, 0)))
				n.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.1, 0.1, 0.02), brass, Vector3(0, -0.1, 0)))
			_:
				var sh := ToolPuzzles.mesh_node(ToolPuzzles.sphere(0.11), ToolPuzzles.solid(Color(1.0, 0.78, 0.78), 0.2, 0.25))
				sh.scale = Vector3(1.0, 0.75, 1.3)
				n.add_child(sh)
				var tip := ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.0, 0.05, 0.12, 8), brass, Vector3(0, 0, -0.16))
				tip.rotation.x = -PI * 0.5
				n.add_child(tip)
		return n

	## Aparece como a relíquia: escala elástica (0,8 s) e sobe 1,5 m em 1,2 s.
	func reveal() -> void:
		if is_taken or (visible and not hidden_until_revealed):
			return
		hidden_until_revealed = false
		visible = true
		_set_solid(true)
		_rising = true
		_holder.position.y = -1.5
		_holder.scale = Vector3.ONE * 0.01
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_holder, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_holder, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func(): _rising = false)
		Fx.burst("relic", global_position + Vector3.UP * item_h, Color(0, 0, 0, 0), 0.7)
		Fx.burst("dust_ring", global_position + Vector3.UP * 0.2, Color(0, 0, 0, 0), 1.2)
		Sfx.play_at("reveal", global_position)

	func item_world_pos() -> Vector3:
		return _item.global_position if _item != null else global_position + Vector3.UP * item_h

	func _physics_process(delta: float) -> void:
		_t += delta
		if _item == null or is_taken:
			return
		_item.rotation.y += delta * 1.4
		_item.position.y = item_h + sin(_t * 2.0) * 0.12
		if not visible or hidden_until_revealed or _rising:
			return
		var ip := item_world_pos()
		for h in Game.heroes:
			if not is_instance_valid(h) or h.is_remote:
				continue
			var d: Vector3 = h.global_position - ip
			if Vector2(d.x, d.z).length() > PICK_R or d.y < -2.3 or d.y > 0.9:
				continue
			if h.hero_id != "agile":
				ToolPuzzles.toast_once("Isso é do %s!" % HeroDefs.display_name("agile"), 2.0, 8.0)
				continue
			take(h)
			return

	## O Sael pega a ferramenta: Game.give_item, os dois comemoram e a faixa aparece (HUD).
	func take(h) -> void:
		if is_taken:
			return
		is_taken = true
		var info: Dictionary = ToolPuzzles.ITEM_INFO.get(item_id, {"name": item_id, "hint": []})
		if Game.has_method("give_item"):
			Game.give_item(item_id)
		else:
			var it = Game.get("items")
			if it is Array and not item_id in it:
				it.append(item_id)
		if not Game.has_signal("item_collected"):
			var lines: Array = info["hint"]
			Game.show_toast("Você encontrou: %s\n%s" % [info["name"], "\n".join(lines)], 4.0)
		var p := item_world_pos()
		Fx.burst("relic", p)
		Fx.burst("ring_light", p, ToolPuzzles.BRASS, 1.4)
		ToolPuzzles.sfx("item_get", p, "relic")
		Game.vibrate(60)
		for hero in Game.heroes:
			if is_instance_valid(hero) and not hero.is_remote and hero.visual != null:
				if hero.visual.has_state("celebrate") and hero.state in [Hero.S.GROUND, Hero.S.RIDE, Hero.S.SWIM]:
					hero.visual.restart_state("celebrate")
				hero.visual.set_happy(1.0)
		taken.emit(item_id)
		_vanish(true, h)
		await get_tree().create_timer(1.2, false).timeout
		for hero in Game.heroes:
			if is_instance_valid(hero) and hero.visual != null:
				hero.visual.set_happy(0.0)
				if hero.state == Hero.S.GROUND and hero.visual.state == "celebrate":
					hero.visual.set_state("loco")

	func _on_collected(id: String) -> void:
		if id == item_id and not is_taken:
			is_taken = true
			_vanish(true)

	func apply_event(kind: String) -> void:
		if kind == "taken":
			take_remote()

	## O parceiro pegou (RPC `_item_taken`): some sem comemorar aqui.
	func take_remote() -> void:
		if not is_taken:
			is_taken = true
			_vanish(true)

	func _vanish(anim: bool, to = null) -> void:
		is_taken = true
		if _item == null:
			return
		if not anim:
			_item.visible = false
			return
		var tw := create_tween()
		if to != null and is_instance_valid(to):
			tw.tween_property(_item, "global_position", (to as Node3D).global_position + Vector3.UP * 1.0, 0.3)
		tw.tween_property(_item, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(func(): _item.visible = false)


# ============================================================================ argola do arpéu
class HookRing extends Lock:
	## Argola de latão (grupo "hook_targets"). swing: âncora do pêndulo; zip: puxa-se
	## e salta por cima; pull: aro preso num objeto, desliza `travel` m e trava (é
	## membro do grupo; com heavy só o Sael no cesto do Hulvar consegue, o Reboque).
	const RANGES := {"swing": 14.0, "zip": 20.0, "pull": 12.0}
	var ring_id := ""
	var mode := "swing"
	var chain_next := ""
	var ai := false
	var last := false
	var travel := 0.6
	var hook_mode := "swing"
	var hook_range := 14.0
	var _prop: Node3D
	var _glow: ShaderMaterial
	var _mat: StandardMaterial3D
	var _hl := false
	var _avail := true
	var _pulling := false
	var _poll := 0.0
	var _exclude: Array[RID] = []
	var _exclude_done := false
	var los_exclude: Array[RID]:
		get:
			return hook_exclude()

	func _ready() -> void:
		hook_mode = mode
		hook_range = RANGES.get(mode, 14.0)
		joins_plates = mode == "pull"
		super._ready()
		add_to_group(&"hook_targets")
		add_to_group(&"hook_rings")
		_prop = ToolPuzzles.make_prop("aro_puxar" if mode == "pull" else "argola", ["glow"])
		if _prop == null:
			_prop = Node3D.new()
			var t := TorusMesh.new()
			var r := 0.3 if mode == "pull" else 0.55
			t.inner_radius = r - (0.07 if mode == "pull" else 0.05)
			t.outer_radius = r
			t.rings = 24
			t.ring_segments = 8
			var ring := ToolPuzzles.mesh_node(t, ToolPuzzles.solid(ToolPuzzles.BRASS, 0.85, 0.3))
			ring.rotation.x = PI * 0.5
			_prop.add_child(ring)
			_mat = ToolPuzzles.emissive(ToolPuzzles.CYAN, 0.25)
			for k in 3:
				var a := TAU * k / 3.0 + PI * 0.5
				_prop.add_child(ToolPuzzles.mesh_node(ToolPuzzles.sphere(0.06 if mode != "pull" else 0.05, 8), _mat, Vector3(cos(a) * r, sin(a) * r, 0)))
		add_child(_prop)
		# aro_puxar: a origem é o verso da placa; o ponto do arpéu é o "grab"
		var grab := _prop.find_child("grab", true, false) as Node3D
		if grab != null:
			_prop.position = -PropLib.rel_xform(grab, _prop).origin
		_glow = ToolPuzzles.glow_of(_prop)
		if _glow != null:
			_glow.set_shader_parameter("tint", ToolPuzzles.CYAN)
		elif _mat == null:
			# prop sem peça glow: um halo fino mostra quando o aro pode ser puxado
			var t := TorusMesh.new()
			t.inner_radius = 0.15
			t.outer_radius = 0.17
			_mat = ToolPuzzles.emissive(ToolPuzzles.CYAN, 0.25)
			var halo := ToolPuzzles.mesh_node(t, _mat, Vector3(0, 0, 0.03))
			halo.rotation.x = PI * 0.5
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(halo)
		_avail = not last
		_apply_glow()

	func hook_point() -> Vector3:
		return global_position

	func can_hook(_by = null) -> bool:
		if not visible:
			return false
		if mode == "pull":
			return not pressed and not _pulling and (not last or _done_others())
		return true

	func can_target(by = null) -> bool:
		return can_hook(by)

	## Colisores do objeto em que o aro está preso (e do próprio aro): não bloqueiam a mira.
	func hook_exclude() -> Array[RID]:
		if not _exclude_done and is_inside_tree():
			_exclude_done = true
			var q := PhysicsShapeQueryParameters3D.new()
			var s := SphereShape3D.new()
			s.radius = 1.2
			q.shape = s
			q.transform = Transform3D(Basis.IDENTITY, global_position)
			q.collision_mask = 1
			for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
				var col = r.get("collider")
				if col is CollisionObject3D and not (col as Node).get_parent() is SandTerrain:
					_exclude.append((col as CollisionObject3D).get_rid())
		return _exclude

	func set_highlight(on: bool) -> void:
		_hl = on
		_apply_glow()

	func _apply_glow() -> void:
		var v := 0.0 if not _avail else (1.0 if (_hl or pressed) else 0.25)
		if _glow != null:
			_glow.set_shader_parameter("active", v)
		if _mat != null:
			_mat.emission_energy_multiplier = 0.1 + v * 2.0

	func _physics_process(delta: float) -> void:
		if not last or pressed:
			return
		_poll -= delta
		if _poll > 0.0:
			return
		_poll = 0.25
		var now_ok := _done_others()
		if now_ok != _avail:
			_avail = now_ok
			_apply_glow()
			if now_ok:
				Fx.burst("sparkle", global_position, ToolPuzzles.CYAN, 1.0)
				Sfx.play_at("reveal", global_position, 1.2, -4.0)

	## Ao prender o gancho. swing/zip: só o retorno (o movimento é do herói); pull: puxa.
	func on_hook(by) -> bool:
		if mode == "pull":
			return on_hook_pull(by)
		Fx.burst("sparkle", global_position, ToolPuzzles.BRASS, 0.6)
		ToolPuzzles.sfx("hook_lock", global_position, "plate_on", 1.2, -3.0)
		return true

	## Puxar o aro. Devolve false se ainda não pode (last) ou se for pesado demais.
	## No Reboque o herói faz o brace do Hulvar (1,2 s) e chama isto no fim: o aro só
	## desliza e trava.
	func on_hook_pull(by) -> bool:
		if mode != "pull" or not can_hook(by):
			return false
		if heavy and not (by != null and is_instance_valid(by) and by.has_method("is_heavy") and by.is_heavy()):
			ToolPuzzles.toast_once("Pesado demais... puxe do cesto do %s!" % HeroDefs.display_name("strong"), 2.5, 4.0)
			ToolPuzzles.sfx("rope_creak", global_position, "plate_off", 0.8)
			var tw0 := create_tween()
			tw0.tween_property(_prop, "position", Vector3(0, 0, 0.08), 0.12)
			tw0.tween_property(_prop, "position", Vector3.ZERO, 0.25)
			return false
		_pulling = true
		var dur := 0.35 if heavy else 0.45
		var dir := Vector3.FORWARD
		if by != null and is_instance_valid(by):
			dir = (by as Node3D).global_position - global_position
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		ToolPuzzles.sfx("rope_creak", global_position, "plate_on", 1.0)
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + dir * travel, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(_finish_pull)
		return true

	func _finish_pull() -> void:
		if pressed:
			return
		_pulling = false
		Fx.burst("sparkle", global_position, ToolPuzzles.BRASS, 1.0)
		Fx.burst("dust", global_position, Color(0, 0, 0, 0), 1.2)
		Sfx.play_at("plate_on", global_position)
		get_tree().call_group(&"cameras", &"shake", 0.2)
		_set_pressed(true)
		_apply_glow()
		_fire("pulled")

	func _on_event(kind: String) -> void:
		if kind in ["pulled", "latched"]:
			_finish_pull()

	func force_done() -> void:
		if mode == "pull":
			_finish_pull()

	func force_pull() -> void:
		force_done()


# ============================================================================ cabo de vidro
class Zipline extends Interactables.SandRail:
	## Cabo reto entre dois postes que só o Arpéu agarra (o Hulvar não usa). O herói
	## fica pendurado `hang` m abaixo do cabo; ver advance() para o modelo de velocidade.
	signal event_fired(kind: String)
	const GRAB_POST := 6.0
	const GRAB_AIR := 2.0
	const GRAB_FRACTION := 0.7
	var zip_id := ""
	var from_ground := Vector3.ZERO     ## chão no poste inicial
	var to_ground := Vector3.ZERO       ## chão no poste final
	var from_h := 2.2
	var to_h := 3.0
	var min_speed := 10.0
	var max_speed := 19.0
	var brake := 8.0
	var hang := 1.15
	var requires := "arpeu"
	var _beads: MultiMeshInstance3D

	func _ready() -> void:
		var pts: Array[Vector3] = [from_ground + Vector3.UP * from_h, to_ground + Vector3.UP * to_h]
		points = pts
		speed = min_speed
		add_to_group(&"ziplines")
		add_to_group(&"puzzle_nodes")
		super._ready()
		var m := ToolPuzzles.solid(Color(0.75, 0.9, 0.95), 0.3, 0.2)
		m.emission_enabled = true
		m.emission = ToolPuzzles.CYAN
		m.emission_energy_multiplier = 0.25
		_mi.material_override = m
		_add_beads()
		_add_post(from_ground, from_h, to_ground)
		_add_post(to_ground, to_h, from_ground)

	## Faixa trançada de 3 cm (duas fitas cruzadas) no lugar da fita larga do SandRail.
	func _strip() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := curve.sample_baked(0.0)
		var b := curve.sample_baked(length())
		var tan := (b - a).normalized()
		var side := tan.cross(Vector3.UP).normalized() * 0.015
		var up := side.cross(tan).normalized() * 0.015
		for off in [side, up]:
			st.add_vertex(a - off); st.add_vertex(a + off); st.add_vertex(b + off)
			st.add_vertex(a - off); st.add_vertex(b + off); st.add_vertex(b - off)
		st.generate_normals()
		return st.commit()

	func _add_beads() -> void:
		var L := length()
		var n := int(L / 4.0)
		if n <= 0:
			return
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ToolPuzzles.sphere(0.05, 8)
		mm.instance_count = n
		for i in n:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, curve.sample_baked((i + 0.5) * L / n)))
		_beads = MultiMeshInstance3D.new()
		_beads.multimesh = mm
		_beads.material_override = ToolPuzzles.emissive(ToolPuzzles.CYAN, 1.2)
		_beads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beads)

	## Poste ("cabeco" 3,0 m / "cabeco_baixo" 2,2 m) com colisão; o aro do topo segura o cabo.
	func _add_post(g: Vector3, h: float, other: Vector3) -> void:
		var low := h < 2.6
		var post := ToolPuzzles.make_prop("cabeco_baixo" if low else "cabeco")
		if post == null and low:
			post = ToolPuzzles.make_prop("cabeco")
			low = false
		if post == null:
			post = Node3D.new()
			post.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.12, 0.16, h), PropLib.shared_material("bronze"), Vector3(0, h * 0.5, 0)))
			var t := TorusMesh.new()
			t.inner_radius = 0.1
			t.outer_radius = 0.17
			post.add_child(ToolPuzzles.mesh_node(t, ToolPuzzles.solid(ToolPuzzles.BRASS, 0.85, 0.3), Vector3(0, h, 0)))
		else:
			var ph := 2.2 if low else 3.0
			var cable := post.find_child("cable", true, false) as Node3D
			if cable != null:
				ph = maxf(PropLib.rel_xform(cable, post).origin.y, 0.5)
			post.scale = Vector3.ONE * (h / ph)
		add_child(post)
		post.global_position = g + Vector3.DOWN * 0.05
		var to := other - g
		post.rotation.y = atan2(to.x, to.z)
		ToolPuzzles.static_cylinder(post, 0.16, h)

	## Desliga a captura automática do SandRail: quem prende é o USAR do herói.
	func _physics_process(_delta: float) -> void:
		if Engine.get_physics_frames() % 15 != 0:
			return
		for h in Game.heroes:
			if is_instance_valid(h) and not h.is_remote and h.hero_id == "strong" \
					and h.global_position.distance_to(from_ground) < 3.0:
				ToolPuzzles.toast_once("O cabo é fino demais para o %s" % HeroDefs.display_name("strong"), 2.0, 15.0)

	## Offset do cabo onde o herói pode prender, ou -1. No chão: a até 6 m do poste
	## inicial; no ar: a até 2 m do cabo nos primeiros 70% dele.
	func grab_offset(pos: Vector3, airborne: bool) -> float:
		if pos.distance_to(from_ground) <= GRAB_POST:
			return 0.0
		if not airborne:
			return -1.0
		var local: Vector3 = global_transform.affine_inverse() * (pos + Vector3.UP * hang)
		var off := curve.get_closest_offset(local)
		if off > length() * GRAB_FRACTION:
			return -1.0
		return off if curve.sample_baked(off).distance_to(local) <= GRAB_AIR else -1.0

	func can_grab(hero) -> bool:
		if hero == null or hero.hero_id != "agile" or not ToolPuzzles.has_item(requires):
			return false
		var air: bool = not (hero.state in [Hero.S.GROUND, Hero.S.SURF, Hero.S.SWIM])
		return grab_offset(hero.global_position, air) >= 0.0

	## Pés do herói pendurado no offset.
	func hang_point(off: float) -> Vector3:
		return transform_at(off).origin + Vector3.DOWN * hang

	func start_speed(entry: float) -> float:
		return clampf(maxf(entry, min_speed), min_speed, max_speed)

	## Um passo do modelo de velocidade: ganha 30·sinθ·0,78 por s na descida, perde
	## 4%/s, fica entre min e max; nos últimos `brake` m freia até 6 m/s.
	func advance(v: float, off: float, delta: float) -> float:
		var t := tangent_at(off)
		v += 30.0 * (-t.y) * 0.78 * delta
		v *= 1.0 - 0.04 * delta
		v = clampf(v, min_speed, max_speed)
		var left := length() - off
		if left < brake:
			var v_cap := lerpf(6.0, max_speed, clampf(left / maxf(brake, 0.01), 0.0, 1.0))
			v = minf(v, maxf(v_cap, 6.0))
		return v

	## Saída no fim do cabo (o herói chama launch(…, 0.2)).
	func exit_velocity(v: float) -> Vector3:
		return tangent_at(length()) * v + Vector3.UP * 6.0


# ============================================================================ olho de brasa
class Brazier extends Lock:
	## Trava acesa pela lanterna: a até 1,6 m por 0,15 s, ou por Lançar a Luz (arpéu
	## com a lanterna acesa, 14 m). Acesa para sempre. Só emissivo (sem OmniLight).
	const LIGHT_R := 1.6
	const LIGHT_T := 0.15
	var mount := "floor"
	var props_root: Node3D             ## onde procurar o prop anfitrião (mount "wall")
	var mode := "light"
	var hook_mode := "light"
	var hook_range := 14.0
	var lit: bool:
		get:
			return pressed
	var los_exclude: Array[RID]:
		get:
			return hook_exclude()
	var _near_t := 0.0
	var _mat: StandardMaterial3D
	var _glow: ShaderMaterial
	var _prop: Node3D
	var _hl := false
	var _lighting := false
	var _ember := 0.0
	var _exclude: Array[RID] = []
	var _exclude_done := false

	func _ready() -> void:
		super._ready()
		add_to_group(&"braziers")
		_prop = ToolPuzzles.make_prop("braseiro", ["glow"])
		_glow = ToolPuzzles.glow_of(_prop)
		if _prop == null or _glow == null:
			if _prop == null:
				_prop = Node3D.new()
			var bowl := ToolPuzzles.mesh_node(ToolPuzzles.sphere(0.42, 16), null)
			_mat = ToolPuzzles.emissive(ToolPuzzles.AMBER, 0.0, Color(0.35, 0.18, 0.08))
			_mat.metallic_specular = 0.8
			_mat.roughness = 0.15
			bowl.material_override = _mat
			bowl.scale = Vector3(1.0, 0.7, 1.0)
			_prop.add_child(bowl)
		else:
			_prop.position.y = -0.2     # origem do braseiro é o fundo da tigela
		add_child(_prop)
		_set_emission(0.0)

	func _set_emission(e: float) -> void:
		if _glow != null:
			_glow.set_shader_parameter("tint", ToolPuzzles.AMBER)
			_glow.set_shader_parameter("active", clampf(e / 2.0, 0.0, 1.0))
		if _mat != null:
			_mat.emission_energy_multiplier = e

	func hook_point() -> Vector3:
		return global_position

	## Alvo de Lançar a Luz: só apagado e com a lanterna acesa.
	func can_hook(_by = null) -> bool:
		return not pressed and not _lighting and ToolPuzzles.lantern_on()

	func can_target(by = null) -> bool:
		return can_hook(by)

	## mount "wall": o colisor do prop mais próximo (até 6 m) não bloqueia a mira.
	func hook_exclude() -> Array[RID]:
		if _exclude_done or not is_inside_tree():
			return _exclude
		_exclude_done = true
		if mount != "wall" or props_root == null:
			return _exclude
		var best: Node3D = null
		var bd := 6.0
		for p in props_root.get_children():
			if not p is Node3D:
				continue
			for mi in PropLib.meshes(p):
				var box: AABB = mi.global_transform * mi.get_aabb()
				var d := _aabb_dist(box, global_position)
				if d < bd:
					bd = d
					best = p
		if best != null:
			for c in best.get_children():
				if c is CollisionObject3D:
					_exclude.append((c as CollisionObject3D).get_rid())
		return _exclude

	static func _aabb_dist(b: AABB, p: Vector3) -> float:
		var q := p.clamp(b.position, b.end)
		return q.distance_to(p)

	func set_highlight(on: bool) -> void:
		_hl = on
		if not pressed and not _lighting:
			_set_emission(0.35 if on else 0.0)

	func on_hook(by) -> bool:
		return on_hook_light(by)

	## Lançar a Luz: o herói corre a chama pela corda (0,4 s) e chama isto quando ela
	## chega ao olho.
	func on_hook_light(_by = null) -> bool:
		if pressed:
			return false
		light()
		return true

	func _physics_process(delta: float) -> void:
		if pressed:
			_ember -= delta
			if _ember <= 0.0:
				_ember = randf_range(0.8, 1.8)
				Fx.burst("sparkle", global_position + Vector3.UP * 0.3, ToolPuzzles.AMBER, 0.4)
			return
		if ToolPuzzles.lantern_on() and ToolPuzzles.lantern_pos().distance_to(global_position) <= LIGHT_R:
			_near_t += delta
			if _near_t >= LIGHT_T:
				light()
		else:
			_near_t = 0.0

	## Acende: emissivo de 0 a 2,0 em 0,6 s, chama pequena e brasas ocasionais.
	func light() -> void:
		if pressed:
			return
		_lighting = false
		create_tween().tween_method(_set_emission, 0.0, 2.0, 0.6)
		Fx.burst("fire", global_position, ToolPuzzles.AMBER, 0.6)
		Fx.burst("sparkle", global_position + Vector3.UP * 0.2, ToolPuzzles.AMBER, 1.2)
		Fx.burst("ring_light", global_position, ToolPuzzles.AMBER, 0.8)
		ToolPuzzles.sfx("ember_ignite", global_position, "checkpoint")
		Game.vibrate(25)
		_set_pressed(true)
		_fire("lit")

	func _on_event(kind: String) -> void:
		if kind in ["lit", "latched"]:
			light()

	func force_done() -> void:
		light()


# ============================================================================ sino de cristal / Cristal-Eco
class Chime extends Lock:
	## Recebe golpes (on_attack) e Barrigadas (on_pound). Cada tipo de `need` fica
	## marcado por `window` s; com todos marcados o sino toca e fica pressed por
	## `window` s (ou para sempre com latch). Os sinos travam quando o grupo resolve.
	## dark: só aceita golpes dentro da luz da lanterna. last: inerte até o resto do grupo.
	signal struck(by: Node, kind: String)
	const HIT_R := 1.2
	var need: Array = ["any"]
	var window := 1.2
	var slam_radius := 9.0
	var dark := false
	var latch := false
	var last := false
	var size := 1.0
	var index := 0
	var solved_lock := false
	var _marks := {}
	var _ring_until := 0.0
	var _glow_v := 0.0
	var _mat: StandardMaterial3D
	var _glow: ShaderMaterial
	var _prop: Node3D
	var _poll := 0.0
	var _avail := true
	var _crystal: ShaderMaterial

	func _ready() -> void:
		super._ready()
		add_to_group(&"chimes")
		add_to_group(&"breakable")
		add_to_group(&"pound_listeners")
		var eco := dark or size > 1.2
		_prop = ToolPuzzles.make_prop("cristal_eco" if eco else "sino_cristal", ["glow", "crystal"])
		_glow = ToolPuzzles.glow_of(_prop)
		if _prop != null:
			# o Cristal-Eco já é ~1,2× o sino: a escala completa o `size`
			_prop.scale = Vector3.ONE * (size / (1.2 if eco else 1.0))
			_crystal = (_prop.get_meta("materials", {}) as Dictionary).get("crystal")
			if _glow != null:
				_glow.set_shader_parameter("tint", ToolPuzzles.CYAN)
		else:
			_prop = Node3D.new()
			var bronze := PropLib.shared_material("bronze")
			for k in 3:
				var a := TAU * k / 3.0
				var foot := Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
				var top := Vector3(0, 1.55, 0)
				var leg := ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.025, 0.035, foot.distance_to(top), 6), bronze, (foot + top) * 0.5)
				leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
				_prop.add_child(leg)
			# prisma de cristal pendurado no ápice do tripé (mesmo shader do kit)
			_crystal = PropLib.shared_material("crystal").duplicate() as ShaderMaterial
			if eco:
				_crystal.set_shader_parameter("deep", Color(0.22, 0.16, 0.45))
			_prop.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.0, 0.15, 0.27, 6), _crystal, Vector3(0, 1.265, 0)))
			_prop.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.15, 0.0, 0.66, 6), _crystal, Vector3(0, 0.8, 0)))
			_prop.add_child(ToolPuzzles.mesh_node(ToolPuzzles.cylinder(0.02, 0.02, 0.2, 6), bronze, Vector3(0, 1.45, 0)))
			_prop.scale = Vector3.ONE * size
		add_child(_prop)
		ToolPuzzles.static_cylinder(self, 0.35 * size, 1.7 * size)
		_avail = not last
		_apply_glow(0.0)

	func hit_center() -> Vector3:
		return global_position + Vector3.UP * 1.1 * size

	## Brilho: 0 apagado, 1,5 durante a janela e fixo quando resolvido.
	func _apply_glow(v: float) -> void:
		_glow_v = v
		var e := v if _avail else 0.0
		if _glow != null:
			_glow.set_shader_parameter("active", clampf(e / 1.5, 0.0, 1.0))
		if _crystal != null:
			_crystal.set_shader_parameter("glow", (0.15 if not _avail else 0.55) + e * 0.9)
		if _mat != null:
			_mat.emission_energy_multiplier = 0.15 + e

	## Golpes do herói (grupo "breakable"). Devolve true se acertou o sino (Ricochete).
	func on_attack(center: Vector3, radius: float, by, kind: String, _dmg := 1) -> bool:
		if center.distance_to(hit_center()) > radius + HIT_R * size:
			return false
		_hit(kind, by)
		return true

	## Barrigada (grupo "pound_listeners"): conta como "slam" a até slam_radius.
	func on_pound(p: Vector3, by) -> void:
		if "slam" in need and p.distance_to(global_position) <= slam_radius:
			_hit("slam", by)

	## Tipos de `need` que um tipo de golpe marca.
	static func types_of(kind: String) -> Array:
		var t := ["any"]
		if kind in ToolPuzzles.STAFF_KINDS:
			t.append("staff")
		if kind in ToolPuzzles.SLAM_KINDS:
			t.append("slam")
		return t

	func _hit(kind: String, by) -> void:
		if pressed and (latch or solved_lock):
			Sfx.play_chime(global_position, index + 4)
			return
		if last and not _done_others():
			ToolPuzzles.sfx("tink", global_position, "plate_off", 1.4, -4.0)
			return
		if dark and not ToolPuzzles.in_light(hit_center(), HIT_R * size):
			ToolPuzzles.sfx("tink", global_position, "plate_off", 1.6, -4.0)
			Fx.burst("sparkle", hit_center(), Color(0.5, 0.5, 0.7), 0.4)
			ToolPuzzles.toast_once("O cristal só ressoa na luz... e com dois golpes.", 2.5, 12.0)
			return
		var matched := false
		for t in types_of(kind):
			if t in need:
				_mark(t)
				matched = true
		if not matched:
			ToolPuzzles.sfx("tink", global_position, "plate_off", 1.3, -4.0)
			return
		struck.emit(by, kind)

	func _mark(t: String, tolerance := 0.0) -> void:
		_marks[t] = ToolPuzzles.now() + tolerance
		_fire("mark_" + t)
		Fx.burst("ring_light", hit_center(), ToolPuzzles.CYAN, 0.6 * size)
		if not pressed:
			_apply_glow(maxf(_glow_v, 0.8))
		_evaluate()

	func _evaluate() -> void:
		if pressed:
			return
		var t := ToolPuzzles.now()
		for n in need:
			if not _marks.has(n) or t - float(_marks[n]) > window:
				if need.size() > 1:
					Sfx.play_chime(global_position, index * 2)
				return
		_ring()

	## O sino toca: onda de luz ciano, brilho 1,5 durante a janela (fixo com latch).
	func _ring() -> void:
		_marks.clear()
		_ring_until = INF if latch else ToolPuzzles.now() + window
		ToolPuzzles.sfx("chime_high" if index % 2 == 0 else "chime_low", global_position, "chime")
		Sfx.play_chime(global_position, index * 2 + 1)
		Fx.burst("ring_light", hit_center(), ToolPuzzles.CYAN, 1.6 * size)
		Fx.burst("sparkle", hit_center(), ToolPuzzles.CYAN, 1.0 * size)
		_apply_glow(1.5)
		Game.vibrate(20)
		_set_pressed(true)
		_fire("rung")

	## Grupo resolvido: fica tocando para sempre.
	func lock_solved() -> void:
		solved_lock = true
		_ring_until = INF
		_apply_glow(1.5)
		_set_pressed(true)

	func _physics_process(delta: float) -> void:
		if last and not pressed:
			_poll -= delta
			if _poll <= 0.0:
				_poll = 0.25
				var ok := _done_others()
				if ok != _avail:
					_avail = ok
					_apply_glow(_glow_v)
					if ok:
						Fx.burst("sparkle", hit_center(), ToolPuzzles.CYAN, 1.2 * size)
						Sfx.play_at("reveal", global_position, 1.1, -4.0)
		var t := ToolPuzzles.now()
		if pressed:
			if not solved_lock and not latch and t > _ring_until:
				# a janela venceu sem o grupo resolver: nota descendente e o brilho apaga
				_set_pressed(false)
				ToolPuzzles.sfx("chime_fail", global_position, "chime", 0.7, -4.0)
				create_tween().tween_method(_apply_glow, 1.5, 0.0, 0.5)
			return
		if not _marks.is_empty():
			var expired := []
			for k in _marks:
				if t - float(_marks[k]) > window:
					expired.append(k)
			for k in expired:
				_marks.erase(k)
			if not expired.is_empty() and _marks.is_empty():
				ToolPuzzles.sfx("chime_fail", global_position, "chime", 0.7, -4.0)
				create_tween().tween_method(_apply_glow, _glow_v, 0.0, 0.5)

	## Eventos de rede: "mark_slam" (o anfitrião marca no próprio relógio, +0,15 s) e "rung".
	func _on_event(kind: String) -> void:
		if kind.begins_with("mark_"):
			var t := kind.substr(5)
			if t in need and not pressed:
				_mark(t, 0.15)
		elif kind == "rung" and not pressed:
			_ring()
		elif kind == "latched":
			lock_solved()

	## Barrigada do cliente (rede): marca "slam" no relógio local com tolerância.
	func mark_slam(tolerance := 0.15) -> void:
		if "slam" in need and not pressed:
			_mark("slam", tolerance)

	## Golpe direto (IA / testes): tipo de golpe como em on_attack.
	func strike(kind := "spin", by = null) -> void:
		_hit(kind, by)

	func force_done() -> void:
		latch = true
		if not pressed:
			_ring()


# ============================================================================ duna-tampão
class SandDrift extends Lock:
	## Domo de areia com colisão por cima de uma placa (cobre de verdade: a placa não
	## desce). Um sopro da Concha no cone desfaz o domo em 0,8 s; os outros golpes só
	## levantam poeira.
	var radius := 1.6
	var height := 1.2
	var covers: Node3D                  ## placa coberta (fica bloqueada até o sopro)
	var _mesh: MeshInstance3D
	var _body: StaticBody3D
	var _blowing := false

	func _ready() -> void:
		super._ready()
		add_to_group(&"drifts")
		add_to_group(&"wind_listeners")
		add_to_group(&"breakable")
		add_to_group(&"pound_listeners")
		var pts := PackedVector3Array()
		_mesh = MeshInstance3D.new()
		_mesh.mesh = _dome(pts)
		var m := PropLib.shared_material("stone").duplicate() as ShaderMaterial
		m.set_shader_parameter("sand_amount", 1.0)
		m.set_shader_parameter("tint", ToolPuzzles.SAND)
		_mesh.material_override = m
		add_child(_mesh)
		_body = StaticBody3D.new()
		_body.collision_layer = 1
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		_body.add_child(cs)
		add_child(_body)
		if covers != null and "blocked_by" in covers:
			covers.blocked_by = self

	## Meia elipsoide (r, h) afundada 0,3 m no chão; preenche `pts` para a colisão.
	func _dome(pts: PackedVector3Array) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 20
		var rings := 7
		var grid := []
		for j in rings + 1:
			var row := []
			var phi := PI * 0.5 * float(j) / rings
			for i in seg + 1:
				var a := TAU * float(i) / seg
				var wob := 1.0 + 0.06 * sin(a * 3.0 + 1.3) * cos(phi)
				var p := Vector3(cos(a) * cos(phi) * radius * wob, sin(phi) * height - 0.3 * (1.0 - sin(phi)), sin(a) * cos(phi) * radius * wob)
				row.append(p)
				if i < seg:
					pts.append(p)
			grid.append(row)
		for j in rings:
			for i in seg:
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i]
				var d: Vector3 = grid[j + 1][i + 1]
				st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
				st.add_vertex(b); st.add_vertex(d); st.add_vertex(c)
		st.generate_normals()
		return st.commit()

	## Ponto para a mira automática da rajada.
	func gust_point() -> Vector3:
		return global_position + Vector3.UP * 0.5

	## Rajada da Concha (grupo "wind_listeners").
	func on_gust(origin: Vector3, dir: Vector3, length := 10.0, half_angle := 25.0, _by = null) -> void:
		if pressed or _blowing:
			return
		if ToolPuzzles.in_cone(origin, dir, global_position + Vector3.UP * 0.5, length, half_angle, radius):
			blow(dir)

	## Some com um sopro: 0,8 s, poeira 2,0 e faixas de areia na direção da rajada.
	func blow(dir := Vector3.FORWARD) -> void:
		if pressed or _blowing:
			return
		_blowing = true
		var f := Vector3(dir.x, 0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.FORWARD
		Fx.burst("dust", global_position + Vector3.UP * 0.6, Color(1.0, 0.86, 0.66, 0.7), 2.0)
		for k in 3:
			Fx.burst("dust", global_position + f * (1.0 + k * 1.2) + Vector3.UP * 0.4, Color(1.0, 0.86, 0.66, 0.5), 1.2)
		ToolPuzzles.sfx("sand_scatter", global_position, "whoosh")
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_mesh, "scale", Vector3(1.4, 0.02, 1.4), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(_mesh, "position", f * 0.8, 0.8)
		tw.chain().tween_callback(_finish_blow)

	func _finish_blow() -> void:
		_blowing = false
		if pressed:
			return
		_mesh.visible = false
		if is_instance_valid(_body):
			_body.queue_free()
		_set_pressed(true)
		_fire("blown")

	## Rodopio, Barrigada e bastão só levantam poeira.
	func on_attack(center: Vector3, r: float, _by, _kind: String, _dmg := 1) -> bool:
		if pressed or center.distance_to(global_position + Vector3.UP * 0.5) > r + radius:
			return false
		_puff()
		return true

	func on_pound(p: Vector3, _by) -> void:
		if not pressed and p.distance_to(global_position) < 3.4 + radius:
			_puff()

	func _puff() -> void:
		Fx.burst("dust", global_position + Vector3.UP * 0.8, Color(1.0, 0.86, 0.66, 0.6), 1.2)
		ToolPuzzles.toast_once("A areia volta a cobrir... precisa de vento.", 2.5, 10.0)

	func _on_event(kind: String) -> void:
		if kind in ["blown", "latched"]:
			_mesh.visible = false
			_finish_blow()

	func force_done() -> void:
		_mesh.visible = false
		_finish_blow()


# ============================================================================ aviso de trava
class HintZone extends Node3D:
	## Um herói local dentro de `radius` vê o texto se faltar o item `needs` e o grupo
	## (se houver) ainda não estiver resolvido. No máximo 1 vez a cada 20 s.
	const EVERY := 20.0
	var radius := 8.0
	var needs := ""
	var group_id := ""
	var text := ""
	var _last := -1000.0
	var _poll := 0.0

	func _ready() -> void:
		add_to_group(&"hints")

	func active() -> bool:
		if needs != "" and ToolPuzzles.has_item(needs):
			return false
		return group_id == "" or not PuzzleGroups.solved(group_id)

	func _physics_process(delta: float) -> void:
		_poll -= delta
		if _poll > 0.0:
			return
		_poll = 0.2
		if ToolPuzzles.now() - _last < EVERY or not active():
			return
		for h in Game.heroes:
			if is_instance_valid(h) and not h.is_remote and h.global_position.distance_to(global_position) <= radius:
				_last = ToolPuzzles.now()
				Game.show_toast(text, 3.0)
				return
