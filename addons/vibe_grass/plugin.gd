@tool
extends EditorPlugin
## Vibe Grass: paint/erase grass density directly in the 3D viewport.

const GrassScript = preload("res://addons/vibe_grass/vibe_grass_3d.gd")
const Presets = preload("res://addons/vibe_grass/grass_presets.gd")

var dock: VBoxContainer
var grass: Node = null
var _enabled_btn: Button
var _erase_btn: Button
var _size := 6.0
var _density := 1.0
var _strength := 0.6
var _painting := false
var _before := {}
var _hit = null
var _preset_opt: OptionButton
var _style_opt: OptionButton
var _title: Label


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Grama"
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	_hide_cursor()
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _get_plugin_name() -> String:
	return "Vibe Grass"


func _handles(object: Object) -> bool:
	return object is GrassScript


func _edit(object: Object) -> void:
	_hide_cursor()
	grass = object if object is GrassScript else null
	_refresh()


func _make_visible(visible: bool) -> void:
	if not visible:
		_hide_cursor()


func _build_dock() -> void:
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(_title)
	var row := HBoxContainer.new()
	dock.add_child(row)
	_enabled_btn = Button.new()
	_enabled_btn.text = "Pintar grama"
	_enabled_btn.toggle_mode = true
	_enabled_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_enabled_btn)
	_erase_btn = Button.new()
	_erase_btn.text = "Borracha"
	_erase_btn.toggle_mode = true
	_erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_erase_btn)
	_add_slider("Tamanho (m)", 0.5, 60.0, 0.5, _size, func(v): _size = v)
	_add_slider("Densidade", 0.0, 1.0, 0.05, _density, func(v): _density = v)
	_add_slider("Força", 0.05, 1.0, 0.05, _strength, func(v): _strength = v)
	var pl := Label.new()
	pl.text = "Tipo de grama:"
	dock.add_child(pl)
	_preset_opt = OptionButton.new()
	for p in Presets.names():
		_preset_opt.add_item(p)
	_preset_opt.item_selected.connect(func(i): _set_prop(&"preset", _preset_opt.get_item_text(i)))
	dock.add_child(_preset_opt)
	var sl := Label.new()
	sl.text = "Estilo visual:"
	dock.add_child(sl)
	_style_opt = OptionButton.new()
	for s in GrassScript.STYLES:
		_style_opt.add_item(s)
	_style_opt.item_selected.connect(func(i): _set_prop(&"style", _style_opt.get_item_text(i)))
	dock.add_child(_style_opt)
	var fill := Button.new()
	fill.text = "Preencher automático (regras)"
	fill.pressed.connect(_auto_fill)
	dock.add_child(fill)
	var clear := Button.new()
	clear.text = "Limpar"
	clear.pressed.connect(func(): _with_undo("Grama: limpar", func(): grass.clear()))
	dock.add_child(clear)
	var help := Label.new()
	help.text = "Clique e arraste sobre o terreno. Ctrl = apagar."
	help.modulate = Color(1, 1, 1, 0.7)
	help.add_theme_font_size_override("font_size", 11)
	dock.add_child(help)
	_refresh()


func _add_slider(label: String, min_v: float, max_v: float, step: float, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	dock.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)


func _refresh() -> void:
	if _title == null:
		return
	if grass == null:
		_title.text = "Selecione um VibeGrass3D para pintar grama."
		return
	var info: Dictionary = grass.get_info()
	_title.text = "%s · %s · %s · cobertura %d%%" % [grass.name, info.preset, info.style, int(info.coverage * 100.0)]
	var pi := Presets.names().find(info.preset)
	if pi >= 0:
		_preset_opt.selected = pi
	var si := GrassScript.STYLES.find(info.style)
	if si >= 0:
		_style_opt.selected = si


func _set_prop(prop: StringName, value: Variant) -> void:
	if grass == null:
		return
	var ur := get_undo_redo()
	ur.create_action("Grama: " + str(prop), UndoRedo.MERGE_DISABLE, grass)
	ur.add_do_property(grass, prop, value)
	ur.add_undo_property(grass, prop, grass.get(prop))
	ur.commit_action()
	_refresh()


func _with_undo(label: String, action: Callable) -> void:
	if grass == null:
		return
	var before: Dictionary = grass.make_snapshot()
	action.call()
	var ur := get_undo_redo()
	ur.create_action(label, UndoRedo.MERGE_DISABLE, grass)
	ur.add_do_method(grass, &"apply_snapshot", grass.make_snapshot())
	ur.add_undo_method(grass, &"apply_snapshot", before)
	ur.commit_action(false)
	_refresh()


func _auto_fill() -> void:
	var rules := {"density": _density, "max_slope": 36.0, "patchiness": 0.3}
	var t: Node = grass.get_terrain() if grass != null else null
	if t != null and t.has_method("get_layers"):
		rules["layer"] = 0
	_with_undo("Grama: preencher", func(): grass.fill(rules))


func _terrain() -> Node:
	return grass.get_terrain() if grass != null else null


func _hide_cursor() -> void:
	var t := _terrain()
	if t != null and is_instance_valid(t):
		t.hide_brush()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if grass == null or not is_instance_valid(grass) or not (_enabled_btn.button_pressed or _erase_btn.button_pressed):
		return AFTER_GUI_INPUT_PASS
	var t := _terrain()
	if event is InputEventMouse:
		var pos: Vector2 = (event as InputEventMouse).position
		var from := camera.project_ray_origin(pos)
		var dir := camera.project_ray_normal(pos)
		if t != null:
			_hit = t.raycast(from, dir, camera.far)
		else:
			var plane := Plane(Vector3.UP, grass.global_position.y)
			_hit = plane.intersects_ray(from, dir)
		if t != null:
			if _hit == null:
				t.hide_brush()
			else:
				var erase := _erase_btn.button_pressed or Input.is_key_pressed(KEY_CTRL)
				t.show_brush(t.to_local(_hit), _size / maxf(t.global_transform.basis.get_scale().x, 0.0001), Color(1.0, 0.4, 0.3) if erase else Color(0.4, 1.0, 0.4))
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _hit != null:
			_painting = true
			_before = grass.make_snapshot()
			_dab()
			return AFTER_GUI_INPUT_STOP
		elif not event.pressed and _painting:
			_painting = false
			var ur := get_undo_redo()
			ur.create_action("Grama: pintar", UndoRedo.MERGE_DISABLE, grass)
			ur.add_do_method(grass, &"apply_snapshot", grass.make_snapshot())
			ur.add_undo_method(grass, &"apply_snapshot", _before)
			ur.commit_action(false)
			_refresh()
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _painting and _hit != null:
		_dab()
	return AFTER_GUI_INPUT_PASS


func _dab() -> void:
	var erase := _erase_btn.button_pressed or Input.is_key_pressed(KEY_CTRL)
	grass.paint(_hit, _size, 0.0 if erase else _density, _strength)
