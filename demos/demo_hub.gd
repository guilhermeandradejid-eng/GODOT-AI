extends Control
## Demo hub (main scene): a card per demo from res://demos/demos.json
## (written by tools/build_demos.py). Click a card to open the demo;
## inside a demo, M comes back here.

const MANIFEST := "res://demos/demos.json"

var _grid: GridContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.065, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Vibe Suite — demos"
	title.add_theme_font_size_override("font_size", 34)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Mundos gerados pelos plugins de terreno, grama e VFX a partir de receitas/prompts (tools/build_demos.py). Clique para explorar."
	sub.modulate = Color(0.75, 0.82, 0.95)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)

	var demos := _load_manifest()
	if demos.is_empty():
		var empty := Label.new()
		empty.text = "Nenhuma demo encontrada. Gere com:  python3 tools/build_demos.py"
		_grid.add_child(empty)
	for d in demos:
		_grid.add_child(_card(d))
	get_viewport().size_changed.connect(_relayout)
	_relayout()


func _relayout() -> void:
	var w := get_viewport_rect().size.x
	_grid.columns = 1 if w < 760 else (2 if w < 1100 else 3)


func _load_manifest() -> Array:
	if not FileAccess.file_exists(MANIFEST):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		parsed = parsed.get("demos", [])
	return parsed if parsed is Array else []


func _card(d: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(340, 250)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.13, 0.18)
	normal.set_corner_radius_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.17, 0.21, 0.3)
	hover.border_color = Color(0.55, 0.75, 1.0)
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", hover)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_top = 8
	box.offset_right = -8
	box.offset_bottom = -8
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tpath := str(d.get("thumb", ""))
	if tpath != "" and ResourceLoader.exists(tpath):
		thumb.texture = load(tpath)
	box.add_child(thumb)
	var name_label := Label.new()
	name_label.text = str(d.get("title", d.get("name", "?")))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var info := Label.new()
	info.text = str(d.get("subtitle", ""))
	info.modulate = Color(0.7, 0.78, 0.9)
	info.add_theme_font_size_override("font_size", 13)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(info)

	var scene := str(d.get("scene", ""))
	button.pressed.connect(func() -> void:
		if ResourceLoader.exists(scene):
			get_tree().change_scene_to_file(scene))
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()
