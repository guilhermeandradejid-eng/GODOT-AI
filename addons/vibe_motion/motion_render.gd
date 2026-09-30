@tool
extends RefCounted
## Renders animation previews in a neutral studio (its own World3D):
##   sheet    - a contact sheet with N poses (camera follows the character)
##   trail    - one picture with every pose along the path (chronophotography)
##   sequence - numbered PNG frames (turn them into GIF/WebP with tools/)
## Needs a window (the terminal client uses xvfb-run when there is none).

const H = preload("res://addons/vibe_motion/humanoid.gd")
const CharScript = preload("res://addons/vibe_motion/vibe_character_3d.gd")

const VIEWS := {
	"three_quarter": Vector3(0.72, 0.3, 1.0),
	"front": Vector3(0.0, 0.22, 1.0),
	"side": Vector3(1.0, 0.18, 0.05),
	"back": Vector3(-0.3, 0.3, -1.0),
	"top": Vector3(0.05, 1.6, 0.6),
}

const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base : source_color = vec4(0.5, 0.52, 0.56, 1.0);
uniform vec4 line : source_color = vec4(0.36, 0.38, 0.43, 1.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wp.xz - 0.5) - 0.5) / fwidth(wp.xz);
	float l = 1.0 - clamp(min(g.x, g.y) * 0.7, 0.0, 1.0);
	vec2 g2 = abs(fract(wp.xz * 4.0 - 0.5) - 0.5) / fwidth(wp.xz * 4.0);
	float l2 = (1.0 - clamp(min(g2.x, g2.y), 0.0, 1.0)) * 0.25;
	float fade = smoothstep(18.0, 6.0, length(wp.xz - CAMERA_POSITION_WORLD.xz));
	vec3 c = mix(base.rgb, line.rgb, max(l, l2) * fade);
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""


static func _make_studio(vp: SubViewport, opts: Dictionary) -> Dictionary:
	var root := Node3D.new()
	vp.add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.45, 0.6)
	mat.sky_horizon_color = Color(0.78, 0.8, 0.84)
	mat.ground_horizon_color = Color(0.7, 0.71, 0.74)
	mat.ground_bottom_color = Color(0.4, 0.4, 0.42)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 30.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.85, 1.0)
	root.add_child(fill)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor.mesh = pm
	var fm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	fm.shader = sh
	floor.material_override = fm
	floor.visible = bool(opts.get("floor", true))
	root.add_child(floor)
	var cam := Camera3D.new()
	cam.fov = float(opts.get("fov", 32.0))
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	return {"root": root, "env": env, "floor": floor, "cam": cam, "sun": sun}


static func _make_character(opts: Dictionary) -> Node3D:
	var ch = CharScript.new()
	ch.name = "Preview"
	ch.outfit = str(opts.get("outfit", "mannequin"))
	var colors = opts.get("colors", {})
	if colors is Dictionary:
		ch.colors = colors
	ch.style = str(opts.get("style", "realistic"))
	ch.preview_in_editor = false
	ch.ensure_nodes()
	return ch


