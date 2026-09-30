@tool
extends RefCounted
## Terminal/bridge commands for text-to-animation (motion.*).

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const H = preload("res://addons/vibe_motion/humanoid.gd")
const Mannequin = preload("res://addons/vibe_motion/mannequin.gd")
const Synth = preload("res://addons/vibe_motion/motion_synth.gd")
const TextParser = preload("res://addons/vibe_motion/motion_text.gd")
const CharScript = preload("res://addons/vibe_motion/vibe_character_3d.gd")
const Render = preload("res://addons/vibe_motion/motion_render.gd")
const Retarget = preload("res://addons/vibe_motion/motion_retarget.gd")
const Kimodo = preload("res://addons/vibe_motion/motion_kimodo.gd")

const ANIM_DIR := "res://animations"
const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]
const SHOT_DIR := "res://.vibe/screenshots"


func register(reg) -> void:
	var outfits := ", ".join(Mannequin.OUTFITS.keys())
	reg.add("motion.generate", {
		"description": "Text -> animation (PT/EN): 'anda devagar, acena duas vezes e senta', 'a person runs in a circle then jumps'. " +
			"Understands ~50 actions (walk, run, jump, wave, dance, sit, lie, fight, magic, push-ups...), moods (feliz, triste, cansado, bravo, confiante, com medo), " +
			"styles (robô, zumbi, bêbado, ninja, cartoon, elegante, idoso, mancando), counts, durations, speed and directions. " +
			"Saves res://animations/<name>.res and adds it to the character (VibeCharacter3D). backend: procedural (built in) or kimodo (kimodo.cpp server).",
		"args": {
			"text": {"type": "string", "required": true, "description": "What the character does (Portuguese or English)."},
			"name": {"type": "string", "description": "Animation name (default: from the text)."},
			"character": {"type": "string", "description": "VibeCharacter3D to receive it (default: the only/first one; created if missing and create=true)."},
			"create": {"type": "boolean", "default": true, "description": "Add a character when the scene has none."},
			"backend": {"type": "string", "default": "auto", "enum": ["auto", "procedural", "kimodo"], "description": "auto = kimodo when a server is configured (motion.backend url=...) and answers, else procedural."},
			"play": {"type": "boolean", "default": true, "description": "Make it the character's current animation."},
			"loop": {"type": "string", "default": "auto", "enum": ["auto", "true", "false"], "description": "Loop (auto: single cyclic actions loop)."},
			"in_place": {"type": "boolean", "default": false, "description": "Remove root motion (walk cycles for game controllers)."},
			"seed": {"type": "integer", "default": 0, "description": "Variation seed."},
			"fps": {"type": "number", "default": 30.0, "description": "Keyframe rate."},
			"path": {"type": "string", "description": "Where to save (default res://animations/<name>.res)."},
			"model": {"type": "string", "description": "Kimodo model id (default soma-rp-v1.1)."},
			"prompt": {"type": "string", "description": "Kimodo only: English prompt used verbatim (skips translation)."},
		},
		"handler": _generate,
		"examples": [{"text": "anda até a esquerda, acena duas vezes e depois senta triste"}, {"text": "dança feliz por 6 segundos", "character": "Heroi"}],
	})
	reg.add("motion.character", {
		"description": "Adds a humanoid character (VibeCharacter3D) with a procedural body. Outfits: " + outfits + ". Optionally generates an animation right away (text).",
		"args": {
			"name": {"type": "string", "default": "Personagem", "description": "Node name."},
			"outfit": {"type": "string", "default": "casual", "description": "Outfit preset (PT/EN: aventureiro, robô, mago, ninja, cavaleiro, zumbi, astronauta, rei, atleta, soldado, manequim)."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style (default: scene style)."},
			"colors": {"type": "object", "default": {}, "description": "Overrides: {\"shirt\": \"red\", \"pants\": \"#222\", \"hair_style\": \"long\", \"hat\": \"cap\"}."},
			"height": {"type": "number", "default": 1.8, "description": "Height in meters (animations scale with it)."},
			"position": {"type": "position", "default": "center", "description": "Where it stands ([x, z] snaps to the terrain), or 'near:<node>' to stand in a ring around a node (e.g. near:Campfire)."},
			"radius": {"type": "number", "default": 2.4, "description": "Ring radius for near:<node>."},
			"facing": {"type": "any", "description": "Yaw in degrees, a position to look at, or 'camera'."},
			"text": {"type": "string", "description": "Also generate and play this animation."},
			"replace": {"type": "boolean", "default": true, "description": "Replace a node with the same name."},
			"parent": {"type": "string", "description": "Parent node (default scene root)."},
			"seed": {"type": "integer", "default": 0, "description": "Seed for anchor positions."},
		},
		"handler": _character,
		"examples": [{"name": "Heroi", "outfit": "aventureiro", "position": "flat", "text": "acena e depois dança"}],
	})
	reg.add("motion.play", {
		"description": "Plays (or freezes at a time) an animation of a character.",
		"args": {
			"character": {"type": "string", "description": "Character name (default first)."},
			"animation": {"type": "string", "required": true, "description": "Animation name."},
			"time": {"type": "number", "default": -1.0, "description": ">= 0 freezes the pose at this second (for screenshots)."},
			"root_motion": {"type": "string", "enum": ["animate", "extract", "in_place"], "description": "Root motion mode."},
		},
		"handler": _play,
	})
	reg.add("motion.list", {
		"description": "Lists the actions the text understands, moods, styles, outfits, saved animations and the characters in the scene.",
		"handler": _list,
	})
	reg.add("motion.describe", {
		"description": "Shows how a text is understood (segments, durations, English prompts) without generating anything.",
		"args": {"text": {"type": "string", "required": true, "description": "Motion description."}},
		"handler": _describe,
	})
	reg.add("motion.render", {
		"description": "Renders an animation preview PNG in a neutral studio: 'sheet' (N poses side by side), 'trail' (all poses along the path in one picture) or 'sequence' (numbered frames). Open the PNG to check the motion.",
		"args": {
			"animation": {"type": "string", "description": "Animation name (of the character) or res:// path."},
			"text": {"type": "string", "description": "Or render a text directly (not saved)."},
			"character": {"type": "string", "description": "Use this character's outfit/style."},
			"outfit": {"type": "string", "description": "Outfit when no character is given (default mannequin)."},
			"style": {"type": "string", "enum": STYLES, "description": "Art style."},
			"mode": {"type": "string", "default": "sheet", "enum": ["sheet", "trail", "sequence"], "description": "Kind of preview."},
			"frames": {"type": "integer", "default": 6, "description": "Number of poses/frames."},
			"view": {"type": "string", "default": "three_quarter", "enum": Render.VIEWS.keys(), "description": "Camera direction."},
			"columns": {"type": "integer", "default": 0, "description": "Sheet columns (0 = auto)."},
			"width": {"type": "integer", "description": "Width of each frame (px)."},
			"height": {"type": "integer", "description": "Height of each frame (px)."},
			"path": {"type": "string", "description": "Output PNG (default res://.vibe/screenshots/motion_<name>_<mode>.png)."},
		},
		"handler": _render,
	})
	reg.add("motion.apply", {
		"description": "Retargets a humanoid animation onto another rigged model in the scene (Godot humanoid BoneMap, Mixamo, Unreal, CMU or SMPL bone names), adding an AnimationPlayer if needed.",
		"args": {
			"animation": {"type": "string", "required": true, "description": "res:// path or name of a character animation."},
			"target": {"type": "string", "required": true, "description": "Node that contains the model's Skeleton3D."},
			"name": {"type": "string", "description": "Animation name on the target (default: same)."},
			"in_place": {"type": "boolean", "default": false, "description": "Drop horizontal root motion."},
			"play": {"type": "boolean", "default": true, "description": "Set as autoplay."},
		},
		"handler": _apply,
	})
	reg.add("motion.import", {
		"description": "Imports motion capture (BVH, glTF/GLB, FBX on Godot 4.3+: Mixamo, CMU, Kimodo exports...) retargeted to the humanoid, saved as res://animations/<name>.res.",
		"args": {
			"path": {"type": "string", "required": true, "description": "File path (res:// or absolute)."},
			"name": {"type": "string", "description": "Animation name (default: file name)."},
			"clip": {"type": "string", "description": "Animation inside the file (default first)."},
			"character": {"type": "string", "description": "Add it to this character."},
			"facing": {"type": "number", "default": 0.0, "description": "Extra yaw (degrees) if the source faces the wrong way."},
			"fps": {"type": "number", "default": 30.0, "description": "Sampling rate for glTF/FBX."},
			"in_place": {"type": "boolean", "default": false, "description": "Remove root motion."},
			"loop": {"type": "boolean", "default": false, "description": "Loop the animation."},
		},
		"handler": _import,
	})
	reg.add("motion.backend", {
		"description": "Text-to-motion backends: the built-in procedural synthesizer and the optional Kimodo (kimodo.cpp) server. Pass url/model to configure it, test=true to check it.",
		"args": {
			"url": {"type": "string", "description": "kimodo.cpp server URL (saved in project settings), e.g. http://127.0.0.1:8090."},
			"model": {"type": "string", "description": "Default Kimodo model (soma-rp-v1.1, soma-seed-v1.1, smplx-rp-v1)."},
			"test": {"type": "boolean", "default": true, "description": "Contact the server."},
		},
		"handler": _backend,
	})


# --- helpers ------------------------------------------------------------------------

func _scene_style(ctx) -> String:
	if ctx.root != null and ctx.root.has_meta("vibe_style"):
		return str(ctx.root.get_meta("vibe_style"))
	return "realistic"


func _characters(ctx) -> Array:
	return ctx.nodes_in_group(CharScript.GROUP)


func _find_character(ctx, name: String) -> Node:
	if name != "":
		var n: Node = ctx.find_node(name)
		if n != null and n.has_method("add_animation"):
			return n
		return ctx.find_in_group(CharScript.GROUP, name)
	var list := _characters(ctx)
	return list[0] if not list.is_empty() else null


func _anim_name(text: String) -> String:
	var words := TextParser.normalize(text).split(" ", false)
	var stop := ["o", "a", "os", "as", "um", "uma", "de", "do", "da", "e", "the", "a", "an", "and", "to", "com", "por", "para", "depois", "then", "person", "pessoa"]
	var kept: Array = []
	for w in words:
		if not stop.has(w) and kept.size() < 6:
			kept.append(w)
	var n := Util.slugify(" ".join(kept))
	return n.substr(0, 48) if n != "" else "animacao"


func _save_animation(anim: Animation, path: String, ctx) -> Variant:
	path = Util.to_res_path(path, "res")
	if not Util.is_safe_write_path(path):
		return Util.err("animation path must be inside the project (res://)")
	Util.ensure_dir(path.get_base_dir())
	var err := ResourceSaver.save(anim, path)
	if err != OK:
		return Util.err("could not save %s (%s)" % [path, error_string(err)])
	anim.take_over_path(path)
	if ctx.is_editor():
		var fs = ctx.editor_interface.get_resource_filesystem()
		if fs != null:
			fs.update_file(path)
	return path


func _load_animation(ref: String, ctx) -> Animation:
	if ref.begins_with("res://") or ref.begins_with("user://") or ref.ends_with(".res") or ref.ends_with(".tres"):
		var p := Util.to_res_path(ref)
		if ResourceLoader.exists(p):
			var a = load(p)
			return a if a is Animation else null
	for ch in _characters(ctx):
		var player: AnimationPlayer = ch.get_animation_player()
		if player != null and player.has_animation(ref):
			return player.get_animation(ref)
	var guess := ANIM_DIR.path_join(Util.slugify(ref) + ".res")
	if ResourceLoader.exists(guess):
		var a2 = load(guess)
		return a2 if a2 is Animation else null
	return null


func _new_character(ctx, args: Dictionary) -> Variant:
	var missing = ctx.require_root()
	if missing != null:
		return missing
	var name := str(args.get("name", "Personagem"))
	var parent: Node = ctx.root
	if str(args.get("parent", "")) != "":
		parent = ctx.find_node(args.parent)
		if parent == null:
			return Util.err("parent not found: %s" % args.parent)
	var old: Node = parent.get_node_or_null(NodePath(name))
	if old != null:
		if Util.to_bool(args.get("replace", true)):
			ctx.remove_node(old)
		else:
			name = ctx.unique_name(name, parent)
	var outfit := Mannequin.resolve_outfit_name(str(args.get("outfit", "casual")))
	if outfit == "":
		outfit = "casual"
	var ch = CharScript.new()
	ch.name = name
	ch.outfit = outfit
	var colors = args.get("colors", {})
	if colors is Dictionary:
		ch.colors = colors
	ch.style = str(args.get("style", "")) if str(args.get("style", "")) != "" else _scene_style(ctx)
	ch.height = float(args.get("height", 1.8))
	ch.ensure_nodes()
	var where = args.get("position", "center")
	var near: Node3D = null
	if where is String and (where as String).begins_with("near:"):
		near = _find_by_name(ctx, (where as String).substr(5))
		if near == null:
			where = "flat"
	var pos
	if near != null:
		# In a ring around the node (a campfire, a portal...), facing it.
		var ang := float(int(args.get("seed", 0))) * 2.39996 + 0.6
		var ring: Vector3 = near.global_position + Vector3(cos(ang), 0.0, sin(ang)) * float(args.get("radius", 2.4))
		pos = ctx.resolve_position([ring.x, ring.z])
	else:
		pos = ctx.resolve_position(where, 0.0, int(args.get("seed", 0)))
	if Util.is_err(pos):
		ch.free()
		return pos
	ctx.add_node(ch, parent, true)
	ch.global_position = pos
	var facing = args.get("facing", null)
	if facing == null and near != null:
		facing = [near.global_position.x, near.global_position.z]
	if facing != null:
		_face(ctx, ch, facing)
	elif ctx.root is Node3D:
		_face(ctx, ch, "camera")
	return ch


func _find_by_name(ctx, name: String) -> Node3D:
	var n: Node = ctx.find_node(name)
	if n is Node3D:
		return n
	var key := Util.slugify(name).replace("_", "")
	for c in ctx.all_nodes():
		if c is Node3D and Util.slugify(str(c.name)).replace("_", "").begins_with(key):
			return c
	return null


func _face(ctx, ch: Node3D, facing: Variant) -> void:
	if facing is float or facing is int:
		ch.rotation.y = deg_to_rad(float(facing))
		return
	var target = null
	if str(facing) == "camera":
		for n in ctx.all_nodes():
			if n is Camera3D:
				target = (n as Camera3D).global_position
				break
		if target == null:
			return
	else:
		target = ctx.resolve_position(facing)
		if Util.is_err(target):
			return
	var d: Vector3 = (target as Vector3) - ch.global_position
	d.y = 0.0
	if d.length() > 0.01:
		ch.rotation.y = atan2(d.x, d.z)


# --- commands -------------------------------------------------------------------------

func _generate(args: Dictionary, ctx) -> Variant:
	var text: String = args.text
	var plan := TextParser.parse(text)
	if plan.segments.is_empty():
		return Util.err("no action recognized in '%s'. Try: 'anda', 'corre', 'pula', 'acena', 'dança', 'senta', 'soca', 'lança magia'... (motion.list shows all)" % text)
	var options := {"seed": args.seed, "fps": args.fps, "in_place": args.in_place}
	if args.loop != "auto":
		options["loop"] = args.loop == "true"
	var synth := Synth.new()
	var timeline := synth.timeline(plan.segments)
	var result: Dictionary = {}
	var used := "procedural"
	var notes: Array = []
	var backend: String = args.backend
	if backend == "kimodo" or backend == "auto":
		var host: Node = ctx.tree.root if ctx.tree != null else null
		var go := backend == "kimodo"
		if backend == "auto" and host != null and Kimodo.configured():
			var st: Dictionary = await Kimodo.status(host)
			go = st.ok
		if go and host != null:
			var segs: Array = []
			var secs: Array = []
			for sg in timeline:
				if sg.get("auto", false):
					continue
				var e := {"clip": sg.clip, "q": sg.q}
				segs.append(e)
				secs.append(float(sg.dur))
			if str(args.get("prompt", "")) != "":
				segs = [{"clip": "", "q": {}, "prompt": args.prompt}]
				var total := 0.0
				for s in secs:
					total += s
				secs = [clampf(total, 2.0, 5.0)]
			var kopts := {"seed": args.seed}
			if str(args.get("model", "")) != "":
				kopts["model"] = args.model
			var k: Dictionary = await Kimodo.generate(host, segs, secs, kopts)
			if k.has("error"):
				if backend == "kimodo":
					return Util.err(str(k.error))
				notes.append("kimodo unavailable, used the procedural synthesizer: " + str(k.error))
			else:
				result = k
				used = "kimodo"
				if options.has("loop"):
					result["loop"] = options.loop
	if result.is_empty():
		result = synth.generate(plan.segments, options)
	if bool(args.in_place) and used == "kimodo":
		for fr in result.frames:
			fr.root = Vector3.ZERO
	var anim := Synth.to_animation(result)
	var name := str(args.get("name", ""))
	if name == "":
		name = _anim_name(text)
	name = Util.slugify(name)
	anim.resource_name = name
	anim.set_meta("vibe_text", text)
	anim.set_meta("vibe_backend", used)
	var path := str(args.get("path", ""))
	if path == "":
		path = ANIM_DIR.path_join(name + ".res")
	var saved = _save_animation(anim, path, ctx)
	if Util.is_err(saved):
		return saved
	var ch := _find_character(ctx, str(args.get("character", "")))
	if ch == null and Util.to_bool(args.create) and ctx.root != null:
		var made = _new_character(ctx, {"name": str(args.get("character", "")) if str(args.get("character", "")) != "" else "Personagem"})
		if Util.is_err(made):
			return made
		ch = made
		notes.append("added character '%s' (motion.character changes outfit/style/position)" % ch.name)
	if ch != null:
		ch.add_animation(anim, name)
		if Util.to_bool(args.play):
			ctx.set_property(ch, &"animation", name)
		ctx.dirty = true
	var english: Array = []
	for e in plan.segments:
		english.append(TextParser.english(e))
	var out := {
		"name": name, "path": saved, "backend": used, "duration": snappedf(float(result.get("duration", anim.length)), 0.01),
		"loop": anim.loop_mode != Animation.LOOP_NONE, "segments": result.get("segments", []), "english": english,
		"character": str(ch.name) if ch != null else "", "tip": "check it: motion.render animation=%s (then open the PNG)" % name,
	}
	if not plan.unknown.is_empty():
		out["not_understood"] = plan.unknown
	if not notes.is_empty():
		out["notes"] = notes
	return out


func _character(args: Dictionary, ctx) -> Variant:
	var made = _new_character(ctx, args)
	if Util.is_err(made):
		return made
	var ch: Node3D = made
	var out := {"name": str(ch.name), "outfit": ch.outfit, "style": ch.style, "position": ch.global_position, "height": ch.height}
	if str(args.get("text", "")) != "":
		var text := str(args.text)
		if TextParser.parse(text).segments.is_empty():
			ctx.warn("no action recognized in '%s': the character stays idle" % text)
			text = "parado"
		var g = await _generate({"text": text, "character": str(ch.name), "create": false, "backend": "auto", "play": true,
			"loop": "auto", "in_place": false, "seed": args.get("seed", 0), "fps": 30.0}, ctx)
		if Util.is_err(g):
			return g
		out["animation"] = g
	return out


func _play(args: Dictionary, ctx) -> Variant:
	var ch := _find_character(ctx, str(args.get("character", "")))
	if ch == null:
		return Util.err("no VibeCharacter3D in the scene (motion.character adds one)")
	var names: PackedStringArray = ch.get_animation_names()
	if not names.has(args.animation):
		var a := _load_animation(args.animation, ctx)
		if a == null:
			return Util.err("animation '%s' not found. Available: %s" % [args.animation, ", ".join(names)])
		ch.add_animation(a, args.animation)
	if args.has("root_motion"):
		ctx.set_property(ch, &"root_motion", args.root_motion)
	ctx.set_property(ch, &"preview_time", float(args.time))
	ctx.set_property(ch, &"animation", args.animation)
	return {"character": str(ch.name), "animation": args.animation, "time": args.time}


func _list(_args: Dictionary, ctx) -> Variant:
	var clips := {}
	for c in Synth.CLIPS:
		var kw: Array = TextParser.KEYWORDS.get(c, [])
		clips[c] = "%s — ex.: %s" % [Synth.CLIPS[c].desc, ", ".join(kw.slice(0, 4))]
	var outfits := {}
	for o in Mannequin.OUTFITS:
		outfits[o] = Mannequin.OUTFITS[o].get("description", "")
	var saved: Array = []
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ANIM_DIR)):
		for f in DirAccess.get_files_at(ANIM_DIR):
			if f.ends_with(".res") or f.ends_with(".tres"):
				saved.append(ANIM_DIR.path_join(f))
	var chars: Array = []
	for ch in _characters(ctx):
		chars.append({"name": str(ch.name), "outfit": ch.outfit, "style": ch.style, "animation": ch.animation, "animations": Array(ch.get_animation_names())})
	return {
		"actions": clips, "moods": TextParser.MOODS.keys(), "styles": TextParser.STYLES.keys(), "outfits": outfits,
		"saved_animations": saved, "characters": chars,
		"modifiers": "counts (3 vezes, twice), durations (por 4 segundos), speed (devagar, rápido), sides (mão esquerda), directions (para trás, em círculo, zigue-zague, de lado), 'enquanto' (anda enquanto acena)",
	}


