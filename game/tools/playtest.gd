extends Node
## Playtest automatizado: roda a fase com física real e um "bot" de entrada,
## exercitando cada mecânica e conferindo o resultado. As posições vêm da
## própria receita (game/world/world.json), então o teste acompanha o layout.
##
##   godot --headless --path . res://game/tools/playtest.tscn            (código de saída 0 = tudo ok)
##   godot --headless --path . res://game/tools/playtest.tscn -- --only surf,launcher

const LEVEL := preload("res://game/scenes/level.tscn")

var level: Node3D
var terrain: SandTerrain
var content: Node3D
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
	for h in Game.heroes:
		if h.controller is CompanionAI:
			h.controller = null


func place(h: Hero, p: Vector3, yaw := 0.0) -> void:
	h.teleport(p, yaw)
	h.set_state(Hero.S.AIR)


func want(name: String) -> bool:
	return _only.is_empty() or name in _only


func nodes_of(cls) -> Array:
	var out := []
	for n in content.get_children():
		if is_instance_of(n, cls):
			out.append(n)
	return out


## Um lugar plano perto de `near` (para testes que precisam de chão calmo).
func flat_spot(near: Vector3, max_slope := 8.0) -> Vector3:
	var best := near
	var best_s := 999.0
	for r: float in [0.0, 6.0, 12.0, 20.0, 30.0, 45.0, 70.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var x: float = near.x + cos(a) * r
			var z: float = near.z + sin(a) * r
			if not terrain.inside(x, z):
				continue
			var s2 := maxf(terrain.slope_deg_at(x, z), maxf(terrain.slope_deg_at(x + 3, z), terrain.slope_deg_at(x, z + 3)))
			if s2 < best_s:
				best_s = s2
				best = terrain.surface(x, z)
			if s2 < max_slope:
				return terrain.surface(x, z)
	return best


## A encosta de areia mais adequada para surfar perto de `near` (20-32°).
func surf_spot(near: Vector3) -> Dictionary:
	for r in range(0, 260, 8):
		for k in 24:
			var a := TAU * k / 24.0
			var x := near.x + cos(a) * r
			var z := near.z + sin(a) * r
			if not terrain.inside(x, z):
				continue
			var s := terrain.slope_deg_at(x, z)
			if s < 20.0 or s > 32.0:
				continue
			var n := terrain.normal_at(x, z)
			var down := Vector3(n.x, 0, n.z).normalized()
			# the slope must keep going down for a while
			var ok := true
			for d: float in [4.0, 8.0, 12.0]:
				var q: Vector3 = Vector3(x, 0, z) + down * d
				if terrain.slope_deg_at(q.x, q.z) < 14.0 or terrain.height_at(q.x, q.z) > terrain.height_at(x, z) - d * 0.3:
					ok = false
			if ok:
				return {"at": terrain.surface(x, z), "down": down}
	return {}


func _run() -> void:
	for i in 60:
		await get_tree().physics_frame
		if level.content != null and level.content.get("mote_field") != null:
			break
	content = level.content
	terrain = level.builder.terrain
	agile = level.party.agile
	strong = level.party.strong
	control(agile)
	idle_ai_off()
	print("[playtest]")
	for t in ["spawn", "terrain", "move", "surf", "glide", "bounds", "launcher", "rail", "rift", "bounce",
			"ride", "enemy", "plates", "motes", "respawn", "relics"]:
		if want(t):
			await call("_t_" + t)
	print("%d ok, %d falhas" % [passes, fails.size()])
	if not fails.is_empty():
		print("FALHAS: ", ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)


# --------------------------------------------------------------------------- tests
func _t_spawn() -> void:
	print("[spawn]")
	await wait(2.0)
	check(agile.state == Hero.S.GROUND, "ágil pousa no chão ao nascer", Hero.S.keys()[agile.state])
	check(strong.state == Hero.S.GROUND, "forte pousa no chão ao nascer", Hero.S.keys()[strong.state])
	var g := terrain.height_at(agile.global_position.x, agile.global_position.z)
	check(absf(agile.global_position.y - g) < 0.6, "spawn sobre a areia (dy=%.2f)" % (agile.global_position.y - g))


func _t_terrain() -> void:
	print("[terreno]")
	var space := get_viewport().world_3d.direct_space_state
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var x := rng.randf_range(-terrain.half + 20, terrain.half - 20)
		var z := rng.randf_range(-terrain.half + 20, terrain.half - 20)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -400, z), 16)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			worst = 999.0
			continue
		worst = maxf(worst, absf(hit["position"].y - terrain.height_at(x, z)))
	check(worst < 0.05, "colisão = alturas do terreno (erro máx %.3f m)" % worst)


