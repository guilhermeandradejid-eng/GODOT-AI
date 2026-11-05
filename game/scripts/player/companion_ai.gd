class_name CompanionAI
extends RefCounted
## Companheiro controlado pela IA (quando só há um jogador). Segue o líder sem
## grudar, pula obstáculos e buracos, plana (ágil), sobe na carona quando
## chamado, ocupa a placa de pressão livre quando o líder está na outra e, se
## ficar para trás ou cair, reaparece perto do líder como um rastro de luz.
##
## Regras dos itens (itens.md 7.2):
## - Segurar Posto: `hold_at(pos)` (TROCAR numa placa ou perto de um sino) faz a
##   IA ficar parada ali, sem seguir nem se teleportar, até o líder chamar
##   (DUPLA) ou o grupo ser resolvido (`release_hold()`).
## - Busca de placas até 40 m (só `is_plate`); placa pesada única (palma).
## - Sinos: vai ao sino não tocado mais distante e bate 0,3 s depois do líder;
##   Cristal-Eco: faz a sua parte 0,4 s depois (Hulvar: pulo + Barrigada; Sael: golpe).
## - Lanterna automática do Sael da IA; Pedido (`request_use`/`request_lamp`)
##   quando se joga de Hulvar no solo; argolas `ai: true` já passadas pelo líder.
## - Amarra: com o Arpéu e linha de visão, o Sael da IA se puxa até o líder por
##   uma corda em vez de virar rastro de luz.
## Tudo o que vem de outros sistemas (travas novas, HeroTools, Game.items) é
## lido com guardas, porque esses sistemas podem ainda não existir.

const PLATE_SEARCH := 40.0         ## alcance da busca de placa parceira
const WARP_DIST := 42.0            ## acima disso (sem posto) vira rastro de luz
const POST_WISP := 20.0            ## posto/sino mais longe que isso: vai em rastro de luz
const CHIME_NEAR := 8.0            ## líder a essa distância de um sino ativa a regra
const CHIME_DELAY := 0.3           ## golpe da IA depois do golpe do líder
const ECO_DELAY := 0.4             ## parte da IA no Cristal-Eco
const ECO_PARTNER := 9.0           ## parceiro a até 9 m faz a sua parte
const CALL_RANGE := 9.0            ## DUPLA como Sael libera o posto a até 9 m
const HEAVY_WAIT := 1.0            ## líder parado perto da placa pesada única
const HEAVY_NEAR := 4.0
const LAMP_RANGE := 12.0           ## lanterna automática
const LAMP_OFF_T := 5.0
const FIGHT_LEADER := 6.0          ## combate leve: Silentes a até 6 m do líder
const FIGHT_CD := 1.5
const AMARRA_RANGE := 60.0
const AMARRA_SPEED := 24.0
const AMARRA_ACCEL := 60.0

## Grupos que já foram resolvidos alguma vez (PuzzleGroups pode não existir).
static var _solved_ever := {}
static var _pg = null
static var _pg_checked := false

var leader: Hero
var follow_dist := 2.4
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _repath_t := 0.0
var _jump_cd := 0.0
var _plate_target = null
var _idle_t := 0.0
var _me: Hero
var _clock := 0.0

# Segurar Posto
var holding := false
var hold_pos := Vector3.ZERO
var hold_group := ""
var ai_icon := ""                  ## "hold" | "ready" | "" (a HUD pode ler; também vira um Label3D)
var _label: Label3D

# sinos
var _chime = null                  ## sino onde a IA espera ("pronto")
var _strike_node = null            ## sino do golpe agendado
var _strike_at := -1.0
var _strike_eco := false
var _leader_atk := false
var _leader_pound := false

# ações agendadas: [[relógio, "jump"|"action"], ...]
var _seq: Array = []

# placa pesada única
var _heavy_plate = null
var _heavy_t := 0.0

# lanterna
var _lamp_auto := false
var _lamp_idle_t := 0.0
var _lamp_cd := 0.0
var _lamp_block_t := 0.0
var _lamp_scan_t := 0.0
var _lamp_want := false

# Pedido
var _req_use := false
var _req_lamp := false
var _req_wait := 0.0

# argolas
var _ring_passed := {}
var _ring_used := {}

# Amarra
var _amarra := false
var _amarra_t := 0.0
var _amarra_v := 0.0
var _amarra_last := Vector3.ZERO
var _amarra_still := 0.0
var _rope: MeshInstance3D

# combate / pausas
var _fight_cd := 0.0
var _freeze_t := 0.0


func _init(l: Hero) -> void:
	leader = l


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_label):
			_label.queue_free()
		if is_instance_valid(_rope):
			_rope.queue_free()


