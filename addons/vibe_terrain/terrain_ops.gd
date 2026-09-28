@tool
extends RefCounted
## Editing operations on a VibeTerrainData, in texel (vertex) coordinates.
## Used by the editor brushes and by the terminal commands.

const Generator = preload("res://addons/vibe_terrain/terrain_generator.gd")

const SCULPT_OPS := ["raise", "lower", "smooth", "flatten", "set", "noise", "terrace"]


static func brush_rect(res: int, center: Vector2, radius: float) -> Rect2i:
	var x0 := maxi(0, int(floor(center.x - radius)))
	var z0 := maxi(0, int(floor(center.y - radius)))
	var x1 := mini(res - 1, int(ceil(center.x + radius)))
	var z1 := mini(res - 1, int(ceil(center.y + radius)))
	return Rect2i(x0, z0, maxi(0, x1 - x0 + 1), maxi(0, z1 - z0 + 1))


## Smooth falloff: 1 inside `hardness * radius`, fading to 0 at `radius`.
static func falloff(dist: float, radius: float, hardness: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var t := dist / radius
	var inner := clampf(hardness, 0.0, 0.98)
	if t <= inner:
		return 1.0
	var k := (t - inner) / (1.0 - inner)
	return 1.0 - k * k * (3.0 - 2.0 * k)


## Sculpts heights. `strength` is meters (raise/lower/noise) or a 0..1 blend factor.
## opts: hardness, height (flatten/set target), step (terrace), seed, noise_scale.
static func sculpt(data, op: String, center: Vector2, radius: float, strength: float, opts: Dictionary = {}) -> Rect2i:
	var res: int = data.resolution
	var rect := brush_rect(res, center, radius)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return rect
	var h: PackedFloat32Array = data.heights
	var hardness := float(opts.get("hardness", 0.35))
	var target := float(opts.get("height", data.sample(center.x, center.y)))
	var src := PackedFloat32Array()
	if op == "smooth":
		src = h.duplicate()
	var noise: FastNoiseLite = null
	if op == "noise":
		noise = FastNoiseLite.new()
		noise.seed = int(opts.get("seed", 7))
		noise.frequency = float(opts.get("noise_scale", 0.08))
		noise.fractal_octaves = 4
	var step := maxf(0.1, float(opts.get("step", 4.0)))
	var blend := clampf(strength, 0.0, 1.0)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var f := falloff(Vector2(x, z).distance_to(center), radius, hardness)
			if f <= 0.0:
				continue
			var i := z * res + x
			match op:
				"raise":
					h[i] += strength * f
				"lower":
					h[i] -= strength * f
				"smooth":
					var s := 0.0
					var n := 0
					for dz in range(-2, 3):
						var zz := clampi(z + dz, 0, res - 1)
						for dx in range(-2, 3):
							var xx := clampi(x + dx, 0, res - 1)
							s += src[zz * res + xx]
							n += 1
					h[i] = lerpf(h[i], s / float(n), clampf(blend * f, 0.0, 1.0))
				"flatten":
					h[i] = lerpf(h[i], target, clampf(blend * f, 0.0, 1.0))
				"set":
					h[i] = lerpf(h[i], target, f)
				"noise":
					h[i] += noise.get_noise_2d(x, z) * strength * f
				"terrace":
					var stepped := roundf(h[i] / step) * step
					h[i] = lerpf(h[i], stepped, clampf(blend * f, 0.0, 1.0))
	data.heights = h
	return rect


## Paints a layer (0..3) into the splatmap. strength 0..1.
static func paint(data, layer: int, center: Vector2, radius: float, strength: float, hardness: float = 0.4) -> Rect2i:
	var res: int = data.resolution
	var rect := brush_rect(res, center, radius)
	var s: PackedByteArray = data.splat
	layer = clampi(layer, 0, 3)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var f := falloff(Vector2(x, z).distance_to(center), radius, hardness) * clampf(strength, 0.0, 1.0)
			if f <= 0.0:
				continue
			var i := (z * res + x) * 4
			var w := [s[i] / 255.0, s[i + 1] / 255.0, s[i + 2] / 255.0, s[i + 3] / 255.0]
			var new_w := minf(1.0, float(w[layer]) + f)
			var others: float = 1.0 - float(w[layer])
			var remaining := 1.0 - new_w
			var total := 0
			for l in 4:
				var v: float
				if l == layer:
					v = new_w
				elif others > 0.0001:
					v = w[l] / others * remaining
				else:
					v = 0.0
				var b := int(round(v * 255.0))
				s[i + l] = b
				total += b
			s[i + layer] = clampi(s[i + layer] + (255 - total), 0, 255)
	data.splat = s
	return rect


# --- Erosion -------------------------------------------------------------------------

## Thermal erosion: material slides down slopes steeper than `talus_deg`.
static func thermal_erosion(data, iterations: int, talus_deg: float = 34.0, strength: float = 0.5) -> void:
	var res: int = data.resolution
	var h: PackedFloat32Array = data.heights
	var talus := tan(deg_to_rad(talus_deg)) * float(data.cell_size)
	var delta := PackedFloat32Array()
	delta.resize(res * res)
	for _it in iterations:
		delta.fill(0.0)
		for z in range(1, res - 1):
			var row := z * res
			for x in range(1, res - 1):
				var i := row + x
				var hi := h[i]
				var j := i - 1
				var dmax := hi - h[i - 1]
				var d := hi - h[i + 1]
				if d > dmax:
					dmax = d
					j = i + 1
				d = hi - h[i - res]
				if d > dmax:
					dmax = d
					j = i - res
				d = hi - h[i + res]
				if d > dmax:
					dmax = d
					j = i + res
				if dmax > talus:
					var amount := (dmax - talus) * 0.5 * strength
					delta[i] -= amount
					delta[j] += amount
		for i in h.size():
			h[i] += delta[i]
	data.heights = h


## Droplet based hydraulic erosion (after Hans Beyer / Sebastian Lague).
static func hydraulic_erosion(data, droplets: int, seed_value: int = 1, strength: float = 1.0) -> void:
	var res: int = data.resolution
	var h: PackedFloat32Array = data.heights
	var r: Vector2 = data.height_range()
	var scale := maxf(r.y - r.x, 1.0)
	# Work in normalized height units so parameters are map independent.
	var hn := PackedFloat32Array()
	hn.resize(h.size())
	for i in h.size():
		hn[i] = (h[i] - r.x) / scale
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var inertia := 0.05
	var capacity_factor := 4.0
	var min_capacity := 0.01
	var deposit_speed := 0.3
	var erode_speed := 0.3 * strength
	var evaporate := 0.015
	var gravity := 4.0
	var max_steps := 48
	# Erosion brush (radius 2).
	var offsets: Array = []
	var weights: Array = []
	var wsum := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var dist := sqrt(float(dx * dx + dz * dz))
			if dist <= 2.0:
				offsets.append(Vector2i(dx, dz))
				var w := 2.0 - dist
				weights.append(w)
				wsum += w
	for k in weights.size():
		weights[k] = weights[k] / wsum
	var lim := float(res - 3)
	for _d in droplets:
		var px := rng.randf_range(2.0, lim)
		var pz := rng.randf_range(2.0, lim)
		var dir_x := 0.0
		var dir_z := 0.0
		var speed := 1.0
		var water := 1.0
		var sediment := 0.0
		for _s in max_steps:
			var nx := int(px)
			var nz := int(pz)
			var ox := px - nx
			var oz := pz - nz
			var i := nz * res + nx
			var h00 := hn[i]
			var h10 := hn[i + 1]
			var h01 := hn[i + res]
			var h11 := hn[i + res + 1]
			var gx := (h10 - h00) * (1.0 - oz) + (h11 - h01) * oz
			var gz := (h01 - h00) * (1.0 - ox) + (h11 - h10) * ox
			var height := h00 * (1.0 - ox) * (1.0 - oz) + h10 * ox * (1.0 - oz) + h01 * (1.0 - ox) * oz + h11 * ox * oz
			dir_x = dir_x * inertia - gx * (1.0 - inertia)
			dir_z = dir_z * inertia - gz * (1.0 - inertia)
			var l := sqrt(dir_x * dir_x + dir_z * dir_z)
			if l < 0.000001:
				var a := rng.randf() * TAU
				dir_x = cos(a)
				dir_z = sin(a)
			else:
				dir_x /= l
				dir_z /= l
			px += dir_x
			pz += dir_z
			if px < 2.0 or pz < 2.0 or px >= lim or pz >= lim:
				break
			var mx := int(px)
			var mz := int(pz)
			var qx := px - mx
			var qz := pz - mz
			var j := mz * res + mx
			var new_height := hn[j] * (1.0 - qx) * (1.0 - qz) + hn[j + 1] * qx * (1.0 - qz) + hn[j + res] * (1.0 - qx) * qz + hn[j + res + 1] * qx * qz
			var dh := new_height - height
			var capacity := maxf(-dh * speed * water * capacity_factor, min_capacity)
			if sediment > capacity or dh > 0.0:
				var amount := minf(dh, sediment) if dh > 0.0 else (sediment - capacity) * deposit_speed
				sediment -= amount
				hn[i] += amount * (1.0 - ox) * (1.0 - oz)
				hn[i + 1] += amount * ox * (1.0 - oz)
				hn[i + res] += amount * (1.0 - ox) * oz
				hn[i + res + 1] += amount * ox * oz
			else:
				var amount := minf((capacity - sediment) * erode_speed, -dh)
				for k in offsets.size():
					var o: Vector2i = offsets[k]
					var idx := (nz + o.y) * res + (nx + o.x)
					var take := minf(amount * float(weights[k]), maxf(hn[idx], 0.0) + 1.0)
					hn[idx] -= take
					sediment += take
			speed = sqrt(maxf(speed * speed - dh * gravity, 0.0))
			water *= (1.0 - evaporate)
	for i in h.size():
		h[i] = hn[i] * scale + r.x
	data.heights = h


# --- Stamps / features ------------------------------------------------------------------

const STAMP_SHAPES := ["mountain", "hill", "crater", "volcano", "lake", "plateau", "pit"]
const STAMP_ALIASES := {"montanha": "mountain", "morro": "hill", "colina": "hill", "cratera": "crater", "vulcao": "volcano",
	"lago": "lake", "lagoa": "lake", "pond": "lake", "platô": "plateau", "plato": "plateau", "mesa": "plateau", "buraco": "pit", "hole": "pit"}


## Adds a landform. Returns {"rect": Rect2i, "level": water level for lakes}.
static func stamp(data, shape: String, center: Vector2, radius: float, height_m: float, seed_value: int = 1) -> Dictionary:
	shape = STAMP_ALIASES.get(shape, shape)
	var res: int = data.resolution
	var reach := radius * (1.6 if shape in ["crater", "lake"] else 1.05)
	var rect := brush_rect(res, center, reach)
	var h: PackedFloat32Array = data.heights
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0 / maxf(radius * 0.5, 1.0)
	noise.fractal_octaves = 4
	var level := 0.0
	if shape == "lake":
		# Water level = lowest point of the rim, so the lake never overflows.
		level = INF
		for k in 48:
			var a := TAU * float(k) / 48.0
			var p := center + Vector2(cos(a), sin(a)) * radius * 1.05
			level = minf(level, data.sample(p.x, p.y))
		level -= 0.4
	var plateau_base: float = data.sample(center.x, center.y)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var d := Vector2(x, z).distance_to(center)
			var t := d / radius
			var i := z * res + x
			match shape:
				"mountain":
					if t < 1.0:
						var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
						h[i] += height_m * pow(1.0 - smoothstep(0.0, 1.0, t), 1.8) * lerpf(0.75, 1.2, n)
				"hill":
					if t < 1.0:
						h[i] += height_m * (cos(PI * t) * 0.5 + 0.5)
				"crater":
					h[i] += Generator._crater_profile(t, height_m, height_m * 0.5)
				"volcano":
					if t < 1.0:
						var cone := pow(1.0 - smoothstep(0.0, 1.0, t), 1.6) * height_m
						cone -= height_m * 0.25 * (1.0 - smoothstep(0.03, 0.16, t))
						h[i] = maxf(h[i], h[i] * 0.3 + cone)
				"lake":
					if t < 1.0:
						var bottom := level - height_m * (1.0 - t * t)
						h[i] = minf(h[i], bottom)
					elif t < 1.6:
						var shore := level + 0.3 + (t - 1.0) * radius * 0.25
						h[i] = minf(h[i], lerpf(shore, h[i], smoothstep(1.0, 1.6, t)))
				"plateau":
					var top := plateau_base + height_m
					var w := 1.0 - smoothstep(0.82, 1.0, t)
					h[i] = maxf(h[i], lerpf(h[i], top, w))
				"pit":
					if t < 1.0:
						h[i] -= height_m * (1.0 - t * t)
	data.heights = h
	return {"rect": rect, "level": level}


## Flattens a circular area to `height` (or the average height at the center).
static func flatten_area(data, center: Vector2, radius: float, height: Variant = null, hardness: float = 0.6) -> Dictionary:
	var target: float
	if height == null:
		var s := 0.0
		var n := 0
		for k in 16:
			var a := TAU * float(k) / 16.0
			var p := center + Vector2(cos(a), sin(a)) * radius * 0.5
			s += data.sample(p.x, p.y)
			n += 1
		target = (s + data.sample(center.x, center.y)) / float(n + 1)
	else:
		target = float(height)
	var rect := sculpt(data, "set", center, radius * 1.35, 1.0, {"height": target, "hardness": hardness / 1.35})
	return {"rect": rect, "height": target}


# --- Paths (rivers / roads) ---------------------------------------------------------------

## Generates a natural path in texel coordinates.
## river: flows downhill from a high point until water/edge/basin.
## road: crosses the map with gentle curves.
static func auto_path(data, mode: String, seed_value: int, water_level: float = -INF) -> Array:
	var res: int = data.resolution
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts: Array = []
	var margin := res * 0.08
	if mode == "river":
		# Start: a high point (top 30%), away from the borders, picked at random.
		var r: Vector2 = data.height_range()
		var best := Vector2(res * 0.5, res * 0.5)
		var best_h := -INF
		for _k in 400:
			var c := Vector2(rng.randf_range(margin * 2.0, res - margin * 2.0), rng.randf_range(margin * 2.0, res - margin * 2.0))
			var hh: float = data.sample(c.x, c.y) + rng.randf() * (r.y - r.x) * 0.35
			if hh > best_h:
				best_h = hh
				best = c
		var p := best
		var dir := Vector2.ZERO
		var noise := FastNoiseLite.new()
		noise.seed = seed_value
		noise.frequency = 0.03
		var stuck := 0
		var lowest := INF
		pts.append(p)
		for step in res * 4:
			var g := Vector2(data.sample(p.x + 1.5, p.y) - data.sample(p.x - 1.5, p.y), data.sample(p.x, p.y + 1.5) - data.sample(p.x, p.y - 1.5))
			var down := -g.normalized() if g.length() > 0.0001 else Vector2.RIGHT.rotated(rng.randf() * TAU)
			var meander := Vector2.RIGHT.rotated(noise.get_noise_1d(step * 1.0) * PI) * 0.35
			dir = (dir * 0.82 + down * 0.18 + meander * 0.08).normalized() if dir != Vector2.ZERO else down
			p += dir
			if p.x < 1.0 or p.y < 1.0 or p.x > res - 2.0 or p.y > res - 2.0:
				break
			var hp: float = data.sample(p.x, p.y)
			pts.append(p)
			if hp < water_level - 0.6:
				break
			if hp < lowest - 0.02:
				lowest = hp
				stuck = 0
			else:
				stuck += 1
				if stuck > res * 0.6:
					break
	else:
		var horizontal := rng.randf() < 0.5
		var a := Vector2(0.0, rng.randf_range(res * 0.3, res * 0.7))
		var b := Vector2(res - 1.0, rng.randf_range(res * 0.3, res * 0.7))
		if not horizontal:
			a = Vector2(a.y, a.x)
			b = Vector2(b.y, b.x)
		var noise := FastNoiseLite.new()
		noise.seed = seed_value
		noise.frequency = 2.0
		var n := 64
		var normal := (b - a).orthogonal().normalized()
		for k in n + 1:
			var t := float(k) / float(n)
			pts.append(a.lerp(b, t) + normal * noise.get_noise_1d(t) * res * 0.12)
	return pts


## Carves a river channel or a road along `points` (texel coords).
## Returns {"rect", "points", "levels"} (levels = river water surface heights).
static func carve_path(data, points: Array, width: float, depth: float, mode: String, water_min: float = -INF) -> Dictionary:
	var res: int = data.resolution
	if points.size() < 2:
		return {"rect": Rect2i(), "points": [], "levels": []}
	var pts := _resample(points, 0.75)
	var n := pts.size()
	var ground := PackedFloat32Array()
	ground.resize(n)
	for k in n:
		ground[k] = data.sample(pts[k].x, pts[k].y)
	var win := maxi(2, int(width * 1.5))
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for k in n:
		var s := 0.0
		var c := 0
		for j in range(maxi(0, k - win), mini(n, k + win + 1)):
			s += ground[j]
			c += 1
		smooth[k] = s / float(c)
	var levels := PackedFloat32Array()
	levels.resize(n)
	if mode == "river":
		var level := smooth[0] - depth * 0.3
		for k in n:
			level = minf(level, smooth[k] - depth * 0.3)
			levels[k] = maxf(level, water_min)
	else:
		levels = smooth
	var half := width * 0.5
	var bank := maxf(width * 0.8, 2.0) + (depth * 1.5 if mode == "river" else 1.0)
	var reach := half + bank
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in pts:
		minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
		maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
	var x0 := maxi(0, int(minp.x - reach - 1))
	var z0 := maxi(0, int(minp.y - reach - 1))
	var x1 := mini(res - 1, int(maxp.x + reach + 1))
	var z1 := mini(res - 1, int(maxp.y + reach + 1))
	var w := x1 - x0 + 1
	var hgt := z1 - z0 + 1
	if w <= 0 or hgt <= 0:
		return {"rect": Rect2i(), "points": [], "levels": []}
	var best_d := PackedFloat32Array()
	best_d.resize(w * hgt)
	best_d.fill(INF)
	var best_k := PackedInt32Array()
	best_k.resize(w * hgt)
	var r := int(ceil(reach))
	for k in n:
		var p: Vector2 = pts[k]
		var cx := int(p.x)
		var cz := int(p.y)
		for z in range(maxi(z0, cz - r), mini(z1, cz + r) + 1):
			for x in range(maxi(x0, cx - r), mini(x1, cx + r) + 1):
				var d := Vector2(x, z).distance_to(p)
				var li := (z - z0) * w + (x - x0)
				if d < best_d[li]:
					best_d[li] = d
					best_k[li] = k
	var h: PackedFloat32Array = data.heights
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var li := (z - z0) * w + (x - x0)
			var d := best_d[li]
			if d >= reach:
				continue
			var i := z * res + x
			var lvl := levels[best_k[li]]
			if mode == "river":
				var bottom := lvl - depth
				if d < half:
					var t := d / half
					h[i] = minf(h[i], bottom + (lvl + 0.15 - bottom) * t * t)
				else:
					var t := (d - half) / bank
					var edge := lvl + 0.25 + t * bank * 0.35
					h[i] = minf(h[i], lerpf(edge, h[i], smoothstep(0.0, 1.0, t)))
			else:
				var wgt := 1.0 - smoothstep(half, reach, d)
				h[i] = lerpf(h[i], lvl, wgt)
	data.heights = h
	# Decimated path for the river water surface.
	var out_pts: Array = []
	var out_lv: Array = []
	var stride := maxi(1, int(2.0 / 0.75))
	for k in range(0, n, stride):
		out_pts.append(pts[k])
		out_lv.append(levels[k])
	if (n - 1) % stride != 0:
		out_pts.append(pts[n - 1])
		out_lv.append(levels[n - 1])
	return {"rect": Rect2i(x0, z0, w, hgt), "points": out_pts, "levels": out_lv}


static func _resample(points: Array, spacing: float) -> Array:
	var out: Array = [points[0]]
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var steps := maxi(1, int(ceil(a.distance_to(b) / spacing)))
		for s in range(1, steps + 1):
			out.append(a.lerp(b, float(s) / float(steps)))
	return out


# --- Texturing ----------------------------------------------------------------------------

const DEFAULT_RULES := {
	"base_layer": 0,
	"beach_layer": 1, "beach_band": 1.6,
	"cliff_layer": 2, "cliff_slope": 36.0,
	"steep_layer": 1, "steep_slope": 24.0,
	"peak_layer": 3, "peak_height": 0.8, "peak_max_slope": 55.0, "peak_concave": false,
	"patch_layer": -1, "patch_amount": 0.3,
	"seed": 3,
}


## Paints the splatmap from height/slope rules (see DEFAULT_RULES).
static func auto_paint(data, rules: Dictionary, water_level: float = -INF) -> void:
	var r := DEFAULT_RULES.duplicate()
	r.merge(rules, true)
	var res: int = data.resolution
	var h: PackedFloat32Array = data.heights
	var s: PackedByteArray = data.splat
	var range_h: Vector2 = data.height_range()
	var span := maxf(range_h.y - range_h.x, 0.001)
	var land_lo := maxf(range_h.x, water_level) if water_level > -INF else range_h.x
	var peak_h := land_lo + (range_h.y - land_lo) * float(r.peak_height)
	var noise := FastNoiseLite.new()
	noise.seed = int(r.seed)
	noise.frequency = 0.045 / maxf(float(data.cell_size), 0.1)
	noise.fractal_octaves = 3
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = int(r.seed) + 1
	patch_noise.frequency = 0.02 / maxf(float(data.cell_size), 0.1)
	var concavity := PackedFloat32Array()
	if r.peak_concave:
		concavity = _concavity(h, res, maxi(3, int(6.0 / float(data.cell_size))))
	var base := int(r.base_layer)
	var cell: float = data.cell_size
	for z in res:
		for x in res:
			var i := z * res + x
			var hi := h[i]
			var hl := h[i - 1] if x > 0 else hi
			var hr := h[i + 1] if x < res - 1 else hi
			var hd := h[i - res] if z > 0 else hi
			var hu := h[i + res] if z < res - 1 else hi
			var ny := 2.0 * cell / Vector3(hl - hr, 2.0 * cell, hd - hu).length()
			var slope := rad_to_deg(acos(clampf(ny, -1.0, 1.0)))
			var nv := noise.get_noise_2d(x, z)
			var w := [0.0, 0.0, 0.0, 0.0]
			w[base] = 1.0
			if int(r.patch_layer) >= 0:
				var t := smoothstep(1.0 - float(r.patch_amount) - 0.08, 1.0 - float(r.patch_amount) + 0.08, patch_noise.get_noise_2d(x, z) * 0.5 + 0.5)
				_blend(w, int(r.patch_layer), t)
			if int(r.steep_layer) >= 0:
				_blend(w, int(r.steep_layer), smoothstep(float(r.steep_slope) - 5.0, float(r.steep_slope) + 5.0, slope + nv * 6.0) * 0.85)
			if int(r.beach_layer) >= 0 and water_level > -INF:
				var band := float(r.beach_band)
				_blend(w, int(r.beach_layer), 1.0 - smoothstep(water_level + band * 0.55, water_level + band, hi + nv * band * 0.35))
			if int(r.peak_layer) >= 0:
				var tp := smoothstep(peak_h - span * 0.04, peak_h + span * 0.04, hi + nv * span * 0.035)
				tp *= 1.0 - smoothstep(float(r.peak_max_slope) - 6.0, float(r.peak_max_slope) + 6.0, slope)
				if r.peak_concave:
					tp *= smoothstep(0.15, 0.8, concavity[i])
				_blend(w, int(r.peak_layer), tp)
			if int(r.cliff_layer) >= 0:
				_blend(w, int(r.cliff_layer), smoothstep(float(r.cliff_slope) - 6.0, float(r.cliff_slope) + 6.0, slope + nv * 8.0))
			var j := i * 4
			var total := 0
			for l in 4:
				var b := int(round(clampf(w[l], 0.0, 1.0) * 255.0))
				s[j + l] = b
				total += b
			s[j + base] = clampi(s[j + base] + 255 - total, 0, 255)
	data.splat = s


static func _blend(w: Array, layer: int, t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0 or layer < 0 or layer > 3:
		return
	for l in 4:
		w[l] = w[l] * (1.0 - t)
	w[layer] += t


## Height below the local average (positive inside bowls/calderas).
static func _concavity(h: PackedFloat32Array, res: int, radius: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(h.size())
	var out := PackedFloat32Array()
	out.resize(h.size())
	for z in res:
		var acc := 0.0
		var row := z * res
		for x in range(-radius, res):
			var add_x := x + radius
			if add_x < res:
				acc += h[row + add_x]
			var rem_x := x - radius - 1
			if rem_x >= 0:
				acc -= h[row + rem_x]
			if x >= 0:
				var count := mini(x + radius, res - 1) - maxi(x - radius, 0) + 1
				tmp[row + x] = acc / float(count)
	for x in res:
		var acc := 0.0
		for z in range(-radius, res):
			var add_z := z + radius
			if add_z < res:
				acc += tmp[add_z * res + x]
			var rem_z := z - radius - 1
			if rem_z >= 0:
				acc -= tmp[rem_z * res + x]
			if z >= 0:
				var count := mini(z + radius, res - 1) - maxi(z - radius, 0) + 1
				out[z * res + x] = acc / float(count) - h[z * res + x]
	return out
