extends SceneTree
## Records one animated shot of a scene with Godot's movie writer (used by
## tools/make_trailer.py, but works on its own too):
##
##   godot --path . --resolution 1280x720 --fixed-fps 24 --write-movie shot.avi \
##         --script res://tools/trailer_shot.gd -- '<shot json>'
##
## Shot keys:
##   scene     res://demos/ilha_tropical.tscn
##   fps       frames per second (same as --fixed-fps, default 24)
##   duration  seconds of camera move (after `warmup` frames that settle
##             particles, grass and shaders; trim those frames when editing)
##   camera    one of
##     {"keys": [{"t": 0, "pos": P, "look": P, "fov": 55}, ...]}   P = [x,y,z], "Node",
##               {"node": "Name", "offset": [x,y,z]} or {"ground": [x,z], "up": h}
##     {"orbit": P, "radius": 8, "height": 2.5, "from": 20, "to": 70, "focus": 1.0, "fov": 55,
##      "base": "facing" | "camera"}   (angles relative to the node's front / the scene camera)
##     {"from_camera": "VibeCamera", "move": [right, up, forward], "pan": deg, "tilt": deg}
##   timelapse [["day", 0.0], ["sunset", 0.55], ["night", 1.0]]  (atmosphere over the shot)
##   env       {"preset": "night", ...}   (applied once)
##   loop_animations  true: characters loop their animation; "anim_offset" 0..1
##   play      ["VfxName", ...] restarts these effects when the move starts
##   hide      node names to hide (default: DemoHUD)

const Env = preload("res://addons/vibe_vfx/env_presets.gd")

var shot: Dictionary = {}
var world: Node
var cam: Camera3D
var frame := 0
var warmup := 16
var total := 0
var fps := 24.0
var keys: Array = []
var orbit: Dictionary = {}
var played := false


var ready_to_record := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var parsed = JSON.parse_string(args[0])
		if parsed is Dictionary:
			shot = parsed
	fps = float(shot.get("fps", 24.0))  # must match --fixed-fps
	warmup = int(shot.get("warmup", 16))
	total = warmup + int(ceil(float(shot.get("duration", 4.0)) * fps))
	# The root enters the tree after _initialize: build the shot deferred.
	_setup.call_deferred()


func _setup() -> void:
	var packed: PackedScene = load(str(shot.get("scene", "")))
	if packed == null:
		push_error("trailer_shot: cannot load scene %s" % shot.get("scene", ""))
		quit(1)
		return
	world = packed.instantiate()
	root.add_child(world)
	for n in shot.get("hide", ["DemoHUD"]):
		var h := world.find_child(str(n), true, false)
		if h != null and "visible" in h:
			h.set("visible", false)
	cam = Camera3D.new()
	cam.far = 12000.0
	cam.near = 0.1
	root.add_child(cam)
	cam.current = true
	if shot.get("env", null) is Dictionary:
		_apply_env(shot.env)
	_setup_camera()
	_update_camera(0.0)
	ready_to_record = true


func _process(_delta: float) -> bool:
	if not ready_to_record:
		return false
	var t := clampf(float(frame - warmup) / float(maxi(total - warmup, 1)), 0.0, 1.0)
	if frame == 2:
		_setup_characters()
	if frame >= warmup and not played:
		played = true
		for n in shot.get("play", []):
			var fx := world.find_child(str(n), true, false)
			if fx != null and fx.has_method("play"):
				fx.play()
	_update_camera(t)
	if shot.get("timelapse", null) is Array:
		_timelapse(t)
	frame += 1
	return frame > total


# --- camera -------------------------------------------------------------------------------

func _resolve(p: Variant) -> Vector3:
	if p is Array and p.size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	if p is String:
		var n := world.find_child(p, true, false)
		if n is Node3D:
			return (n as Node3D).global_position
	if p is Dictionary:
		if p.has("node"):
			var base := _resolve(str(p.node))
			var o: Array = p.get("offset", [0, 0, 0])
			return base + Vector3(float(o[0]), float(o[1]), float(o[2]))
		if p.has("ground"):
			var g: Array = p.ground
			return Vector3(float(g[0]), _ground(float(g[0]), float(g[1])) + float(p.get("up", 2.0)), float(g[1]))
	return Vector3.ZERO


