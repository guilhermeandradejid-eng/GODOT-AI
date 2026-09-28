@tool
extends EditorPlugin
## Vibe Terrain: visual sculpting/painting of VibeTerrain3D in the 3D viewport.

const TerrainScript = preload("res://addons/vibe_terrain/vibe_terrain_3d.gd")
const Ops = preload("res://addons/vibe_terrain/terrain_ops.gd")
const Generator = preload("res://addons/vibe_terrain/terrain_generator.gd")
const Dock = preload("res://addons/vibe_terrain/editor/terrain_dock.gd")

const DAB_RATE := 30.0

var dock = null
var terrain: Node = null
var _hit = null
var _stroke := false
var _stroke_before := {}
var _stroke_tool := ""
var _flatten_height := 0.0
var _dab_accum := 0.0
var _last_dab = null
var _dirty_rect := Rect2i()


func _enter_tree() -> void:
	dock = Dock.new()
	dock.plugin = self
	dock.action_requested.connect(_on_action)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	_hide_brush()
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _get_plugin_name() -> String:
	return "Vibe Terrain"


func _handles(object: Object) -> bool:
	return object is TerrainScript


func _edit(object: Object) -> void:
	if terrain != null and is_instance_valid(terrain) and terrain != object:
		terrain.hide_brush()
	terrain = object if object is TerrainScript else null
	if dock != null:
		dock.set_terrain(terrain)


func _make_visible(visible: bool) -> void:
	if not visible:
		_hide_brush()


func on_tool_changed() -> void:
	if dock.tool == "none":
		_hide_brush()


func _hide_brush() -> void:
	if terrain != null and is_instance_valid(terrain):
		terrain.hide_brush()


