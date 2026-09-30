@tool
extends RefCounted
## Procedural text-to-motion synthesizer (no model download needed).
##
## A plan (see motion_text.gd) is a list of segments ("walk 5 steps", "wave",
## "sit"...). Each clip is a function of time that returns a pose *spec*:
## targets and angles (hips offset, spine/head angles, arm directions or hand
## targets, foot targets...). Specs are solved every frame with FK + two-bone
## IK, so planted feet do not slide; segments are crossfaded and root motion
## (walking, turning, jumping forward) is integrated on the "Root" bone.
##
## Spec keys (x is mirrored per side: x > 0 = away from the body):
##   hips: Vector3 offset (m) | hips_rot / spine / head: Vector3(pitch, yaw, roll) deg
##     (pitch > 0 bends forward / looks down, yaw > 0 turns left, roll > 0 tilts right)
##   sh_L / sh_R: Vector2(raise, forward) deg (shoulder blades)
##   arm_L / arm_R: {du, df, palm[, hand]} chest-relative directions of upper arm,
##     forearm, palm normal (and hand) | or {ik: target, pole, palm, hand, chest: bool}
##   foot_L / foot_R: {pos: ankle target (root frame), pitch (heel up > 0), yaw (toe out), knee: pole, ground}
##   leg_L / leg_R: {flex, abd, knee, ankle, twist} FK angles in degrees (kicks, lying)
##   curl_L / curl_R: finger curl 0..1 | point_L/R: index straight 0..1 | thumb_L/R
##   vel: root velocity (m/s, character frame) | turn: root yaw speed (deg/s, + = left)

const H = preload("res://addons/vibe_motion/humanoid.gd")

const DEG := PI / 180.0
const SIDES := ["Left", "Right"]
const PHAL := ["Proximal", "Intermediate", "Distal"]
const SPINE_W := [0.34, 0.33, 0.33]
const FINGER_ANG := [72.0, 95.0, 62.0]
const ANKLE_Y := 0.08
const ANKLE_OFF := Vector3(0, 0.08, 0.0)
const BALL_OFF := Vector3(0, 0.015, 0.14)
const HEEL_OFF := Vector3(0, 0.0, -0.065)
const DEFAULT_ARM := {"du": Vector3(0.13, -1.0, 0.02), "df": Vector3(0.09, -1.0, 0.24), "palm": Vector3(-1.0, 0.0, 0.25)}
const DEFAULT_FOOT := {"pos": Vector3(0.1, ANKLE_Y, -0.01), "yaw": 6.0}
const DEFAULT_CROSSFADE := 0.3

## Clip catalogue: duration (seconds, per repetition for counted clips),
## loop (cyclic, repeats seamlessly), end (state after the clip), upper (the
## clip only moves the upper body, so it can run while sitting/walking).
const CLIPS := {
	"idle": {"dur": 4.0, "loop": true, "upper": true, "desc": "parado, respirando"},
	"walk": {"dur": 4.0, "loop": true, "loco": true, "desc": "andar"},
	"run": {"dur": 3.0, "loop": true, "loco": true, "desc": "correr"},
	"sneak": {"dur": 4.0, "loop": true, "loco": true, "desc": "andar furtivo, agachado"},
	"march": {"dur": 4.0, "loop": true, "loco": true, "desc": "marchar"},
	"jump": {"dur": 1.45, "count": true, "desc": "pular"},
	"jumping_jacks": {"dur": 1.0, "count": true, "loop": true, "desc": "polichinelo"},
	"spin": {"dur": 1.6, "count": true, "desc": "girar no lugar"},
	"turn": {"dur": 1.2, "desc": "virar (esquerda/direita/meia volta)"},
	"wave": {"dur": 2.6, "upper": true, "desc": "acenar"},
	"clap": {"dur": 2.4, "upper": true, "loop": true, "desc": "bater palmas"},
	"point": {"dur": 2.2, "upper": true, "desc": "apontar"},
	"cheer": {"dur": 2.6, "desc": "comemorar, vibrar"},
	"dance": {"dur": 4.0, "loop": true, "desc": "dançar"},
	"sit": {"dur": 2.5, "end": "sit", "desc": "sentar (cadeira)"},
	"sit_ground": {"dur": 2.8, "end": "ground", "desc": "sentar no chão"},
	"meditate": {"dur": 4.0, "end": "ground", "desc": "meditar"},
	"stand_up": {"dur": 1.6, "end": "stand", "desc": "levantar"},
	"crouch": {"dur": 2.0, "end": "crouch", "desc": "agachar"},
	"squats": {"dur": 1.8, "count": true, "desc": "agachamentos"},
	"kneel": {"dur": 2.2, "end": "kneel", "desc": "ajoelhar"},
	"lie": {"dur": 3.2, "end": "lie", "desc": "deitar"},
	"fall": {"dur": 2.4, "end": "lie", "desc": "cair"},
	"die": {"dur": 2.8, "end": "prone", "desc": "morrer"},
	"hit": {"dur": 1.2, "desc": "levar um golpe"},
	"bow": {"dur": 2.4, "desc": "reverência"},
	"salute": {"dur": 2.2, "upper": true, "desc": "continência"},
	"nod": {"dur": 1.6, "upper": true, "desc": "sim com a cabeça"},
	"shake_head": {"dur": 1.6, "upper": true, "desc": "não com a cabeça"},
	"look_around": {"dur": 3.6, "upper": true, "desc": "olhar em volta"},
	"shrug": {"dur": 1.8, "upper": true, "desc": "dar de ombros"},
	"stretch": {"dur": 3.2, "desc": "espreguiçar"},
	"talk": {"dur": 4.0, "upper": true, "loop": true, "desc": "conversar, gesticular"},
	"think": {"dur": 3.0, "upper": true, "loop": true, "desc": "pensar (mão no queixo)"},
	"cross_arms": {"dur": 3.0, "upper": true, "loop": true, "desc": "braços cruzados"},
	"hands_on_hips": {"dur": 3.0, "upper": true, "loop": true, "desc": "mãos na cintura"},
	"pray": {"dur": 3.0, "upper": true, "loop": true, "desc": "rezar"},
	"cry": {"dur": 3.0, "upper": true, "loop": true, "desc": "chorar"},
	"laugh": {"dur": 2.5, "upper": true, "desc": "rir, gargalhar"},
	"punch": {"dur": 0.75, "count": true, "desc": "socar (alterna mãos)"},
	"kick": {"dur": 1.3, "count": true, "desc": "chutar"},
	"slash": {"dur": 1.1, "count": true, "desc": "golpe de espada"},
	"cast": {"dur": 2.2, "desc": "lançar magia"},
	"throw": {"dur": 1.6, "desc": "arremessar"},
	"pick_up": {"dur": 2.6, "desc": "pegar algo do chão"},
	"push": {"dur": 3.0, "loop": true, "loco": true, "desc": "empurrar algo pesado"},
	"guard": {"dur": 2.0, "loop": true, "desc": "posição de luta"},
	"aim": {"dur": 2.5, "upper": true, "desc": "mirar/atirar"},
	"fly": {"dur": 3.0, "loop": true, "desc": "voar como super-herói"},
	"pushups": {"dur": 1.6, "count": true, "desc": "flexões"},
}

## Moods change posture, speed and energy of every clip.
const MOODS := {
	"happy": {"speed": 1.12, "bob": 1.8, "arm": 1.3, "lean": -3.0, "head": -6.0, "spine": -3.0, "sh": Vector2(0, -3), "amp": 1.15},
	"sad": {"speed": 0.72, "bob": 0.5, "arm": 0.35, "lean": 7.0, "head": 24.0, "spine": 9.0, "sh": Vector2(-4, 12), "lift": 0.7, "amp": 0.7, "curl": 0.15},
	"tired": {"speed": 0.62, "bob": 0.6, "arm": 0.3, "lean": 9.0, "head": 14.0, "spine": 7.0, "sh": Vector2(-6, 8), "lift": 0.5, "amp": 0.6},
	"angry": {"speed": 1.2, "bob": 1.2, "arm": 1.45, "lean": 8.0, "head": 6.0, "spine": 4.0, "sh": Vector2(6, 4), "curl": 1.0, "elbow": 25.0, "amp": 1.25},
	"confident": {"speed": 0.95, "bob": 1.0, "arm": 1.35, "lean": -4.0, "head": -8.0, "spine": -6.0, "sh": Vector2(-3, -9), "pyaw": 1.7, "amp": 1.1},
	"scared": {"speed": 1.15, "bob": 0.6, "arm": 0.5, "lean": 12.0, "head": 4.0, "spine": 9.0, "sh": Vector2(12, 9), "crouch": 0.08, "curl": 0.75, "amp": 0.8},
}

## Styles are stronger changes to the way of moving.
const STYLE_NAMES := ["robot", "zombie", "drunk", "ninja", "cartoon", "elegant", "old", "limp"]

var rest := {}
var len_thigh := 0.0
var len_shin := 0.0
var len_upper := 0.0
var len_fore := 0.0
var dir_thigh := Vector3.DOWN
var dir_shin := Vector3.DOWN
var seed_value := 0


class Pose:
	var j := {}
	var hips := Vector3.ZERO
	var vel := Vector3.ZERO
	var turn := 0.0

	func rot(b: String) -> Quaternion:
		return j.get(b, Quaternion.IDENTITY)


func _init() -> void:
	for b in H.bone_names():
		rest[b] = H.rest_position(b)
	len_thigh = rest.LeftUpperLeg.distance_to(rest.LeftLowerLeg)
	len_shin = rest.LeftLowerLeg.distance_to(rest.LeftFoot)
	len_upper = rest.LeftUpperArm.distance_to(rest.LeftLowerArm)
	len_fore = rest.LeftLowerArm.distance_to(rest.LeftHand)
	dir_thigh = (rest.LeftLowerLeg - rest.LeftUpperLeg).normalized()
	dir_shin = (rest.LeftFoot - rest.LeftLowerLeg).normalized()


# =============================================================================
# Math helpers
# =============================================================================

static func qx(deg: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg * DEG)


static func qy(deg: float) -> Quaternion:
	return Quaternion(Vector3.UP, deg * DEG)


static func qz(deg: float) -> Quaternion:
	return Quaternion(Vector3.BACK, deg * DEG)


## Vector3(pitch, yaw, roll) in degrees -> rotation in character axes.
static func euler(v: Vector3) -> Quaternion:
	return qy(v.y) * qx(v.x) * qz(v.z)


static func perp(v: Vector3, axis: Vector3, fallback: Vector3) -> Vector3:
	var p := v - axis * v.dot(axis)
	if p.length() < 0.02:
		p = fallback - axis * fallback.dot(axis)
		if p.length() < 0.001:
			p = Vector3.UP - axis * axis.y if absf(axis.y) < 0.9 else Vector3.BACK - axis * axis.z
	return p.normalized()


## Rotation mapping a0 -> a1 and b0 -> b1 (b made perpendicular to a).
static func frame_rot(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3) -> Quaternion:
	var x0 := a0.normalized()
	var y0 := perp(b0, x0, Vector3.BACK)
	var x1 := a1.normalized()
	var y1 := perp(b1, x1, y0)
	var B0 := Basis(x0, y0, x0.cross(y0))
	var B1 := Basis(x1, y1, x1.cross(y1))
	return (B1 * B0.transposed()).get_rotation_quaternion()


static func smooth(a: float, b: float, x: float) -> float:
	if b == a:
		return 1.0 if x >= b else 0.0
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func pulse(t: float, a: float, b: float, c: float, d: float) -> float:
	# 0 before a, rises to 1 at b, holds, falls back to 0 between c and d.
	return smooth(a, b, t) * (1.0 - smooth(c, d, t))


func noise(x: float, channel: int = 0) -> float:
	# Smooth value noise in [-1, 1].
	var i := floori(x)
	var f := x - float(i)
	var a := _hash(i, channel)
	var b := _hash(i + 1, channel)
	var u := f * f * (3.0 - 2.0 * f)
	return lerpf(a, b, u) * 2.0 - 1.0


func _hash(i: int, channel: int) -> float:
	var h := hash([i, channel, seed_value])
	return float(h & 0xffff) / 65535.0


# =============================================================================
# Spec interpolation
# =============================================================================

static func lerp_spec(a: Variant, b: Variant, w: float) -> Variant:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		# Limbs driven in different modes (directions vs IK) cannot be mixed.
		if (da.has("ik") != db.has("ik")) or (da.has("du") != db.has("du")):
			return a if w < 0.5 else b
		var out := {}
		for k in da:
			out[k] = lerp_spec(da[k], db[k], w) if db.has(k) else da[k]
		for k in db:
			if not da.has(k):
				out[k] = db[k]
		return out
	if (a is float or a is int) and (b is float or b is int):
		return lerpf(float(a), float(b), w)
	if a is Vector3 and b is Vector3:
		return (a as Vector3).lerp(b, w)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).lerp(b, w)
	return a if w < 0.5 else b


## Key poses: keys = [[time, spec], ...] (sorted); smooth in-between.
static func keys(t: float, ks: Array) -> Dictionary:
	if ks.is_empty():
		return {}
	if t <= ks[0][0]:
		return ks[0][1]
	for i in range(ks.size() - 1):
		var t0: float = ks[i][0]
		var t1: float = ks[i + 1][0]
		if t < t1:
			return lerp_spec(ks[i][1], ks[i + 1][1], smooth(t0, t1, t))
	return ks[ks.size() - 1][1]


