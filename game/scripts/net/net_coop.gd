extends Node
## Co-op em rede local (Wi-Fi) com ENet: quem cria a sala joga com a
## personagem ágil, quem entra joga com a forte. Descoberta automática por broadcast UDP.
## Cada aparelho é dono do próprio herói (envia estado a 30 Hz); eventos do
## mundo (centelhas, Pedras das Horas, Silentes vencidos, lançamento) vão por RPC confiável.
## Itens e travas (itens.md 7.3): o anfitrião (sempre o Sael) é autoritativo.
## `_item_taken`, `_puzzle_event` e `_enemy_hit` são confiáveis e idempotentes
## (eventos repetidos são ignorados); do cliente o anfitrião só aceita `rung` e
## `mark_slam` (golpes do Hulvar nos sinos). O estado do herói leva `tool_bits`
## (1 lanterna acesa, 2 erguida, 4 corda) e `rope_to` para o par desenhar.

signal hosts_changed(hosts: Array)
signal connected(as_host: bool)
signal failed(msg: String)

const PORT := 47110
const DISCOVERY_PORT := 47111
const MAGIC := "YLVAAR1"

var peer: ENetMultiplayerPeer
var is_host := false
var level: GameLevel
var mine: Hero
var other: Hero
var puppet: NetPuppet
var _udp: PacketPeerUDP
var _listen: PacketPeerUDP
var _hosts := {}
var _beacon_t := 0.0
var _send_t := 0.0
var _started := false

const PERMANENT_EVENTS := ["lit", "blown", "pulled", "latched"]
const CLIENT_EVENTS := ["rung", "mark_slam"]
const EVENT_REPEAT_MS := 800

var _events := {}           ## "chave|tipo" -> msec (eventos já enviados/recebidos)
var _applying := false
var _hp_seen := {}          ## nome do Silente -> PV visto
var _remote_item := false
var _latched_seen := {}
var _parted_seen := {}
var _solved_sent := {}
var _watch_t := 0.0
var _mine_atk := false


func host() -> String:
	stop()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		failed.emit("Não deu para criar a sala (erro %d)" % err)
		return ""
	multiplayer.multiplayer_peer = peer
	is_host = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	return local_ip()


func discover() -> void:
	if _listen == null:
		_listen = PacketPeerUDP.new()
		var err := _listen.bind(DISCOVERY_PORT)
		if err != OK:
			failed.emit("Não deu para procurar salas (porta ocupada)")
			_listen = null


