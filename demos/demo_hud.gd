extends CanvasLayer
## Overlay of the demo scenes: title, how the scene was made and the controls.
## M returns to the demo hub, H hides the panel.

const HUB := "res://demos/demo_hub.tscn"

@export var title := ""
@export_multiline var subtitle := ""
@export_multiline var prompt := ""

var _panel: PanelContainer


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(18, -18)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	var t := Label.new()
	t.text = title if title != "" else str(get_parent().name)
	t.add_theme_font_size_override("font_size", 26)
	box.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.modulate = Color(0.75, 0.85, 1.0)
		box.add_child(s)
	if prompt != "":
		var p := Label.new()
		p.text = "vibe: \"%s\"" % prompt
		p.modulate = Color(1.0, 0.86, 0.55)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size.x = 460
		box.add_child(p)
	var help := Label.new()
	help.text = "Botão direito + mouse: olhar   WASD: mover   E/Q: subir/descer   Shift: rápido\nM: menu das demos   H: esconder este painel"
	help.modulate = Color(1, 1, 1, 0.7)
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_H:
				_panel.visible = not _panel.visible
			KEY_M:
				if ResourceLoader.exists(HUB):
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					get_tree().change_scene_to_file(HUB)