## Merges b over a (b wins); nested limb dicts are replaced, not merged.
static func over(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out


# =============================================================================
# Solver: spec -> joint rotations
# =============================================================================

func solve(s: Dictionary) -> Pose:
	var p := Pose.new()
	p.hips = s.get("hips", Vector3.ZERO)
	p.j["Hips"] = euler(s.get("hips_rot", Vector3.ZERO))
	var sp: Vector3 = s.get("spine", Vector3.ZERO)
	for i in 3:
		p.j[H.SPINE[i]] = euler(sp * SPINE_W[i])
	var hd: Vector3 = s.get("head", Vector3.ZERO)
	p.j["Neck"] = euler(hd * 0.4)
	p.j["Head"] = euler(hd * 0.6)
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var sx := 1.0 if side == "Left" else -1.0
		var sh: Vector2 = s.get("sh_" + k, Vector2.ZERO)
		p.j[side + "Shoulder"] = qz(sh.x * sx) * qy(-sh.y * sx)
		if s.has("leg_" + k):
			_leg_fk(p, side, s["leg_" + k])
		else:
			_leg_ik(p, side, s.get("foot_" + k, DEFAULT_FOOT))
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var a: Dictionary = s.get("arm_" + k, DEFAULT_ARM)
		if a.has("ik"):
			_arm_ik(p, side, a)
		else:
			_arm_dir(p, side, a)
		_fingers(p, side, float(s.get("curl_" + k, 0.3)), float(s.get("point_" + k, 0.0)), float(s.get("thumb_" + k, -1.0)))
	p.vel = s.get("vel", Vector3.ZERO)
	p.turn = float(s.get("turn", 0.0)) * DEG
	return p


## Global delta rotation D and position of a bone (root frame) under a pose.
func fk(p: Pose, bone: String) -> Array:
	var chain: Array = []
	var b := bone
	while b != "" and b != "Root":
		chain.push_front(b)
		b = H.parent_of(b)
	var D := Quaternion.IDENTITY
	var pos: Vector3 = rest.Hips + p.hips
	var prev := ""
	for c in chain:
		if prev == "":
			D = p.rot(c)
		else:
			pos = pos + D * (rest[c] - rest[prev])
			D = D * p.rot(c)
		prev = c
	return [pos, D]


func _arm_dir(p: Pose, side: String, a: Dictionary) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var m := Vector3(sx, 1, 1)
	var uc: Array = fk(p, "UpperChest")
	var Duc: Quaternion = uc[1]
	var du: Vector3 = Duc * ((a.get("du", DEFAULT_ARM.du) as Vector3) * m).normalized()
	var df: Vector3 = Duc * ((a.get("df", a.get("du", DEFAULT_ARM.df)) as Vector3) * m).normalized()
	var palm: Vector3 = Duc * ((a.get("palm", DEFAULT_ARM.palm) as Vector3) * m)
	var hand: Vector3 = df
	if a.has("hand"):
		hand = Duc * ((a.hand as Vector3) * m).normalized()
	_arm_apply(p, side, du, df, palm, hand, Duc * p.rot(side + "Shoulder"))


func _arm_ik(p: Pose, side: String, a: Dictionary) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var m := Vector3(sx, 1, 1)
	var shoulder: Array = fk(p, side + "Shoulder")
	var Dsh: Quaternion = shoulder[1]
	var s_pos: Vector3 = shoulder[0] + Dsh * (rest[side + "UpperArm"] - rest[side + "Shoulder"])
	var target: Vector3 = (a.ik as Vector3) * m
	var uc: Array = fk(p, "UpperChest")
	if a.get("chest", false):
		target = uc[0] + (uc[1] as Quaternion) * (target - rest.UpperChest)
	var pole: Vector3 = (a.get("pole", Vector3(0.35, -0.55, -0.6)) as Vector3) * m
	if a.get("chest", false):
		pole = (uc[1] as Quaternion) * pole
	var la := len_upper
	var lb := len_fore
	var dv := target - s_pos
	var dist := dv.length()
	var u := dv / maxf(dist, 0.0001)
	dist = clampf(dist, absf(la - lb) + 0.002, la + lb - 0.0005)
	var w := perp(pole, u, Vector3.DOWN)
	var x := (la * la - lb * lb + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var elbow := s_pos + u * x + w * h
	var wrist := s_pos + u * dist
	var du := (elbow - s_pos).normalized()
	var df := (wrist - elbow).normalized()
	var palm: Vector3 = (a.get("palm", Vector3(-1, 0, 0)) as Vector3) * m
	var hand: Vector3 = df
	if a.has("hand"):
		hand = ((a.hand as Vector3) * m).normalized()
	if a.get("chest", false):
		palm = (uc[1] as Quaternion) * palm
		if a.has("hand"):
			hand = (uc[1] as Quaternion) * hand
	_arm_apply(p, side, du, df, palm, hand, Dsh)


## Sets upper arm / forearm / hand from global directions (root frame).
func _arm_apply(p: Pose, side: String, du: Vector3, df: Vector3, palm: Vector3, hand: Vector3, Dsh: Quaternion) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var a0 := Vector3(sx, 0, 0)
	var b0 := Vector3.BACK
	# The elbow crease faces the side the forearm bends toward.
	var bu := perp(df, du, perp(Dsh * Vector3.BACK, du, Vector3.UP))
	var Xu := frame_rot(a0, b0, du, bu)
	var e := du.angle_to(df)
	var Xf := Xu
	if e > 0.001:
		var hinge := du.cross(bu).normalized()
		Xf = Quaternion(hinge, e) * Xu
	var c := perp(palm, hand, Xf * Vector3.DOWN)
	var cc := c if sx > 0.0 else -c
	var bh := cc.cross(hand)
	var Xh := frame_rot(a0, b0, hand, bh)
	p.j[side + "UpperArm"] = (Dsh.inverse() * Xu).normalized()
	p.j[side + "LowerArm"] = (Xu.inverse() * Xf).normalized()
	p.j[side + "Hand"] = (Xf.inverse() * Xh).normalized()


func _leg_ik(p: Pose, side: String, f: Dictionary) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var m := Vector3(sx, 1, 1)
	var ankle: Vector3 = (f.get("pos", DEFAULT_FOOT.pos) as Vector3) * m
	var yaw: float = float(f.get("yaw", 6.0)) * sx
	var pitch: float = float(f.get("pitch", 0.0))
	var Dh := p.rot("Hips")
	var hip: Vector3 = rest.Hips + p.hips + Dh * (rest[side + "UpperLeg"] - rest.Hips)
	var pole: Vector3 = f.get("knee", Vector3.ZERO)
	if pole == Vector3.ZERO:
		pole = qy(yaw) * Vector3.BACK
	else:
		pole = pole * m
	var a := len_thigh
	var b := len_shin
	var dv := ankle - hip
	var dist := dv.length()
	var u := dv / maxf(dist, 0.0001)
	dist = clampf(dist, absf(a - b) + 0.002, a + b - 0.0004)
	var w := perp(pole, u, Vector3.BACK)
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var hh := sqrt(maxf(a * a - x * x, 0.0))
	var knee := hip + u * x + w * hh
	var ank := hip + u * dist
	var n := w.cross(u).normalized()
	var ut := (knee - hip).normalized()
	var us := (ank - knee).normalized()
	var Dt := frame_rot(dir_thigh, Vector3.BACK, ut, ut.cross(n))
	var Ds := frame_rot(dir_shin, Vector3.BACK, us, us.cross(n))
	var qyaw := qy(yaw)
	var lateral := qyaw * Vector3.RIGHT
	var Df := Quaternion(lateral, pitch * DEG) * qyaw
	p.j[side + "UpperLeg"] = (Dh.inverse() * Dt).normalized()
	p.j[side + "LowerLeg"] = (Dt.inverse() * Ds).normalized()
	p.j[side + "Foot"] = (Ds.inverse() * Df).normalized()
	# Toes stay flat on the ground while the heel is up.
	var ground: float = float(f.get("ground", 1.0))
	if pitch > 0.0 and ground > 0.0:
		p.j[side + "Toes"] = Quaternion.IDENTITY.slerp((Df.inverse() * qyaw).normalized(), ground)
	elif f.has("toes"):
		p.j[side + "Toes"] = qx(float(f.toes))


func _leg_fk(p: Pose, side: String, l: Dictionary) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	p.j[side + "UpperLeg"] = qy(float(l.get("twist", 0.0)) * sx) * qx(-float(l.get("flex", 0.0))) * qz(float(l.get("abd", 0.0)) * sx)
	p.j[side + "LowerLeg"] = qx(float(l.get("knee", 0.0)))
	p.j[side + "Foot"] = qx(float(l.get("ankle", 0.0)))
	p.j[side + "Toes"] = qx(float(l.get("toes", 0.0)))


func _fingers(p: Pose, side: String, curl: float, point: float, thumb: float) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	for f in H.FINGERS:
		var c := curl
		if f == "Index":
			c = lerpf(curl, 0.02, point)
		elif point > 0.0:
			c = lerpf(curl, 1.0, point)
		for k in 3:
			p.j[side + f + PHAL[k]] = qz(-sx * FINGER_ANG[k] * c)
	var t := curl if thumb < 0.0 else thumb
	var tdir := (H.THUMB_DIR * Vector3(sx, 1, 1)).normalized()
	var axis := tdir.cross(Vector3.DOWN).normalized()
	p.j[side + "ThumbMetacarpal"] = Quaternion(axis, 18.0 * DEG * t)
	p.j[side + "ThumbProximal"] = Quaternion(axis, 28.0 * DEG * t)
	p.j[side + "ThumbDistal"] = Quaternion(axis, 35.0 * DEG * t)


## Crossfade of solved poses.
static func blend(a: Pose, b: Pose, w: float) -> Pose:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	var p := Pose.new()
	for k in a.j:
		p.j[k] = (a.j[k] as Quaternion).slerp(b.rot(k), w)
	for k in b.j:
		if not a.j.has(k):
			p.j[k] = Quaternion.IDENTITY.slerp(b.j[k], w)
	p.hips = a.hips.lerp(b.hips, w)
	p.vel = a.vel.lerp(b.vel, w)
	p.turn = lerpf(a.turn, b.turn, w)
	return p


## Ankle target for a foot whose ground point (under the rest ankle) is `ref`,
## pivoting on the ball joint (heel up, pitch > 0) or on the heel (toes up),
## for a foot turned `yaw` degrees outward (mirrored coordinates).
static func ankle_from(ref: Vector3, pitch: float, yaw: float = 0.0) -> Vector3:
	var qyaw := qy(yaw)
	var r := Quaternion(qyaw * Vector3.RIGHT, pitch * DEG) * qyaw
	if pitch >= 0.0:
		var ball := ref + qyaw * BALL_OFF
		return ball + r * (ANKLE_OFF - BALL_OFF)
	var heel := ref + qyaw * HEEL_OFF
	return heel + r * (ANKLE_OFF - HEEL_OFF)


func stand_foot(x: float = 0.1, z: float = -0.01, yaw: float = 6.0) -> Dictionary:
	return {"pos": Vector3(x, ANKLE_Y, z), "yaw": yaw}


# =============================================================================
# Base postures (the lower body held by upper-body clips)
# =============================================================================

func base(state: String) -> Dictionary:
	match state:
		"sit":
			return {
				"hips": Vector3(0, -0.5, -0.26), "spine": Vector3(6, 0, 0), "head": Vector3(-4, 0, 0),
				"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.16), "yaw": 8.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y, 0.16), "yaw": 8.0},
				"arm_L": {"ik": Vector3(0.15, 0.53, 0.06), "palm": Vector3(0, -1, 0), "hand": Vector3(0.05, -0.25, 1), "pole": Vector3(0.7, -0.4, -0.5)},
				"arm_R": {"ik": Vector3(0.15, 0.53, 0.06), "palm": Vector3(0, -1, 0), "hand": Vector3(0.05, -0.25, 1), "pole": Vector3(0.7, -0.4, -0.5)},
				"curl_L": 0.35, "curl_R": 0.35,
			}
		"ground":
			return {
				"hips": Vector3(0, -0.84, -0.06), "spine": Vector3(10, 0, 0), "head": Vector3(-6, 0, 0),
				"foot_L": {"pos": Vector3(-0.1, 0.075, 0.26), "yaw": -35.0, "knee": Vector3(1, 0.55, 0.35), "ground": 0.0},
				"foot_R": {"pos": Vector3(-0.13, 0.075, 0.18), "yaw": -35.0, "knee": Vector3(1, 0.55, 0.35), "ground": 0.0},
				"arm_L": {"ik": Vector3(0.24, 0.24, 0.2), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, -0.3, 1), "pole": Vector3(0.6, -0.3, -0.7)},
				"arm_R": {"ik": Vector3(0.24, 0.24, 0.2), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, -0.3, 1), "pole": Vector3(0.6, -0.3, -0.7)},
				"curl_L": 0.3, "curl_R": 0.3,
			}
		"lie":
			return {
				"hips": Vector3(0, 0.115 - rest.Hips.y, -0.35), "hips_rot": Vector3(-90, 0, 0), "spine": Vector3(2, 0, 0), "head": Vector3(6, 0, 0),
				"leg_L": {"flex": 3.0, "abd": 4.0, "ankle": 25.0, "knee": 3.0}, "leg_R": {"flex": 6.0, "abd": 5.0, "ankle": 25.0, "knee": 8.0},
				"arm_L": {"du": Vector3(0.28, -1, -0.12), "df": Vector3(0.3, -1, -0.02), "palm": Vector3(-0.3, 0, -1)},
				"arm_R": {"du": Vector3(0.3, -1, -0.12), "df": Vector3(0.32, -1, -0.02), "palm": Vector3(-0.3, 0, -1)},
				"curl_L": 0.4, "curl_R": 0.4,
			}
		"prone":
			return {
				"hips": Vector3(0, 0.12 - rest.Hips.y, 0.3), "hips_rot": Vector3(90, 0, 8), "spine": Vector3(0, 0, 0), "head": Vector3(-8, 25, 0),
				"leg_L": {"flex": -2.0, "abd": 6.0, "ankle": 55.0}, "leg_R": {"flex": 8.0, "abd": 3.0, "knee": 12.0, "ankle": 50.0},
				"arm_L": {"du": Vector3(0.6, 0.35, 0.3), "df": Vector3(0.2, 0.3, 1.0), "palm": Vector3(0, 0, -1)},
				"arm_R": {"du": Vector3(0.35, -1, 0.1), "df": Vector3(0.3, -1, 0.2), "palm": Vector3(-0.5, 0, 1)},
				"curl_L": 0.3, "curl_R": 0.5,
			}
		"crouch":
			return {
				"hips": Vector3(0, -0.44, -0.1), "spine": Vector3(26, 0, 0), "head": Vector3(-24, 0, 0),
				"foot_L": {"pos": Vector3(0.14, ANKLE_Y, 0.04), "yaw": 16.0, "knee": Vector3(0.45, 0, 1)},
				"foot_R": {"pos": Vector3(0.14, ANKLE_Y, 0.04), "yaw": 16.0, "knee": Vector3(0.45, 0, 1)},
				"arm_L": {"du": Vector3(0.25, -0.55, 0.8), "df": Vector3(0.05, -0.6, 0.8), "palm": Vector3(-0.6, -0.3, 0)},
				"arm_R": {"du": Vector3(0.25, -0.55, 0.8), "df": Vector3(0.05, -0.6, 0.8), "palm": Vector3(-0.6, -0.3, 0)},
				"curl_L": 0.45, "curl_R": 0.45,
			}
		"kneel":
			return {
				"hips": Vector3(0, -0.43, -0.05), "spine": Vector3(4, 0, 0),
				"foot_L": {"pos": Vector3(0.13, ANKLE_Y, 0.36), "yaw": 6.0},
				"foot_R": {"pos": Vector3(0.1, 0.1, -0.44), "pitch": 62.0, "yaw": 2.0, "ground": 1.0},
				"arm_L": {"ik": Vector3(0.13, 0.62, 0.36), "palm": Vector3(0, -1, 0), "hand": Vector3(0, -0.3, 1), "pole": Vector3(0.8, -0.3, -0.4)},
				"arm_R": {"du": Vector3(0.15, -1, 0.05), "df": Vector3(0.1, -1, 0.2), "palm": Vector3(-1, 0, 0.2)},
				"curl_L": 0.3, "curl_R": 0.35,
			}
	return {"hips": Vector3(0, -0.012, 0)}


func _stand() -> Dictionary:
	return base("stand")


