@tool
extends RefCounted
## Procedural vegetation and prop meshes for vibe_scatter.
##
## Every model is generated from code (tapered tubes, leaf cards, displaced
## spheres) in several variants, each with a near and a far (LOD) version,
## cached per style. Leaf cards use spherical normals around their canopy,
## so foliage shades like a soft volume instead of flat quads.
##
## Vertex data: COLOR.rgb = tint / ambient occlusion, COLOR.a = flexibility
## (0 = rigid base, 1 = swaying tips); UV = texture coordinates; UV2.x = sway
## phase per branch/card. Surface 0 = solid (wood, rock...), surface 1 =
## foliage cards (alpha-tested, two-sided).

const KINDS := ["broadleaf", "pine", "palm", "birch", "acacia", "dead_tree", "bush", "fern", "cactus", "barrel_cactus",
	"rock", "boulder", "pebbles", "mushroom", "crystal", "log", "stump"]
const VARIANTS := 4

static var _cache := {}


class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, col: Color, t: Vector2, t2: Vector2) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	## Two triangles for corners a, b, c, d given counter-clockwise as seen
	## from the front (Godot's front faces are clockwise).
	func quad(a: int, b: int, cc: int, d: int) -> void:
		idx.append_array([a, cc, b, a, d, cc])

	func tri(a: int, b: int, cc: int) -> void:
		idx.append_array([a, cc, b])

	func empty() -> bool:
		return idx.is_empty()

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


