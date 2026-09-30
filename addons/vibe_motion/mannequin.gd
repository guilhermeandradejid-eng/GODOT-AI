@tool
extends RefCounted
## Procedural skinned character mesh (the "Vibe mannequin").
##
## The body is made of tapered capsules and ellipsoids rigidly bound to the
## humanoid bones (like an artist's wooden figure, so joints never tear), with
## clothes, hair, hats and faces, in the 5 art styles of the suite. Everything
## is generated in code: no external assets.
##
## Vertex COLOR.rgb = albedo, COLOR.a = material id (see the shaders).

const H = preload("res://addons/vibe_motion/humanoid.gd")
const Util = preload("res://addons/vibe_core/core/vibe_util.gd")
const SHADER_PBR = preload("res://addons/vibe_motion/shaders/character.gdshader")
const SHADER_TOON = preload("res://addons/vibe_motion/shaders/character_toon.gdshader")
const SHADER_OUTLINE = preload("res://addons/vibe_motion/shaders/character_outline.gdshader")

const STYLES := ["realistic", "stylized", "toon", "cel", "lowpoly"]

# Material ids (vertex alpha).
const CLOTH := 1.0
const SKIN := 0.8
const LEATHER := 0.6
const METAL := 0.4
const GLOW := 0.2
const EYE := 0.0

const DEFAULT_OUTFIT := {
	"description": "",
	"skin": "#d9a07a", "hair": "#3b2618", "hair_style": "short",
	"shirt": "#2f6fb5", "sleeves": "short", "pants": "#3a4d6b", "shorts": false,
	"shoes": "#f2f2f2", "sole": "#d6d6d6", "boots": false, "belt": "#3a2a1a",
	"eyes": "#2a1c14", "gloves": "", "hat": "", "hat_color": "#aa3333", "mask": "",
	"joints": "", "antenna": false, "face": true,
	"mat": {"skin": SKIN, "shirt": CLOTH, "pants": CLOTH, "shoes": LEATHER, "hat": CLOTH, "gloves": LEATHER, "eyes": EYE},
}

