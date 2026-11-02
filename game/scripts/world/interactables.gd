class_name Interactables
extends RefCounted
## Fábricas dos elementos de jogo. Cada classe interna é um Node3D autônomo.


# ============================================================================ semente
class WindSeed extends Node3D:
	var seed_id := "s1"
	var visual: Node3D
	var light: OmniLight3D
	var _t := 0.0
	var taken := false
	var hidden_until_revealed := false

	func _ready() -> void:
		add_to_group(&"seeds")
		visual = PropLib.make("seed")
		visual.scale = Vector3.ONE * 0.9
		add_child(visual)
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.5)
		light.light_energy = 1.6
		light.omni_range = 6.0
		light.shadow_enabled = false
		light.position.y = 0.6
		add_child(light)
		if hidden_until_revealed:
			visible = false

	func reveal() -> void:
		hidden_until_revealed = false
		visible = true
		scale = Vector3.ONE * 0.01
		create_tween().tween_property(self, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Fx.burst("seed", global_position, Color(0, 0, 0, 0), 0.7)
		Sfx.play_at("reveal", global_position)

	func _physics_process(delta: float) -> void:
		_t += delta
		visual.rotation.y += delta * 1.2
		visual.position.y = 0.4 + sin(_t * 2.0) * 0.15
		if taken or not visible or hidden_until_revealed:
			return
		for h in Game.heroes:
			if is_instance_valid(h) and h.global_position.distance_to(global_position + Vector3.UP * 0.5) < 1.5:
				_take(h)
				return

	func _take(h: Hero) -> void:
		taken = true
		Game.collect_seed(seed_id)
		Fx.burst("seed", global_position + Vector3.UP * 0.6)
		Fx.burst("ring_light", global_position + Vector3.UP * 0.3, Color(1, 0.85, 0.5), 1.6)
		Sfx.play_at("seed", global_position)
		Game.vibrate(80)
		h.visual.restart_state("celebrate" if h.hero_id == "juba" else "sit")
		h.visual.set_happy(1.0)
		get_tree().call_group(&"cameras", &"shake", 0.25)
		var n := Game.seeds.size()
		Game.show_toast("Semente de Sopro! (%d/%d)" % [n, Game.SEEDS_TOTAL], 3.0)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE * 1.6, 0.25)
		tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35)
		tw.tween_callback(func(): visible = false)
		await get_tree().create_timer(1.6, false).timeout
		h.visual.set_happy(0.0)
		if h.state == Hero.S.GROUND:
			h.visual.set_state("loco")


# ============================================================================ água-viva (trampolim)
class JellyPad extends AnimatableBody3D:
	var power := 15.0
	var bob := 0.6
	var drift := Vector3.ZERO
	var size := 1.6
	var _base := Vector3.ZERO
	var _t := 0.0
	var _mat: ShaderMaterial
	var _squash := 0.0
	var _tentacles: MeshInstance3D

	func _ready() -> void:
		add_to_group(&"bouncy")
		set_meta("bounce", power)
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		_base = position
		_t = randf() * 10.0
		var v := PropLib.make("jelly", ["jelly"])
		v.scale = Vector3.ONE * size
		add_child(v)
		_mat = (v.get_meta("materials") as Dictionary)["jelly"]
		_mat.set_shader_parameter("phase", randf() * 6.0)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.15 * size
		cyl.height = 0.5 * size
		cs.shape = cyl
		cs.position.y = 0.75 * size
		add_child(cs)
		_tentacles = _make_tentacles()
		add_child(_tentacles)

	func _make_tentacles() -> MeshInstance3D:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 7:
			var a := TAU * k / 7.0
			var r := 0.55 * size
			var base := Vector3(cos(a) * r, 0.15 * size, sin(a) * r)
			var n := 8
			for i in n:
				var t0 := float(i) / n
				var t1 := float(i + 1) / n
				var w0 := 0.09 * size * (1.0 - t0)
				var w1 := 0.09 * size * (1.0 - t1)
				var p0 := base + Vector3(0, -t0 * 2.4 * size, 0)
				var p1 := base + Vector3(0, -t1 * 2.4 * size, 0)
				var side := Vector3(-sin(a), 0, cos(a))
				var c0 := Color(1.0, 0.8, 0.95, t0)
				var c1 := Color(1.0, 0.8, 0.95, t1)
				st.set_color(c0); st.add_vertex(p0 - side * w0)
				st.set_color(c0); st.add_vertex(p0 + side * w0)
				st.set_color(c1); st.add_vertex(p1 + side * w1)
				st.set_color(c0); st.add_vertex(p0 - side * w0)
				st.set_color(c1); st.add_vertex(p1 + side * w1)
				st.set_color(c1); st.add_vertex(p1 - side * w1)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled, depth_draw_never;
