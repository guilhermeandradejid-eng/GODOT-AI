@tool
extends VBoxContainer
## "Terreno" dock: brush tools, brush settings, layer picker, generators.

const Generator = preload("res://addons/vibe_terrain/terrain_generator.gd")
const Palettes = preload("res://addons/vibe_terrain/terrain_palettes.gd")

signal action_requested(action: String, params: Dictionary)

const TOOLS := [
	["none", "Selecionar", "Ferramentas desligadas (seleção normal)"],
	["raise", "Elevar", "Levanta o terreno (Ctrl = rebaixar)"],
	["lower", "Rebaixar", "Abaixa o terreno (Ctrl = elevar)"],
	["smooth", "Suavizar", "Suaviza relevos (atalho: Shift enquanto esculpe)"],
	["flatten", "Nivelar", "Nivela na altura onde o clique começou"],
	["noise", "Ruído", "Adiciona irregularidades naturais"],
	["terrace", "Degraus", "Cria patamares (estilo cânion)"],
	["paint", "Pintar", "Pinta a camada selecionada (Ctrl = camada 0)"],
]

var plugin = null
var tool := "none"
var brush_size := 10.0
var strength := 0.5
var hardness := 0.35
var paint_layer := 0

var _title: Label
var _tool_buttons := {}
var _layer_buttons: Array = []
var _preset: OptionButton
var _palette: OptionButton
var _seed: SpinBox
var _size_slider: HSlider
var _terrain_ok := false


func _ready() -> void:
	name = "Terreno"
	custom_minimum_size = Vector2(200, 0)
	add_theme_constant_override("separation", 5)
	_title = Label.new()
	_title.text = "Selecione um VibeTerrain3D"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.tooltip_text = t[2]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tool.bind(t[0]))
		grid.add_child(b)
		_tool_buttons[t[0]] = b
	_tool_buttons["none"].button_pressed = true

	_size_slider = _slider("Tamanho (m)", 1.0, 120.0, 0.5, brush_size, func(v): brush_size = v)
	_slider("Força", 0.01, 1.0, 0.01, strength, func(v): strength = v)
	_slider("Dureza", 0.0, 0.95, 0.05, hardness, func(v): hardness = v)

	var layers_label := Label.new()
	layers_label.text = "Camada para pintar:"
	add_child(layers_label)
	var layers_row := GridContainer.new()
	layers_row.columns = 2
	add_child(layers_row)
	var lgroup := ButtonGroup.new()
	for i in 4:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = lgroup
		b.text = "%d" % i
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func(): paint_layer = i)
		layers_row.add_child(b)
		_layer_buttons.append(b)
	_layer_buttons[0].button_pressed = true

	add_child(HSeparator.new())
	var gen_label := Label.new()
	gen_label.text = "Gerar relevo:"
	add_child(gen_label)
	_preset = OptionButton.new()
	for p in Generator.PRESETS.keys():
		_preset.add_item(p)
	_preset.selected = Generator.PRESETS.keys().find("hills")
	add_child(_preset)
	var seed_row := HBoxContainer.new()
	add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 999999
	_seed.value = 1
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "Seed aleatória"
	dice.pressed.connect(func(): _seed.value = randi() % 100000)
	seed_row.add_child(dice)
	_button("Gerar terreno", func(): action_requested.emit("generate", {"preset": _preset.get_item_text(_preset.selected), "seed": int(_seed.value)}))

	var pal_label := Label.new()
	pal_label.text = "Bioma / paleta:"
	add_child(pal_label)
	_palette = OptionButton.new()
	for p in Palettes.names():
		_palette.add_item(p)
	add_child(_palette)
	_button("Aplicar paleta", func(): action_requested.emit("palette", {"name": _palette.get_item_text(_palette.selected)}))

	var row := HFlowContainer.new()
	add_child(row)
	for a in [["Auto-pintar", "auto_paint"], ["Erosão", "erode"], ["Suavizar tudo", "smooth_all"], ["Água", "toggle_water"], ["Rio", "river"]]:
		var b := Button.new()
		b.text = a[0]
		b.pressed.connect(func(): action_requested.emit(a[1], {}))
		row.add_child(b)

	var help := Label.new()
	help.text = "Clique e arraste no terreno.\nShift = suavizar · Ctrl = inverter · [ ] = tamanho · Esc = soltar ferramenta"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(1, 1, 1, 0.7)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	set_terrain(null)


func _slider(label: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(78, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.text = str(value)
	v.custom_minimum_size = Vector2(36, 0)
	row.add_child(v)
	s.value_changed.connect(func(x):
		v.text = str(snappedf(x, step))
		on_change.call(x))
	return s


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	add_child(b)
	return b


func _set_tool(t: String) -> void:
	tool = t
	if plugin != null:
		plugin.on_tool_changed()


func set_tool(t: String) -> void:
	if _tool_buttons.has(t):
		_tool_buttons[t].button_pressed = true
	_set_tool(t)


func set_brush_size(v: float) -> void:
	brush_size = clampf(v, 1.0, 120.0)
	if _size_slider != null:
		_size_slider.value = brush_size


func set_terrain(terrain: Node) -> void:
	_terrain_ok = terrain != null
	if _title == null:
		return
	if terrain == null:
		_title.text = "Selecione um VibeTerrain3D para esculpir e pintar."
	else:
		var info: Dictionary = terrain.get_info()
		_title.text = "%s · %dm · %s" % [terrain.name, int(info.get("size", 0)), info.get("palette", "")]
		var layers: Array = terrain.get_layers()
		for i in 4:
			var l = layers[i]
			_layer_buttons[i].text = "%d %s" % [i, l.name if l != null else ""]
			if l != null:
				_layer_buttons[i].add_theme_color_override("font_color", l.color_b.lerp(Color.WHITE, 0.2))
		var idx := Palettes.names().find(str(info.get("palette", "")))
		if idx >= 0:
			_palette.selected = idx
	for k in _tool_buttons:
		(_tool_buttons[k] as Button).disabled = not _terrain_ok and k != "none"
