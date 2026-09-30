extends SceneTree
## Numeric checks for vibe_motion (run by tests/run_tests.py):
##   godot --headless --path . --script res://tests/motion_unit.gd
## Prints @@VIBE@@{"checks": [[name, ok, detail], ...]}

const H = preload("res://addons/vibe_motion/humanoid.gd")
const Synth = preload("res://addons/vibe_motion/motion_synth.gd")
const TextParser = preload("res://addons/vibe_motion/motion_text.gd")
const Retarget = preload("res://addons/vibe_motion/motion_retarget.gd")
const Kimodo = preload("res://addons/vibe_motion/motion_kimodo.gd")
const CharScript = preload("res://addons/vibe_motion/vibe_character_3d.gd")

var checks: Array = []


func check(name: String, ok: bool, detail: Variant = "") -> void:
	checks.append([name, ok, str(detail)])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parser()
	_walk_ik()
	_loop_and_exports()
	_kimodo_retarget()
	_bvh_import()
	_apply_to_foreign_skeleton()
	_gltf_roundtrip()
	print("@@VIBE@@" + JSON.stringify({"checks": checks}))
	quit()


func _clips(text: String) -> Array:
	var out: Array = []
	for s in TextParser.parse(text).segments:
		out.append(s.clip + ("+" + s.overlay.clip if s.has("overlay") else ""))
	return out


func _parser() -> void:
	var cases := {
		"anda devagar e depois acena duas vezes": ["walk", "wave"],
		"a person runs in a circle then jumps twice and sits down": ["run", "jump", "sit"],
		"senta, levanta e dança": ["sit", "stand_up", "dance"],
		"anda enquanto acena com a mão esquerda": ["walk+wave"],
		"faz 3 flexões": ["pushups"],
		"anda furtivo": ["sneak"],
		"soca, chuta e lança magia": ["punch", "kick", "cast"],
		"deita no chão": ["lie"],
		"sits cross-legged and meditates": ["sit_ground", "meditate"],
	}
	for text in cases:
		var got := _clips(text)
		check("parse: " + text, got == cases[text], got)
	var p := TextParser.parse("acena 3 vezes com a mão esquerda")
	check("parse count + side", p.segments[0].q.get("count", 0) == 3 and p.segments[0].q.get("side", "") == "Left", p.segments[0].q)
	p = TextParser.parse("faz 3 flexões")
	check("parse 'N <action>' count", p.segments[0].q.get("count", 0) == 3, p.segments[0].q)
	p = TextParser.parse("anda triste e depois corre")
	check("mood sticks to later segments", p.segments[1].q.get("mood_name", "") == "sad", p.segments[1].q)
	p = TextParser.parse("dança por 6 segundos")
	check("duration", absf(float(p.segments[0].q.get("duration", 0.0)) - 6.0) < 0.01, p.segments[0].q)


## Walking: the planted foot must not slide (IK + root motion agree). The ball
## of the foot (Toes bone) is the contact point from foot-flat to toe-off.
func _walk_ik() -> void:
	var synth := Synth.new()
	var res := synth.generate(TextParser.parse("anda").segments, {})
	var anim := Synth.to_animation(res)
	var sk := H.build_skeleton()
	root.add_child(sk)
	var toe := sk.find_bone("LeftToes")
	var fps := 30.0
	var worst := 0.0
	var prev := Vector3.INF
	var planted := 0
	for f in int(anim.length * fps):
		CharScript.apply_animation_pose(sk, anim, float(f) / fps)
		var p := sk.get_bone_global_pose(toe).origin
		if p.y < 0.03 and prev != Vector3.INF and prev.y < 0.03:
			planted += 1
			worst = maxf(worst, Vector2(p.x - prev.x, p.z - prev.z).length())
		prev = p
	check("walk: planted foot slides < 5 mm/frame", worst < 0.005 and planted > 20, "worst %.4f m over %d frames" % [worst, planted])
	var root_tr := anim.find_track(NodePath("Skeleton3D:Root"), Animation.TYPE_POSITION_3D)
	var end := anim.position_track_interpolate(root_tr, anim.length)
	check("walk: root motion forward ~1.35 m/s", end.z > anim.length * 1.2 and end.z < anim.length * 1.5 and absf(end.x) < 0.1, end)
	sk.queue_free()