void vertex() {
	float t = TIME * 2.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0;
	VERTEX.x += sin(t + COLOR.a * 5.0) * 0.25 * COLOR.a;
	VERTEX.z += cos(t * 0.8 + COLOR.a * 4.0) * 0.25 * COLOR.a;
}
void fragment() {
	ALBEDO = vec3(1.0, 0.7, 0.9) * (1.0 - COLOR.a) * 0.9;
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	func _physics_process(delta: float) -> void:
		_t += delta
		position = _base + Vector3(sin(_t * 0.4) * drift.x, sin(_t * 0.9) * bob, cos(_t * 0.35) * drift.z)
		_squash = move_toward(_squash, 0.0, delta * 2.5)
		_mat.set_shader_parameter("squash", sin(_squash * PI) * 0.6)

	func on_bounced(h: Hero) -> void:
		_squash = 1.0
		Fx.burst("sparkle", h.global_position, Color(1.0, 0.75, 0.95), 0.7)
		Game.vibrate(15)


# ============================================================================ flor-canhão
class FlowerCannon extends Node3D:
	var target := Vector3.ZERO
	var flight_time := 2.4
	var prop: Node3D
	var _petals: Array[Node3D] = []
	var _petal_rest: Array[Vector3] = []
	var _cool := 0.0
	var _busy := false

	func _ready() -> void:
		prop = PropLib.make("flower_cannon")
		add_child(prop)
		PropLib.add_collision(prop, "convex", ["Base"])
		for c in prop.get_children():
			if String(c.name).begins_with("petal_"):
				_petals.append(c)
				_petal_rest.append(c.rotation)
		_open(0.0, 0.0)

	func _open(amount: float, dur: float) -> void:
		for i in _petals.size():
			var p := _petals[i]
			var r := _petal_rest[i]
			# local Y rotation opens the petal outwards
			var to := Vector3(r.x, r.y + deg_to_rad(40.0) * amount, r.z)
			if dur <= 0.0:
				p.rotation = to
			else:
				create_tween().tween_property(p, "rotation", to, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _physics_process(delta: float) -> void:
		_cool = maxf(0.0, _cool - delta)
		if _busy or _cool > 0.0:
			return
		for h in Game.heroes:
			if not is_instance_valid(h) or h.is_remote or h.state == Hero.S.RIDE:
				continue
			var d: Vector3 = h.global_position - (global_position + Vector3.UP * 2.0)
			if Vector2(d.x, d.z).length() < 1.1 and absf(d.y) < 1.2:
				_fire(h)
				return

	func _fire(h: Hero) -> void:
		_busy = true
		h.set_state(Hero.S.CUTSCENE)
		h.teleport(global_position + Vector3.UP * 2.0)
		h.visual.set_state("fall" if h.hero_id == "caju" else "jump")
		_open(-0.8, 0.25)
		Sfx.play_at("flower_load", global_position)
		await get_tree().create_timer(0.45, false).timeout
		_open(1.6, 0.35)
		var g: float = h.cfg["gravity"]
		var start := h.global_position
		var dp := target - start
		var T := flight_time
		var v := Vector3(dp.x / T, (dp.y + 0.5 * g * T * T) / T, dp.z / T)
		h.launch(v, T * 0.45)
		Fx.burst("petals", global_position + Vector3.UP * 2.2)
		Fx.burst("ring_light", global_position + Vector3.UP * 2.2, Color(1, 0.7, 0.85), 1.2)
		Sfx.play_at("launch", global_position)
		Game.vibrate(40)
		await get_tree().create_timer(0.6, false).timeout
		_open(0.0, 0.6)
		_busy = false
		_cool = 0.8


# ============================================================================ fita de vento
class WindRibbon extends Node3D:
	var points: Array[Vector3] = []
	var speed := 15.0
	var curve: Curve3D
	var _mi: MeshInstance3D
	var _grab_cool := {}

	func _ready() -> void:
		curve = Curve3D.new()
		curve.bake_interval = 0.5
		for i in points.size():
			var p := points[i]
			var tin := Vector3.ZERO
			var tout := Vector3.ZERO
			if i > 0 and i < points.size() - 1:
				var tangent := (points[i + 1] - points[i - 1]) * 0.25
				tin = -tangent
				tout = tangent
			curve.add_point(p - global_position, tin, tout)
		_mi = MeshInstance3D.new()
		_mi.mesh = _strip()
		var m := ShaderMaterial.new()
		m.shader = preload("res://game/shaders/ribbon.gdshader")
		_mi.material_override = m
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)

	func length() -> float:
		return curve.get_baked_length()

	func transform_at(off: float) -> Transform3D:
		var t := curve.sample_baked_with_rotation(clampf(off, 0.0, length()), true, true)
		return global_transform * t

	func tangent_at(off: float) -> Vector3:
		var a := curve.sample_baked(clampf(off - 0.3, 0.0, length()))
		var b := curve.sample_baked(clampf(off + 0.3, 0.0, length()))
		return (global_transform.basis * (b - a)).normalized()

	func _strip() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var L := length()
		var n := int(L / 0.6) + 1
		var w := 0.75
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_v := 0.0
		for i in n + 1:
			var off := L * i / n
			var p := curve.sample_baked(off)
			var a := curve.sample_baked(clampf(off - 0.3, 0.0, L))
			var b := curve.sample_baked(clampf(off + 0.3, 0.0, L))
			var tan := (b - a).normalized()
			var side := tan.cross(Vector3.UP).normalized() * w
			var l := p - side
			var r := p + side
			if i > 0:
				st.set_uv(Vector2(0, prev_v)); st.add_vertex(prev_l)
				st.set_uv(Vector2(1, prev_v)); st.add_vertex(prev_r)
				st.set_uv(Vector2(1, off)); st.add_vertex(r)
				st.set_uv(Vector2(0, prev_v)); st.add_vertex(prev_l)
				st.set_uv(Vector2(1, off)); st.add_vertex(r)
				st.set_uv(Vector2(0, off)); st.add_vertex(l)
			prev_l = l
			prev_r = r
			prev_v = off
		return st.commit()

	func _physics_process(delta: float) -> void:
		for h in Game.heroes:
			if not is_instance_valid(h) or h.is_remote:
				continue
			var cd: float = _grab_cool.get(h, 0.0)
			if cd > 0.0:
				_grab_cool[h] = cd - delta
				continue
			if not (h.state in [Hero.S.AIR, Hero.S.GLIDE, Hero.S.GROUND, Hero.S.LAUNCH]):
				if h.state == Hero.S.GRIND and h.grind == self:
					_grab_cool[h] = 0.5
				continue
			var local: Vector3 = global_transform.affine_inverse() * (h.global_position as Vector3)
			var off := curve.get_closest_offset(local)
			if off > length() - 2.0:
				continue
			var cp := curve.sample_baked(off)
			if cp.distance_to(local + Vector3.UP * 0.2) < 1.0:
				h.start_grind(self, off)
				Fx.burst("ring_light", h.global_position, Color(0.4, 1.0, 0.9), 0.6)


# ============================================================================ corrente de ar
class Updraft extends Area3D:
	var radius := 3.0
	var height := 22.0
	var strength := 30.0
	var _parts: GPUParticles3D

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		monitoring = true
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = height
		cs.shape = cyl
		cs.position.y = height * 0.5
		add_child(cs)
		_parts = GPUParticles3D.new()
		_parts.amount = 48
		_parts.lifetime = 2.2
		_parts.visibility_aabb = AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2, height + 4, radius * 2))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = radius * 0.8
		pm.emission_ring_inner_radius = radius * 0.2
		pm.emission_ring_height = 0.5
		pm.direction = Vector3.UP
		pm.spread = 8.0
		pm.initial_velocity_min = 8.0
		pm.initial_velocity_max = 12.0
		pm.gravity = Vector3.ZERO
		pm.tangential_accel_min = 2.0
		pm.tangential_accel_max = 4.0
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.color = Color(1, 1, 1, 0.5)
		_parts.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 1.6)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_texture = preload("res://game/assets/textures/streak.png")
		m.albedo_color = Color(1.0, 0.95, 0.85, 0.6)
		m.vertex_color_use_as_albedo = true
		q.material = m
		_parts.draw_pass_1 = q
		_parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_parts)

	func _physics_process(_delta: float) -> void:
		for b in get_overlapping_bodies():
			if b is Hero:
				var h := b as Hero
				var k := 1.0 - clampf((h.global_position.y - global_position.y) / height, 0.0, 1.0) * 0.6
				h.add_updraft(strength * k)