func join(ip: String) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		failed.emit("Não deu para conectar (erro %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	multiplayer.connected_to_server.connect(func(): connected.emit(false), CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(func(): failed.emit("A conexão falhou. Mesma rede Wi-Fi?"), CONNECT_ONE_SHOT)
	multiplayer.server_disconnected.connect(_on_peer_disconnected.bind(1))


func stop() -> void:
	_started = false
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
	if _udp != null:
		_udp.close()
		_udp = null
	if _listen != null:
		_listen.close()
		_listen = null


func local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


func _on_peer_connected(_id: int) -> void:
	if is_host and not _started:
		connected.emit(true)


func _on_peer_disconnected(_id: int) -> void:
	Game.show_toast("O outro jogador saiu. %s volta a ser controlado pela IA." % HeroDefs.display_name("strong"), 3.5)
	if puppet != null:
		puppet.release()
	if level != null and other != null:
		other.is_remote = false
		other.controller = CompanionAI.new(mine)
		other.player_index = -1
		Game.mode = Game.Mode.SOLO


func start_game(lv: GameLevel) -> void:
	level = lv
	_started = true
	if _udp != null:
		_udp.close()
		_udp = null
	mine = lv.party.agile if is_host else lv.party.strong
	other = lv.party.strong if is_host else lv.party.agile
	puppet = NetPuppet.new()
	lv.party.assign_network(mine, puppet)
	Game.net_peer_hero = mine.hero_id
	Game.motes_changed.connect(func(_t): pass)
	# world events
	var field := get_tree().get_first_node_in_group(&"motes")
	if field != null:
		field.set_meta("net", self)
	Game.relic_collected.connect(_on_local_seed)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		e.defeated.connect(_on_local_enemy)
	# itens e travas novas
	if Game.has_signal("item_collected"):
		Game.connect("item_collected", _on_local_item)
	_connect_locks()
	add_to_group(&"pound_listeners")
	Game.show_toast("Co-op na rede: você é %s!" % HeroDefs.display_name("agile" if is_host else "strong"), 3.0)


func _process(delta: float) -> void:
	# host beacon
	if _udp != null and not _started:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			_udp.put_packet(("%s|%s" % [MAGIC, local_ip()]).to_utf8_buffer())
	# client listening
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var msg := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			if msg.begins_with(MAGIC):
				if not _hosts.has(ip):
					changed = true
				_hosts[ip] = Time.get_ticks_msec()
		for ip in _hosts.keys():
			if Time.get_ticks_msec() - int(_hosts[ip]) > 4000:
				_hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit(_hosts.keys())
	# state sync
	if _started and mine != null and multiplayer.multiplayer_peer != null:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / 30.0
			var ts := tool_state(mine)
			_hero_state.rpc(mine.global_position, mine.velocity, mine.facing, mine.state,
				mine.visual.state if mine.visual != null else "loco", mine.petals, int(ts[0]), ts[1] as Vector3)
		_watch_t -= delta
		if _watch_t <= 0.0:
			_watch_t = 0.25
			_watch_world()
		_watch_ram()


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _hero_state(pos: Vector3, vel: Vector3, facing: float, state: int, vis: String, petals: int,
		tool_bits := 0, rope_to := Vector3.ZERO) -> void:
	if puppet == null or other == null:
		return
	puppet.push(pos, vel, facing, state, vis, tool_bits, rope_to)
	other.petals = petals
	# keep "rider" relations consistent across peers
	if other.hero_id == "agile":
		var strong := mine
		if state == Hero.S.RIDE and strong.rider == null:
			strong.rider = other
			strong.visual.set_glyph(true)
		elif state != Hero.S.RIDE and strong.rider == other:
			strong.rider = null
			strong.visual.set_glyph(false)


## Chamado pelo MoteField quando um herói local coleta.
func send_mote(i: int) -> void:
	_lume_taken.rpc(i)


@rpc("any_peer", "reliable", "call_remote")
func _lume_taken(i: int) -> void:
	var field := get_tree().get_first_node_in_group(&"motes")
	if field != null and i < field.alive.size() and field.alive[i]:
		field.alive[i] = false
		field.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), field.points[i]))
		Game.add_motes(1)


var _remote_seed := false


func _on_local_seed(id: String, _total: int) -> void:
	if not _remote_seed:
		_seed_taken.rpc(id)


@rpc("any_peer", "reliable", "call_remote")
func _seed_taken(id: String) -> void:
	_remote_seed = true
	for s in get_tree().get_nodes_in_group(&"relics"):
		if s.seed_id == id and not s.taken:
			s.taken = true
			s.visible = false
	Game.collect_relic(id)
	Game.show_toast("Seu parceiro achou uma Pedra das Horas! (%d/%d)" % [Game.relics.size(), Game.RELICS_TOTAL], 3.0)
	_remote_seed = false


var _remote_enemy := false


func _on_local_enemy(b: Node) -> void:
	if not _remote_enemy:
		_enemy_defeated.rpc(String(b.name))


@rpc("any_peer", "reliable", "call_remote")
func _enemy_defeated(enemy_name: String) -> void:
	_remote_enemy = true
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if String(e.name) == enemy_name and e.get("dead") != true:
			e.defeat(null)
	_remote_enemy = false


## Lançamento pedido pelo forte (cliente) para a ágil (host).
func request_catapult(v: Vector3) -> void:
	_do_catapult.rpc(v)


