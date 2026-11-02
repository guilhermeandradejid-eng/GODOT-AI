class_name SandTrails
extends Node
## Rastros na areia (pegadas e sulcos de surfe) que somem devagar, como no Journey.
## Um SubViewport HDR acumula "carimbos" macios onde os heróis pisam; um retângulo
## semitransparente a cada quadro faz os rastros desbotarem. O shader do terreno lê
## a textura (escurece + afunda a normal). A área segue o jogador e recentraliza.

const TEX := 512
const AREA := 64.0          ## metros cobertos pela textura (12,5 cm por pixel)
const RECENTER := 18.0      ## distância do centro que dispara a recentralização
const HALF_LIFE := 4.0      ## segundos para um rastro perder metade da força (o vento cobre)

var terrain: SandTerrain
var viewport: SubViewport
var _canvas: _Stamps
var _fade: ColorRect
var _bg: ColorRect
var _copy: SubViewport
var _shift: TextureRect
var _busy := false
var _center := Vector2.ZERO
var _active := true


class _Stamps extends Node2D:
	var pending: Array = []      ## [pos(px), radius(px), strength]
	var dot: Texture2D
	var _drew := false
	func _process(_d: float) -> void:
		if not pending.is_empty() or _drew:
			queue_redraw()
	func _draw() -> void:
		_drew = false
		for p in pending:
			var r: float = p[1]
			# the HDR target is linear: convert so `strength` is the value the shader reads
			var c := Color(p[2], p[2], p[2], 1.0).linear_to_srgb()
			draw_texture_rect(dot, Rect2(p[0] - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
			_drew = true
		pending.clear()


func setup(t: SandTerrain) -> void:
	terrain = t
	add_to_group(&"sand_trails")
	viewport = _make_viewport(SubViewport.UPDATE_ALWAYS)
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 1)
	_bg.size = Vector2(TEX, TEX)
	viewport.add_child(_bg)
	# old trails, redrawn shifted when the area recenters (see _recenter)
	_copy = _make_viewport(SubViewport.UPDATE_DISABLED)
	var src := TextureRect.new()
	src.texture = viewport.get_texture()
	src.size = Vector2(TEX, TEX)
	_copy.add_child(src)
	_shift = TextureRect.new()
	_shift.texture = _copy.get_texture()
	_shift.size = Vector2(TEX, TEX)
	_shift.visible = false
	viewport.add_child(_shift)
	_fade = ColorRect.new()
	_fade.size = Vector2(TEX, TEX)
	_fade.color = Color(0, 0, 0, 0.0)
	viewport.add_child(_fade)
	_canvas = _Stamps.new()
	_canvas.dot = _small_dot()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = mat
	viewport.add_child(_canvas)
	_center = Vector2.ZERO
	_apply_uniforms()
	# the background rect only clears once (then the fade rect keeps decaying)
	await RenderingServer.frame_post_draw
	_bg.visible = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER


## Ponto macio pequeno (os carimbos têm poucos pixels; uma textura grande sem
## mipmaps seria amostrada com serrilhado e perderia o pico).
static func _small_dot() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_viewport(update: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX, TEX)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.use_hdr_2d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = update
	add_child(vp)
	return vp


## Move a área dos rastros para perto do jogador SEM apagar o que já existe:
## copia a textura atual e a redesenha deslocada sob o novo centro.
func _recenter(c: Vector2) -> void:
	if _busy:
		return
	_busy = true
	var new_center := c.snapped(Vector2(4.0, 4.0))
	_copy.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_shift.position = (_center - new_center) / AREA * TEX
	_shift.visible = true
	_bg.visible = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_center = new_center
	_apply_uniforms()
	await RenderingServer.frame_post_draw
	_shift.visible = false
	_bg.visible = false
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_busy = false


func _apply_uniforms() -> void:
	if terrain == null:
		return
	terrain.set_param("trail_tex", viewport.get_texture())
	terrain.set_param("trail_rect", Vector4(_center.x - AREA * 0.5, _center.y - AREA * 0.5, AREA, 1.0))


## Carimba um rastro em (x, z). radius em metros, strength 0..1.
func stamp(world: Vector3, radius := 0.35, strength := 0.5) -> void:
	if not _active or _canvas == null:
		return
	var px := (Vector2(world.x, world.z) - (_center - Vector2(AREA, AREA) * 0.5)) / AREA * TEX
	if px.x < 0 or px.y < 0 or px.x > TEX or px.y > TEX:
		return
	_canvas.pending.append([px, radius / AREA * TEX, strength])


## Traça um sulco contínuo de a até b (carimbos a cada ~1 pixel).
func stroke(a: Vector3, b: Vector3, radius := 0.2, strength := 0.12) -> void:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := clampi(int(ceil(d / (AREA / TEX))), 1, 48)
	for i in n:
		stamp(a.lerp(b, (i + 1.0) / n), radius, strength)


func _process(delta: float) -> void:
	if _fade != null:
		# time-based decay (same look at 30 or 60 fps); the HDR target keeps tiny steps
		_fade.color.a = 1.0 - pow(0.5, delta / HALF_LIFE)


func follow(world: Vector3) -> void:
	if _canvas == null:
		return
	if Vector2(world.x, world.z).distance_to(_center) > RECENTER:
		_recenter(Vector2(world.x, world.z))