# ============================================================================ placa de pressão
class PressurePlate extends Node3D:
	signal changed(pressed: bool)
	var heavy := false
	var group_id := "g1"
	var pressed := false
	var _prop: Node3D
	var _glow: ShaderMaterial
	var _on: Array = []

	func _ready() -> void:
		add_to_group(&"plates")
		_prop = PropLib.make("plate_heavy" if heavy else "plate", ["glow"])
		add_child(_prop)
		_glow = (_prop.get_meta("materials") as Dictionary)["glow"]
		_glow.set_shader_parameter("active", 0.25)
		PropLib.add_collision(_prop, "convex")

	func occupied_by(h) -> bool:
		return h in _on

	func _physics_process(_delta: float) -> void:
		_on.clear()
		var r := 1.35 if heavy else 1.0
		for h in Game.heroes:
			if not is_instance_valid(h):
				continue
			var d: Vector3 = h.global_position - global_position
			if Vector2(d.x, d.z).length() < r and d.y > -0.3 and d.y < 0.9 and h.state in [Hero.S.GROUND, Hero.S.SWIM, Hero.S.POUND, Hero.S.CUTSCENE]:
				if not heavy or h.is_heavy():
					_on.append(h)
		var now := not _on.is_empty()
		if now != pressed:
			pressed = now
			_glow.set_shader_parameter("active", 1.0 if now else 0.25)
			_prop.position.y = -0.08 if now else 0.0
			Sfx.play_at("plate_on" if now else "plate_off", global_position)
			changed.emit(now)
			if now and heavy:
				Fx.burst("dust_ring", global_position + Vector3.UP * 0.2, Color(0, 0, 0, 0), 1.2)
		if heavy and not now:
			for h in Game.heroes:
				if is_instance_valid(h) and h.hero_id == "juba" and h.global_position.distance_to(global_position) < 1.2 and h.state == Hero.S.GROUND:
					if Engine.get_physics_frames() % 120 == 0:
						Game.show_toast("Essa placa é pesada... precisa do Caju!", 2.0)