@rpc("any_peer", "reliable", "call_remote")
func _do_catapult(v: Vector3) -> void:
	if mine != null and mine.hero_id == "agile" and mine.state == Hero.S.RIDE:
		mine.dismount(v)
		mine.set_state(Hero.S.LAUNCH)
		mine.visual.restart_state("launch" if mine.visual.has_state("launch") else "double_jump")


# =================================================================== estado das ferramentas
## [tool_bits, rope_to] do herói local: 1 = lanterna acesa, 2 = erguida (raio 9 m),
## 4 = corda ativa. Usa `HeroTools.net_state()` quando existir; senão lê
## `Game.lantern_pos`/`lantern_radius` e os campos da corda do HeroTools.
static func tool_state(h: Hero) -> Array:
	var tools = h.get("tools")
	if tools != null and tools.has_method("net_state"):
		var st = tools.net_state()
		if st is Array and st.size() >= 2:
			return st
	var bits := 0
	var rope := Vector3.ZERO
	if h.hero_id == "agile":
		var lp = Game.get("lantern_pos")
		if lp is Vector3 and is_finite((lp as Vector3).x):
			bits |= 1
			var lr = Game.get("lantern_radius")
			if lr != null and float(lr) >= 8.5:
				bits |= 2
	if tools != null:
		for k in ["rope_to", "rope_end", "hook_point"]:
			var v = tools.get(k)
			if v is Vector3:
				rope = v
				break
		var active := false
		for k in ["rope_active", "rope_on", "rope_visible"]:
			if tools.get(k) == true:
				active = true
		if not active:
			for k in ["HOOK", "SWING", "ZIPLINE"]:
				if h.state == Hero.S.get(k, -1):
					active = true
		if active and rope != Vector3.ZERO:
			bits |= 4
	return [bits, rope]


# =================================================================== itens
func _on_local_item(id) -> void:
	if not _remote_item and _started:
		_item_taken.rpc(String(id))


@rpc("any_peer", "reliable", "call_remote")
func _item_taken(id: String) -> void:
	if Game.has_method("has_item") and bool(Game.call("has_item", id)):
		return    # idempotente
	_remote_item = true
	for grp in [&"tool_pedestals", &"pedestals", &"items"]:
		for n in get_tree().get_nodes_in_group(grp):
			var nid = n.get("item_id")
			if nid == null:
				nid = n.get("tool_id")
			if nid == null or String(nid) != id:
				continue
			if n.has_method("take_remote"):
				n.take_remote()
			elif n.get("taken") != null:
				n.set("taken", true)
				n.visible = false
	if Game.has_method("give_item"):
		Game.call("give_item", id)
	_remote_item = false


# =================================================================== travas
func _connect_locks() -> void:
	for n in get_tree().get_nodes_in_group(&"plates"):
		if CompanionAI.lock_kind(n) == "plate" or not n.has_signal("changed"):
			continue
		var cb := _on_lock_changed.bind(n)
		if not n.is_connected("changed", cb):
			n.connect("changed", cb)


static func _event_kind(n) -> String:
	match CompanionAI.lock_kind(n):
		"brazier": return "lit"
		"chime": return "rung"
		"drift": return "blown"
		"ring": return "pulled"
	return "latched"


func _on_lock_changed(pressed: bool, n: Node) -> void:
	if not pressed or _applying or not _started:
		return
	var kind := _event_kind(n)
	if not is_host and not (kind in CLIENT_EVENTS):
		return
	_send_event(n, kind)


## Chave estável da trava: caminho relativo à fase ou, para nós com nome
## automático ("@..."), a posição (os dois aparelhos montam a mesma fase).
func _puzzle_key(n: Node) -> String:
	var path := String(level.get_path_to(n)) if level != null and level.is_ancestor_of(n) else String(n.get_path())
	if not path.contains("@"):
		return path
	var p: Vector3 = (n as Node3D).global_position if n is Node3D else Vector3.ZERO
	return "@%.1f,%.1f,%.1f" % [p.x, p.y, p.z]


