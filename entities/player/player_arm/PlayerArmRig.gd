extends Node3D
class_name PlayerArmRig
## First-person viewmodel: the held weapon, the hands holding it, and every
## procedural motion layered on top of them.
##
## Layers, outermost first:
##   _sway  - camera-relative feel: mouse lag, walk bob, breathing, sprint
##            tuck, landing dip, equip raise, recoil/hit springs.
##   _main  - the weapon hand. Its pose is a hand position plus the direction
##            the weapon's tip points and the direction its face points (see
##            WeaponModelLibrary's grip-space convention), so clips read as
##            "hand here, blade pointing there" instead of Euler angles.
##   _off   - the left hand: on the weapon's second grip for two-handers, holding
##            a shield/focus, a second gauntlet, or tucked away until a cast.
##
## Attack clips are keyframed per weapon family (WeaponModelLibrary.FAMILY) and
## timed by the caller's windup/strike/recovery durations, so the strike pose
## lands exactly when PlayerMeleeAttack turns hits on. Clips advance on scaled
## process time, so melee hitstop freezes the swing at the impact frame.

enum Attack { LIGHT, HEAVY, CHARGED, FIRE }

const SHOW_ARMS := true

## Sway pivots around a point near the hands, not the camera, so tilting the
## viewmodel doesn't swing it across the screen.
const PIVOT := Vector3(0.12, -0.3, -0.45)
const RIGHT_SHOULDER := Vector3(0.36, -0.5, 0.3)
const LEFT_SHOULDER := Vector3(-0.36, -0.5, 0.3)
const OFF_HIDDEN := Vector3(-0.3, -0.75, -0.3)

## Hand pose: position (camera space), tip direction, face direction.
class Pose:
	var pos: Vector3
	var tip: Vector3
	var face: Vector3
	func _init(p: Vector3 = Vector3.ZERO, t: Vector3 = Vector3.UP, f: Vector3 = Vector3.BACK) -> void:
		pos = p
		tip = t.normalized()
		face = f.normalized()
	func lerp_to(o: Pose, w: float) -> Pose:
		return Pose.new(pos.lerp(o.pos, w), tip.slerp(o.tip, w) if tip.angle_to(o.tip) < 3.1 else tip.lerp(o.tip, w), face.slerp(o.face, w) if face.angle_to(o.face) < 3.1 else face.lerp(o.face, w))
	func basis() -> Basis:
		var y := tip.normalized()
		var z := face - y * face.dot(y)
		if z.length() < 0.001:
			z = Vector3.BACK - y * Vector3.BACK.dot(y)
			if z.length() < 0.001:
				z = Vector3.UP
		z = z.normalized()
		return Basis(y.cross(z), y, z)

## One keyframe of a clip track. `pos` is an offset from the live rest pose;
## a null tip/face holds the rest orientation.
class ClipKey:
	var t: float
	var pos: Vector3
	var tip: Variant
	var face: Variant
	var curve: float
	func _init(time: float, p: Vector3, tp: Variant, fc: Variant, c: float) -> void:
		t = time
		pos = p
		tip = (tp as Vector3).normalized() if tp != null else null
		face = (fc as Vector3).normalized() if fc != null else null
		curve = c

class Track:
	var keys: Array[ClipKey] = []
	var time: float = 0.0
	func active() -> bool:
		return not keys.is_empty() and time < keys[-1].t
	## Offset + orientation at the current time, relative to `rest`.
	func sample(rest: Pose) -> Pose:
		if keys.is_empty():
			return Pose.new(rest.pos, rest.tip, rest.face)
		var i := 0
		while i < keys.size() - 2 and time >= keys[i + 1].t:
			i += 1
		var k1 := keys[i]
		var k2 := keys[mini(i + 1, keys.size() - 1)]
		var k0 := keys[maxi(i - 1, 0)]
		var k3 := keys[mini(i + 2, keys.size() - 1)]
		var span := k2.t - k1.t
		var w := 1.0 if span <= 0.0 else clampf((time - k1.t) / span, 0.0, 1.0)
		w = ease(w, k2.curve)
		var p := k1.pos.cubic_interpolate(k2.pos, k0.pos, k3.pos, w)
		var tip := _dir(k1.tip, rest.tip).cubic_interpolate(_dir(k2.tip, rest.tip), _dir(k0.tip, rest.tip), _dir(k3.tip, rest.tip), w)
		var face := _dir(k1.face, rest.face).cubic_interpolate(_dir(k2.face, rest.face), _dir(k0.face, rest.face), _dir(k3.face, rest.face), w)
		if tip.length() < 0.01:
			tip = rest.tip
		if face.length() < 0.01:
			face = rest.face
		return Pose.new(rest.pos + p, tip, face)
	static func _dir(v: Variant, fallback: Vector3) -> Vector3:
		return v if v != null else fallback

