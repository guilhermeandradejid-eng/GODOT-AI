@tool
extends RefCounted
## Motion retargeting between skeletons.
##
##  * to the Vibe humanoid: Kimodo (SOMA30 / SMPL-X 22), BVH mocap, glTF/GLB
##    and FBX animations (Mixamo, Unreal mannequin, CMU, Godot humanoid...)
##  * from the Vibe humanoid to any other skeleton (motion.apply), so text
##    animations drive your own characters.
##
## Method: per-bone world rotation deltas from the rest pose, with a rest
## direction alignment per bone (handles T-pose vs A-pose and different bone
## axes), hips height scaled by leg length, heading split into root motion.

const H = preload("res://addons/vibe_motion/humanoid.gd")
const Synth = preload("res://addons/vibe_motion/motion_synth.gd")

## Name tables (keys normalized: lowercase letters and digits only).
const MAP_SOMA := {
	"hips": "Hips", "spine1": "Spine", "spine2": "Chest", "chest": "UpperChest", "neck1": "Neck", "head": "Head", "jaw": "Jaw",
	"lefteye": "LeftEye", "righteye": "RightEye",
	"leftshoulder": "LeftShoulder", "leftarm": "LeftUpperArm", "leftforearm": "LeftLowerArm", "lefthand": "LeftHand",
	"rightshoulder": "RightShoulder", "rightarm": "RightUpperArm", "rightforearm": "RightLowerArm", "righthand": "RightHand",
	"leftleg": "LeftUpperLeg", "leftshin": "LeftLowerLeg", "leftfoot": "LeftFoot", "lefttoebase": "LeftToes",
	"rightleg": "RightUpperLeg", "rightshin": "RightLowerLeg", "rightfoot": "RightFoot", "righttoebase": "RightToes",
}
const MAP_SMPL := {
	"pelvis": "Hips", "spine1": "Spine", "spine2": "Chest", "spine3": "UpperChest", "neck": "Neck", "head": "Head", "jaw": "Jaw",
	"leftcollar": "LeftShoulder", "leftshoulder": "LeftUpperArm", "leftelbow": "LeftLowerArm", "leftwrist": "LeftHand",
	"rightcollar": "RightShoulder", "rightshoulder": "RightUpperArm", "rightelbow": "RightLowerArm", "rightwrist": "RightHand",
	"lefthip": "LeftUpperLeg", "leftknee": "LeftLowerLeg", "leftankle": "LeftFoot", "leftfoot": "LeftToes",
	"righthip": "RightUpperLeg", "rightknee": "RightLowerLeg", "rightankle": "RightFoot", "rightfoot": "RightToes",
}
const MAP_MIXAMO := {
	"hips": "Hips", "spine": "Spine", "spine1": "Chest", "spine2": "UpperChest", "neck": "Neck", "head": "Head",
	"leftshoulder": "LeftShoulder", "leftarm": "LeftUpperArm", "leftforearm": "LeftLowerArm", "lefthand": "LeftHand",
	"rightshoulder": "RightShoulder", "rightarm": "RightUpperArm", "rightforearm": "RightLowerArm", "righthand": "RightHand",
	"leftupleg": "LeftUpperLeg", "leftleg": "LeftLowerLeg", "leftfoot": "LeftFoot", "lefttoebase": "LeftToes",
	"rightupleg": "RightUpperLeg", "rightleg": "RightLowerLeg", "rightfoot": "RightFoot", "righttoebase": "RightToes",
	"lefthandthumb1": "LeftThumbMetacarpal", "lefthandthumb2": "LeftThumbProximal", "lefthandthumb3": "LeftThumbDistal",
	"lefthandindex1": "LeftIndexProximal", "lefthandindex2": "LeftIndexIntermediate", "lefthandindex3": "LeftIndexDistal",
	"lefthandmiddle1": "LeftMiddleProximal", "lefthandmiddle2": "LeftMiddleIntermediate", "lefthandmiddle3": "LeftMiddleDistal",
	"lefthandring1": "LeftRingProximal", "lefthandring2": "LeftRingIntermediate", "lefthandring3": "LeftRingDistal",
	"lefthandpinky1": "LeftLittleProximal", "lefthandpinky2": "LeftLittleIntermediate", "lefthandpinky3": "LeftLittleDistal",
	"righthandthumb1": "RightThumbMetacarpal", "righthandthumb2": "RightThumbProximal", "righthandthumb3": "RightThumbDistal",
	"righthandindex1": "RightIndexProximal", "righthandindex2": "RightIndexIntermediate", "righthandindex3": "RightIndexDistal",
	"righthandmiddle1": "RightMiddleProximal", "righthandmiddle2": "RightMiddleIntermediate", "righthandmiddle3": "RightMiddleDistal",
	"righthandring1": "RightRingProximal", "righthandring2": "RightRingIntermediate", "righthandring3": "RightRingDistal",
	"righthandpinky1": "RightLittleProximal", "righthandpinky2": "RightLittleIntermediate", "righthandpinky3": "RightLittleDistal",
}
const MAP_CMU := {
	"hip": "Hips", "abdomen": "Spine", "chest": "Chest", "neck": "Neck", "head": "Head",
	"lcollar": "LeftShoulder", "lshldr": "LeftUpperArm", "lforearm": "LeftLowerArm", "lhand": "LeftHand",
	"rcollar": "RightShoulder", "rshldr": "RightUpperArm", "rforearm": "RightLowerArm", "rhand": "RightHand",
	"lthigh": "LeftUpperLeg", "lshin": "LeftLowerLeg", "lfoot": "LeftFoot", "rthigh": "RightUpperLeg", "rshin": "RightLowerLeg", "rfoot": "RightFoot",
	"lowerback": "Spine", "lhipjoint": "", "rhipjoint": "",
}
const MAP_UE := {
	"pelvis": "Hips", "spine01": "Spine", "spine02": "Chest", "spine03": "UpperChest", "neck01": "Neck", "head": "Head",
	"claviclel": "LeftShoulder", "upperarml": "LeftUpperArm", "lowerarml": "LeftLowerArm", "handl": "LeftHand",
	"clavicler": "RightShoulder", "upperarmr": "RightUpperArm", "lowerarmr": "RightLowerArm", "handr": "RightHand",
	"thighl": "LeftUpperLeg", "calfl": "LeftLowerLeg", "footl": "LeftFoot", "balll": "LeftToes",
	"thighr": "RightUpperLeg", "calfr": "RightLowerLeg", "footr": "RightFoot", "ballr": "RightToes",
}
## Kimodo skeleton joint names (parents/offsets come from the server).
const KIMODO_NAMES := {
	"soma30": ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "LeftEye", "RightEye", "LeftShoulder", "LeftArm",
		"LeftForeArm", "LeftHand", "LeftHandThumbEnd", "LeftHandMiddleEnd", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"RightHandThumbEnd", "RightHandMiddleEnd", "LeftLeg", "LeftShin", "LeftFoot", "LeftToeBase", "RightLeg", "RightShin", "RightFoot", "RightToeBase"],
	"smplx22": ["pelvis", "left_hip", "right_hip", "spine1", "left_knee", "right_knee", "spine2", "left_ankle", "right_ankle", "spine3",
		"left_foot", "right_foot", "neck", "left_collar", "right_collar", "head", "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
		"left_wrist", "right_wrist"],
}
## The child used to measure each humanoid bone's rest direction.
const DIR_CHILD := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand", "LeftHand": "LeftMiddleProximal",
	"RightShoulder": "RightUpperArm", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand", "RightHand": "RightMiddleProximal",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot", "RightFoot": "RightToes",
	"LeftThumbMetacarpal": "LeftThumbProximal", "LeftThumbProximal": "LeftThumbDistal",
	"RightThumbMetacarpal": "RightThumbProximal", "RightThumbProximal": "RightThumbDistal",
}


