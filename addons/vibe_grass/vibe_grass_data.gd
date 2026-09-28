@tool
@icon("res://addons/vibe_grass/icons/grass_data.svg")
class_name VibeGrassData
extends Resource
## Density map of a [VibeGrass3D] (0..255 per texel), covering the terrain area.

@export var resolution: int = 257
@export var density := PackedByteArray()


func setup(p_resolution: int, value: int = 0) -> void:
	resolution = maxi(2, p_resolution)
	density = PackedByteArray()
	density.resize(resolution * resolution)
	density.fill(clampi(value, 0, 255))
	emit_changed()


func is_valid() -> bool:
	return resolution >= 2 and density.size() == resolution * resolution


func get_value(x: int, z: int) -> float:
	x = clampi(x, 0, resolution - 1)
	z = clampi(z, 0, resolution - 1)
	return density[z * resolution + x] / 255.0


func sample(fx: float, fz: float) -> float:
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - x0
	var tz := fz - z0
	return lerpf(lerpf(get_value(x0, z0), get_value(x0 + 1, z0), tx), lerpf(get_value(x0, z0 + 1), get_value(x0 + 1, z0 + 1), tx), tz)


func image() -> Image:
	return Image.create_from_data(resolution, resolution, false, Image.FORMAT_L8, density)


## Resamples the density map to a new resolution (e.g. after the terrain changed size).
func resample(new_resolution: int) -> void:
	if new_resolution == resolution or not is_valid():
		if not is_valid():
			setup(new_resolution)
		return
	var img := image()
	img.resize(new_resolution, new_resolution, Image.INTERPOLATE_BILINEAR)
	resolution = new_resolution
	density = img.get_data()
	emit_changed()


func coverage() -> float:
	if density.is_empty():
		return 0.0
	var total := 0
	for v in density:
		total += v
	return float(total) / (255.0 * density.size())


func snapshot() -> Dictionary:
	return {"resolution": resolution, "density": density.duplicate()}


func restore(snap: Dictionary) -> void:
	resolution = int(snap.resolution)
	density = (snap.density as PackedByteArray).duplicate()
	emit_changed()
