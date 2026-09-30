@tool
extends RefCounted
## Humanoid skeleton shared by the mannequin, the text-to-motion synthesizer
## and the retargeter.
##
## Bone names, hierarchy and bone axes follow Godot's SkeletonProfileHumanoid
## (the profile used by the importer's "Retarget > Bone Map"), so animations
## generated here also play on any model imported with the humanoid bone map.
## Proportions are an adult (1.8 m) instead of the profile's unit figure.
##
## Conventions used everywhere in vibe_motion ("character axes"):
##   +X = the character's left, +Y = up, +Z = forward (the character faces +Z).
## A joint rotation J (per bone) is expressed in character axes as if the
## parent were at rest; the bone's global rotation is D = D_parent * J, and the
## local pose stored in animation tracks is L = R0_parent^-1 * J * R0_bone.

const HEIGHT := 1.8
const SKELETON_NAME := "Skeleton3D"

## Rest positions (skeleton space, meters) of the left side and the center
## line; right-side bones mirror their left twin. Fingers, eyes and jaw are
## derived from the profile (see _position()).
const POSITIONS := {
	"Root": Vector3(0, 0, 0),
	"Hips": Vector3(0, 0.97, 0),
	"Spine": Vector3(0, 1.07, 0.0),
	"Chest": Vector3(0, 1.19, 0.0),
	"UpperChest": Vector3(0, 1.31, 0.0),
	"Neck": Vector3(0, 1.47, 0.0),
	"Head": Vector3(0, 1.585, 0.01),
	"Jaw": Vector3(0, 1.62, 0.035),
	"LeftEye": Vector3(0.032, 1.685, 0.082),
	"LeftShoulder": Vector3(0.03, 1.43, 0.0),
	"LeftUpperArm": Vector3(0.18, 1.435, 0.0),
	"LeftLowerArm": Vector3(0.465, 1.435, 0.0),
	"LeftHand": Vector3(0.72, 1.435, 0.0),
	"LeftUpperLeg": Vector3(0.09, 0.93, 0.0),
	"LeftLowerLeg": Vector3(0.09, 0.51, 0.0),
	"LeftFoot": Vector3(0.09, 0.08, -0.01),
	"LeftToes": Vector3(0.09, 0.015, 0.13),
}
## Left-hand finger roots (offset from the wrist) and phalanx lengths; fingers
## point along the hand (+X for the left hand at rest, palm down).
const FINGER_BASE := {
	"Index": Vector3(0.088, -0.002, 0.026), "Middle": Vector3(0.091, 0.0, 0.005),
	"Ring": Vector3(0.087, -0.002, -0.016), "Little": Vector3(0.079, -0.005, -0.034),
}
const FINGER_LENGTHS := {
	"Index": [0.043, 0.026], "Middle": [0.047, 0.029], "Ring": [0.044, 0.027], "Little": [0.035, 0.021],
}
const THUMB_BASE := Vector3(0.022, -0.012, 0.024)
const THUMB_DIR := Vector3(0.8, -0.16, 0.58)
const THUMB_LENGTHS := [0.042, 0.032]

const SPINE := ["Spine", "Chest", "UpperChest"]
const FINGERS := ["Index", "Middle", "Ring", "Little"]
const PHALANGES := ["Proximal", "Intermediate", "Distal"]

static var _data := {}


## Rest data for a skeleton of the given height (cached):
## {names, parents (index), parent_names, index, rest_local[], rest_global[], rot0[] (Quaternion)}
static func data(height: float = HEIGHT) -> Dictionary:
	var key := snappedf(height, 0.001)
	if _data.has(key):
		return _data[key]
	var profile := SkeletonProfileHumanoid.new()
	var n := profile.bone_size
	var names := PackedStringArray()
	var index := {}
	for i in n:
		names.append(str(profile.get_bone_name(i)))
		index[names[i]] = i
	var parents := PackedInt32Array()
	var parent_names := PackedStringArray()
	var profile_global: Array = []
	for i in n:
		var par := str(profile.get_bone_parent(i))
		parents.append(index.get(par, -1))
		parent_names.append(par)
		var ref: Transform3D = profile.get_reference_pose(i)
		profile_global.append(ref if parents[i] < 0 else profile_global[parents[i]] * ref)
	var s := height / HEIGHT
	var positions: Array = []
	for i in n:
		positions.append(_position(names[i], i, parents, profile_global, positions))
	var rest_global: Array = []
	var rot0: Array = []
	for i in n:
		var b := Basis((profile_global[i] as Transform3D).basis.get_rotation_quaternion())
		rest_global.append(Transform3D(b, positions[i] * s))
		rot0.append(b.get_rotation_quaternion())
	var rest_local: Array = []
	for i in n:
		var g: Transform3D = rest_global[i]
		rest_local.append(g if parents[i] < 0 else (rest_global[parents[i]] as Transform3D).affine_inverse() * g)
	var d := {
		"height": height, "names": names, "parents": parents, "parent_names": parent_names,
		"index": index, "rest_local": rest_local, "rest_global": rest_global, "rot0": rot0,
	}
	_data[key] = d
	return d


