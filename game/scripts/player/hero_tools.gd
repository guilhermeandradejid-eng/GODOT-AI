class_name HeroTools
extends RefCounted
## Ferramentas do Sael (papel "agile"), uma instância por herói ágil (game/design/itens.md §2):
##   Arpéu de Rumo     – mira automática (cone, prioridade, trava grudenta, buffer) e despacho do USAR
##                       para os verbos do Hero (_st_hook / _st_swing / _st_zipline);
##   Lanterna de Brasa – estado liga/desliga: OmniLight3D no osso grip_L/belt_L, Game.lantern_pos;
##   Concha dos Ventos – rajada em cone (call_group "wind_listeners".on_gust) e, no ar, a Lufada;
##   Bastão de Quilha  – só o modelo nas costas/mão (o combo fica no Hero).
## Também desenha a corda (faixa de 2 segmentos virada para a câmera) e os modelos dos itens
## nos ossos (game/assets/props/<id>.glb, com reserva procedural).

const HOOK_SPEED := 60.0            ## o gancho visual voa a 60 m/s
const EMPTY_LEN := 8.0              ## arremesso vazio: 8 m à frente
const EMPTY_BACK := 0.35            ## ... e volta em 0,35 s
const COOLDOWN := 0.25              ## recarga do arpéu (0 ao encadear para a chain_next)
const USE_BUFFER := 0.20
const PRE_LOOK := 0.25              ## pré-destaque no ar: válida em ≤ 0,25 s pela velocidade
const STICKY_SCORE := 0.15
const STICKY_TIME := 0.25
const CONE_KB := 45.0
const CONE_TOUCH := 60.0
const RANGES := {"swing": 14.0, "zip": 20.0, "pull": 12.0, "heavy": 12.0, "relic": 12.0, "enemy": 12.0,
	"hulvar": 16.0, "brazier": 14.0, "zipline": 6.0}
## argola > aro de puxar ou braseiro > relíquia > Hulvar > Silente
const PRIORITY := {"swing": 0, "zip": 0, "zipline": 0, "pull": 1, "heavy": 1, "brazier": 1, "relic": 2,
	"hulvar": 3, "enemy": 4}
const HULVAR_MIN := 4.0
const ZIP_POLE_R := 6.0             ## USAR a até 6 m do poste inicial
const ZIP_AIR_R := 2.0              ## ... ou no ar a até 2 m do cabo
const ZIP_AIR_FRAC := 0.7           ## ... nos primeiros 70% dele
const LAMP_R := 7.0
const LAMP_R_RAISED := 9.0
const LAMP_COLOR := Color(1.0, 0.706, 0.353)     ## #FFB45A
const LAMP_STILL := 0.6             ## parado 0,6 s = lanterna erguida
const LAMP_REST := 0.8              ## volta à mão 0,8 s depois do golpe/arremesso/sopro
const GUST_LEN := 10.0
const GUST_HALF := 25.0
const GUST_COOL := 0.9
const BLOW_CLIP := 0.6
const BLOW_ON := 0.12               ## vento ativo de 0,12 a 0,47 s
const BLOW_ROOT := 0.45             ## no chão, o Sael fica parado 0,45 s
const ROPE_W := 0.025
const ROPE_COLOR := Color(0.47, 0.2, 0.13)
const ROPE_GLOW := Color(0.3, 0.95, 0.9)
## modelos dos itens: encaixe guardado e deslocamentos por encaixe (§8.1)
const ITEM_SLOTS := {"arpeu": "belt_R", "bastao": "back_slot", "lanterna": "belt_L", "concha": "belt_L"}
const ITEM_OFFSETS := {
	"lanterna": {"belt_L": Vector3(-0.04, -0.02, -0.08)},
	"concha": {"belt_L": Vector3(0.02, -0.04, 0.09)},
}

var hero: Hero
var target := {}                    ## alvo travado: {node, kind, pos, score, cls, pre, id}
var lamp_on := false
var lamp_raised := false
var light: OmniLight3D
var rope_active := false            ## corda no ar ou presa (tool_bits 4)
var rope_attached := false          ## presa no alvo (brilho ciano)
var rope_to := Vector3.ZERO         ## ponta da corda (mundo)
var flame_t := -1.0                 ## Lançar a Luz: chama correndo pela corda (0..1)
var lufada_ready := true
var cooldown := 0.0
var chain_from := ""                ## chain_next da última argola solta (recarga 0 se encadear)
var _cands: Array = []
var _out_t := 0.0
var _use_buf := 0.0
var _buf_empty := false
var _gust_cool := 0.0
var _blow_t := -1.0
var _blow_dir := Vector3.FORWARD
var _blow_done := false
var _empty_t := -1.0
var _empty_to := Vector3.ZERO
var _still_t := 0.0
var _lamp_rest := 0.0
var _flick_t := 0.0
var _remote_bits := 0
var _rope_mi: MeshInstance3D
var _rope_mesh: ImmediateMesh
var _rope_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _props_done := {}


func _init(h: Hero) -> void:
	hero = h