# =================================================================== API pública
## Segurar Posto: fica em `pos` até ser chamado ou o grupo ser resolvido.
## Sem `group`, usa o grupo da placa ou do sino que estiver ali.
func hold_at(pos: Vector3, group := "") -> void:
	holding = true
	hold_pos = pos
	hold_group = group if group != "" else _group_at(pos)
	_plate_target = null
	_chime = null
	_set_icon("hold")


func release_hold() -> void:
	if not holding:
		return
	holding = false
	hold_group = ""
	_set_icon("")


## O líder apertou DUPLA (repasse da HeroParty): como Hulvar sempre chama; como
## Sael, só a até 9 m.
func on_leader_call() -> void:
	if not holding or _me == null or leader == null:
		return
	if leader.hero_id == "strong" or leader.global_position.distance_to(_me.global_position) <= CALL_RANGE:
		release_hold()


## Pedido (jogando de Hulvar no solo): USAR e chip mandam o Sael da IA agir.
func request_use() -> void:
	_req_use = true
	_req_wait = 0.0


func request_lamp() -> void:
	_req_lamp = true


## Para a IA por `t` s (ex.: o Hulvar da IA sendo mirado pelo Embarque Relâmpago).
func freeze(t: float) -> void:
	_freeze_t = maxf(_freeze_t, t)


func pause(t: float) -> void:
	freeze(t)


# =================================================================== laço
func poll(intent: PlayerInput, me: Hero, delta: float) -> void:
	_me = me
	intent.move = Vector2.ZERO
	intent.jump = false
	intent.action = false
	intent.set("use", false)
	if leader == null or not is_instance_valid(leader):
		return
	_clock += delta
	_jump_cd = maxf(0.0, _jump_cd - delta)
	_fight_cd = maxf(0.0, _fight_cd - delta)
	_freeze_t = maxf(0.0, _freeze_t - delta)
	_lamp_cd = maxf(0.0, _lamp_cd - delta)
	_lamp_block_t = maxf(0.0, _lamp_block_t - delta)
	_run_seq(intent)
	_lamp_rule(intent, me, delta)
	_check_hold_release(me)
	if me.state == Hero.S.RIDE:
		# rider: stays put; jumps off if the leader launches far away
		if holding:
			release_hold()
		_pedido(intent, me, delta)
		return
	if _amarra:
		_amarra_step(me, delta)
		return
	_watch_leader_strikes(me)
	if _freeze_t > 0.0 or _in_hook(me):
		_pedido(intent, me, delta)
		return
	_heavy_plate_rule(me, delta)
	_chime_rule(me)
	var target := leader.global_position
	var post := false
	var want := follow_dist
	if holding:
		target = hold_pos
		post = true
		want = 0.15
	elif _strike_node != null and is_instance_valid(_strike_node):
		target = _chime_spot(me, _strike_node)
		post = true
		want = 0.4
	elif _chime != null:
		target = _chime_spot(me, _chime)
		post = true
		want = 0.4
	else:
		# help with pressure plates: go to the free partner plate
		_plate_target = _find_plate(me)
		if _plate_target != null:
			target = _plate_target.global_position
			post = true
			want = 0.15
	# combate leve (Hulvar da IA): Silentes expostos perto do líder
	var foe = null
	if not post and me.hero_id == "strong":
		foe = _find_foe(me)
		if foe != null:
			target = foe.global_position
			want = 1.4
	var to := target - me.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	if post:
		# posto ativo: sem teleporte por distância; longe do posto, rastro de luz
		if dist > POST_WISP or me.global_position.y < target.y - 22.0:
			_warp_to(me, target + Vector3.UP * 1.0, leader.facing)
			return
	# teleport if far behind (launchers, rifts) or stuck far below/above on the dunes
	elif dist > WARP_DIST or (to.y > 16.0 and dist > 6.0) or (me.global_position.y < leader.global_position.y - 22.0):
		_catch_up(me)
		return
	if dist > want:
		var dir := flat / dist
		var speed01 := clampf((dist - want) / 4.0, 0.25, 1.0)
		var cam_basis := Basis(Vector3.UP, me.cam_yaw)
		var local := cam_basis.inverse() * (dir * speed01)
		intent.move = Vector2(local.x, local.z)
		_idle_t = 0.0
	else:
		_idle_t += delta
	if foe != null:
		_fight(intent, me, foe, dist)
	_strike_rule(intent, me)
	# obstacles & gaps
	if intent.move.length() > 0.1 and me.state == Hero.S.GROUND and _jump_cd <= 0.0:
		var fwd := Vector3(sin(me.facing), 0, cos(me.facing))
		var space := me.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(me.global_position + Vector3.UP * 0.35,
				me.global_position + Vector3.UP * 0.35 + fwd * 0.9, Hero.LAYER_WORLD)
		var wall := space.intersect_ray(q)
		var ahead := me.global_position + fwd * 1.4 + Vector3.UP * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 3.5, Hero.LAYER_WORLD)
		var ground := space.intersect_ray(q2)
		var leader_higher := to.y > 1.2 and dist < 4.0
		if not wall.is_empty() or ground.is_empty() or leader_higher:
			intent.press("jump")
			intent.jump = true
			_jump_cd = 0.6
	if me.state in [Hero.S.AIR, Hero.S.GLIDE] and _seq.is_empty():
		intent.jump = me.velocity.y > 0.0 or (me.hero_id == "agile" and me.global_position.y > target.y + 0.5 and dist > 3.0)
		if me.hero_id == "agile" and me.state == Hero.S.AIR and me.velocity.y < -2.0 and dist > 3.0 and me.air_jumps > 0:
			intent.press("jump")
	# stuck detection
	if intent.move.length() > 0.3:
		if me.global_position.distance_to(_last_pos) < 0.02:
			_stuck_t += delta
		else:
			_stuck_t = 0.0
		if _stuck_t > 1.6:
			if post:
				_warp_to(me, target + Vector3.UP * 1.0, leader.facing)
			else:
				_catch_up(me)
	_last_pos = me.global_position
	_ring_rule(intent, me)
	_pedido(intent, me, delta)
	# idle agile hops on strong if the leader is strong and standing still for a while
	if not post and me.hero_id == "agile" and leader.hero_id == "strong" and leader.rider == null and _idle_t > 6.0 \
			and leader.velocity.length() < 0.2 and dist < 2.6:
		_idle_t = 0.0
		me.mount_on(leader)


