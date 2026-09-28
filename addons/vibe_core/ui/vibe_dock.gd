@tool
extends VBoxContainer
## "Vibe" dock: shows the live bridge status, a console to type commands or
## natural-language prompts, and a log of every command (including the ones
## sent by Claude Code from the terminal), so you always see what is happening.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

var plugin = null  # the vibe_core EditorPlugin (untyped: we access script members)

var _status_label: Label
var _input: LineEdit
var _log: RichTextLabel
var _busy := false


func _ready() -> void:
	name = "Vibe"
	custom_minimum_size = Vector2(220, 260)
	add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	add_child(header)
	_status_label = Label.new()
	_status_label.text = "Bridge: ..."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	header.add_child(_status_label)
	var copy_btn := Button.new()
	copy_btn.text = "Copiar"
	copy_btn.tooltip_text = "Copia o comando para testar a conexão pelo terminal."
	copy_btn.pressed.connect(_copy_info)
	header.add_child(copy_btn)

	var hint := Label.new()
	hint.text = "Comando ou descrição (vibe):"
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)

	var row := HBoxContainer.new()
	add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "ex.: ilha tropical à noite  |  terrain.sculpt op=raise position=[0,0] radius=12"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _run_input())
	row.add_child(_input)
	var run_btn := Button.new()
	run_btn.text = "▶"
	run_btn.tooltip_text = "Executar"
	run_btn.pressed.connect(_run_input)
	row.add_child(run_btn)

	var quick := HFlowContainer.new()
	add_child(quick)
	for pair in [["Status", "status"], ["Ajuda", "help"], ["Screenshot", "screenshot"], ["Salvar", "scene.save"]]:
		var b := Button.new()
		b.text = pair[0]
		b.flat = false
		b.pressed.connect(_run_command.bind(pair[1], {}))
		quick.add_child(b)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.fit_content = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 160)
	add_child(_log)
	_append("[color=#8ab]Vibe Suite pronta. Claude Code pode enviar comandos pelo terminal (tools/vibe.py ou MCP).[/color]")


func set_bridge_status(listening: bool, port: int) -> void:
	if _status_label == null:
		return
	if listening:
		_status_label.text = "● Bridge ativa em 127.0.0.1:%d" % port
		_status_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
	else:
		_status_label.text = "○ Bridge desligada"
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))


func on_command_executed(entry: Dictionary) -> void:
	var color := "#7d7" if entry.get("ok", false) else "#f77"
	var src := str(entry.get("source", ""))
	var line := "[color=#888]%s[/color] [color=#9bd]%s[/color] [color=%s]%s[/color]" % [entry.get("time", ""), src, color, entry.get("cmd", "")]
	var args_text := JSON.stringify(entry.get("args", {}))
	if args_text.length() > 140:
		args_text = args_text.left(140) + "…"
	if args_text != "{}":
		line += " [color=#aaa]%s[/color]" % args_text.replace("[", "[lb]")
	if not entry.get("ok", false) and str(entry.get("error", "")) != "":
		line += "\n    [color=#f99]%s[/color]" % str(entry.error).replace("[", "[lb]")
	_append(line)


func _append(bbcode: String) -> void:
	if _log != null:
		_log.append_text(bbcode + "\n")


func _copy_info() -> void:
	var port := 8423
	if plugin != null and plugin.get("bridge") != null:
		port = plugin.bridge.port
	DisplayServer.clipboard_set("python3 tools/vibe.py status   # bridge 127.0.0.1:%d" % port)
	_append("[color=#8ab]Copiado para a área de transferência.[/color]")


func _run_input() -> void:
	var text := _input.text.strip_edges()
	if text == "" or _busy:
		return
	_input.text = ""
	var parsed := parse_command_line(text, plugin.registry if plugin != null else null)
	await _run_command(parsed[0], parsed[1])


func _run_command(cmd: String, args: Dictionary) -> void:
	if plugin == null or _busy:
		return
	_busy = true
	var ctx = plugin.make_context("dock")
	var result: Dictionary = await plugin.registry.execute(cmd, args, ctx)
	_busy = false
	if result.get("ok", false):
		var summary := JSON.stringify(result.get("result", {}))
		if summary.length() > 600:
			summary = summary.left(600) + "…"
		_append("   [color=#bbb]%s[/color]" % summary.replace("[", "[lb]"))


## Parses `command key=value key2=[1,2]` or treats the whole text as a vibe prompt.
static func parse_command_line(text: String, registry) -> Array:
	var first := text.get_slice(" ", 0)
	if registry == null or not registry.has_command(first):
		return ["vibe", {"prompt": text}]
	var args := {}
	var rest := text.substr(first.length()).strip_edges()
	for token in _split_args(rest):
		var eq := (token as String).find("=")
		if eq <= 0:
			continue
		var key := (token as String).substr(0, eq).strip_edges()
		var raw := (token as String).substr(eq + 1).strip_edges()
		if raw.length() >= 2 and ((raw.begins_with("\"") and raw.ends_with("\"")) or (raw.begins_with("'") and raw.ends_with("'"))):
			args[key] = raw.substr(1, raw.length() - 2)
			continue
		var parsed = JSON.parse_string(raw)
		args[key] = parsed if parsed != null or raw == "null" else raw
	return [first, args]


static func _split_args(text: String) -> Array:
	var out: Array = []
	var cur := ""
	var depth := 0
	var quote := ""
	for i in text.length():
		var ch := text[i]
		if quote != "":
			cur += ch
			if ch == quote:
				quote = ""
			continue
		if ch == "\"" or ch == "'":
			quote = ch
			cur += ch
		elif ch == "[" or ch == "{":
			depth += 1
			cur += ch
		elif ch == "]" or ch == "}":
			depth -= 1
			cur += ch
		elif ch == " " and depth == 0:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out