class Geo:
	var solid := Surf.new()
	var leaves := Surf.new()
	var rng := RandomNumberGenerator.new()
	var flat := false
	var lod := 0
	## Collision hint: [type, radius, height] in model space.
	var collider := []

	func r(a: float, b: float) -> float:
		return rng.randf_range(a, b)

	## Tapered tube along a polyline (parallel-transport frames).
	func tube(pts: Array, radii: Array, sides: int, col: Color, flex0: float, flex1: float, phase: float = 0.0, v_scale: float = 1.0, cap: bool = true, rib: Callable = Callable()) -> void:
		var s := solid
		var count := pts.size()
		if count < 2:
			return
		var tangent: Vector3 = ((pts[1] as Vector3) - (pts[0] as Vector3)).normalized()
		var normal := tangent.cross(Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.BACK).normalized()
		var base := s.v.size()
		var length := 0.0
		var ring := sides + 1
		for i in count:
			var p: Vector3 = pts[i]
			var t: Vector3
			if i == 0:
				t = ((pts[1] as Vector3) - p).normalized()
			elif i == count - 1:
				t = (p - (pts[i - 1] as Vector3)).normalized()
			else:
				t = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).normalized()
			normal = (normal - t * normal.dot(t)).normalized()
			var b := t.cross(normal)
			if i > 0:
				length += p.distance_to(pts[i - 1])
			var fl := lerpf(flex0, flex1, float(i) / float(count - 1))
			var rad: float = radii[i]
			for k in ring:
				var ang := TAU * float(k) / float(sides)
				var dir := normal * cos(ang) + b * sin(ang)
				var rr := rad
				if rib.is_valid():
					rr *= float(rib.call(ang))
				var cl := col
				cl.a = fl
				s.add(p + dir * rr, dir, cl, Vector2(float(k) / float(sides), length * v_scale), Vector2(phase, 0.0))
		for i in count - 1:
			for k in sides:
				var p00 := base + i * ring + k
				var p01 := p00 + 1
				var p10 := p00 + ring
				var p11 := p10 + 1
				s.quad(p00, p01, p11, p10)
		if cap:
			var last: Vector3 = pts[count - 1]
			var tl: Vector3 = (last - (pts[count - 2] as Vector3)).normalized()
			var cl2 := col
			cl2.a = flex1
			var tip := s.add(last + tl * (radii[count - 1] as float) * 0.6, tl, cl2, Vector2(0.5, length * v_scale + 0.1), Vector2(phase, 0.0))
			var start := base + (count - 1) * ring
			for k in sides:
				s.tri(start + k, start + k + 1, tip)

	## A leaf card: a square facing `facing`, spun by `spin`, with normals
	## bent toward `center` (soft volumetric shading). Two cards cross when
	## `cross` is set.
	func card(pos: Vector3, facing: Vector3, spin: float, size: Vector2, col: Color, flex: float, center: Vector3, bend: float = 0.7, uv_rect: Rect2 = Rect2(0, 0, 1, 1), phase: float = 0.0) -> void:
		var s := leaves
		var nrm := facing.normalized()
		var up := Vector3.UP if absf(nrm.y) < 0.95 else Vector3.BACK
		var right := up.cross(nrm).normalized()
		up = nrm.cross(right).normalized()
		var q := Quaternion(nrm, spin)
		right = q * right
		up = q * up
		var hw := size.x * 0.5
		var hh := size.y * 0.5
		var corners := [pos - right * hw - up * hh, pos + right * hw - up * hh, pos + right * hw + up * hh, pos - right * hw + up * hh]
		var uvs := [uv_rect.position + Vector2(0, uv_rect.size.y), uv_rect.position + uv_rect.size, uv_rect.position + Vector2(uv_rect.size.x, 0), uv_rect.position]
		var ids: Array = []
		for i in 4:
			var cp: Vector3 = corners[i]
			var sn := (cp - center)
			var nn := nrm.lerp(sn.normalized() if sn.length() > 0.001 else nrm, bend).normalized()
			var cl := col
			cl.a = flex
			ids.append(s.add(cp, nn, cl, uvs[i], Vector2(phase, 1.0)))
		s.quad(ids[0], ids[1], ids[2], ids[3])

	## A strip card along a curve (palm fronds, ferns, pine branches):
	## spine points, widths, side direction per point; UV x along, y across.
	func strip(spine: Array, widths: Array, side_dirs: Array, col: Color, flex0: float, flex1: float, center: Vector3, fold: float = 0.0, phase: float = 0.0, bend: float = 0.55) -> void:
		var s := leaves
		var count := spine.size()
		var base := s.v.size()
		for i in count:
			var p: Vector3 = spine[i]
			var sd: Vector3 = (side_dirs[i] as Vector3).normalized()
			var w: float = widths[i]
			var along: Vector3 = ((spine[mini(i + 1, count - 1)] as Vector3) - (spine[maxi(i - 1, 0)] as Vector3)).normalized()
			var nrm := along.cross(sd).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var t := float(i) / float(count - 1)
			var fl := lerpf(flex0, flex1, t)
			for j in 3:
				var off := (float(j) - 1.0)
				var cp := p + sd * off * w * 0.5 + nrm * absf(off) * fold * w * 0.5
				var sn := (cp - center)
				var nn := nrm.lerp(sn.normalized() if sn.length() > 0.001 else nrm, bend).normalized()
				var cl := col
				cl.a = fl
				s.add(cp, nn, cl, Vector2(t, float(j) * 0.5), Vector2(phase, 1.0))
		for i in count - 1:
			for j in 2:
				var a := base + i * 3 + j
				s.quad(a, a + 1, a + 4, a + 3)

	func sphere(center: Vector3, radius: Vector3, rings: int, sides: int, col: Color, flex: float, disp: Callable = Callable(), flat_bottom: float = -INF, target: Surf = null) -> void:
		var s := solid if target == null else target
		var leaf_flag := 1.0 if target == leaves else 0.0
		var base := s.v.size()
		for i in rings + 1:
			var th := PI * float(i) / float(rings)
			for k in sides + 1:
				var ph := TAU * float(k) / float(sides)
				var dir := Vector3(sin(th) * cos(ph), -cos(th), sin(th) * sin(ph))
				var rr := 1.0
				if disp.is_valid():
					rr = float(disp.call(dir))
				var p := center + dir * radius * rr
				if p.y < flat_bottom:
					p.y = flat_bottom
				var cl := col
				cl.a = flex
				s.add(p, dir, cl, Vector2(float(k) / float(sides), float(i) / float(rings)), Vector2(center.x * 0.7 + center.z, leaf_flag))
		for i in rings:
			for k in sides:
				var a := base + i * (sides + 1) + k
				s.quad(a, a + sides + 1, a + sides + 2, a + 1)


	## A cone (low poly pine layers) on the foliage surface.
	func cone(base_y: float, radius: float, height: float, sides: int, col: Color, flex0: float, flex1: float) -> void:
		var s := leaves
		var start := s.v.size()
		var tilt := rng.randf_range(-0.2, 0.2)
		for k in sides + 1:
			var a := TAU * float(k) / float(sides) + tilt
			var dir := Vector3(cos(a), 0, sin(a))
			var cl := col
			cl.a = flex0
			var jag := radius * rng.randf_range(0.85, 1.1)
			s.add(Vector3(0, base_y, 0) + dir * jag, (dir + Vector3.UP * 0.6).normalized(), cl, Vector2(0, 0), Vector2(base_y, 1.0))
		var cl2 := col
		cl2.a = flex1
		var tip := s.add(Vector3(0, base_y + height, 0), Vector3.UP, cl2, Vector2(0, 0), Vector2(base_y, 1.0))
		for k in sides:
			s.tri(start + k + 1, start + k, tip)
		# Underside.
		var bottom := s.add(Vector3(0, base_y + height * 0.12, 0), Vector3.DOWN, col, Vector2(0, 0), Vector2(base_y, 1.0))
		for k in sides:
			s.tri(start + k, start + k + 1, bottom)


# =============================================================================
# Public API
# =============================================================================