# =================================================================== placas
func _find_plate(me: Hero):
	var plates := me.get_tree().get_nodes_in_group(&"plates")
	var leader_plate = null
	for p in plates:
		if is_plate(p) and p.occupied_by(leader):
			leader_plate = p
			break
	if leader_plate == null:
		return null
	if group_done(leader_plate.group_id):
		return null
	var best = null
	var bd := PLATE_SEARCH
	for p in plates:
		if p == leader_plate or not is_plate(p) or p.group_id != leader_plate.group_id:
			continue
		if p.heavy and not me.is_heavy():
			continue
		var d: float = p.global_position.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = p
	return best


## Placa pesada única (palma): o Sael líder espera 1,0 s a até 4 m e o Hulvar
## da IA sobe nela e segura até o grupo ser resolvido.
func _heavy_plate_rule(me: Hero, delta: float) -> void:
	if holding or me.hero_id != "strong" or leader.hero_id != "agile":
		_heavy_t = 0.0
		return
	var found = null
	var plates := me.get_tree().get_nodes_in_group(&"plates")
	for p in plates:
		if not is_plate(p) or not p.heavy or group_done(p.group_id):
			continue
		var d: Vector3 = p.global_position - leader.global_position
		if Vector2(d.x, d.z).length() > HEAVY_NEAR:
			continue
		var n := 0
		for q in plates:
			if q.get("group_id") == p.group_id:
				n += 1
		if n == 1:
			found = p
			break
	if found == null or found != _heavy_plate:
		_heavy_plate = found
		_heavy_t = 0.0
		return
	_heavy_t += delta
	if _heavy_t >= HEAVY_WAIT:
		_heavy_t = 0.0
		hold_at(found.global_position, found.group_id)


func _check_hold_release(me: Hero) -> void:
	if not holding:
		return
	if hold_group != "" and group_done(hold_group):
		release_hold()
	elif me.state == Hero.S.RIDE:
		release_hold()


## Grupo da placa (ocupável) ou do sino a até 2 m de `pos`.
func _group_at(pos: Vector3) -> String:
	if _me == null and leader == null:
		return ""
	var tree := (leader if leader != null else _me).get_tree()
	for p in tree.get_nodes_in_group(&"plates"):
		var k := lock_kind(p)
		var d: float = (p.global_position as Vector3).distance_to(pos)
		if (k == "plate" and d < 1.6) or (k == "chime" and d < 2.0 + 1.2 * _size(p)):
			return String(p.get("group_id"))
	return ""


# =================================================================== sinos
func _chimes(me: Hero) -> Array:
	var out := []
	for p in me.get_tree().get_nodes_in_group(&"plates"):
		if lock_kind(p) == "chime":
			out.append(p)
	return out


func _size(c) -> float:
	var s = c.get("size")
	return float(s) if s != null else 1.0


static func _need(c) -> Array:
	var n = c.get("need")
	return n if n is Array else ["any"]