static func norm_name(n: String) -> String:
	var s := n.to_lower()
	for prefix in ["mixamorig:", "mixamorig_", "mixamorig1:", "mixamorig2:", "bip01_", "bip01 ", "def-", "def_", "j_bip_c_", "armature|", "armature_"]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length())
	if s.contains(":"):
		s = s.get_slice(":", s.get_slice_count(":") - 1)
	var out := ""
	for i in s.length():
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


## Source bone name -> humanoid bone, picking the naming convention that
## matches best (Godot humanoid, Kimodo SOMA, SMPL-X, Mixamo, CMU, Unreal).
static func build_map(names: PackedStringArray) -> Dictionary:
	var humanoid := {}
	for b in H.bone_names():
		humanoid[norm_name(b)] = b
	var normalized := {}
	for n in names:
		normalized[n] = norm_name(n)
	var has_shin := false
	var has_upleg := false
	for n in names:
		var k: String = normalized[n]
		if k == "leftshin":
			has_shin = true
		if k == "leftupleg":
			has_upleg = true
	var tables := [humanoid, MAP_MIXAMO if has_upleg or not has_shin else MAP_SOMA, MAP_SMPL, MAP_CMU, MAP_UE]
	if has_shin:
		tables = [humanoid, MAP_SOMA, MAP_MIXAMO, MAP_SMPL, MAP_CMU, MAP_UE]
	var best := {}
	for table in tables:
		var m := {}
		var used := {}
		for n in names:
			var k: String = normalized[n]
			if table.has(k) and table[k] != "" and not used.has(table[k]):
				m[n] = table[k]
				used[table[k]] = true
		if m.size() > best.size():
			best = m
	return best