## Chamado no _ready do herói (depois do visual): luz, corda e modelos dos itens.
func setup() -> void:
	light = OmniLight3D.new()
	light.name = "LuzLanterna"
	light.light_color = LAMP_COLOR
	light.light_energy = 1.8
	light.omni_range = LAMP_R + 2.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.visible = false
	hero.add_child(light)
	light.position = Vector3(0.18, 0.55, 0.12)
	_halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8)
	_halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_color = Color(1.0, 0.62, 0.3, 0.32)
	hm.no_depth_test = false
	if ResourceLoader.exists("res://game/assets/textures/soft_dot.png"):
		hm.albedo_texture = load("res://game/assets/textures/soft_dot.png")
	_halo.material_override = hm
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.add_child(_halo)
	_rope_mesh = ImmediateMesh.new()
	_rope_mi = MeshInstance3D.new()
	_rope_mi.name = "Corda"
	_rope_mi.mesh = _rope_mesh
	_rope_mi.top_level = true
	_rope_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope_mat.vertex_color_use_as_albedo = true
	_rope_mi.material_override = _rope_mat
	hero.add_child(_rope_mi)
	_rope_mi.global_transform = Transform3D.IDENTITY
	_sync_props()


# =================================================================== inventário
func has_item(id: String) -> bool:
	if Game.has_method("has_item"):
		return bool(Game.call("has_item", id))
	var items = Game.get("items")
	return items is Array and id in items


## Modelos dos itens nos ossos: aparecem quando o item entra no inventário.
func _sync_props() -> void:
	if hero.visual == null:
		return
	for id in ITEM_SLOTS:
		var have := has_item(id)
		if have and not _props_done.has(id):
			_props_done[id] = true
			var offs := {}
			var od: Dictionary = ITEM_OFFSETS.get(id, {})
			for s in od:
				offs[s] = Transform3D(Basis.IDENTITY, od[s])
			hero.visual.attach_prop(id, _make_prop(id), ITEM_SLOTS[id], offs)
			if id == "lanterna":
				var n := hero.visual.prop_node("lanterna")
				if n != null:
					light.reparent(n, false)
					light.position = Vector3(0.0, -0.06, 0.0)
		if _props_done.has(id):
			hero.visual.set_prop_visible(id, have)


## GLB do item (game/assets/props/<id>.glb ou item_<id>.glb, materiais pelo PropLib) ou um
## modelo procedural simples de reserva. Eixo +Y = eixo do item, origem no ponto de pega.
func _make_prop(id: String) -> Node3D:
	for name in [id, "item_" + id]:
		if ResourceLoader.exists("res://game/assets/props/%s.glb" % name):
			var n := PropLib.make(name)
			for mi in PropLib.meshes(n):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return n
	var root := Node3D.new()
	root.name = "Item_" + id
	var brass := _mat(Color(0.83, 0.64, 0.25), 0.0)
	match id:
		"arpeu":
			var coil := _mesh(TorusMesh.new(), _mat(ROPE_COLOR, 0.0), root)
			(coil.mesh as TorusMesh).inner_radius = 0.035
			(coil.mesh as TorusMesh).outer_radius = 0.075
			coil.rotation.z = PI * 0.5
			for i in 3:
				var claw := _mesh(CylinderMesh.new(), brass, root)
				var cm := claw.mesh as CylinderMesh
				cm.top_radius = 0.004
				cm.bottom_radius = 0.01
				cm.height = 0.1
				claw.position = Vector3(0, 0.1, 0)
				claw.rotation = Vector3(0.5, TAU * i / 3.0, 0)
		"bastao":
			var shaft := _mesh(CylinderMesh.new(), _mat(Color(0.86, 0.72, 0.5), 0.0), root)
			var sm := shaft.mesh as CylinderMesh
			sm.top_radius = 0.016
			sm.bottom_radius = 0.019
			sm.height = 0.95
			shaft.position.y = 0.125
			var tip := _mesh(CylinderMesh.new(), brass, root)
			var tm := tip.mesh as CylinderMesh
			tm.top_radius = 0.022
			tm.bottom_radius = 0.022
			tm.height = 0.06
			tip.position.y = 0.6
		"lanterna":
			var glass := _mesh(BoxMesh.new(), _mat(LAMP_COLOR, 2.0), root)
			(glass.mesh as BoxMesh).size = Vector3(0.1, 0.13, 0.1)
			glass.position.y = -0.1
			var cap := _mesh(CylinderMesh.new(), brass, root)
			var cpm := cap.mesh as CylinderMesh
			cpm.top_radius = 0.03
			cpm.bottom_radius = 0.07
			cpm.height = 0.04
			cap.position.y = -0.02
		"concha":
			var shell := _mesh(SphereMesh.new(), _mat(Color(0.98, 0.78, 0.76), 0.15), root)
			var shm := shell.mesh as SphereMesh
			shm.radius = 0.07
			shm.height = 0.12
			shell.scale = Vector3(1.0, 1.0, 1.5)
			var mouth := _mesh(CylinderMesh.new(), brass, root)
			var mm := mouth.mesh as CylinderMesh
			mm.top_radius = 0.012
			mm.bottom_radius = 0.02
			mm.height = 0.06
			mouth.position = Vector3(0, 0, -0.11)
			mouth.rotation.x = PI * 0.5
	return root