## J-level mix of two specs (works across limb modes).
static func mixs(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0:
		return a
	if w >= 1.0:
		return b
	return {"_mix": [a, b, w]}


func solve_any(s: Dictionary) -> Pose:
	if s.has("_mix"):
		var m: Array = s["_mix"]
		var p := blend(solve_any(m[0]), solve_any(m[1]), float(m[2]))
		return p
	return solve(s)


## Root velocity/turn of a spec (looks inside mixes).
static func spec_motion(s: Dictionary) -> Array:
	if s.has("_mix"):
		var m: Array = s["_mix"]
		var a := spec_motion(m[0])
		var b := spec_motion(m[1])
		var w := float(m[2])
		return [(a[0] as Vector3).lerp(b[0], w), lerpf(a[1], b[1], w)]
	return [s.get("vel", Vector3.ZERO), float(s.get("turn", 0.0))]


# =============================================================================
# Locomotion
# =============================================================================

const GAITS := {
	"walk": {"v": 1.3, "freq": 2.0, "duty": 0.6, "lift": 0.085, "bob": 0.015, "sway": 0.022, "pyaw": 5.0, "proll": 3.0, "lean": 3.0,
		"arm": 17.0, "elbow": 12.0, "elbow_swing": 12.0, "crouch": 0.03, "width": 0.095, "heel": 16.0, "toe": 42.0, "toe_out": 6.0,
		"curl": 0.35, "run": false, "kick": 0.0, "head": 0.0},
	"run": {"v": 3.6, "freq": 2.8, "duty": 0.36, "lift": 0.2, "bob": 0.035, "sway": 0.012, "pyaw": 7.0, "proll": 2.5, "lean": 10.0,
		"arm": 30.0, "elbow": 82.0, "elbow_swing": 16.0, "crouch": 0.05, "width": 0.08, "heel": 4.0, "toe": 50.0, "toe_out": 4.0,
		"curl": 0.85, "run": true, "kick": 0.14, "head": -6.0},
	"sneak": {"v": 0.75, "freq": 1.35, "duty": 0.66, "lift": 0.1, "bob": 0.012, "sway": 0.03, "pyaw": 4.0, "proll": 2.0, "lean": 22.0,
		"arm": 8.0, "elbow": 75.0, "elbow_swing": 6.0, "crouch": 0.27, "width": 0.13, "heel": 4.0, "toe": 20.0, "toe_out": 12.0,
		"curl": 0.55, "run": false, "kick": 0.0, "head": -20.0, "arm_fwd": 28.0},
	"march": {"v": 1.2, "freq": 1.9, "duty": 0.6, "lift": 0.26, "bob": 0.012, "sway": 0.01, "pyaw": 2.0, "proll": 1.0, "lean": -3.0,
		"arm": 42.0, "elbow": 4.0, "elbow_swing": 2.0, "crouch": 0.03, "width": 0.1, "heel": 6.0, "toe": 20.0, "toe_out": 4.0,
		"curl": 0.85, "run": false, "kick": 0.0, "head": -4.0},
	"push": {"v": 0.55, "freq": 1.3, "duty": 0.7, "lift": 0.07, "bob": 0.01, "sway": 0.02, "pyaw": 3.0, "proll": 2.0, "lean": 26.0,
		"arm": 0.0, "elbow": 0.0, "elbow_swing": 0.0, "crouch": 0.1, "width": 0.12, "heel": 2.0, "toe": 34.0, "toe_out": 8.0,
		"curl": 0.1, "run": false, "kick": 0.0, "head": -22.0},
}


func gait(kind: String, q: Dictionary) -> Dictionary:
	var c: Dictionary = GAITS.get(kind, GAITS.walk).duplicate()
	var mood: Dictionary = q.get("mood", {})
	var speed: float = float(q.get("speed", 1.0)) * float(mood.get("speed", 1.0))
	c.v *= speed
	c.freq *= lerpf(1.0, speed, 0.45)
	c.bob *= float(mood.get("bob", 1.0))
	c.arm *= float(mood.get("arm", 1.0))
	c.lift *= float(mood.get("lift", 1.0))
	c.pyaw *= float(mood.get("pyaw", 1.0))
	c.lean += float(mood.get("lean", 0.0))
	c.crouch += float(mood.get("crouch", 0.0))
	c.elbow += float(mood.get("elbow", 0.0))
	if mood.has("curl"):
		c.curl = mood.curl
	c.head += float(mood.get("head", 0.0)) * 0.6
	match str(q.get("style", "")):
		"old":
			c.v *= 0.55
			c.freq *= 0.75
			c.lean += 26.0
			c.head += 4.0
			c.crouch += 0.06
			c.lift *= 0.45
			c.arm *= 0.35
			c.width += 0.03
			c.heel *= 0.3
			c.toe *= 0.4
		"elegant":
			c.width = -0.012
			c.sway *= 2.4
			c.proll *= 1.8
			c.pyaw *= 1.4
			c.arm *= 0.6
			c.lean -= 3.0
			c.head -= 6.0
		"zombie":
			c.v *= 0.45
			c.freq *= 0.7
			c.lift *= 0.45
			c.lean += 10.0
			c.heel = 0.0
			c.toe *= 0.3
			c.limp = true
		"limp":
			c.v *= 0.6
			c.freq *= 0.8
			c.limp = true
		"ninja":
			if kind == "run":
				c.lean += 22.0
				c.crouch += 0.1
				c.head -= 26.0
				c.ninja = true
		"cartoon":
			c.bob *= 2.2
			c.arm *= 1.5
			c.lift *= 1.4
			c.lean *= 1.3
		"robot":
			c.bob *= 0.2
			c.pyaw = 0.0
			c.proll = 0.0
			c.sway *= 0.3
			c.elbow = 88.0
			c.elbow_swing = 0.0
			c.arm = 22.0
			c.heel = 0.0
			c.toe *= 0.3
		"drunk":
			c.v *= 0.75
			c.width += 0.04
	var dir: Vector3 = q.get("dir_vec", Vector3.BACK)
	if dir.z < -0.5:
		# Walking backwards: shorter steps, the toes land first.
		c.v *= 0.6
		c.heel = 0.0
		c.lean -= 4.0
	elif absf(dir.x) > 0.5:
		c.v *= 0.55
		c.heel = 0.0
		c.toe *= 0.5
	c.dir = dir
	c.turn = float(q.get("turn", 0.0))
	c.turn_to = float(q.get("turn_to", 0.0))
	c.zigzag = bool(q.get("zigzag", false))
	_fit_stride(c)
	return c


## Lowers the hips just enough that the planted foot stays reachable from
## heel strike to toe-off (a straight leg only reaches so far), choosing how
## much of the stance happens behind the hips (like real gait) to keep the
## knees as straight as possible.
func _fit_stride(c: Dictionary) -> void:
	var fc: float = c.freq * 0.5
	var half: float = c.v / fc * c.duty * 0.5
	var reach: float = len_thigh + len_shin - 0.008
	var hip_rest: float = rest.LeftUpperLeg.y
	var best_need := INF
	var best_back := 0.0
	for i in 12:
		var back := half * 0.05 * float(i)
		var fa := ankle_from(Vector3(0, 0, half - back), -c.heel)
		var ba := ankle_from(Vector3(0, 0, -half - back), c.toe)
		var max_hip := minf(fa.y + sqrt(maxf(reach * reach - fa.z * fa.z, 0.0)), ba.y + sqrt(maxf(reach * reach - ba.z * ba.z, 0.0)))
		var need: float = hip_rest - max_hip
		if need < best_need - 0.0005:
			best_need = need
			best_back = back
	c.back = best_back
	c.crouch = maxf(c.crouch, best_need + c.bob + c.sway * 0.1)


func loco(t: float, c: Dictionary) -> Dictionary:
	var fc: float = c.freq * 0.5
	var phase: float = t * fc + float(c.get("phase0", 0.55))
	var cycle: float = c.v / fc
	var beta: float = c.duty
	var mid := beta * 0.5
	var ph := TAU * phase
	var run: bool = c.run
	var bob := cos(2.0 * TAU * (phase - mid))
	if run:
		bob = -bob
	var dir: Vector3 = c.dir
	var s := {}
	var limp: bool = c.get("limp", false)
	var sway_c := cos(TAU * (phase - mid))
	var hy: float = -c.crouch + c.bob * bob
	var extra_roll := 0.0
	if limp:
		# Weight drops onto the good (left) leg; the hurt leg is barely lifted.
		var right_stance := 1.0 if fposmod(phase + 0.5, 1.0) < beta else 0.0
		hy -= 0.03 * right_stance
		extra_roll = -6.0 * right_stance
	s.hips = Vector3(c.sway * sway_c, hy, 0)
	s.hips_rot = Vector3(c.lean * 0.3, -c.pyaw * cos(ph), c.proll * sway_c + extra_roll)
	s.spine = Vector3(c.lean * 0.7, c.pyaw * 1.4 * cos(ph), -c.proll * 0.7 * sway_c - extra_roll * 0.6)
	s.head = Vector3(-c.lean * 0.55 + c.head, -c.pyaw * 0.35 * cos(ph), 0)
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var off := 0.0 if side == "Left" else 0.5
		var psi := fposmod(phase + off, 1.0)
		var along := 0.0
		var lift := 0.0
		var pitch := 0.0
		var ground := 1.0
		var lift_k := 1.0
		if limp and side == "Right":
			lift_k = 0.35
		var back_off: float = c.get("back", 0.0)
		if psi < beta:
			var sn := psi / beta
			along = cycle * beta * (0.5 - sn) - back_off
			pitch = -c.heel * (1.0 - smooth(0.0, 0.16, sn)) + c.toe * smooth(0.58, 1.0, sn) * lift_k
		else:
			var w := (psi - beta) / (1.0 - beta)
			var e := 0.5 - 0.5 * cos(PI * w)
			along = cycle * beta * (-0.5 + e) - back_off
			lift = c.lift * lift_k * sin(PI * pow(w, 0.75))
			pitch = lerpf(c.toe * lift_k, -c.heel, smooth(0.1, 0.95, w))
			if run:
				along -= c.kick * sin(PI * w) * (1.0 - w)
			ground = 0.0
		var ref := Vector3(c.width, 0, -0.01) + Vector3(dir.x * (1.0 if side == "Left" else -1.0), 0, dir.z) * along + Vector3(0, lift, 0)
		s["foot_" + k] = {"pos": ankle_from(ref, pitch, c.toe_out), "pitch": pitch, "yaw": c.toe_out, "ground": ground}
		# Arms swing against the legs.
		var sw: float = c.arm * cos(TAU * (phase - (0.5 if side == "Left" else 0.0)))
		var fwd: float = c.get("arm_fwd", 0.0)
		var e_ang: float = c.elbow + c.elbow_swing * maxf(0.0, sw / maxf(c.arm, 1.0))
		var down := Vector3(0.12, -1, 0).normalized()
		s["arm_" + k] = {"du": qx(-(sw + fwd)) * down, "df": qx(-(sw + fwd + e_ang)) * Vector3(0.08, -1, 0).normalized(), "palm": Vector3(-1, 0, 0.2)}
		s["curl_" + k] = c.curl
		if c.get("ninja", false):
			s["arm_" + k] = {"du": Vector3(0.22, -0.45, -0.86), "df": Vector3(0.18, -0.35, -0.92), "palm": Vector3(0, 1, 0)}
			s["curl_" + k] = 0.05
	s.vel = dir * c.v
	var turn: float = c.turn
	if c.get("turn_to", 0.0) != 0.0:
		turn += _turn_rate(t, c.turn_to, 1.1)
	if c.get("zigzag", false):
		turn += 70.0 * sin(TAU * t / 2.6)
	s.turn = turn
	return s


# =============================================================================
# Clips (t = seconds since the clip started, q = segment parameters)
# =============================================================================

func _side(q: Dictionary) -> String:
	return str(q.get("side", "Right"))


func _arms_for(q: Dictionary) -> Array:
	var s := _side(q)
	if s == "Both":
		return ["Left", "Right"]
	return [s]


func c_idle(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = base(q.get("state", "stand")).duplicate()
	var breath := sin(TAU * t / 3.9)
	var sp: Vector3 = s.get("spine", Vector3.ZERO)
	s.spine = sp + Vector3(1.3 * breath, 3.0 * noise(t * 0.25, 5), 0)
	var hd: Vector3 = s.get("head", Vector3.ZERO)
	s.head = hd + Vector3(3.0 * noise(t * 0.3, 1), 10.0 * noise(t * 0.22, 2), 2.0 * noise(t * 0.2, 3))
	s.sh_L = Vector2(1.2 * breath, 0)
	s.sh_R = Vector2(1.2 * breath, 0)
	if str(q.get("state", "stand")) == "stand":
		var shift := sin(TAU * t / 5.5 + 0.8)
		s.hips = Vector3(0.022 * shift, -0.014 - 0.006 * absf(shift), 0)
		s.hips_rot = Vector3(0, 2.0 * noise(t * 0.2, 7), -2.0 * shift)
		s.spine = s.spine + Vector3(0, 0, 1.4 * shift)
		for side in SIDES:
			var sway := 2.5 * sin(TAU * t / 4.4 + (0.0 if side == "Left" else 1.3))
			s["arm_" + side.substr(0, 1)] = {"du": qx(-sway) * DEFAULT_ARM.du, "df": qx(-sway) * DEFAULT_ARM.df, "palm": DEFAULT_ARM.palm}
	return s


func c_walk(t: float, q: Dictionary) -> Dictionary:
	return loco(t, gait("walk", q))


func c_run(t: float, q: Dictionary) -> Dictionary:
	return loco(t, gait("run", q))


func c_sneak(t: float, q: Dictionary) -> Dictionary:
	var s := loco(t, gait("sneak", q))
	s.head = s.head + Vector3(0, 25.0 * noise(t * 0.4, 9), 0)
	return s


func c_march(t: float, q: Dictionary) -> Dictionary:
	return loco(t, gait("march", q))


func c_push(t: float, q: Dictionary) -> Dictionary:
	var s := loco(t, gait("push", q))
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(0.17, 1.33, 0.56), "palm": Vector3(0, 0.1, 1), "hand": Vector3(0.1, 1, 0.1), "pole": Vector3(0.7, -0.7, -0.2)}
		s["curl_" + k] = 0.1
	return s


func c_jump(t: float, q: Dictionary) -> Dictionary:
	var D: float = CLIPS.jump.dur
	var tt := fposmod(t, D)
	var forward: bool = q.get("dir", "") == "forward"
	var h_scale: float = float(q.get("mood", {}).get("amp", 1.0)) * (1.35 if q.get("style", "") == "cartoon" else 1.0)
	var T0 := 0.28
	var T1 := 0.4
	var v0 := 2.35 * sqrt(h_scale)
	var g := 9.81
	var T2 := T1 + 2.0 * v0 / g
	var T3 := T2 + 0.16
	var hy := 0.0
	var air := 0.0
	var pitch := 0.0
	if tt < T0:
		hy = -0.2 * smooth(0, T0, tt)
	elif tt < T1:
		hy = lerpf(-0.2, 0.03, smooth(T0, T1, tt))
		pitch = 34.0 * smooth(T0, T1, tt)
	elif tt < T2:
		var ft := tt - T1
		hy = 0.03 + v0 * ft - 0.5 * g * ft * ft
		air = sin(PI * ft / (T2 - T1))
		pitch = 30.0
	elif tt < T3:
		hy = lerpf(0.03, -0.17, smooth(T2, T3, tt))
		pitch = 30.0 * (1.0 - smooth(T2, T2 + 0.07, tt))
	else:
		hy = lerpf(-0.17, -0.012, smooth(T3, D, tt))
	var ground_y := maxf(0.0, hy - 0.03) + 0.1 * air
	var s := {"hips": Vector3(0, hy, 0)}
	for k in ["L", "R"]:
		var ref := Vector3(0.1 if tt < T1 or tt > T2 else 0.085, ground_y if tt >= T1 and tt < T2 else 0.0, -0.01)
		s["foot_" + k] = {"pos": ankle_from(ref, pitch), "pitch": pitch, "yaw": 6.0, "ground": 0.0 if air > 0.0 else 1.0}
	var arm := 0.0
	if tt < T0:
		arm = -50.0 * smooth(0, T0, tt)
	elif tt < T1 + 0.1:
		arm = lerpf(-50.0, 165.0, smooth(T0, T1 + 0.1, tt))
	elif tt < T2:
		arm = lerpf(165.0, 60.0, smooth(T1 + 0.1, T2, tt))
	else:
		arm = lerpf(60.0, 0.0, smooth(T2, D, tt))
	for k in ["L", "R"]:
		var du := qx(-arm) * Vector3(0.18, -1, 0).normalized()
		s["arm_" + k] = {"du": du, "df": qx(-arm - 18.0) * Vector3(0.12, -1, 0).normalized(), "palm": Vector3(-1, 0, 0.2)}
		s["curl_" + k] = 0.4
	var lean := 0.0
	if tt < T0:
		lean = 26.0 * smooth(0, T0, tt)
	elif tt < T1:
		lean = lerpf(26.0, -4.0, smooth(T0, T1, tt))
	elif tt < T2:
		lean = -4.0
	elif tt < T3:
		lean = lerpf(-4.0, 20.0, smooth(T2, T3, tt))
	else:
		lean = lerpf(20.0, 0.0, smooth(T3, D, tt))
	s.spine = Vector3(lean * 0.7, 0, 0)
	s.hips_rot = Vector3(lean * 0.3, 0, 0)
	s.head = Vector3(-lean * 0.6 - 8.0 * air, 0, 0)
	if forward and tt > T1 - 0.05 and tt < T2 + 0.05:
		s.vel = Vector3(0, 0, 1.7)
	return s


func c_jumping_jacks(t: float, q: Dictionary) -> Dictionary:
	var tt := fposmod(t, 1.0)
	var open := smooth(0.05, 0.3, tt) * (1.0 - smooth(0.55, 0.8, tt))
	var hop := maxf(0.0, sin(TAU * tt * 2.0 - 0.3)) * 0.05
	var s := {"hips": Vector3(0, -0.02 + hop - 0.03 * (1.0 - absf(sin(TAU * tt * 2.0))), 0)}
	for k in ["L", "R"]:
		var ref := Vector3(lerpf(0.09, 0.3, open), maxf(0.0, hop - 0.01), -0.01)
		s["foot_" + k] = {"pos": ankle_from(ref, 20.0 if hop > 0.01 else 0.0), "pitch": 20.0 if hop > 0.01 else 0.0, "yaw": lerpf(6.0, 20.0, open)}
		var up := lerpf(0.0, 1.0, open)
		var du := Vector3(lerpf(0.2, 0.55, up), lerpf(-1.0, 0.85, up), 0).normalized()
		s["arm_" + k] = {"du": du, "df": (du + Vector3(-0.15 * up, 0.1, 0)).normalized(), "palm": Vector3(0, -1, 0).lerp(Vector3(-1, 0, 0), 1.0 - up)}
		s["curl_" + k] = 0.1
	return s


func _turn_rate(t: float, total_deg: float, dur: float) -> float:
	var dt := 0.01
	return total_deg * (smooth(0, dur, t + dt) - smooth(0, dur, t - dt)) / (2.0 * dt)


func _stepping(t: float, rate: float, lift: float = 0.06) -> Dictionary:
	var s := {}
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var ph := fposmod(t * rate + (0.0 if side == "Left" else 0.5), 1.0)
		var l := lift * maxf(0.0, sin(TAU * ph)) if ph < 0.5 else 0.0
		s["foot_" + k] = {"pos": ankle_from(Vector3(0.1, l, -0.01), 10.0 * sign(l)), "pitch": 10.0 * sign(l), "yaw": 6.0, "ground": 0.0 if l > 0.0 else 1.0}
	return s


func c_spin(t: float, q: Dictionary) -> Dictionary:
	var n: int = maxi(1, int(q.get("count", 1)))
	var D := CLIPS.spin.dur * n
	var sign_dir := -1.0 if q.get("dir", "") == "right" else 1.0
	var s := _stepping(t, 2.2, 0.05 * pulse(t, 0.0, 0.2, D - 0.2, D))
	s.hips = Vector3(0, -0.03, 0)
	var out := pulse(t, 0.0, 0.3, D - 0.35, D)
	for k in ["L", "R"]:
		s["arm_" + k] = lerp_spec(DEFAULT_ARM, {"du": Vector3(0.75, -0.6, 0.1), "df": Vector3(0.75, -0.45, 0.35), "palm": Vector3(0, -1, 0)}, out)
		s["curl_" + k] = 0.1
	s.head = Vector3(-6, 12.0 * sign_dir * out, 0)
	s.turn = _turn_rate(t, 360.0 * n * sign_dir, D)
	return s


func c_turn(t: float, q: Dictionary) -> Dictionary:
	var ang: float = float(q.get("angle", 90.0))
	var d: String = q.get("dir", "left")
	if d == "right":
		ang = -absf(ang)
	elif d == "back" or d == "around":
		ang = 180.0
	var D := 0.8 + absf(ang) / 180.0 * 0.7
	var s := _stepping(t, 2.4, 0.05 * pulse(t, 0.0, 0.1, D - 0.2, D))
	s.hips = Vector3(0, -0.02, 0)
	var lead := pulse(t, 0.0, 0.3, D * 0.6, D)
	s.head = Vector3(0, 25.0 * signf(ang) * lead, 0)
	s.spine = Vector3(0, 10.0 * signf(ang) * lead, 0)
	s.turn = _turn_rate(t, ang, D)
	return s


func c_wave(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.wave.dur)
	var s: Dictionary = base(q.get("state", "stand")).duplicate()
	var up := pulse(t, 0.0, 0.4, D - 0.45, D)
	var amp: float = float(q.get("mood", {}).get("amp", 1.0))
	var osc := sin(TAU * 2.2 * maxf(0.0, t - 0.35)) * 0.42 * amp
	for side in _arms_for(q):
		var k: String = side.substr(0, 1)
		var wave := {"du": Vector3(0.85, 0.4, 0.3), "df": Vector3(0.22 + osc, 1.0, 0.12), "palm": Vector3(0, 0.05, 1)}
		var from: Dictionary = s.get("arm_" + k, DEFAULT_ARM)
		s["arm_" + k] = lerp_spec(from, wave, up) if not from.has("ik") else (wave if up > 0.5 else from)
		s["curl_" + k] = lerpf(0.3, 0.05, up)
	var tilt := -4.0 if _side(q) == "Left" else 4.0
	var hd: Vector3 = s.get("head", Vector3.ZERO)
	s.head = hd + Vector3(-4.0 * up, 6.0 * up * (1.0 if _side(q) == "Left" else -1.0), tilt * up)
	return s


func c_clap(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.clap.dur)
	var st: Dictionary = base(q.get("state", "stand"))
	var up := pulse(t, 0.0, 0.35, D - 0.35, D)
	var rate := 2.4 * float(q.get("speed", 1.0))
	var gap := 0.028 + 0.1 * (0.5 + 0.5 * cos(TAU * rate * maxf(0.0, t - 0.3)))
	var hand_y := 1.2 if q.get("state", "stand") == "stand" else 1.2 + float((st.get("hips", Vector3.ZERO) as Vector3).y)
	var s: Dictionary = st.duplicate()
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(gap, hand_y, 0.3), "palm": Vector3(-1, 0, 0), "hand": Vector3(0, 0.5, 1), "pole": Vector3(0.6, -0.8, -0.2)}
		s["curl_" + k] = 0.05
	var hd: Vector3 = s.get("head", Vector3.ZERO)
	s.head = hd + Vector3(-5, 0, 0)
	return mixs(st, s, up)