# =============================================================================
# Skeleton descriptions
# =============================================================================

## {names, parents, rest (local Transform3D per joint), index}
static func desc_from_skeleton(sk: Skeleton3D) -> Dictionary:
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rest: Array = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parents.append(sk.get_bone_parent(i))
		rest.append(sk.get_bone_rest(i))
	return _finish_desc(names, parents, rest)


static func desc_from_offsets(names: Array, parents: Array, offsets: Array) -> Dictionary:
	var n := PackedStringArray()
	var p := PackedInt32Array()
	var rest: Array = []
	for i in names.size():
		n.append(str(names[i]))
		p.append(int(parents[i]))
		var o = offsets[i]
		rest.append(Transform3D(Basis(), Vector3(float(o[0]), float(o[1]), float(o[2]))))
	return _finish_desc(n, p, rest)


static func _finish_desc(names: PackedStringArray, parents: PackedInt32Array, rest: Array) -> Dictionary:
	var index := {}
	for i in names.size():
		index[names[i]] = i
	var glob: Array = []
	glob.resize(names.size())
	var order := _topo_order(parents)
	for i in order:
		glob[i] = rest[i] if parents[i] < 0 else (glob[parents[i]] as Transform3D) * (rest[i] as Transform3D)
	return {"names": names, "parents": parents, "rest": rest, "global": glob, "index": index, "order": order}


static func _topo_order(parents: PackedInt32Array) -> Array:
	var order: Array = []
	var done := {}
	var guard := 0
	while order.size() < parents.size() and guard < parents.size() + 2:
		guard += 1
		for i in parents.size():
			if done.has(i):
				continue
			if parents[i] < 0 or done.has(parents[i]):
				order.append(i)
				done[i] = true
	return order


## Rotation that makes a source skeleton stand Y-up and face +Z with its
## left side on +X (auto-detected from the rest pose), times `facing` degrees.
static func orientation_fix(desc: Dictionary, map: Dictionary, facing_deg: float = 0.0, auto: bool = true) -> Quaternion:
	var fix := Quaternion.IDENTITY
	if auto:
		var pos := func(bone: String) -> Variant:
			for n in map:
				if map[n] == bone:
					return (desc.global[desc.index[n]] as Transform3D).origin
			return null
		var hips = pos.call("Hips")
		var head = pos.call("Head")
		if head == null:
			head = pos.call("Neck")
		var ll = pos.call("LeftUpperLeg")
		var rl = pos.call("RightUpperLeg")
		if hips != null and head != null:
			var up: Vector3 = (head - hips).normalized()
			fix = Quaternion(up, Vector3.UP) if up.dot(Vector3.UP) < 0.999 else Quaternion.IDENTITY
		if ll != null and rl != null:
			var lr: Vector3 = fix * ((ll as Vector3) - (rl as Vector3))
			lr.y = 0.0
			if lr.length() > 0.0001:
				var yaw := atan2(-lr.z, lr.x)
				fix = Quaternion(Vector3.UP, -yaw) * fix
	return (Quaternion(Vector3.UP, deg_to_rad(facing_deg)) * fix).normalized()


