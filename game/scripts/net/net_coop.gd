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
const EVENT_REPEAT_MS := 800

var _events := {}           ## "chave|tipo" -> msec (eventos já enviados/recebidos)
var _applying := false
var _hp_seen := {}          ## nome do Silente -> PV visto (só sem o sinal `hit`)
var _remote_item := false
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
## 4 = corda ativa. Vem do HeroTools (`tool_bits()`, `rope_to`); sem ele, da
## luz em `Game.lantern_pos`/`lantern_radius`.
static func tool_state(h: Hero) -> Array:
	var tools = h.get("tools")
	if tools != null and tools.has_method("tool_bits"):
		var to = tools.get("rope_to")
		return [int(tools.tool_bits()), to if to is Vector3 else Vector3.ZERO]
	var bits := 0
	if h.hero_id == "agile":
		var lp = Game.get("lantern_pos")
		if lp is Vector3 and (lp as Vector3).is_finite():
			bits |= 1
			var lr = Game.get("lantern_radius")
			if lr != null and float(lr) >= 8.5:
				bits |= 2
	return [bits, Vector3.ZERO]


# =================================================================== itens
func _on_local_item(id) -> void:
	if not _remote_item and _started:
		_item_taken.rpc(String(id))


## Item pego no outro aparelho. `Game.give_item` é idempotente e o pedestal some
## pelo próprio `Game.item_collected`.
@rpc("any_peer", "reliable", "call_remote")
func _item_taken(id: String) -> void:
	if Game.has_method("has_item") and bool(Game.call("has_item", id)):
		return
	_remote_item = true
	if Game.has_method("give_item"):
		Game.call("give_item", id)
	_remote_item = false


# =================================================================== travas
## Liga os eventos das travas (grupo "puzzle_nodes": `event_fired(kind)`), o fim
## dos grupos (PuzzleGroups.group_solved) e os golpes nos Silentes (`hit`).
## Idempotente: roda de novo de tempos em tempos para nós criados depois.
func _connect_locks() -> void:
	var seen := {}
	for grp in [&"puzzle_nodes", &"plates", &"sand_veils"]:
		for n in get_tree().get_nodes_in_group(grp):
			if seen.has(n):
				continue
			seen[n] = true
			if n.has_signal("event_fired"):
				var cb := _on_fired.bind(n)
				if not n.is_connected("event_fired", cb):
					n.connect("event_fired", cb)
			elif CompanionAI.lock_kind(n) != "plate" and n.has_signal("changed"):
				var cb2 := _on_lock_changed.bind(n)
				if not n.is_connected("changed", cb2):
					n.connect("changed", cb2)
	var pg := get_tree().get_first_node_in_group(&"puzzle_groups")
	if is_host and pg != null and pg.has_signal("group_solved") and not pg.is_connected("group_solved", _on_group_solved):
		pg.connect("group_solved", _on_group_solved)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e.has_signal("hit") and not e.is_connected("hit", _on_local_hit):
			e.connect("hit", _on_local_hit)


## Do cliente o anfitrião só aceita golpes nos sinos (o Hulvar não tem itens).
static func _client_kind(kind: String) -> bool:
	return kind == "rung" or kind.begins_with("mark_")


func _on_fired(kind: String, n: Node) -> void:
	if _applying or not _started or kind == "taken":
		return    # itens vão por _item_taken
	if not is_host and not _client_kind(kind):
		return
	_send_event(n, kind)


## Travas sem `event_fired`: o `changed(true)` vira o evento do tipo da trava.
func _on_lock_changed(pressed: bool, n: Node) -> void:
	if not pressed or _applying or not _started:
		return
	var kind: String = {"brazier": "lit", "chime": "rung", "drift": "blown", "ring": "pulled"}.get(CompanionAI.lock_kind(n), "latched")
	if not is_host and not _client_kind(kind):
		return
	_send_event(n, kind)


