@tool
extends EditorPlugin
## Vibe Motion: "Motion" dock. Describe a movement in a sentence and the
## selected character (VibeCharacter3D) gets the animation; everything runs
## through the same commands as the terminal (motion.*).

const CharScript = preload("res://addons/vibe_motion/vibe_character_3d.gd")
const Mannequin = preload("res://addons/vibe_motion/mannequin.gd")
const Synth = preload("res://addons/vibe_motion/motion_synth.gd")

const EXAMPLES := [
	"anda, acena e depois senta",
	"corre em círculo e pula duas vezes",
	"dança feliz por 6 segundos",
	"anda como um zumbi",
	"soca 3 vezes e chuta",
	"lança magia",
	"deita, levanta e comemora",
]

var dock: VBoxContainer
var _text: LineEdit
var _outfit: OptionButton
var _style: OptionButton
var _list: ItemList
var _status: Label
var _busy := false


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Motion"
	_build_ui()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	EditorInterface.get_selection().selection_changed.connect(_refresh_list)


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_refresh_list):
		EditorInterface.get_selection().selection_changed.disconnect(_refresh_list)
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _get_plugin_name() -> String:
	return "Vibe Motion"


func _build_ui() -> void:
	var title := Label.new()
	title.text = "Animação por texto"
	title.add_theme_color_override("font_color", Color(0.56, 0.82, 1.0))
	dock.add_child(title)
	_text = LineEdit.new()
	_text.placeholder_text = "ex.: anda, acena e depois senta"
	_text.text_submitted.connect(func(_t): _generate())
	dock.add_child(_text)
	var ex := OptionButton.new()
	ex.add_item("Exemplos…")
	for e in EXAMPLES:
		ex.add_item(e)
	ex.item_selected.connect(func(i):
		if i > 0:
			_text.text = EXAMPLES[i - 1]
		ex.select(0))
	dock.add_child(ex)
	var gen := Button.new()
	gen.text = "Gerar animação"
	gen.pressed.connect(_generate)
	dock.add_child(gen)
	var row := HBoxContainer.new()
	dock.add_child(row)
	_outfit = OptionButton.new()
	for o in Mannequin.OUTFITS:
		_outfit.add_item(o)
	_outfit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outfit.tooltip_text = "Roupa do novo personagem"
	row.add_child(_outfit)
	_style = OptionButton.new()
	_style.add_item("estilo da cena")
	for s in CharScript.STYLES:
		_style.add_item(s)
	row.add_child(_style)
	var add := Button.new()
	add.text = "Adicionar personagem"
	add.pressed.connect(_add_character)
	dock.add_child(add)
	var lbl := Label.new()
	lbl.text = "Animações (duplo clique toca):"
	dock.add_child(lbl)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_play_item)
	dock.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "%d ações entendidas. Terminal: python3 tools/vibe.py motion.generate text=\"...\"" % Synth.CLIPS.size()
	dock.add_child(_status)


func _core():
	return Engine.get_meta(&"vibe_core_plugin") if Engine.has_meta(&"vibe_core_plugin") else null


func _selected_character() -> Node:
	for n in EditorInterface.get_selection().get_selected_nodes():
		var cur: Node = n
		while cur != null:
			if cur.is_in_group(CharScript.GROUP):
				return cur
			cur = cur.get_parent()
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for n in get_tree().get_nodes_in_group(CharScript.GROUP):
		if root.is_ancestor_of(n):
			return n
	return null


func _run(cmd: String, args: Dictionary) -> Dictionary:
	var core = _core()
	if core == null:
		_status.text = "Ative o plugin Vibe Core."
		return {}
	var result: Dictionary = await core.registry.execute(cmd, args, core.make_context("motion_dock"))
	if not result.get("ok", false):
		_status.text = "Erro: " + str(result.get("error", ""))
	return result


func _generate() -> void:
	var text := _text.text.strip_edges()
	if text == "" or _busy:
		return
	_busy = true
	_status.text = "Gerando…"
	var args := {"text": text}
	var ch := _selected_character()
	if ch != null:
		args["character"] = str(ch.name)
	var r := await _run("motion.generate", args)
	_busy = false
	if r.get("ok", false):
		var res: Dictionary = r.result
		var clips: Array = []
		for s in res.get("segments", []):
			clips.append(str(s.get("clip", "")))
		_status.text = "%s (%.1fs): %s" % [res.get("name", ""), float(res.get("duration", 0.0)), " → ".join(clips)]
		if res.has("not_understood"):
			_status.text += "\nNão entendi: " + ", ".join(res.not_understood)
	_refresh_list()


func _add_character() -> void:
	var args := {"outfit": _outfit.get_item_text(_outfit.selected), "name": "Personagem"}
	if _style.selected > 0:
		args["style"] = _style.get_item_text(_style.selected)
	var r := await _run("motion.character", args)
	if r.get("ok", false):
		_status.text = "Personagem adicionado: " + str(r.result.get("name", ""))
	_refresh_list()


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	var ch := _selected_character()
	if ch == null:
		return
	for a in ch.get_animation_names():
		_list.add_item(a)


func _play_item(index: int) -> void:
	var ch := _selected_character()
	if ch == null:
		return
	await _run("motion.play", {"character": str(ch.name), "animation": _list.get_item_text(index)})