## Per-family rest, guard (melee stance held) and aim (ranged stance held)
## poses: [hand pos, tip, face]. "off" is the left hand when it holds its own
## item or gauntlet.
const RESTS := {
	&"blade": {"rest": [Vector3(0.27, -0.29, -0.46), Vector3(-0.3, 0.8, -0.5), Vector3(0.3, 0.1, 1)],
		"guard": [Vector3(0.17, -0.2, -0.44), Vector3(-1, 0.4, -0.35), Vector3(0, 0.3, 1)]},
	&"heavy": {"rest": [Vector3(0.22, -0.33, -0.4), Vector3(-0.5, 0.75, -0.35), Vector3(0.3, 0.2, 1)],
		"guard": [Vector3(0.16, -0.22, -0.4), Vector3(-1, 0.5, -0.3), Vector3(0, 0.3, 1)]},
	&"thrust": {"rest": [Vector3(0.24, -0.26, -0.42), Vector3(-0.15, 0.4, -1), Vector3(0, 1, 0.3)],
		"guard": [Vector3(0.16, -0.17, -0.5), Vector3(-0.1, 0.15, -1), Vector3(1, 0.2, 0)]},
	&"blunt": {"rest": [Vector3(0.27, -0.32, -0.44), Vector3(-0.2, 0.85, -0.4), Vector3(0.3, 0.1, 1)],
		"guard": [Vector3(0.18, -0.2, -0.44), Vector3(-0.9, 0.55, -0.3), Vector3(0, 0.3, 1)]},
	&"spear": {"rest": [Vector3(0.27, -0.3, -0.38), Vector3(-0.3, 0.2, -1), Vector3(0, 1, 0)],
		"guard": [Vector3(0.18, -0.22, -0.22), Vector3(-0.05, 0.03, -1), Vector3(0, 1, 0)]},
	&"halberd": {"rest": [Vector3(0.26, -0.3, -0.36), Vector3(-0.2, 0.55, -0.8), Vector3(1, 0, 0)],
		"guard": [Vector3(0.18, -0.22, -0.26), Vector3(-0.1, 0.25, -1), Vector3(1, 0, 0)]},
	&"staff": {"rest": [Vector3(0.25, -0.34, -0.4), Vector3(-0.2, 0.95, -0.3), Vector3(0, 0, 1)],
		"guard": [Vector3(0.16, -0.24, -0.4), Vector3(-1, 0.6, -0.2), Vector3(0, 0.2, 1)]},
	&"whip": {"rest": [Vector3(0.26, -0.29, -0.42), Vector3(-0.1, 0.6, -0.8), Vector3(0, 0, 1)],
		"guard": [Vector3(0.2, -0.22, -0.44), Vector3(-0.3, 0.8, -0.4), Vector3(0, 0, 1)]},
	&"fist": {"rest": [Vector3(0.2, -0.22, -0.42), Vector3(-0.1, 0.5, -0.9), Vector3(0, 1, 0.5)],
		"guard": [Vector3(0.14, -0.15, -0.34), Vector3(-0.1, 0.5, -0.9), Vector3(0, 1, 0.3)],
		"off": [Vector3(-0.2, -0.22, -0.42), Vector3(0.1, 0.5, -0.9), Vector3(0, 1, 0.5)],
		"off_guard": [Vector3(-0.13, -0.14, -0.33), Vector3(0.1, 0.5, -0.9), Vector3(0, 1, 0.3)]},
	&"wand": {"rest": [Vector3(0.25, -0.26, -0.42), Vector3(-0.15, 0.5, -0.85), Vector3(0, 0, 1)],
		"guard": [Vector3(0.18, -0.2, -0.45), Vector3(-0.1, 0.3, -1), Vector3(0, 1, 0)]},
	&"pistol": {"rest": [Vector3(0.19, -0.18, -0.36), Vector3(-0.2, 0.05, -1), Vector3(0.15, 1, 0)],
		"aim": [Vector3(0.0, -0.105, -0.36), Vector3(0, 0, -1), Vector3(0, 1, 0)]},
	&"rifle": {"rest": [Vector3(0.18, -0.21, -0.3), Vector3(-0.12, 0.03, -1), Vector3(0.12, 1, 0)],
		"aim": [Vector3(0.0, -0.12, -0.24), Vector3(0, 0, -1), Vector3(0, 1, 0)]},
	&"bow": {"rest": [Vector3(0.2, -0.12, -0.55), Vector3(-0.2, 1, 0), Vector3(-0.1, 0, 1)],
		"aim": [Vector3(0.12, -0.09, -0.6), Vector3(-0.05, 1, 0), Vector3(0.05, 0, 1)]},
}
## Left hand holding a shield or focus, and raised for a block.
const OFF_ITEM_REST := [Vector3(-0.27, -0.3, -0.44), Vector3(0.1, 1, -0.2), Vector3(0, 0, 1)]
const OFF_ITEM_GUARD := [Vector3(-0.07, -0.18, -0.38), Vector3(0.05, 1, 0), Vector3(0, 0, 1)]

