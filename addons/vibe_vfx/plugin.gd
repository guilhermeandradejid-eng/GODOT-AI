@tool
extends EditorPlugin
## Vibe VFX: effect browser dock. Click a preset to add it to the scene
## (under the selected node, or at the center of the 3D view).

const VFXScript = preload("res://addons/vibe_vfx/vibe_vfx_3d.gd")
const Library = preload("res://addons/vibe_vfx/vfx_library.gd")
const Env = preload("res://addons/vibe_vfx/env_presets.gd")

var dock: VBoxContainer
var _style: OptionButton
var _color: ColorPickerButton
var _use_color: CheckBox
var _size: SpinBox


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "VFX"
	_build_ui()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _get_plugin_name() -> String:
	return "Vibe VFX"


func _build_ui() -> void:
	var row := HBoxContainer.new()
	dock.add_child(row)
	var sl := Label.new()
	sl.text = "Estilo"
	row.add_child(sl)
	_style = OptionButton.new()
	for s in VFXScript.STYLES:
		_style.add_item(s)
	_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_style)
	var row2 := HBoxContainer.new()
	dock.add_child(row2)
	_use_color = CheckBox.new()
	_use_color.text = "Cor"
	row2.add_child(_use_color)
	_color = ColorPickerButton.new()
	_color.color = Color(0.3, 0.6, 1.0)
	_color.custom_minimum_size = Vector2(40, 0)
	_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_color)
	var zl := Label.new()
	zl.text = "Tamanho"
	row2.add_child(zl)
	_size = SpinBox.new()
	_size.min_value = 0.1
	_size.max_value = 20.0
	_size.step = 0.1
	_size.value = 1.0
	row2.add_child(_size)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	dock.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var by_cat := {}
	for n in Library.names():
		var d := Library.get_preset(n)
		var cat := str(d.get("category", "custom"))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append([n, str(d.get("description", n))])
	for cat in by_cat:
		var h := Label.new()
		h.text = cat.capitalize()
		h.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		list.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 2
		list.add_child(grid)
		for item in by_cat[cat]:
			var b := Button.new()
			b.text = item[0]
			b.tooltip_text = item[1]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(_add_effect.bind(item[0]))
			grid.add_child(b)

	var env_label := Label.new()
	env_label.text = "Atmosfera:"
	dock.add_child(env_label)
	var env_grid := GridContainer.new()
	env_grid.columns = 4
	dock.add_child(env_grid)
	for k in Env.PRESETS:
		var b := Button.new()
		b.text = k
		b.tooltip_text = Env.PRESETS[k].description
		b.pressed.connect(_set_env.bind(k))
		env_grid.add_child(b)


func _style_name() -> String:
	return _style.get_item_text(_style.selected)


func _add_effect(preset_name: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("Vibe VFX: abra uma cena 3D primeiro.")
		return
	var parent: Node = root
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var at := Vector3.ZERO
	if not sel.is_empty() and sel[0] is Node3D and sel[0] != root:
		at = (sel[0] as Node3D).global_position
	else:
		var vp := EditorInterface.get_editor_viewport_3d(0)
		var cam: Camera3D = vp.get_camera_3d() if vp != null else null
		if cam != null:
			var center := vp.get_visible_rect().size * 0.5
			var from := cam.project_ray_origin(center)
			var dir := cam.project_ray_normal(center)
			var hit = null
			for t in get_tree().get_nodes_in_group(&"vibe_terrain"):
				if root.is_ancestor_of(t) and t.has_method("raycast"):
					hit = t.raycast(from, dir, 5000.0)
					break
			if hit == null:
				hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
			at = hit if hit != null else from + dir * 10.0
	var fx := VFXScript.new()
	fx.name = preset_name.capitalize().replace(" ", "")
	fx.preset = preset_name
	fx.style = _style_name()
	fx.size = _size.value
	if _use_color.button_pressed:
		fx.color = _color.color
	var def := Library.get_preset(preset_name)
	fx.follow_camera = bool(def.get("follow_camera", false))
	var ur := get_undo_redo()
	ur.create_action("VFX: adicionar " + preset_name)
	ur.add_do_method(parent, &"add_child", fx, true)
	ur.add_do_property(fx, &"owner", root)
	ur.add_do_property(fx, &"global_position", at)
	ur.add_do_reference(fx)
	ur.add_undo_method(parent, &"remove_child", fx)
	ur.commit_action()
	EditorInterface.edit_node(fx)


func _set_env(preset_name: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var env_node := root.find_child("VibeEnvironment", false, false) as WorldEnvironment
	var sun := root.find_child("VibeSun", false, false) as DirectionalLight3D
	var ur := get_undo_redo()
	ur.create_action("Atmosfera: " + preset_name)
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "VibeEnvironment"
		env_node.environment = Environment.new()
		ur.add_do_method(root, &"add_child", env_node, true)
		ur.add_do_property(env_node, &"owner", root)
		ur.add_do_reference(env_node)
		ur.add_undo_method(root, &"remove_child", env_node)
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "VibeSun"
		ur.add_do_method(root, &"add_child", sun, true)
		ur.add_do_property(sun, &"owner", root)
		ur.add_do_reference(sun)
		ur.add_undo_method(root, &"remove_child", sun)
	var style := str(root.get_meta("vibe_style", _style_name()))
	var new_env: Environment = env_node.environment.duplicate(true) if env_node.environment != null else Environment.new()
	var probe_env := WorldEnvironment.new()
	probe_env.environment = new_env
	var probe_sun := DirectionalLight3D.new()
	var overrides: Dictionary = env_node.get_meta("vibe_env_overrides", {}) if str(env_node.get_meta("vibe_preset", "")) == Env.resolve(preset_name) else {}
	Env.apply(probe_env, probe_sun, Env.resolve_settings(preset_name, overrides), style)
	ur.add_do_property(env_node, &"environment", new_env)
	ur.add_undo_property(env_node, &"environment", env_node.environment)
	for p in Env.SUN_PROPS:
		ur.add_do_property(sun, p, probe_sun.get(p))
		ur.add_undo_property(sun, p, sun.get(p))
	probe_env.set_meta("vibe_env_overrides", overrides)
	for m in ["vibe_preset", "vibe_style", "vibe_quality", "vibe_env_overrides"]:
		ur.add_do_method(env_node, &"set_meta", m, probe_env.get_meta(m))
		ur.add_undo_method(env_node, &"set_meta", m, env_node.get_meta(m, null))
	ur.commit_action()
	probe_env.free()
	probe_sun.free()