func _ground(x: float, z: float) -> float:
	for n in world.find_children("*", "Node3D", true, false):
		if n.has_method("get_height_at_world"):
			return n.get_height_at_world(Vector3(x, 0, z))
	return 0.0


func _scene_camera(name: String) -> Camera3D:
	var c := world.find_child(name, true, false)
	if c is Camera3D:
		return c
	for n in world.find_children("*", "Camera3D", true, false):
		return n
	return null


func _setup_camera() -> void:
	var c: Dictionary = shot.get("camera", {})
	if c.has("keys"):
		for k in c.keys:
			keys.append({"t": float(k.get("t", 0.0)), "pos": _resolve(k.pos), "look": _resolve(k.look), "fov": float(k.get("fov", 55.0))})
		keys.sort_custom(func(a, b): return a.t < b.t)
	elif c.has("orbit"):
		orbit = c.duplicate()
		orbit["center"] = _resolve(c.orbit)
		# Angles are relative to: "facing" = the node's front (characters look
		# at +Z), "camera" = the direction the scene camera sees it from.
		var base := 0.0
		var node := world.find_child(str(c.orbit), true, false) if c.orbit is String else null
		match str(c.get("base", "")):
			"facing":
				if node is Node3D:
					base = rad_to_deg((node as Node3D).global_rotation.y)
			"camera":
				var sc := _scene_camera("VibeCamera")
				if sc != null:
					var d: Vector3 = sc.global_position - (orbit.center as Vector3)
					base = rad_to_deg(atan2(d.x, d.z))
		orbit["from"] = float(c.get("from", 0.0)) + base
		orbit["to"] = float(c.get("to", 60.0)) + base
	else:
		var sc := _scene_camera(str(c.get("from_camera", "VibeCamera")))
		var start := sc.global_transform if sc != null else Transform3D(Basis(), Vector3(0, 30, 60))
		var fov := float(c.get("fov", sc.fov if sc != null else 55.0))
		var mv: Array = c.get("move", [0, 0, 10])
		var b := start.basis
		var end_pos := start.origin + b.x * float(mv[0]) + b.y * float(mv[1]) - b.z * float(mv[2])
		var end_basis := b.rotated(Vector3.UP, deg_to_rad(-float(c.get("pan", 0.0))))
		end_basis = end_basis.rotated(end_basis.x, deg_to_rad(float(c.get("tilt", 0.0))))
		var dist := float(c.get("look_distance", 40.0))
		keys = [
			{"t": 0.0, "pos": start.origin, "look": start.origin - b.z * dist, "fov": fov},
			{"t": 1.0, "pos": end_pos, "look": end_pos - end_basis.z * dist, "fov": float(c.get("fov_end", fov))},
		]


func _update_camera(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t) if bool(shot.get("ease", true)) else t
	if not orbit.is_empty():
		var a := deg_to_rad(lerpf(float(orbit.get("from", 0.0)), float(orbit.get("to", 60.0)), e))
		var ctr: Vector3 = orbit.center
		var r := lerpf(float(orbit.get("radius", 8.0)), float(orbit.get("radius_end", orbit.get("radius", 8.0))), e)
		var h := lerpf(float(orbit.get("height", 2.5)), float(orbit.get("height_end", orbit.get("height", 2.5))), e)
		cam.global_position = ctr + Vector3(sin(a) * r, h, cos(a) * r)
		cam.fov = float(orbit.get("fov", 55.0))
		cam.look_at(ctr + Vector3.UP * float(orbit.get("focus", 1.0)), Vector3.UP)
		return
	if keys.is_empty():
		return
	var i := 0
	while i < keys.size() - 2 and e > float(keys[i + 1].t):
		i += 1
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[mini(i + 1, keys.size() - 1)]
	var span := maxf(float(k1.t) - float(k0.t), 0.0001)
	var u := clampf((e - float(k0.t)) / span, 0.0, 1.0)
	var pos: Vector3 = (k0.pos as Vector3).lerp(k1.pos, u)
	var look: Vector3 = (k0.look as Vector3).lerp(k1.look, u)
	cam.global_position = pos
	cam.fov = lerpf(float(k0.fov), float(k1.fov), u)
	if not pos.is_equal_approx(look):
		cam.look_at(look, Vector3.UP)