func _loop_and_exports() -> void:
	var synth := Synth.new()
	var res := synth.generate(TextParser.parse("dança").segments, {})
	check("single cyclic clip loops", res.loop == true, res.loop)
	var anim := Synth.to_animation(res)
	var names := H.bone_names()
	var ok := true
	for b in names:
		if b != "Root" and anim.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D) < 0:
			ok = false
	check("every humanoid bone has a rotation track", ok)
	var a2 := Synth.to_animation(synth.generate(TextParser.parse("senta").segments, {}))
	check("one-shot clip does not loop", a2.loop_mode == Animation.LOOP_NONE)
	# Kimodo English prompts.
	var en := TextParser.english(TextParser.parse("anda triste em círculo").segments[0])
	check("english prompt", en.contains("walks") and en.contains("circle") and en.contains("sadly"), en)


func _segment_dir(sk: Skeleton3D, a: String, b: String) -> Vector3:
	return (sk.get_bone_global_pose(sk.find_bone(b)).origin - sk.get_bone_global_pose(sk.find_bone(a)).origin).normalized()


## Kimodo raw arrays (SOMA30) -> humanoid: arm raised, root moved.
func _kimodo_retarget() -> void:
	var names: Array = Retarget.KIMODO_NAMES.soma30
	var parents := [-1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 3, 10, 11, 12, 13, 13, 3, 16, 17, 18, 19, 19, 0, 22, 23, 24, 0, 26, 27, 28]
	var offsets := [[0, 0, 0], [0, 0.07, 0], [0, 0.1, 0], [0, 0.1, 0], [0, 0.2, 0], [0, 0.06, 0.01], [0, 0.07, 0.01], [0, 0.0, 0.04],
		[0.03, 0.06, 0.08], [-0.03, 0.06, 0.08], [0.02, 0.2, 0.0], [0.15, 0.0, -0.02], [0.28, 0, 0], [0.26, 0, 0], [0.1, -0.02, 0.05],
		[0.18, 0, 0], [-0.02, 0.2, 0.0], [-0.15, 0.0, -0.02], [-0.28, 0, 0], [-0.26, 0, 0], [-0.1, -0.02, 0.05], [-0.18, 0, 0],
		[0.1, -0.08, 0.0], [0, -0.43, 0.0], [0, -0.42, -0.01], [0, -0.05, 0.13], [-0.1, -0.08, 0.0], [0, -0.43, 0.0], [0, -0.42, -0.01], [0, -0.05, 0.13]]
	var nf := 60
	var rot := PackedFloat32Array()
	var rootp := PackedFloat32Array()
	for f in nf:
		var t := float(f) / float(nf - 1)
		for n in names:
			var q := Quaternion.IDENTITY
			if n == "LeftArm":
				q = Quaternion(Vector3.BACK, deg_to_rad(80.0) * t)
			elif n == "RightArm":
				q = Quaternion(Vector3.BACK, deg_to_rad(80.0))
			rot.append_array([q.x, q.y, q.z, q.w])
		rootp.append_array([0.0, 1.0, 1.2 * float(f) / 30.0])
	var src := Kimodo.decode(names, parents, offsets, rot, rootp)
	check("kimodo decode", not src.has("error"), src.get("error", ""))
	if src.has("error"):
		return
	var res := Retarget.to_humanoid(src.desc, src.frames, src.root_pos, 30.0, {"auto_orient": false})
	check("kimodo retarget maps the skeleton", int(res.get("mapped", 0)) >= 24, res.get("mapped", 0))
	var anim := Synth.to_animation(res)
	var sk := H.build_skeleton()
	root.add_child(sk)
	CharScript.apply_animation_pose(sk, anim, anim.length)
	var up := _segment_dir(sk, "LeftUpperArm", "LeftLowerArm")
	var down := _segment_dir(sk, "RightUpperArm", "RightLowerArm")
	check("kimodo: left arm raised", up.y > 0.9, up)
	check("kimodo: right arm down", down.y < -0.9, down)
	var rp := sk.get_bone_pose_position(sk.find_bone("Root"))
	check("kimodo: root moved forward", rp.z > 2.0 and rp.z < 2.6, rp)
	var hips := sk.get_bone_pose_position(sk.find_bone("Hips"))
	check("kimodo: hips height scaled to the humanoid", absf(hips.y - H.rest_position("Hips").y) < 0.05, hips)
	sk.queue_free()


