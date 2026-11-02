extends Node
## Playtest automatizado de SOPRO: roda a fase com física real e um "bot" de
## entrada, exercitando cada mecânica e conferindo o resultado.
##
##   godot --headless --path . res://game/tools/playtest.tscn            (código de saída 0 = tudo ok)
##   godot --headless --path . res://game/tools/playtest.tscn -- --only cannon,ribbon

const LEVEL := preload("res://game/scenes/level.tscn")

var level: SoproLevel
var agile: Hero
var strong: Hero
var bot := ScriptBot.new()
var fails: Array[String] = []
var passes := 0
var _only: Array = []


class ScriptBot extends RefCounted:
	var move := Vector2.ZERO
	var jump_hold := false
	var queue: Array[String] = []
	var yaw := 0.0
	func poll(intent: PlayerInput, me, _delta: float) -> void:
		me.cam_yaw = yaw
		intent.move = move
		intent.jump = jump_hold
		intent.action = false
		for q in queue:
			intent.press(q)
		queue.clear()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--only" in args:
		_only = Array(args[args.find("--only") + 1].split(","))
	level = LEVEL.instantiate()
	level.capture_mode = true
	add_child(level)
	_run.call_deferred()


func check(cond: bool, what: String, detail := "") -> bool:
	if cond:
		passes += 1
		print("  ok   ", what)
	else:
		fails.append(what)
		print("  FAIL ", what, "  ", detail)
	return cond


func wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func control(h: Hero) -> void:
	h.controller = bot
	h.player_index = 0
	bot.move = Vector2.ZERO
	bot.jump_hold = false
	bot.queue.clear()


func idle_ai_off() -> void:
	# park the companion so it doesn't interfere
	for h in Game.heroes:
		if h.controller is CompanionAI:
			h.controller = null


func place(h: Hero, p: Vector3, yaw := 0.0) -> void:
	h.teleport(p, yaw)
	h.set_state(Hero.S.AIR)


func want(name: String) -> bool:
	return _only.is_empty() or name in _only


func _run() -> void:
	# wait for the content (async raycasts) and the heroes
	for i in 120:
		await get_tree().physics_frame
		if level.content != null and level.content.get("lume_field") != null:
			break
	agile = level.party.agile
	strong = level.party.strong
	control(agile)
	idle_ai_off()
	print("[sopro playtest]")
	if want("spawn"):
		await _t_spawn()
	if want("move"):
		await _t_move()
	if want("glide"):
		await _t_glide()
	if want("jelly"):
		await _t_jelly()
	if want("cannon"):
		await _t_cannon()
	if want("ribbon"):
		await _t_ribbon()
	if want("portal"):
		await _t_portal()
	if want("ride"):
		await _t_ride()
	if want("swim"):
		await _t_swim()
	if want("enemy"):
		await _t_enemy()
	if want("plates"):
		await _t_plates()
	if want("lumes"):
		await _t_lumes()
	if want("respawn"):
		await _t_respawn()
	if want("seeds"):
		await _t_seeds_and_bell()
	print("%d ok, %d falhas" % [passes, fails.size()])
	if not fails.is_empty():
		print("FALHAS: ", ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)


# --------------------------------------------------------------------------- tests
func _t_spawn() -> void:
	print("[spawn]")
	await wait(2.0)
	check(agile.state == Hero.S.GROUND, "Juba pousa no chão ao nascer", Hero.S.keys()[agile.state])
	check(strong.state == Hero.S.GROUND, "Caju pousa no chão ao nascer", Hero.S.keys()[strong.state])
	check(agile.global_position.y > 1.0 and agile.global_position.y < 5.0, "altura do spawn plausível", str(agile.global_position))


func _t_move() -> void:
	print("[movimento]")
	control(agile)
	place(agile, Vector3(0, 4, 38), PI)
	await wait(1.0)
	var p0 := agile.global_position
	bot.yaw = 0.0
	bot.move = Vector2(0, -1)
	await wait(2.0)
	bot.move = Vector2.ZERO
	var d := Vector2(agile.global_position.x - p0.x, agile.global_position.z - p0.z).length()
	check(d > 9.0, "Juba corre (%.1f m em 2 s)" % d)
	check(agile.global_position.z < p0.z - 5.0, "anda para frente (norte, -Z)")
	await wait(0.6)
	var y0 := agile.global_position.y
	bot.queue.append("jump")
	bot.jump_hold = true
	var peak := y0
	for i in 40:
		await get_tree().physics_frame
		peak = maxf(peak, agile.global_position.y)
	bot.jump_hold = false
	check(peak - y0 > 1.6, "pulo alto o bastante (%.2f m)" % (peak - y0))
	await wait(1.2)
	check(agile.state == Hero.S.GROUND, "volta ao chão depois do pulo")


