@tool
extends RefCounted
## Builds grass clump meshes (one clump = several curved, tapered blades).
##
## Vertex data used by the grass shaders:
##   UV.x  = 0..1 across the blade, UV.y = 0 at the base .. 1 at the tip
##   COLOR = (height factor, per-blade random, clump radial factor, petal flag)

const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]


## params: blades, height, width, segments, curve, spread, flowers (0..1 chance per blade),
## flower_size, wheat (bool), seed, style.
static func build(params: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 1))
	var style := str(params.get("style", "realistic"))
	var blades := int(params.get("blades", 5))
	var height := float(params.get("height", 0.5))
	var width := float(params.get("width", 0.05))
	var segments := int(params.get("segments", 4))
	var curve := float(params.get("curve", 0.35))
	var spread := float(params.get("spread", height * 0.25))
	var flowers := float(params.get("flowers", 0.0))
	var flower_size := float(params.get("flower_size", 0.06))
	var wheat := bool(params.get("wheat", false))
	match style:
		"lowpoly":
			segments = 1
			width *= 2.2
			height *= 0.55
			curve *= 1.6
			blades = maxi(3, blades - 2)
		"toon", "cel":
			segments = mini(segments, 3)
			width *= 1.6
		"stylized":
			width *= 1.3

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()

	for b in blades:
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * spread
		var base := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var facing := rng.randf() * TAU
		var forward := Vector3(cos(facing), 0.0, sin(facing))
		var side := Vector3(-forward.z, 0.0, forward.x)
		var h := height * rng.randf_range(0.65, 1.25)
		var w := width * rng.randf_range(0.75, 1.25)
		var lean := curve * rng.randf_range(0.4, 1.3)
		var r := rng.randf()
		var radial := dist / maxf(spread, 0.0001)
		var start := verts.size()
		var tip := Vector3.ZERO
		if style == "lowpoly":
			# A single triangle (flat-shaded tuft blade).
			var top := base + forward * lean * h * 0.8 + Vector3.UP * h * rng.randf_range(0.7, 1.0)
			var n := side.cross(top - base).normalized()
			verts.append_array([base - side * w * 0.5, base + side * w * 0.5, top])
			normals.append_array([n, n, n])
			uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)])
			colors.append_array([Color(0, r, radial, 0), Color(0, r, radial, 0), Color(1, r, radial, 0)])
			idx.append_array([start, start + 2, start + 1])
			tip = top
		else:
			for s in segments + 1:
				var t := float(s) / float(segments)
				var bend := lean * t * t * h
				var center := base + forward * bend + Vector3.UP * (h * t * (1.0 - lean * 0.15 * t))
				var taper := pow(1.0 - t, 0.75) if s < segments else 0.0
				var hw := w * 0.5 * maxf(taper, 0.0)
				if wheat and t > 0.7:
					hw = w * 0.5 * 0.35
				var tangent := (forward * (2.0 * lean * t * h) + Vector3.UP * h).normalized()
				var n := side.cross(tangent).normalized()
				verts.append(center - side * hw)
				verts.append(center + side * hw)
				normals.append(n)
				normals.append(n)
				uvs.append(Vector2(0.0, t))
				uvs.append(Vector2(1.0, t))
				colors.append(Color(t, r, radial, 0.0))
				colors.append(Color(t, r, radial, 0.0))
				tip = center
			for s in segments:
				var a := start + s * 2
				idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		# Flower head / wheat ear on top of some blades.
		if wheat:
			_add_head(verts, normals, uvs, colors, idx, tip, flower_size * 0.6, flower_size * 2.6, r, 1.0)
		elif flowers > 0.0 and rng.randf() < flowers:
			var petals := 5 + rng.randi_range(0, 3)
			var tilt := Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35)).normalized()
			_add_flower(verts, normals, uvs, colors, idx, tip + Vector3.UP * flower_size * 0.2, tilt, flower_size * rng.randf_range(0.8, 1.25), petals, r, style == "lowpoly")

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Flat flower: a fan of rounded petals around a center disc, facing `up`.
## COLOR.a = 1 marks petal vertices, COLOR.b = 1 marks the flower center.
static func _add_flower(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		colors: PackedColorArray, idx: PackedInt32Array, center: Vector3, up: Vector3, radius: float, petals: int, r: float, low: bool) -> void:
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = up.cross(Vector3.RIGHT).normalized()
	var fwd := side.cross(up).normalized()
	var start := verts.size()
	verts.append(center + up * radius * 0.05)
	normals.append(up)
	uvs.append(Vector2(0.5, 0.5))
	colors.append(Color(1.0, r, 1.0, 1.0))
	var segs := 2 if low else 4
	for p in petals:
		var a0 := TAU * float(p) / float(petals)
		var a1 := TAU * float(p + 1) / float(petals)
		var ring_start := verts.size()
		for s in segs + 1:
			var a := lerpf(a0, a1, float(s) / float(segs))
			# Rounded petal outline: radius bulges in the middle of each petal.
			var k := sin(PI * float(s) / float(segs))
			var rr := radius * (0.35 + 0.65 * pow(k, 0.6))
			var dir := side * cos(a) + fwd * sin(a)
			verts.append(center + dir * rr - up * rr * 0.12)
			normals.append(up)
			uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
			colors.append(Color(1.0, r, 0.0, 1.0))
		for s in segs:
			idx.append_array([start, ring_start + s, ring_start + s + 1])


## Two crossed quads (wheat ear / reed head). COLOR.a = 1 marks "head" vertices.
static func _add_head(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		colors: PackedColorArray, idx: PackedInt32Array, center: Vector3, size: float, tall: float, r: float, flag: float) -> void:
	for k in 2:
		var ang := PI * 0.5 * k + r
		var side := Vector3(cos(ang), 0.0, sin(ang)) * size
		var up := Vector3.UP * tall
		var s := verts.size()
		var n := side.cross(Vector3.UP).normalized()
		verts.append_array([center - side - up * 0.3, center + side - up * 0.3, center + side + up, center - side + up])
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		for _i in 4:
			colors.append(Color(1.0, r, 0.0, flag))
		idx.append_array([s, s + 3, s + 2, s, s + 2, s + 1])