func _mesh(m: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


# =================================================================== por quadro
## Tick local (herói controlado aqui): mira, buffer do USAR, sopro, lanterna e corda.
func process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_gust_cool = maxf(0.0, _gust_cool - delta)
	if Engine.get_physics_frames() % 15 == 0:
		_sync_props()
	_update_target(delta)
	if _use_buf > 0.0:
		_use_buf -= delta
		if _can_fire():
			_use_buf = 0.0
			_fire(target)
		elif _use_buf <= 0.0 and _buf_empty:
			_buf_empty = false
			throw_empty()
	_update_blow(delta)
	_update_lamp(delta)
	_update_rope(delta)


## Herói remoto (par da rede): só a luz e a corda, pelos tool_bits recebidos.
func process_remote(delta: float) -> void:
	if Engine.get_physics_frames() % 15 == 0:
		_sync_props()
	lamp_on = _remote_bits & 1 != 0
	lamp_raised = _remote_bits & 2 != 0
	rope_active = _remote_bits & 4 != 0
	rope_attached = rope_active
	_update_lamp(delta)
	_update_rope(delta)


## Estado das ferramentas para a rede (_hero_state): 1 = lanterna acesa, 2 = erguida, 4 = corda ativa.
func tool_bits() -> int:
	return (1 if lamp_on else 0) | (2 if lamp_on and lamp_raised else 0) | (4 if rope_active else 0)


func apply_remote(bits: int, to: Vector3) -> void:
	_remote_bits = bits
	rope_to = to


# =================================================================== mira
func _touch() -> bool:
	return bool(Game.get("touch_enabled")) and hero.player_index <= 0


## Centro do cone: analógico (≥ 0,2) ou a câmera.
func aim_dir() -> Vector3:
	var m := hero.intent.move
	if m.length() >= 0.2:
		var w := hero.wish_dir()
		return Vector3(w.x, 0.0, w.z).normalized()
	return Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, hero.cam_yaw)


func chest() -> Vector3:
	return hero.global_position + Vector3.UP * 0.6


func _update_target(delta: float) -> void:
	if not has_item("arpeu") or hero.state in [Hero.S.HURT, Hero.S.CUTSCENE, Hero.S.HOOK, Hero.S.ZIPLINE] \
			or hero.is_remote:
		target = {}
		_cands = []
		_highlight(null)
		return
	_update_target_inner(delta)
	_highlight(target.get("node") if not target.is_empty() else null)


func _update_target_inner(delta: float) -> void:
	var best := find_target(chest(), aim_dir(), _touch())
	var cur := {}
	if not target.is_empty():
		for c in _cands:
			if c["node"] == target["node"] and c["kind"] == target["kind"]:
				cur = c
				break
		if cur.is_empty():
			if not _alive(target):
				target = {}
			else:
				_out_t += delta
				if _out_t > STICKY_TIME:
					target = {}
				else:
					target["pos"] = target_point(target)
		else:
			_out_t = 0.0
			target = cur
	if best.is_empty():
		return
	if target.is_empty():
		target = best
		_out_t = 0.0
		_on_new_target()
		return
	if best["node"] == target["node"] and best["kind"] == target["kind"]:
		return
	if int(best["cls"]) < int(target["cls"]) or (int(best["cls"]) == int(target["cls"]) \
			and float(best["score"]) < float(target["score"]) - STICKY_SCORE):
		target = best
		_out_t = 0.0
		_on_new_target()


func _on_new_target() -> void:
	_highlight(target.get("node"))
	# a IA do Hulvar para por 0,4 s quando é mirada
	if target.get("kind", "") == "hulvar":
		var hv: Hero = target["node"]
		if hv.has_method("hook_aimed"):
			hv.hook_aimed(0.4)


## Destaque do alvo travado (set_highlight do ToolPuzzles); apaga o anterior.
var _hl_node = null


func _highlight(n) -> void:
	if _hl_node == n:
		return
	if _hl_node != null and is_instance_valid(_hl_node) and _hl_node.has_method("set_highlight"):
		_hl_node.set_highlight(false)
	_hl_node = n
	if n != null and is_instance_valid(n) and n.has_method("set_highlight"):
		n.set_highlight(true)


func _alive(t: Dictionary) -> bool:
	var n = t.get("node")
	if n == null or not is_instance_valid(n):
		return false
	match String(t.get("kind", "")):
		"enemy": return not bool(n.get("dead"))
		"brazier": return not bool(n.get("pressed")) and lamp_on
		"relic": return not bool(n.get("taken")) and (n as Node3D).visible
		"pull", "heavy": return not bool(n.get("pressed"))
	return true


func has_target() -> bool:
	return not target.is_empty() and not bool(target.get("pre", false))


## Posição para o retículo do HUD (INF sem alvo).
func target_pos() -> Vector3:
	return Vector3.INF if target.is_empty() else target_point(target)


func target_kind() -> String:
	return String(target.get("kind", ""))


## Ícone do botão USAR: "hook" (alvo destacado), "concha" (rajada/Lufada) ou "empty" (arremesso vazio).
func use_icon() -> String:
	if has_target():
		return "hook"
	if has_item("concha"):
		return "concha"
	return "empty"


## Algum alvo de quebra-cabeça válido a até 10 m (o USAR pulsa).
func puzzle_hint() -> bool:
	for c in _cands:
		if c["kind"] in ["pull", "heavy", "brazier", "relic"] and chest().distance_to(c["pos"]) <= 10.0:
			return true
	return false


## Janela de soltura perfeita no balanço (o retículo pisca dourado).
func perfect_window() -> bool:
	return hero.state == Hero.S.SWING and hero.has_method("swing_perfect_now") and hero.swing_perfect_now()


## Posição atual de um alvo (alvos que andam: Hulvar, Silente, relíquia).
func target_point(t: Dictionary) -> Vector3:
	var n = t.get("node")
	if n == null or not is_instance_valid(n):
		return t.get("pos", Vector3.ZERO)
	match String(t.get("kind", "")):
		"hulvar": return (n as Hero).saddle_transform().origin + Vector3.UP * 0.3
		"zipline": return t.get("pos", (n as Node3D).global_position)
	if n.has_method("hook_point"):
		return n.hook_point()
	match String(t.get("kind", "")):
		"enemy", "relic": return (n as Node3D).global_position + Vector3.UP * 0.5
	return (n as Node3D).global_position


