@tool
extends RefCounted
## Procedural terrain presets (FastNoiseLite based).
##
## Every preset writes heights in meters relative to the terrain origin, with
## "sea level" at 0 for the presets that include water (island, archipelago,
## volcano). Parameters:
##   preset, seed, height (peak height in m, auto by default), scale (feature
##   size multiplier), roughness (0..1 detail), mode (replace/add/max/min/blend),
##   strength (for add/blend).

const PRESETS := {
	"flat": {"height": 0.6, "description": "Plano / flat ground"},
	"plains": {"height": 6.0, "description": "Planície levemente ondulada / gentle plains"},
	"hills": {"height": 22.0, "description": "Colinas suaves / rolling hills"},
	"mountains": {"height": 80.0, "description": "Montanhas com cristas / ridged mountains"},
	"island": {"height": 32.0, "description": "Ilha cercada de mar / island surrounded by sea"},
	"archipelago": {"height": 20.0, "description": "Várias ilhas / several islands"},
	"dunes": {"height": 14.0, "description": "Dunas de deserto / desert dunes"},
	"canyon": {"height": 42.0, "description": "Cânion com platôs em degraus / terraced canyon mesas"},
	"crater": {"height": 26.0, "description": "Cratera de impacto + crateras menores / impact crater field"},
	"volcano": {"height": 85.0, "description": "Vulcão em ilha com caldeira / volcanic island with caldera"},
	"valley": {"height": 60.0, "description": "Vale entre duas serras / valley between two ridges"},
}

const ALIASES := {
	"plano": "flat", "plana": "flat", "planicie": "plains", "campo": "plains", "campos": "plains", "pradaria": "plains",
	"colina": "hills", "colinas": "hills", "morros": "hills", "montanha": "mountains", "montanhas": "mountains",
	"serra": "mountains", "ilha": "island", "arquipelago": "archipelago", "ilhas": "archipelago",
	"deserto": "dunes", "dunas": "dunes", "duna": "dunes", "desert": "dunes", "canion": "canyon", "mesa": "canyon",
	"cratera": "crater", "vulcao": "volcano", "vale": "valley", "mountain": "mountains", "hill": "hills",
}


static func resolve(preset_name: String) -> String:
	var n := preset_name.to_lower().strip_edges()
	for k in {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}.keys():
		n = n.replace(k, {"á": "a", "ã": "a", "â": "a", "é": "e", "ê": "e", "í": "i", "ó": "o", "õ": "o", "ô": "o", "ú": "u", "ç": "c"}[k])
	if PRESETS.has(n):
		return n
	return ALIASES.get(n, "")


static func default_height(preset: String, world_size: float) -> float:
	var base: float = PRESETS.get(preset, {"height": 20.0}).height
	return base * clampf(pow(world_size / 256.0, 0.6), 0.5, 2.5)


