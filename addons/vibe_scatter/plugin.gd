@tool
extends EditorPlugin
## Vibe Scatter: "Vegetação" dock. One click adds a preset to the terrain of
## the edited scene (or the palette's natural vegetation); everything goes
## through the scatter.* commands (undoable).

const Presets = preload("res://addons/vibe_scatter/scatter_presets.gd")

var dock: VBoxContainer
var _density: SpinBox
var _status: Label


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Vegetação"
	var title := Label.new()
	title.text = "Vegetação e objetos"
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55))
	dock.add_child(title)
	var row := HBoxContainer.new()
	dock.add_child(row)
	var dl := Label.new()
	dl.text = "Densidade"
	row.add_child(dl)
	_density = SpinBox.new()
	_density.min_value = 0.1
	_density.max_value = 4.0
	_density.step = 0.1
	_density.value = 1.0
	_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_density)
	var auto := Button.new()
	auto.text = "Automático (pela paleta do terreno)"
	auto.pressed.connect(func(): _run("scatter.auto", {"density": _density.value}))
	dock.add_child(auto)
	var grid := GridContainer.new()
	grid.columns = 2
	dock.add_child(grid)
	for k in Presets.PRESETS:
		var b := Button.new()
		b.text = k
		b.tooltip_text = Presets.PRESETS[k].desc
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _run("scatter.add", {"preset": k, "density": _density.value}))
		grid.add_child(b)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(_status)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _get_plugin_name() -> String:
	return "Vibe Scatter"


func _run(cmd: String, args: Dictionary) -> void:
	var core = Engine.get_meta(&"vibe_core_plugin") if Engine.has_meta(&"vibe_core_plugin") else null
	if core == null:
		_status.text = "Ative o plugin Vibe Core."
		return
	var r: Dictionary = await core.registry.execute(cmd, args, core.make_context("scatter_dock"))
	if r.get("ok", false):
		var res: Dictionary = r.result
		_status.text = "%s: %s instâncias" % [cmd, str(res.get("instances", ""))]
	else:
		_status.text = "Erro: " + str(r.get("error", ""))