# =============================================================================
# Anything -> Vibe humanoid
# =============================================================================

## src: desc (see above); frames: Array of Array[Quaternion] (full local
## rotations per joint); root_pos: Array[Vector3] per frame (position of the
## root joint in the source's parent space). Returns synthesizer-style frames.
static func to_humanoid(src: Dictionary, frames: Array, root_pos: Array, fps: float, opts: Dictionary = {}) -> Dictionary:
	var map: Dictionary = opts.get("map", build_map(src.names))
	var inv := {}
	for n in map:
		inv[map[n]] = src.index[n]
	if not inv.has("Hips"):
		return {"error": "no hips/pelvis joint found in the source skeleton (%s...)" % ", ".join(Array(src.names).slice(0, 8))}
	var F: Quaternion = orientation_fix(src, map, float(opts.get("facing", 0.0)), bool(opts.get("auto_orient", true)))
	var nj: int = src.names.size()
	var parents: PackedInt32Array = src.parents
	var order: Array = src.order
	# Rest rotations (with the orientation fix) and alignments.
	var r0: Array = []
	r0.resize(nj)
	for i in nj:
		r0[i] = F * (src.global[i] as Transform3D).basis.get_rotation_quaternion()
	var src_pos := func(i: int) -> Vector3: return F * (src.global[i] as Transform3D).origin
	var align := {}
	for b in inv:
		var c: String = DIR_CHILD.get(b, "")
		if c != "" and inv.has(c):
			var dh := H.rest_position(c) - H.rest_position(b)
			var ds: Vector3 = src_pos.call(inv[c]) - src_pos.call(inv[b])
			if dh.length() > 0.0001 and ds.length() > 0.0001:
				align[b] = _arc(dh.normalized(), ds.normalized())
	# Leg length ratio for translations.
	var foot_i: int = inv.get("LeftToes", inv.get("LeftFoot", -1))
	var src_leg := 1.0
	if foot_i >= 0:
		src_leg = maxf(0.01, (src_pos.call(inv.Hips) as Vector3).y - (src_pos.call(foot_i) as Vector3).y)
	var dst_leg := H.rest_position("Hips").y - H.rest_position("LeftToes" if inv.has("LeftToes") else "LeftFoot").y
	var k: float = float(opts.get("scale", dst_leg / src_leg))
	var feet: Array = []
	for b in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
		if inv.has(b):
			feet.append(inv[b])
	# Pass 1: world deltas, hips heading and foot heights per frame.
	var nf := frames.size()
	var deltas: Array = []
	var yaws := PackedFloat32Array()
	var hips_w: Array = []
	var floor_y := INF
	var hips_i: int = inv.Hips
	for f in nf:
		var loc: Array = frames[f]
		var g: Array = []
		g.resize(nj)
		var gp: Array = []
		gp.resize(nj)
		for i in order:
			var q: Quaternion = loc[i] if i < loc.size() else (src.rest[i] as Transform3D).basis.get_rotation_quaternion()
			if parents[i] < 0:
				g[i] = F * q
				gp[i] = F * (root_pos[f] if f < root_pos.size() else (src.rest[i] as Transform3D).origin)
			else:
				g[i] = (g[parents[i]] as Quaternion) * q
				gp[i] = (gp[parents[i]] as Vector3) + (g[parents[i]] as Quaternion) * (src.rest[i] as Transform3D).origin
		var D := {}
		for i in nj:
			D[i] = ((g[i] as Quaternion) * (r0[i] as Quaternion).inverse()).normalized()
		deltas.append(D)
		for i in feet:
			floor_y = minf(floor_y, (gp[i] as Vector3).y)
		hips_w.append(gp[hips_i])
		var Dh: Quaternion = D[hips_i]
		if align.has("Hips"):
			Dh = Dh * (align.Hips as Quaternion)
		var fwd := Dh * Vector3.BACK
		yaws.append(atan2(fwd.x, fwd.z))
	if floor_y == INF:
		floor_y = 0.0
	# Unwrap and smooth the heading (root yaw).
	for f in range(1, nf):
		while yaws[f] - yaws[f - 1] > PI:
			yaws[f] -= TAU
		while yaws[f] - yaws[f - 1] < -PI:
			yaws[f] += TAU
	var smooth := PackedFloat32Array()
	smooth.resize(nf)
	var win := int(opts.get("heading_smooth", 7))
	for f in nf:
		var acc := 0.0
		var cnt := 0
		for d in range(-win, win + 1):
			var ff := clampi(f + d, 0, nf - 1)
			acc += yaws[ff]
			cnt += 1
		smooth[f] = acc / float(cnt)
	# Pass 2: humanoid joint rotations.
	var toe_h := H.rest_position("LeftToes").y if inv.has("LeftToes") else H.rest_position("LeftFoot").y
	var start: Vector3 = hips_w[0] if nf > 0 else Vector3.ZERO
	var out_frames: Array = []
	var bones := H.bone_names()
	for f in nf:
		var D: Dictionary = deltas[f]
		var Dt := {}
		var pose := Synth.Pose.new()
		for b in bones:
			if b == "Root":
				Dt[b] = Quaternion.IDENTITY
				continue
			var par := H.parent_of(b)
			var parent_d: Quaternion = Dt.get(par, Quaternion.IDENTITY)
			if inv.has(b):
				var d: Quaternion = D[inv[b]]
				if align.has(b):
					d = d * (align[b] as Quaternion)
				Dt[b] = d
			else:
				Dt[b] = parent_d
			if b == "Hips":
				pose.j[b] = (Quaternion(Vector3.UP, -smooth[f]) * (Dt[b] as Quaternion)).normalized()
			else:
				pose.j[b] = (parent_d.inverse() * (Dt[b] as Quaternion)).normalized()
		var hw: Vector3 = hips_w[f]
		var root := Vector3(hw.x - start.x, 0.0, hw.z - start.z) * k
		var hy := (hw.y - floor_y) * k + toe_h
		pose.hips = Vector3(0, hy - H.rest_position("Hips").y, 0)
		out_frames.append({"root": root, "yaw": smooth[f], "pose": pose})
	return {"frames": out_frames, "fps": fps, "duration": float(maxi(nf - 1, 0)) / fps, "loop": false,
		"segments": [{"clip": "imported", "start": 0.0, "duration": snappedf(float(maxi(nf - 1, 0)) / fps, 0.01)}],
		"mapped": map.size(), "scale": k}


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	# Shortest rotation taking unit vector a to unit vector b.
	var d := a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length() < 0.001:
			axis = a.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clampf(d, -1.0, 1.0)))


