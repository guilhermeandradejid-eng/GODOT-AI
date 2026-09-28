@tool
@icon("res://addons/vibe_terrain/icons/terrain_data.svg")
class_name VibeTerrainData
extends Resource
## Heightmap + splatmap of a [VibeTerrain3D].
##
## Heights are stored in meters (one value per vertex, row-major, `resolution`
## x `resolution`). The splatmap stores 4 texture-layer weights per vertex
## (RGBA8). Save it as a binary `.res` file to keep scenes small.

const LAYERS := 4

## Vertices per side. Use 2^n + 1 (65, 129, 257, 513, 1025) so chunks divide evenly.
@export var resolution: int = 257
## Distance in meters between two vertices.
@export var cell_size: float = 1.0
@export var heights := PackedFloat32Array()
@export var splat := PackedByteArray()


func setup(p_resolution: int, p_cell_size: float = 1.0, base_height: float = 0.0) -> void:
	resolution = maxi(3, p_resolution)
	cell_size = maxf(0.05, p_cell_size)
	heights = PackedFloat32Array()
	heights.resize(resolution * resolution)
	heights.fill(base_height)
	var img := Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 0))
	splat = img.get_data()
	emit_changed()


func is_valid() -> bool:
	return resolution >= 3 and heights.size() == resolution * resolution and splat.size() == resolution * resolution * 4


## World size (meters) covered by the terrain along X and Z.
func get_size() -> float:
	return float(resolution - 1) * cell_size


func get_h(x: int, z: int) -> float:
	x = clampi(x, 0, resolution - 1)
	z = clampi(z, 0, resolution - 1)
	return heights[z * resolution + x]


func set_h(x: int, z: int, value: float) -> void:
	if x < 0 or z < 0 or x >= resolution or z >= resolution:
		return
	heights[z * resolution + x] = value


## Bilinear height sample in vertex (texel) coordinates.
func sample(fx: float, fz: float) -> float:
	fx = clampf(fx, 0.0, float(resolution - 1))
	fz = clampf(fz, 0.0, float(resolution - 1))
	var x0 := mini(int(fx), resolution - 2)
	var z0 := mini(int(fz), resolution - 2)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var i := z0 * resolution + x0
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + resolution]
	var h11 := heights[i + resolution + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: int, z: int) -> Vector3:
	var hl := get_h(x - 1, z)
	var hr := get_h(x + 1, z)
	var hd := get_h(x, z - 1)
	var hu := get_h(x, z + 1)
	return Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized()


## Slope in degrees (0 = flat, 90 = vertical).
func slope_at(x: int, z: int) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


func sample_normal(fx: float, fz: float) -> Vector3:
	var hl := sample(fx - 1.0, fz)
	var hr := sample(fx + 1.0, fz)
	var hd := sample(fx, fz - 1.0)
	var hu := sample(fx, fz + 1.0)
	return Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized()


func height_range() -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var lo := heights[0]
	var hi := heights[0]
	for h in heights:
		if h < lo:
			lo = h
		elif h > hi:
			hi = h
	return Vector2(lo, hi)


func region_range(x0: int, z0: int, x1: int, z1: int) -> Vector2:
	x0 = clampi(x0, 0, resolution - 1)
	x1 = clampi(x1, 0, resolution - 1)
	z0 = clampi(z0, 0, resolution - 1)
	z1 = clampi(z1, 0, resolution - 1)
	var lo := INF
	var hi := -INF
	for z in range(z0, z1 + 1):
		var row := z * resolution
		for x in range(x0, x1 + 1):
			var h := heights[row + x]
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


func get_weight(x: int, z: int, layer: int) -> float:
	x = clampi(x, 0, resolution - 1)
	z = clampi(z, 0, resolution - 1)
	return float(splat[(z * resolution + x) * 4 + layer]) / 255.0


## Bilinear layer weight (0..1) in vertex coordinates.
func sample_weight(fx: float, fz: float, layer: int) -> float:
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	return lerpf(lerpf(get_weight(x0, z0, layer), get_weight(x0 + 1, z0, layer), tx),
		lerpf(get_weight(x0, z0 + 1, layer), get_weight(x0 + 1, z0 + 1, layer), tx), tz)


## Sets normalized weights (Array/PackedFloat32Array of 4 floats) for one vertex.
func set_weights(x: int, z: int, w: Array) -> void:
	var total := 0.0
	for v in w:
		total += maxf(0.0, float(v))
	if total <= 0.0:
		return
	var i := (z * resolution + x) * 4
	for l in LAYERS:
		splat[i + l] = int(round(clampf(float(w[l]) / total, 0.0, 1.0) * 255.0))


func height_image() -> Image:
	return Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, heights.to_byte_array())


func splat_image() -> Image:
	return Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGBA8, splat)


func snapshot() -> Dictionary:
	return {"resolution": resolution, "cell_size": cell_size, "heights": heights.duplicate(), "splat": splat.duplicate()}


func restore(snap: Dictionary) -> void:
	resolution = int(snap.get("resolution", resolution))
	cell_size = float(snap.get("cell_size", cell_size))
	heights = (snap.heights as PackedFloat32Array).duplicate()
	splat = (snap.splat as PackedByteArray).duplicate()
	emit_changed()


## Imports a grayscale image as heights between min_height and max_height.
func import_height_image(img: Image, min_height: float, max_height: float) -> void:
	var src := img.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RF)
	if src.get_width() != resolution or src.get_height() != resolution:
		src.resize(resolution, resolution, Image.INTERPOLATE_CUBIC)
	var values := src.get_data().to_float32_array()
	for i in heights.size():
		heights[i] = lerpf(min_height, max_height, clampf(values[i], 0.0, 1.0))
	emit_changed()


## Heights normalized to 0..1 as a 16-bit grayscale image (for export).
func export_height_image() -> Image:
	var r := height_range()
	var span := maxf(r.y - r.x, 0.0001)
	var norm := PackedFloat32Array()
	norm.resize(heights.size())
	for i in heights.size():
		norm[i] = (heights[i] - r.x) / span
	var img := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, norm.to_byte_array())
	img.convert(Image.FORMAT_RGB8)
	return img