func c_point(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.point.dur)
	var s: Dictionary = base(q.get("state", "stand")).duplicate()
	var up := pulse(t, 0.0, 0.35, D - 0.4, D)
	var side := _side(q)
	if side == "Both":
		side = "Right"
	var k := side.substr(0, 1)
	var target := Vector3(0.05, 0.12, 1.0)
	var look := 0.0
	match str(q.get("dir", "")):
		"left":
			target = Vector3(0.9, 0.15, 0.35) if side == "Left" else Vector3(-0.8, 0.15, 0.6)
			look = 40.0
		"right":
			target = Vector3(-0.8, 0.15, 0.6) if side == "Left" else Vector3(0.9, 0.15, 0.35)
			look = -40.0
		"up":
			target = Vector3(0.2, 1.0, 0.3)
		"down":
			target = Vector3(0.1, -0.55, 0.8)
		"back":
			target = Vector3(0.7, 0.2, -0.7)
			look = 60.0 if side == "Left" else -60.0
	var from: Dictionary = s.get("arm_" + k, DEFAULT_ARM)
	var pt := {"du": target, "df": target, "palm": Vector3(-0.3, -1, 0)}
	s["arm_" + k] = lerp_spec(from, pt, up) if not from.has("ik") else (pt if up > 0.5 else from)
	s["point_" + k] = up
	s["curl_" + k] = 0.3
	var hd: Vector3 = s.get("head", Vector3.ZERO)
	s.head = hd + Vector3(-target.y * 20.0 * up, look * up, 0)
	var sp: Vector3 = s.get("spine", Vector3.ZERO)
	s.spine = sp + Vector3(0, look * 0.3 * up, 0)
	return s


func c_cheer(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.cheer.dur)
	var up := pulse(t, 0.0, 0.3, D - 0.4, D)
	var hop := maxf(0.0, sin(TAU * 1.6 * maxf(0.0, t - 0.3))) * up
	var s := {"hips": Vector3(0, -0.02 + 0.09 * hop - 0.04 * up * (1.0 - hop), 0)}
	for k in ["L", "R"]:
		var ref := Vector3(0.11, maxf(0.0, 0.09 * hop - 0.05), -0.01)
		var p := 25.0 * clampf(hop * 2.0, 0.0, 1.0)
		s["foot_" + k] = {"pos": ankle_from(ref, p), "pitch": p, "yaw": 8.0, "ground": 0.0 if ref.y > 0.0 else 1.0}
		var pump := 10.0 * sin(TAU * 3.2 * t)
		var v := qz(pump if k == "L" else -pump) * Vector3(0.45, 0.9, 0.1)
		s["arm_" + k] = lerp_spec(DEFAULT_ARM, {"du": v, "df": v + Vector3(-0.05, 0.1, 0), "palm": Vector3(-1, 0, 0.3)}, up)
		s["curl_" + k] = lerpf(0.3, 1.0, up)
	s.head = Vector3(-14.0 * up, 0, 0)
	s.spine = Vector3(-6.0 * up, 0, 0)
	return s


func c_dance(t: float, q: Dictionary) -> Dictionary:
	var variant: int = int(q.get("variant", seed_value)) % 3
	var bpm := 116.0 * float(q.get("speed", 1.0))
	var beat := t * bpm / 60.0
	var w := TAU * beat * 0.5
	var bounce := absf(sin(PI * beat))
	var s := {}
	var sway := sin(w)
	s.hips = Vector3(0.07 * sway, -0.06 - 0.05 * (1.0 - bounce), 0)
	s.hips_rot = Vector3(0, 14.0 * sin(w * 0.5), -8.0 * sway)
	s.spine = Vector3(5.0 + 5.0 * bounce, -16.0 * sin(w * 0.5), 7.0 * sway)
	s.head = Vector3(10.0 * sin(TAU * beat) - 4.0, 14.0 * sin(w * 0.5), -6.0 * sway)
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var sgn := 1.0 if side == "Left" else -1.0
		var step := maxf(0.0, sin(w) * sgn)
		s["foot_" + k] = {"pos": ankle_from(Vector3(0.12 + 0.1 * step, 0.03 * maxf(0.0, sin(TAU * beat)) * step, -0.01), 0.0), "yaw": 10.0}
	match variant:
		0:
			# Groove: elbows bent, forearms pumping in turns.
			for side in SIDES:
				var k: String = side.substr(0, 1)
				var ph := sin(TAU * beat * 0.5 + (0.0 if side == "Left" else PI))
				s["arm_" + k] = {"du": Vector3(0.5, -0.65 + 0.3 * ph, 0.3), "df": Vector3(0.05 + 0.4 * ph, 0.5 + 0.6 * ph, 1.0), "palm": Vector3(-0.5, -0.5, 0.3)}
				s["curl_" + k] = 0.75
		1:
			# Disco: right hand points up high and down low; left hand on the hip.
			var hi := sin(w) > 0.0
			s.arm_R = {"du": Vector3(0.45, 0.85, 0.25), "df": Vector3(0.45, 0.85, 0.25), "palm": Vector3(-0.4, 0, 1)} if hi else {"du": Vector3(-0.35, -0.7, 0.45), "df": Vector3(-0.5, -0.6, 0.4), "palm": Vector3(0, -1, 0)}
			s.point_R = 1.0
			s.arm_L = {"ik": Vector3(0.2, 1.0, 0.0), "palm": Vector3(-1, 0, 0), "hand": Vector3(0, -0.5, -0.8), "pole": Vector3(1, 0, -0.3)}
			s.curl_L = 0.5
		_:
			# Arms waving overhead.
			for side in SIDES:
				var k: String = side.substr(0, 1)
				var ph := sin(w + (0.0 if side == "Left" else 0.6))
				var v := Vector3(0.45 + 0.3 * ph, 0.85, 0.15)
				s["arm_" + k] = {"du": v, "df": v + Vector3(-0.3 * ph, 0.2, 0), "palm": Vector3(0, 0.1, 1)}
				s["curl_" + k] = 0.1
	return s


func _breathe(s: Dictionary, t: float, amount: float = 1.0) -> Dictionary:
	var out := s.duplicate()
	var b := sin(TAU * t / 3.8) * amount
	out.spine = (s.get("spine", Vector3.ZERO) as Vector3) + Vector3(1.2 * b, 0, 0)
	out.head = (s.get("head", Vector3.ZERO) as Vector3) + Vector3(2.0 * noise(t * 0.3, 11) * amount, 6.0 * noise(t * 0.2, 12) * amount, 0)
	return out


func c_sit(t: float, q: Dictionary) -> Dictionary:
	if q.get("state", "stand") == "sit":
		return _breathe(base("sit"), t)
	var mid := {"hips": Vector3(0, -0.2, -0.12), "spine": Vector3(26, 0, 0), "head": Vector3(-14, 0, 0),
		"foot_L": {"pos": Vector3(0.11, ANKLE_Y + 0.02, 0.1), "yaw": 7.0}, "foot_R": {"pos": Vector3(0.11, ANKLE_Y + 0.02, 0.1), "yaw": 7.0},
		"arm_L": {"du": Vector3(0.25, -0.7, 0.6), "df": Vector3(0.1, -0.5, 0.85), "palm": Vector3(-1, -0.3, 0)},
		"arm_R": {"du": Vector3(0.25, -0.7, 0.6), "df": Vector3(0.1, -0.5, 0.85), "palm": Vector3(-1, -0.3, 0)}}
	var low := over(base("sit"), {"spine": Vector3(18, 0, 0), "head": Vector3(-10, 0, 0),
		"arm_L": mid.arm_L, "arm_R": mid.arm_R})
	if t < 1.2:
		return keys(t, [[0.0, _stand()], [0.55, mid], [1.2, low]])
	return mixs(low, _breathe(base("sit"), t - 1.2), smooth(1.2, 1.7, t))