## BVH (Mixamo names, centimeters, ZXY) -> humanoid.
func _bvh_import() -> void:
	var bvh := """HIERARCHY
ROOT mixamorig:Hips
{
	OFFSET 0 0 0
	CHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation
	JOINT mixamorig:Spine
	{
		OFFSET 0 10 0
		CHANNELS 3 Zrotation Xrotation Yrotation
		JOINT mixamorig:Spine1
		{
			OFFSET 0 12 0
			CHANNELS 3 Zrotation Xrotation Yrotation
			JOINT mixamorig:Spine2
			{
				OFFSET 0 12 0
				CHANNELS 3 Zrotation Xrotation Yrotation
				JOINT mixamorig:Neck
				{
					OFFSET 0 15 0
					CHANNELS 3 Zrotation Xrotation Yrotation
					JOINT mixamorig:Head
					{
						OFFSET 0 10 0
						CHANNELS 3 Zrotation Xrotation Yrotation
						End Site
						{
							OFFSET 0 18 0
						}
					}
				}
				JOINT mixamorig:LeftShoulder
				{
					OFFSET 3 12 0
					CHANNELS 3 Zrotation Xrotation Yrotation
					JOINT mixamorig:LeftArm
					{
						OFFSET 14 0 0
						CHANNELS 3 Zrotation Xrotation Yrotation
						JOINT mixamorig:LeftForeArm
						{
							OFFSET 28 0 0
							CHANNELS 3 Zrotation Xrotation Yrotation
							JOINT mixamorig:LeftHand
							{
								OFFSET 26 0 0
								CHANNELS 3 Zrotation Xrotation Yrotation
								End Site
								{
									OFFSET 10 0 0
								}
							}
						}
					}
				}
				JOINT mixamorig:RightShoulder
				{
					OFFSET -3 12 0
					CHANNELS 3 Zrotation Xrotation Yrotation
					JOINT mixamorig:RightArm
					{
						OFFSET -14 0 0
						CHANNELS 3 Zrotation Xrotation Yrotation
						JOINT mixamorig:RightForeArm
						{
							OFFSET -28 0 0
							CHANNELS 3 Zrotation Xrotation Yrotation
							JOINT mixamorig:RightHand
							{
								OFFSET -26 0 0
								CHANNELS 3 Zrotation Xrotation Yrotation
								End Site
								{
									OFFSET -10 0 0
								}
							}
						}
					}
				}
			}
		}
	}
	JOINT mixamorig:LeftUpLeg
	{
		OFFSET 9 -6 0
		CHANNELS 3 Zrotation Xrotation Yrotation
		JOINT mixamorig:LeftLeg
		{
			OFFSET 0 -42 0
			CHANNELS 3 Zrotation Xrotation Yrotation
			JOINT mixamorig:LeftFoot
			{
				OFFSET 0 -42 0
				CHANNELS 3 Zrotation Xrotation Yrotation
				JOINT mixamorig:LeftToeBase
				{
					OFFSET 0 -6 13
					CHANNELS 3 Zrotation Xrotation Yrotation
					End Site
					{
						OFFSET 0 0 6
					}
				}
			}
		}
	}
	JOINT mixamorig:RightUpLeg
	{
		OFFSET -9 -6 0
		CHANNELS 3 Zrotation Xrotation Yrotation
		JOINT mixamorig:RightLeg
		{
			OFFSET 0 -42 0
			CHANNELS 3 Zrotation Xrotation Yrotation
			JOINT mixamorig:RightFoot
			{
				OFFSET 0 -42 0
				CHANNELS 3 Zrotation Xrotation Yrotation
				JOINT mixamorig:RightToeBase
				{
					OFFSET 0 -6 13
					CHANNELS 3 Zrotation Xrotation Yrotation
					End Site
					{
						OFFSET 0 0 6
					}
				}
			}
		}
	}
}
MOTION
Frames: 31
Frame Time: 0.0333333
"""
	# 31 frames: hips move 60 cm forward, right arm goes from T-pose to down (-80 deg about Z).
	var joints := 22
	for f in 31:
		var t := float(f) / 30.0
		var vals: Array = [0.0, 98.0, 60.0 * t, 0.0, 0.0, 0.0]
		for j in range(1, joints):
			var z := 0.0
			if j == 11:  # RightArm (order: Spine, Spine1, Spine2, Neck, Head, LShoulder, LArm, LForeArm, LHand, RShoulder, RArm...)
				z = 80.0 * t
			vals.append_array([z, 0.0, 0.0])
		bvh += " ".join(vals.map(func(v): return str(v))) + "\n"
	var path := "user://vibe_test.bvh"
	var fw := FileAccess.open(path, FileAccess.WRITE)
	fw.store_string(bvh)
	fw.close()
	var src := Retarget.load_bvh(path)
	check("bvh parses", not src.has("error") and src.desc.names.size() == 22 and src.frames.size() == 31, [src.get("error", ""), src.get("desc", {}).get("names", []).size() if src.has("desc") else 0])
	if src.has("error"):
		return
	check("bvh hierarchy", src.desc.parents[src.desc.index["mixamorig:LeftForeArm"]] == src.desc.index["mixamorig:LeftArm"] and src.desc.parents[src.desc.index["mixamorig:LeftUpLeg"]] == 0, src.desc.parents)
	var res := Retarget.to_humanoid(src.desc, src.frames, src.root_pos, float(src.fps), {})
	check("bvh maps Mixamo names", int(res.get("mapped", 0)) >= 18, res.get("mapped", 0))
	check("bvh: centimeters scaled to meters", float(res.get("scale", 1.0)) > 0.008 and float(res.get("scale", 1.0)) < 0.012, res.get("scale", 0))
	var anim := Synth.to_animation(res)
	var sk := H.build_skeleton()
	root.add_child(sk)
	CharScript.apply_animation_pose(sk, anim, anim.length)
	var d := _segment_dir(sk, "RightUpperArm", "RightLowerArm")
	check("bvh: right arm lowered", d.y < -0.9, d)
	var l := _segment_dir(sk, "LeftUpperArm", "LeftLowerArm")
	check("bvh: left arm still in T-pose", l.x > 0.9, l)
	var rp := sk.get_bone_pose_position(sk.find_bone("Root"))
	check("bvh: root moved ~0.6 m forward", rp.z > 0.45 and rp.z < 0.75, rp)
	sk.queue_free()


