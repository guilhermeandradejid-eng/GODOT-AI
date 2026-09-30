@tool
@icon("res://addons/vibe_motion/icons/character.svg")
class_name VibeCharacter3D
extends Node3D
## Humanoid character animated from text ("vibe motion").
##
## Builds its own skeleton (Godot's humanoid bone names, so animations also
## retarget to any model imported with the humanoid BoneMap) and a procedural
## body in the suite's art styles. Animations made with `motion.generate` live
## in the AnimationPlayer child. From game code:
## [codeblock]
## $Heroi.play("acenar")
## var anim: Animation = $Heroi.generate("pula duas vezes e comemora")
## $Heroi.play(anim.resource_name)
## [/codeblock]
## Root motion: animations move the "Root" bone. Set [member root_motion] to
## "extract" so this node travels instead (endless walk loops).

const H = preload("res://addons/vibe_motion/humanoid.gd")
const Mannequin = preload("res://addons/vibe_motion/mannequin.gd")
const Synth = preload("res://addons/vibe_motion/motion_synth.gd")
const TextParser = preload("res://addons/vibe_motion/motion_text.gd")
const GROUP := &"vibe_character"
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]

## Clothes preset: casual, mannequin, adventurer, athlete, ninja, robot,
## soldier, knight, wizard, zombie, astronaut, king.
@export var outfit := "casual":
	set(v):
		outfit = v
		_queue_rebuild()
## Per-part overrides, e.g. {"shirt": "red", "hair_style": "long", "hat": "cap"}.
@export var colors: Dictionary = {}:
	set(v):
		colors = v
		_queue_rebuild()
@export_enum("realistic", "stylized", "toon", "cel", "lowpoly") var style := "realistic":
	set(v):
		style = v if STYLES.has(v) else "realistic"
		_queue_rebuild()
@export_range(0.5, 3.0, 0.01, "suffix:m") var height := 1.8:
	set(v):
		height = clampf(v, 0.3, 5.0)
		_apply_height()
## Animation played when the scene runs (and previewed in the editor).
@export var animation := "":
	set(v):
		animation = v
		if is_inside_tree():
			_apply_animation()
@export var preview_in_editor := true:
	set(v):
		preview_in_editor = v
		if is_inside_tree():
			_apply_animation()
## >= 0 freezes the pose at this time (seconds) instead of playing.
@export var preview_time := -1.0:
	set(v):
		preview_time = v
		if is_inside_tree():
			_apply_animation()
## "animate": the Root bone moves (loops snap back) | "extract": this node
## travels with the root motion | "in_place": root motion is ignored.
@export_enum("animate", "extract", "in_place") var root_motion := "animate":
	set(v):
		root_motion = v
		_setup_root_motion()
@export var cast_shadows := true:
	set(v):
		cast_shadows = v
		if _body != null:
			_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if v else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _body: MeshInstance3D = null
var _rebuild_queued := false


func _ready() -> void:
	add_to_group(GROUP)
	ensure_nodes()
	_rebuild()
	_setup_root_motion()
	_apply_animation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		# Save the rest pose, not whatever frame the preview was showing.
		var sk := get_skeleton()
		if sk != null:
			sk.reset_bone_poses()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply_animation()


## Creates the Skeleton3D and AnimationPlayer children if missing. Call before
## adding the node to a scene so they can be owned (saved) by it.
func ensure_nodes() -> void:
	var sk := get_node_or_null(H.SKELETON_NAME) as Skeleton3D
	if sk == null:
		sk = H.build_skeleton()
		add_child(sk)
	elif sk.get_bone_count() != H.bone_names().size():
		H.apply_rest(sk)
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		add_child(player)
	if not player.has_animation_library(""):
		player.add_animation_library("", AnimationLibrary.new())
	_apply_height()


func get_skeleton() -> Skeleton3D:
	return get_node_or_null(H.SKELETON_NAME) as Skeleton3D


func get_animation_player() -> AnimationPlayer:
	return get_node_or_null("AnimationPlayer") as AnimationPlayer


## The generated body mesh (internal child of the skeleton).
func get_body() -> MeshInstance3D:
	return _body


func get_outfit() -> Dictionary:
	return Mannequin.resolve_outfit(outfit, colors)