func c_sit_ground(t: float, q: Dictionary) -> Dictionary:
	if q.get("state", "stand") == "ground":
		return _breathe(base("ground"), t)
	var crouch: Dictionary = base("crouch")
	var down := {"hips": Vector3(0, -0.78, -0.16), "spine": Vector3(16, 0, 0), "head": Vector3(-10, 0, 0),
		"foot_L": {"pos": Vector3(0.14, ANKLE_Y, 0.3), "yaw": 10.0}, "foot_R": {"pos": Vector3(0.14, ANKLE_Y, 0.3), "yaw": 10.0},
		"arm_L": {"ik": Vector3(0.22, 0.1, -0.3), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, 0, -1), "pole": Vector3(0.3, 0, -1)},
		"arm_R": {"ik": Vector3(0.22, 0.1, -0.3), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, 0, -1), "pole": Vector3(0.3, 0, -1)}}
	if t < 0.7:
		return keys(t, [[0.0, _stand()], [0.7, crouch]])
	if t < 1.4:
		return mixs(crouch, down, smooth(0.7, 1.4, t))
	return mixs(down, _breathe(base("ground"), t - 1.4), smooth(1.4, 2.2, t))


func c_meditate(t: float, q: Dictionary) -> Dictionary:
	var hold := over(base("ground"), {"spine": Vector3(2, 0, 0), "head": Vector3(10, 0, 0),
		"arm_L": {"ik": Vector3(0.27, 0.25, 0.22), "palm": Vector3(0, 1, 0), "hand": Vector3(0.3, -0.2, 1), "pole": Vector3(0.6, -0.4, -0.6)},
		"arm_R": {"ik": Vector3(0.27, 0.25, 0.22), "palm": Vector3(0, 1, 0), "hand": Vector3(0.3, -0.2, 1), "pole": Vector3(0.6, -0.4, -0.6)},
		"curl_L": 0.25, "curl_R": 0.25, "thumb_L": 0.6, "thumb_R": 0.6})
	var b := sin(TAU * t / 5.0)
	hold.spine = Vector3(2.0 + 1.5 * b, 0, 0)
	hold.sh_L = Vector2(2.0 * b, 0)
	hold.sh_R = Vector2(2.0 * b, 0)
	if q.get("state", "stand") == "ground":
		return hold
	if t < 2.2:
		return c_sit_ground(t, q)
	return mixs(c_sit_ground(t, q), hold, smooth(2.2, 2.8, t))


func stand_up_duration(state: String) -> float:
	return {"sit": 1.6, "ground": 2.2, "lie": 2.6, "prone": 2.6, "crouch": 0.8, "kneel": 1.1}.get(state, 0.4)


func c_stand_up(t: float, q: Dictionary) -> Dictionary:
	var state: String = q.get("state", "stand")
	var stand := _stand()
	match state:
		"sit":
			var lean := over(base("sit"), {"hips": Vector3(0, -0.44, -0.12), "spine": Vector3(32, 0, 0), "head": Vector3(-20, 0, 0),
				"arm_L": {"du": Vector3(0.2, -0.75, 0.55), "df": Vector3(0.1, -0.6, 0.8), "palm": Vector3(-1, -0.3, 0)},
				"arm_R": {"du": Vector3(0.2, -0.75, 0.55), "df": Vector3(0.1, -0.6, 0.8), "palm": Vector3(-1, -0.3, 0)}})
			if t < 0.5:
				return mixs(base("sit"), lean, smooth(0, 0.5, t))
			var up := over(lean, {"hips": Vector3(0, -0.12, 0.0), "spine": Vector3(10, 0, 0), "head": Vector3(-5, 0, 0),
				"foot_L": {"pos": Vector3(0.11, ANKLE_Y, 0.08), "yaw": 7.0}, "foot_R": {"pos": Vector3(0.11, ANKLE_Y, 0.08), "yaw": 7.0}})
			if t < 1.1:
				return keys(t, [[0.5, lean], [1.1, up]])
			return mixs(up, stand, smooth(1.1, 1.6, t))
		"ground", "lie", "prone":
			var crouch: Dictionary = base("crouch")
			var start: Dictionary = base(state)
			var knee := over(base("kneel"), {"spine": Vector3(22, 0, 0), "head": Vector3(-15, 0, 0)})
			var T := stand_up_duration(state)
			if state == "ground":
				if t < 0.9:
					return mixs(start, knee, smooth(0, 0.9, t))
				if t < 1.6:
					return mixs(knee, crouch, smooth(0.9, 1.6, t))
				return mixs(crouch, stand, smooth(1.6, T, t))
			var sitting := over(base("ground"), {"spine": Vector3(26, 0, 0), "head": Vector3(-12, 0, 0),
				"arm_L": {"ik": Vector3(0.25, 0.1, -0.2), "palm": Vector3(0, -1, 0), "pole": Vector3(0.3, 0, -1)},
				"arm_R": {"ik": Vector3(0.25, 0.1, -0.2), "palm": Vector3(0, -1, 0), "pole": Vector3(0.3, 0, -1)}})
			if state == "prone":
				sitting = over(base("kneel"), {"hips": Vector3(0, -0.58, 0.05), "hips_rot": Vector3(35, 0, 0), "spine": Vector3(20, 0, 0),
					"foot_L": {"pos": Vector3(0.12, 0.1, -0.35), "pitch": 60.0, "ground": 1.0},
					"arm_L": {"ik": Vector3(0.2, 0.08, 0.45), "palm": Vector3(0, -1, 0), "pole": Vector3(0.5, 0, -1)},
					"arm_R": {"ik": Vector3(0.2, 0.08, 0.45), "palm": Vector3(0, -1, 0), "pole": Vector3(0.5, 0, -1)}})
			if t < 1.0:
				return mixs(start, sitting, smooth(0, 1.0, t))
			if t < 1.8:
				return mixs(sitting, crouch, smooth(1.0, 1.8, t))
			return mixs(crouch, stand, smooth(1.8, T, t))
		"crouch":
			return mixs(base("crouch"), stand, smooth(0, 0.8, t))
		"kneel":
			return mixs(base("kneel"), stand, smooth(0, 1.1, t))
	return stand


func c_crouch(t: float, q: Dictionary) -> Dictionary:
	var hold := _breathe(base("crouch"), t, 0.6)
	hold.head = (hold.head as Vector3) + Vector3(0, 20.0 * noise(t * 0.35, 21), 0)
	if q.get("state", "stand") == "crouch":
		return hold
	return mixs(_stand(), hold, smooth(0, 0.6, t))


func c_squats(t: float, q: Dictionary) -> Dictionary:
	var P: float = CLIPS.squats.dur
	var down := sin(PI * fposmod(t, P) / P)
	down = down * down
	var s := {"hips": Vector3(0, -0.012 - 0.45 * down, -0.13 * down), "spine": Vector3(32.0 * down, 0, 0), "head": Vector3(-26.0 * down, 0, 0)}
	for k in ["L", "R"]:
		s["foot_" + k] = {"pos": Vector3(0.15, ANKLE_Y, -0.01), "yaw": 14.0, "knee": Vector3(0.35, 0, 1)}
		var v := Vector3(0.2, -1, 0.05).lerp(Vector3(0.12, 0.05, 1.0), down)
		s["arm_" + k] = {"du": v, "df": v, "palm": Vector3(0, -1, 0)}
		s["curl_" + k] = 0.2
	return s


func c_kneel(t: float, q: Dictionary) -> Dictionary:
	var hold := _breathe(base("kneel"), t, 0.6)
	if q.get("state", "stand") == "kneel":
		return hold
	var step := over(_stand(), {"hips": Vector3(0, -0.1, 0.02),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.3), "yaw": 6.0}, "foot_R": {"pos": Vector3(0.1, ANKLE_Y + 0.03, -0.3), "pitch": 30.0, "ground": 1.0}})
	if t < 0.6:
		return keys(t, [[0.0, _stand()], [0.6, step]])
	return mixs(step, hold, smooth(0.6, 1.4, t))


func c_lie(t: float, q: Dictionary) -> Dictionary:
	var hold := _breathe(base("lie"), t, 0.4)
	hold.head = Vector3(6, 0, 0)
	if q.get("state", "stand") == "lie":
		return hold
	var crouch: Dictionary = base("crouch")
	var sitting := over(base("ground"), {"hips": Vector3(0, -0.84, -0.12), "spine": Vector3(-6, 0, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.45), "yaw": 6.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y, 0.4), "yaw": 6.0},
		"arm_L": {"ik": Vector3(0.24, 0.1, -0.32), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, 0, -1), "pole": Vector3(0.3, 0, -1)},
		"arm_R": {"ik": Vector3(0.24, 0.1, -0.32), "palm": Vector3(0, -1, 0), "hand": Vector3(0.2, 0, -1), "pole": Vector3(0.3, 0, -1)}})
	if t < 0.7:
		return mixs(_stand(), crouch, smooth(0, 0.7, t))
	if t < 1.5:
		return mixs(crouch, sitting, smooth(0.7, 1.5, t))
	return mixs(sitting, hold, smooth(1.5, 2.5, t))


func c_fall(t: float, q: Dictionary) -> Dictionary:
	if q.get("dir", "") == "forward":
		return _fall_forward(t)
	var stumble := {"hips": Vector3(0, -0.06, -0.06), "spine": Vector3(-14, 0, 0), "head": Vector3(-18, 0, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.08), "yaw": 6.0}, "foot_R": {"pos": Vector3(0.1, ANKLE_Y + 0.06, -0.2), "pitch": 20.0, "ground": 0.0},
		"arm_L": {"du": Vector3(0.7, 0.55, 0.3), "df": Vector3(0.5, 0.8, 0.3), "palm": Vector3(0, 0, 1)},
		"arm_R": {"du": Vector3(0.75, 0.4, 0.4), "df": Vector3(0.45, 0.8, 0.4), "palm": Vector3(0, 0, 1)}, "curl_L": 0.1, "curl_R": 0.1}
	var hit := {"hips": Vector3(0, 0.12 - rest.Hips.y, -0.42), "hips_rot": Vector3(-25, 0, 0), "spine": Vector3(8, 0, 0), "head": Vector3(10, 0, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.3), "yaw": 6.0, "ground": 0.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y + 0.05, 0.25), "yaw": 6.0, "ground": 0.0},
		"arm_L": {"du": Vector3(0.45, -0.4, -0.8), "df": Vector3(0.2, -0.7, -0.6), "palm": Vector3(0, -1, 0)},
		"arm_R": {"du": Vector3(0.45, -0.4, -0.8), "df": Vector3(0.2, -0.7, -0.6), "palm": Vector3(0, -1, 0)}}
	var bounce := over(base("lie"), {"hips_rot": Vector3(-97, 0, 0), "head": Vector3(-6, 0, 0)})
	if t < 0.25:
		return mixs(_stand(), stumble, smooth(0, 0.25, t))
	if t < 0.75:
		return mixs(stumble, hit, smooth(0.25, 0.75, t))
	if t < 1.1:
		return mixs(hit, bounce, smooth(0.75, 1.1, t))
	return mixs(bounce, _breathe(base("lie"), t, 0.8), smooth(1.1, 1.5, t))


func _fall_forward(t: float) -> Dictionary:
	var trip := {"hips": Vector3(0, -0.05, 0.05), "spine": Vector3(25, 0, 0), "head": Vector3(-20, 0, 0),
		"arm_L": {"du": Vector3(0.3, -0.2, 1), "df": Vector3(0.2, -0.3, 1), "palm": Vector3(0, -0.3, 1)},
		"arm_R": {"du": Vector3(0.3, -0.2, 1), "df": Vector3(0.2, -0.3, 1), "palm": Vector3(0, -0.3, 1)}, "curl_L": 0.1, "curl_R": 0.1}
	var knees := {"hips": Vector3(0, -0.46, 0.05), "hips_rot": Vector3(30, 0, 0), "spine": Vector3(15, 0, 0), "head": Vector3(-25, 0, 0),
		"foot_L": {"pos": Vector3(0.12, 0.1, -0.4), "pitch": 60.0, "ground": 1.0}, "foot_R": {"pos": Vector3(0.12, 0.1, -0.4), "pitch": 60.0, "ground": 1.0},
		"arm_L": {"ik": Vector3(0.2, 0.08, 0.55), "palm": Vector3(0, -1, 0), "pole": Vector3(0.5, 0, -1)},
		"arm_R": {"ik": Vector3(0.2, 0.08, 0.55), "palm": Vector3(0, -1, 0), "pole": Vector3(0.5, 0, -1)}}
	if t < 0.3:
		return mixs(_stand(), trip, smooth(0, 0.3, t))
	if t < 0.8:
		return mixs(trip, knees, smooth(0.3, 0.8, t))
	return mixs(knees, _breathe(base("prone"), t, 0.5), smooth(0.8, 1.4, t))


func c_die(t: float, q: Dictionary) -> Dictionary:
	var hit := {"hips": Vector3(0, -0.03, -0.04), "spine": Vector3(-12, 0, 4), "head": Vector3(-20, 0, 8),
		"arm_L": {"du": Vector3(0.7, -0.3, 0.2), "df": Vector3(0.6, -0.1, 0.6), "palm": Vector3(0, -1, 0)},
		"arm_R": {"ik": Vector3(0.02, 1.2, 0.16), "palm": Vector3(0, 0, -1), "pole": Vector3(0.6, -0.8, 0)}, "curl_L": 0.2, "curl_R": 0.4}
	var knees := {"hips": Vector3(0, -0.5, 0.0), "hips_rot": Vector3(5, 0, 0), "spine": Vector3(20, 0, 0), "head": Vector3(25, 0, 0),
		"foot_L": {"pos": Vector3(0.12, 0.1, -0.42), "pitch": 60.0, "ground": 1.0}, "foot_R": {"pos": Vector3(0.12, 0.1, -0.42), "pitch": 60.0, "ground": 1.0},
		"arm_L": {"du": Vector3(0.2, -1, 0.1), "df": Vector3(0.1, -1, 0.1), "palm": Vector3(-1, 0, 0)},
		"arm_R": {"du": Vector3(0.2, -1, 0.1), "df": Vector3(0.1, -1, 0.1), "palm": Vector3(-1, 0, 0)}, "curl_L": 0.5, "curl_R": 0.5}
	if t < 0.35:
		return mixs(_stand(), hit, smooth(0, 0.35, t))
	if t < 1.2:
		return mixs(hit, knees, smooth(0.35, 1.2, t))
	return mixs(knees, base("prone"), smooth(1.2, 1.9, t))


func c_hit(t: float, q: Dictionary) -> Dictionary:
	var recoil := {"hips": Vector3(0, -0.03, -0.07), "hips_rot": Vector3(-6, 0, 0), "spine": Vector3(-16, 8, 0), "head": Vector3(-22, 10, 6),
		"foot_R": {"pos": Vector3(0.1, ANKLE_Y, -0.15), "yaw": 6.0},
		"arm_L": {"du": Vector3(0.55, -0.6, 0.4), "df": Vector3(0.4, -0.2, 0.9), "palm": Vector3(0, -1, 0)},
		"arm_R": {"du": Vector3(0.55, -0.6, 0.4), "df": Vector3(0.4, -0.2, 0.9), "palm": Vector3(0, -1, 0)}}
	return keys(t, [[0.0, _stand()], [0.12, recoil], [0.5, over(recoil, {"spine": Vector3(6, 0, 0), "head": Vector3(4, 0, 0)})], [1.2, _stand()]])