## Meshes of a kind/variant/style, one surface each so every part can get
## its own material on a MultiMeshInstance3D:
## {"near": {"solid": ArrayMesh|null, "leaves": ArrayMesh|null}, "far": {...},
##  "collider": [type, radius, height], "height": float}
static func get_model(kind: String, variant: int, style: String) -> Dictionary:
	var key := "%s/%d/%s" % [kind, variant, style]
	if _cache.has(key):
		return _cache[key]
	var near := _build(kind, variant, style, 0)
	var far := _build(kind, variant, style, 1)
	var out := {"near": near.meshes, "far": far.meshes, "collider": near.collider, "height": near.height}
	_cache[key] = out
	return out


static func _build(kind: String, variant: int, style: String, lod: int) -> Dictionary:
	var g := Geo.new()
	g.rng.seed = hash([kind, variant]) & 0x7fffffff
	g.flat = style == "lowpoly"
	g.lod = lod
	match kind:
		"broadleaf":
			_broadleaf(g, style, false)
		"birch":
			_broadleaf(g, style, true)
		"acacia":
			_acacia(g, style)
		"pine":
			_pine(g, style)
		"palm":
			_palm(g, style)
		"dead_tree":
			_dead_tree(g)
		"bush":
			_bush(g, style)
		"fern":
			_fern(g)
		"cactus":
			_cactus(g)
		"barrel_cactus":
			_barrel_cactus(g)
		"rock":
			_rock(g, 1.0, lod)
		"boulder":
			_rock(g, 2.4, lod)
		"pebbles":
			for i in 5:
				var c := Vector3(g.r(-0.5, 0.5), 0, g.r(-0.5, 0.5))
				_rock(g, g.r(0.12, 0.3), 1, c)
		"mushroom":
			_mushrooms(g)
		"crystal":
			_crystals(g)
		"log":
			_log(g)
		"stump":
			_stump(g)
	var meshes := {"solid": null, "leaves": null}
	var h := 0.5
	for part in ["solid", "leaves"]:
		var surf: Surf = g.solid if part == "solid" else g.leaves
		if surf.empty():
			continue
		if g.flat:
			surf = _flatten(surf)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf.arrays())
		meshes[part] = mesh
		for p in surf.v:
			h = maxf(h, p.y)
	return {"meshes": meshes, "collider": g.collider, "height": h}


## Flat shading: every triangle gets its own vertices and face normal.
static func _flatten(s: Surf) -> Surf:
	var o := Surf.new()
	for t in range(0, s.idx.size(), 3):
		var a := s.idx[t]
		var b := s.idx[t + 1]
		var c := s.idx[t + 2]
		var fn := (s.v[c] - s.v[a]).cross(s.v[b] - s.v[a])
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		for i in [a, b, c]:
			o.idx.append(o.add(s.v[i], fn, s.c[i], s.uv[i], s.uv2[i]))
	return o


# =============================================================================
# Trees
# =============================================================================

static func _bent_path(g: Geo, base: Vector3, dir: Vector3, length: float, segs: int, wobble: float, gravity: float = 0.0) -> Array:
	var pts: Array = [base]
	var d := dir.normalized()
	var p := base
	for i in segs:
		d = (d + Vector3(g.r(-wobble, wobble), g.r(-wobble, wobble) * 0.3, g.r(-wobble, wobble)) + Vector3.DOWN * gravity).normalized()
		p += d * (length / float(segs))
		pts.append(p)
	return pts


static func _taper(count: int, r0: float, r1: float, flare: float = 0.0) -> Array:
	var out: Array = []
	for i in count:
		var t := float(i) / float(count - 1)
		var rr := lerpf(r0, r1, pow(t, 0.8))
		if flare > 0.0 and t < 0.15:
			rr *= 1.0 + flare * (1.0 - t / 0.15)
		out.append(rr)
	return out


