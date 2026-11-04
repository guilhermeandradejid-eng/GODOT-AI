class_name ScarfCloth
extends MeshInstance3D
## Pontas do cachecol como TECIDO simulado em tempo real (dinâmica baseada em posição, PBD).
## Cada ponta é uma fita de partículas (2 colunas × N linhas) presa ao nó do cachecol, que
## segue um osso do esqueleto. Forças: gravidade, inércia (o pano fica para trás quando o
## herói corre, gira ou salta), arrasto aerodinâmico por triângulo (é ele que faz o tecido
## tremular contra o ar), vento do mundo com rajadas e uma onda de tremulação. Restrições de
## distância (comprimento, largura, cisalhamento, dobra), limite de esticamento até a raiz
## e colisão com esferas/cápsulas presas aos ossos do corpo. Roda no passo de física;
## a malha é redesenhada a cada quadro (ImmediateMesh, dois lados).

const CLOTH_SHADER := preload("res://game/shaders/hero_cloth.gdshader")
## Vento do mundo (mesma direção das faixas de areia: wind_deg 25° da receita).
const WIND_DIR := Vector3(0.906, 0.05, 0.423)

var rows := 14                  ## partículas ao longo de cada ponta
var length := 0.7               ## comprimento de cada ponta (m)
var width_root := 0.085
var width_tip := 0.07
var gravity := 9.8
var air_damping := 0.6          ## amortecimento geral (1/s)
var aero := 1.4                 ## arrasto normal ao pano (quadrático, 1/m)
var aero_tangent := 0.08        ## arrasto ao longo do pano (linear)
var wind_speed := 2.4           ## vento base (m/s)
var flutter := 7.0              ## onda de tremulação (m/s²)
var iterations := 4
var substeps := 2
var bend := 0.22                ## rigidez de dobra (0..1)
var hang := Vector3(0.0, -0.8, -0.6)   ## direção de repouso das pontas, no espaço do osso
var colors := [Color("d6322b"), Color("9e1f1f")]

var sk: Skeleton3D
var bone_idx := -1
var tails: Array = []           ## por ponta: [raiz esquerda, raiz direita] (espaço do osso)
var colliders: Array = []       ## [osso, raio, deslocamento, altura (0 = esfera)]

var _n := 0                     ## partículas por ponta
var _seg := 0.05
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _acc := PackedVector3Array()
var _w := PackedFloat32Array()  ## inverso da massa (0 = presa)
var _rest := PackedVector3Array()   ## posição das raízes no espaço do osso, por partícula presa
var _root_of := PackedInt32Array()  ## partícula presa da mesma coluna
var _root_d := PackedFloat32Array() ## distância máxima até a raiz (limite de esticamento)
var _ca := PackedInt32Array()
var _cb := PackedInt32Array()
var _cl := PackedFloat32Array()
var _ck := PackedFloat32Array()
var _col_pts: Array = []        ## colisores no espaço do mundo, neste passo
var _anchor := Transform3D()
var _anchor_prev := Transform3D()
var _t := 0.0
var _imesh: ImmediateMesh
var _mat: ShaderMaterial
var _live := false


func setup(skel: Skeleton3D, cfg: Dictionary, overrides := {}) -> void:
	sk = skel
	bone_idx = sk.find_bone(String(cfg.get("bone", "neck")))
	tails = cfg.get("tails", [])
	for k in ["rows", "length", "width_root", "width_tip", "gravity", "air_damping", "aero", "aero_tangent",
			"wind_speed", "flutter", "iterations", "substeps", "bend", "hang", "colors"]:
		if cfg.has(k):
			set(k, cfg[k])
	for c in cfg.get("colliders", []):
		var bi := sk.find_bone(String(c[0]))
		if bi >= 0:
			colliders.append([bi, float(c[1]), c[2] if c.size() > 2 else Vector3.ZERO, float(c[3]) if c.size() > 3 else 0.0])
	top_level = true
	global_transform = Transform3D.IDENTITY
	_imesh = ImmediateMesh.new()
	mesh = _imesh
	_mat = ShaderMaterial.new()
	_mat.shader = CLOTH_SHADER
	_mat.set_shader_parameter("use_texture", true)
	_mat.set_shader_parameter("albedo_tex", _stripe_texture())
	_mat.set_shader_parameter("sss_strength", 0.5)
	_mat.set_shader_parameter("sss_color", Color(1.0, 0.36, 0.24))
	_mat.set_shader_parameter("rim_strength", 1.0)
	_mat.set_shader_parameter("sheen", 0.06)
	for k in overrides:
		_mat.set_shader_parameter(k, overrides[k])
	material_override = null
	_build()
	_live = bone_idx >= 0 and not tails.is_empty()
	if _live:
		reset()


## Material do pano (para o flash de dano, etc.).
func material() -> ShaderMaterial:
	return _mat