func c_bow(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.bow.dur)
	var bow := {"hips": Vector3(0, -0.015, -0.07), "hips_rot": Vector3(34, 0, 0), "spine": Vector3(16, 0, 0), "head": Vector3(12, 0, 0),
		"arm_L": {"du": Vector3(0.05, -1, 0.35), "df": Vector3(-0.05, -1, 0.45), "palm": Vector3(-1, 0, -0.2)},
		"arm_R": {"ik": Vector3(-0.02, 1.05, 0.2), "chest": true, "palm": Vector3(0, 0, -1), "hand": Vector3(-1, 0, 0), "pole": Vector3(0.8, -0.6, 0)},
		"curl_R": 0.15}
	return mixs(_stand(), bow, pulse(t, 0.0, 0.7, D - 0.7, D))


func c_salute(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.salute.dur)
	var st: Dictionary = base(q.get("state", "stand"))
	var s: Dictionary = st.duplicate()
	s.arm_R = {"ik": Vector3(0.085, 1.715, 0.06), "chest": true, "palm": Vector3(0.1, -0.45, 1.0), "hand": Vector3(-0.8, 0.55, 0.15), "pole": Vector3(1, 0.1, 0.1)}
	s.curl_R = 0.0
	s.thumb_R = 0.4
	if q.get("state", "stand") == "stand":
		s.foot_L = {"pos": Vector3(0.08, ANKLE_Y, -0.01), "yaw": 12.0}
		s.foot_R = {"pos": Vector3(0.08, ANKLE_Y, -0.01), "yaw": 12.0}
		s.spine = Vector3(-4, 0, 0)
		s.head = Vector3(-4, 0, 0)
		s.arm_L = {"du": Vector3(0.06, -1, 0.0), "df": Vector3(0.06, -1, 0.05), "palm": Vector3(-1, 0, 0)}
	return mixs(st, s, pulse(t, 0.0, 0.45, D - 0.4, D))


func c_nod(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = c_idle(t, q)
	var D: float = q.get("clip_dur", CLIPS.nod.dur)
	var n: int = maxi(2, int(q.get("count", 3)))
	var e := pulse(t, 0.0, 0.1, D - 0.15, D)
	s.head = (s.head as Vector3) + Vector3(13.0 * e * sin(TAU * n * t / D), 0, 0)
	return s


func c_shake_head(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = c_idle(t, q)
	var D: float = q.get("clip_dur", CLIPS.shake_head.dur)
	var n: int = maxi(2, int(q.get("count", 3)))
	var e := pulse(t, 0.0, 0.1, D - 0.15, D)
	s.head = (s.head as Vector3) + Vector3(3.0 * e, 24.0 * e * sin(TAU * n * t / D), 0)
	return s


func c_look_around(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = c_idle(t, q)
	var yaw: float = keys(t, [[0.0, {"y": 0.0}], [0.7, {"y": 58.0}], [1.4, {"y": 58.0}], [2.4, {"y": -58.0}], [3.0, {"y": -58.0}], [3.6, {"y": 0.0}]]).y
	s.head = Vector3((s.head as Vector3).x - 4.0, yaw * 0.75, 0)
	s.spine = (s.spine as Vector3) + Vector3(0, yaw * 0.3, 0)
	return s


func c_shrug(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.shrug.dur)
	var st: Dictionary = base(q.get("state", "stand"))
	var s: Dictionary = st.duplicate()
	s.sh_L = Vector2(16, 3)
	s.sh_R = Vector2(16, 3)
	for k in ["L", "R"]:
		s["arm_" + k] = {"du": Vector3(0.3, -0.9, 0.2), "df": Vector3(0.75, 0.05, 0.65), "palm": Vector3(0, 1, 0.2)}
		s["curl_" + k] = 0.1
	s.head = (st.get("head", Vector3.ZERO) as Vector3) + Vector3(-4, 0, 9)
	return mixs(st, s, pulse(t, 0.0, 0.35, D - 0.5, D))


func c_stretch(t: float, q: Dictionary) -> Dictionary:
	var up := {"hips": Vector3(0, 0.02, 0), "spine": Vector3(-12, 0, 0), "head": Vector3(-16, 0, 0),
		"foot_L": {"pos": ankle_from(Vector3(0.1, 0, -0.01), 18.0), "pitch": 18.0, "yaw": 6.0}, "foot_R": {"pos": ankle_from(Vector3(0.1, 0, -0.01), 18.0), "pitch": 18.0, "yaw": 6.0},
		"arm_L": {"du": Vector3(0.12, 1, 0.05), "df": Vector3(-0.1, 1, 0.05), "palm": Vector3(0, 1, 0)},
		"arm_R": {"du": Vector3(0.12, 1, 0.05), "df": Vector3(-0.1, 1, 0.05), "palm": Vector3(0, 1, 0)}, "curl_L": 0.5, "curl_R": 0.5}
	var side := over(up, {"spine": Vector3(-6, 0, 14), "hips": Vector3(-0.04, 0.02, 0)})
	return keys(t, [[0.0, _stand()], [1.0, up], [1.8, side], [2.5, up], [3.2, _stand()]])


func c_talk(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = c_idle(t, q)
	var st: String = q.get("state", "stand")
	var hy: float = (base(st).get("hips", Vector3.ZERO) as Vector3).y
	for side in SIDES:
		var k: String = side.substr(0, 1)
		var c := 20 + (0 if side == "Left" else 7)
		var target := Vector3(0.17 + 0.07 * noise(t * 1.3, c), 1.06 + hy + 0.1 * noise(t * 1.1, c + 1), 0.28 + 0.07 * noise(t * 0.9, c + 2))
		s["arm_" + k] = {"ik": target, "palm": Vector3(-0.5, 0.7, 0.3), "hand": Vector3(-0.1, 0.25, 1), "pole": Vector3(0.6, -0.8, -0.2)}
		s["curl_" + k] = 0.25 + 0.15 * noise(t * 0.8, c + 3)
	s.head = (s.head as Vector3) + Vector3(4.0 * sin(TAU * 1.3 * t), 8.0 * noise(t * 0.5, 31), 3.0 * noise(t * 0.4, 32))
	return mixs(c_idle(t, q), s, pulse(t, 0.0, 0.4, q.get("clip_dur", 4.0) - 0.4, q.get("clip_dur", 4.0)))


func c_think(t: float, q: Dictionary) -> Dictionary:
	var st: Dictionary = base(q.get("state", "stand"))
	var hy: float = (st.get("hips", Vector3.ZERO) as Vector3).y
	var s: Dictionary = c_idle(t, q)
	s.arm_R = {"ik": Vector3(0.0, 1.575 + hy, 0.115), "palm": Vector3(0.3, -0.2, -1), "hand": Vector3(-0.35, 1, 0.3), "pole": Vector3(0.4, -1, 0.1)}
	s.curl_R = 0.65
	s.point_R = 0.5
	s.arm_L = {"ik": Vector3(-0.12, 1.2 + hy, 0.16), "palm": Vector3(0, 1, 0), "hand": Vector3(-1, 0, 0.1), "pole": Vector3(0.6, -0.7, -0.2)}
	s.curl_L = 0.5
	s.head = (s.head as Vector3) + Vector3(10, 0, 7)
	var D: float = q.get("clip_dur", 3.0)
	return mixs(c_idle(t, q), s, pulse(t, 0.0, 0.5, D - 0.5, D))


func c_cross_arms(t: float, q: Dictionary) -> Dictionary:
	var st: Dictionary = base(q.get("state", "stand"))
	var hy: float = (st.get("hips", Vector3.ZERO) as Vector3).y
	var s: Dictionary = c_idle(t, q)
	s.arm_L = {"ik": Vector3(-0.16, 1.21 + hy, 0.12), "palm": Vector3(0, 0, -1), "hand": Vector3(-1, 0.05, 0), "pole": Vector3(0.7, -0.6, 0.3)}
	s.arm_R = {"ik": Vector3(-0.15, 1.25 + hy, 0.16), "palm": Vector3(0, 0, -1), "hand": Vector3(-1, 0.1, 0), "pole": Vector3(0.7, -0.6, 0.3)}
	s.curl_L = 0.3
	s.curl_R = 0.3
	s.head = (s.head as Vector3) + Vector3(-4, 0, 0)
	var D: float = q.get("clip_dur", 3.0)
	return mixs(c_idle(t, q), s, pulse(t, 0.0, 0.5, D - 0.5, D))


func c_hands_on_hips(t: float, q: Dictionary) -> Dictionary:
	var s: Dictionary = c_idle(t, q)
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(0.19, 1.0, 0.0), "palm": Vector3(-1, 0, 0), "hand": Vector3(-0.2, -0.3, 0.9), "pole": Vector3(1, 0, -0.4)}
		s["curl_" + k] = 0.2
		s["foot_" + k] = {"pos": Vector3(0.15, ANKLE_Y, -0.01), "yaw": 12.0}
	s.spine = (s.spine as Vector3) + Vector3(-5, 0, 0)
	s.head = (s.head as Vector3) + Vector3(-6, 0, 0)
	var D: float = q.get("clip_dur", 3.0)
	return mixs(c_idle(t, q), s, pulse(t, 0.0, 0.5, D - 0.5, D))


func c_pray(t: float, q: Dictionary) -> Dictionary:
	var st: Dictionary = base(q.get("state", "stand"))
	var hy: float = (st.get("hips", Vector3.ZERO) as Vector3).y
	var s: Dictionary = _breathe(st, t, 0.5)
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(0.018, 1.29 + hy, 0.22), "palm": Vector3(-1, 0, 0), "hand": Vector3(0, 1, 0.25), "pole": Vector3(0.5, -1, -0.2)}
		s["curl_" + k] = 0.03
	s.head = Vector3(18, 0, 0)
	var D: float = q.get("clip_dur", 3.0)
	return mixs(st, s, pulse(t, 0.0, 0.6, D - 0.5, D))


func c_cry(t: float, q: Dictionary) -> Dictionary:
	var st: Dictionary = base(q.get("state", "stand"))
	var hy: float = (st.get("hips", Vector3.ZERO) as Vector3).y
	var s: Dictionary = st.duplicate()
	var sob := maxf(0.0, sin(TAU * 3.0 * t)) * (0.6 + 0.4 * noise(t, 41))
	s.spine = (st.get("spine", Vector3.ZERO) as Vector3) + Vector3(16 + 3.0 * sob, 0, 0)
	s.head = Vector3(22, 0, 0)
	s.sh_L = Vector2(6 + 6 * sob, 8)
	s.sh_R = Vector2(6 + 6 * sob, 8)
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(0.045, 1.6 + hy, 0.16), "chest": true, "palm": Vector3(0, 0, -1), "hand": Vector3(-0.2, 1, 0.1), "pole": Vector3(0.4, -1, 0)}
		s["curl_" + k] = 0.3
	var D: float = q.get("clip_dur", 3.0)
	return mixs(st, s, pulse(t, 0.0, 0.5, D - 0.4, D))


func c_laugh(t: float, q: Dictionary) -> Dictionary:
	var st: Dictionary = base(q.get("state", "stand"))
	var hy: float = (st.get("hips", Vector3.ZERO) as Vector3).y
	var s: Dictionary = st.duplicate()
	var shake := sin(TAU * 4.5 * t)
	s.spine = (st.get("spine", Vector3.ZERO) as Vector3) + Vector3(-8 + 4.0 * shake, 0, 0)
	s.head = Vector3(-18 + 5.0 * shake, 0, 0)
	s.sh_L = Vector2(4 + 3 * shake, 0)
	s.sh_R = Vector2(4 + 3 * shake, 0)
	for k in ["L", "R"]:
		s["arm_" + k] = {"ik": Vector3(0.11, 1.07 + hy, 0.15), "chest": true, "palm": Vector3(-0.3, 0, -1), "hand": Vector3(-1, -0.2, 0.2), "pole": Vector3(0.9, -0.5, -0.2)}
		s["curl_" + k] = 0.2
	var D: float = q.get("clip_dur", CLIPS.laugh.dur)
	return mixs(st, s, pulse(t, 0.0, 0.3, D - 0.4, D))


# --- action ----------------------------------------------------------------

func _stance() -> Dictionary:
	return {"hips": Vector3(0, -0.09, -0.02), "hips_rot": Vector3(0, 12, 0), "spine": Vector3(8, -10, 0), "head": Vector3(-6, -3, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.14), "yaw": 14.0}, "foot_R": {"pos": Vector3(0.13, ANKLE_Y, -0.2), "yaw": 30.0, "pitch": 8.0},
		"arm_L": {"ik": Vector3(-0.02, 1.47, 0.28), "palm": Vector3(-1, 0, 0), "hand": Vector3(-0.2, 0.9, 0.3), "pole": Vector3(0.3, -1, 0)},
		"arm_R": {"ik": Vector3(0.0, 1.44, 0.2), "palm": Vector3(-1, 0, 0), "hand": Vector3(-0.2, 0.9, 0.3), "pole": Vector3(0.3, -1, 0)},
		"curl_L": 1.0, "curl_R": 1.0}


func c_guard(t: float, q: Dictionary) -> Dictionary:
	var s := _stance()
	var b := sin(TAU * 2.0 * t)
	s.hips = (s.hips as Vector3) + Vector3(0.01 * sin(TAU * t), 0.018 * b, 0)
	for k in ["L", "R"]:
		var f: Dictionary = (s["foot_" + k] as Dictionary).duplicate()
		f.pitch = 10.0 + 8.0 * maxf(0.0, b)
		f.pos = ankle_from(Vector3((f.pos as Vector3).x, 0, (f.pos as Vector3).z), f.pitch)
		s["foot_" + k] = f
	return mixs(_stand(), s, smooth(0, 0.4, t))


func c_punch(t: float, q: Dictionary) -> Dictionary:
	var P: float = CLIPS.punch.dur
	var i := int(t / P)
	var tt := fposmod(t, P)
	var side := "Left" if i % 2 == 0 else "Right"
	if _side(q) in ["Left", "Right"] and q.get("side_explicit", false):
		side = _side(q)
	var s := _stance()
	var k := side.substr(0, 1)
	var ext := smooth(0.05, 0.17, tt) * (1.0 - smooth(0.27, 0.55, tt))
	var guard: Dictionary = s["arm_" + k]
	var reach := Vector3(0.03 if side == "Left" else -0.06, 1.45, 0.72)
	var punch := {"ik": reach, "palm": Vector3(0, -1, 0), "hand": Vector3(0, 0, 1), "pole": Vector3(0.8, -0.3, 0)}
	s["arm_" + k] = lerp_spec(guard, punch, ext)
	var twist := (-16.0 if side == "Left" else 22.0) * ext
	s.spine = (s.spine as Vector3) + Vector3(4 * ext, twist, 0)
	s.hips_rot = (s.hips_rot as Vector3) + Vector3(0, twist * 0.5, 0)
	var enter := smooth(0, 0.2, t)
	return mixs(_stand(), s, enter)


func c_kick(t: float, q: Dictionary) -> Dictionary:
	var P: float = CLIPS.kick.dur
	var tt := fposmod(t, P)
	var side := "Left" if _side(q) == "Left" and q.get("side_explicit", false) else "Right"
	var k := side.substr(0, 1)
	var other := "L" if k == "R" else "R"
	var s := _stance()
	s.foot_L = {"pos": Vector3(0.12, ANKLE_Y, 0.02), "yaw": 12.0}
	s.foot_R = {"pos": Vector3(0.12, ANKLE_Y, -0.06), "yaw": 20.0}
	var chamber := {"flex": 85.0, "knee": 105.0, "ankle": 20.0}
	var extend := {"flex": 88.0, "knee": 6.0, "ankle": 35.0}
	var leg: Dictionary = keys(tt, [[0.0, {"flex": 0.0, "knee": 0.0, "ankle": 0.0}], [0.3, chamber], [0.45, extend], [0.65, extend], [0.85, chamber], [1.1, {"flex": 0.0, "knee": 5.0, "ankle": 0.0}]])
	var up := pulse(tt, 0.0, 0.25, 0.9, 1.15)
	if up > 0.02:
		s["leg_" + k] = leg
		s.erase("foot_" + k)
	s["foot_" + other] = {"pos": Vector3(0.1, ANKLE_Y, -0.01), "yaw": 20.0}
	s.hips = Vector3(0, -0.04 - 0.03 * up, -0.05 * up)
	s.hips_rot = Vector3(-8.0 * up, 0, 0)
	s.spine = Vector3(-10.0 * up, 0, 0)
	s.head = Vector3(12.0 * up, 0, 0)
	return mixs(_stand(), s, smooth(0, 0.2, t))