# =============================================================================
# File formats
# =============================================================================

## Parses a BVH file: {desc, frames, root_pos, fps} or {error}.
static func load_bvh(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "cannot open %s" % path}
	var text := f.get_as_text()
	f.close()
	var tokens := text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false)
	var i := 0
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var offsets: Array = []
	var channels: Array = []
	var stack: Array = []
	var last := -1
	var end_site := false
	while i < tokens.size():
		var t := tokens[i]
		match t:
			"ROOT", "JOINT":
				names.append(tokens[i + 1])
				parents.append(stack.back() if not stack.is_empty() else -1)
				offsets.append(Vector3.ZERO)
				channels.append([])
				last = names.size() - 1
				i += 2
				continue
			"End":
				end_site = true
				i += 2
				continue
			"{":
				stack.append(last if not end_site else -2)
			"}":
				stack.pop_back()
				end_site = false
				while not stack.is_empty() and stack.back() == -2:
					stack.pop_back()
				if not stack.is_empty():
					last = stack.back()
			"OFFSET":
				if not end_site:
					offsets[last] = Vector3(float(tokens[i + 1]), float(tokens[i + 2]), float(tokens[i + 3]))
				i += 4
				continue
			"CHANNELS":
				var n := int(tokens[i + 1])
				var ch: Array = []
				for c in n:
					ch.append(tokens[i + 2 + c].to_lower())
				channels[last] = ch
				i += 2 + n
				continue
			"MOTION":
				i += 1
				break
		i += 1
	var nframes := 0
	var frame_time := 1.0 / 30.0
	while i < tokens.size():
		if tokens[i] == "Frames:":
			nframes = int(tokens[i + 1])
			i += 2
		elif tokens[i] == "Frame" and i + 2 < tokens.size() and tokens[i + 1] == "Time:":
			frame_time = float(tokens[i + 2])
			i += 3
			break
		else:
			i += 1
	var per_frame := 0
	for ch in channels:
		per_frame += (ch as Array).size()
	var frames: Array = []
	var root_pos: Array = []
	for fr in nframes:
		if i + per_frame > tokens.size():
			break
		var rots: Array = []
		var rp := Vector3.ZERO
		for j in names.size():
			var q := Quaternion.IDENTITY
			var pos: Vector3 = offsets[j]
			for c in channels[j]:
				var v := float(tokens[i])
				i += 1
				match c:
					"xposition":
						pos.x = v
					"yposition":
						pos.y = v
					"zposition":
						pos.z = v
					"xrotation":
						q = q * Quaternion(Vector3.RIGHT, deg_to_rad(v))
					"yrotation":
						q = q * Quaternion(Vector3.UP, deg_to_rad(v))
					"zrotation":
						q = q * Quaternion(Vector3.BACK, deg_to_rad(v))
			rots.append(q)
			if j == 0:
				rp = pos
		frames.append(rots)
		root_pos.append(rp)
	var desc := desc_from_offsets(Array(names), Array(parents), offsets.map(func(v): return [v.x, v.y, v.z]))
	return {"desc": desc, "frames": frames, "root_pos": root_pos, "fps": 1.0 / maxf(frame_time, 0.001)}