func _t_move() -> void:
	print("[movimento]")
	control(agile)
	var p := flat_spot(level.content.spawn_point())
	place(agile, p + Vector3.UP * 0.5, PI)
	await wait(1.0)
	var p0 := agile.global_position
	bot.yaw = 0.0
	bot.move = Vector2(0, -1)
	await wait(1.5)
	bot.move = Vector2.ZERO
	var d := Vector2(agile.global_position.x - p0.x, agile.global_position.z - p0.z).length()
	check(d > 7.0, "corre (%.1f m em 1,5 s)" % d)
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
	await wait(1.5)
	check(agile.state in [Hero.S.GROUND, Hero.S.SURF], "volta ao chão depois do pulo", Hero.S.keys()[agile.state])


func _t_surf() -> void:
	print("[surfe nas dunas]")
	control(agile)
	var spot := surf_spot(level.content.spawn_point())
	if not check(not spot.is_empty(), "existe encosta de areia para surfar perto do início"):
		return
	var down: Vector3 = spot["down"]
	place(agile, spot["at"] + Vector3.UP * 0.4, atan2(down.x, down.z))
	bot.yaw = atan2(-down.x, -down.z)
	bot.move = Vector2(0, -1)
	var surfed := false
	var top_speed := 0.0
	for i in 150:
		await get_tree().physics_frame
		if agile.state == Hero.S.SURF:
			surfed = true
		top_speed = maxf(top_speed, Vector2(agile.velocity.x, agile.velocity.z).length())
	bot.move = Vector2.ZERO
	check(surfed, "descer a duna correndo entra no surfe")
	check(top_speed > 9.0, "surfe ganha velocidade (%.1f m/s)" % top_speed)
	await wait(1.0)


func _t_glide() -> void:
	print("[pulo duplo + planar]")
	control(agile)
	var p := flat_spot(level.content.spawn_point())
	place(agile, p + Vector3.UP * 16.0, PI)
	await wait(0.2)
	bot.queue.append("jump")
	bot.jump_hold = true
	await wait(0.5)
	bot.move = Vector2(0, -1)
	await wait(0.6)
	check(agile.state == Hero.S.GLIDE, "segurar pulo no ar faz planar", Hero.S.keys()[agile.state])
	check(agile.velocity.y > -4.0, "queda lenta planando (vy=%.1f)" % agile.velocity.y)
	bot.jump_hold = false
	bot.move = Vector2.ZERO
	await wait(2.5)


func _t_bounds() -> void:
	print("[borda do mundo]")
	control(agile)
	var lim := terrain.half - 14.0
	place(agile, terrain.surface(lim - 2.0, 0.0) + Vector3.UP * 1.0, PI * 0.5)
	bot.yaw = -PI * 0.5
	bot.move = Vector2(0, -1)
	await wait(2.0)
	bot.move = Vector2.ZERO
	check(agile.global_position.x <= lim + 0.01, "não sai do mapa pela borda (x=%.1f)" % agile.global_position.x)
	check(agile.global_position.y > terrain.height_min - 5.0, "continua sobre o terreno")


func _t_launcher() -> void:
	print("[lançador]")
	control(agile)
	var cannons := nodes_of(Interactables.Launcher)
	if cannons.is_empty():
		print("  (sem lançadores na receita)")
		return
	var c: Interactables.Launcher = cannons[0]
	place(agile, c.global_position + Vector3.UP * 2.6)
	var t := 0.0
	while t < c.flight_time + 3.5 and agile.global_position.distance_to(c.target) > 3.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	var d := agile.global_position.distance_to(c.target)
	check(d < 8.0, "lançador leva ao alvo (erro %.1f m)" % d, str(agile.global_position))
	await wait(1.0)