static func _canopy(g: Geo, clusters: Array, center: Vector3, leaf: Color, cards_per: int, card_size: float, uv: Rect2, flatten_y: float = 1.0) -> void:
	var lo := INF
	var hi := -INF
	for c in clusters:
		lo = minf(lo, (c[0] as Vector3).y - float(c[1]))
		hi = maxf(hi, (c[0] as Vector3).y + float(c[1]))
	if g.flat:
		for c in clusters:
			var cc0: Vector3 = c[0]
			var cr0: float = c[1]
			var hf := clampf((cc0.y - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
			var ao0 := 0.7 + 0.3 * hf
			var jitter := func(dir: Vector3) -> float: return 1.0 + 0.18 * sin(dir.x * 7.1 + dir.y * 5.3 + dir.z * 6.7 + cc0.x)
			g.sphere(cc0, Vector3(cr0 * 1.05, cr0 * 0.9 * flatten_y, cr0 * 1.05), 3, 6, Color(leaf.r * ao0, leaf.g * ao0, leaf.b * ao0, 0.7), 0.7, jitter, -INF, g.leaves)
		return
	var n := cards_per if g.lod == 0 else maxi(3, cards_per / 3)
	var size := card_size * (1.0 if g.lod == 0 else 1.55)
	for c in clusters:
		var cc: Vector3 = c[0]
		var cr: float = c[1]
		var phase := g.r(0.0, TAU)
		for i in n:
			var dir := Vector3(g.r(-1, 1), g.r(-0.6, 1.0), g.r(-1, 1)).normalized()
			var pos := cc + Vector3(dir.x, dir.y * flatten_y, dir.z) * cr * g.r(0.3, 0.95)
			var facing := (dir + Vector3(g.r(-0.5, 0.5), g.r(-0.2, 0.6), g.r(-0.5, 0.5))).normalized()
			var hfrac := clampf((pos.y - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
			var outer := clampf((pos - center).length() / maxf(cr * 2.0, 0.01), 0.0, 1.0)
			var ao := 0.5 + 0.35 * hfrac + 0.2 * outer
			var col := Color(leaf.r * ao, leaf.g * ao, leaf.b * ao)
			g.card(pos, facing, g.r(0.0, TAU), Vector2.ONE * size * g.r(0.8, 1.2), col, 0.55 + 0.45 * hfrac, center, 0.72, uv, phase)


static func _broadleaf(g: Geo, style: String, birch: bool) -> void:
	var shape := g.rng.randi_range(0, 2)
	var height := (g.r(4.2, 6.0) if shape != 1 else g.r(6.5, 8.0)) if not birch else g.r(5.5, 7.5)
	var r0 := g.r(0.17, 0.24) if not birch else g.r(0.1, 0.14)
	var sides := 5 if g.flat or g.lod == 1 else 9
	var trunk := _bent_path(g, Vector3.ZERO, Vector3.UP, height * 0.72, 6, 0.1 if not birch else 0.05)
	var bark := Color(1, 1, 1)
	g.tube(trunk, _taper(trunk.size(), r0, r0 * 0.45, 0.45 if not birch else 0.2), sides, bark, 0.0, 0.35, g.r(0, TAU), 1.0)
	g.collider = ["cylinder", r0 * 1.1, height * 0.6]
	var top: Vector3 = trunk[trunk.size() - 1]
	var clusters: Array = [[top + Vector3(0, height * 0.12, 0), height * (0.26 if not birch else 0.2)]]
	var branches := g.rng.randi_range(4, 6) if not birch else g.rng.randi_range(5, 8)
	for b in branches:
		var t := g.r(0.45, 0.85)
		var start: Vector3 = trunk[int(t * (trunk.size() - 1))]
		var az := TAU * float(b) / float(branches) + g.r(-0.4, 0.4)
		var elev := (g.r(0.35, 0.8) if shape != 2 else g.r(0.15, 0.45)) if not birch else g.r(0.2, 0.55)
		var dir := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev))
		var blen := height * g.r(0.25, 0.4) * (1.0 - t * 0.4) * (1.3 if shape == 2 else 1.0)
		var path := _bent_path(g, start, dir, blen, 3, 0.18, 0.05 if not birch else 0.12)
		if g.lod == 0 or b % 2 == 0:
			g.tube(path, _taper(path.size(), r0 * 0.42, r0 * 0.12), maxi(4, sides - 3), bark, 0.3, 0.7, g.r(0, TAU), 1.0)
		var tip: Vector3 = path[path.size() - 1]
		clusters.append([tip + Vector3(0, height * 0.04, 0), height * g.r(0.17, 0.24) * (0.8 if birch else 1.0)])
	var center := Vector3(0, 0, 0)
	for c in clusters:
		center += c[0]
	center /= float(clusters.size())
	var leaf := Color(1, 1, 1)
	var stylized := style in ["stylized", "toon", "cel"]
	var cards := 16 if not birch else 12
	var size := height * (0.24 if not stylized else 0.3) * (0.8 if birch else 1.0)
	_canopy(g, clusters, center, leaf, cards, size, Rect2(0, 0, 1, 1))


static func _acacia(g: Geo, style: String) -> void:
	var height := g.r(4.5, 6.0)
	var r0 := g.r(0.16, 0.22)
	var sides := 5 if g.flat or g.lod == 1 else 8
	var trunk := _bent_path(g, Vector3.ZERO, Vector3.UP + Vector3(g.r(-0.2, 0.2), 0, g.r(-0.2, 0.2)), height * 0.45, 4, 0.12)
	g.tube(trunk, _taper(trunk.size(), r0, r0 * 0.7, 0.3), sides, Color(1, 1, 1), 0.0, 0.2, 0.0)
	g.collider = ["cylinder", r0 * 1.1, height * 0.45]
	var fork: Vector3 = trunk[trunk.size() - 1]
	var clusters: Array = []
	var n := g.rng.randi_range(3, 4)
	for b in n:
		var az := TAU * float(b) / float(n) + g.r(-0.3, 0.3)
		var dir := Vector3(cos(az), g.r(0.9, 1.3), sin(az))
		var path := _bent_path(g, fork, dir, height * g.r(0.45, 0.6), 3, 0.12)
		g.tube(path, _taper(path.size(), r0 * 0.6, r0 * 0.2), maxi(4, sides - 2), Color(1, 1, 1), 0.2, 0.55, g.r(0, TAU))
		clusters.append([path[path.size() - 1] + Vector3(0, 0.25, 0), height * g.r(0.28, 0.36)])
	clusters.append([Vector3(0, height * 0.98, 0), height * 0.3])
	_canopy(g, clusters, Vector3(0, height * 0.95, 0), Color(1, 1, 1), 16, height * 0.26, Rect2(0, 0, 1, 1), 0.28)


static func _pine(g: Geo, style: String) -> void:
	var height := g.r(8.0, 12.5)
	var r0 := g.r(0.18, 0.26)
	var sides := 5 if g.flat or g.lod == 1 else 8
	var trunk := _bent_path(g, Vector3.ZERO, Vector3.UP, height, 6, 0.025)
	g.tube(trunk, _taper(trunk.size(), r0, r0 * 0.15, 0.35), sides, Color(1, 1, 1), 0.0, 0.5, g.r(0, TAU), 1.0)
	g.collider = ["cylinder", r0 * 1.1, height * 0.5]
	if g.flat:
		var layers := 4
		for i in layers:
			var t := float(i) / float(layers)
			var by := height * (0.2 + 0.62 * t)
			var rad := height * 0.24 * (1.0 - t * 0.72)
			g.cone(by, rad, height * 0.34, 7, Color(0.75 + 0.25 * t, 0.75 + 0.25 * t, 0.75 + 0.25 * t), 0.3 + 0.5 * t, 0.6 + 0.4 * t)
		return
	var y := height * g.r(0.16, 0.24)
	var whorl := 0
	var step := 0.55 if g.lod == 0 else 1.1
	var center := Vector3(0, height * 0.5, 0)
	while y < height * 0.97:
		var t := (y) / height
		var len_b := height * 0.26 * pow(maxf(1.0 - t, 0.0), 0.85) + 0.3
		var count := g.rng.randi_range(5, 7) if g.lod == 0 else 4
		var off := g.r(0, TAU)
		for k in count:
			var az := off + TAU * float(k) / float(count)
			var droop := g.r(0.12, 0.4) + t * 0.1
			var dir := Vector3(cos(az), -droop, sin(az)).normalized()
			var start := Vector3(0, y, 0)
			var spine: Array = []
			var widths: Array = []
			var sides_d: Array = []
			var side_dir := Vector3(-sin(az), 0, cos(az))
			var segs := 4 if g.lod == 0 else 2
			for i in segs + 1:
				var s := float(i) / float(segs)
				spine.append(start + dir * len_b * s + Vector3.DOWN * s * s * len_b * 0.18)
				widths.append(len_b * 0.62 * (0.35 + 0.65 * sin(PI * (0.15 + 0.85 * s))))
				sides_d.append(side_dir)
			var ao := 0.55 + 0.45 * t
			g.strip(spine, widths, sides_d, Color(ao, ao, ao), 0.3 + 0.4 * t, 0.7 + 0.3 * t, center, 0.35, g.r(0, TAU), 0.5)
		y += step * g.r(0.8, 1.2) * (1.0 - t * 0.35)
		whorl += 1
	# Crown tip.
	var tip_spine := [Vector3(0, height * 0.94, 0), Vector3(0, height * 1.04, 0)]
	g.strip(tip_spine, [0.35, 0.05], [Vector3.RIGHT, Vector3.RIGHT], Color(1, 1, 1), 0.8, 1.0, center, 0.0)
	g.strip(tip_spine, [0.35, 0.05], [Vector3.BACK, Vector3.BACK], Color(1, 1, 1), 0.8, 1.0, center, 0.0)


static func _palm(g: Geo, style: String) -> void:
	var height := g.r(6.0, 9.0)
	var r0 := g.r(0.17, 0.22)
	var sides := 5 if g.flat or g.lod == 1 else 8
	var lean := Vector3(g.r(-1, 1), 0, g.r(-1, 1)).normalized() * g.r(0.15, 0.4)
	var pts: Array = []
	var segs := 8 if g.lod == 0 else 4
	for i in segs + 1:
		var t := float(i) / float(segs)
		pts.append(Vector3(lean.x * t * t * height, t * height, lean.z * t * t * height))
	g.tube(pts, _taper(pts.size(), r0, r0 * 0.72, 0.25), sides, Color(1, 1, 1), 0.0, 0.6, 0.0, 1.0)
	g.collider = ["cylinder", r0 * 1.1, height * 0.5]
	var crown: Vector3 = pts[pts.size() - 1]
	var fronds := g.rng.randi_range(11, 15) if g.lod == 0 else 8
	for f in fronds:
		var az := TAU * float(f) / float(fronds) + g.r(-0.25, 0.25)
		var up := g.r(0.15, 1.1) if f % 3 != 0 else g.r(1.2, 2.0)
		var dir := Vector3(cos(az), up, sin(az)).normalized()
		var length := g.r(3.4, 4.6)
		var spine: Array = []
		var widths: Array = []
		var side_dirs: Array = []
		var fsegs := 8 if g.lod == 0 else 4
		var side := Vector3(-sin(az), 0, cos(az))
		for i in fsegs + 1:
			var s := float(i) / float(fsegs)
			var p := crown + dir * length * s + Vector3.DOWN * s * s * length * 0.75
			spine.append(p)
			widths.append(1.5 * sin(PI * minf(s * 1.05 + 0.05, 1.0)) + 0.05)
			side_dirs.append(side)
		g.strip(spine, widths, side_dirs, Color(1, 1, 1), 0.55, 1.0, crown, 0.45, g.r(0, TAU), 0.35)
	if g.lod == 0:
		for k in g.rng.randi_range(3, 5):
			var a := g.r(0, TAU)
			g.sphere(crown + Vector3(cos(a) * 0.24, -0.22, sin(a) * 0.24), Vector3.ONE * 0.14, 6, 8, Color(0.5, 0.38, 0.2), 0.6)


static func _dead_tree(g: Geo) -> void:
	var height := g.r(5.0, 8.0)
	var r0 := g.r(0.18, 0.28)
	var sides := 5 if g.flat or g.lod == 1 else 7
	var trunk := _bent_path(g, Vector3.ZERO, Vector3.UP, height, 6, 0.18)
	var col := Color(1, 1, 1)
	g.tube(trunk, _taper(trunk.size(), r0, r0 * 0.2, 0.4), sides, col, 0.0, 0.3, 0.0)
	g.collider = ["cylinder", r0 * 1.1, height * 0.6]
	var n := g.rng.randi_range(6, 9)
	for b in n:
		var t := g.r(0.3, 0.92)
		var start: Vector3 = trunk[int(t * (trunk.size() - 1))]
		var az := TAU * float(b) / float(n) + g.r(-0.5, 0.5)
		var dir := Vector3(cos(az), g.r(0.3, 1.1), sin(az))
		var path := _bent_path(g, start, dir, height * g.r(0.28, 0.45) * (1.15 - t), 4, 0.28)
		g.tube(path, _taper(path.size(), r0 * 0.4 * (1.1 - t), r0 * 0.06), maxi(4, sides - 3), col, 0.25, 0.6, g.r(0, TAU))
		if g.lod == 0:
			for s in 3:
				var sp: Vector3 = path[g.rng.randi_range(1, path.size() - 1)]
				var sd := Vector3(g.r(-1, 1), g.r(0.2, 1.0), g.r(-1, 1))
				var sub := _bent_path(g, sp, sd, height * g.r(0.1, 0.18), 3, 0.35)
				g.tube(sub, _taper(sub.size(), r0 * 0.12, r0 * 0.03), 4, col, 0.5, 0.8, g.r(0, TAU), 1.0, false)


static func _bush(g: Geo, style: String) -> void:
	var clusters: Array = []
	var n := g.rng.randi_range(3, 5)
	var size := g.r(0.7, 1.1)
	for i in n:
		var a := g.r(0, TAU)
		var d := g.r(0.0, 0.45) * size
		clusters.append([Vector3(cos(a) * d, size * g.r(0.45, 0.75), sin(a) * d), size * g.r(0.45, 0.65)])
	_canopy(g, clusters, Vector3(0, size * 0.35, 0), Color(1, 1, 1), 11, size * 0.75, Rect2(0, 0, 1, 1))
	g.collider = ["sphere", size * 0.5, size]


static func _fern(g: Geo) -> void:
	var n := g.rng.randi_range(8, 12)
	var center := Vector3(0, 0.1, 0)
	for f in n:
		var az := TAU * float(f) / float(n) + g.r(-0.3, 0.3)
		var dir := Vector3(cos(az), g.r(0.8, 1.5), sin(az)).normalized()
		var length := g.r(1.0, 1.5)
		var spine: Array = []
		var widths: Array = []
		var sides: Array = []
		for i in 6:
			var s := float(i) / 5.0
			spine.append(Vector3(0, 0.05, 0) + dir * length * s + Vector3.DOWN * s * s * length * 0.7)
			widths.append(0.5 * (1.0 - s * 0.55))
			sides.append(Vector3(-sin(az), 0, cos(az)))
		g.strip(spine, widths, sides, Color(1, 1, 1), 0.2, 1.0, center, 0.3, g.r(0, TAU), 0.3)


# =============================================================================
# Desert, rocks and props
# =============================================================================

static func _cactus(g: Geo) -> void:
	var height := g.r(2.4, 4.2)
	var r0 := g.r(0.2, 0.28)
	var sides := 8 if g.flat else (16 if g.lod == 0 else 8)
	var ribs := func(a: float) -> float: return 1.0 + 0.1 * absf(cos(a * 5.0))
	var col := Color(0.9, 0.9, 0.9)
	var trunk := _bent_path(g, Vector3.ZERO, Vector3.UP, height, 6, 0.02)
	g.tube(trunk, _taper(trunk.size(), r0, r0 * 0.85), sides, col, 0.0, 0.1, 0.0, 1.0, true, ribs)
	g.collider = ["cylinder", r0 * 1.1, height]
	var arms := g.rng.randi_range(1, 3)
	for a in arms:
		var az := g.r(0, TAU)
		var hy := height * g.r(0.35, 0.65)
		var out := Vector3(cos(az), 0, sin(az))
		var pts: Array = [Vector3(0, hy, 0), Vector3(0, hy, 0) + out * r0 * 2.2 + Vector3.UP * 0.05]
		var elbow: Vector3 = pts[1]
		pts.append(elbow + out * 0.12 + Vector3.UP * 0.25)
		var top := elbow + out * 0.15 + Vector3.UP * g.r(0.7, 1.3)
		pts.append(top)
		g.tube(pts, _taper(pts.size(), r0 * 0.62, r0 * 0.55), sides, col, 0.0, 0.1, 0.0, 1.0, true, ribs)


static func _barrel_cactus(g: Geo) -> void:
	var r0 := g.r(0.25, 0.4)
	var ribs := func(dir: Vector3) -> float: return 1.0 + 0.08 * absf(cos(atan2(dir.z, dir.x) * 7.0))
	g.sphere(Vector3(0, r0 * 0.8, 0), Vector3(r0, r0 * 1.1, r0), 8 if g.lod == 0 else 5, 16 if g.lod == 0 else 8, Color(1, 1, 1), 0.0, ribs, 0.0)
	# Flowers on top.
	g.sphere(Vector3(0, r0 * 1.85, 0), Vector3(r0 * 0.3, r0 * 0.12, r0 * 0.3), 4, 8, Color(1.6, 0.55, 0.75), 0.0)
	g.collider = ["sphere", r0, r0 * 2.0]


static func _rock(g: Geo, scale: float, lod: int, offset: Vector3 = Vector3.ZERO) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = g.rng.randi()
	noise.frequency = 1.4
	noise.fractal_octaves = 4
	var stretch := Vector3(g.r(0.8, 1.3), g.r(0.45, 0.8), g.r(0.7, 1.1)) * scale
	var disp := func(dir: Vector3) -> float:
		var n1 := noise.get_noise_3dv(dir * 1.0)
		return 1.0 + n1 * 0.45 + absf(noise.get_noise_3dv(dir * 3.1 + Vector3(5, 1, 2))) * -0.12
	var rings := 3 if g.flat else (10 if lod == 0 else 5)
	var sides := 5 if g.flat else (14 if lod == 0 else 7)
	var start := g.solid.v.size()
	var center := offset + Vector3(0, stretch.y * 0.35, 0)
	g.sphere(center, stretch, rings, sides, Color(1, 1, 1), 0.0, disp, offset.y - stretch.y * 0.1)
	# Chip the stone with random planes: flat faces and sharp edges.
	var s := g.solid
	var cuts := 7 if lod == 0 else 5
	for c in cuts:
		var pn := Vector3(g.r(-1, 1), g.r(-0.3, 1), g.r(-1, 1)).normalized()
		var reach := 0.0
		for i in range(start, s.v.size()):
			reach = maxf(reach, (s.v[i] - center).dot(pn))
		var d := reach * g.r(0.62, 0.85)
		for i in range(start, s.v.size()):
			var rel := s.v[i] - center
			var over := rel.dot(pn) - d
			if over > 0.0:
				s.v[i] = s.v[i] - pn * over
	# Cheap ambient occlusion: darker low vertices and crevices; smooth normals.
	for i in range(start, s.v.size()):
		var p := s.v[i] - offset
		var dirv := (p - Vector3(0, stretch.y * 0.35, 0)) / stretch
		var ao := clampf(0.55 + 0.45 * (dirv.length() - 0.6) + 0.25 * clampf(p.y / maxf(stretch.y, 0.01), 0.0, 1.0), 0.35, 1.0)
		s.c[i] = Color(ao, ao, ao, 0.0)
	_recompute_normals(s, start)
	if g.collider.is_empty():
		g.collider = ["sphere", maxf(stretch.x, stretch.z) * 0.85, stretch.y * 1.3]


static func _recompute_normals(s: Surf, start: int) -> void:
	var acc := PackedVector3Array()
	acc.resize(s.v.size() - start)
	for t in range(0, s.idx.size(), 3):
		var a := s.idx[t]
		if a < start:
			continue
		var b := s.idx[t + 1]
		var c := s.idx[t + 2]
		var fn := (s.v[c] - s.v[a]).cross(s.v[b] - s.v[a])
		acc[a - start] += fn
		acc[b - start] += fn
		acc[c - start] += fn
	# Seam vertices share positions: merge their normals.
	var by_pos := {}
	for i in acc.size():
		var key := (s.v[start + i] * 1000.0).round()
		by_pos[key] = (by_pos.get(key, Vector3.ZERO) as Vector3) + acc[i]
	for i in acc.size():
		var nn: Vector3 = by_pos[(s.v[start + i] * 1000.0).round()]
		if nn.length_squared() > 1e-12:
			s.n[start + i] = nn.normalized()


static func _mushrooms(g: Geo) -> void:
	var n := g.rng.randi_range(2, 5)
	for i in n:
		var a := g.r(0, TAU)
		var d := g.r(0.0, 0.35)
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := g.r(0.2, 0.55)
		var rs := g.r(0.045, 0.09)
		var tilt := Vector3(g.r(-0.15, 0.15), 1, g.r(-0.15, 0.15)).normalized()
		var top := base + tilt * h
		g.tube([base, base + tilt * h * 0.5, top], [rs * 1.2, rs, rs * 0.9], 6, Color(0.95, 0.92, 0.85), 0.0, 0.2, 0.0, 1.0, false)
		var cr := rs * g.r(2.5, 4.0)
		var spots := func(dir: Vector3) -> float: return 1.0
		var start := g.solid.v.size()
		g.sphere(top, Vector3(cr, cr * 0.55, cr), 6, 12, Color(1.6, 0.25, 0.2), 0.2, spots, top.y - cr * 0.05)
		# White spots: bright vertices on the upper cap.
		for k in range(start, g.solid.v.size()):
			var p := g.solid.v[k] - top
			if p.y > cr * 0.1 and (int(abs(p.x * 97.0 + p.z * 131.0)) % 5) == 0:
				g.solid.c[k] = Color(1.9, 1.9, 1.9, 0.2)


static func _crystals(g: Geo) -> void:
	var n := g.rng.randi_range(3, 7)
	for i in n:
		var a := g.r(0, TAU)
		var tilt := g.r(0.0, 0.55) if i > 0 else 0.0
		var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt))
		var h := g.r(0.6, 1.9) * (1.0 if i == 0 else 0.7)
		var r := h * g.r(0.1, 0.16)
		var base := Vector3(cos(a) * r * 1.5, -0.05, sin(a) * r * 1.5)
		var body := base + dir * h * 0.78
		var tip := base + dir * h
		g.tube([base, body], [r, r], 6, Color(1, 1, 1), 0.0, 0.0, 0.0, 1.0, false)
		var s := g.solid
		var ring_start := s.v.size() - 7
		var tip_i := s.add(tip, dir, Color(1.3, 1.3, 1.3, 0.0), Vector2(0.5, 1.0), Vector2(0, 0))
		for k in 6:
			s.tri(ring_start + k, ring_start + k + 1, tip_i)
	g.collider = ["sphere", 0.5, 1.2]


static func _log(g: Geo) -> void:
	var length := g.r(2.0, 3.6)
	var r0 := g.r(0.17, 0.26)
	var dir := Vector3(1, 0, 0)
	var pts := [Vector3(-length * 0.5, r0 * 0.85, 0), Vector3(0, r0 * 0.9, g.r(-0.1, 0.1)), Vector3(length * 0.5, r0 * 0.8, 0)]
	g.tube(pts, [r0, r0 * 0.95, r0 * 0.88], 8 if not g.flat else 5, Color(1, 1, 1), 0.0, 0.0, 0.0, 1.0, true)
	g.collider = ["box", length, r0 * 2.0]


static func _stump(g: Geo) -> void:
	var r0 := g.r(0.22, 0.35)
	var h := g.r(0.3, 0.55)
	g.tube([Vector3.ZERO, Vector3(0, h, 0)], [r0 * 1.35, r0], 9 if not g.flat else 5, Color(1, 1, 1), 0.0, 0.0, 0.0, 1.0, true)
	g.collider = ["cylinder", r0, h]