const OUTFITS := {
	"casual": {"description": "camiseta azul, jeans e tênis"},
	"mannequin": {"description": "manequim de madeira (ótimo para testar animações)",
		"skin": "#d9b48a", "shirt": "#d9b48a", "pants": "#d9b48a", "shoes": "#d9b48a", "sole": "#c7a077",
		"hair_style": "none", "sleeves": "none", "belt": "", "joints": "#b5885c", "face": false,
		"mat": {"skin": LEATHER, "shirt": LEATHER, "pants": LEATHER, "shoes": LEATHER}},
	"adventurer": {"description": "aventureiro: túnica verde, calça marrom e botas",
		"skin": "#c98e62", "hair": "#6b4423", "shirt": "#5f7f45", "sleeves": "long", "pants": "#6b5238",
		"shoes": "#3d2a1a", "sole": "#241810", "boots": true, "belt": "#2a1a0e"},
	"athlete": {"description": "atleta: regata vermelha, short e tênis",
		"skin": "#8d5a3b", "hair": "#1a1210", "shirt": "#d63a3a", "sleeves": "none", "pants": "#1e1e24",
		"shorts": true, "shoes": "#ffffff", "sole": "#ff5a36", "belt": ""},
	"ninja": {"description": "ninja todo de preto com faixa vermelha",
		"skin": "#e0b090", "hair": "#1b1b22", "hair_style": "hood", "shirt": "#1b1b22", "sleeves": "long",
		"pants": "#1b1b22", "shoes": "#121216", "sole": "#121216", "belt": "#b22222", "mask": "#1b1b22"},
	"robot": {"description": "robô metálico com olhos brilhantes",
		"skin": "#9aa5b1", "hair_style": "none", "shirt": "#c5ced8", "sleeves": "long", "pants": "#6d7885",
		"shoes": "#3b424b", "sole": "#2b3038", "belt": "#2f3540", "eyes": "#3fe6ff", "joints": "#2f3540",
		"antenna": true, "gloves": "#8e99a6",
		"mat": {"skin": METAL, "shirt": METAL, "pants": METAL, "shoes": METAL, "gloves": METAL, "eyes": GLOW}},
	"soldier": {"description": "soldado com uniforme verde e capacete",
		"skin": "#b98060", "hair_style": "none", "shirt": "#56633f", "sleeves": "long", "pants": "#4d5838",
		"shoes": "#2b2a22", "sole": "#1c1b16", "boots": true, "belt": "#2f2a1d", "hat": "helmet", "hat_color": "#46523a"},
	"knight": {"description": "cavaleiro de armadura",
		"skin": "#e0b090", "hair": "#5b3b1f", "shirt": "#b7bec6", "sleeves": "long", "pants": "#9aa2ab",
		"shoes": "#6d747c", "sole": "#4a4f55", "boots": true, "belt": "#6b3a1a", "gloves": "#8a929b",
		"hat": "helmet", "hat_color": "#b7bec6",
		"mat": {"shirt": METAL, "pants": METAL, "shoes": METAL, "gloves": METAL, "hat": METAL}},
	"wizard": {"description": "mago de manto roxo e chapéu pontudo",
		"skin": "#e8b896", "hair": "#d8d8d8", "hair_style": "long", "shirt": "#4b2a7a", "sleeves": "long",
		"pants": "#3d2263", "shoes": "#2a1a10", "sole": "#1a100a", "belt": "#c9a227", "hat": "wizard", "hat_color": "#3a1f63"},
	"zombie": {"description": "zumbi de pele esverdeada e roupa rasgada",
		"skin": "#7f9c6c", "hair": "#2b2b1f", "shirt": "#7a6a55", "pants": "#3f4660", "shoes": "#2b2520",
		"sole": "#1a1612", "belt": "", "eyes": "#e8e8a0"},
	"astronaut": {"description": "astronauta de traje branco",
		"skin": "#e0b090", "hair_style": "none", "shirt": "#eeeeee", "sleeves": "long", "pants": "#e6e6e6",
		"shoes": "#cfcfcf", "sole": "#8a8a8a", "boots": true, "gloves": "#d8d8d8", "belt": "#ff6a00",
		"hat": "helmet", "hat_color": "#f4f4f4", "mat": {"shoes": LEATHER, "gloves": LEATHER, "hat": LEATHER}},
	"king": {"description": "rei com coroa dourada e manto vermelho",
		"skin": "#e0b090", "hair": "#8a5a2b", "shirt": "#9e1b25", "sleeves": "long", "pants": "#2b2440",
		"shoes": "#3a2616", "sole": "#20150c", "boots": true, "belt": "#d4af37", "hat": "crown", "hat_color": "#e0b43a",
		"mat": {"hat": METAL}},
}

const ALIASES := {
	"padrao": "casual", "default": "casual", "pessoa": "casual", "person": "casual", "humano": "casual", "human": "casual",
	"manequim": "mannequin", "boneco": "mannequin", "wooden": "mannequin", "madeira": "mannequin",
	"aventureiro": "adventurer", "explorador": "adventurer", "explorer": "adventurer", "heroi": "adventurer", "hero": "adventurer",
	"atleta": "athlete", "corredor": "athlete", "runner": "athlete", "esportista": "athlete",
	"robo": "robot", "android": "robot", "androide": "robot", "ciborgue": "robot", "cyborg": "robot",
	"soldado": "soldier", "militar": "soldier",
	"cavaleiro": "knight", "armadura": "knight", "guerreiro": "knight", "warrior": "knight",
	"mago": "wizard", "bruxo": "wizard", "feiticeiro": "wizard", "mage": "wizard", "sorcerer": "wizard",
	"zumbi": "zombie", "morto_vivo": "zombie",
	"astronauta": "astronaut", "rei": "king", "rainha": "king", "queen": "king",
}

static var _cache := {}


static func outfit_names() -> Array:
	return OUTFITS.keys()


static func resolve_outfit_name(value: String) -> String:
	var k := Util.slugify(value)
	if OUTFITS.has(k):
		return k
	if ALIASES.has(k):
		return ALIASES[k]
	for word in k.split("_"):
		if OUTFITS.has(word):
			return word
		if ALIASES.has(word):
			return ALIASES[word]
	return ""