## Clip keys: [phase, fraction of that phase, hand offset, tip, face, ease curve].
## Phases "w" windup, "s" strike, "r" recovery; every clip ends back at rest.
## Ease curves follow Godot's ease(): <1 decelerates, >1 accelerates.
const DIAGONAL := [
	["w", 1.0, Vector3(0.1, 0.17, 0.1), Vector3(0.45, 0.8, 0.35), Vector3(-0.6, 0, 1), 0.45],
	["s", 0.45, Vector3(-0.1, 0.06, -0.16), Vector3(-0.35, 0.45, -0.85), Vector3(-0.8, -0.3, 0.3), 2.2],
	["s", 1.0, Vector3(-0.38, -0.2, -0.04), Vector3(-0.85, -0.4, -0.35), Vector3(-0.3, -0.9, 0.3), 0.55],
	["r", 0.25, Vector3(-0.4, -0.22, -0.02), Vector3(-0.8, -0.5, -0.3), Vector3(-0.3, -0.9, 0.3), 0.5],
]
const HORIZONTAL := [
	["w", 1.0, Vector3(0.1, 0.07, 0.06), Vector3(0.95, 0.3, 0.1), Vector3(0, 1, 0), 0.45],
	["s", 0.5, Vector3(-0.06, 0.03, -0.2), Vector3(-0.05, 0.12, -1), Vector3(0, 1, 0), 2.2],
	["s", 1.0, Vector3(-0.42, -0.04, -0.03), Vector3(-0.95, 0.05, 0.3), Vector3(0, 1, 0), 0.55],
	["r", 0.25, Vector3(-0.44, -0.06, 0.0), Vector3(-0.9, 0.0, 0.4), Vector3(0, 1, 0), 0.5],
]
const OVERHEAD := [
	["w", 1.0, Vector3(0.02, 0.24, 0.05), Vector3(-0.15, 0.85, 0.45), Vector3(1, 0, 0), 0.45],
	["s", 0.5, Vector3(-0.07, 0.14, -0.22), Vector3(-0.1, 0.65, -0.8), Vector3(1, 0, 0), 2.4],
	["s", 1.0, Vector3(-0.12, -0.22, -0.12), Vector3(-0.1, -0.75, -0.65), Vector3(1, 0, 0), 0.5],
	["r", 0.3, Vector3(-0.12, -0.24, -0.1), Vector3(-0.1, -0.8, -0.6), Vector3(1, 0, 0), 0.5],
]
const BACKHAND := [
	["w", 1.0, Vector3(-0.24, 0.1, 0.06), Vector3(-0.85, 0.45, 0.1), Vector3(0, 1, 0.3), 0.45],
	["s", 0.5, Vector3(-0.05, 0.05, -0.2), Vector3(-0.1, 0.1, -1), Vector3(0, 1, 0), 2.2],
	["s", 1.0, Vector3(0.12, -0.12, -0.05), Vector3(0.9, -0.25, -0.25), Vector3(0, 1, 0), 0.55],
]
const STAB := [
	["w", 1.0, Vector3(0.03, 0.03, 0.12), Vector3(-0.05, 0.35, -1), null, 0.45],
	["s", 1.0, Vector3(-0.12, 0.08, -0.32), Vector3(-0.15, 0.08, -1), null, 0.4],
	["r", 0.2, Vector3(-0.12, 0.08, -0.3), Vector3(-0.15, 0.08, -1), null, 0.5],
]
const LUNGE := [
	["w", 1.0, Vector3(0.05, 0.05, 0.08), Vector3(0.1, 0.45, -0.9), Vector3(1, 0, 0), 0.45],
	["s", 0.6, Vector3(-0.15, 0.1, -0.4), Vector3(-0.12, 0.1, -1), Vector3(0.3, 1, 0), 2.0],
	["s", 1.0, Vector3(-0.15, 0.09, -0.42), Vector3(-0.12, 0.08, -1), Vector3(1, 0.2, 0), 0.5],
	["r", 0.25, Vector3(-0.15, 0.08, -0.4), Vector3(-0.12, 0.08, -1), Vector3(1, 0.2, 0), 0.5],
]
const POLE_JAB := [
	["w", 1.0, Vector3(0.0, 0.0, 0.1), null, null, 0.45],
	["s", 1.0, Vector3(-0.04, 0.03, -0.36), Vector3(-0.06, 0.08, -1), null, 0.4],
	["r", 0.25, Vector3(-0.04, 0.03, -0.34), Vector3(-0.06, 0.08, -1), null, 0.5],
]
const POLE_DRIVE := [
	["w", 1.0, Vector3(0.02, 0.14, 0.16), Vector3(-0.1, 0.4, -0.9), null, 0.45],
	["s", 1.0, Vector3(-0.08, -0.06, -0.46), Vector3(-0.08, -0.25, -1), null, 0.4],
	["r", 0.25, Vector3(-0.08, -0.07, -0.44), Vector3(-0.08, -0.28, -1), null, 0.5],
]
const WHIP_CRACK := [
	["w", 1.0, Vector3(0.08, 0.18, 0.06), Vector3(0.15, 0.95, 0.15), Vector3(0, 0, 1), 0.45],
	["s", 0.55, Vector3(-0.05, 0.02, -0.25), Vector3(-0.1, 0.3, -1), Vector3(0, 1, 0), 2.2],
	["s", 1.0, Vector3(-0.08, -0.12, -0.2), Vector3(-0.1, -0.45, -1), Vector3(0, 1, 0), 0.5],
]
const WAND_FLICK := [
	["w", 1.0, Vector3(0.04, 0.1, 0.08), Vector3(0.0, 0.9, 0.3), null, 0.45],
	["s", 1.0, Vector3(-0.06, 0.02, -0.2), Vector3(-0.15, 0.2, -1), null, 0.4],
	["r", 0.2, Vector3(-0.06, 0.02, -0.19), Vector3(-0.15, 0.2, -1), null, 0.5],
]
## Wand shots: whip the wand across the body and back, alternating sides
## (the mirrored clip plays on every other shot).
const WAND_SLING := [
	["w", 1.0, Vector3(-0.16, 0.08, 0.04), Vector3(-0.95, 0.45, 0.05), null, 0.45],
	["s", 0.55, Vector3(0.0, 0.07, -0.16), Vector3(0.0, 0.4, -0.9), null, 2.0],
	["s", 1.0, Vector3(0.18, 0.0, -0.1), Vector3(0.95, 0.15, -0.35), null, 0.5],
	["r", 0.35, Vector3(0.17, 0.0, -0.1), Vector3(0.9, 0.18, -0.4), null, 0.5],
]
const PUNCH := [
	["w", 1.0, Vector3(0.03, -0.02, 0.08), null, null, 0.45],
	["s", 1.0, Vector3(-0.1, 0.07, -0.24), Vector3(-0.15, 0.3, -1), null, 0.35],
	["r", 0.2, Vector3(-0.1, 0.07, -0.22), Vector3(-0.15, 0.3, -1), null, 0.5],
]
const HOOK := [
	["w", 1.0, Vector3(0.1, -0.02, 0.06), Vector3(0.3, 0.1, -1), Vector3(0, 1, 0), 0.45],
	["s", 0.6, Vector3(-0.08, 0.07, -0.26), Vector3(-0.6, 0.05, -1), Vector3(0, 1, 0), 2.0],
	["s", 1.0, Vector3(-0.24, 0.06, -0.2), Vector3(-1, 0, -0.4), Vector3(0, 1, 0), 0.5],
]
const UPPERCUT := [
	["w", 1.0, Vector3(0.05, -0.14, 0.08), Vector3(0, -0.3, -1), Vector3(0, 0, 1), 0.45],
	["s", 1.0, Vector3(-0.12, 0.16, -0.3), Vector3(-0.1, 0.8, -0.6), Vector3(0, 0, 1), 0.4],
	["r", 0.25, Vector3(-0.12, 0.17, -0.28), Vector3(-0.1, 0.85, -0.5), Vector3(0, 0, 1), 0.5],
]
const PISTOL_KICK := [
	["s", 1.0, Vector3(0.0, 0.025, 0.06), Vector3(0, 0.55, -1), null, 0.25],
]
const RIFLE_KICK := [
	["s", 1.0, Vector3(0.0, 0.012, 0.07), Vector3(0, 0.15, -1), null, 0.25],
]
## How far the string hand pulls back from the brace at full draw (aiming).
const BOW_DRAW := 0.1
const BOW_RELEASE := [
	["s", 1.0, Vector3(0.0, 0.0, -0.03), Vector3(0.12, 1, -0.15), null, 0.3],
]

