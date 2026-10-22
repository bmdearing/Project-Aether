extends RefCounted
class_name LedgeClimb
## Ledge catching and mantling for the Player. In the air, a ledge whose top
## is between the knees and the reach of the hands can be climbed:
##   - holding forward climbs straight over it (a quick vault for low ones),
##   - falling while facing it without forward held catches it: the player
##     hangs until forward/Jump (climb up) or Crouch/back (let go).
## Only static geometry counts, and never a body in the NO_CLIMB group
## (map boundaries, building shells), so nothing climbs out of a map.

const NO_CLIMB := &"no_climb"
## Ledge top above the feet: lowest worth a mantle, highest the hands reach.
const MIN_LEDGE := 0.5
const REACH := 2.15
## Up to here it's a vault (no hang); above it the climb starts from a hang.
const VAULT_HEIGHT := 1.2
const WALL_PROBE_HEIGHTS: Array[float] = [0.5, 1.2]
const WALL_PROBE_DISTANCE := 0.85
const LEDGE_INSET := 0.45
## Hanging: feet this far below the ledge top, body this far off the wall.
const HANG_DROP := 1.75
const HANG_OFF_WALL := 0.42
const FACING_DOT := 0.55
const MANTLE_BASE_SEC := 0.16
const MANTLE_PER_METRE := 0.11
## Every mantle takes at least this long, with no attacking or casting.
const MANTLE_MIN_SEC := 0.5
const RISE_SHARE := 0.7
## After letting go, no catch for this long (or it would re-grab at once).
const REGRAB_COOLDOWN := 0.4

enum State { NONE, HANG, MANTLE }

var state: State = State.NONE
var _player: Player
var _cooldown := 0.0
var _from := Vector3.ZERO
var _top := Vector3.ZERO
var _target := Vector3.ZERO
var _wall_normal := Vector3.ZERO
var _t := 0.0
var _duration := 0.0

func _init(player: Player) -> void:
	_player = player

func busy() -> bool:
	return state != State.NONE

static func forbid(body: Node) -> void:
	body.add_to_group(NO_CLIMB)

## Called after the player's own movement each physics frame.
func try_catch(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0 or _player.is_on_floor() or _player.is_mid_action():
		return
	var forward_held := Input.get_action_strength("move_forward") > 0.5 and not _player.is_input_blocked()
	var ledge := find_ledge()
	if ledge.is_empty():
		return
	var height: float = ledge["top"].y - _player.global_position.y
	if forward_held:
		_start_mantle(ledge)
	elif height > VAULT_HEIGHT and _player.velocity.y < 0.0:
		_start_hang(ledge)

## The climbable ledge in front of the player: {top, target, normal}, or {}.
func find_ledge() -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var feet := _player.global_position
	var facing := -_player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		return {}
	facing = facing.normalized()
	for probe_height in WALL_PROBE_HEIGHTS:
		var from := feet + Vector3.UP * probe_height
		var query := PhysicsRayQueryParameters3D.create(from, from + facing * WALL_PROBE_DISTANCE, 1)
		query.exclude = [_player.get_rid()]
		var wall := space.intersect_ray(query)
		if wall.is_empty() or not _climbable(wall["collider"]):
			continue
		var normal: Vector3 = wall["normal"]
		if absf(normal.y) > 0.35 or facing.dot(-normal) < FACING_DOT:
			continue
		normal.y = 0.0
		normal = normal.normalized()
		var over: Vector3 = wall["position"] - normal * LEDGE_INSET
		var down := PhysicsRayQueryParameters3D.create(Vector3(over.x, feet.y + REACH + 0.25, over.z), Vector3(over.x, feet.y + MIN_LEDGE - 0.05, over.z), 1)
		down.exclude = [_player.get_rid()]
		var top := space.intersect_ray(down)
		if top.is_empty() or top["normal"].y < 0.7 or not _climbable(top["collider"]):
			continue
		var height: float = top["position"].y - feet.y
		if height < MIN_LEDGE or height > REACH:
			continue
		var target: Vector3 = top["position"] + Vector3.UP * 0.05
		if not _fits(space, target):
			continue
		return {"top": top["position"], "target": target, "normal": normal}
	return {}

func _climbable(collider: Object) -> bool:
	if not (collider is StaticBody3D or collider is AnimatableBody3D):
		return false
	var node := collider as Node
	return not (node.is_in_group(NO_CLIMB) or (node.get_parent() and node.get_parent().is_in_group(NO_CLIMB)))

## Room for the standing capsule with its feet at `feet`.
func _fits(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = Player.STANDING_CAPSULE_HEIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (Player.STANDING_CAPSULE_HEIGHT / 2.0 + 0.04))
	params.collision_mask = _player.collision_mask
	params.exclude = [_player.get_rid()]
	return space.intersect_shape(params, 1).is_empty()

func _start_hang(ledge: Dictionary) -> void:
	state = State.HANG
	_top = ledge["top"]
	_target = ledge["target"]
	_wall_normal = ledge["normal"]
	var hang := _top + _wall_normal * (LEDGE_INSET + HANG_OFF_WALL)
	hang.y = _top.y - HANG_DROP
	_player.global_position = hang
	_stop_player()

func _start_mantle(ledge: Dictionary) -> void:
	state = State.MANTLE
	_top = ledge["top"]
	_target = ledge["target"]
	_wall_normal = ledge["normal"]
	_from = _player.global_position
	_t = 0.0
	_duration = maxf(MANTLE_MIN_SEC, MANTLE_BASE_SEC + MANTLE_PER_METRE * maxf(_target.y - _from.y, 0.0))
	_stop_player()
	_player.arm_rig.play_mantle(_duration)

func _stop_player() -> void:
	_player.velocity = Vector3.ZERO
	_player._move_velocity = Vector3.ZERO
	_player._impulse = Vector3.ZERO
	_player._is_dashing = false
	_player._is_sliding = false

## Runs instead of the player's movement while hanging or mantling.
func process(delta: float) -> void:
	if _player.status_effects.is_stunned() or _player.is_knocked_up() or not _player.health.is_alive():
		_let_go()
		return
	match state:
		State.HANG:
			_player.velocity = Vector3.ZERO
			if _player.is_input_blocked():
				return
			if Input.is_action_just_pressed("crouch") or Input.get_action_strength("move_backward") > 0.5:
				_let_go()
			elif Input.is_action_just_pressed("jump") or Input.get_action_strength("move_forward") > 0.5:
				_start_mantle({"top": _top, "target": _target, "normal": _wall_normal})
		State.MANTLE:
			_t += delta
			var k := clampf(_t / maxf(_duration, 0.01), 0.0, 1.0)
			var pos := _from
			if k < RISE_SHARE:
				var rise := ease(k / RISE_SHARE, 0.6)
				pos.y = lerpf(_from.y, _target.y, rise)
			else:
				var over := ease((k - RISE_SHARE) / (1.0 - RISE_SHARE), 0.8)
				pos = Vector3(_from.x, _target.y, _from.z).lerp(_target, over)
			_player.global_position = pos
			if k >= 1.0:
				state = State.NONE
				_player.velocity = Vector3.ZERO
				_player._jump_buffer_timer = 0.0
				# A little momentum onto the ledge, so a held forward keeps walking.
				_player._move_velocity = -_wall_normal * 2.0

func _let_go() -> void:
	state = State.NONE
	_cooldown = REGRAB_COOLDOWN
	_player.velocity = _wall_normal * 1.5