## Full outfit dictionary from a preset name and/or overrides
## ({"shirt": "red", "hat": "cap"...}).
static func resolve_outfit(preset: String, overrides: Dictionary = {}) -> Dictionary:
	var o: Dictionary = DEFAULT_OUTFIT.duplicate(true)
	var name := resolve_outfit_name(preset)
	if name == "":
		name = "casual"
	var p: Dictionary = OUTFITS[name]
	for k in p:
		if k == "mat":
			o.mat.merge(p.mat, true)
		else:
			o[k] = p[k]
	for k in overrides:
		if k == "mat" and overrides[k] is Dictionary:
			o.mat.merge(overrides[k], true)
		elif o.has(k):
			var v = overrides[k]
			if v is Color:
				v = "#" + (v as Color).to_html(false)
			o[k] = v
	o["name"] = name
	return o


static func _color(value: Variant, mat: float) -> Color:
	var c = Util.parse_color(value)
	var col: Color = c if c is Color else Color(0.8, 0.8, 0.8)
	col.a = mat
	return col


# --- Mesh ---------------------------------------------------------------------------

class MeshAcc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var flat := false
	var bone_index := {}

	func _bone_of(bone: Variant, p: Vector3) -> Array:
		if bone is Callable:
			return (bone as Callable).call(p)
		if bone is Array:
			return bone
		return [bone, bone, 0.0]

	func _color_of(color: Variant, p: Vector3) -> Color:
		if color is Callable:
			return (color as Callable).call(p)
		return color

	func _push(p: Vector3, nn: Vector3, color: Variant, bone: Variant) -> int:
		var b: Array = _bone_of(bone, p)
		var i0: int = bone_index[b[0]]
		var i1: int = bone_index[b[1]]
		var w1: float = b[2]
		v.append(p)
		n.append(nn)
		c.append(_color_of(color, p))
		bones.append_array([i0, i1, 0, 0])
		weights.append_array([1.0 - w1, w1, 0.0, 0.0])
		return v.size() - 1

	## Surface of revolution around `axis` (from `origin`). profile: Array of
	## Vector3(t, r_side, r_front) with t measured along the axis; r = 0 at
	## both ends closes the shape. `front` orients the cross-section.
	## opts: expo (2 = ellipse, >2 = rounded box), min_y (flattens below).
	func lathe(origin: Vector3, axis: Vector3, front: Vector3, profile: Array, radial: int, color: Variant, bone: Variant, opts: Dictionary = {}) -> void:
		var u := axis.normalized()
		var f := front - u * front.dot(u)
		if f.length() < 0.001:
			f = Vector3.FORWARD if absf(u.z) < 0.9 else Vector3.UP
			f = f - u * f.dot(u)
		f = f.normalized()
		var s := u.cross(f).normalized()
		var expo: float = opts.get("expo", 2.0)
		var min_y: float = opts.get("min_y", -INF)
		var rings: Array = []
		for pr in profile:
			var t: float = pr.x
			var rs: float = pr.y
			var rf: float = pr.z
			var off := 0.0
			if pr is Vector4:
				off = (pr as Vector4).w
			var ring := PackedVector3Array()
			var center := origin + u * t + f * off
			for k in radial:
				var th := TAU * float(k) / float(radial)
				var cs := cos(th)
				var sn := sin(th)
				if expo != 2.0:
					cs = signf(cs) * pow(absf(cs), 2.0 / expo)
					sn = signf(sn) * pow(absf(sn), 2.0 / expo)
				var p := center + s * (cs * rs) + f * (sn * rf)
				if p.y < min_y:
					p.y = min_y
				ring.append(p)
			rings.append(ring)
		_grid(rings, radial, u, color, bone)

	func _grid(rings: Array, radial: int, u: Vector3, color: Variant, bone: Variant) -> void:
		var nr := rings.size()
		if flat:
			for i in nr - 1:
				var a: PackedVector3Array = rings[i]
				var b: PackedVector3Array = rings[i + 1]
				for k in radial:
					var k1 := (k + 1) % radial
					_flat_tri(a[k], a[k1], b[k], color, bone)
					_flat_tri(a[k1], b[k1], b[k], color, bone)
			return
		# Smooth: accumulate face normals per vertex (area weighted).
		var acc: Array = []
		for i in nr:
			var row := PackedVector3Array()
			row.resize(radial)
			acc.append(row)
		for i in nr - 1:
			var a: PackedVector3Array = rings[i]
			var b: PackedVector3Array = rings[i + 1]
			var ra: PackedVector3Array = acc[i]
			var rb: PackedVector3Array = acc[i + 1]
			for k in radial:
				var k1 := (k + 1) % radial
				var n1 := (b[k] - a[k]).cross(a[k1] - a[k])
				var n2 := (b[k] - a[k1]).cross(b[k1] - a[k1])
				ra[k] += n1
				ra[k1] += n1 + n2
				rb[k] += n1 + n2
				rb[k1] += n2
			acc[i] = ra
			acc[i + 1] = rb
		var base := v.size()
		for i in nr:
			var ring: PackedVector3Array = rings[i]
			var row: PackedVector3Array = acc[i]
			var pole := ring[0].distance_squared_to(ring[radial / 2]) < 1e-10
			for k in radial:
				var nn := row[k]
				if pole:
					nn = -u if i == 0 else u
				if nn.length_squared() < 1e-14:
					nn = u
				_push(ring[k], nn.normalized(), color, bone)
		for i in nr - 1:
			for k in radial:
				var k1 := (k + 1) % radial
				var p00 := base + i * radial + k
				var p01 := base + i * radial + k1
				var p10 := base + (i + 1) * radial + k
				var p11 := base + (i + 1) * radial + k1
				# Clockwise seen from outside (Godot's front faces).
				idx.append_array([p00, p01, p10, p01, p11, p10])

	func _flat_tri(a: Vector3, b: Vector3, cc: Vector3, color: Variant, bone: Variant) -> void:
		var nn := (cc - a).cross(b - a)
		if nn.length_squared() < 1e-14:
			return
		nn = nn.normalized()
		var mid := (a + b + cc) / 3.0
		var col := _color_of(color, mid)
		var bb := _bone_of(bone, mid)
		for p in [a, b, cc]:
			idx.append(_push(p, nn, col, bb))

	func ellipsoid(center: Vector3, radii: Vector3, rings: int, radial: int, color: Variant, bone: Variant, opts: Dictionary = {}) -> void:
		var prof: Array = []
		for i in rings + 1:
			var a := PI * float(i) / float(rings)
			prof.append(Vector3(-radii.y * cos(a), radii.x * sin(a), radii.z * sin(a)))
		lathe(center, Vector3.UP, Vector3.FORWARD, prof, radial, color, bone, opts)

	## Capsule from a to b with radius ra at a and rb at b.
	func capsule(a: Vector3, b: Vector3, ra: float, rb: float, cap: int, radial: int, color: Variant, bone: Variant, front: Vector3 = Vector3.ZERO, flatten: float = 1.0) -> void:
		var axis := b - a
		var length := axis.length()
		var prof: Array = []
		for k in cap + 1:
			var ang := PI * 0.5 * (1.0 - float(k) / float(cap))
			prof.append(Vector3(-ra * sin(ang), ra * cos(ang), ra * cos(ang) * flatten))
		var mid := maxi(1, int(length / 0.08))
		for k in range(1, mid):
			var t := float(k) / float(mid)
			var r := lerpf(ra, rb, t)
			prof.append(Vector3(length * t, r, r * flatten))
		for k in cap + 1:
			var ang := PI * 0.5 * float(k) / float(cap)
			prof.append(Vector3(length + rb * sin(ang), rb * cos(ang), rb * cos(ang) * flatten))
		var fr := front
		if fr == Vector3.ZERO:
			fr = Vector3.FORWARD if absf(axis.normalized().z) < 0.9 else Vector3.UP
		lathe(a, axis, fr, prof, radial, color, bone)

	func commit(scale: float) -> ArrayMesh:
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		uv.resize(v.size())
		uv2.resize(v.size())
		for i in v.size():
			var p := v[i]
			uv[i] = Vector2(p.x, p.y)
			uv2[i] = Vector2(p.z, 0.0)
			v[i] = p * scale
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Builds (or returns the cached) body mesh. Vertices are in skeleton space at
## rest, bone indices follow the humanoid bone order.
static func build_mesh(outfit: Dictionary, style: String = "realistic", height: float = H.HEIGHT) -> ArrayMesh:
	var key := JSON.stringify([outfit, style, snappedf(height, 0.001)])
	if _cache.has(key):
		return _cache[key]
	var acc := MeshAcc.new()
	acc.flat = style == "lowpoly"
	var names := H.bone_names()
	for i in names.size():
		acc.bone_index[names[i]] = i
	_body(acc, outfit, style)
	var mesh := acc.commit(height / H.HEIGHT)
	_cache[key] = mesh
	return mesh