func _resolve(key: String) -> Node:
	if not key.begins_with("@"):
		return level.get_node_or_null(key) if level != null else get_tree().root.get_node_or_null(key)
	var c := key.substr(1).split(",")
	if c.size() < 3:
		return null
	var p := Vector3(float(c[0]), float(c[1]), float(c[2]))
	var best: Node = null
	var bd := 0.35
	for grp in [&"plates", &"wind_listeners", &"hook_targets", &"relics"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				var d := (n as Node3D).global_position.distance_to(p)
				if d < bd:
					bd = d
					best = n
	return best


func _seen(ek: String, kind: String) -> bool:
	if not _events.has(ek):
		return false
	return kind in PERMANENT_EVENTS or Time.get_ticks_msec() - int(_events[ek]) < EVENT_REPEAT_MS


func _send_event(n: Node, kind: String) -> void:
	var key := _puzzle_key(n)
	var ek := key + "|" + kind
	if _seen(ek, kind):
		return
	_events[ek] = Time.get_ticks_msec()
	_puzzle_event.rpc(key, kind)


## Evento de quebra-cabeça: `lit`, `rung`, `mark_slam`, `blown`, `pulled`, `parted`, `latched`.
@rpc("any_peer", "reliable", "call_remote")
func _puzzle_event(path: String, kind: String) -> void:
	if is_host and not (kind in CLIENT_EVENTS):
		return    # o anfitrião é autoritativo
	var ek := path + "|" + kind
	if _seen(ek, kind):
		return
	_events[ek] = Time.get_ticks_msec()
	var n := _resolve(path)
	if n == null:
		return
	_applying = true
	_apply_event(n, kind)
	_applying = false


func _apply_event(n: Node, kind: String) -> void:
	if n.has_method("net_event"):
		n.net_event(kind)
		return
	match kind:
		"rung":
			if n.has_method("ring"):
				n.ring()
			else:
				_strike(n)
		"mark_slam":
			# o anfitrião marca no próprio relógio (+0,15 s de tolerância se o sino aceitar)
			if n.has_method("mark_slam"):
				n.mark_slam(0.15)
			elif n.has_method("on_pound"):
				n.on_pound((n as Node3D).global_position, other)
		"parted":
			if n.has_method("part"):
				var pt = n.get("part_time")
				n.part(float(pt) if pt != null else 6.0)
		"latched":
			if CompanionAI.is_plate(n):
				if n.get("latch") == true:
					if n.has_method("force_latch"):
						n.force_latch()
					elif n.has_method("force_done"):
						n.force_done()
					else:
						n.set("latched", true)
			else:
				_force_done(n)
		_:
			if n.get("pressed") == true:
				return
			var named := {"lit": ["ignite", "light_up"], "blown": ["blow"], "pulled": ["force_pull"]}
			for m in named.get(kind, []):
				if n.has_method(m):
					n.call(m)
					return
			_force_done(n)


## Golpe simulado do herói remoto num sino (reusa a janela do próprio sino).
func _strike(n: Node) -> void:
	var need = n.get("need")
	if not (need is Array):
		need = ["any"]
	var p: Vector3 = (n as Node3D).global_position
	if "slam" in need and n.has_method("on_pound"):
		n.on_pound(p, other)
	if n.has_method("on_attack"):
		var kind := "staff1" if ("staff" in need and not ("any" in need)) else ("bump" if other != null and other.hero_id == "strong" else "spin")
		n.on_attack(p + Vector3.UP * 0.5, 0.6, other, kind)


func _force_done(n: Node) -> void:
	if n.has_method("force_done"):
		n.force_done()
	elif n.get("pressed") == false:
		n.set("pressed", true)
		if n.has_signal("changed"):
			n.emit_signal("changed", true)


## Barrigada local perto de um sino `slam` (pound_listeners): o cliente avisa o anfitrião.
func on_pound(p: Vector3, by) -> void:
	if not _started or is_host or by != mine:
		return
	_mark_slam_near(p, 0.0)


## Aríete local do Hulvar (também vale como `slam`).
func _watch_ram() -> void:
	if is_host or mine == null or mine.hero_id != "strong":
		return
	var atk := mine.is_attacking() and mine.state != Hero.S.POUND
	if atk and not _mine_atk:
		var f := Vector3(sin(mine.facing), 0, cos(mine.facing))
		_mark_slam_near(mine.global_position + f * 0.6, 1.1 + 1.0)
	_mine_atk = atk


func _mark_slam_near(p: Vector3, reach: float) -> void:
	for n in get_tree().get_nodes_in_group(&"plates"):
		if CompanionAI.lock_kind(n) != "chime" or not ("slam" in CompanionAI._need(n)):
			continue
		var sr = n.get("slam_radius")
		var r := reach + 1.2 * float(n.get("size") if n.get("size") != null else 1.0) if reach > 0.0 else (float(sr) if sr != null else 9.0)
		if (n as Node3D).global_position.distance_to(p) <= r:
			_send_event(n, "mark_slam")


## Varredura periódica: travas novas, placas que travaram (`latch`), véus de
## areia abertos, grupos resolvidos (anfitrião) e PV dos Silentes (os dois lados).
func _watch_world() -> void:
	_connect_locks()
	if is_host:
		var groups := {}
		for n in get_tree().get_nodes_in_group(&"plates"):
			groups[String(n.get("group_id"))] = true
			if CompanionAI.is_plate(n) and n.get("latched") == true and not _latched_seen.has(n):
				_latched_seen[n] = true
				_send_event(n, "latched")
		for g in groups:
			if g != "" and not _solved_sent.has(g) and CompanionAI.group_done(g):
				_solved_sent[g] = true
				for n in get_tree().get_nodes_in_group(&"plates"):
					if String(n.get("group_id")) == g:
						_send_event(n, "latched")
		for n in get_tree().get_nodes_in_group(&"wind_listeners"):
			if not n.has_method("part"):
				continue
			var open := _is_open(n)
			if open and not _parted_seen.get(n, false):
				_send_event(n, "parted")
			_parted_seen[n] = open
	_track_hp()


static func _is_open(n: Node) -> bool:
	if n.has_method("is_open"):
		return bool(n.is_open())
	for k in ["parted", "is_parted", "opened", "open"]:
		var v = n.get(k)
		if v is bool:
			return v
	var t = n.get("part_t")
	return t != null and float(t) > 0.0


# =================================================================== golpes em Silentes
## Cada golpe local num Silente com PV vira `_enemy_hit` (lido pela queda do PV).
func _track_hp() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var hp = e.get("hp")
		if hp == null or e.get("dead") == true:
			continue
		var k := String(e.name)
		if not _hp_seen.has(k):
			_hp_seen[k] = int(hp)
			continue
		var dmg := int(_hp_seen[k]) - int(hp)
		_hp_seen[k] = int(hp)
		if dmg > 0:
			_enemy_hit.rpc(k, dmg)


@rpc("any_peer", "reliable", "call_remote")
func _enemy_hit(enemy_name: String, dmg: int) -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if String(e.name) != enemy_name:
			continue
		if e.get("dead") == true or dmg <= 0:
			return
		_remote_enemy = true
		if e.has_method("net_hit"):
			e.net_hit(dmg)
		elif e.has_method("apply_damage"):
			e.apply_damage(dmg)
		elif e.get("hp") != null:
			e.set("hp", int(e.get("hp")) - dmg)
			if int(e.get("hp")) <= 0:
				e.defeat(null)
		_remote_enemy = false
		if e.get("hp") != null:
			_hp_seen[enemy_name] = int(e.get("hp"))
		return
