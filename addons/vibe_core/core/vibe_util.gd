@tool
extends RefCounted
## Shared helpers for the Vibe suite: argument coercion, JSON conversion,
## text normalization (PT/EN) and small math utilities.
##
## Every script in the suite preloads this file instead of relying on global
## class names, so the helpers also work in headless CLI mode on a fresh clone.

const ERROR_KEY := "_vibe_error"

## Node groups used to find Vibe nodes without relying on global class names.
const TERRAIN_GROUP := &"vibe_terrain"
const GRASS_GROUP := &"vibe_grass"
const VFX_GROUP := &"vibe_vfx"

const PT_COLOR_NAMES := {
	"vermelho": Color(0.9, 0.12, 0.1), "vermelha": Color(0.9, 0.12, 0.1),
	"azul": Color(0.15, 0.4, 1.0), "verde": Color(0.2, 0.85, 0.25),
	"amarelo": Color(1.0, 0.9, 0.15), "amarela": Color(1.0, 0.9, 0.15),
	"laranja": Color(1.0, 0.5, 0.1), "roxo": Color(0.6, 0.2, 0.95), "roxa": Color(0.6, 0.2, 0.95),
	"lilas": Color(0.75, 0.55, 1.0), "violeta": Color(0.55, 0.25, 1.0),
	"rosa": Color(1.0, 0.4, 0.75), "magenta": Color(1.0, 0.1, 0.85),
	"branco": Color(1, 1, 1), "branca": Color(1, 1, 1), "preto": Color(0.03, 0.03, 0.03),
	"preta": Color(0.03, 0.03, 0.03), "cinza": Color(0.5, 0.5, 0.5),
	"dourado": Color(1.0, 0.78, 0.25), "dourada": Color(1.0, 0.78, 0.25),
	"prateado": Color(0.8, 0.82, 0.86), "prateada": Color(0.8, 0.82, 0.86),
	"marrom": Color(0.45, 0.28, 0.12), "ciano": Color(0.1, 0.9, 1.0),
	"turquesa": Color(0.2, 0.9, 0.8), "anil": Color(0.3, 0.2, 0.9),
}

const EN_COLOR_NAMES := {
	"red": Color(0.9, 0.12, 0.1), "blue": Color(0.15, 0.4, 1.0), "green": Color(0.2, 0.85, 0.25),
	"yellow": Color(1.0, 0.9, 0.15), "orange": Color(1.0, 0.5, 0.1), "purple": Color(0.6, 0.2, 0.95),
	"violet": Color(0.55, 0.25, 1.0), "pink": Color(1.0, 0.4, 0.75), "magenta": Color(1.0, 0.1, 0.85),
	"white": Color(1, 1, 1), "black": Color(0.03, 0.03, 0.03), "gray": Color(0.5, 0.5, 0.5),
	"grey": Color(0.5, 0.5, 0.5), "gold": Color(1.0, 0.78, 0.25), "golden": Color(1.0, 0.78, 0.25),
	"silver": Color(0.8, 0.82, 0.86), "brown": Color(0.45, 0.28, 0.12), "cyan": Color(0.1, 0.9, 1.0),
	"teal": Color(0.1, 0.6, 0.6), "turquoise": Color(0.2, 0.9, 0.8),
}

const ACCENTS := {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i",
	"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "ñ": "n",
}


# --- Errors -----------------------------------------------------------------

## Returns an error marker. Command handlers `return Util.err("...")` to fail.
static func err(message: String) -> Dictionary:
	return {ERROR_KEY: message}


static func is_err(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).has(ERROR_KEY)


# --- Text -------------------------------------------------------------------

## Lowercase + accent stripping, used to match Portuguese and English keywords.
static func normalize_text(text: String) -> String:
	var out := text.to_lower()
	for k in ACCENTS:
		out = out.replace(k, ACCENTS[k])
	return out


static func slugify(text: String) -> String:
	var s := normalize_text(text)
	var out := ""
	for i in s.length():
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif not out.ends_with("_"):
			out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else "item"


## Converts "my_node name" to "MyNodeName" (valid, readable node names).
static func pascal_case(text: String) -> String:
	var parts := slugify(text).split("_", false)
	var out := ""
	for p in parts:
		out += p.substr(0, 1).to_upper() + p.substr(1)
	return out if out != "" else "Node"