func c_slash(t: float, q: Dictionary) -> Dictionary:
	var P: float = CLIPS.slash.dur
	var i := int(t / P)
	var tt := fposmod(t, P)
	var s := _stance()
	s.foot_L = {"pos": Vector3(0.13, ANKLE_Y, 0.22), "yaw": 10.0}
	var high := {"du": Vector3(0.45, 0.85, -0.25), "df": Vector3(0.1, 0.95, -0.3), "palm": Vector3(-1, 0, 0), "hand": Vector3(0.0, 0.5, -1)}
	var low := {"du": Vector3(-0.35, -0.55, 0.75), "df": Vector3(-0.55, -0.6, 0.6), "palm": Vector3(0, 1, 0), "hand": Vector3(-0.6, -0.6, 0.5)}
	if i % 2 == 1:
		high = {"du": Vector3(0.9, 0.3, -0.2), "df": Vector3(0.8, 0.3, -0.5), "palm": Vector3(0, -1, 0), "hand": Vector3(0.3, 0.2, -1)}
		low = {"du": Vector3(-0.5, 0.15, 0.85), "df": Vector3(-0.8, 0.1, 0.55), "palm": Vector3(0, -1, 0), "hand": Vector3(-0.9, 0.1, 0.4)}
	s.arm_R = keys(tt, [[0.0, high], [0.35, high], [0.52, low], [0.8, low], [P, high]])
	var twist: float = keys(tt, [[0.0, {"v": -25.0}], [0.35, {"v": -30.0}], [0.52, {"v": 28.0}], [0.8, {"v": 28.0}], [P, {"v": -25.0}]]).v
	s.spine = Vector3(8, twist, 0)
	s.hips_rot = Vector3(0, twist * 0.4, 0)
	s.arm_L = {"du": Vector3(0.7, -0.5, 0.3), "df": Vector3(0.6, -0.3, 0.6), "palm": Vector3(0, -1, 0)}
	s.curl_R = 1.0
	return mixs(_stand(), s, smooth(0, 0.3, t))


func c_cast(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.cast.dur)
	var gather := {"hips": Vector3(0, -0.05, -0.02), "spine": Vector3(6, 0, 0), "head": Vector3(0, 0, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.16), "yaw": 8.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y, -0.14), "yaw": 20.0},
		"arm_L": {"ik": Vector3(0.07, 1.22, 0.2), "palm": Vector3(-0.7, 0.2, 0), "hand": Vector3(-0.2, 0.3, 1), "pole": Vector3(0.5, -1, -0.3)},
		"arm_R": {"ik": Vector3(0.07, 1.22, 0.2), "palm": Vector3(-0.7, 0.2, 0), "hand": Vector3(-0.2, 0.3, 1), "pole": Vector3(0.5, -1, -0.3)},
		"curl_L": 0.45, "curl_R": 0.45}
	var thrust := over(gather, {"hips": Vector3(0, -0.1, 0.08), "spine": Vector3(14, 0, 0), "head": Vector3(-10, 0, 0),
		"arm_L": {"ik": Vector3(0.1, 1.42, 0.66), "palm": Vector3(0, 0.1, 1), "hand": Vector3(0.1, 1, 0.2), "pole": Vector3(0.6, -1, 0)},
		"arm_R": {"ik": Vector3(0.1, 1.42, 0.66), "palm": Vector3(0, 0.1, 1), "hand": Vector3(0.1, 1, 0.2), "pole": Vector3(0.6, -1, 0)},
		"curl_L": 0.05, "curl_R": 0.05})
	if t < 0.5:
		return mixs(_stand(), gather, smooth(0, 0.5, t))
	if t < 1.0:
		return gather
	if t < 1.25:
		return keys(t, [[1.0, gather], [1.25, thrust]])
	return mixs(thrust, _stand(), smooth(D - 0.6, D, t))


func c_throw(t: float, q: Dictionary) -> Dictionary:
	var wind := {"hips": Vector3(0, -0.05, -0.04), "hips_rot": Vector3(0, -15, 0), "spine": Vector3(-6, -25, 0), "head": Vector3(0, 30, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.05), "yaw": 8.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y, -0.12), "yaw": 30.0},
		"arm_R": {"du": Vector3(0.75, 0.25, -0.6), "df": Vector3(0.4, 0.85, -0.35), "palm": Vector3(0, 0, 1)},
		"arm_L": {"du": Vector3(0.1, 0.35, 0.9), "df": Vector3(0.1, 0.35, 0.9), "palm": Vector3(0, -1, 0)}, "curl_R": 0.8}
	var release := {"hips": Vector3(0, -0.08, 0.12), "hips_rot": Vector3(8, 18, 0), "spine": Vector3(20, 25, 0), "head": Vector3(-14, -15, 0),
		"foot_L": {"pos": Vector3(0.12, ANKLE_Y, 0.42), "yaw": 8.0}, "foot_R": {"pos": ankle_from(Vector3(0.12, 0, -0.12), 35.0), "yaw": 30.0, "pitch": 35.0, "ground": 1.0},
		"arm_R": {"du": Vector3(-0.1, 0.3, 0.95), "df": Vector3(-0.2, 0.1, 0.97), "palm": Vector3(0, -1, 0)},
		"arm_L": {"du": Vector3(0.3, -0.9, -0.3), "df": Vector3(0.25, -0.9, -0.1), "palm": Vector3(-1, 0, 0)}, "curl_R": 0.1}
	var follow := over(release, {"spine": Vector3(28, 30, 0), "arm_R": {"du": Vector3(-0.35, -0.7, 0.6), "df": Vector3(-0.45, -0.8, 0.4), "palm": Vector3(-1, 0, 0)}})
	return keys(t, [[0.0, _stand()], [0.55, wind], [0.78, release], [1.0, follow], [1.6, _stand()]])


func c_pick_up(t: float, q: Dictionary) -> Dictionary:
	var reach := {"hips": Vector3(0, -0.42, -0.14), "spine": Vector3(42, 0, 0), "head": Vector3(-5, 0, 0),
		"foot_L": {"pos": Vector3(0.13, ANKLE_Y, 0.04), "yaw": 12.0}, "foot_R": {"pos": Vector3(0.12, ANKLE_Y, -0.1), "yaw": 12.0},
		"arm_R": {"ik": Vector3(0.1, 0.07, 0.42), "palm": Vector3(0, -1, 0), "hand": Vector3(0, -0.2, 1), "pole": Vector3(0.6, 0, -0.8)},
		"arm_L": {"ik": Vector3(0.17, 0.58, 0.28), "palm": Vector3(0, -1, 0), "hand": Vector3(0, -0.3, 1), "pole": Vector3(0.7, -0.3, -0.5)},
		"curl_R": 0.1, "curl_L": 0.35}
	var grab := over(reach, {"curl_R": 0.95})
	var hold := over(_stand(), {"arm_R": {"ik": Vector3(0.1, 1.1, 0.32), "palm": Vector3(-0.3, 1, 0), "hand": Vector3(-0.2, 0.2, 1), "pole": Vector3(0.6, -1, -0.2)},
		"curl_R": 0.95, "head": Vector3(12, 0, 0)})
	return keys(t, [[0.0, _stand()], [0.9, reach], [1.25, grab], [2.1, hold], [2.6, hold]])


func c_aim(t: float, q: Dictionary) -> Dictionary:
	var D: float = q.get("clip_dur", CLIPS.aim.dur)
	var st: Dictionary = base(q.get("state", "stand"))
	var s: Dictionary = st.duplicate()
	var recoil := 0.0
	for shot in [1.0, 1.6]:
		recoil = maxf(recoil, pulse(t, shot, shot + 0.04, shot + 0.06, shot + 0.3))
	var aim_dir := qx(-10.0 * recoil) * Vector3(-0.12, 0.06, 1.0)
	s.arm_R = {"du": aim_dir, "df": aim_dir, "palm": Vector3(-1, -0.2, 0), "hand": aim_dir}
	s.point_R = 1.0
	s.curl_R = 0.9
	s.arm_L = {"ik": Vector3(0.02, 1.39 + 0.03 * recoil, 0.46), "palm": Vector3(0, 1, 0.2), "hand": Vector3(-0.6, 0.1, 0.8), "pole": Vector3(0.4, -1, -0.2)}
	s.curl_L = 0.7
	s.head = (st.get("head", Vector3.ZERO) as Vector3) + Vector3(4, -6, 4)
	if q.get("state", "stand") == "stand":
		s.foot_L = {"pos": Vector3(0.12, ANKLE_Y, 0.12), "yaw": 10.0}
		s.foot_R = {"pos": Vector3(0.12, ANKLE_Y, -0.14), "yaw": 25.0}
		s.hips = Vector3(0, -0.04, 0)
	return mixs(st, s, pulse(t, 0.0, 0.4, D - 0.35, D))


func c_fly(t: float, q: Dictionary) -> Dictionary:
	var bob := sin(TAU * 0.6 * t)
	var s := {"hips": Vector3(0, 0.55 + 0.06 * bob, 0), "hips_rot": Vector3(72, 0, 3.0 * bob), "spine": Vector3(-6, 0, 0), "head": Vector3(-62, 0, 0),
		"leg_L": {"flex": -4.0, "knee": 4.0, "ankle": 35.0, "abd": 1.0}, "leg_R": {"flex": 6.0, "knee": 22.0, "ankle": 35.0, "abd": 1.0},
		"arm_R": {"du": Vector3(0.08, 0.95, 0.25), "df": Vector3(0.05, 0.97, 0.2), "palm": Vector3(0, 0, 1)}, "curl_R": 1.0,
		"arm_L": {"du": Vector3(0.12, -1, 0.15), "df": Vector3(0.1, -1, 0.2), "palm": Vector3(-1, 0, 0)}, "curl_L": 0.5}
	var take := smooth(0, 0.8, t)
	s.vel = Vector3(0, 0, 6.0 * float(q.get("speed", 1.0)) * take)
	return mixs(_stand(), s, take)


func c_pushups(t: float, q: Dictionary) -> Dictionary:
	var n: int = maxi(1, int(q.get("count", 3)))
	var P: float = CLIPS.pushups.dur
	var plank := {"hips": Vector3(0, 0.34 - rest.Hips.y, -0.1), "hips_rot": Vector3(76, 0, 0), "spine": Vector3(2, 0, 0), "head": Vector3(-30, 0, 0),
		"leg_L": {"flex": -2.0, "ankle": 62.0, "toes": -50.0}, "leg_R": {"flex": -2.0, "ankle": 62.0, "toes": -50.0},
		"arm_L": {"ik": Vector3(0.2, 0.07, 0.36), "palm": Vector3(0, -1, 0), "hand": Vector3(0, 0, 1), "pole": Vector3(0.6, 0.2, -1)},
		"arm_R": {"ik": Vector3(0.2, 0.07, 0.36), "palm": Vector3(0, -1, 0), "hand": Vector3(0, 0, 1), "pole": Vector3(0.6, 0.2, -1)},
		"curl_L": 0.0, "curl_R": 0.0}
	var down := over(plank, {"hips": Vector3(0, 0.2 - rest.Hips.y, -0.1), "hips_rot": Vector3(83, 0, 0)})
	var kneel := over(base("kneel"), {"hips": Vector3(0, -0.55, 0.1), "hips_rot": Vector3(30, 0, 0), "spine": Vector3(20, 0, 0),
		"arm_L": plank.arm_L, "arm_R": plank.arm_R})
	var T_in := 1.4
	var T_reps := T_in + n * P
	if t < 0.7:
		return mixs(_stand(), kneel, smooth(0, 0.7, t))
	if t < T_in:
		return mixs(kneel, plank, smooth(0.7, T_in, t))
	if t < T_reps:
		var d := sin(PI * fposmod(t - T_in, P) / P)
		return lerp_spec(plank, down, d * d)
	if t < T_reps + 0.7:
		return mixs(plank, kneel, smooth(T_reps, T_reps + 0.7, t))
	return mixs(kneel, _stand(), smooth(T_reps + 0.7, T_reps + 1.4, t))


# =============================================================================
# Sequencer
# =============================================================================

## Seconds a segment lasts (in animation time).
func clip_duration(clip: String, q: Dictionary) -> float:
	var info: Dictionary = CLIPS.get(clip, {})
	var mood: Dictionary = q.get("mood", {})
	var speed: float = maxf(0.1, float(q.get("speed", 1.0)) * float(mood.get("speed", 1.0)))
	if info.get("loco", false):
		var d: float = float(q.get("duration", -1.0))
		if d <= 0.0:
			var c := gait(clip if GAITS.has(clip) else "walk", q)
			if int(q.get("steps", 0)) > 0:
				d = float(q.steps) / c.freq
			elif float(q.get("distance", 0.0)) > 0.0:
				d = float(q.distance) / maxf(c.v, 0.1)
			else:
				d = float(info.dur) * (1.0 + 0.5 * (maxi(1, int(q.get("count", 1))) - 1))
		return d
	if float(q.get("duration", -1.0)) > 0.0:
		return float(q.duration)
	var n := maxi(1, int(q.get("count", 1)))
	var base_d: float = float(info.get("dur", 2.0))
	match clip:
		"stand_up":
			return stand_up_duration(str(q.get("state", "stand"))) / speed
		"turn":
			var a := absf(float(q.get("angle", 90.0)))
			if q.get("dir", "") in ["back", "around"]:
				a = 180.0
			return (0.8 + a / 180.0 * 0.7) / speed
		"pushups":
			return (2.8 + n * base_d) / speed
		"nod", "shake_head":
			return (0.35 + 0.42 * maxi(2, int(q.get("count", 3)))) / speed
		"wave":
			return (0.8 + (maxf(2.0, n * 1.0)) / 2.2 * 1.0 + 0.6) / speed
		"sit", "sit_ground", "crouch", "kneel", "lie", "meditate":
			var hold := 1.2 if n <= 1 else n * 1.0
			if str(q.get("state", "stand")) == str(info.get("end", "")):
				return maxf(base_d * 0.6, hold) / speed
			return base_d / speed
	if info.get("count", false):
		base_d *= n
	return base_d / speed


## Evaluates a segment at `t` seconds since it started (animation time).
func eval_segment(seg: Dictionary, t: float) -> Dictionary:
	var clip: String = seg.clip
	var q: Dictionary = seg.q
	var info: Dictionary = CLIPS.get(clip, {})
	var mood: Dictionary = q.get("mood", {})
	var tl := t
	if not info.get("loco", false):
		tl = t * float(q.get("speed", 1.0)) * float(mood.get("speed", 1.0))
	if str(q.get("style", "")) == "robot":
		tl = floorf(tl * 7.0) / 7.0
	var s: Dictionary = call("c_" + clip, tl, q)
	if seg.has("overlay"):
		var o: Dictionary = seg.overlay
		var oq: Dictionary = o.q
		var od: float = oq.get("clip_dur", 2.0)
		var ot := fposmod(t, od) if CLIPS.get(o.clip, {}).get("loop", false) or t < od else od
		s = _overlay(s, call("c_" + str(o.clip), ot, oq), _arms_for(oq))
	return _post(s, q, tl, info)