## Melhor alvo do arpéu a partir de origin (peito), cone centrado em dir (horizontal).
## Devolve {node, kind, pos, score, cls, pre, id} ou {}; guarda todos os válidos em _cands.
func find_target(origin: Vector3, dir: Vector3, touch: bool) -> Dictionary:
	_cands = []
	var half := deg_to_rad(CONE_TOUCH if touch else CONE_KB)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(sin(hero.facing), 0, cos(hero.facing))
	var tree := hero.get_tree()
	var vel := hero.velocity
	var airborne := hero.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.LAUNCH, Hero.S.SWING]
	var cur_chain := ""
	if hero.state == Hero.S.SWING and hero.hook.has("node") and is_instance_valid(hero.hook["node"]):
		cur_chain = String(_prop(hero.hook["node"], ["chain_next"], ""))
	var riding := hero.state == Hero.S.RIDE
	# argolas e aros (grupo hook_targets)
	for n in tree.get_nodes_in_group(&"hook_targets"):
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if hero.state == Hero.S.SWING and hero.hook.get("node") == n:
			continue
		var mode := String(_prop(n, ["mode"], "swing"))
		if n.has_method("can_target") and not n.can_target(hero):
			continue
		var kind := mode
		if mode == "pull":
			if bool(_prop(n, ["pressed"], false)):
				continue
			kind = "heavy" if bool(_prop(n, ["heavy"], false)) else "pull"
		elif mode != "swing" and mode != "zip":
			continue
		var rid := String(_prop(n, ["ring_id", "id"], ""))
		var bonus := 0.4 if cur_chain != "" and rid == cur_chain else 0.0
		var lo := 15.0 if kind in ["swing", "zip"] else -30.0
		_consider(n, kind, _point(n, Vector3.ZERO), origin, dir, half, lo, bonus, vel, airborne, rid)
	# Cabo de Vidro
	for z in tree.get_nodes_in_group(&"ziplines"):
		_consider_zipline(z, origin)
	# Olhos de Brasa (só com a lanterna acesa: Lançar a Luz)
	if lamp_on:
		var seen := {}
		for b in tree.get_nodes_in_group(&"braziers"):
			seen[b] = true
			_consider_brazier(b, origin, dir, half, vel, airborne)
		for b in tree.get_nodes_in_group(&"plates"):
			if not seen.has(b) and (b.has_method("on_hook_light") or String(_prop(b, ["kind"], "")) == "brazier"):
				_consider_brazier(b, origin, dir, half, vel, airborne)
	# relíquias que podem ser puxadas
	for r in tree.get_nodes_in_group(&"relics"):
		if not (r is Node3D) or not bool(_prop(r, ["pull"], false)) or bool(_prop(r, ["taken"], false)):
			continue
		if not (r as Node3D).visible or bool(_prop(r, ["hidden_until_revealed"], false)):
			continue
		if r.has_method("can_target"):
			if not r.can_target(hero):
				continue
		elif r.has_method("can_take") and not r.can_take():
			continue
		_consider(r, "relic", _point(r, Vector3.UP * 0.5), origin, dir, half, -30.0, 0.0, vel, airborne)
	# o Hulvar (Embarque Relâmpago)
	var hv := Game.hero("strong") as Hero
	if hv != null and hv != hero and not riding and hv.rider == null and hv.state in [Hero.S.GROUND, Hero.S.SWIM, Hero.S.SURF]:
		var p := hv.saddle_transform().origin + Vector3.UP * 0.3
		if origin.distance_to(p) >= HULVAR_MIN:
			_consider(hv, "hulvar", p, origin, dir, half, -30.0, 0.0, vel, airborne, "", false)
	# Silentes (puxar)
	for e in tree.get_nodes_in_group(&"enemies"):
		if not (e is Node3D) or bool(_prop(e, ["dead"], false)):
			continue
		if e.has_method("can_target") and not e.can_target(hero):
			continue
		_consider(e, "enemy", _point(e, Vector3.UP * 0.5), origin, dir, half, -30.0, 0.0, vel, airborne)
	var best := {}
	for c in _cands:
		if best.is_empty() or int(c["cls"]) < int(best["cls"]) \
				or (int(c["cls"]) == int(best["cls"]) and float(c["score"]) < float(best["score"])):
			best = c
	return best


func _consider_brazier(b, origin: Vector3, dir: Vector3, half: float, vel: Vector3, airborne: bool) -> void:
	if not (b is Node3D) or bool(_prop(b, ["pressed", "lit"], false)):
		return
	if b.has_method("can_target") and not b.can_target(hero):
		return
	_consider(b, "brazier", _point(b, Vector3.ZERO), origin, dir, half, -30.0, 0.0, vel, airborne)


