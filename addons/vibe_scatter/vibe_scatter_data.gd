@tool
extends Resource
## Painted density for a VibeScatter3D (0..255 per texel over the terrain;
## 255 = the preset's full density). Saved next to the scene.

@export var resolution := 0
@export var density := PackedByteArray()


func setup(res: int, value: int = 255) -> void:
	resolution = res
	density = PackedByteArray()
	density.resize(res * res)
	density.fill(value)


func is_valid() -> bool:
	return resolution > 1 and density.size() == resolution * resolution


## Bilinear sample, fx/fz in texels.
func sample(fx: float, fz: float) -> float:
	if not is_valid():
		return 1.0
	var x0 := clampi(int(floor(fx)), 0, resolution - 1)
	var z0 := clampi(int(floor(fz)), 0, resolution - 1)
	var x1 := mini(x0 + 1, resolution - 1)
	var z1 := mini(z0 + 1, resolution - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var tz := clampf(fz - z0, 0.0, 1.0)
	var a := lerpf(density[z0 * resolution + x0], density[z0 * resolution + x1], tx)
	var b := lerpf(density[z1 * resolution + x0], density[z1 * resolution + x1], tx)
	return lerpf(a, b, tz) / 255.0


func snapshot() -> Dictionary:
	return {"resolution": resolution, "density": density.duplicate()}


func restore(snap: Dictionary) -> void:
	resolution = int(snap.get("resolution", resolution))
	density = (snap.get("density", density) as PackedByteArray).duplicate()
	emit_changed()