## [light, heavy, charged] clip per melee family.
const MELEE_CLIPS := {
	&"blade": [DIAGONAL, HORIZONTAL, OVERHEAD],
	&"heavy": [DIAGONAL, HORIZONTAL, OVERHEAD],
	&"thrust": [STAB, LUNGE, BACKHAND],
	&"blunt": [DIAGONAL, OVERHEAD, OVERHEAD],
	&"spear": [POLE_JAB, POLE_JAB, POLE_DRIVE],
	&"halberd": [POLE_JAB, OVERHEAD, HORIZONTAL],
	&"staff": [POLE_JAB, HORIZONTAL, OVERHEAD],
	&"whip": [WHIP_CRACK, WHIP_CRACK, WHIP_CRACK],
	&"fist": [PUNCH, HOOK, UPPERCUT],
	&"wand": [WAND_FLICK, WAND_FLICK, WAND_FLICK],
}

## Reload: tilt the weapon in, hold while the off hand works, bring it back.
const RELOAD := [
	["w", 1.0, Vector3(0.0, -0.07, 0.05), Vector3(-0.4, 0.35, -0.85), Vector3(-0.6, 1, 0), 0.5],
	["s", 0.5, Vector3(0.01, -0.09, 0.05), Vector3(-0.42, 0.3, -0.85), Vector3(-0.6, 1, 0), -1.8],
	["s", 1.0, Vector3(0.0, -0.06, 0.04), Vector3(-0.38, 0.38, -0.85), Vector3(-0.6, 1, 0), -1.8],
]
const RELOAD_OFF := [
	["w", 1.0, Vector3(-0.02, -0.25, 0.08), null, null, 0.6],
	["s", 0.6, Vector3(0.0, -0.22, 0.06), null, null, -1.8],
	["s", 1.0, Vector3(0.0, 0.0, 0.0), null, null, 0.5],
]
## Off hand casting: up into view, push forward, drop away.
## One-handed gun reload: the free hand comes up under the grip with a fresh mag.
const RELOAD_OFF_FREE := [
	["w", 1.0, Vector3(0.3, 0.3, -0.05), Vector3(0.3, 1, -0.3), Vector3(0, 0, 1), 0.5],
	["s", 0.45, Vector3(0.44, 0.47, -0.07), Vector3(0.4, 1, -0.4), Vector3(0, 0, 1), -1.8],
	["s", 1.0, Vector3(0.44, 0.49, -0.07), Vector3(0.4, 1, -0.4), Vector3(0, 0, 1), -1.8],
]
const CAST_OFF := [
	["w", 1.0, Vector3(0.12, 0.5, -0.12), Vector3(0.1, 1, -0.3), Vector3(0, 0, 1), 0.45],
	["s", 1.0, Vector3(0.16, 0.54, -0.26), Vector3(0.05, 1, -0.6), Vector3(0, 0, 1), 0.35],
	["r", 0.3, Vector3(0.16, 0.53, -0.24), Vector3(0.05, 1, -0.6), Vector3(0, 0, 1), 0.5],
]
const CAST_MAIN := [
	["w", 1.0, Vector3(0.0, 0.05, 0.06), null, null, 0.45],
	["s", 1.0, Vector3(-0.03, 0.08, -0.14), null, null, 0.35],
]

enum OffMode { HIDDEN, TWO_HAND, ITEM, GAUNTLET }

var _player: Player
var _sway: Node3D
var _main: Node3D
var _grip: Node3D
var _off: Node3D
var _off_holder: Node3D
var _right_hand: MeshInstance3D
var _left_hand: MeshInstance3D
var _right_arm: MeshInstance3D
var _left_arm: MeshInstance3D
var _weapon_model: Node3D
var _off_model: Node3D
var _muzzle_flash: Node3D

var _weapon: Weapon
var _offhand_item: Item
var _family: StringName = &"blade"
var _wand_alt: bool = false
var _off_mode: OffMode = OffMode.HIDDEN
var _offhand_grip: Vector3 = Vector3.ZERO

var _main_track := Track.new()
var _off_track := Track.new()
var _main_pose := Pose.new()
var _off_pose := Pose.new()
var _guard: bool = false
var _aiming: bool = false
var _guard_w: float = 0.0
var _shield_w: float = 0.0
var _aim_w: float = 0.0
var _fist_alt: bool = false