## Humanoid animation -> a Mixamo-like skeleton in A-pose with other bone axes.
func _apply_to_foreign_skeleton() -> void:
	var sk := Skeleton3D.new()
	var bones := [
		["mixamorig_Hips", -1, Vector3(0, 100, 0)], ["mixamorig_Spine", 0, Vector3(0, 10, 0)], ["mixamorig_Spine1", 1, Vector3(0, 12, 0)],
		["mixamorig_Spine2", 2, Vector3(0, 12, 0)], ["mixamorig_Neck", 3, Vector3(0, 15, 0)], ["mixamorig_Head", 4, Vector3(0, 10, 0)],
		["mixamorig_LeftShoulder", 3, Vector3(3, 12, 0)], ["mixamorig_LeftArm", 6, Vector3(14, 0, 0)],
		["mixamorig_LeftForeArm", 7, Vector3(20, -20, 0)], ["mixamorig_LeftHand", 8, Vector3(18, -18, 0)],
		["mixamorig_RightShoulder", 3, Vector3(-3, 12, 0)], ["mixamorig_RightArm", 10, Vector3(-14, 0, 0)],
		["mixamorig_RightForeArm", 11, Vector3(-20, -20, 0)], ["mixamorig_RightHand", 12, Vector3(-18, -18, 0)],
		["mixamorig_LeftUpLeg", 0, Vector3(9, -6, 0)], ["mixamorig_LeftLeg", 14, Vector3(0, -44, 0)], ["mixamorig_LeftFoot", 15, Vector3(0, -44, 0)],
		["mixamorig_LeftToeBase", 16, Vector3(0, -6, 13)],
		["mixamorig_RightUpLeg", 0, Vector3(-9, -6, 0)], ["mixamorig_RightLeg", 18, Vector3(0, -44, 0)], ["mixamorig_RightFoot", 19, Vector3(0, -44, 0)],
		["mixamorig_RightToeBase", 20, Vector3(0, -6, 13)],
	]
	# Rest rotations: arbitrary twists per bone (bone axes unlike the humanoid's).
	for i in bones.size():
		sk.add_bone(bones[i][0])
	for i in bones.size():
		var par: int = bones[i][1]
		if par >= 0:
			sk.set_bone_parent(i, par)
	var globals: Array = []
	for i in bones.size():
		var par: int = bones[i][1]
		var twist := Basis(Vector3(0.3, 1, 0.2).normalized(), 0.4 * float(i))
		var pos: Vector3 = bones[i][2] if par < 0 else (globals[par] as Transform3D).origin + bones[i][2]
		globals.append(Transform3D(twist, pos))
		var local: Transform3D = globals[i] if par < 0 else (globals[par] as Transform3D).affine_inverse() * globals[i]
		sk.set_bone_rest(i, local)
	sk.reset_bone_poses()
	sk.scale = Vector3.ONE * 0.01
	root.add_child(sk)
	var synth := Synth.new()
	var src := Synth.to_animation(synth.generate(TextParser.parse("comemora").segments, {}))
	var r := Retarget.humanoid_to_skeleton(src, sk, ".", {})
	check("apply: recognizes a Mixamo skeleton", not r.has("error") and int(r.mapped) >= 18, r.get("error", r.get("mapped", 0)))
	if r.has("error"):
		sk.queue_free()
		return
	var out: Animation = r.animation
	var t := 1.2
	for tr in out.get_track_count():
		var p := out.track_get_path(tr)
		var bi := sk.find_bone(str(p.get_subname(0)))
		if out.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(bi, out.rotation_track_interpolate(tr, t))
		elif out.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			sk.set_bone_pose_position(bi, out.position_track_interpolate(tr, t))
	var up_l := _segment_dir(sk, "mixamorig_LeftArm", "mixamorig_LeftForeArm")
	var up_r := _segment_dir(sk, "mixamorig_RightArm", "mixamorig_RightForeArm")
	check("apply: cheer raises both arms on the A-pose model", up_l.y > 0.7 and up_r.y > 0.7, [up_l, up_r])
	var leg := _segment_dir(sk, "mixamorig_LeftUpLeg", "mixamorig_LeftLeg")
	check("apply: legs stay under the body", leg.y < -0.85, leg)
	var hip := sk.get_bone_pose_position(0)
	check("apply: hips height in model units", hip.y > 80.0 and hip.y < 115.0, hip)
	sk.queue_free()