func _t_glide() -> void:
	print("[pulo duplo + planar]")
	control(agile)
	place(agile, Vector3(0, 20, 30), PI)
	await wait(0.2)
	bot.queue.append("jump")       # double jump in the air
	bot.jump_hold = true
	await wait(0.5)
	bot.move = Vector2(0, -1)
	await wait(0.6)
	check(agile.state == Hero.S.GLIDE, "segurar pulo no ar abre a pipa (planar)", Hero.S.keys()[agile.state])
	var vy := agile.velocity.y
	check(vy > -4.0, "queda lenta planando (vy=%.1f)" % vy)
	check(agile.kite != null, "a pipa existe")
	bot.jump_hold = false
	bot.move = Vector2.ZERO
	await wait(2.5)


func _t_jelly() -> void:
	print("[água-viva trampolim]")
	control(agile)
	var jellies := []
	for n in level.content.get_children():
		if n is Interactables.JellyPad:
			jellies.append(n)
	check(jellies.size() >= 6, "águas-vivas criadas (%d)" % jellies.size())
	if jellies.is_empty():
		return
	var j: Node3D = jellies[0]
	place(agile, j.global_position + Vector3.UP * 5.0)
	var max_vy := -99.0
	for i in 120:
		await get_tree().physics_frame
		max_vy = maxf(max_vy, agile.velocity.y)
	check(max_vy > 12.0, "quicar arremessa para cima (vy máx=%.1f)" % max_vy)


func _t_cannon() -> void:
	print("[flor-canhão]")
	control(agile)
	var cannons := []
	for n in level.content.get_children():
		if n is Interactables.FlowerCannon:
			cannons.append(n)
	check(cannons.size() >= 3, "flores-canhão criadas (%d)" % cannons.size())
	if cannons.is_empty():
		return
	var c: Interactables.FlowerCannon = cannons[0]
	place(agile, c.global_position + Vector3.UP * 2.6)
	await wait(4.5)
	var d := agile.global_position.distance_to(c.target)
	check(d < 7.0, "flor-canhão leva até a ilha dos Cata-ventos (erro %.1f m)" % d, str(agile.global_position))
	check(agile.state in [Hero.S.GROUND, Hero.S.AIR], "herói recupera o controle depois do voo")


func _t_ribbon() -> void:
	print("[fita de vento]")
	control(agile)
	var ribbon: Interactables.WindRibbon = null
	for n in level.content.get_children():
		if n is Interactables.WindRibbon:
			ribbon = n
	if not check(ribbon != null, "fita de vento criada"):
		return
	var start := ribbon.transform_at(1.0).origin
	place(agile, start + Vector3.UP * 0.6)
	var grinded := false
	for i in 60:
		await get_tree().physics_frame
		if agile.state == Hero.S.GRIND:
			grinded = true
			break
	check(grinded, "herói engata na fita")
	await wait(ribbon.length() / ribbon.speed + 2.5)
	var west: Vector3 = level.builder.island_center("IlhaFita")
	var dist := Vector2(agile.global_position.x - west.x, agile.global_position.z - west.z).length()
	check(dist < 30.0 and agile.global_position.y > -5.0, "fita leva até a Ilha da Fita (%.1f m do centro)" % dist, str(agile.global_position))


func _t_portal() -> void:
	print("[portal]")
	control(agile)
	var portals := get_tree().get_nodes_in_group(&"portals")
	if not check(portals.size() >= 2, "portais criados"):
		return
	var p: Node3D = portals[0]
	place(agile, p.global_position + p.global_transform.basis.z * 2.5 + Vector3.UP * 0.5, p.rotation.y + PI)
	await wait(0.4)
	place(agile, p.global_position + Vector3.UP * 0.8)
	await wait(0.5)
	var exitp: Vector3 = p.exit_pos
	check(agile.global_position.distance_to(exitp) < 4.0, "portal teleporta para a ilhota secreta", str(agile.global_position))
	await wait(1.6)


func _t_ride() -> void:
	print("[carona + catapulta]")
	control(agile)
	place(strong, Vector3(2, 4, 36), PI)
	place(agile, Vector3(0.6, 4, 36), PI)
	strong.controller = null
	await wait(1.5)
	bot.queue.append("special")
	await wait(0.3)
	check(agile.state == Hero.S.RIDE and strong.rider == agile, "Juba sobe nas costas do Caju", Hero.S.keys()[agile.state])
	# drive strong forward with a second bot
	var cbot := ScriptBot.new()
	strong.controller = cbot
	cbot.move = Vector2(0, -1)
	var p0 := strong.global_position
	await wait(1.0)
	cbot.move = Vector2.ZERO
	check(agile.global_position.distance_to(strong.global_position) < 1.2, "Juba acompanha o Caju andando")
	check(strong.global_position.distance_to(p0) > 4.0, "Caju anda carregando o Juba")
	cbot.queue.append("special")
	var max_y := agile.global_position.y
	for i in 60:
		await get_tree().physics_frame
		max_y = maxf(max_y, agile.global_position.y)
	check(agile.state != Hero.S.RIDE and max_y - strong.global_position.y > 3.0, "catapulta lança o Juba alto (%.1f m)" % (max_y - strong.global_position.y))
	strong.controller = null
	await wait(2.0)