## Cabo de Vidro: perto do poste inicial (chão) ou a até 2 m do cabo no ar, nos primeiros 70%.
func _consider_zipline(z, origin: Vector3) -> void:
	if not (z is Node3D) or not z.has_method("transform_at") or not z.has_method("length"):
		return
	var length: float = z.length()
	if length <= 1.0:
		return
	var hand := hero.global_position + Vector3.UP * float(_prop(z, ["hang"], 1.15))
	var start: Vector3 = z.transform_at(0.0).origin
	var off := 0.0
	var p := start
	var d := INF
	if z.has_method("can_grab") and z.has_method("grab_offset"):
		# contrato do ToolPuzzles.Zipline: poste a até 6 m ou cabo a até 2 m (70%)
		if not z.can_grab(hero):
			return
		var air: bool = not (hero.state in [Hero.S.GROUND, Hero.S.SURF, Hero.S.SWIM])
		off = maxf(0.0, z.grab_offset(hero.global_position, air))
		p = z.transform_at(off).origin
		d = p.distance_to(hand)
	elif hero.state in [Hero.S.GROUND, Hero.S.SURF, Hero.S.RIDE]:
		var flat := Vector2(start.x - hero.global_position.x, start.z - hero.global_position.z).length()
		if flat > ZIP_POLE_R or absf(start.y - hand.y) > 4.0:
			return
		d = flat
	else:
		var curve = z.get("curve")
		if curve == null:
			return
		var local: Vector3 = (z as Node3D).global_transform.affine_inverse() * hand
		off = curve.get_closest_offset(local)
		if off > length * ZIP_AIR_FRAC:
			return
		p = z.transform_at(off).origin
		d = p.distance_to(hand)
		if d > ZIP_AIR_R:
			return
	_cands.append({"node": z, "kind": "zipline", "pos": p, "offset": off, "score": 0.6 * d / RANGES["zipline"],
		"cls": PRIORITY["zipline"], "pre": false, "id": String(_prop(z, ["zip_id", "id"], ""))})


## Testa um alvo: alcance, elevação, cone, linha de visão; no ar, também o pré-destaque.
func _consider(n, kind: String, p: Vector3, origin: Vector3, dir: Vector3, half: float, elev_lo: float,
		bonus: float, vel: Vector3, airborne: bool, rid := "", los := true) -> void:
	var rng: float = RANGES[kind]
	var ok := _valid(p, origin, dir, half, elev_lo, rng)
	var pre := false
	if ok < 0.0:
		# pré-destaque: argola que fica válida em ≤ 0,25 s pela velocidade atual
		if not (airborne and kind in ["swing", "zip"]):
			return
		var o2 := origin + vel * PRE_LOOK
		var hv := Vector3(vel.x, 0, vel.z)
		var d2 := hv.normalized() if hv.length() > 1.0 else dir
		ok = _valid(p, o2, d2, half, elev_lo, rng)
		if ok < 0.0:
			return
		pre = true
	if los and not _los(origin, p, n):
		return
	var d := origin.distance_to(p)
	var hvel := Vector3(vel.x, 0, vel.z)
	if hvel.length() > 3.0:
		var to := Vector3(p.x - origin.x, 0, p.z - origin.z).normalized()
		if to.dot(hvel.normalized()) > cos(deg_to_rad(30.0)):
			bonus += 0.2
	var score := ok / half + 0.6 * d / rng - bonus
	_cands.append({"node": n, "kind": kind, "pos": p, "score": score, "cls": PRIORITY[kind], "pre": pre, "id": rid})


## Ângulo horizontal ao centro do cone (rad) se o ponto está no alcance, na faixa de
## elevação e no cone; -1 se não.
func _valid(p: Vector3, origin: Vector3, dir: Vector3, half: float, elev_lo: float, rng: float) -> float:
	var d := p - origin
	var dist := d.length()
	if dist > rng or dist < 0.3:
		return -1.0
	var flat := Vector2(d.x, d.z).length()
	var elev := rad_to_deg(atan2(d.y, flat))
	if elev < elev_lo or elev > 85.0:
		return -1.0
	if flat < 0.5:
		return 0.0
	var ang := Vector3(d.x, 0, d.z).normalized().angle_to(dir)
	return ang if ang <= half else -1.0


## Linha de visão do peito na LAYER_WORLD; bater a até 0,6 m do alvo conta como livre.
## O colisor do prop anfitrião do alvo (los_exclude) e os do próprio alvo são ignorados.
func _los(origin: Vector3, p: Vector3, n) -> bool:
	var space := hero.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, p, Hero.LAYER_WORLD)
	var ex: Array[RID] = [hero.get_rid()]
	if n is CollisionObject3D:
		ex.append((n as CollisionObject3D).get_rid())
	for c in (n as Node).get_children():
		if c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
	var extra = n.get("los_exclude")
	if extra is Array:
		for e in extra:
			if e is RID:
				ex.append(e)
			elif e is CollisionObject3D and is_instance_valid(e):
				ex.append((e as CollisionObject3D).get_rid())
	elif extra is CollisionObject3D:
		ex.append((extra as CollisionObject3D).get_rid())
	q.exclude = ex
	for i in 3:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if (hit["position"] as Vector3).distance_to(p) <= 0.6:
			return true
		# o corpo atingido é filho do próprio alvo? ignora e tenta de novo
		var col = hit.get("collider")
		if col is Node and (n as Node).is_ancestor_of(col):
			ex.append(hit["rid"])
			q.exclude = ex
			continue
		return false
	return false


## Ponto de mira do alvo: hook_point() quando existe.
func _point(n, off: Vector3) -> Vector3:
	if n.has_method("hook_point"):
		return n.hook_point()
	return (n as Node3D).global_position + off


func _prop(n, names: Array, def = null):
	if n == null or not is_instance_valid(n):
		return def
	for k in names:
		var v = n.get(k)
		if v != null:
			return v
	return def