# ------------------------------------------------------------------ build
func _idx(t: int, r: int, c: int) -> int:
	return t * _n + r * 2 + c


func _build() -> void:
	_n = rows * 2
	var total := _n * tails.size()
	_pos.resize(total)
	_prev.resize(total)
	_acc.resize(total)
	_w.resize(total)
	_rest.resize(total)
	_root_of.resize(total)
	_root_d.resize(total)
	_seg = length / float(rows - 1)
	for t in tails.size():
		for r in rows:
			for c in 2:
				var i := _idx(t, r, c)
				_w[i] = 0.0 if r == 0 else 1.0
				_root_of[i] = _idx(t, 0, c)
				_root_d[i] = _seg * r * 1.03
				_rest[i] = tails[t][c] if r == 0 else Vector3.ZERO
	# restrições: comprimento, largura, cisalhamento e dobra (distâncias de repouso da fita reta)
	_ca.clear(); _cb.clear(); _cl.clear(); _ck.clear()
	for t in tails.size():
		var wr: float = (tails[t][0] as Vector3).distance_to(tails[t][1])
		for r in rows:
			var wid := lerpf(wr, wr * width_tip / width_root, float(r) / (rows - 1))
			_con(_idx(t, r, 0), _idx(t, r, 1), wid, 1.0)
			if r + 1 < rows:
				var wid2 := lerpf(wr, wr * width_tip / width_root, float(r + 1) / (rows - 1))
				for c in 2:
					_con(_idx(t, r, c), _idx(t, r + 1, c), _seg, 1.0)
				var diag := sqrt(_seg * _seg + pow((wid + wid2) * 0.5, 2.0))
				_con(_idx(t, r, 0), _idx(t, r + 1, 1), diag, 0.7)
				_con(_idx(t, r, 1), _idx(t, r + 1, 0), diag, 0.7)
			if r + 2 < rows:
				for c in 2:
					_con(_idx(t, r, c), _idx(t, r + 2, c), _seg * 2.0, bend)


func _con(a: int, b: int, l: float, k: float) -> void:
	_ca.append(a)
	_cb.append(b)
	_cl.append(l)
	_ck.append(k)


func _bone_xf() -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(bone_idx)


## Recoloca o pano pendurado na pose de repouso (início e teletransportes).
func reset() -> void:
	if not _live:
		return
	_anchor = _bone_xf()
	_anchor_prev = _anchor
	var down := (_anchor.basis * hang).normalized()
	for t in tails.size():
		for c in 2:
			var root: Vector3 = _anchor * (tails[t][c] as Vector3)
			for r in rows:
				var i := _idx(t, r, c)
				_pos[i] = root + down * (_seg * r)
				_prev[i] = _pos[i]


# ------------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	if not _live or not is_inside_tree():
		return
	var a := _bone_xf()
	if a.origin.distance_squared_to(_anchor.origin) > 9.0:
		reset()
		return
	_anchor_prev = _anchor
	_anchor = a
	_update_colliders()
	var h := delta / float(substeps)
	for s in substeps:
		_t += h
		var at := _anchor_prev.interpolate_with(_anchor, float(s + 1) / float(substeps))
		_pin(at)
		_forces(h)
		_integrate(h)
		for it in iterations:
			_solve()
		_limit_stretch()
		_collide()


func _pin(at: Transform3D) -> void:
	for i in _pos.size():
		if _w[i] == 0.0:
			var p := at * _rest[i]
			_prev[i] = p
			_pos[i] = p


func _forces(h: float) -> void:
	var gust := 0.7 + 0.3 * sin(_t * 0.8) * sin(_t * 0.27 + 1.3)
	var wind := WIND_DIR * (wind_speed * gust)
	var inv_h := 1.0 / h
	for i in _acc.size():
		_acc[i] = Vector3.ZERO
	for t in tails.size():
		for r in rows - 1:
			var i0 := _idx(t, r, 0)
			var wave := sin(_t * 12.0 - r * 0.85 + t * 1.7) * flutter * (0.25 + 0.75 * float(r) / rows)
			_tri(i0, i0 + 1, i0 + 2, wind, inv_h, wave)
			_tri(i0 + 1, i0 + 3, i0 + 2, wind, inv_h, wave)


func _tri(a: int, b: int, c: int, wind: Vector3, inv_h: float, wave: float) -> void:
	var p0 := _pos[a]
	var nrm := (_pos[b] - p0).cross(_pos[c] - p0)
	var l := nrm.length()
	if l < 1e-9:
		return
	nrm /= l
	var v := ((p0 - _prev[a]) + (_pos[b] - _prev[b]) + (_pos[c] - _prev[c])) * (inv_h / 3.0)
	var rel := v - wind
	var vn := rel.dot(nrm)
	var f := nrm * (-aero * vn * absf(vn) + wave) - (rel - nrm * vn) * aero_tangent
	if f.length_squared() > 6400.0:
		f = f.normalized() * 80.0
	f /= 3.0
	_acc[a] += f
	_acc[b] += f
	_acc[c] += f