func _overlay(s: Dictionary, o: Dictionary, sides: Array) -> Dictionary:
	if s.has("_mix"):
		var m: Array = s["_mix"]
		return {"_mix": [_overlay(m[0], o, sides), _overlay(m[1], o, sides), m[2]]}
	if o.has("_mix"):
		var mo: Array = o["_mix"]
		return {"_mix": [_overlay(s, mo[0], sides), _overlay(s, mo[1], sides), mo[2]]}
	var out := s.duplicate()
	for side in sides:
		var k: String = side.substr(0, 1)
		for key in ["arm_", "curl_", "point_", "thumb_"]:
			if o.has(key + k):
				out[key + k] = o[key + k]
	if o.has("head"):
		out.head = (s.get("head", Vector3.ZERO) as Vector3) * 0.5 + (o.head as Vector3) * 0.5
	return out


## Mood and style adjustments on top of a clip.
func _post(s: Dictionary, q: Dictionary, t: float, info: Dictionary) -> Dictionary:
	if s.has("_mix"):
		var m: Array = s["_mix"]
		return {"_mix": [_post(m[0], q, t, info), _post(m[1], q, t, info), m[2]]}
	var out := s.duplicate()
	var mood: Dictionary = q.get("mood", {})
	var lying := (s.get("hips_rot", Vector3.ZERO) as Vector3).length() > 45.0
	if not mood.is_empty() and not lying:
		var sh: Vector2 = mood.get("sh", Vector2.ZERO)
		for k in ["L", "R"]:
			out["sh_" + k] = (s.get("sh_" + k, Vector2.ZERO) as Vector2) + sh
		if not info.get("loco", false):
			out.spine = (s.get("spine", Vector3.ZERO) as Vector3) + Vector3(float(mood.get("spine", 0.0)), 0, 0)
			out.head = (s.get("head", Vector3.ZERO) as Vector3) + Vector3(float(mood.get("head", 0.0)), 0, 0)
		else:
			out.spine = (s.get("spine", Vector3.ZERO) as Vector3) + Vector3(float(mood.get("spine", 0.0)) * 0.5, 0, 0)
	match str(q.get("style", "")):
		"zombie":
			if not lying:
				out.head = (out.get("head", Vector3.ZERO) as Vector3) + Vector3(12, 0, 18)
				if info.get("loco", false) or q.get("clip", "") == "idle":
					for k in ["L", "R"]:
						var d := Vector3(0.14, 0.02 + 0.03 * sin(t * 2.0 + (0.0 if k == "L" else 1.5)), 1.0)
						out["arm_" + k] = {"du": d, "df": d + Vector3(0, -0.05, 0), "palm": Vector3(0, -1, 0)}
						out["curl_" + k] = 0.35
		"drunk":
			if not lying:
				out.hips = (out.get("hips", Vector3.ZERO) as Vector3) + Vector3(0.05 * noise(t * 0.8, 51), 0, 0)
				out.spine = (out.get("spine", Vector3.ZERO) as Vector3) + Vector3(4.0 * noise(t * 0.5, 52), 0, 9.0 * noise(t * 0.6, 53))
				out.head = (out.get("head", Vector3.ZERO) as Vector3) + Vector3(8.0 * noise(t * 0.7, 54), 0, 12.0 * noise(t * 0.65, 55))
				out.turn = float(out.get("turn", 0.0)) + 32.0 * noise(t * 0.45, 56)
		"old":
			if not lying and not info.get("loco", false):
				out.spine = (out.get("spine", Vector3.ZERO) as Vector3) + Vector3(18, 0, 0)
				out.head = (out.get("head", Vector3.ZERO) as Vector3) + Vector3(-20, 0, 0)
				out.hips = (out.get("hips", Vector3.ZERO) as Vector3) + Vector3(0, -0.03, 0)
	return out


## Builds the timeline: [{clip, q, start, dur, overlay?}], inserting automatic
## "stand_up" segments when a clip needs the character on its feet.
func timeline(plan: Array) -> Array:
	var segs: Array = []
	var t := 0.0
	var state := "stand"
	for sg in plan:
		var clip: String = sg.get("clip", "idle")
		if not CLIPS.has(clip):
			continue
		var info: Dictionary = CLIPS[clip]
		var q: Dictionary = (sg.get("q", {}) as Dictionary).duplicate(true)
		q["clip"] = clip
		var needs_stand: bool = state != "stand" and not info.get("upper", false) and clip != "stand_up" and str(info.get("end", "")) != state
		if needs_stand:
			var sq := {"state": state, "clip": "stand_up", "mood": q.get("mood", {}), "style": q.get("style", "")}
			var sd := clip_duration("stand_up", sq)
			segs.append({"clip": "stand_up", "q": sq, "start": t, "dur": sd, "auto": true})
			t += sd
			state = "stand"
		q["state"] = state
		var d := clip_duration(clip, q)
		if info.get("loco", false):
			q["clip_dur"] = d
		else:
			q["clip_dur"] = d * float(q.get("speed", 1.0)) * float((q.get("mood", {}) as Dictionary).get("speed", 1.0))
		var seg := {"clip": clip, "q": q, "start": t, "dur": d}
		if sg.has("overlay") and CLIPS.has(str(sg.overlay.get("clip", ""))):
			var oq: Dictionary = (sg.overlay.get("q", {}) as Dictionary).duplicate(true)
			oq["state"] = "stand"
			oq["clip"] = sg.overlay.clip
			oq["clip_dur"] = clip_duration(str(sg.overlay.clip), oq)
			seg["overlay"] = {"clip": sg.overlay.clip, "q": oq}
		segs.append(seg)
		t += d
		if clip == "stand_up":
			state = "stand"
		elif info.has("end"):
			state = str(info.end)
		elif not info.get("upper", false):
			state = "stand"
	return segs


## Generates frames for a plan (Array of {clip, q[, overlay]}).
## Returns {frames: [{root, yaw, pose}], fps, duration, loop, segments}.
func generate(plan: Array, options: Dictionary = {}) -> Dictionary:
	seed_value = int(options.get("seed", 0))
	var fps: float = clampf(float(options.get("fps", 30.0)), 10.0, 120.0)
	var segs := timeline(plan)
	if segs.is_empty():
		segs = timeline([{"clip": "idle", "q": {}}])
	var loop := false
	var single_loop: bool = segs.size() == 1 and CLIPS[segs[0].clip].get("loop", false)
	if options.has("loop"):
		loop = bool(options.loop)
	else:
		loop = single_loop
	if loop and segs.size() == 1 and CLIPS[segs[0].clip].get("loco", false):
		# Whole gait cycles, so the loop is seamless.
		var c := gait(segs[0].clip if GAITS.has(segs[0].clip) else "walk", segs[0].q)
		var fc: float = c.freq * 0.5
		var cycles := maxf(1.0, roundf(float(segs[0].dur) * fc))
		segs[0].dur = cycles / fc
		segs[0].q["clip_dur"] = segs[0].dur
	var total := 0.0
	for s in segs:
		total = maxf(total, float(s.start) + float(s.dur))
	var xf: float = float(options.get("crossfade", DEFAULT_CROSSFADE))
	var n := maxi(2, int(ceil(total * fps)) + 1)
	var frames: Array = []
	var pos := Vector3.ZERO
	var yaw := 0.0
	var first_pose: Pose = null
	var sub := 4
	var cartoon := false
	for s in segs:
		if str(s.q.get("style", "")) == "cartoon":
			cartoon = true
	for f in n:
		var t := minf(float(f) / fps, total)
		var pose := _pose_at(segs, t, xf)
		if loop and not CLIPS[segs[0].clip].get("loco", false) and segs.size() == 1:
			if first_pose == null:
				first_pose = pose
			var w := smooth(total - 0.35, total, t)
			pose = blend(pose, first_pose, w)
		if cartoon:
			pose = _exaggerate(pose, 1.25)
		if f > 0:
			var dt := 1.0 / fps / float(sub)
			for k in sub:
				var tk := t - (1.0 / fps) + dt * (float(k) + 0.5)
				var m := _motion_at(segs, clampf(tk, 0.0, total), xf)
				yaw += float(m[1]) * DEG * dt
				pos += qy(yaw / DEG) * (m[0] as Vector3) * dt
		frames.append({"root": pos, "yaw": yaw, "pose": pose})
	if bool(options.get("in_place", false)):
		for fr in frames:
			fr.root = Vector3.ZERO
	var seg_info: Array = []
	for s in segs:
		var e := {"clip": s.clip, "start": snappedf(float(s.start), 0.01), "duration": snappedf(float(s.dur), 0.01)}
		if s.get("auto", false):
			e["auto"] = true
		if s.has("overlay"):
			e["overlay"] = s.overlay.clip
		seg_info.append(e)
	return {"frames": frames, "fps": fps, "duration": total, "loop": loop, "segments": seg_info}


func _seg_index(segs: Array, t: float) -> int:
	for i in segs.size():
		if t < float(segs[i].start) + float(segs[i].dur):
			return i
	return segs.size() - 1


func _pose_at(segs: Array, t: float, xf: float) -> Pose:
	var i := _seg_index(segs, t)
	var seg: Dictionary = segs[i]
	var lt: float = t - float(seg.start)
	var p := solve_any(eval_segment(seg, lt))
	if i > 0 and lt < xf:
		var prev: Dictionary = segs[i - 1]
		var pp := solve_any(eval_segment(prev, t - float(prev.start)))
		p = blend(pp, p, smooth(0.0, xf, lt))
	return p


func _motion_at(segs: Array, t: float, xf: float) -> Array:
	var i := _seg_index(segs, t)
	var seg: Dictionary = segs[i]
	var lt: float = t - float(seg.start)
	var m := spec_motion(eval_segment(seg, lt))
	if i > 0 and lt < xf:
		var prev: Dictionary = segs[i - 1]
		var mp := spec_motion(eval_segment(prev, t - float(prev.start)))
		var w := smooth(0.0, xf, lt)
		m = [(mp[0] as Vector3).lerp(m[0], w), lerpf(mp[1], m[1], w)]
	# A clip that ended keeps no momentum.
	if float(seg.start) + float(seg.dur) < t - 0.0001:
		return [Vector3.ZERO, 0.0]
	return m


static func _exaggerate(p: Pose, k: float) -> Pose:
	var out := Pose.new()
	for b in p.j:
		var q: Quaternion = p.j[b]
		var ang := q.get_angle()
		if ang < 0.0001:
			out.j[b] = q
		else:
			out.j[b] = Quaternion(q.get_axis(), ang * k)
	out.hips = p.hips * Vector3(k, k, k)
	out.vel = p.vel
	out.turn = p.turn
	return out


# =============================================================================
# Animation export
# =============================================================================

## Converts generated frames into a Godot Animation for the humanoid skeleton
## (tracks "Skeleton3D:<bone>"; root motion on "Root").
static func to_animation(result: Dictionary, skeleton_path: String = "Skeleton3D") -> Animation:
	var frames: Array = result.frames
	var fps: float = result.fps
	var anim := Animation.new()
	var n := frames.size()
	anim.length = maxf(float(n - 1) / fps, 1.0 / fps)
	anim.loop_mode = Animation.LOOP_LINEAR if result.get("loop", false) else Animation.LOOP_NONE
	anim.step = 1.0 / fps
	var prefix := skeleton_path + ":"
	var hips_rest := H.rest_position("Hips")
	var root_pos := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(root_pos, prefix + "Root")
	var root_rot := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(root_rot, prefix + "Root")
	var hips_pos := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_pos, prefix + "Hips")
	var names := H.bone_names()
	var rot_tracks := {}
	var values := {}
	for b in names:
		if b == "Root":
			continue
		values[b] = []
	var root_vals: Array = []
	var yaw_vals: Array = []
	var hips_vals: Array = []
	for f in n:
		var fr: Dictionary = frames[f]
		var pose = fr.pose
		root_vals.append(fr.root)
		yaw_vals.append(Quaternion(Vector3.UP, float(fr.yaw)))
		hips_vals.append(hips_rest + pose.hips)
		for b in values:
			(values[b] as Array).append(H.local_rotation(b, pose.rot(b)))
	_write_track(anim, root_pos, root_vals, fps, true)
	_write_track(anim, root_rot, yaw_vals, fps, false)
	_write_track(anim, hips_pos, hips_vals, fps, true)
	for b in values:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, prefix + b)
		var bn: String = b
		var tight: bool = bn == "Hips" or bn.ends_with("Leg") or bn.ends_with("Foot") or bn.ends_with("Toes")
		_write_track(anim, tr, values[b], fps, false, 0.06 if tight else 0.25)
	return anim


## Writes keys, dropping the ones that linear interpolation reproduces
## (greedy, with a bounded window so long clips stay fast).
static func _write_track(anim: Animation, track: int, vals: Array, fps: float, is_pos: bool, tol_deg: float = 0.25) -> void:
	var n := vals.size()
	var constant := true
	for i in range(1, n):
		if is_pos:
			if (vals[i] as Vector3).distance_to(vals[0]) > 0.0001:
				constant = false
				break
		elif (vals[i] as Quaternion).angle_to(vals[0]) > 0.0005:
			constant = false
			break
	if constant:
		if is_pos:
			anim.position_track_insert_key(track, 0.0, vals[0])
		else:
			anim.rotation_track_insert_key(track, 0.0, vals[0])
		return
	var keep := PackedByteArray()
	keep.resize(n)
	keep.fill(0)
	keep[0] = 1
	keep[n - 1] = 1
	var last := 0
	var tol_pos := 0.001
	var tol_rot := tol_deg * DEG
	for i in range(1, n - 1):
		var ok := i + 1 - last <= 8
		if ok:
			for j in range(last + 1, i + 1):
				var w := float(j - last) / float(i + 1 - last)
				if is_pos:
					if ((vals[last] as Vector3).lerp(vals[i + 1], w)).distance_to(vals[j]) > tol_pos:
						ok = false
						break
				elif ((vals[last] as Quaternion).slerp(vals[i + 1], w)).angle_to(vals[j]) > tol_rot:
					ok = false
					break
		if not ok:
			keep[i] = 1
			last = i
	for i in n:
		if keep[i] == 0:
			continue
		var t := float(i) / fps
		if is_pos:
			anim.position_track_insert_key(track, t, vals[i])
		else:
			anim.rotation_track_insert_key(track, t, vals[i])


## Applies a pose (joint rotations, hips offset, root) to a humanoid skeleton.
static func apply_pose(sk: Skeleton3D, pose, root: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	var hips_rest := H.rest_position("Hips")
	for b in H.bone_names():
		var i := sk.find_bone(b)
		if i < 0:
			continue
		if b == "Root":
			sk.set_bone_pose_rotation(i, Quaternion(Vector3.UP, yaw))
			sk.set_bone_pose_position(i, root)
			continue
		sk.set_bone_pose_rotation(i, H.local_rotation(b, pose.rot(b)))
		if b == "Hips":
			sk.set_bone_pose_position(i, hips_rest + pose.hips)