func _t_rail() -> void:
	print("[trilho]")
	control(agile)
	var rails := nodes_of(Interactables.SandRail)
	if rails.is_empty():
		print("  (sem trilhos na receita)")
		return
	var r: Interactables.SandRail = rails[0]
	var start := r.transform_at(1.0).origin
	var end := r.transform_at(r.length() - 0.5).origin
	place(agile, start + Vector3.UP * 0.6)
	var grinded := false
	for i in 60:
		await get_tree().physics_frame
		if agile.state == Hero.S.GRIND:
			grinded = true
			break
	check(grinded, "herói engata no trilho")
	await wait(r.length() / r.speed + 1.5)
	var dist := agile.global_position.distance_to(end)
	check(dist < 25.0, "trilho leva até o fim (%.1f m)" % dist, str(agile.global_position))


func _t_rift() -> void:
	print("[fenda]")
	control(agile)
	var portals := get_tree().get_nodes_in_group(&"portals")
	if portals.is_empty():
		print("  (sem fendas na receita)")
		return
	var p: Node3D = portals[0]
	place(agile, p.global_position + p.global_transform.basis.z * 2.5 + Vector3.UP * 0.5, p.rotation.y + PI)
	await wait(0.4)
	place(agile, p.global_position + Vector3.UP * 0.8)
	await wait(0.6)
	check(agile.global_position.distance_to(p.exit_pos) < 4.0, "fenda teleporta para a saída", str(agile.global_position))
	await wait(1.6)


func _t_bounce() -> void:
	print("[trampolim]")
	var pads := nodes_of(Interactables.BouncePad)
	if pads.is_empty():
		print("  (sem trampolins na receita)")
		return
	control(agile)
	place(agile, (pads[0] as Node3D).global_position + Vector3.UP * 5.0)
	var max_vy := -99.0
	for i in 120:
		await get_tree().physics_frame
		max_vy = maxf(max_vy, agile.velocity.y)
	check(max_vy > 12.0, "quicar arremessa para cima (vy máx=%.1f)" % max_vy)


func _t_ride() -> void:
	print("[carona + lançamento em dupla]")
	control(agile)
	var p := flat_spot(level.content.spawn_point(), 5.0)
	place(strong, p + Vector3(1.4, 0.6, 0), PI)
	place(agile, p + Vector3(0, 0.6, 0), PI)
	strong.controller = null
	await wait(1.5)
	bot.queue.append("special")
	await wait(0.3)
	check(agile.state == Hero.S.RIDE and strong.rider == agile, "a ágil sobe no forte", Hero.S.keys()[agile.state])
	var cbot := ScriptBot.new()
	strong.controller = cbot
	cbot.move = Vector2(0, -1)
	var p0 := strong.global_position
	await wait(1.0)
	cbot.move = Vector2.ZERO
	check(agile.global_position.distance_to(strong.global_position) < 1.6, "a ágil acompanha o forte andando")
	check(strong.global_position.distance_to(p0) > 4.0, "o forte anda carregando a parceira")
	cbot.queue.append("special")
	var max_y := agile.global_position.y
	for i in 60:
		await get_tree().physics_frame
		max_y = maxf(max_y, agile.global_position.y)
	check(agile.state != Hero.S.RIDE and max_y - strong.global_position.y > 3.0, "o forte lança a parceira alto (%.1f m)" % (max_y - strong.global_position.y))
	strong.controller = null
	await wait(2.0)


func _t_enemy() -> void:
	print("[inimigos]")
	control(agile)
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	if enemies.is_empty():
		print("  (sem inimigos na receita)")
		return
	var e: Silente = enemies[0]
	place(agile, e.global_position + Vector3.UP * 3.0)
	for i in 90:
		await get_tree().physics_frame
		if e.dead:
			break
	check(e.dead, "pular em cima vence o inimigo")
	await wait(0.8)
	enemies = get_tree().get_nodes_in_group(&"enemies")
	if enemies.is_empty():
		return
	var e2: Silente = enemies[0]
	place(agile, e2.global_position + Vector3(1.2, 1.0, 0))
	await wait(0.6)
	bot.queue.append("action")
	await wait(0.3)
	check(not is_instance_valid(e2) or e2.dead, "o giro da ágil vence o inimigo")
	await wait(1.0)