static func _body(acc: MeshAcc, o: Dictionary, style: String) -> void:
	var low := style == "lowpoly"
	var toonish := style in ["toon", "cel", "stylized"]
	var R := 7 if low else (18 if style == "realistic" else 16)
	var RS := 4 if low else 9
	var RINGS := 5 if low else 12
	var CAP := 2 if low else 5
	var mat: Dictionary = o.mat
	var skin := _color(o.skin, float(mat.get("skin", SKIN)))
	var shirt := _color(o.shirt, float(mat.get("shirt", CLOTH)))
	var pants := _color(o.pants, float(mat.get("pants", CLOTH)))
	var shoes := _color(o.shoes, float(mat.get("shoes", LEATHER)))
	var sole := _color(o.sole, LEATHER)
	var hair := _color(o.hair, CLOTH)
	var hand := _color(o.gloves, float(mat.get("gloves", LEATHER))) if str(o.gloves) != "" else skin
	var belt: Variant = _color(o.belt, LEATHER) if str(o.belt) != "" else null
	var mask: Variant = _color(o.mask, CLOTH) if str(o.mask) != "" else null
	var joints: Variant = _color(o.joints, float(mat.get("skin", SKIN))) if str(o.joints) != "" else null
	var boots := bool(o.boots)
	var shorts := bool(o.shorts)
	var P := func(b: String) -> Vector3: return H.rest_position(b)

	# --- torso: one smooth shape skinned along the spine ---------------------
	var torso_col := func(p: Vector3) -> Color:
		if p.y < 1.005:
			return belt if belt != null and p.y > 0.975 else pants
		return shirt
	var torso_bone := func(p: Vector3) -> Array:
		if p.y < 0.99:
			return ["Hips", "Hips", 0.0]
		if p.y < 1.07:
			return ["Hips", "Spine", smoothstep(0.99, 1.07, p.y)]
		if p.y < 1.17:
			return ["Spine", "Chest", smoothstep(1.07, 1.17, p.y)]
		if p.y < 1.29:
			return ["Chest", "UpperChest", smoothstep(1.17, 1.29, p.y)]
		return ["UpperChest", "UpperChest", 0.0]
	var torso := [Vector4(0.0, 0.0, 0.0, 0.0), Vector4(0.015, 0.1, 0.075, -0.005), Vector4(0.05, 0.145, 0.104, -0.01),
		Vector4(0.1, 0.158, 0.112, -0.012), Vector4(0.15, 0.153, 0.108, -0.008), Vector4(0.2, 0.141, 0.101, 0.0),
		Vector4(0.25, 0.138, 0.101, 0.006), Vector4(0.31, 0.148, 0.107, 0.01), Vector4(0.37, 0.16, 0.113, 0.012),
		Vector4(0.44, 0.168, 0.116, 0.012), Vector4(0.5, 0.172, 0.111, 0.006), Vector4(0.55, 0.175, 0.103, -0.004),
		Vector4(0.59, 0.166, 0.092, -0.01), Vector4(0.62, 0.138, 0.076, -0.012), Vector4(0.64, 0.09, 0.062, -0.012),
		Vector4(0.655, 0.055, 0.05, -0.012), Vector4(0.66, 0.0, 0.0, -0.012)]
	acc.lathe(Vector3(0, 0.83, 0), Vector3.UP, Vector3.BACK, torso, R + 4, torso_col, torso_bone, {"expo": 2.3})
	var neck_col: Variant = skin if mask == null else mask
	acc.capsule(Vector3(0, 1.42, -0.012), Vector3(0, 1.6, 0.0), 0.056, 0.05, CAP, R, neck_col, "Neck")

	# --- head ------------------------------------------------------------
	var face: Variant = skin
	if mask != null:
		face = func(p: Vector3) -> Color: return mask if p.y < 1.676 and p.z > -0.03 else skin
	acc.ellipsoid(Vector3(0, 1.69, 0.012), Vector3(0.09, 0.115, 0.104), RINGS, R, face, "Head")
	acc.ellipsoid(Vector3(0, 1.628, 0.035), Vector3(0.068, 0.058, 0.07), RINGS, R, face, "Head")
	if bool(o.face):
		acc.ellipsoid(Vector3(0, 1.672, 0.112), Vector3(0.015, 0.023, 0.019), maxi(3, RINGS / 2), maxi(4, R / 2), face, "Head")
		for sx in [1.0, -1.0]:
			acc.ellipsoid(Vector3(0.09 * sx, 1.68, 0.0), Vector3(0.014, 0.029, 0.021), maxi(3, RINGS / 2), maxi(4, R / 2), skin, "Head")
		var eye_mat := float(mat.get("eyes", EYE))
		var eye_col := _color(o.eyes, eye_mat)
		for sx in [1.0, -1.0]:
			if style == "realistic" and eye_mat == EYE:
				acc.ellipsoid(Vector3(0.034 * sx, 1.696, 0.098), Vector3(0.0128, 0.0128, 0.0128), 8, 10, _color("#f3efe6", EYE), "Head")
				acc.ellipsoid(Vector3(0.034 * sx, 1.696, 0.1098), Vector3(0.0068, 0.0068, 0.0024), 6, 10, eye_col, "Head")
			elif low:
				acc.ellipsoid(Vector3(0.035 * sx, 1.695, 0.1), Vector3(0.012, 0.013, 0.008), 3, 4, eye_col, "Head")
			else:
				acc.ellipsoid(Vector3(0.035 * sx, 1.694, 0.1), Vector3(0.0115, 0.018, 0.009), 8, 10, eye_col, "Head")
			if not low and str(o.hair_style) != "hood":
				var brow := hair if str(o.hair_style) != "none" else _color(Color(skin).darkened(0.45), SKIN)
				acc.ellipsoid(Vector3(0.037 * sx, 1.724, 0.103), Vector3(0.02, 0.0045, 0.008), 4, 8, brow, "Head")
		if toonish and mask == null:
			acc.ellipsoid(Vector3(0, 1.632, 0.1), Vector3(0.017, 0.0032, 0.006), 4, 8, _color("#5a2a26", EYE), "Head")
	_hair(acc, o, hair, RINGS, R)
	_hat(acc, o, RINGS, R)
	if bool(o.antenna):
		acc.capsule(Vector3(0, 1.79, -0.01), Vector3(0, 1.9, -0.02), 0.006, 0.005, CAP, RS, _color(o.pants, METAL), "Head")
		acc.ellipsoid(Vector3(0, 1.905, -0.02), Vector3(0.016, 0.016, 0.016), 6, RS, _color(o.eyes, GLOW), "Head")

	# --- arms and hands --------------------------------------------------------
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ua: Vector3 = P.call(side + "UpperArm")
		var la: Vector3 = P.call(side + "LowerArm")
		var hd: Vector3 = P.call(side + "Hand")
		var sleeve := shirt if str(o.sleeves) != "none" else skin
		var fore := shirt if str(o.sleeves) == "long" else skin
		acc.capsule(ua + Vector3(0.004 * sx, 0, 0), la, 0.056, 0.045, CAP, R, sleeve, side + "UpperArm")
		acc.ellipsoid(ua + Vector3(-0.004 * sx, -0.006, -0.004), Vector3(0.058, 0.054, 0.058), RINGS, R, sleeve, side + "UpperArm")
		acc.capsule(la, hd - Vector3(0.01 * sx, 0, 0), 0.046, 0.033, CAP, R, fore, side + "LowerArm")
		if joints != null:
			acc.ellipsoid(la, Vector3.ONE * 0.047, RINGS, R, joints, side + "LowerArm")
			acc.ellipsoid(hd, Vector3.ONE * 0.034, RINGS, R, joints, side + "Hand")
		# Palm: a rounded slab from the wrist to the knuckles.
		var palm := [Vector3(-0.012, 0, 0), Vector3(-0.004, 0.024, 0.012), Vector3(0.012, 0.04, 0.02),
			Vector3(0.07, 0.044, 0.021), Vector3(0.094, 0.04, 0.017), Vector3(0.104, 0, 0)]
		acc.lathe(hd + Vector3(0, -0.003, -0.003), Vector3(sx, 0, 0), Vector3.UP, palm, 8 if not low else 5, hand, side + "Hand", {"expo": 3.0})
		for f in H.FINGERS:
			var r: float = {"Index": 0.0098, "Middle": 0.0103, "Ring": 0.0096, "Little": 0.0083}[f]
			var p0: Vector3 = P.call(side + f + "Proximal")
			var p1: Vector3 = P.call(side + f + "Intermediate")
			var p2: Vector3 = P.call(side + f + "Distal")
			var tip := p2 + Vector3(0.021 * sx, 0, 0)
			acc.capsule(p0, p1, r, r * 0.95, 2, RS, hand, side + f + "Proximal")
			acc.capsule(p1, p2, r * 0.95, r * 0.9, 2, RS, hand, side + f + "Intermediate")
			acc.capsule(p2, tip, r * 0.9, r * 0.82, 2, RS, hand, side + f + "Distal")
		var t0: Vector3 = P.call(side + "ThumbMetacarpal")
		var t1: Vector3 = P.call(side + "ThumbProximal")
		var t2: Vector3 = P.call(side + "ThumbDistal")
		var tdir := (t2 - t1).normalized()
		acc.capsule(t0, t1, 0.017, 0.013, 2, RS, hand, side + "ThumbMetacarpal")
		acc.capsule(t1, t2, 0.012, 0.0115, 2, RS, hand, side + "ThumbProximal")
		acc.capsule(t2, t2 + tdir * 0.025, 0.0112, 0.0095, 2, RS, hand, side + "ThumbDistal")

		# --- legs and shoes ----------------------------------------------------
		var ul: Vector3 = P.call(side + "UpperLeg")
		var ll: Vector3 = P.call(side + "LowerLeg")
		var ft: Vector3 = P.call(side + "Foot")
		var thigh: Variant = pants
		if shorts:
			thigh = func(p: Vector3) -> Color: return skin if p.y < 0.63 else pants
		acc.capsule(ul + Vector3(0, 0.03, 0), ll, 0.084, 0.058, CAP, R, thigh, side + "UpperLeg")
		var shin: Variant = skin if shorts else pants
		if boots:
			var above: Color = skin if shorts else pants
			shin = func(p: Vector3) -> Color: return shoes if p.y < 0.3 else above
		acc.capsule(ll, ft + Vector3(0, 0.02, 0), 0.057, 0.038, CAP, R, shin, side + "LowerLeg")
		acc.ellipsoid(ll + Vector3(0, -0.14, -0.022), Vector3(0.05, 0.11, 0.048), RINGS, R, shin, side + "LowerLeg")
		if joints != null:
			acc.ellipsoid(ll, Vector3.ONE * 0.06, RINGS, R, joints, side + "LowerLeg")
			acc.ellipsoid(ul, Vector3.ONE * 0.07, RINGS, R, joints, side + "UpperLeg")
		var toe_bone: String = side + "Toes"
		var foot_bone: String = side + "Foot"
		var shoe_bone := func(p: Vector3) -> Array:
			return [foot_bone, toe_bone, smoothstep(0.105, 0.145, p.z)]
		var shoe_col := func(p: Vector3) -> Color: return sole if p.y < 0.013 else shoes
		var shoe := [Vector3(0, 0, 0), Vector3(0.012, 0.028, 0.04), Vector3(0.04, 0.037, 0.055), Vector3(0.09, 0.043, 0.06),
			Vector3(0.15, 0.047, 0.05), Vector3(0.21, 0.05, 0.038), Vector3(0.255, 0.043, 0.03), Vector3(0.283, 0.03, 0.022), Vector3(0.294, 0, 0)]
		acc.lathe(Vector3(ft.x, 0.058, -0.078), Vector3(0, -0.028, 0.293), Vector3.UP, shoe, R, shoe_col, shoe_bone, {"min_y": 0.0})
	if joints != null:
		acc.ellipsoid(P.call("Neck"), Vector3.ONE * 0.05, RINGS, R, joints, "Neck")