func _t_swim() -> void:
	print("[nado]")
	var cbot := ScriptBot.new()
	strong.controller = cbot
	place(strong, Vector3(22, 3.5, 12))
	await wait(2.0)
	check(strong.state == Hero.S.SWIM, "Caju nada na lagoa", Hero.S.keys()[strong.state])
	check(strong.global_position.y > -1.5, "boia perto da superfície (y=%.2f)" % strong.global_position.y)
	strong.controller = null
	place(strong, Vector3(4, 4, 36))
	await wait(1.0)


func _t_enemy() -> void:
	print("[Breu]")
	control(agile)
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	if not check(enemies.size() >= 5, "Breus criados (%d)" % enemies.size()):
		return
	var e: Breu = enemies[0]
	var before := get_tree().get_nodes_in_group(&"enemies").size()
	# stomp from above
	place(agile, e.global_position + Vector3.UP * 3.0)
	for i in 90:
		await get_tree().physics_frame
		if e.dead:
			break
	check(e.dead, "pular em cima vence o Breu")
	await wait(0.8)
	enemies = get_tree().get_nodes_in_group(&"enemies")
	if enemies.is_empty():
		return
	var e2: Breu = enemies[0]
	place(agile, e2.global_position + Vector3(1.2, 1.0, 0))
	await wait(0.6)
	bot.queue.append("action")
	await wait(0.3)
	check(not is_instance_valid(e2) or e2.dead, "giro do Juba vence o Breu")
	await wait(1.0)


func _t_plates() -> void:
	print("[placas + portão-flor]")
	var plates := get_tree().get_nodes_in_group(&"plates")
	if not check(plates.size() >= 2, "placas criadas"):
		return
	var normal: Node3D = null
	var heavy: Node3D = null
	for p in plates:
		if p.heavy:
			heavy = p
		else:
			normal = p
	var gate: Interactables.FlowerGate = null
	for n in level.content.get_children():
		if n is Interactables.FlowerGate:
			gate = n
	check(gate != null and not gate.opened, "portão começa fechado")
	agile.controller = null
	strong.controller = null
	place(agile, heavy.global_position + Vector3.UP * 1.0)
	await wait(1.2)
	check(not heavy.pressed, "placa pesada não desce com o Juba")
	place(agile, normal.global_position + Vector3.UP * 1.0)
	place(strong, heavy.global_position + Vector3.UP * 1.0)
	await wait(1.5)
	check(normal.pressed and heavy.pressed, "as duas placas descem (Juba + Caju)")
	await wait(0.5)
	check(gate != null and gate.opened, "portão-flor abre com as duas placas")
	if gate != null and gate.seed != null:
		check(gate.seed.visible, "semente revelada dentro do portão")
	control(agile)


func _t_lumes() -> void:
	print("[lumes]")
	control(agile)
	var field: LumeField = level.content.lume_field
	check(field.points.size() > 100, "lumes espalhados (%d)" % field.points.size())
	var before := Game.lumes
	place(agile, Vector3(-26, 4, 8), PI * 0.5)
	await wait(1.0)
	bot.yaw = PI * 0.5
	bot.move = Vector2(0, -1)
	await wait(2.6)
	bot.move = Vector2.ZERO
	check(Game.lumes - before >= 5, "correndo pela trilha coleta lumes (+%d)" % (Game.lumes - before))
	check(Game.lumes >= 15, "total de lumes coletados no teste (%d)" % Game.lumes)


func _t_respawn() -> void:
	print("[queda + retorno]")
	control(agile)
	place(agile, Vector3(200, -10, 200))
	await wait(1.5)
	check(agile.global_position.distance_to(Game.checkpoint) < 6.0, "cair no mar de nuvens volta ao ponto de retorno")


func _t_seeds_and_bell() -> void:
	print("[sementes + Grande Sino]")
	control(agile)
	var seeds := get_tree().get_nodes_in_group(&"seeds")
	check(seeds.size() == 3, "3 Sementes de Sopro")
	for s in seeds:
		if not s.visible:
			s.reveal()
		await wait(0.2)
		place(agile, s.global_position + Vector3.UP * 0.4)
		await wait(0.4)
	check(Game.seeds.size() == 3, "coletou as 3 sementes (%d)" % Game.seeds.size())
	var tower := level.content.find_child("TorreDoSino", true, false) as Node3D
	place(agile, tower.global_position + Vector3(0, 1.5, 7.5))
	await wait(1.0)
	check(Game.bell_done, "o Grande Sino toca com as 3 sementes")
	await wait(9.5)
	check(agile.state != Hero.S.CUTSCENE, "controle volta depois da cena final")