## Cristal-Eco: sino com vários tipos de golpe exigidos (ex.: ["slam", "staff"]).
static func is_eco(c) -> bool:
	var n := _need(c)
	return n.size() > 1 and not ("any" in n)


func _can_touch(me: Hero, c) -> bool:
	if c.get("last") == true and not done_except(c):
		return false
	for k in _need(c):
		match String(k):
			"any":
				return true
			"staff":
				if me.hero_id == "agile" and has_item("bastao"):
					return true
			"slam":
				if me.hero_id == "strong":
					return true
	return false


## Lugar de espera ao lado do sino, do lado de onde a IA vem.
func _chime_spot(me: Hero, c) -> Vector3:
	var cp: Vector3 = c.global_position
	var d := me.global_position - cp
	d.y = 0.0
	if d.length() < 0.05:
		d = Vector3(1, 0, 0)
	return cp + d.normalized() * (1.2 * _size(c) + 0.3)


func _chime_rule(me: Hero) -> void:
	if _chime != null and (not is_instance_valid(_chime) or group_done(_chime.group_id)):
		_chime = null
	if _strike_node != null and (not is_instance_valid(_strike_node) or group_done(_strike_node.group_id)):
		_strike_node = null
	var lp := leader.global_position
	var all := _chimes(me)
	if _chime == null:
		for c in all:
			if group_done(c.group_id):
				continue
			var d: Vector3 = c.global_position - lp
			if Vector2(d.x, d.z).length() <= CHIME_NEAR:
				_chime = _pick_chime(me, all, String(c.group_id))
				break
	else:
		# líder foi embora (> 30 m de todos os sinos do grupo): volta a seguir
		var near := false
		for c in all:
			if c.group_id == _chime.group_id and (c.global_position as Vector3).distance_to(lp) < 30.0:
				near = true
		if not near:
			_chime = null
	if _chime != null and not holding:
		var d2 := me.global_position.distance_to(_chime_spot(me, _chime))
		_set_icon("ready" if d2 < 1.2 else "")
	elif not holding:
		_set_icon("")


## Sino não tocado mais distante do líder que a IA consegue tocar.
func _pick_chime(me: Hero, all: Array, group: String):
	var best = null
	var bd := -1.0
	for c in all:
		if String(c.group_id) != group or c.pressed or not _can_touch(me, c):
			continue
		var d: float = (c.global_position as Vector3).distance_to(leader.global_position)
		if d > bd:
			bd = d
			best = c
	return best


## Detecta o golpe do líder num sino e agenda o da IA.
func _watch_leader_strikes(me: Hero) -> void:
	var atk := leader.is_attacking() and leader.state != Hero.S.POUND
	var pounding := leader.state == Hero.S.POUND
	var atk_edge := atk and not _leader_atk
	var pound_edge := _leader_pound and not pounding    # impacto da Barrigada
	_leader_atk = atk
	_leader_pound = pounding
	if not atk_edge and not pound_edge:
		return
	var lp := leader.global_position
	for c in _chimes(me):
		if group_done(c.group_id):
			continue
		var cp: Vector3 = c.global_position
		var reach := 1.2 * _size(c) + (3.6 if atk_edge else 2.4)
		if pound_edge and "slam" in _need(c):
			var sr = c.get("slam_radius")
			reach = maxf(reach, float(sr) if sr != null else 9.0)
		if cp.distance_to(lp) > reach:
			continue
		if is_eco(c):
			if _can_touch(me, c) and cp.distance_to(me.global_position) <= ECO_PARTNER:
				_schedule_strike(c, ECO_DELAY, true)
			return
		if _chime != null and _chime != c and String(_chime.group_id) == String(c.group_id) and not _chime.pressed:
			_schedule_strike(_chime, CHIME_DELAY, false)
			return


func _schedule_strike(c, delay: float, eco: bool) -> void:
	_strike_node = c
	_strike_at = _clock + delay
	_strike_eco = eco


## Executa o golpe agendado quando a hora chega e a IA está ao alcance.
func _strike_rule(intent: PlayerInput, me: Hero) -> void:
	if _strike_node == null:
		return
	if not is_instance_valid(_strike_node) or _clock > _strike_at + 1.6:
		_strike_node = null
		return
	if _clock < _strike_at:
		return
	var c = _strike_node
	var cp: Vector3 = c.global_position
	var d := cp - me.global_position
	var flat := Vector2(d.x, d.z).length()
	if me.hero_id == "strong" and (_strike_eco or not ("any" in _need(c))):
		# Barrigada: pulo + ação no ar (vale a até slam_radius pelos pound_listeners)
		var sr = c.get("slam_radius")
		if flat <= (float(sr) if sr != null else 9.0) - 0.5 and me.state == Hero.S.GROUND:
			_seq = [[_clock, "jump"], [_clock + 0.22, "action"]]
			_strike_node = null
		return
	var reach := 1.2 * _size(c) + (1.6 if me.hero_id == "agile" else 1.4)
	if flat <= reach and me.state == Hero.S.GROUND:
		me.facing = atan2(d.x, d.z)
		intent.move = Vector2.ZERO
		intent.press("action")
		_strike_node = null