# =================================================================== USAR
## Botão USAR: arpéu se houver alvo destacado; senão Concha (rajada no chão, Lufada no ar)
## ou arremesso vazio. Devolve true se fez algo.
func use_pressed(_h: Hero = null) -> bool:
	if hero.state in [Hero.S.HOOK, Hero.S.HURT, Hero.S.CUTSCENE]:
		return false
	var arpeu := has_item("arpeu")
	if arpeu and _can_fire():
		_fire(target)
		return true
	if arpeu and not target.is_empty():
		# argola quase no cone (pré-destaque) ou arpéu recarregando: espera até 0,20 s
		_use_buf = maxf(USE_BUFFER, cooldown + 0.02)
		_buf_empty = false
		return true
	if hero.state == Hero.S.SWING:
		return false
	if has_item("concha"):
		var air := hero.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.LAUNCH]
		if air and lufada_ready:
			return lufada()
		return blow()
	if arpeu:
		_use_buf = USE_BUFFER
		_buf_empty = true
		return true
	return false


func _can_fire() -> bool:
	if target.is_empty() or bool(target.get("pre", false)):
		return false
	var chain := chain_from != "" and String(target.get("id", "")) == chain_from
	return cooldown <= 0.0 or chain


## Prende no alvo: passa para o Hero (HOOK / SWING / ZIPLINE / Reboque).
func _fire(t: Dictionary) -> void:
	var chain := chain_from != "" and String(t.get("id", "")) == chain_from
	chain_from = ""
	_use_buf = 0.0
	if t.get("kind", "") == "hulvar":
		var hv: Hero = t["node"]
		if hv.has_method("hook_aimed"):
			hv.hook_aimed(0.4)
	if hero.has_method("start_hook"):
		hero.start_hook(t.duplicate(), chain)
	target = {}
	_out_t = 0.0


## Mira usada pela IA ou pelo Pedido (origem no Sael, direção da câmera ou dada).
func request_use(dir := Vector3.ZERO) -> bool:
	var d := dir if dir.length() > 0.01 else Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, hero.cam_yaw)
	var t := find_target(chest(), d, true)
	if not t.is_empty() and not bool(t.get("pre", false)) and has_item("arpeu"):
		target = t
		_fire(t)
		return true
	if has_item("concha") and hero.state in [Hero.S.GROUND, Hero.S.SURF, Hero.S.RIDE, Hero.S.SWIM]:
		return blow(d)
	return false


## Prende num alvo específico sem depender do cone (IA: argolas `ai: true`, Pedido).
## Confere alcance, faixa de elevação e linha de visão. Devolve true se lançou.
func hook_to(n) -> bool:
	if n == null or not is_instance_valid(n) or not has_item("arpeu") or cooldown > 0.0:
		return false
	if hero.state in [Hero.S.HOOK, Hero.S.SWING, Hero.S.ZIPLINE, Hero.S.HURT, Hero.S.CUTSCENE]:
		return false
	if n.has_method("can_target") and not n.can_target(hero):
		return false
	var kind := ""
	if n == Game.hero("strong"):
		kind = "hulvar"
	elif (n as Node).is_in_group(&"hook_targets"):
		kind = String(_prop(n, ["mode"], "swing"))
		if kind == "pull" and bool(_prop(n, ["heavy"], false)):
			kind = "heavy"
	elif (n as Node).is_in_group(&"braziers"):
		kind = "brazier"
	elif (n as Node).is_in_group(&"relics"):
		kind = "relic"
	elif (n as Node).is_in_group(&"enemies"):
		kind = "enemy"
	if not RANGES.has(kind) or kind == "zipline":
		return false
	var t := {"node": n, "kind": kind, "score": 0.0, "cls": PRIORITY[kind], "pre": false,
		"id": String(_prop(n, ["ring_id", "id"], ""))}
	var p := target_point(t)
	t["pos"] = p
	var o := chest()
	var lo := 15.0 if kind in ["swing", "zip"] else -30.0
	var to := p - o
	if _valid(p, o, Vector3(to.x, 0, to.z).normalized() if Vector2(to.x, to.z).length() > 0.01 else aim_dir(),
			PI, lo, RANGES[kind]) < 0.0:
		return false
	if kind != "hulvar" and not _los(o, p, n):
		return false
	target = t
	_fire(t)
	return true


## Arremesso vazio: 8 m à frente, volta em 0,35 s.
func throw_empty() -> void:
	if hero.state in [Hero.S.HOOK, Hero.S.SWING, Hero.S.ZIPLINE, Hero.S.HURT, Hero.S.CUTSCENE]:
		return
	var f := aim_dir()
	_empty_to = chest() + f * EMPTY_LEN + Vector3.UP * 0.6
	_empty_t = 0.0
	cooldown = COOLDOWN
	rope_active = true
	rope_attached = false
	rope_to = hand_pos()
	hero.facing = atan2(f.x, f.z)
	suppress_lamp()
	_play_clip("grapple_throw", "jump", 0.18)
	hero.visual.set_prop_slot("arpeu", "grip_R")
	_sfx("hook_throw", "whoosh", hero.global_position, 1.3)


## Corda: começa a voar (rope_to anda até o alvo a 60 m/s; o Hero cuida do tempo de prender).
func rope_throw() -> void:
	rope_active = true
	rope_attached = false
	rope_to = hand_pos()
	flame_t = -1.0
	_empty_t = -1.0
	suppress_lamp()
	hero.visual.set_prop_slot("arpeu", "grip_R")


func rope_lock(at: Vector3) -> void:
	rope_active = true
	rope_attached = true
	rope_to = at
	Fx.burst("sparkle", at, Color(1.0, 0.85, 0.4), 0.6)
	_sfx("hook_lock", "bump", at, 1.4)