var _mouse_delta := Vector2.ZERO
var _sway_offset := Vector3.ZERO
var _sway_tilt := Vector3.ZERO
var _bob_phase: float = 0.0
var _bob_w: float = 0.0
var _sprint_w: float = 0.0
var _time: float = 0.0
var _equip_t: float = 1.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _kick_pos := Vector3.ZERO
var _kick_pos_v := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _kick_rot_v := Vector3.ZERO
var _flash_t: float = 0.0
var _cast_glow: MeshInstance3D
var _cast_glow_t: float = 0.0
var _bow_strings: Array[MeshInstance3D] = []
var _arrow: Node3D
var _bow_release_t: float = 0.0
var _bow_release_len: float = 0.0

func _ready() -> void:
	# Work in camera space: cancel the WeaponSocket offset we sit under.
	position = -(get_parent() as Node3D).position
	_sway = _node("Sway", self)
	_main = _node("Main", _sway)
	_grip = _node("Grip", _main)
	_off = _node("Off", _sway)
	_off_holder = _node("OffHolder", _off)
	_right_hand = _make_hand(_grip)
	_left_hand = _make_hand(_off)
	if SHOW_ARMS:
		_right_arm = _make_arm()
		_left_arm = _make_arm()
	_muzzle_flash = _make_muzzle_flash()
	_cast_glow = _make_cast_glow()
	var weapon_mesh := get_node_or_null("WeaponMesh") as MeshInstance3D
	if weapon_mesh:
		# Only the headshot check uses WeaponMesh now (its AttackHitbox child).
		weapon_mesh.reparent(_grip, false)
		weapon_mesh.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))
		weapon_mesh.mesh = null
	_snap_to_rest()
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.reload_started.connect(_on_reload_started)
	EventBus.reload_interrupted.connect(_on_reload_stopped)
	EventBus.ability_cast.connect(_on_ability_cast)