# --- characters, atmosphere ---------------------------------------------------------------------

func _setup_characters() -> void:
	var offset := float(shot.get("anim_offset", -1.0))
	var i := 0
	for ch in world.get_tree().get_nodes_in_group(&"vibe_character"):
		var player: AnimationPlayer = ch.get_animation_player() if ch.has_method("get_animation_player") else null
		if player == null or str(ch.animation) == "":
			continue
		ch.preview_time = -1.0
		var anim := player.get_animation(str(ch.animation))
		if anim != null and bool(shot.get("loop_animations", false)):
			anim.loop_mode = Animation.LOOP_LINEAR
		player.play(str(ch.animation))
		if offset >= 0.0 and anim != null:
			player.seek(fmod(offset + i * 0.17, 1.0) * anim.length, true)
		i += 1


func _env_nodes() -> Array:
	var we: WorldEnvironment = null
	var sun: DirectionalLight3D = null
	for n in world.find_children("*", "WorldEnvironment", true, false):
		we = n
	for n in world.find_children("*", "DirectionalLight3D", true, false):
		if sun == null or n.name == "VibeSun":
			sun = n
	return [we, sun]


func _style() -> String:
	return str(world.get_meta("vibe_style", "realistic"))


func _apply_env(settings: Dictionary) -> void:
	var nodes := _env_nodes()
	if nodes[0] == null or nodes[1] == null:
		return
	var s := Env.resolve_settings(str(settings.get("preset", "day")), settings)
	Env.apply(nodes[0], nodes[1], s, _style())


## Blends two atmosphere presets (numbers and colors) for a day/night timelapse.
func _timelapse(t: float) -> void:
	var stops: Array = shot.timelapse
	var i := 0
	while i < stops.size() - 2 and t > float(stops[i + 1][1]):
		i += 1
	var a: Array = stops[i]
	var b: Array = stops[mini(i + 1, stops.size() - 1)]
	var u := clampf((t - float(a[1])) / maxf(float(b[1]) - float(a[1]), 0.0001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var sa := Env.resolve_settings(str(a[0]), {})
	var sb := Env.resolve_settings(str(b[0]), {})
	var mixed := {}
	for k in sa:
		var va = sa[k]
		var vb = sb.get(k, va)
		if (va is float or va is int) and (vb is float or vb is int):
			mixed[k] = lerpf(float(va), float(vb), u)
		elif va is String and str(va).begins_with("#") and vb is String and str(vb).begins_with("#"):
			mixed[k] = "#" + Color.html(va).lerp(Color.html(vb), u).to_html(false)
		else:
			mixed[k] = va if u < 0.5 else vb
	if not sa.has("sky_mid") or not sb.has("sky_mid"):
		mixed.erase("sky_mid")
	# The sun sweeps continuously across the sky; the moon takes over at night.
	mixed["moon"] = 1.0 if u > 0.5 and float(sb.get("moon", 0.0)) > 0.5 else float(sa.get("moon", 0.0)) if u <= 0.5 else float(sb.get("moon", 0.0))
	mixed["grade"] = sa.get("grade", []) if u < 0.5 else sb.get("grade", [])
	var nodes := _env_nodes()
	if nodes[0] != null and nodes[1] != null:
		Env.apply(nodes[0], nodes[1], mixed, _style())