## Loads a glTF/GLB (or FBX on Godot 4.3+) file and samples its skeleton
## animation: {desc, frames, root_pos, fps, animation} or {error}.
static func load_scene_animation(path: String, anim_name: String = "", fps: float = 30.0) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var doc: Object = null
	var state: Object = null
	if ext == "fbx":
		if not ClassDB.class_exists("FBXDocument"):
			return {"error": "FBX import needs Godot 4.3+ (FBXDocument)"}
		doc = ClassDB.instantiate("FBXDocument")
		state = ClassDB.instantiate("FBXState")
	else:
		doc = GLTFDocument.new()
		state = GLTFState.new()
	var err: int = doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		return {"error": "could not read %s (%s)" % [path, error_string(err)]}
	var scene: Node = doc.generate_scene(state)
	if scene == null:
		return {"error": "no scene in %s" % path}
	var out := _sample_scene(scene, anim_name, fps)
	scene.free()
	return out


static func _find_first(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


static func _sample_scene(scene: Node, anim_name: String, fps: float) -> Dictionary:
	var player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
	if player == null or player.get_animation_list().is_empty():
		return {"error": "the file has no animation"}
	var list := player.get_animation_list()
	var an := anim_name if anim_name != "" and player.has_animation(anim_name) else list[0]
	var anim := player.get_animation(an)
	var anim_root: Node = player.get_node_or_null(player.root_node)
	if anim_root == null:
		anim_root = player.get_parent()
	var sk := _find_first(scene, "Skeleton3D") as Skeleton3D
	var nf := maxi(2, int(ceil(anim.length * fps)) + 1)
	var frames: Array = []
	var root_pos: Array = []
	if sk != null and sk.get_bone_count() > 0:
		var desc := desc_from_skeleton(sk)
		var sk_path := anim_root.get_path_to(sk)
		var rot_tr := {}
		var pos_tr := {}
		for tr in anim.get_track_count():
			var p := anim.track_get_path(tr)
			if NodePath(p.get_concatenated_names()) != sk_path or p.get_subname_count() == 0:
				continue
			var bi := sk.find_bone(str(p.get_subname(0)))
			if bi < 0:
				continue
			if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
				rot_tr[bi] = tr
			elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
				pos_tr[bi] = tr
		var root_bone := 0
		for i in sk.get_bone_count():
			if sk.get_bone_parent(i) < 0:
				root_bone = i
				break
		# The skeleton node's own transform (e.g. FBX unit scale) goes into
		# the root joint so positions come out in meters.
		var sk_xf := _global_of(sk)
		var sk_rot := sk_xf.basis.get_rotation_quaternion()
		for f in nf:
			var t := minf(float(f) / fps, anim.length)
			var rots: Array = []
			for i in sk.get_bone_count():
				var q: Quaternion = anim.rotation_track_interpolate(rot_tr[i], t) if rot_tr.has(i) else sk.get_bone_rest(i).basis.get_rotation_quaternion()
				if i == root_bone:
					q = sk_rot * q
				rots.append(q)
			var rp: Vector3 = anim.position_track_interpolate(pos_tr[root_bone], t) if pos_tr.has(root_bone) else sk.get_bone_rest(root_bone).origin
			frames.append(rots)
			root_pos.append(sk_xf * rp)
		# Rest of the root joint in the same space (the node's scale moves
		# into the offsets so everything is in meters).
		var rest: Array = desc.rest.duplicate()
		var scale := sk_xf.basis.get_scale().x
		for i in rest.size():
			var r: Transform3D = rest[i]
			if i == root_bone:
				rest[i] = Transform3D(Basis(sk_rot) * r.basis, sk_xf * r.origin)
			else:
				rest[i] = Transform3D(r.basis, r.origin * scale)
		var fixed := _finish_desc(desc.names, desc.parents, rest)
		return {"desc": fixed, "frames": frames, "root_pos": root_pos, "fps": fps, "animation": an}
	# Node hierarchy (no skin): joints are Node3Ds animated by path.
	var nodes: Array = []
	_collect_3d(anim_root, nodes)
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rest: Array = []
	var idx := {}
	for n in nodes:
		idx[n] = names.size()
		names.append(str((n as Node).name))
	for n in nodes:
		var par: Node = (n as Node).get_parent()
		parents.append(idx.get(par, -1))
		rest.append((n as Node3D).transform)
	var desc := _finish_desc(names, parents, rest)
	var rot_tr := {}
	var pos_tr := {}
	for tr in anim.get_track_count():
		var p := anim.track_get_path(tr)
		var node := anim_root.get_node_or_null(NodePath(p.get_concatenated_names()))
		if node == null or not idx.has(node):
			continue
		var ji: int = idx[node]
		match anim.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				rot_tr[ji] = tr
			Animation.TYPE_POSITION_3D:
				pos_tr[ji] = tr
	var root_i := 0
	for f in nf:
		var t := minf(float(f) / fps, anim.length)
		var rots: Array = []
		for i in names.size():
			rots.append(anim.rotation_track_interpolate(rot_tr[i], t) if rot_tr.has(i) else (rest[i] as Transform3D).basis.get_rotation_quaternion())
		frames.append(rots)
		root_pos.append(anim.position_track_interpolate(pos_tr[root_i], t) if pos_tr.has(root_i) else (rest[root_i] as Transform3D).origin)
	return {"desc": desc, "frames": frames, "root_pos": root_pos, "fps": fps, "animation": an}


static func _collect_3d(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D and not (c is MeshInstance3D) and not (c is Camera3D) and not (c is Light3D):
			out.append(c)
		_collect_3d(c, out)


static func _global_of(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# =============================================================================
# Vibe humanoid -> any skeleton
# =============================================================================

## Builds an Animation for another skeleton from a humanoid animation.
## skeleton_path: track path prefix (relative to the AnimationPlayer root).
static func humanoid_to_skeleton(anim: Animation, sk: Skeleton3D, skeleton_path: String, opts: Dictionary = {}) -> Dictionary:
	var dst := desc_from_skeleton(sk)
	var map := build_map(dst.names)
	var inv := {}
	for n in map:
		inv[map[n]] = dst.index[n]
	if not inv.has("Hips") or inv.size() < 8:
		return {"error": "could not recognize a humanoid skeleton in '%s' (%d bones matched). Rename bones with Godot's humanoid BoneMap or Mixamo names." % [sk.name, inv.size()]}
	var F: Quaternion = orientation_fix(dst, map, 0.0, true).inverse()
	var nd: int = dst.names.size()
	var r0: Array = []
	for i in nd:
		r0.append((dst.global[i] as Transform3D).basis.get_rotation_quaternion())
	var dpos := func(i: int) -> Vector3: return (dst.global[i] as Transform3D).origin
	var align := {}
	for b in inv:
		var c: String = DIR_CHILD.get(b, "")
		if c != "" and inv.has(c):
			var dh := (H.rest_position(c) - H.rest_position(b)).normalized()
			var dd: Vector3 = (F.inverse() * (dpos.call(inv[c]) - dpos.call(inv[b]))).normalized()
			align[b] = _arc(dd, dh)
	# Leg length ratio (skeleton units per humanoid meter).
	var foot: String = "LeftToes" if inv.has("LeftToes") else "LeftFoot"
	var dst_leg := 1.0
	if inv.has(foot):
		dst_leg = maxf(0.0001, (F.inverse() * (dpos.call(inv.Hips) - dpos.call(inv[foot]))).y)
	var k := dst_leg / (H.rest_position("Hips").y - H.rest_position(foot).y)
	var fps: float = float(opts.get("fps", 30.0))
	var nf := maxi(2, int(ceil(anim.length * fps)) + 1)
	var prefix := "Skeleton3D:"
	var tr_of := {}
	for tr in anim.get_track_count():
		var p := anim.track_get_path(tr)
		if p.get_subname_count() > 0:
			tr_of[str(p.get_subname(0)) + "/" + str(anim.track_get_type(tr))] = tr
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	out.step = 1.0 / fps
	var rot_tracks := {}
	var hips_i: int = inv.Hips
	var hips_parent: int = dst.parents[hips_i]
	var hips_pos_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_pos_tr, skeleton_path + ":" + dst.names[hips_i])
	var targets: Array = []
	for i in nd:
		# Every bone at or below the hips that is mapped (or between mapped ones).
		if map.has(dst.names[i]):
			targets.append(i)
	for i in targets:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, skeleton_path + ":" + dst.names[i])
		rot_tracks[i] = tr
	var in_place := bool(opts.get("in_place", false))
	for f in nf:
		var t := minf(float(f) / fps, anim.length)
		# Humanoid world deltas.
		var yaw_q: Quaternion = anim.rotation_track_interpolate(tr_of["Root/%d" % Animation.TYPE_ROTATION_3D], t) if tr_of.has("Root/%d" % Animation.TYPE_ROTATION_3D) else Quaternion.IDENTITY
		var root_p: Vector3 = anim.position_track_interpolate(tr_of["Root/%d" % Animation.TYPE_POSITION_3D], t) if tr_of.has("Root/%d" % Animation.TYPE_POSITION_3D) else Vector3.ZERO
		var hips_p: Vector3 = anim.position_track_interpolate(tr_of["Hips/%d" % Animation.TYPE_POSITION_3D], t) if tr_of.has("Hips/%d" % Animation.TYPE_POSITION_3D) else H.rest_position("Hips")
		var Dh := {}
		for b in H.bone_names():
			if b == "Root":
				Dh[b] = yaw_q
				continue
			var key := b + "/%d" % Animation.TYPE_ROTATION_3D
			var local: Quaternion = anim.rotation_track_interpolate(tr_of[key], t) if tr_of.has(key) else H.local_rotation(b, Quaternion.IDENTITY)
			var j := H.joint_rotation(b, local)
			Dh[b] = (Dh[H.parent_of(b)] as Quaternion) * j
		# Destination globals.
		var G := {}
		for i in dst.order:
			var b: String = map.get(dst.names[i], "")
			var g: Quaternion
			if b != "":
				var d: Quaternion = F * (Dh[b] as Quaternion) * (align.get(b, Quaternion.IDENTITY) as Quaternion) * F.inverse()
				g = d * (r0[i] as Quaternion)
			else:
				var par: int = dst.parents[i]
				var pg: Quaternion = G[par] if par >= 0 else Quaternion.IDENTITY
				g = pg * (dst.rest[i] as Transform3D).basis.get_rotation_quaternion()
			G[i] = g
			if rot_tracks.has(i):
				var par2: int = dst.parents[i]
				var pg2: Quaternion = G[par2] if par2 >= 0 else Quaternion.IDENTITY
				out.rotation_track_insert_key(rot_tracks[i], t, (pg2.inverse() * g).normalized())
		# Hips position: humanoid world position scaled, in the hips' parent space.
		var world := root_p + yaw_q * hips_p
		if in_place:
			world = Vector3(0, world.y, 0)
		var sp := F * (world * k)
		if hips_parent >= 0:
			sp = (dst.global[hips_parent] as Transform3D).affine_inverse() * sp
		out.position_track_insert_key(hips_pos_tr, t, sp)
	return {"animation": out, "mapped": inv.size(), "bones": nd, "scale": k}