func _node(n: String, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = n
	parent.add_child(node)
	return node

# --- public API ---

## Rebuilds the held models. Safe to call every equipment change; only
## replays the raise animation when the weapon itself changed.
func set_loadout(weapon: Weapon, offhand: Item) -> void:
	var weapon_changed := weapon != _weapon
	if not weapon_changed and offhand == _offhand_item and (_weapon_model != null or weapon == null):
		return
	_weapon = weapon
	_offhand_item = offhand
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null
	if _off_model:
		_off_model.queue_free()
		_off_model = null
	_family = WeaponModelLibrary.get_family(weapon.weapon_type) if weapon else &"blade"
	_offhand_grip = Vector3.ZERO
	_right_hand.visible = weapon != null
	if weapon:
		_weapon_model = WeaponModelLibrary.build(weapon)
		_grip.add_child(_weapon_model)
		_right_hand.visible = not _weapon_model.get_meta("hide_hand", false)
	if weapon and _weapon_model.has_meta("offhand_grip"):
		_off_mode = OffMode.TWO_HAND
		_offhand_grip = _weapon_model.get_meta("offhand_grip")
	elif _family == &"fist":
		_off_mode = OffMode.GAUNTLET
		_off_model = WeaponModelLibrary.build_left_gauntlet(weapon)
		_off_holder.add_child(_off_model)
	elif offhand:
		_off_mode = OffMode.ITEM
		_off_model = WeaponModelLibrary.build_offhand(offhand)
		_off_holder.add_child(_off_model)
	else:
		_off_mode = OffMode.HIDDEN
	_left_hand.visible = _off_mode != OffMode.GAUNTLET
	_build_bow_parts()
	_main_track.keys.clear()
	_off_track.keys.clear()
	if weapon_changed:
		_equip_t = 0.0
	_snap_to_rest()

func get_family() -> StringName:
	return _family

## Melee swing or ranged shot, timed to the caller's phases.
func play_attack(kind: Attack, windup: float, strike: float, recovery: float) -> void:
	if kind == Attack.FIRE:
		_play_fire(windup, strike, recovery)
		return
	var clips: Array = MELEE_CLIPS.get(_family, MELEE_CLIPS[&"blade"])
	var clip: Array = clips[kind]
	if _family == &"fist" and kind == Attack.LIGHT:
		# Alternate jabs between the two fists.
		_fist_alt = not _fist_alt
		if _fist_alt:
			_start(_off_track, _mirror(clip), windup, strike, recovery, _off_rest())
			return
	_start(_main_track, clip, windup, strike, recovery, _main_rest())

## Right-click hold: melee raises a weapon guard, ranged aims down sights. The
## shield only comes up while ShieldBlock is actually raised.
func set_guard(on: bool) -> void:
	_guard = on

func set_aiming(on: bool) -> void:
	_aiming = on

func is_animating() -> bool:
	return _main_track.active() or _off_track.active()

# --- clip playback ---

func _start(track: Track, clip: Array, windup: float, strike: float, recovery: float, rest: Pose) -> void:
	var current := track.sample(rest) if track.active() else Pose.new(rest.pos, rest.tip, rest.face)
	track.keys.clear()
	track.time = 0.0
	var starts := {"w": 0.0, "s": windup, "r": windup + strike}
	var lens := {"w": windup, "s": strike, "r": recovery}
	track.keys.append(ClipKey.new(0.0, current.pos - rest.pos, current.tip, current.face, 1.0))
	for k in clip:
		var t: float = starts[k[0]] + lens[k[0]] * float(k[1])
		if t <= track.keys[-1].t:
			t = track.keys[-1].t + 0.001
		track.keys.append(ClipKey.new(t, k[2], k[3], k[4], k[5]))
	track.keys.append(ClipKey.new(maxf(windup + strike + recovery, track.keys[-1].t + 0.05), Vector3.ZERO, null, null, -1.8))

func _mirror(clip: Array) -> Array:
	var out: Array = []
	for k in clip:
		var p: Vector3 = k[2]
		var tp: Variant = Vector3(-k[3].x, k[3].y, k[3].z) if k[3] != null else null
		var fc: Variant = Vector3(-k[4].x, k[4].y, k[4].z) if k[4] != null else null
		out.append([k[0], k[1], Vector3(-p.x, p.y, p.z), tp, fc, k[5]])
	return out

func _play_fire(windup: float, strike: float, recovery: float) -> void:
	match _family:
		&"wand":
			_wand_alt = not _wand_alt
			_start(_main_track, WAND_SLING if _wand_alt else _mirror(WAND_SLING), windup, strike, recovery, _main_rest())
			_cast_glow_t = 0.3
		&"bow":
			_start(_main_track, BOW_RELEASE, 0.0, strike, recovery, _main_rest())
			# String hand snaps back on release, then returns to nock.
			_start(_off_track, [["s", 1.0, Vector3(0.03, 0.015, 0.04), null, null, 0.3]], 0.0, strike, recovery * 1.6, _off_rest())
			_bow_release_t = 0.0
			_bow_release_len = strike + recovery * 0.9
		&"pistol":
			_start(_main_track, PISTOL_KICK, 0.0, strike * 0.5, recovery + windup, _main_rest())
			_kick(Vector3(0, 0, 0.02), Vector3(0.05, 0, randf_range(-0.03, 0.03)))
			_flash()
		_:
			_start(_main_track, RIFLE_KICK, 0.0, strike * 0.5, recovery + windup, _main_rest())
			_kick(Vector3(0, 0, 0.03), Vector3(0.025, 0, randf_range(-0.02, 0.02)))
			_flash()

func _on_reload_started(weapon: Weapon) -> void:
	if weapon != _weapon:
		return
	var total := weapon.cycle_time if weapon.reload_per_shell else weapon.reload_time
	_start(_main_track, RELOAD, total * 0.2, total * 0.6, total * 0.2, _main_rest())
	if _off_mode == OffMode.HIDDEN:
		_start(_off_track, RELOAD_OFF_FREE, total * 0.2, total * 0.6, total * 0.2, _off_rest())
	elif _off_mode == OffMode.TWO_HAND:
		_start(_off_track, RELOAD_OFF, total * 0.2, total * 0.6, total * 0.2, _off_rest())

func _on_reload_stopped(weapon: Weapon) -> void:
	if weapon != _weapon:
		return
	# Return from wherever the reload got to.
	_start(_main_track, [], 0.0, 0.0, 0.18, _main_rest())
	_start(_off_track, [], 0.0, 0.0, 0.18, _off_rest())

func _on_ability_cast(caster: Node, _ability: Ability) -> void:
	if caster != _player or _player == null:
		return
	if _family == &"wand":
		_play_fire(0.08, 0.08, 0.22)
		return
	if _off_mode == OffMode.HIDDEN:
		_start(_off_track, CAST_OFF, 0.12, 0.1, 0.35, _off_rest())
		_cast_glow_t = 0.5
	elif _off_mode == OffMode.ITEM:
		_start(_off_track, CAST_MAIN, 0.12, 0.1, 0.3, _off_rest())
	else:
		_start(_main_track, CAST_MAIN, 0.12, 0.1, 0.3, _main_rest())

func _on_hit_landed(is_critical: bool, _spot: bool, is_kill: bool) -> void:
	if _weapon == null or _weapon.is_ranged:
		return
	var s := 1.6 if is_critical or is_kill else 1.0
	_kick(Vector3(0, 0, 0.015) * s, Vector3(randf_range(-0.02, 0.02), randf_range(-0.03, 0.03), randf_range(-0.04, 0.04)) * s)

func _kick(pos: Vector3, rot: Vector3) -> void:
	_kick_pos_v += pos * 40.0
	_kick_rot_v += rot * 40.0

# --- per-frame ---

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += (event as InputEventMouseMotion).relative

func _process(delta: float) -> void:
	if _player == null:
		_player = owner as Player
	_time += delta
	_main_track.time += delta
	_off_track.time += delta
	var attacking := _main_track.active()
	_guard_w = move_toward(_guard_w, 1.0 if _guard and not attacking else 0.0, delta * 6.0)
	var shield_up := _player != null and _player.shield_block != null and _player.shield_block.is_raised
	_shield_w = move_toward(_shield_w, 1.0 if shield_up else 0.0, delta * 8.0)
	_aim_w = move_toward(_aim_w, 1.0 if _aiming else 0.0, delta * 7.0)
	_update_sway(delta, attacking)

	_main_pose = _main_track.sample(_main_rest())
	_apply(_main, _main_pose)

	match _off_mode:
		OffMode.TWO_HAND:
			var off_rest := _off_rest()
			_off_pose = _off_track.sample(off_rest)
			_off.position = _off_pose.pos - PIVOT
			_off.basis = _main.basis
		_:
			_off_pose = _off_track.sample(_off_rest())
			_apply(_off, _off_pose)
	_left_hand.visible = _off_mode != OffMode.GAUNTLET and (_off_mode != OffMode.HIDDEN or _off_track.active())
	_off.visible = _off_mode != OffMode.HIDDEN or _off_track.active()

	if SHOW_ARMS:
		# Bows: the left arm holds the bow (main) and the right draws the string.
		var bow := _family == &"bow"
		_place_arm(_right_arm, _main, _right_hand.visible or _family == &"fist", LEFT_SHOULDER if bow else RIGHT_SHOULDER)
		_place_arm(_left_arm, _off, _off.visible, RIGHT_SHOULDER if bow else LEFT_SHOULDER)

	_update_bow(delta)
	_cast_glow_t = maxf(_cast_glow_t - delta, 0.0)
	_cast_glow.visible = _cast_glow_t > 0.0
	if _cast_glow.visible:
		_cast_glow.scale = Vector3.ONE * (0.5 + _cast_glow_t * 1.6)

	if _flash_t > 0.0:
		_flash_t -= delta
		_muzzle_flash.visible = _flash_t > 0.0

func _apply(node: Node3D, pose: Pose) -> void:
	node.position = pose.pos - PIVOT
	node.basis = pose.basis()

func _main_rest() -> Pose:
	var spec: Dictionary = RESTS.get(_family, RESTS[&"blade"])
	var pose := _pose_from(spec["rest"])
	if spec.has("guard") and _guard_w > 0.0:
		pose = pose.lerp_to(_pose_from(spec["guard"]), _smooth(_guard_w))
	if spec.has("aim") and _aim_w > 0.0:
		pose = pose.lerp_to(_pose_from(spec["aim"]), _smooth(_aim_w))
	return pose

func _off_rest() -> Pose:
	match _off_mode:
		OffMode.TWO_HAND:
			# Follows the weapon's second grip; pos only, orientation copies the main hand.
			# A bow's string hand draws back toward the face while aiming.
			var grip := _offhand_grip + Vector3(0, 0, BOW_DRAW * _smooth(_aim_w)) if _family == &"bow" else _offhand_grip
			var p := _main_pose.pos + _main_pose.basis() * grip
			return Pose.new(p, _main_pose.tip, _main_pose.face)
		OffMode.GAUNTLET:
			var spec: Dictionary = RESTS[&"fist"]
			return _pose_from(spec["off"]).lerp_to(_pose_from(spec["off_guard"]), _smooth(_guard_w))
		OffMode.ITEM:
			var guard := _shield_w if _offhand_item is Shield else 0.0
			return _pose_from(OFF_ITEM_REST).lerp_to(_pose_from(OFF_ITEM_GUARD), _smooth(guard))
	return Pose.new(OFF_HIDDEN, Vector3(0.1, 1, -0.3), Vector3(0, 0, 1))

func _pose_from(spec: Array) -> Pose:
	return Pose.new(spec[0], spec[1], spec[2])

func _snap_to_rest() -> void:
	_main_pose = _main_rest()
	_apply(_main, _main_pose)

static func _smooth(w: float) -> float:
	return w * w * (3.0 - 2.0 * w)

func _update_sway(delta: float, attacking: bool) -> void:
	var speed := 0.0
	var on_floor := true
	var vertical := 0.0
	if _player:
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		on_floor = _player.is_on_floor()
		vertical = _player.velocity.y

	# Mouse lag: the weapon trails the view a little, then catches up.
	var md := _mouse_delta
	_mouse_delta = Vector2.ZERO
	var aim_damp := lerpf(1.0, 0.3, _aim_w)
	var sway_target := Vector3(-md.x, md.y, 0.0) * 0.00045 * aim_damp
	sway_target = sway_target.limit_length(0.05)
	_sway_offset = _sway_offset.lerp(sway_target, clampf(delta * 9.0, 0.0, 1.0))
	var tilt_target := Vector3(md.y * 0.0018, md.x * 0.0018, md.x * 0.0025) * aim_damp
	tilt_target = tilt_target.limit_length(0.14)
	_sway_tilt = _sway_tilt.lerp(tilt_target, clampf(delta * 8.0, 0.0, 1.0))

	# Walk bob: figure-eight, bigger when sprinting, faded out while aiming.
	var moving := on_floor and speed > 0.5
	_bob_w = move_toward(_bob_w, clampf(speed / 6.0, 0.0, 1.6) if moving else 0.0, delta * 4.0)
	_bob_phase += delta * (5.5 + speed * 0.9) if moving else delta * 2.0
	var bob_amp := _bob_w * lerpf(1.0, 0.25, _aim_w)
	var bob := Vector3(sin(_bob_phase) * 0.012, -absf(cos(_bob_phase)) * 0.014, 0.0) * bob_amp
	var bob_rot := Vector3(0.0, 0.0, sin(_bob_phase) * 0.02) * bob_amp

	var breathe := Vector3(0.0, sin(_time * 1.6) * 0.0035, cos(_time * 0.8) * 0.002) * lerpf(1.0, 0.3, _aim_w)

	var sprinting := _player != null and moving and speed > _player.move_speed * 1.2 and not attacking and not _aiming
	_sprint_w = move_toward(_sprint_w, 1.0 if sprinting else 0.0, delta * 5.0)
	var sprint_pos := Vector3(-0.04, -0.06, 0.05) * _smooth(_sprint_w)
	var sprint_rot := Vector3(-0.25, 0.55, 0.2) * _smooth(_sprint_w)

	# Landing dip proportional to fall speed; a small lift on take-off.
	if not on_floor:
		_fall_speed = minf(vertical, _fall_speed)
	if on_floor and not _was_on_floor:
		var impact := clampf(-_fall_speed / 12.0, 0.15, 1.0)
		_kick(Vector3(0, -0.05, 0.01) * impact, Vector3(-0.08, 0, 0) * impact)
		_fall_speed = 0.0
	elif not on_floor and _was_on_floor and vertical > 1.0:
		_kick(Vector3(0, -0.02, 0), Vector3(0.04, 0, 0))
	_was_on_floor = on_floor
	var air := Vector3(0, clampf(-vertical * 0.002, -0.015, 0.02), 0) if not on_floor else Vector3.ZERO

	# Equip: rise in from below.
	_equip_t = minf(_equip_t + delta / 0.35, 1.0)
	var e := 1.0 - ease(_equip_t, 0.4)
	var equip_pos := Vector3(0.02, -0.3, 0.05) * e
	var equip_rot := Vector3(-0.6, 0.2, 0.0) * e

	_spring(delta)
	_sway.position = PIVOT + _sway_offset + bob + breathe + sprint_pos + air + equip_pos + _kick_pos
	_sway.rotation = _sway_tilt + bob_rot + sprint_rot + equip_rot + _kick_rot

func _spring(delta: float) -> void:
	var k := 180.0
	var c := 18.0
	var dt := minf(delta, 0.033)
	_kick_pos_v += (-k * _kick_pos - c * _kick_pos_v) * dt
	_kick_pos += _kick_pos_v * dt
	_kick_rot_v += (-k * _kick_rot - c * _kick_rot_v) * dt
	_kick_rot += _kick_rot_v * dt

# --- hands, arms, effects ---

func _make_hand(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Hand"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.08, 0.085)
	mi.mesh = mesh
	mi.material_override = _flat(Color(0.24, 0.16, 0.11), 0.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var knuckles := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.074, 0.07, 0.025)
	knuckles.mesh = km
	knuckles.position = Vector3(0, 0, -0.045)
	knuckles.material_override = mi.material_override
	mi.add_child(knuckles)
	parent.add_child(mi)
	return mi

func _make_arm() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.034
	mesh.bottom_radius = 0.06
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = _flat(Color(0.2, 0.23, 0.3), 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.042
	cm.bottom_radius = 0.045
	cm.height = 0.05
	cm.radial_segments = 8
	cuff.mesh = cm
	cuff.material_override = _flat(Color(0.3, 0.2, 0.13), 0.8)
	cuff.name = "Cuff"
	mi.add_child(cuff)
	_sway.add_child(mi)
	return mi

## Stretches a tapered sleeve from a shoulder point (behind the camera) to the wrist.
func _place_arm(arm: MeshInstance3D, hand: Node3D, show: bool, shoulder: Vector3) -> void:
	arm.visible = show
	if not show:
		return
	var wrist := hand.position - hand.basis.y * 0.06 + hand.basis.z * 0.01
	var from := shoulder - PIVOT
	var dir := wrist - from
	var length := dir.length()
	if length < 0.01:
		return
	var y := dir / length
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	arm.transform = Transform3D(Basis(x, y * length, z), from + dir * 0.5)
	var cuff := arm.get_node("Cuff") as Node3D
	cuff.position = Vector3(0, 0.5 - 0.03 / length, 0)
	cuff.scale = Vector3(1, 1.0 / length, 1)

func _build_bow_parts() -> void:
	for s in _bow_strings:
		s.queue_free()
	_bow_strings.clear()
	if _arrow:
		_arrow.queue_free()
		_arrow = null
	if _weapon_model == null or not _weapon_model.has_meta("bow_tip_top"):
		return
	var mat := _flat(Color(0.85, 0.82, 0.72), 0.9)
	for i in 2:
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0018
		mesh.bottom_radius = 0.0018
		mesh.height = 1.0
		mesh.radial_segments = 4
		mesh.rings = 1
		mi.mesh = mesh
		mi.material_override = mat
		_grip.add_child(mi)
		_bow_strings.append(mi)
	_arrow = Node3D.new()
	var model: Node3D = (load(WeaponModelLibrary.PACK % "Broadhead_Arrow") as PackedScene).instantiate()
	# Pack arrows run head-first along -Z with the nock at z = +0.38.
	model.scale = Vector3.ONE * 0.85
	model.position = Vector3(0, 0, -0.38 * 0.85)
	_arrow.add_child(model)
	_grip.add_child(_arrow)

## String runs tip -> nock -> tip. The nock rides the string hand except just
## after a release, when the string snaps back to brace.
func _update_bow(delta: float) -> void:
	if _bow_strings.is_empty():
		return
	_bow_release_t += delta
	var released := _bow_release_t < _bow_release_len
	var top: Vector3 = _weapon_model.get_meta("bow_tip_top")
	var bottom: Vector3 = _weapon_model.get_meta("bow_tip_bottom")
	var brace := Vector3(0, 0, top.z)
	var nock := brace
	if not released:
		nock = _main.basis.inverse() * (_off.position - _main.position)
		nock.z = maxf(nock.z, brace.z)
	_stretch(_bow_strings[0], top, nock)
	_stretch(_bow_strings[1], bottom, nock)
	_arrow.visible = not released
	var aim := Vector3(0.012, 0.01, 0.0) - nock
	if aim.length() > 0.01:
		_arrow.transform = Transform3D(Basis.looking_at(aim, Vector3.UP), nock)

func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	mi.transform = Transform3D(Basis(x, y * length, x.cross(y)), a + d * 0.5)

func _make_muzzle_flash() -> Node3D:
	var root := Node3D.new()
	root.name = "MuzzleFlash"
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mi.mesh = mesh
	mi.scale = Vector3(1, 1.8, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 2.0
	light.omni_range = 3.0
	root.add_child(light)
	root.visible = false
	_grip.add_child(root)
	return root

func _flash() -> void:
	if _weapon_model == null or not _weapon_model.has_meta("muzzle"):
		return
	_muzzle_flash.position = _weapon_model.get_meta("muzzle")
	_muzzle_flash.rotation = Vector3(0, randf() * TAU, 0)
	_muzzle_flash.visible = true
	_flash_t = 0.05

func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _make_cast_glow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.8, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.75, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.02, -0.08)
	mi.visible = false
	_off.add_child(mi)
	return mi