## Anfitrião: grupo resolvido → o cliente resolve à força o mesmo grupo.
func _on_group_solved(group: String) -> void:
	if _started and not _solved_sent.has(group):
		_solved_sent[group] = true
		_puzzle_event.rpc("group:" + group, "latched")


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
	for grp in [&"puzzle_nodes", &"plates", &"sand_veils"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				var d := (n as Node3D).global_position.distance_to(p)
				if d < bd:
					bd = d
					best = n
	return best


## Já enviado/recebido? Eventos permanentes valem uma vez; os outros (sinos,
## marcas, véu) só se repetem depois de 0,8 s.
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


## Evento de quebra-cabeça: `lit`, `rung`, `mark_slam` (e outras marcas), `blown`,
## `pulled`, `parted`, `latched`; "group:<id>" + `latched` resolve o grupo.
@rpc("any_peer", "reliable", "call_remote")
func _puzzle_event(path: String, kind: String) -> void:
	if is_host and not _client_kind(kind):
		return    # o anfitrião é autoritativo
	var ek := path + "|" + kind
	if _seen(ek, kind):
		return
	_events[ek] = Time.get_ticks_msec()
	_applying = true
	if path.begins_with("group:"):
		_force_group(path.substr(6))
	else:
		var n := _resolve(path)
		if n != null:
			if n.has_method("apply_event"):
				n.apply_event(kind)    # a trava aplica sem reemitir
			else:
				_apply_fallback(n, kind)
	_applying = false


## Grupo resolvido no anfitrião: as travas daqui ficam feitas (placas com latch
## travam), o grupo resolve (revela itens/relíquias) e os portões do grupo abrem.
func _force_group(g: String) -> void:
	for n in get_tree().get_nodes_in_group(&"plates"):
		if String(n.get("group_id")) != g:
			continue
		if CompanionAI.is_plate(n):
			if n.get("latch") == true and n.has_method("apply_event"):
				n.apply_event("latched")
		elif n.get("pressed") != true and n.has_method("force_done"):
			n.force_done()
	var pg := get_tree().get_first_node_in_group(&"puzzle_groups")
	if pg != null and pg.has_method("force_solve"):
		pg.call("force_solve", g)
	if level != null and level.content != null:
		for n in level.content.get_children():
			if n.get("opened") == false and String(n.get("group_id")) == g and n.has_method("open"):
				n.open()


## Travas sem `apply_event` (versões antigas): melhor esforço.
func _apply_fallback(n: Node, kind: String) -> void:
	if kind == "parted" and n.has_method("part"):
		n.part()
	elif kind == "rung" or kind.begins_with("mark_"):
		if n.has_method("on_attack"):
			n.on_attack((n as Node3D).global_position + Vector3.UP * 0.9, 0.6, other, "bump" if other.hero_id == "strong" else "spin")
	elif n.has_method("force_done"):
		n.force_done()


## Barrigada do Hulvar no cliente (pound_listeners): marca `slam` nos sinos ao
## alcance. Garante o Eco mesmo se o cristal `dark` daqui não vir a luz a tempo;
## o anfitrião marca no próprio relógio com +0,15 s de tolerância.
func on_pound(p: Vector3, by) -> void:
	if not _started or is_host or by != mine:
		return
	_mark_slam_near(p, -1.0)


## Aríete local do Hulvar (também conta como `slam`).
func _watch_ram() -> void:
	if is_host or mine == null or mine.hero_id != "strong":
		return
	var atk := mine.is_attacking() and mine.state != Hero.S.POUND
	if atk and not _mine_atk:
		var f := Vector3(sin(mine.facing), 0, cos(mine.facing))
		_mark_slam_near(mine.global_position + f * 0.6 + Vector3.UP * 0.4, 1.1)
	_mine_atk = atk


func _mark_slam_near(p: Vector3, reach: float) -> void:
	for n in get_tree().get_nodes_in_group(&"plates"):
		if CompanionAI.lock_kind(n) != "chime" or not ("slam" in CompanionAI._need(n)) or n.get("pressed") == true:
			continue
		var sz = n.get("size")
		var sr = n.get("slam_radius")
		var r := (reach + 1.2 * (float(sz) if sz != null else 1.0)) if reach >= 0.0 else (float(sr) if sr != null else 9.0)
		if (n as Node3D).global_position.distance_to(p) <= r + 0.6:
			_send_event(n, "mark_slam")


## Varredura periódica: liga nós novos; Silentes sem o sinal `hit` pelo PV.
func _watch_world() -> void:
	_connect_locks()
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e.has_signal("hit"):
			continue
		var hp = e.get("hp")
		if hp == null or e.get("dead") == true:
			continue
		var k := String(e.name)
		var dmg := int(_hp_seen.get(k, hp)) - int(hp)
		_hp_seen[k] = int(hp)
		if dmg > 0:
			_enemy_hit.rpc(k, dmg)


# =================================================================== golpes em Silentes
func _on_local_hit(who: Node, dmg: int) -> void:
	if _started and not _remote_enemy and who != null:
		_enemy_hit.rpc(String(who.name), dmg)


## Golpe num Silente com PV feito no outro aparelho (`Silente.apply_hit` não reemite).
@rpc("any_peer", "reliable", "call_remote")
func _enemy_hit(enemy_name: String, dmg: int) -> void:
	if dmg <= 0:
		return
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if String(e.name) != enemy_name:
			continue
		if e.get("dead") == true:
			return
		_remote_enemy = true
		if e.has_method("apply_hit"):
			e.apply_hit(dmg)
		elif e.get("hp") != null:
			e.set("hp", int(e.get("hp")) - dmg)
			if int(e.get("hp")) <= 0:
				e.defeat(null)
		_remote_enemy = false
		if e.get("hp") != null:
			_hp_seen[enemy_name] = int(e.get("hp"))
		return