static func _position(bone: String, i: int, parents: PackedInt32Array, profile_global: Array, done: Array) -> Vector3:
	if POSITIONS.has(bone):
		return POSITIONS[bone]
	if bone.begins_with("Right"):
		var twin := "Left" + bone.substr(5)
		if POSITIONS.has(twin):
			var p: Vector3 = POSITIONS[twin]
			return Vector3(-p.x, p.y, p.z)
	var par := parents[i]
	if par < 0:
		return Vector3.ZERO
	var sx := -1.0 if bone.begins_with("Right") else 1.0
	var hand: Vector3 = POSITIONS["LeftHand"] * Vector3(sx, 1, 1)
	for f in FINGERS:
		if bone.contains(f):
			var base: Vector3 = FINGER_BASE[f] * Vector3(sx, 1, 1)
			var lens: Array = FINGER_LENGTHS[f]
			if bone.ends_with("Proximal"):
				return hand + base
			if bone.ends_with("Intermediate"):
				return hand + base + Vector3(sx * lens[0], 0, 0)
			return hand + base + Vector3(sx * (lens[0] + lens[1]), 0, 0)
	if bone.contains("Thumb"):
		var tb: Vector3 = hand + THUMB_BASE * Vector3(sx, 1, 1)
		var td: Vector3 = THUMB_DIR.normalized() * Vector3(sx, 1, 1)
		if bone.ends_with("Metacarpal"):
			return tb
		if bone.ends_with("Proximal"):
			return tb + td * THUMB_LENGTHS[0]
		return tb + td * (THUMB_LENGTHS[0] + THUMB_LENGTHS[1])
	# Anything else: the profile offset from the parent.
	var offset: Vector3 = (profile_global[i] as Transform3D).origin - (profile_global[par] as Transform3D).origin
	return (done[par] as Vector3) + offset


static func bone_names() -> PackedStringArray:
	return data().names


static func has_bone(bone: String) -> bool:
	return data().index.has(bone)


## Global rest rotation (skeleton space) of a bone.
static func rot0(bone: String) -> Quaternion:
	var d := data()
	return d.rot0[d.index[bone]]


static func parent_of(bone: String) -> String:
	var d := data()
	return d.parent_names[d.index[bone]]


## Rest position (skeleton space) of a bone for a given height.
static func rest_position(bone: String, height: float = HEIGHT) -> Vector3:
	var d := data(height)
	return (d.rest_global[d.index[bone]] as Transform3D).origin


## Local pose rotation for a joint rotation J (see the header).
static func local_rotation(bone: String, j: Quaternion) -> Quaternion:
	var d := data()
	var i: int = d.index[bone]
	var r0: Quaternion = d.rot0[i]
	var p: int = d.parents[i]
	if p < 0:
		return (j * r0).normalized()
	var rp: Quaternion = d.rot0[p]
	return (rp.inverse() * j * r0).normalized()


## Inverse of local_rotation(): the joint rotation J from a local pose rotation.
static func joint_rotation(bone: String, local: Quaternion) -> Quaternion:
	var d := data()
	var i: int = d.index[bone]
	var r0: Quaternion = d.rot0[i]
	var p: int = d.parents[i]
	if p < 0:
		return (local * r0.inverse()).normalized()
	var rp: Quaternion = d.rot0[p]
	return (rp * local * r0.inverse()).normalized()


## Creates a Skeleton3D with every humanoid bone at rest.
static func build_skeleton(height: float = HEIGHT) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = SKELETON_NAME
	apply_rest(sk, height)
	return sk


## (Re)creates the bones of an existing skeleton (keeps the node).
static func apply_rest(sk: Skeleton3D, height: float = HEIGHT) -> void:
	var d := data(height)
	sk.clear_bones()
	for i in d.names.size():
		sk.add_bone(d.names[i])
	for i in d.names.size():
		if d.parents[i] >= 0:
			sk.set_bone_parent(i, d.parents[i])
		sk.set_bone_rest(i, d.rest_local[i])
	sk.reset_bone_poses()
	sk.set_meta("vibe_height", height)


## Rest height of the hips above the soles (used to scale translations when
## an animation is applied to a character of another size).
static func hips_height(height: float = HEIGHT) -> float:
	return rest_position("Hips", height).y


## Humanoid rest length helpers (meters, for the given height).
static func length(from_bone: String, to_bone: String, height: float = HEIGHT) -> float:
	return rest_position(from_bone, height).distance_to(rest_position(to_bone, height))


## Finds the Skeleton3D of a character-like node (itself or a descendant).
static func find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children(true):
		var s := find_skeleton(c)
		if s != null:
			return s
	return null