## Root trajectory of an animation (sampled).
static func root_path(anim: Animation, samples: int = 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	var tr := anim.find_track(NodePath(H.SKELETON_NAME + ":Root"), Animation.TYPE_POSITION_3D)
	for i in samples:
		var t := anim.length * float(i) / float(maxi(samples - 1, 1))
		out.append(anim.position_track_interpolate(tr, t) if tr >= 0 else Vector3.ZERO)
	return out


static func _look(cam: Camera3D, target: Vector3, dir: Vector3, dist: float) -> void:
	cam.global_position = target + dir.normalized() * dist
	cam.look_at(target, Vector3.UP)


## Renders a preview. opts: mode (sheet|trail|sequence), frames, columns,
## width, height (per frame), view, outfit, style, colors, path, label.
static func render(host: Node, anim: Animation, opts: Dictionary) -> Dictionary:
	var mode := str(opts.get("mode", "sheet"))
	var n := clampi(int(opts.get("frames", 6)), 1, 240)
	var w := clampi(int(opts.get("width", 320 if mode == "sheet" else 1280)), 64, 3840)
	var h := clampi(int(opts.get("height", 420 if mode == "sheet" else 720)), 64, 2160)
	var view: Vector3 = VIEWS.get(str(opts.get("view", "three_quarter")), VIEWS.three_quarter)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(w, h)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var studio := _make_studio(vp, opts)
	var ch: Node3D = _make_character(opts)
	(studio.root as Node3D).add_child(ch)
	var sk: Skeleton3D = ch.get_skeleton()
	var cam: Camera3D = studio.cam
	var body_h := 1.9 * float(opts.get("height_m", 1.8)) / 1.8
	var times: Array = []
	for i in n:
		times.append(anim.length * float(i) / float(maxi(n - 1, 1)) if n > 1 else 0.0)
	var was_low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var frames: Array = []
	var path_pts := root_path(anim, 32)
	var box := AABB(path_pts[0], Vector3.ZERO)
	for p in path_pts:
		box = box.expand(p)
	var fit_h := (body_h * 0.5 + 0.25) / tan(deg_to_rad(cam.fov * 0.5))
	if mode == "trail":
		var span := maxf(box.size.x, box.size.z)
		var aspect := float(w) / float(h)
		var dist := maxf(fit_h * 1.05, (span * 0.5 + 0.8) / (tan(deg_to_rad(cam.fov * 0.5)) * aspect) * 1.1)
		_look(cam, box.get_center() + Vector3(0, body_h * 0.45, 0), view, dist)
		# Background with the floor only, then each pose over it.
		ch.visible = false
		await _frames(2)
		var base := vp.get_texture().get_image()
		base.convert(Image.FORMAT_RGBA8)
		ch.visible = true
		(studio.floor as Node3D).visible = false
		(studio.env as Environment).background_mode = Environment.BG_CLEAR_COLOR
		vp.transparent_bg = true
		var body: MeshInstance3D = ch.get_body()
		for i in n:
			CharScript.apply_animation_pose(sk, anim, times[i])
			if body != null and body.material_override is ShaderMaterial:
				var k := float(i) / float(maxi(n - 1, 1))
				(body.material_override as ShaderMaterial).set_shader_parameter("tint", Color(0.42, 0.48, 0.62).lerp(Color.WHITE, k * k))
			await _frames(2)
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			base.blend_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
		frames = [base]
	else:
		for i in n:
			CharScript.apply_animation_pose(sk, anim, times[i])
			var rp: Vector3 = sk.get_bone_pose_position(sk.find_bone("Root")) * sk.scale
			var hips_y: float = sk.get_bone_pose_position(sk.find_bone("Hips")).y * sk.scale.y
			_look(cam, rp + Vector3(0, clampf(hips_y * 0.95, 0.35, 2.0), 0), view, fit_h * 1.15)
			await _frames(2)
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			frames.append(img)
	OS.low_processor_usage_mode = was_low
	host.remove_child(vp)
	vp.queue_free()
	var path := str(opts.get("path", ""))
	var out := {"mode": mode, "frames": n, "times": times}
	if mode == "sequence":
		var dir := path.get_basename()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var files: Array = []
		for i in frames.size():
			var fp := dir.path_join("frame_%03d.png" % i)
			(frames[i] as Image).save_png(fp)
			files.append(fp)
		out["dir"] = dir
		out["files"] = files.size()
		out["fps"] = float(n) / maxf(anim.length, 0.001)
		return out
	var sheet: Image
	if mode == "trail":
		sheet = frames[0]
	else:
		var cols := clampi(int(opts.get("columns", 0)), 0, 32)
		if cols <= 0:
			cols = n if n <= 8 else int(ceil(sqrt(float(n) * 1.6)))
		var rows := int(ceil(float(n) / float(cols)))
		sheet = Image.create(cols * w, rows * h, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.1, 0.1, 0.12))
		for i in frames.size():
			sheet.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		out["columns"] = cols
		out["rows"] = rows
	var err := sheet.save_png(path)
	if err != OK:
		return {"error": "could not save PNG %s (%s)" % [path, error_string(err)]}
	out["path"] = path
	out["file"] = ProjectSettings.globalize_path(path)
	out["size"] = [sheet.get_width(), sheet.get_height()]
	return out


static func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