## Generated animation -> GLB (Godot's exporter) -> motion import -> same pose.
func _gltf_roundtrip() -> void:
	var ch = CharScript.new()
	ch.name = "Exported"
	ch.ensure_nodes()
	root.add_child(ch)
	var anim := Synth.to_animation(Synth.new().generate(TextParser.parse("comemora").segments, {}))
	ch.add_animation(anim, "cheer")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(ch, state)
	var path := "user://vibe_roundtrip.glb"
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	check("glTF export of a generated animation", err == OK, error_string(err))
	if err != OK:
		ch.queue_free()
		return
	var src := Retarget.load_scene_animation(path, "", 30.0)
	check("glTF import samples the skeleton animation", not src.has("error") and src.frames.size() > 10, src.get("error", ""))
	if src.has("error"):
		ch.queue_free()
		return
	var res := Retarget.to_humanoid(src.desc, src.frames, src.root_pos, 30.0, {})
	check("glTF import maps the humanoid bones", int(res.get("mapped", 0)) >= 50, res.get("mapped", 0))
	var back := Synth.to_animation(res)
	var sk := H.build_skeleton()
	root.add_child(sk)
	CharScript.apply_animation_pose(sk, back, 1.2)
	var l := _segment_dir(sk, "LeftUpperArm", "LeftLowerArm")
	var r := _segment_dir(sk, "RightUpperArm", "RightLowerArm")
	check("glTF roundtrip keeps the pose (arms up)", l.y > 0.7 and r.y > 0.7, [l, r])
	sk.queue_free()
	ch.queue_free()