static func _hair(acc: MeshAcc, o: Dictionary, hair: Color, rings: int, radial: int) -> void:
	var style := str(o.hair_style)
	if style == "none" or style == "":
		return
	if style == "hood":
		acc.ellipsoid(Vector3(0, 1.70, -0.008), Vector3(0.104, 0.125, 0.115), rings, radial, hair, "Head")
		acc.ellipsoid(Vector3(0, 1.575, -0.045), Vector3(0.1, 0.12, 0.08), rings, radial, hair, "Head")
		return
	acc.ellipsoid(Vector3(0, 1.715, -0.012), Vector3(0.099, 0.11, 0.108), rings, radial, hair, "Head")
	match style:
		"long":
			acc.ellipsoid(Vector3(0, 1.6, -0.06), Vector3(0.104, 0.165, 0.066), rings, radial, hair, "Head")
		"ponytail":
			acc.ellipsoid(Vector3(0, 1.7, -0.12), Vector3(0.035, 0.035, 0.035), rings, radial, hair, "Head")
			acc.capsule(Vector3(0, 1.69, -0.13), Vector3(0, 1.52, -0.15), 0.03, 0.018, 4, radial, hair, "Head")
		"bun":
			acc.ellipsoid(Vector3(0, 1.79, -0.08), Vector3(0.05, 0.045, 0.05), rings, radial, hair, "Head")


