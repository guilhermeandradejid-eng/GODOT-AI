class_name BoneHider
extends SkeletonModifier3D
## Encolhe a zero (depois da animação) os ossos pedidos — ex.: as pontas modeladas do
## cachecol, que no jogo são substituídas pelo tecido simulado (ScarfCloth).

var bones: PackedStringArray = []
var _idx: PackedInt32Array = []


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _idx.size() != bones.size():
		_idx.clear()
		for b in bones:
			_idx.append(sk.find_bone(b))
	for i in _idx:
		if i >= 0:
			sk.set_bone_pose_scale(i, Vector3.ONE * 0.001)