func _describe(args: Dictionary, _ctx) -> Variant:
	var plan := TextParser.parse(args.text)
	var synth := Synth.new()
	var segs: Array = []
	for s in synth.timeline(plan.segments):
		var q: Dictionary = s.q
		var e := {"clip": s.clip, "start": snappedf(float(s.start), 0.01), "duration": snappedf(float(s.dur), 0.01)}
		for k in ["count", "speed", "dir", "side", "mood_name", "style", "steps", "distance", "angle"]:
			if q.has(k):
				e[k] = q[k]
		if s.get("auto", false):
			e["auto"] = true
		if s.has("overlay"):
			e["overlay"] = s.overlay.clip
		segs.append(e)
	var english: Array = []
	for e2 in plan.segments:
		english.append(TextParser.english(e2))
	return {"segments": segs, "not_understood": plan.unknown, "english": english, "mood": plan.mood, "style": plan.style}


func _render(args: Dictionary, ctx) -> Variant:
	if DisplayServer.get_name() == "headless":
		return Util.err("rendering needs a window: run it through tools/vibe.py (uses xvfb-run on Linux) or with the editor open")
	var anim: Animation = null
	var label := ""
	if str(args.get("text", "")) != "":
		var plan := TextParser.parse(args.text)
		if plan.segments.is_empty():
			return Util.err("no action recognized in '%s'" % args.text)
		anim = Synth.to_animation(Synth.new().generate(plan.segments, {}))
		label = _anim_name(args.text)
	elif str(args.get("animation", "")) != "":
		anim = _load_animation(args.animation, ctx)
		label = Util.slugify(str(args.animation).get_file().get_basename())
	else:
		var ch0 := _find_character(ctx, str(args.get("character", "")))
		if ch0 != null and ch0.animation != "":
			anim = _load_animation(ch0.animation, ctx)
			label = ch0.animation
	if anim == null:
		return Util.err("animation not found (pass animation=<name or res:// path> or text=...)")
	var opts := {"mode": args.mode, "frames": args.frames, "view": args.view, "columns": args.columns}
	if args.has("width"):
		opts["width"] = args.width
	if args.has("height"):
		opts["height"] = args.height
	var ch := _find_character(ctx, str(args.get("character", ""))) if str(args.get("character", "")) != "" else null
	opts["outfit"] = str(args.get("outfit", ch.outfit if ch != null else "mannequin"))
	opts["style"] = str(args.get("style", ch.style if ch != null else "realistic"))
	if ch != null:
		opts["colors"] = ch.colors
	var path := str(args.get("path", ""))
	if path == "":
		path = SHOT_DIR.path_join("motion_%s_%s.png" % [label, args.mode])
		Util.ensure_dir("res://.vibe")
		if not FileAccess.file_exists("res://.vibe/.gdignore"):
			var f := FileAccess.open("res://.vibe/.gdignore", FileAccess.WRITE)
			if f:
				f.close()
	path = Util.to_res_path(path, "png")
	Util.ensure_dir(path.get_base_dir())
	opts["path"] = path
	var host: Node = ctx.editor_interface.get_base_control() if ctx.is_editor() else ctx.tree.root
	var r: Dictionary = await Render.render(host, anim, opts)
	if r.has("error"):
		return Util.err(str(r.error))
	r["animation"] = label
	r["duration"] = snappedf(anim.length, 0.01)
	return r