static func _hat(acc: MeshAcc, o: Dictionary, rings: int, radial: int) -> void:
	var kind := str(o.hat)
	if kind == "" or kind == "none":
		return
	var col := _color(o.hat_color, float(o.mat.get("hat", CLOTH)))
	match kind:
		"cap", "bone":
			acc.ellipsoid(Vector3(0, 1.735, -0.005), Vector3(0.104, 0.085, 0.113), rings, radial, col, "Head", {"min_y": 1.735})
			acc.ellipsoid(Vector3(0, 1.738, 0.112), Vector3(0.078, 0.008, 0.07), rings, radial, col, "Head")
		"wizard", "mago":
			acc.ellipsoid(Vector3(0, 1.772, -0.005), Vector3(0.19, 0.012, 0.19), rings, radial, col, "Head")
			var prof := [Vector3(0, 0.115, 0.115), Vector3(0.12, 0.08, 0.08), Vector3(0.24, 0.045, 0.045), Vector3(0.34, 0.012, 0.012), Vector3(0.365, 0, 0)]
			acc.lathe(Vector3(0, 1.772, -0.005), Vector3(0, 1.0, -0.2), Vector3.FORWARD, prof, radial, col, "Head")
		"helmet", "capacete":
			acc.ellipsoid(Vector3(0, 1.73, -0.005), Vector3(0.108, 0.1, 0.118), rings, radial, col, "Head", {"min_y": 1.718})
		"crown", "coroa":
			var ring := [Vector3(0, 0.08, 0.08), Vector3(0, 0.094, 0.094), Vector3(0.05, 0.094, 0.094), Vector3(0.05, 0.08, 0.08), Vector3(0, 0.08, 0.08)]
			acc.lathe(Vector3(0, 1.765, -0.005), Vector3.UP, Vector3.FORWARD, ring, radial, col, "Head")
			for k in 6:
				var a := TAU * float(k) / 6.0
				var base := Vector3(sin(a) * 0.087, 1.81, -0.005 + cos(a) * 0.087)
				acc.capsule(base, base + Vector3(0, 0.035, 0), 0.012, 0.004, 2, 6, col, "Head")