func _run_seq(intent: PlayerInput) -> void:
	while not _seq.is_empty() and _clock >= float(_seq[0][0]):
		var step: Array = _seq.pop_front()
		intent.press(String(step[1]))
		if step[1] == "jump":
			intent.jump = true
	if not _seq.is_empty():
		intent.jump = true      # segura o pulo até a ação no ar


# =================================================================== combate leve
func _exposed(e) -> bool:
	if e.get("dead") == true or e.get("veiled") != true:
		return false
	if e.has_method("is_exposed"):
		return e.is_exposed()
	return e.get("_exposed") == true


func _find_foe(me: Hero):
	var best = null
	var bd := INF
	for e in me.get_tree().get_nodes_in_group(&"enemies"):
		if not (e is Node3D) or not _exposed(e):
			continue
		var p: Vector3 = e.global_position
		if p.distance_to(leader.global_position) > FIGHT_LEADER:
			continue
		var d := p.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = e
	return best


## Hulvar da IA: Aríete (≤ 2 m) ou pulo + Barrigada (≤ 3,4 m). Recarga de 1,5 s.
func _fight(intent: PlayerInput, me: Hero, foe, dist: float) -> void:
	if _fight_cd > 0.0 or me.state != Hero.S.GROUND or not _seq.is_empty():
		return
	var d: Vector3 = foe.global_position - me.global_position
	if dist <= 2.0:
		me.facing = atan2(d.x, d.z)
		intent.press("action")
		_fight_cd = FIGHT_CD
	elif dist <= 3.4:
		_seq = [[_clock, "jump"], [_clock + 0.22, "action"]]
		_fight_cd = FIGHT_CD


# =================================================================== lanterna
func _lamp_lit(me: Hero) -> bool:
	var tools = me.get("tools")
	if tools != null:
		for k in ["lamp_on", "lantern_on", "lamp_lit", "lit"]:
			var v = tools.get(k)
			if v is bool:
				return v
	var lp = Game.get("lantern_pos")
	return lp is Vector3 and is_finite((lp as Vector3).x)


func _lamp_reason(me: Hero) -> bool:
	var p := me.global_position
	for e in me.get_tree().get_nodes_in_group(&"enemies"):
		if e is Node3D and e.get("veiled") == true and e.get("dead") != true \
				and (e.global_position as Vector3).distance_to(p) <= LAMP_RANGE:
			return true
	for n in me.get_tree().get_nodes_in_group(&"plates"):
		if (n.global_position as Vector3).distance_to(p) > LAMP_RANGE:
			continue
		var k := lock_kind(n)
		if k == "brazier" and not n.pressed:
			return true
		if k == "chime" and n.get("dark") == true and not group_done(n.group_id):
			return true
	return false


## Sael da IA com a Lanterna: acende perto de Silente velado, Olho de Brasa
## apagado ou sino `dark`; apaga 5 s depois sem nenhum.
func _lamp_rule(intent: PlayerInput, me: Hero, delta: float) -> void:
	if me.hero_id != "agile" or not has_item("lanterna"):
		return
	var lit := _lamp_lit(me)
	if _req_lamp:
		_req_lamp = false
		intent.press("lamp")
		_lamp_cd = 0.4
		_lamp_auto = false
		if lit:
			_lamp_block_t = 10.0     # apagou de propósito: a IA não reacende logo
		return
	_lamp_scan_t -= delta
	if _lamp_scan_t <= 0.0:
		_lamp_scan_t = 0.25
		_lamp_want = _lamp_reason(me)
	if _lamp_want:
		_lamp_idle_t = 0.0
		if not lit and _lamp_cd <= 0.0 and _lamp_block_t <= 0.0:
			intent.press("lamp")
			_lamp_cd = 0.6
			_lamp_auto = true
	else:
		_lamp_idle_t += delta
		if lit and _lamp_auto and _lamp_idle_t >= LAMP_OFF_T and _lamp_cd <= 0.0:
			intent.press("lamp")
			_lamp_cd = 0.6
			_lamp_auto = false