static func _noise(seed_value: int, wavelength: float, octaves: int, gain: float, fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / maxf(wavelength, 0.001)
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = 2.0
	return n


## Generates heights into `data` (a VibeTerrainData). Returns a summary.
static func generate(data, params: Dictionary) -> Dictionary:
	var preset := resolve(str(params.get("preset", "hills")))
	if preset == "":
		preset = "hills"
	var seed_value := int(params.get("seed", 1))
	var world_size: float = data.get_size()
	var height := float(params.get("height", -1.0))
	if height <= 0.0:
		height = default_height(preset, world_size)
	height *= float(params.get("height_multiplier", 1.0))
	var feature := maxf(0.05, float(params.get("scale", 1.0)))
	var rough := clampf(float(params.get("roughness", 0.5)), 0.0, 1.0)
	var gain := lerpf(0.35, 0.62, rough)
	var octaves := int(lerpf(3.0, 7.0, rough))

	var res: int = data.resolution
	var cell: float = data.cell_size
	var half := world_size * 0.5
	var out := PackedFloat32Array()
	out.resize(res * res)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	match preset:
		"flat":
			var n := _noise(seed_value, world_size * 0.3, 3, 0.5)
			for z in res:
				for x in res:
					out[z * res + x] = n.get_noise_2d(x * cell, z * cell) * height
		"plains":
			var n := _noise(seed_value, world_size * 0.45 * feature, octaves, gain)
			for z in res:
				for x in res:
					out[z * res + x] = (n.get_noise_2d(x * cell, z * cell) * 0.5 + 0.5) * height
		"hills":
			var n := _noise(seed_value, world_size * 0.28 * feature, octaves, gain)
			for z in res:
				for x in res:
					var v := clampf(n.get_noise_2d(x * cell, z * cell) * 0.6 + 0.5, 0.0, 1.0)
					out[z * res + x] = pow(v, 1.3) * height
		"mountains":
			var ridge := _noise(seed_value, world_size * 0.4 * feature, octaves, gain, FastNoiseLite.FRACTAL_RIDGED)
			ridge.domain_warp_enabled = true
			ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
			ridge.domain_warp_amplitude = world_size * 0.06
			ridge.domain_warp_frequency = 1.0 / (world_size * 0.5)
			var base := _noise(seed_value + 17, world_size * 0.7 * feature, 3, 0.5)
			for z in res:
				for x in res:
					var r := clampf(ridge.get_noise_2d(x * cell, z * cell) * 0.5 + 0.5, 0.0, 1.0)
					var b := base.get_noise_2d(x * cell, z * cell) * 0.5 + 0.5
					out[z * res + x] = pow(r, 1.7) * height * lerpf(0.45, 1.15, b)
		"island":
			var n := _noise(seed_value, world_size * 0.3 * feature, octaves, gain)
			var warp := _noise(seed_value + 5, world_size * 0.5, 3, 0.5)
			var ridge := _noise(seed_value + 9, world_size * 0.35 * feature, 5, 0.5, FastNoiseLite.FRACTAL_RIDGED)
			var depth := height * 0.35 + 2.0
			for z in res:
				for x in res:
					var px := x * cell - half
					var pz := z * cell - half
					var r := Vector2(px, pz).length() / half
					var rw := r + warp.get_noise_2d(px, pz) * 0.22
					var mask := 1.0 - smoothstep(0.3, 0.92, rw)
					var b := n.get_noise_2d(px, pz) * 0.5 + 0.5
					var m := pow(clampf(ridge.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0), 2.0)
					var land := mask * (0.22 + 0.55 * b + 0.45 * m * mask)
					out[z * res + x] = land * height - (1.0 - mask) * depth - 0.8
		"archipelago":
			var cells := FastNoiseLite.new()
			cells.seed = seed_value
			cells.noise_type = FastNoiseLite.TYPE_CELLULAR
			cells.frequency = 1.0 / (world_size * 0.28 * feature)
			cells.fractal_type = FastNoiseLite.FRACTAL_NONE
			cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
			cells.cellular_jitter = 0.9
			var n := _noise(seed_value + 3, world_size * 0.12 * feature, octaves, gain)
			var raw := PackedFloat32Array()
			raw.resize(res * res)
			var lo := INF
			var hi := -INF
			for z in res:
				for x in res:
					var v := cells.get_noise_2d(x * cell, z * cell)
					raw[z * res + x] = v
					lo = minf(lo, v)
					hi = maxf(hi, v)
			var span := maxf(hi - lo, 0.0001)
			var depth := height * 0.4 + 2.0
			for z in res:
				for x in res:
					var px := x * cell - half
					var pz := z * cell - half
					var c := (raw[z * res + x] - lo) / span
					var d := n.get_noise_2d(px, pz)
					var mask := 1.0 - smoothstep(0.18, 0.5, c + d * 0.18)
					var edge := 1.0 - smoothstep(0.78, 0.98, Vector2(px, pz).length() / half)
					mask *= edge
					out[z * res + x] = mask * height * (0.35 + 0.65 * (d * 0.5 + 0.5)) - (1.0 - mask) * depth - 0.8
		"dunes":
			var angle := rng.randf_range(0.0, TAU)
			var wavelength := world_size * 0.11 * feature
			var warp := _noise(seed_value + 1, world_size * 0.35, 3, 0.5)
			var amp := _noise(seed_value + 2, world_size * 0.5, 2, 0.5)
			var base := _noise(seed_value + 4, world_size * 0.6, 3, 0.5)
			var dir := Vector2(cos(angle), sin(angle))
			for z in res:
				for x in res:
					var px := x * cell
					var pz := z * cell
					var d := px * dir.x + pz * dir.y + warp.get_noise_2d(px, pz) * wavelength * 0.9
					var s := fposmod(d / wavelength, 1.0)
					var profile := s / 0.72 if s < 0.72 else (1.0 - s) / 0.28
					var dune := smoothstep(0.0, 1.0, profile)
					var a := amp.get_noise_2d(px, pz) * 0.5 + 0.5
					out[z * res + x] = dune * lerpf(0.25, 1.0, a) * height + (base.get_noise_2d(px, pz) * 0.5 + 0.5) * height * 0.35
		"canyon":
			var chan := _noise(seed_value, world_size * 0.42 * feature, 4, 0.45, FastNoiseLite.FRACTAL_RIDGED)
			chan.domain_warp_enabled = true
			chan.domain_warp_amplitude = world_size * 0.05
			chan.domain_warp_frequency = 1.0 / (world_size * 0.4)
			var base := _noise(seed_value + 7, world_size * 0.5 * feature, octaves, gain)
			var steps := 5.0
			for z in res:
				for x in res:
					var px := x * cell
					var pz := z * cell
					var c := pow(clampf(chan.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0), 4.0)
					var b := base.get_noise_2d(px, pz) * 0.5 + 0.5
					var raw := clampf(0.5 + 0.5 * b - c * 1.15, 0.0, 1.0)
					var t := raw * steps
					var f := floorf(t)
					var terr := (f + smoothstep(0.55, 0.95, t - f)) / steps
					out[z * res + x] = terr * height
		"crater":
			var n := _noise(seed_value, world_size * 0.2 * feature, octaves, gain)
			var rad := 0.55 * clampf(feature, 0.3, 1.6)
			var depth := height * 0.7
			var rim := height * 0.45
			for z in res:
				for x in res:
					var px := x * cell - half
					var pz := z * cell - half
					var r := Vector2(px, pz).length() / half
					var h := n.get_noise_2d(px, pz) * height * 0.12
					h += _crater_profile(r / rad, depth, rim)
					out[z * res + x] = h
			for i in 9:
				var c := Vector2(rng.randf_range(-0.85, 0.85), rng.randf_range(-0.85, 0.85)) * half
				var cr := rng.randf_range(0.04, 0.12) * world_size
				_stamp_crater(out, res, cell, half, c, cr, height * rng.randf_range(0.15, 0.35))
		"volcano":
			var warp := _noise(seed_value, world_size * 0.25, 4, 0.5)
			var ridges := _noise(seed_value + 3, world_size * 0.08 * feature, 4, 0.5, FastNoiseLite.FRACTAL_RIDGED)
			var caldera := 0.09 * clampf(feature, 0.5, 2.0)
			for z in res:
				for x in res:
					var px := x * cell - half
					var pz := z * cell - half
					var r := Vector2(px, pz).length() / half
					var rw := r + warp.get_noise_2d(px, pz) * 0.07
					var cone := pow(1.0 - smoothstep(0.0, 0.88, rw), 1.7)
					var h := cone * height
					h += (ridges.get_noise_2d(px, pz) * 0.5 + 0.5) * height * 0.07 * cone
					h -= height * 0.24 * (1.0 - smoothstep(caldera * 0.3, caldera * 1.4, r))
					h -= smoothstep(0.7, 1.0, r) * (height * 0.12 + 3.0)
					out[z * res + x] = h - 1.0
		"valley":
			var angle := rng.randf_range(-0.6, 0.6)
			var dir := Vector2(cos(angle), sin(angle))
			var warp := _noise(seed_value, world_size * 0.5, 3, 0.5)
			var ridge := _noise(seed_value + 11, world_size * 0.3 * feature, octaves, gain, FastNoiseLite.FRACTAL_RIDGED)
			var n := _noise(seed_value + 13, world_size * 0.15, 3, 0.5)
			for z in res:
				for x in res:
					var px := x * cell - half
					var pz := z * cell - half
					var across := absf(-px * dir.y + pz * dir.x) / half
					across += warp.get_noise_2d(px, pz) * 0.18
					var sides := pow(smoothstep(0.06, 0.95, absf(across)), 1.35)
					var m := clampf(ridge.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0)
					out[z * res + x] = sides * height * lerpf(0.65, 1.1, m) + n.get_noise_2d(px, pz) * height * 0.03

	# Flatten the borders into a plain so the terrain continues into the horizon
	# (skipped for presets that end in the sea).
	var edge_default := not (preset in ["island", "archipelago", "volcano"])
	if bool(params.get("edge_falloff", edge_default)) and str(params.get("mode", "replace")) == "replace":
		_edge_blend(out, res, clampf(float(params.get("edge_width", 0.16)), 0.02, 0.5))
	_apply_mode(data, out, str(params.get("mode", "replace")), clampf(float(params.get("strength", 1.0)), 0.0, 1.0))
	data.emit_changed()
	return {"preset": preset, "seed": seed_value, "height": snappedf(height, 0.01), "height_range": data.height_range()}


static func _apply_mode(data, out: PackedFloat32Array, mode: String, strength: float) -> void:
	var h: PackedFloat32Array = data.heights
	match mode:
		"add":
			for i in h.size():
				h[i] += out[i] * strength
		"max":
			for i in h.size():
				h[i] = maxf(h[i], out[i])
		"min":
			for i in h.size():
				h[i] = minf(h[i], out[i])
		"blend":
			for i in h.size():
				h[i] = lerpf(h[i], out[i], strength)
		_:
			data.heights = out
			return
	data.heights = h


## Blends heights near the map border toward a low base level (25th percentile).
static func _edge_blend(out: PackedFloat32Array, res: int, width_frac: float) -> void:
	var sample: Array = []
	var stride := maxi(1, out.size() / 4096)
	for i in range(0, out.size(), stride):
		sample.append(out[i])
	sample.sort()
	var base: float = sample[int(sample.size() * 0.25)] if not sample.is_empty() else 0.0
	var width := maxf(float(res) * width_frac, 1.0)
	for z in res:
		var dz := mini(z, res - 1 - z)
		for x in res:
			var d := mini(mini(x, res - 1 - x), dz)
			if d >= width:
				continue
			var t := smoothstep(0.0, 1.0, float(d) / width)
			var i := z * res + x
			out[i] = lerpf(base, out[i], t)


## Radial crater profile. t = distance / crater radius.
static func _crater_profile(t: float, depth: float, rim: float) -> float:
	var h := 0.0
	if t < 1.0:
		h -= depth * (1.0 - t * t)
		h += depth * 0.45 * exp(-pow(t / 0.13, 2.0))
	h += rim * exp(-pow((t - 1.0) / 0.2, 2.0))
	return h


static func _stamp_crater(out: PackedFloat32Array, res: int, cell: float, half: float, center: Vector2, radius: float, depth: float) -> void:
	var reach := radius * 1.8
	var x0 := maxi(0, int((center.x - reach + half) / cell))
	var x1 := mini(res - 1, int((center.x + reach + half) / cell) + 1)
	var z0 := maxi(0, int((center.y - reach + half) / cell))
	var z1 := mini(res - 1, int((center.y + reach + half) / cell) + 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x * cell - half, z * cell - half)
			var t := p.distance_to(center) / radius
			if t < 1.8:
				out[z * res + x] += _crater_profile(t, depth, depth * 0.5)