## Material for a style (with an outline pass for toon / cel).
static func make_material(style: String) -> Material:
	var m := ShaderMaterial.new()
	match style:
		"toon":
			m.shader = SHADER_TOON
			m.set_shader_parameter("soft", 0.0)
			m.set_shader_parameter("bands", 3.0)
			m.set_shader_parameter("band_softness", 0.05)
			m.set_shader_parameter("rim_strength", 0.35)
			m.next_pass = _outline(0.006, Color(0.07, 0.06, 0.1))
		"cel":
			m.shader = SHADER_TOON
			m.set_shader_parameter("soft", 0.0)
			m.set_shader_parameter("bands", 2.0)
			m.set_shader_parameter("band_softness", 0.012)
			m.set_shader_parameter("shadow_tint", Color(0.55, 0.52, 0.82))
			m.set_shader_parameter("shadow_floor", 0.55)
			m.set_shader_parameter("rim_strength", 0.55)
			m.next_pass = _outline(0.009, Color(0.03, 0.02, 0.05))
		"stylized":
			m.shader = SHADER_TOON
			m.set_shader_parameter("soft", 1.0)
			m.set_shader_parameter("shadow_floor", 0.5)
			m.set_shader_parameter("rim_strength", 0.3)
		"lowpoly":
			m.shader = SHADER_PBR
			m.set_shader_parameter("fabric_detail", 0.0)
			m.set_shader_parameter("cloth_sheen", 0.1)
		_:
			m.shader = SHADER_PBR
	return m


static func _outline(width: float, color: Color) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = SHADER_OUTLINE
	o.set_shader_parameter("width", width)
	o.set_shader_parameter("outline_color", color)
	return o