# =================================================================== Pedido
## Executa o USAR pedido pelo jogador (de Hulvar): mira com origem no Sael e
## direção da câmera, puxando para o alvo de quebra-cabeça mais provável.
func _pedido(intent: PlayerInput, me: Hero, delta: float) -> void:
	if not _req_use:
		return
	if me.hero_id != "agile":
		_req_use = false
		return
	_req_wait = maxf(0.0, _req_wait - delta)
	if _req_wait > 0.0:
		return
	var t = _pedido_target(me)
	var aim := Vector3(-sin(leader.cam_yaw), 0.0, -cos(leader.cam_yaw))
	if t != null:
		var d: Vector3 = (t.global_position as Vector3) - me.global_position
		d.y = 0.0
		if d.length() > 0.1:
			aim = d.normalized()
		# Lançar a Luz precisa da lanterna acesa: acende antes e tenta de novo
		if lock_kind(t) == "brazier" and not _lamp_lit(me) and has_item("lanterna"):
			intent.press("lamp")
			_lamp_cd = 0.6
			_lamp_auto = true
			_req_wait = 0.2
			return
	me.cam_yaw = atan2(-aim.x, -aim.z)
	intent.move = Vector2.ZERO
	intent.press("use")
	_req_use = false


func _pedido_target(me: Hero):
	var p := me.global_position + Vector3.UP * 0.6
	var cam := Vector3(-sin(leader.cam_yaw), 0.0, -cos(leader.cam_yaw))
	var cands := []
	var tree := me.get_tree()
	if has_item("arpeu"):
		for r in tree.get_nodes_in_group(&"hook_targets"):
			if r.get("mode") == "pull" and r.get("pressed") != true:
				if r.get("heavy") == true and me.state != Hero.S.RIDE:
					continue
				cands.append([r, 12.0])
		for s in tree.get_nodes_in_group(&"relics"):
			if s.get("pull") == true and s.get("taken") != true and s.visible:
				cands.append([s, 12.0])
		if has_item("lanterna"):
			for n in tree.get_nodes_in_group(&"plates"):
				if lock_kind(n) == "brazier" and not n.pressed:
					cands.append([n, 14.0])
	if has_item("concha"):
		for n in tree.get_nodes_in_group(&"plates"):
			if lock_kind(n) == "drift" and not n.pressed:
				cands.append([n, 10.0])
		for n in tree.get_nodes_in_group(&"wind_listeners"):
			if n.has_method("part") and n is Node3D:
				cands.append([n, 12.0])
	var best = null
	var bs := INF
	for c in cands:
		var n: Node3D = c[0]
		var d := n.global_position - p
		var L := d.length()
		if L > float(c[1]) or L < 0.01:
			continue
		var flat := Vector3(d.x, 0, d.z).normalized()
		var ang := acos(clampf(flat.dot(cam), -1.0, 1.0))
		var score := L / float(c[1]) + (0.0 if ang < deg_to_rad(75.0) else 1.0)
		if score < bs:
			bs = score
			best = n
	return best


# =================================================================== argolas
## Sael da IA: usa só argolas `ai: true` que o líder já passou.
func _ring_rule(intent: PlayerInput, me: Hero) -> void:
	if me.hero_id != "agile" or not has_item("arpeu"):
		return
	if not (me.state in [Hero.S.GROUND, Hero.S.AIR, Hero.S.GLIDE, Hero.S.SURF]):
		return
	var chest := me.global_position + Vector3.UP * 0.6
	for r in me.get_tree().get_nodes_in_group(&"hook_targets"):
		if r.get("ai") != true or not (r is Node3D):
			continue
		var rp: Vector3 = r.global_position
		var ld := rp - leader.global_position
		if Vector2(ld.x, ld.z).length() < 10.0:
			_ring_passed[r] = true
		if not _ring_passed.has(r) or _clock - float(_ring_used.get(r, -99.0)) < 4.0:
			continue
		var mode := String(r.get("mode")) if r.get("mode") != null else "zip"
		var rng := 20.0 if mode == "zip" else (14.0 if mode == "swing" else 12.0)
		var d := rp - chest
		var L := d.length()
		if L > rng or L < 2.0:
			continue
		var elev := rad_to_deg(asin(clampf(d.y / L, -1.0, 1.0)))
		if elev < 15.0 or elev > 85.0:
			continue
		var flat := Vector3(d.x, 0, d.z).normalized()
		var hv := Vector3(me.velocity.x, 0, me.velocity.z)
		if hv.length() > 1.0 and hv.normalized().dot(flat) < cos(deg_to_rad(45.0)):
			continue
		var local := Basis(Vector3.UP, me.cam_yaw).inverse() * (flat * 0.6)
		intent.move = Vector2(local.x, local.z)
		intent.press("use")
		_ring_used[r] = _clock
		return