func _integrate(h: float) -> void:
	var g := Vector3(0.0, -gravity, 0.0)
	var keep := clampf(1.0 - air_damping * h, 0.0, 1.0)
	var hh := h * h
	for i in _pos.size():
		if _w[i] == 0.0:
			continue
		var p := _pos[i]
		var v := (p - _prev[i]) * keep
		_prev[i] = p
		_pos[i] = p + v + (g + _acc[i]) * hh


func _solve() -> void:
	for k in _ca.size():
		var a := _ca[k]
		var b := _cb[k]
		var wa := _w[a]
		var wb := _w[b]
		var ws := wa + wb
		if ws == 0.0:
			continue
		var d := _pos[b] - _pos[a]
		var l := d.length()
		if l < 1e-7:
			continue
		var corr := d * ((l - _cl[k]) / (l * ws) * _ck[k])
		_pos[a] += corr * wa
		_pos[b] -= corr * wb


## Nenhuma partícula fica mais longe da raiz do que o comprimento da fita (sem efeito elástico).
func _limit_stretch() -> void:
	for i in _pos.size():
		if _w[i] == 0.0:
			continue
		var root := _pos[_root_of[i]]
		var d := _pos[i] - root
		var l := d.length()
		if l > _root_d[i]:
			_pos[i] = root + d * (_root_d[i] / l)


func _update_colliders() -> void:
	_col_pts.clear()
	var sx := sk.global_transform
	for c in colliders:
		var bx := sx * sk.get_bone_global_pose(int(c[0]))
		var center: Vector3 = bx * (c[2] as Vector3)
		var hgt := float(c[3])
		if hgt > 0.0:
			var axis := bx.basis.y.normalized() * (hgt * 0.5)
			_col_pts.append([center - axis, center + axis, float(c[1])])
		else:
			_col_pts.append([center, center, float(c[1])])


func _collide() -> void:
	for c in _col_pts:
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var r: float = c[2] + 0.012
		var ab := b - a
		var ab2 := maxf(ab.length_squared(), 1e-9)
		for i in _pos.size():
			if _w[i] == 0.0:
				continue
			var p := _pos[i]
			var q := a + ab * clampf((p - a).dot(ab) / ab2, 0.0, 1.0)
			var d := p - q
			var l2 := d.length_squared()
			if l2 < r * r:
				var l := sqrt(l2)
				_pos[i] = q + (d / l if l > 1e-6 else Vector3.UP) * r


# ------------------------------------------------------------------ drawing
func _process(_delta: float) -> void:
	if not _live:
		return
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	for t in tails.size():
		for r in rows - 1:
			var i0 := _idx(t, r, 0)
			var v0 := float(r) / (rows - 1)
			var v1 := float(r + 1) / (rows - 1)
			var n0 := _normal(t, r)
			var n1 := _normal(t, r + 1)
			_vert(_pos[i0], n0, Vector2(0.0, v0))
			_vert(_pos[i0 + 1], n0, Vector2(1.0, v0))
			_vert(_pos[i0 + 2], n1, Vector2(0.0, v1))
			_vert(_pos[i0 + 1], n0, Vector2(1.0, v0))
			_vert(_pos[i0 + 3], n1, Vector2(1.0, v1))
			_vert(_pos[i0 + 2], n1, Vector2(0.0, v1))
	_imesh.surface_end()


func _normal(t: int, r: int) -> Vector3:
	var i := _idx(t, r, 0)
	var across := _pos[i + 1] - _pos[i]
	var along := (_pos[_idx(t, mini(r + 1, rows - 1), 0)] - _pos[_idx(t, maxi(r - 1, 0), 0)])
	var n := across.cross(along)
	return n.normalized() if n.length_squared() > 1e-12 else Vector3.UP


func _vert(p: Vector3, n: Vector3, uv: Vector2) -> void:
	_imesh.surface_set_normal(n)
	_imesh.surface_set_uv(uv)
	_imesh.surface_set_color(Color(1, 1, 1, 1))
	_imesh.surface_add_vertex(p)


## Faixas do cachecol: vermelho com bordas e duas listras escuras perto da ponta.
func _stripe_texture() -> ImageTexture:
	var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
	var main: Color = colors[0]
	var shade: Color = colors[1]
	for y in 64:
		var v := y / 63.0
		var stripe := (v > 0.74 and v < 0.79) or (v > 0.84 and v < 0.89)
		for x in 8:
			var edge := x == 0 or x == 7
			var col := main
			if stripe:
				col = shade
			elif edge:
				col = main.lerp(shade, 0.45)
			if v > 0.965:
				col = col.lightened(0.12)   # franja clara na ponta
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