func _apply(args: Dictionary, ctx) -> Variant:
	var anim := _load_animation(args.animation, ctx)
	if anim == null:
		return Util.err("animation not found: %s" % args.animation)
	var target: Node = ctx.find_node(args.target)
	if target == null:
		return Util.err("target not found: %s" % args.target)
	var sk := H.find_skeleton(target)
	if sk == null:
		return Util.err("no Skeleton3D inside '%s'" % args.target)
	var player: AnimationPlayer = null
	for c in target.get_children():
		if c is AnimationPlayer:
			player = c
			break
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		ctx.add_node(player, target)
	var anim_root: Node = player.get_node_or_null(player.root_node)
	if anim_root == null:
		anim_root = target
	var sk_path := str(anim_root.get_path_to(sk))
	var r: Dictionary = Retarget.humanoid_to_skeleton(anim, sk, sk_path, {"in_place": args.in_place})
	if r.has("error"):
		return Util.err(str(r.error))
	var out_anim: Animation = r.animation
	var name := Util.slugify(str(args.get("name", "")) if str(args.get("name", "")) != "" else str(anim.resource_name if anim.resource_name != "" else args.animation.get_file().get_basename()))
	out_anim.resource_name = name
	var saved = _save_animation(out_anim, ANIM_DIR.path_join("%s_%s.res" % [Util.slugify(str(target.name)), name]), ctx)
	if Util.is_err(saved):
		return saved
	if not player.has_animation_library(""):
		player.add_animation_library("", AnimationLibrary.new())
	var lib := player.get_animation_library("")
	if lib.has_animation(name):
		lib.remove_animation(name)
	lib.add_animation(name, out_anim)
	if Util.to_bool(args.play):
		ctx.set_property(player, &"autoplay", name)
	ctx.dirty = true
	return {"target": str(target.name), "skeleton": sk_path, "animation": name, "path": saved, "bones_matched": r.mapped, "scale": snappedf(float(r.scale), 0.001)}


