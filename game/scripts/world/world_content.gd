extends Node3D
## Monta o conteúdo de jogo da receita (seção "content") sobre o terreno
## contínuo: ponto de partida, props, interativos, inimigos e decoração.
## Posições [x, z] encaixam na superfície do terreno (consulta direta ao
## heightfield, sem física); [x, y, z] são absolutas.

var level: Node3D
var builder: WorldBuilder
var terrain: SandTerrain
var data: Dictionary
var menu_focus: Node3D          ## o que a câmera do menu orbita
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
	_place_heroes.call_deferred()
	set_quality(Game.quality)


func ground(x: float, z: float) -> Vector3:
	return terrain.surface(x, z)


func pos_of(a, extra_h := 0.0) -> Vector3:
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return ground(float(a[0]), float(a[1])) + Vector3.UP * extra_h


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


func set_quality(q: int) -> void:
	_quality = q
