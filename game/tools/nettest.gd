extends Node
## Teste do co-op em rede: rode duas instâncias (host e cliente) no mesmo PC.
##   godot --headless --path . res://game/tools/nettest.tscn -- --host
##   godot --headless --path . res://game/tools/nettest.tscn -- --client
## O host anda com a Saeli pela primeira trilha de centelhas da receita (e coleta),
## o cliente anda com o Hulvar; cada lado confere se o herói do outro se moveu e
## se as centelhas chegaram.

const LEVEL := preload("res://game/scenes/level.tscn")

var level: GameLevel
var net: Node
var host := false
var ok := true
var _connected := false


class Bot extends RefCounted:
	var move := Vector2.ZERO
	var yaw := 0.0
	func poll(intent: PlayerInput, me, _d: float) -> void:
		me.cam_yaw = yaw
		intent.move = move


func _ready() -> void:
	host = "--host" in OS.get_cmdline_user_args()
	level = LEVEL.instantiate()
	level.capture_mode = true
	add_child(level)
	net = load("res://game/scripts/net/net_coop.gd").new()
	net.name = "Rede"
	get_tree().root.add_child.call_deferred(net)
	_run.call_deferred()


func say(s: String) -> void:
	print("[%s] %s" % ["host" if host else "cliente", s])


func check(c: bool, what: String) -> void:
	say(("ok   " if c else "FAIL ") + what)
	ok = ok and c


func _run() -> void:
	for i in 60:
		await get_tree().physics_frame
	net.connected.connect(func(_h): _connected = true)
	if host:
		net.host()
		say("sala criada")
	else:
		await get_tree().create_timer(1.0).timeout
		net.join("127.0.0.1")
	var t := 0.0
	while not _connected and t < 15.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	check(_connected, "conectou")
	if not _connected:
		get_tree().quit(1)
		return
	Game.mode = Game.Mode.NET_HOST if host else Game.Mode.NET_CLIENT
	net.start_game(level)
	var mine: Hero = net.mine
	var other: Hero = net.other
	await get_tree().create_timer(1.5).timeout
	var other_start := other.global_position
	var bot := Bot.new()
	mine.controller = bot
	var terrain: SandTerrain = level.builder.terrain
	var lines: Array = level.content.data.get("motes", []).filter(func(e): return e.has("line"))
	var a: Array = lines[0]["line"]
	var s0 := terrain.surface(float(a[0][0]), float(a[0][1]))
	var s1 := terrain.surface(float(a[1][0]), float(a[1][1]))
	var dir := Vector3(s1.x - s0.x, 0.0, s1.z - s0.z).normalized()
	if host:
		mine.teleport(s0 + Vector3.UP * 0.6, atan2(dir.x, dir.z))
		await get_tree().create_timer(0.8).timeout
		bot.yaw = atan2(-dir.x, -dir.z)
		bot.move = Vector2(0, -1)              # along the first mote trail
	else:
		mine.teleport(s0 + Vector3(6, 0.6, 0), 0.0)
		await get_tree().create_timer(0.8).timeout
		bot.yaw = 0.0
		bot.move = Vector2(1, 0)               # east
	await get_tree().create_timer(2.5).timeout
	bot.move = Vector2.ZERO
	await get_tree().create_timer(1.5).timeout
	var moved := other.global_position.distance_to(other_start)
	check(moved > 4.0, "vejo o %s se mexer pela rede (%.1f m)" % [other.hero_id, moved])
	check(other.is_remote, "o herói do outro é marionete de rede")
	if not host:
		check(Game.motes >= 4, "centelhas coletadas pelo host chegaram aqui (%d)" % Game.motes)
	else:
		check(Game.motes >= 4, "coletei centelhas (%d)" % Game.motes)
	await get_tree().create_timer(1.0).timeout
	say("fim: " + ("OK" if ok else "FALHOU"))
	get_tree().quit(0 if ok else 1)