# --- Parsing ----------------------------------------------------------------

static func parse_vector3(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_VECTOR3I:
			return Vector3(value)
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY:
			if value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
		TYPE_DICTIONARY:
			if value.has("x") and value.has("z"):
				return Vector3(float(value.x), float(value.get("y", 0.0)), float(value.z))
		TYPE_STRING:
			var parts: PackedStringArray = (value as String).replace("(", "").replace(")", "").split(",")
			if parts.size() >= 3 and parts[0].strip_edges().is_valid_float():
				return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
		TYPE_INT, TYPE_FLOAT:
			return Vector3.ONE * float(value)
	return null


static func parse_vector2(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return value
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY:
			if value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
		TYPE_DICTIONARY:
			if value.has("x"):
				return Vector2(float(value.x), float(value.get("y", value.get("z", 0.0))))
	return null


## Accepts "#ff8800", "ff8800", Godot color names ("red"), Portuguese names
## ("vermelho"), [r,g,b(,a)] arrays (0..1 or 0..255) and Color values.
static func parse_color(value: Variant) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			return value
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY:
			if value.size() >= 3:
				var arr: Array = Array(value)
				var scale := 1.0
				for v in arr:
					if float(v) > 1.0:
						scale = 1.0 / 255.0
				var a := float(arr[3]) * scale if arr.size() > 3 else 1.0
				return Color(float(arr[0]) * scale, float(arr[1]) * scale, float(arr[2]) * scale, a)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := normalize_text(str(value)).strip_edges()
			if s == "":
				return null
			if PT_COLOR_NAMES.has(s):
				return PT_COLOR_NAMES[s]
			if EN_COLOR_NAMES.has(s):
				return EN_COLOR_NAMES[s]
			if s.is_valid_html_color():
				return Color.html(s)
			var named := Color.from_string(s, Color(0, 0, 0, -1))
			if named.a >= 0.0:
				return named
	return null


## Finds a color word inside a normalized phrase (used by the NL parser).
static func find_color_word(word: String) -> Variant:
	var w := normalize_text(word)
	if PT_COLOR_NAMES.has(w):
		return PT_COLOR_NAMES[w]
	if EN_COLOR_NAMES.has(w):
		return EN_COLOR_NAMES[w]
	return null


static func to_bool(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING, TYPE_STRING_NAME:
			var s := normalize_text(str(value)).strip_edges()
			return s in ["1", "true", "yes", "y", "on", "sim", "s", "verdadeiro"]
	return value != null


## Coerces a raw (JSON) value to the type declared in a command argument spec.
## Returns [ok: bool, value_or_error].
static func coerce(value: Variant, type_name: String) -> Array:
	match type_name:
		"string":
			if value is String:
				return [true, value]
			if value == null:
				return [false, "expected a string"]
			return [true, str(value)]
		"number":
			if value is float or value is int:
				return [true, float(value)]
			if value is String and (value as String).is_valid_float():
				return [true, (value as String).to_float()]
			return [false, "expected a number"]
		"integer":
			if value is int:
				return [true, value]
			if value is float:
				return [true, int(round(value))]
			if value is String and (value as String).is_valid_float():
				return [true, int(round((value as String).to_float()))]
			return [false, "expected an integer"]
		"boolean":
			return [true, to_bool(value)]
		"array":
			if value is Array:
				return [true, value]
			if value is String:
				var parsed = JSON.parse_string(value)
				if parsed is Array:
					return [true, parsed]
				return [true, Array((value as String).split(",", false))]
			return [false, "expected an array"]
		"object":
			if value is Dictionary:
				return [true, value]
			if value is String:
				var parsed = JSON.parse_string(value)
				if parsed is Dictionary:
					return [true, parsed]
			return [false, "expected an object"]
		"vector3":
			var v = parse_vector3(value)
			if v == null:
				return [false, "expected a vector [x, y, z]"]
			return [true, v]
		"color":
			var c = parse_color(value)
			if c == null:
				return [false, "expected a color ('#rrggbb', a name like 'red'/'vermelho' or [r,g,b])"]
			return [true, c]
		"position":
			# Resolved later by the handler (needs the terrain): [x,z], [x,y,z] or an anchor name.
			if value is String and (value as String).begins_with("["):
				var parsed = JSON.parse_string(value)
				if parsed is Array:
					return [true, parsed]
			return [true, value]
	return [true, value]


# --- JSON -------------------------------------------------------------------

## Converts any Variant into something JSON.stringify can serialize nicely.
static func to_json_safe(value: Variant, depth: int = 0) -> Variant:
	if depth > 16:
		return str(value)
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return null
			return snappedf(value, 0.0001)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001)]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return "#" + (value as Color).to_html(true)
		TYPE_RECT2, TYPE_RECT2I:
			return {"position": to_json_safe(value.position), "size": to_json_safe(value.size)}
		TYPE_AABB:
			return {"position": to_json_safe(value.position), "size": to_json_safe(value.size)}
		TYPE_BASIS:
			return {"rotation_degrees": to_json_safe(value.get_euler() * (180.0 / PI)), "scale": to_json_safe(value.get_scale())}
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return {
				"origin": to_json_safe(t.origin),
				"rotation_degrees": to_json_safe(t.basis.get_euler() * (180.0 / PI)),
				"scale": to_json_safe(t.basis.get_scale()),
			}
		TYPE_DICTIONARY:
			var out := {}
			for k in value:
				out[str(k)] = to_json_safe(value[k], depth + 1)
			return out
		TYPE_ARRAY:
			var arr := []
			for v in value:
				arr.append(to_json_safe(v, depth + 1))
			return arr
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if value.size() > 64:
				return "<%s with %d items>" % [type_string(typeof(value)), value.size()]
			var arr2 := []
			for v in value:
				arr2.append(to_json_safe(v, depth + 1))
			return arr2
		TYPE_OBJECT:
			if value == null or not is_instance_valid(value):
				return null
			if value is Node:
				return {"node": str((value as Node).name), "type": (value as Node).get_class()}
			if value is Resource:
				var r: Resource = value
				return {"resource": r.resource_path if r.resource_path != "" else "<built-in>", "type": r.get_class()}
			return "<%s>" % value.get_class()
	return str(value)


static func json_to_string(value: Variant, indent := "") -> String:
	return JSON.stringify(to_json_safe(value), indent)


## Recursively merges dictionary `b` into a copy of `a`.
static func deep_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.has(k) and out[k] is Dictionary and b[k] is Dictionary:
			out[k] = deep_merge(out[k], b[k])
		else:
			out[k] = b[k]
	return out


# --- Math -------------------------------------------------------------------

## Deterministic 2D hash in [0, 1).
static func hash01(x: int, y: int, seed_value: int = 0) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_value * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0


## Smooth brush falloff: 1 at the center, 0 at the edge. `hardness` in [0, 1].
static func falloff(dist: float, radius: float, hardness: float = 0.5) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var t := dist / radius
	var inner := clampf(hardness, 0.0, 0.99)
	if t <= inner:
		return 1.0
	var k := (t - inner) / (1.0 - inner)
	return 1.0 - k * k * (3.0 - 2.0 * k)


## Returns a list of points spaced `spacing` apart along a polyline.
static func resample_polyline(points: Array, spacing: float) -> Array:
	var out: Array = []
	if points.is_empty():
		return out
	out.append(points[0])
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg := a.distance_to(b)
		var steps := maxi(1, int(ceil(seg / maxf(spacing, 0.01))))
		for s in range(1, steps + 1):
			out.append(a.lerp(b, float(s) / float(steps)))
	return out


## Distance from point p to segment ab (2D).
static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Files ------------------------------------------------------------------

static func ensure_dir(res_dir: String) -> void:
	if res_dir == "":
		return
	var abs_path := ProjectSettings.globalize_path(res_dir)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)


## Normalizes user supplied paths to res:// (accepts "scenes/a.tscn" too).
static func to_res_path(path: String, default_ext: String = "") -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p == "":
		return ""
	if not (p.begins_with("res://") or p.begins_with("user://")):
		if p.is_absolute_path():
			var project_root := ProjectSettings.globalize_path("res://")
			if p.begins_with(project_root):
				p = "res://" + p.substr(project_root.length())
			else:
				return p
		else:
			p = "res://" + p.trim_prefix("./").trim_prefix("/")
	if default_ext != "" and p.get_extension() == "":
		p += "." + default_ext
	return p


static func is_safe_write_path(path: String) -> bool:
	return (path.begins_with("res://") or path.begins_with("user://")) and not path.contains("..")