func _in_hook(me: Hero) -> bool:
	for k in ["HOOK", "SWING", "ZIPLINE"]:
		var v = Hero.S.get(k, -1)
		if v >= 0 and me.state == v:
			return true
	return false


# =================================================================== rastro de luz / Amarra
## Fica para trás: com o Arpéu e linha de visão, Amarra; senão, rastro de luz.
func _catch_up(me: Hero) -> void:
	_stuck_t = 0.0
	if me.hero_id == "agile" and has_item("arpeu") and not _amarra:
		var goal := _amarra_goal()
		if goal.distance_to(me.global_position) <= AMARRA_RANGE and _los(me, me.global_position + Vector3.UP * 0.6, goal):
			_start_amarra(me)
			return
	_warp(me)


func _amarra_goal() -> Vector3:
	var back := -Vector3(sin(leader.facing), 0, cos(leader.facing)) * 1.6
	return leader.global_position + back + Vector3.UP * 1.0


func _los(me: Hero, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, Hero.LAYER_WORLD)
	var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.6


func _start_amarra(me: Hero) -> void:
	_amarra = true
	_amarra_t = 0.0
	_amarra_v = maxf(8.0, me.velocity.length())
	_amarra_last = me.global_position
	_amarra_still = 0.0
	if me.state in [Hero.S.GROUND, Hero.S.SURF, Hero.S.SWIM]:
		me.set_state(Hero.S.AIR)
	if me.visual != null:
		me.visual.restart_state("grapple_throw" if me.visual.has_state("grapple_throw") else "jump")
	Sfx.play_at("hook_throw", me.global_position)
	Fx.burst("sparkle", _amarra_goal(), Color(0.55, 1.0, 0.95), 0.5)


func _amarra_step(me: Hero, delta: float) -> void:
	_amarra_t += delta
	var goal := _amarra_goal()
	var d := goal - me.global_position
	var L := d.length()
	if me.global_position.distance_to(_amarra_last) < 0.04:
		_amarra_still += delta
	else:
		_amarra_still = 0.0
	_amarra_last = me.global_position
	if L < 1.3 or _amarra_t > 4.0 or _amarra_still > 0.3:
		var ok := L < 3.0
		_end_amarra(me)
		if ok:
			me.velocity = d.normalized() * 4.0 + Vector3.UP * 6.0
			me.air_jumps = 1
		else:
			_warp(me)
		return
	_amarra_v = minf(AMARRA_SPEED, _amarra_v + AMARRA_ACCEL * delta)
	me.velocity = d / L * _amarra_v
	me.facing = atan2(d.x, d.z)
	if me.state != Hero.S.AIR:
		me.set_state(Hero.S.AIR)
	if me.visual != null and _amarra_t > 0.18:
		var clip := "swing" if me.visual.has_state("swing") else "fall"
		if me.visual.state != clip:
			me.visual.set_state(clip, 0.15)
	_draw_rope(me, goal)


func _end_amarra(me: Hero) -> void:
	_amarra = false
	if is_instance_valid(_rope):
		_rope.visible = false
	me.set_state(Hero.S.AIR)


## Corda simples: faixa de 2 segmentos (2,5 cm) da mão ao alvo.
func _draw_rope(me: Hero, to: Vector3) -> void:
	if not is_instance_valid(_rope):
		_rope = MeshInstance3D.new()
		_rope.top_level = true
		_rope.mesh = ImmediateMesh.new()
		_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.62, 0.3, 0.22)
		m.emission_enabled = true
		m.emission = Color(0.31, 0.89, 0.84)
		m.emission_energy_multiplier = 0.4
		_rope.material_override = m
		me.add_child(_rope)
	_rope.visible = true
	_rope.global_transform = Transform3D.IDENTITY
	rope_strip(_rope.mesh as ImmediateMesh, me.global_position + Vector3.UP * 1.0, to)


## Faixa de corda de 2 segmentos, virada para cima (usada também pela NetPuppet).
static func rope_strip(im: ImmediateMesh, a: Vector3, b: Vector3, w := 0.025) -> void:
	im.clear_surfaces()
	var dir := b - a
	if dir.length() < 0.01:
		return
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized() * w * 0.5
	var mid := (a + b) * 0.5 + Vector3.DOWN * minf(0.25, dir.length() * 0.02)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in [a, mid, b]:
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
	im.surface_end()


func _warp(me: Hero) -> void:
	_stuck_t = 0.0
	var back := -Vector3(sin(leader.facing), 0, cos(leader.facing)) * 1.8 + Vector3(0.8, 0, 0)
	_warp_to(me, leader.global_position + back + Vector3.UP * 1.2, leader.facing)