# ============================================================================ portão-flor
class FlowerGate extends Node3D:
	var group_id := "g1"
	var seed: Node3D
	var opened := false
	var _petals: Array[Node3D] = []
	var _rest: Array[Vector3] = []
	var _blocker: StaticBody3D

	func _ready() -> void:
		var prop := PropLib.make("gate_flower")
		add_child(prop)
		PropLib.add_collision(prop, "convex", ["BaseFlor"])
		for c in prop.get_children():
			if String(c.name).begins_with("gpetal_"):
				_petals.append(c)
				_rest.append(c.rotation)
		_blocker = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 2.0
		cyl.height = 3.6
		cs.shape = cyl
		cs.position.y = 2.2
		_blocker.add_child(cs)
		add_child(_blocker)
		await get_tree().process_frame
		for p in get_tree().get_nodes_in_group(&"plates"):
			if p.group_id == group_id:
				p.changed.connect(_check)

	func _check(_v: bool) -> void:
		if opened:
			return
		var all := true
		var count := 0
		for p in get_tree().get_nodes_in_group(&"plates"):
			if p.group_id == group_id:
				count += 1
				all = all and p.pressed
		if all and count > 0:
			open()

	func open() -> void:
		opened = true
		_blocker.queue_free()
		Sfx.play_at("gate_open", global_position)
		get_tree().call_group(&"cameras", &"shake", 0.3)
		Game.show_toast("O portão-flor se abriu!", 2.5)
		for i in _petals.size():
			var r := _rest[i]
			create_tween().tween_property(_petals[i], "rotation", Vector3(r.x, r.y + deg_to_rad(62.0), r.z), 1.4) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Fx.burst("petals", global_position + Vector3.UP * 2.0, Color(1.0, 0.85, 0.7), 1.5)
		if seed != null and seed.has_method("reveal"):
			seed.reveal()


