@tool
extends RefCounted
## Client for a kimodo.cpp server (NVIDIA Kimodo text-to-motion diffusion,
## GGML port). Start the server from the kimodo.cpp repository:
##     go run ./demo -addr 127.0.0.1:8090
## and point the suite at it (project setting vibe/motion/kimodo_url or the
## KIMODO_URL environment variable). Prompts are sent in English (one per
## segment, 60..150 frames at 30 fps), the result (local rotations + root
## positions of the SOMA30 / SMPL-X skeleton) is retargeted to the humanoid.

const TextParser = preload("res://addons/vibe_motion/motion_text.gd")
const Retarget = preload("res://addons/vibe_motion/motion_retarget.gd")

const DEFAULT_URL := "http://127.0.0.1:8090"
const SETTING_URL := "vibe/motion/kimodo_url"
const SETTING_MODEL := "vibe/motion/kimodo_model"
const FPS := 30.0


static func url() -> String:
	var env := OS.get_environment("KIMODO_URL")
	if env != "":
		return env.trim_suffix("/")
	return str(ProjectSettings.get_setting(SETTING_URL, DEFAULT_URL)).trim_suffix("/")


## True when a server was configured (env KIMODO_URL or the project setting):
## only then does backend "auto" try Kimodo.
static func configured() -> bool:
	return OS.get_environment("KIMODO_URL") != "" or ProjectSettings.has_setting(SETTING_URL)


static func default_model() -> String:
	var env := OS.get_environment("KIMODO_MODEL")
	if env != "":
		return env
	return str(ProjectSettings.get_setting(SETTING_MODEL, "soma-rp-v1.1"))


## Sends an HTTP request and waits for it: [ok, code, body PackedByteArray, error].
static func _request(host: Node, method: int, target: String, body: String = "", timeout: float = 30.0) -> Array:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.use_threads = false
	host.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var err := http.request(target, headers, method, body)
	if err != OK:
		http.queue_free()
		return [false, 0, PackedByteArray(), "request failed: %s" % error_string(err)]
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	if result != HTTPRequest.RESULT_SUCCESS:
		return [false, 0, PackedByteArray(), "cannot reach %s (HTTPRequest result %d)" % [target, result]]
	var code: int = res[1]
	return [code >= 200 and code < 300, code, res[3], "" if code < 300 else "HTTP %d: %s" % [code, (res[3] as PackedByteArray).get_string_from_utf8().substr(0, 300)]]


static func _json(res: Array) -> Variant:
	if res[2] is PackedByteArray:
		return JSON.parse_string((res[2] as PackedByteArray).get_string_from_utf8())
	return null


## Server status: {ok, url, models: [...], error}.
static func status(host: Node, base: String = "") -> Dictionary:
	var u := base if base != "" else url()
	var res: Array = await _request(host, HTTPClient.METHOD_GET, u + "/api/models", "", 5.0)
	if not res[0]:
		return {"ok": false, "url": u, "error": res[3]}
	var models = _json(res)
	var out: Array = []
	if models is Array:
		for m in models:
			if m is Dictionary:
				out.append({"id": m.get("id", ""), "label": m.get("label", ""), "skeleton": m.get("skeleton_key", ""),
					"available": m.get("available", false), "license": m.get("license", ""), "reason": m.get("reason", "")})
	return {"ok": true, "url": u, "models": out}