## Solta a corda (fim do verbo). chain_next: id da próxima argola da cadeia (recarga 0).
func rope_release(next_id := "") -> void:
	rope_active = false
	rope_attached = false
	flame_t = -1.0
	cooldown = COOLDOWN          # encadear para a chain_next ignora a recarga (_can_fire)
	chain_from = next_id
	hero.visual.set_prop_slot("arpeu", "belt_R", 0.15)


func hand_pos() -> Vector3:
	if hero.visual != null and hero.visual.has_method("slot_position"):
		return hero.visual.slot_position("grip_R")
	return chest()


func _play_clip(clip: String, fallback: String, dur := 0.0) -> void:
	if hero.has_method("play_clip"):
		hero.play_clip(clip, fallback, dur)
	elif hero.visual != null:
		hero.visual.restart_state(clip if hero.visual.has_state(clip) else fallback)


func _sfx(id: String, fallback: String, pos: Vector3, pitch := 1.0, vol := 0.0) -> void:
	Sfx.play_at(id if Sfx.has(id) else fallback, pos, pitch, vol)


# =================================================================== Concha dos Ventos
## Rajada (USAR sem alvo de arpéu): clipe horn_blow, vento de 0,12 a 0,47 s, recarga 0,9 s.
func blow(dir := Vector3.ZERO) -> bool:
	if _gust_cool > 0.0 or _blow_t >= 0.0:
		return false
	_gust_cool = GUST_COOL
	_blow_dir = dir if dir.length() > 0.01 else aim_dir()
	_blow_dir.y = 0.0
	_blow_dir = _blow_dir.normalized()
	_blow_dir = _auto_aim_gust(_blow_dir)
	_blow_t = 0.0
	_blow_done = false
	hero.facing = atan2(_blow_dir.x, _blow_dir.z)
	if hero.state in [Hero.S.GROUND, Hero.S.SURF]:
		hero.root_for(BLOW_ROOT)
	suppress_lamp()
	hero.visual.set_prop_slot("concha", "grip_L")
	if hero.state != Hero.S.RIDE:
		_play_clip("horn_blow", "spin", BLOW_CLIP)
	_sfx("horn_blow", "call", hero.global_position, 1.5)
	return true


## Lufada (USAR no ar sem alvo): vy = max(vy, 9), +4 m/s no teto horizontal (1,2 s), 1× por voo.
func lufada() -> bool:
	if not lufada_ready:
		return false
	lufada_ready = false
	hero.velocity.y = maxf(hero.velocity.y, 9.0)
	if hero.has_method("lufada_boost"):
		hero.lufada_boost(4.0, 1.2)
	Fx.burst("ring_light", hero.global_position - Vector3.UP * 0.1, Color(0.85, 1.0, 0.95), 0.6)
	_sfx("gust_whoosh", "whoosh", hero.global_position, 1.1)
	# a Lufada também é um sopro (Véu, duna) na direção do voo
	_gust_cool = 0.0
	var f := Vector3(hero.velocity.x, 0, hero.velocity.z)
	blow(f.normalized() if f.length() > 1.0 else aim_dir())
	return true


func recharge_lufada() -> void:
	lufada_ready = true


## Mira automática da rajada: o Véu, Duna-tampão ou Silente mais próximo dentro do cone.
func _auto_aim_gust(dir: Vector3) -> Vector3:
	var o := hero.global_position
	var best := dir
	var bd := INF
	for n in _wind_nodes():
		var p := (n as Node3D).global_position
		if n.has_method("gust_point"):
			p = n.gust_point()
		var d := p - o
		var flat := Vector3(d.x, 0, d.z)
		if flat.length() > GUST_LEN or flat.length() < 0.3:
			continue
		if rad_to_deg(flat.normalized().angle_to(dir)) > GUST_HALF:
			continue
		if flat.length() < bd:
			bd = flat.length()
			best = flat.normalized()
	return best


func _wind_nodes() -> Array:
	var out := []
	var seen := {}
	for g in [&"wind_listeners", &"enemies"]:
		for n in hero.get_tree().get_nodes_in_group(g):
			if seen.has(n) or not (n is Node3D) or not n.has_method("on_gust"):
				continue
			seen[n] = true
			out.append(n)
	return out


func _update_blow(delta: float) -> void:
	if _blow_t < 0.0:
		return
	_blow_t += delta
	if not _blow_done and _blow_t >= BLOW_ON:
		_blow_done = true
		gust(chest(), _blow_dir)
	if _blow_t >= BLOW_CLIP:
		_blow_t = -1.0
		hero.visual.set_prop_slot("concha", "belt_L", 0.15)


## Vento da Concha: on_gust(origin, dir, 10, 25, hero) nos ouvintes; Vento de Popa no Hulvar.
func gust(origin: Vector3, dir: Vector3) -> void:
	for n in _wind_nodes():
		n.on_gust(origin, dir, GUST_LEN, GUST_HALF, hero)
	var hv := Game.hero("strong") as Hero
	if hv != null and hv != hero:
		var d := hv.global_position - origin
		var flat := Vector3(d.x, 0, d.z)
		if flat.length() <= GUST_LEN and flat.length() > 0.1 and rad_to_deg(flat.normalized().angle_to(dir)) <= GUST_HALF:
			if hv.has_method("tailwind"):
				hv.tailwind(3.0)
	# traços de vento + anel de poeira
	for i in 4:
		var p := origin + dir * (1.5 + i * 2.2) + Vector3.UP * (randf() - 0.4) * 0.6
		Fx.burst("ring_light" if i % 2 == 0 else "dust", p, Color(0.9, 1.0, 0.98, 0.7), 0.35 + i * 0.12)
	Fx.burst("dust_ring", hero.global_position + Vector3.UP * 0.05, Color(0, 0, 0, 0), 0.7)
	_sfx("gust_whoosh", "whoosh", origin + dir * 3.0, 1.0)