# ============================================================================ portal (fenda)
class Portal extends Node3D:
	var exit_pos := Vector3.ZERO
	var exit_yaw := 0.0
	var _cool := {}

	func _ready() -> void:
		var prop := PropLib.make("portal")
		add_child(prop)
		PropLib.add_collision(prop, "trimesh")
		var disc := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.3, 3.3)
		disc.mesh = q
		var m := ShaderMaterial.new()
		m.shader = preload("res://game/shaders/portal.gdshader")
		disc.material_override = m
		disc.position = Vector3(0, 2.1, 0)
		disc.rotation.x = 0.0
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)
		var l := OmniLight3D.new()
		l.light_color = Color(0.7, 0.6, 1.0)
		l.light_energy = 1.5
		l.omni_range = 7.0
		l.position = Vector3(0, 2.1, 0.5)
		add_child(l)

	func _physics_process(delta: float) -> void:
		for h in Game.heroes:
			if not is_instance_valid(h) or h.is_remote:
				continue
			var cd: float = _cool.get(h, 0.0)
			if cd > 0.0:
				_cool[h] = cd - delta
				continue
			var local: Vector3 = global_transform.affine_inverse() * (h.global_position as Vector3)
			if absf(local.z) < 0.6 and absf(local.x) < 1.4 and local.y > -0.3 and local.y < 3.5:
				_cool[h] = 1.5
				_warp(h)

	func _warp(h: Hero) -> void:
		Fx.burst("wisp", h.global_position + Vector3.UP * 0.5, Color(0.7, 0.6, 1.0), 1.2)
		Sfx.play_at("portal", global_position)
		if h.rider != null:
			h.rider.teleport(exit_pos + Vector3.UP * 0.8, exit_yaw)
		h.teleport(exit_pos, exit_yaw)
		h.set_state(Hero.S.AIR)
		Fx.burst("wisp", exit_pos + Vector3.UP * 0.5, Color(0.7, 0.6, 1.0), 1.2)
		for p in get_tree().get_nodes_in_group(&"portals"):
			if p != self and p.global_position.distance_to(exit_pos) < 6.0:
				p._cool[h] = 1.5
		get_tree().call_group(&"cameras", &"snap_to_targets")


# ============================================================================ sinos de vento
class ChimePost extends Node3D:
	var _tubes: Array[Node3D] = []
	var _swing: Array[float] = []
	var _vel: Array[float] = []
	var _cool := 0.0
	var base_note := 0

	func _ready() -> void:
		var prop := PropLib.make("chime_post")
		add_child(prop)
		for c in prop.get_children():
			if String(c.name).begins_with("tube_"):
				_tubes.append(c)
				_swing.append(0.0)
				_vel.append(0.0)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.14
		cyl.height = 2.7
		cs.shape = cyl
		cs.position.y = 1.35
		body.add_child(cs)
		add_child(body)
		base_note = randi() % 3

	func _physics_process(delta: float) -> void:
		_cool = maxf(0.0, _cool - delta)
		for i in _tubes.size():
			_vel[i] += (-_swing[i] * 40.0 - _vel[i] * 1.6) * delta
			_swing[i] += _vel[i] * delta
			_tubes[i].rotation.x = _swing[i]
			_tubes[i].rotation.z = _swing[i] * 0.4 * sin(i * 1.3)
		if _cool > 0.0:
			return
		for h in Game.heroes:
			if is_instance_valid(h) and h.global_position.distance_to(global_position + Vector3.UP * 1.2) < 2.0:
				ring(h.velocity.length())
				return

	func ring(force := 4.0) -> void:
		_cool = 1.4
		for i in _tubes.size():
			_vel[i] += randf_range(1.0, 2.5) * clampf(force / 5.0, 0.5, 1.5) * (1 if i % 2 == 0 else -1)
		for k in 3:
			Sfx.play_chime(global_position + Vector3.UP * 2.2, base_note + k * 2 + randi() % 2)
			await get_tree().create_timer(0.16, false).timeout


# ============================================================================ totem (checkpoint)
class Totem extends Node3D:
	var active := false
	var _glow: ShaderMaterial

	func _ready() -> void:
		add_to_group(&"totems")
		var prop := PropLib.make("totem", ["glow"])
		add_child(prop)
		_glow = (prop.get_meta("materials") as Dictionary)["glow"]
		_glow.set_shader_parameter("active", 0.0)
		PropLib.add_collision(prop, "convex")

	func _physics_process(_delta: float) -> void:
		if active:
			return
		for h in Game.heroes:
			if is_instance_valid(h) and h.global_position.distance_to(global_position) < 2.6:
				activate()
				return

	func activate() -> void:
		for t in get_tree().get_nodes_in_group(&"totems"):
			if t != self and t.active:
				t.active = false
				t._glow.set_shader_parameter("active", 0.0)
		active = true
		_glow.set_shader_parameter("active", 1.0)
		var fwd := global_transform.basis.z
		Game.checkpoint = global_position + fwd * 2.0 + Vector3.UP * 0.6
		Fx.burst("ring_light", global_position + Vector3.UP * 1.2, Color(0.4, 1.0, 0.9), 1.2)
		Sfx.play_at("checkpoint", global_position)
		Game.show_toast("Ponto de retorno ativado", 1.6)