func _warp_to(me: Hero, p: Vector3, yaw: float) -> void:
	_stuck_t = 0.0
	Fx.burst("wisp", me.global_position + Vector3.UP * 0.5)
	me.teleport(p, yaw)
	me.set_state(Hero.S.AIR)
	Fx.burst("wisp", p)


# =================================================================== ícone
func _set_icon(kind: String) -> void:
	if kind == ai_icon:
		return
	ai_icon = kind
	if _me == null or not is_instance_valid(_me):
		return
	if kind == "":
		if is_instance_valid(_label):
			_label.visible = false
		return
	if not is_instance_valid(_label):
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0018
		_label.font_size = 26
		_label.outline_size = 8
		_label.outline_modulate = Color(0.1, 0.08, 0.2, 0.85)
		var f = load("res://game/assets/fonts/Fredoka.ttf")
		if f is Font:
			_label.font = f
		_label.position = Vector3.UP * (2.2 if _me.hero_id == "agile" else 4.0)
		_me.add_child(_label)
	_label.visible = true
	_label.text = "segurando o posto" if kind == "hold" else "pronto!"
	_label.modulate = Color(1.0, 0.86, 0.5) if kind == "hold" else Color(0.6, 1.0, 0.95)


# =================================================================== utilitários (estáticos)
static func has_item(id: String) -> bool:
	return Game.has_method("has_item") and bool(Game.call("has_item", id))


## Placa de pressão de verdade (`is_plate`). Antes das travas novas existirem,
## qualquer nó de `plates` com `occupied_by` conta como placa.
static func is_plate(p) -> bool:
	var v = p.get("is_plate")
	if v == null:
		return p.has_method("occupied_by") and p.get("need") == null and not p.is_in_group(&"hook_targets")
	return bool(v)


## Tipo de trava por "duck typing": plate | chime | ring | brazier | drift | lock.
static func lock_kind(n) -> String:
	if is_plate(n):
		return "plate"
	if n.get("need") is Array:
		return "chime"
	if n.is_in_group(&"hook_targets") or (n.get("mode") is String and n.get("travel") != null):
		return "ring"
	if n.get("mount") is String or n.has_method("ignite") or n.has_method("light_up"):
		return "brazier"
	if n.has_method("on_gust") or n.has_method("blow"):
		return "drift"
	return "lock"


static func _puzzle_groups():
	if _pg_checked:
		return _pg
	_pg_checked = true
	for c in ProjectSettings.get_global_class_list():
		var cls := String(c.get("class", ""))
		if cls == "PuzzleGroups":
			_pg = load(String(c["path"]))
		elif cls == "ToolPuzzles" and _pg == null:
			var s = load(String(c["path"]))
			if s is Script and (s as Script).get_script_constant_map().has("PuzzleGroups"):
				_pg = (s as Script).get_script_constant_map()["PuzzleGroups"]
	if _pg != null:
		var names := []
		for m in (_pg as Script).get_script_method_list():
			names.append(String(m["name"]))
		if not ("solved" in names):
			_pg = null
	return _pg


## Grupo resolvido: PuzzleGroups.solved(group) quando existir; senão, todos os
## membros de `plates` do grupo `pressed`. Uma vez resolvido, fica resolvido.
static func group_done(group) -> bool:
	var g := String(group)
	# memória por fase: uma partida nova começa sem grupos resolvidos
	var lid := Game.level.get_instance_id() if is_instance_valid(Game.level) else 0
	if int(_solved_ever.get("@level", 0)) != lid:
		_solved_ever.clear()
		_solved_ever["@level"] = lid
	if g == "" or g == "@level" or _solved_ever.has(g):
		return _solved_ever.has(g)
	var pg = _puzzle_groups()
	var done := false
	if pg != null:
		done = bool(pg.call("solved", g))
	else:
		var tree := Engine.get_main_loop() as SceneTree
		var n := 0
		done = true
		for p in tree.get_nodes_in_group(&"plates"):
			if String(p.get("group_id")) == g:
				n += 1
				if not p.pressed:
					done = false
					break
		done = done and n > 0
	if done:
		_solved_ever[g] = true
	return done


## Os outros membros do grupo de `node` estão feitos (para travas `last`).
static func done_except(node) -> bool:
	var pg = _puzzle_groups()
	if pg != null:
		for m in (pg as Script).get_script_method_list():
			if String(m["name"]) == "done_except":
				return bool(pg.call("done_except", node))
	var tree := Engine.get_main_loop() as SceneTree
	for p in tree.get_nodes_in_group(&"plates"):
		if p != node and p.get("group_id") == node.get("group_id") and not p.pressed:
			return false
	return true