func _apply_height() -> void:
	# The skeleton is always built at 1.8 m; height scales it, so the same
	# animations fit every character.
	var sk := get_skeleton()
	if sk != null:
		var k := height / H.HEIGHT
		sk.scale = Vector3(k, k, k)


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	var sk := get_skeleton()
	if sk == null:
		return
	if _body == null or not is_instance_valid(_body):
		_body = MeshInstance3D.new()
		_body.name = "Body"
		sk.add_child(_body, false, Node.INTERNAL_MODE_BACK)
	_body.mesh = Mannequin.build_mesh(get_outfit(), style)
	_body.skin = sk.create_skin_from_rest_transforms()
	_body.skeleton = NodePath("..")
	_body.material_override = Mannequin.make_material(style)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_root_motion() -> void:
	var player := get_animation_player()
	if player == null:
		return
	if root_motion == "animate":
		player.root_motion_track = NodePath()
	else:
		player.root_motion_track = NodePath(H.SKELETON_NAME + ":Root")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or root_motion != "extract":
		return
	var player := get_animation_player()
	if player == null or not player.is_playing():
		return
	var rot := player.get_root_motion_rotation()
	var pos := player.get_root_motion_position()
	var k := height / H.HEIGHT
	global_position += global_basis.get_rotation_quaternion() * (pos * k)
	quaternion = quaternion * rot


func _apply_animation() -> void:
	var player := get_animation_player()
	if player == null:
		return
	if animation == "" or not player.has_animation(animation):
		if Engine.is_editor_hint() and player.is_playing():
			player.stop()
		return
	# Autoplay only matters for the saved scene (at runtime play() below starts
	# it; setting it in a running game only prints a warning).
	if Engine.is_editor_hint() or not player.is_inside_tree():
		player.autoplay = animation
	if Engine.is_editor_hint():
		if preview_time >= 0.0:
			player.stop()
			pose_at(animation, preview_time)
		elif preview_in_editor:
			player.play(animation)
		else:
			player.stop()
			get_skeleton().reset_bone_poses()
		return
	if preview_time >= 0.0:
		pose_at(animation, preview_time)
	else:
		player.play(animation)


## Plays an animation of this character (crossfade in seconds).
func play(anim_name: String, blend: float = 0.25, speed: float = 1.0) -> void:
	var player := get_animation_player()
	if player == null or not player.has_animation(anim_name):
		push_warning("VibeCharacter3D: no animation '%s'" % anim_name)
		return
	player.play(anim_name, blend, speed)


## Adds (or replaces) an animation in the character's library.
func add_animation(anim: Animation, anim_name: String) -> void:
	ensure_nodes()
	var lib := get_animation_player().get_animation_library("")
	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)


func get_animation_names() -> PackedStringArray:
	var player := get_animation_player()
	return player.get_animation_list() if player != null else PackedStringArray()


## The animation called anim_name, or null.
func get_animation(anim_name: String) -> Animation:
	var player := get_animation_player()
	return player.get_animation(anim_name) if player != null and player.has_animation(anim_name) else null


## Generates an animation from a description (runtime or editor) and adds it
## to the library. options: name, seed, fps, in_place, loop.
func generate(text: String, options: Dictionary = {}) -> Animation:
	var plan := TextParser.parse(text)
	var synth := Synth.new()
	var result := synth.generate(plan.segments, options)
	var anim := Synth.to_animation(result)
	var anim_name := str(options.get("name", ""))
	if anim_name == "":
		anim_name = TextParser.normalize(text).substr(0, 40).replace(" ", "_")
	anim.resource_name = anim_name
	anim.set_meta("vibe_text", text)
	add_animation(anim, anim_name)
	return anim


## Shows the pose of an animation at a given time (no AnimationPlayer needed).
func pose_at(anim_name: String, time: float) -> void:
	var player := get_animation_player()
	var sk := get_skeleton()
	if player == null or sk == null or not player.has_animation(anim_name):
		return
	apply_animation_pose(sk, player.get_animation(anim_name), time)


## Samples every bone track of `anim` at `time` onto a skeleton.
static func apply_animation_pose(sk: Skeleton3D, anim: Animation, time: float) -> void:
	for tr in anim.get_track_count():
		var path := anim.track_get_path(tr)
		if path.get_subname_count() == 0:
			continue
		var bone := sk.find_bone(str(path.get_subname(0)))
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, time))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, anim.position_track_interpolate(tr, time))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(bone, anim.scale_track_interpolate(tr, time))


## Approximate radius for screenshots framing.
func get_effect_radius() -> float:
	return height * 0.75


func get_effect_focus_height() -> float:
	return height * 0.55
