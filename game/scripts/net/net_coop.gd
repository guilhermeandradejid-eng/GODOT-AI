extends Node
## Co-op em rede local (Wi-Fi) com ENet: quem cria a sala joga com a
## personagem ágil, quem entra joga com a forte. Descoberta automática por broadcast UDP.
## Cada aparelho é dono do próprio herói (envia estado a 30 Hz); eventos do
## mundo (centelhas, Pedras das Horas, Silentes vencidos, lançamento) vão por RPC confiável.

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
			_hero_state.rpc(mine.global_position, mine.velocity, mine.facing, mine.state,
				mine.visual.state if mine.visual != null else "loco", mine.petals)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _hero_state(pos: Vector3, vel: Vector3, facing: float, state: int, vis: String, petals: int) -> void:
	if puppet == null or other == null:
		return
	puppet.push(pos, vel, facing, state, vis)
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
		if String(e.name) == enemy_name:
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