func _process(delta: float) -> void:
	if not _stroke or terrain == null or not is_instance_valid(terrain) or _hit == null:
		return
	_dab_accum += delta
	var interval := 1.0 / DAB_RATE
	var applied := false
	while _dab_accum >= interval:
		_dab_accum -= interval
		_apply_dab(_hit, interval)
		applied = true
	if applied:
		if _is_sculpt_tool():
			terrain.notify_heights_changed(_dirty_rect, false)
		else:
			terrain.notify_splat_changed(_dirty_rect)
		_dirty_rect = Rect2i()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if terrain == null or not is_instance_valid(terrain) or dock == null or dock.tool == "none":
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_update_hit(camera, (event as InputEventMouseMotion).position)
		if _stroke and _hit != null and _last_dab != null:
			# Fill gaps when the mouse moves fast.
			var step: float = maxf(dock.brush_size * 0.3, 0.2)
			var from: Vector3 = _last_dab
			var dist := from.distance_to(_hit)
			if dist > step:
				var n := int(dist / step)
				for i in range(1, n + 1):
					_apply_dab(from.lerp(_hit, float(i) / float(n + 1)), 1.0 / DAB_RATE)
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_update_hit(camera, mb.position)
				if _hit == null:
					return AFTER_GUI_INPUT_PASS
				_begin_stroke(mb)
				return AFTER_GUI_INPUT_STOP
			elif _stroke:
				_end_stroke()
				return AFTER_GUI_INPUT_STOP
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_BRACKETLEFT:
			dock.set_brush_size(dock.brush_size / 1.2)
			_refresh_cursor()
			return AFTER_GUI_INPUT_STOP
		if k.keycode == KEY_BRACKETRIGHT:
			dock.set_brush_size(dock.brush_size * 1.2)
			_refresh_cursor()
			return AFTER_GUI_INPUT_STOP
		if k.keycode == KEY_ESCAPE:
			if _stroke:
				_end_stroke()
			dock.set_tool("none")
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _update_hit(camera: Camera3D, screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	_hit = terrain.raycast(from, dir, camera.far)
	_refresh_cursor()


func _refresh_cursor() -> void:
	if terrain == null or not is_instance_valid(terrain):
		return
	if _hit == null or dock.tool == "none":
		terrain.hide_brush()
		return
	var color := Color(0.35, 0.8, 1.0) if dock.tool == "paint" else Color(1.0, 0.72, 0.2)
	if Input.is_key_pressed(KEY_SHIFT):
		color = Color(0.6, 1.0, 0.6)
	elif Input.is_key_pressed(KEY_CTRL):
		color = Color(1.0, 0.4, 0.4)
	var scale_x: float = terrain.global_transform.basis.get_scale().x
	terrain.show_brush(terrain.to_local(_hit), dock.brush_size / maxf(scale_x, 0.0001), color)


func _is_sculpt_tool() -> bool:
	return _stroke_tool != "paint"


func _begin_stroke(mb: InputEventMouseButton) -> void:
	_stroke = true
	_stroke_before = terrain.make_snapshot()
	_stroke_tool = dock.tool
	if mb.shift_pressed and _stroke_tool != "paint":
		_stroke_tool = "smooth"
	_flatten_height = terrain.data.sample(terrain.world_to_texel(_hit).x, terrain.world_to_texel(_hit).y)
	_dab_accum = 0.0
	_last_dab = null
	_apply_dab(_hit, 1.0 / DAB_RATE)
	if _is_sculpt_tool():
		terrain.notify_heights_changed(_dirty_rect, false)
	else:
		terrain.notify_splat_changed(_dirty_rect)
	_dirty_rect = Rect2i()


func _apply_dab(world: Vector3, dt: float) -> void:
	var data = terrain.data
	var t: Vector2 = terrain.world_to_texel(world)
	var scale_x: float = terrain.global_transform.basis.get_scale().x
	var radius: float = dock.brush_size / (data.cell_size * maxf(scale_x, 0.0001))
	var tool_name := _stroke_tool
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	var rect := Rect2i()
	if tool_name == "paint":
		var layer: int = 0 if ctrl else dock.paint_layer
		rect = Ops.paint(data, layer, t, radius, clampf(dock.strength * dt * 8.0, 0.0, 1.0), dock.hardness)
	else:
		if ctrl and tool_name == "raise":
			tool_name = "lower"
		elif ctrl and tool_name == "lower":
			tool_name = "raise"
		var amount: float = dock.strength
		match tool_name:
			"raise", "lower":
				amount = dock.strength * dt * maxf(dock.brush_size, 4.0) * 1.2
			"noise":
				amount = dock.strength * dt * 6.0
			_:
				amount = clampf(dock.strength * dt * 6.0, 0.0, 1.0)
		rect = Ops.sculpt(data, tool_name, t, radius, amount, {"hardness": dock.hardness, "height": _flatten_height, "step": maxf(dock.brush_size * 0.25, 1.0), "seed": 11})
	_dirty_rect = rect if _dirty_rect.size.x == 0 else _dirty_rect.merge(rect)
	_last_dab = world


func _end_stroke() -> void:
	_stroke = false
	_last_dab = null
	if terrain == null or not is_instance_valid(terrain):
		return
	if _is_sculpt_tool():
		terrain.notify_heights_changed(Rect2i(), true)
	else:
		terrain.notify_splat_changed()
	_commit_undo("Terreno: " + _stroke_tool, _stroke_before)


func _commit_undo(label: String, before: Dictionary) -> void:
	var ur := get_undo_redo()
	ur.create_action(label, UndoRedo.MERGE_DISABLE, terrain)
	ur.add_do_method(terrain, &"apply_snapshot", terrain.make_snapshot())
	ur.add_undo_method(terrain, &"apply_snapshot", before)
	ur.commit_action(false)


func _on_action(action: String, params: Dictionary) -> void:
	if terrain == null or not is_instance_valid(terrain):
		push_warning("Vibe Terrain: selecione um VibeTerrain3D primeiro.")
		return
	var before: Dictionary = terrain.make_snapshot()
	var data = terrain.data
	var rules: Dictionary = terrain.get_palette_rules()
	var wl: float = terrain.water_level if (terrain.water_enabled or not terrain.lakes.is_empty() or not terrain.rivers.is_empty()) else -INF
	match action:
		"generate":
			Generator.generate(data, params)
			terrain.clear_water_features()
			Ops.auto_paint(data, rules, wl)
		"palette":
			terrain.apply_palette(params.name)
			Ops.auto_paint(data, terrain.get_palette_rules(), wl)
		"auto_paint":
			Ops.auto_paint(data, rules, wl)
		"erode":
			Ops.hydraulic_erosion(data, int(data.resolution * data.resolution * 0.3), randi() % 1000, 1.0)
			Ops.auto_paint(data, rules, wl)
		"smooth_all":
			var c := Vector2(data.resolution, data.resolution) * 0.5
			Ops.sculpt(data, "smooth", c, data.resolution, 0.6, {"hardness": 1.0})
		"toggle_water":
			terrain.water_enabled = not terrain.water_enabled
		"river":
			var pts := Ops.auto_path(data, "river", randi() % 10000, terrain.water_level if terrain.water_enabled else -INF)
			var r := Ops.carve_path(data, pts, 7.0 / data.cell_size, 2.5, "river", terrain.water_level if terrain.water_enabled else -INF)
			var local_pts := PackedVector2Array()
			for p in r.points:
				var lp: Vector3 = terrain.texel_to_local(p)
				local_pts.append(Vector2(lp.x, lp.z))
			terrain.add_river(local_pts, PackedFloat32Array(r.levels), 7.0)
			Ops.auto_paint(data, rules, terrain.water_level)
	terrain.notify_heights_changed()
	terrain.notify_splat_changed()
	dock.set_terrain(terrain)
	_commit_undo("Terreno: " + action, before)