## Generates motion for parsed segments. seconds: per-segment durations.
## Returns synthesizer-style frames ({frames, fps, duration, ...}) or {error}.
static func generate(host: Node, segments: Array, seconds: Array, options: Dictionary = {}) -> Dictionary:
	var u := str(options.get("url", url()))
	var model := str(options.get("model", default_model()))
	var prompts: Array = []
	var seg_json: Array = []
	for i in segments.size():
		var e: Dictionary = segments[i]
		var prompt := str(e.get("prompt", ""))
		if prompt == "":
			prompt = TextParser.english(e)
		var frames := clampi(int(round(float(seconds[i] if i < seconds.size() else 3.0) * FPS)), 60, 150)
		prompts.append(prompt)
		seg_json.append({"prompt": prompt, "frames": frames})
	if seg_json.is_empty():
		return {"error": "nothing to generate"}
	if seg_json.size() > 16:
		seg_json = seg_json.slice(0, 16)
	var req := {"segments": seg_json, "transition_frames": int(options.get("transition_frames", 5)),
		"steps": int(options.get("steps", 100)), "seed": int(options.get("seed", 0)), "model": model}
	if options.has("text_quantization"):
		req["text_quantization"] = str(options.text_quantization)
	var res: Array = await _request(host, HTTPClient.METHOD_POST, u + "/api/generate", JSON.stringify(req), 30.0)
	if not res[0]:
		return {"error": "Kimodo: %s" % res[3], "prompts": prompts}
	var item = _json(res)
	if not (item is Dictionary) or str(item.get("id", "")) == "":
		return {"error": "Kimodo: unexpected answer to /api/generate", "prompts": prompts}
	var id := str(item.id)
	var deadline := Time.get_ticks_msec() + int(float(options.get("timeout", 900.0)) * 1000.0)
	var status := str(item.get("status", "queued"))
	while status != "ready":
		if status == "failed":
			return {"error": "Kimodo failed: %s" % str(item.get("error", "")), "prompts": prompts, "id": id}
		if Time.get_ticks_msec() > deadline:
			return {"error": "Kimodo timed out (still %s). The animation id is %s." % [status, id], "prompts": prompts, "id": id}
		await host.get_tree().create_timer(1.0).timeout
		var lst: Array = await _request(host, HTTPClient.METHOD_GET, u + "/api/animations", "", 10.0)
		if not lst[0]:
			continue
		var all = _json(lst)
		if all is Array:
			for a in all:
				if a is Dictionary and str(a.get("id", "")) == id:
					item = a
					status = str(a.get("status", status))
	return await fetch(host, id, model, {"url": u, "prompts": prompts})


## Downloads a finished animation (raw rotations) and retargets it.
static func fetch(host: Node, id: String, model: String, options: Dictionary = {}) -> Dictionary:
	var u := str(options.get("url", url()))
	var mres: Array = await _request(host, HTTPClient.METHOD_GET, u + "/api/models", "", 10.0)
	if not mres[0]:
		return {"error": "Kimodo: %s" % mres[3]}
	var skel: Dictionary = {}
	var models = _json(mres)
	if models is Array:
		for m in models:
			if m is Dictionary and str(m.get("id", "")) == model:
				skel = m
	if skel.is_empty():
		return {"error": "Kimodo: model '%s' not listed by the server" % model}
	var key := str(skel.get("skeleton_key", ""))
	if not Retarget.KIMODO_NAMES.has(key):
		return {"error": "Kimodo skeleton '%s' is not humanoid-mapped yet (use a SOMA or SMPL-X model)" % key}
	var names: Array = Retarget.KIMODO_NAMES[key]
	var parents: Array = skel.get("parents", [])
	var offsets: Array = skel.get("offsets", [])
	if parents.size() != names.size() or offsets.size() != names.size():
		return {"error": "Kimodo: skeleton data mismatch for %s" % key}
	var rres: Array = await _request(host, HTTPClient.METHOD_GET, "%s/api/animations/%s/rotations.f32" % [u, id], "", 60.0)
	var pres: Array = await _request(host, HTTPClient.METHOD_GET, "%s/api/animations/%s/root.f32" % [u, id], "", 60.0)
	if not rres[0] or not pres[0]:
		return {"error": "Kimodo: could not download the motion (%s %s)" % [rres[3], pres[3]]}
	var rot: PackedFloat32Array = (rres[2] as PackedByteArray).to_float32_array()
	var root: PackedFloat32Array = (pres[2] as PackedByteArray).to_float32_array()
	var src := decode(names, parents, offsets, rot, root)
	if src.has("error"):
		return src
	var out := Retarget.to_humanoid(src.desc, src.frames, src.root_pos, FPS, {"auto_orient": false})
	out["backend"] = "kimodo"
	out["kimodo_id"] = id
	out["model"] = model
	out["prompts"] = options.get("prompts", [])
	return out


## Raw Kimodo arrays -> retarget input.
static func decode(names: Array, parents: Array, offsets: Array, rot: PackedFloat32Array, root: PackedFloat32Array) -> Dictionary:
	var nj := names.size()
	var nf := root.size() / 3
	if nf <= 0 or rot.size() < nf * nj * 4:
		return {"error": "Kimodo: motion arrays have unexpected sizes (%d rotations, %d root values, %d joints)" % [rot.size(), root.size(), nj]}
	var desc := Retarget.desc_from_offsets(names, parents, offsets)
	var frames: Array = []
	var root_pos: Array = []
	for f in nf:
		var rots: Array = []
		for j in nj:
			var o := (f * nj + j) * 4
			rots.append(Quaternion(rot[o], rot[o + 1], rot[o + 2], rot[o + 3]).normalized())
		frames.append(rots)
		root_pos.append(Vector3(root[f * 3], root[f * 3 + 1], root[f * 3 + 2]))
	return {"desc": desc, "frames": frames, "root_pos": root_pos}