func _t_plates() -> void:
	print("[placas + portões]")
	var gates := nodes_of(Interactables.StoneGate)
	if gates.is_empty():
		print("  (sem portões na receita)")
		return
	agile.controller = null
	strong.controller = null
	for g in gates:
		var group: String = g.group_id
		var plates := get_tree().get_nodes_in_group(&"plates").filter(func(pl): return pl.group_id == group)
		check(not g.opened, "portão '%s' começa fechado" % group)
		var heavy := plates.filter(func(pl): return pl.heavy)
		var light := plates.filter(func(pl): return not pl.heavy)
		if not heavy.is_empty():
			place(agile, heavy[0].global_position + Vector3.UP * 1.0)
			await wait(1.2)
			check(not heavy[0].pressed, "placa pesada '%s' não desce com a ágil" % group)
		var hs: Array = [strong, agile]
		var order: Array = heavy + light
		for i in order.size():
			place(hs[mini(i, 1)], order[i].global_position + Vector3.UP * 1.0)
		await wait(1.6)
		check(order.all(func(pl): return pl.pressed), "placas do grupo '%s' descem" % group)
		await wait(0.5)
		check(g.opened, "portão '%s' abre" % group)
		place(strong, flat_spot(level.content.spawn_point()) + Vector3(2, 0.6, 0))
		place(agile, flat_spot(level.content.spawn_point()) + Vector3(0, 0.6, 0))
		await wait(0.6)
	control(agile)


func _t_motes() -> void:
	print("[coletáveis]")
	control(agile)
	var field: MoteField = content.mote_field
	check(field.points.size() > 80, "coletáveis espalhados (%d)" % field.points.size())
	if field.points.is_empty():
		return
	var before := Game.motes
	var lines: Array = content.data.get("motes", []).filter(func(e): return e.has("line"))
	if lines.is_empty():
		place(agile, field.points[0] + Vector3.UP * 0.2)
		await wait(0.8)
	else:
		var a: Array = lines[0]["line"]
		var s := terrain.surface(float(a[0][0]), float(a[0][1]))
		var e := terrain.surface(float(a[1][0]), float(a[1][1]))
		var dir := e - s
		dir.y = 0.0
		place(agile, s + Vector3.UP * 0.6, atan2(dir.x, dir.z))
		await wait(0.5)
		bot.yaw = atan2(-dir.x, -dir.z)
		bot.move = Vector2(0, -1)
		await wait(minf(dir.length() / 7.0 + 0.5, 6.0))
		bot.move = Vector2.ZERO
	check(Game.motes - before >= 3, "passar pela trilha coleta (+%d)" % (Game.motes - before))


func _t_respawn() -> void:
	print("[queda + retorno]")
	control(agile)
	place(agile, Vector3(0, level.kill_y - 5.0, 0))
	await wait(1.0)
	check(agile.global_position.distance_to(Game.checkpoint) < 6.0, "cair do mundo volta ao ponto de retorno")


func _t_relics() -> void:
	print("[relíquias + final]")
	control(agile)
	var relics := get_tree().get_nodes_in_group(&"relics")
	check(relics.size() == 3, "3 relíquias (%d)" % relics.size())
	for s in relics:
		if not s.visible:
			s.reveal()
		await wait(0.2)
		place(agile, s.global_position + Vector3.UP * 0.4)
		await wait(0.5)
	check(Game.relics.size() == 3, "coletou as 3 relíquias (%d)" % Game.relics.size())
	var goal: Node3D = content.goal
	if not check(goal != null, "objetivo final existe"):
		return
	place(agile, goal.global_position + Vector3(0, 1.5, 7.5))
	await wait(1.2)
	check(Game.finale_done, "o final começa com as 3 relíquias")
	await wait(10.0)
	check(agile.state != Hero.S.CUTSCENE, "controle volta depois da cena final")