# =================================================================== Lanterna de Brasa
func toggle_lamp() -> void:
	set_lamp(not lamp_on)


func set_lamp(on: bool) -> void:
	if on and not has_item("lanterna"):
		return
	if on == lamp_on:
		return
	lamp_on = on
	if on:
		_sfx("lantern_on", "mote", hero.global_position, 1.0)
		Fx.burst("sparkle", hero.global_position + Vector3.UP * 0.6, LAMP_COLOR, 0.5)
	if _lamp_rest <= 0.0:
		_lamp_hand(on)


## Golpe, arremesso ou sopro: a lanterna volta ao cinto (0,1 s) e retorna à mão 0,8 s depois.
func suppress_lamp() -> void:
	if not lamp_on:
		return
	_lamp_rest = LAMP_REST
	_lamp_hand(false, 0.1)


func _lamp_hand(on: bool, blend := 0.15) -> void:
	if hero.visual == null:
		return
	hero.visual.set_lantern_hold(on, blend)
	hero.visual.set_prop_slot("lanterna", "grip_L" if on else "belt_L", blend)


func _update_lamp(delta: float) -> void:
	if _lamp_rest > 0.0:
		_lamp_rest -= delta
		if _lamp_rest <= 0.0 and lamp_on:
			_lamp_hand(true)
	if lamp_on and not has_item("lanterna") and not hero.is_remote:
		lamp_on = false
		_lamp_hand(false)
	if not hero.is_remote:
		var still := lamp_on and Vector2(hero.velocity.x, hero.velocity.z).length() < 0.3 and hero.state == Hero.S.GROUND
		_still_t = _still_t + delta if still else 0.0
		lamp_raised = lamp_on and (hero.state == Hero.S.RIDE or _still_t >= LAMP_STILL)
	light.visible = lamp_on
	if not lamp_on:
		if Game.has_method("lantern_off"):
			Game.call("lantern_off")
		else:
			Game.set("lantern_pos", Vector3.INF)
			Game.set("lantern_radius", 0.0)
		return
	var r := LAMP_R_RAISED if lamp_raised else LAMP_R
	var hours := 0
	var rel = Game.get("relics")
	if rel is Array:
		hours = clampi(rel.size(), 0, 3)
	_flick_t += delta
	var flick := 1.0 + 0.06 * sin(_flick_t * TAU * 3.0) * (0.7 + 0.3 * sin(_flick_t * 7.7))
	light.light_energy = 1.8 * (1.0 + 0.6 * hours / 3.0) * flick
	light.omni_range = r + 2.0
	_halo.scale = Vector3.ONE * (0.5 + 0.05 * flick)
	if Game.has_method("set_lantern"):
		Game.call("set_lantern", light.global_position, r)
	else:
		Game.set("lantern_pos", light.global_position)
		Game.set("lantern_radius", r)


# =================================================================== corda
func _update_rope(delta: float) -> void:
	if _empty_t >= 0.0:
		# arremesso vazio: vai até 8 m (60 m/s) e volta em 0,35 s
		_empty_t += delta
		var out_t := EMPTY_LEN / HOOK_SPEED
		var hand := hand_pos()
		if _empty_t < out_t:
			rope_to = hand.lerp(_empty_to, _empty_t / out_t)
		elif _empty_t < out_t + EMPTY_BACK:
			rope_to = _empty_to.lerp(hand, (_empty_t - out_t) / EMPTY_BACK)
		else:
			_empty_t = -1.0
			rope_active = false
			hero.visual.set_prop_slot("arpeu", "belt_R", 0.15)
	_rope_mesh.clear_surfaces()
	if not rope_active:
		return
	var a := hand_pos()
	var b := rope_to
	var cam := hero.get_viewport().get_camera_3d() if hero.is_inside_tree() else null
	var eye := cam.global_position if cam != null else a + Vector3(0, 2, 4)
	# 2 segmentos: o meio cede um pouco quando a corda está frouxa (voando)
	var sag := 0.0 if rope_attached else minf(a.distance_to(b) * 0.04, 0.4)
	var m := (a + b) * 0.5 + Vector3.DOWN * sag
	var pts := [a, m, b]
	var base := ROPE_COLOR
	var glow := ROPE_GLOW * 0.4 + ROPE_COLOR * 0.6 if rope_attached else ROPE_COLOR
	_rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _rope_mat)
	for i in 3:
		var p: Vector3 = pts[i]
		var tan: Vector3 = (pts[mini(i + 1, 2)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tan.cross((eye - p).normalized())
		side = side.normalized() * ROPE_W * 0.5 if side.length() > 1e-4 else Vector3.RIGHT * ROPE_W * 0.5
		var c := glow
		if flame_t >= 0.0 and float(i) / 2.0 <= flame_t:
			c = Color(1.0, 0.62, 0.25)          # a chama corre pela corda (Lançar a Luz)
		_rope_mesh.surface_set_color(c if i > 0 else base)
		_rope_mesh.surface_add_vertex(p - side)
		_rope_mesh.surface_set_color(c if i > 0 else base)
		_rope_mesh.surface_add_vertex(p + side)
	_rope_mesh.surface_end()