func _import(args: Dictionary, ctx) -> Variant:
	var path: String = args.path
	var res_path := Util.to_res_path(path)
	var file := res_path if res_path.begins_with("res://") or res_path.begins_with("user://") else path
	if not FileAccess.file_exists(file):
		return Util.err("file not found: %s" % path)
	var ext := file.get_extension().to_lower()
	var src: Dictionary
	if ext == "bvh":
		src = Retarget.load_bvh(file)
	elif ext in ["glb", "gltf", "fbx"]:
		src = Retarget.load_scene_animation(file, str(args.get("clip", "")), float(args.fps))
	else:
		return Util.err("unsupported format .%s (use .bvh, .glb, .gltf or .fbx)" % ext)
	if src.has("error"):
		return Util.err(str(src.error))
	var result := Retarget.to_humanoid(src.desc, src.frames, src.root_pos, float(src.fps), {"facing": args.facing})
	if result.has("error"):
		return Util.err(str(result.error))
	result["loop"] = Util.to_bool(args.loop)
	if Util.to_bool(args.in_place):
		for fr in result.frames:
			fr.root = Vector3.ZERO
	var anim := Synth.to_animation(result)
	var name := Util.slugify(str(args.get("name", "")) if str(args.get("name", "")) != "" else file.get_file().get_basename())
	anim.resource_name = name
	anim.set_meta("vibe_source", file)
	var saved = _save_animation(anim, ANIM_DIR.path_join(name + ".res"), ctx)
	if Util.is_err(saved):
		return saved
	var ch := _find_character(ctx, str(args.get("character", ""))) if str(args.get("character", "")) != "" else null
	if ch != null:
		ch.add_animation(anim, name)
		ctx.set_property(ch, &"animation", name)
	return {"name": name, "path": saved, "frames": result.frames.size(), "duration": snappedf(anim.length, 0.01),
		"bones_matched": result.get("mapped", 0), "scale": snappedf(float(result.get("scale", 1.0)), 0.0001), "character": str(ch.name) if ch != null else ""}


func _backend(args: Dictionary, ctx) -> Variant:
	var changed := false
	if str(args.get("url", "")) != "":
		ProjectSettings.set_setting(Kimodo.SETTING_URL, str(args.url).trim_suffix("/"))
		changed = true
	if str(args.get("model", "")) != "":
		ProjectSettings.set_setting(Kimodo.SETTING_MODEL, str(args.model))
		changed = true
	if changed:
		ProjectSettings.save()
	var out := {
		"procedural": {"available": true, "actions": Synth.CLIPS.size(), "note": "built in, instant, deterministic"},
		"kimodo": {"url": Kimodo.url(), "model": Kimodo.default_model(),
			"setup": "git clone kimodo.cpp, download the GGUF models (Hugging Face), build, then run: go run ./demo -addr 127.0.0.1:8090"},
	}
	if Util.to_bool(args.test) and ctx.tree != null:
		var st: Dictionary = await Kimodo.status(ctx.tree.root)
		out.kimodo["reachable"] = st.ok
		if st.ok:
			out.kimodo["models"] = st.models
		else:
			out.kimodo["error"] = st.get("error", "")
	return out
