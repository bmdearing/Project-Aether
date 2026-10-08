extends Node
class_name ShieldBlock
## Active block (Master v3, Block System): with a shield equipped and the
## Behaviors tab set to Raise Shield, holding RMB raises it instead of
## entering the weapon stance. Hits from the front are fully negated but
## drain Composure, as does holding the shield up. Running out breaks the
## guard: the shield drops and the player is stunned for GUARD_BREAK_STUN.
## Composure stands in for the doc's Stamina pool until that exists.

signal guard_broken

const BASE_COMPOSURE := 100.0
const HOLD_DRAIN_PER_SEC := 5.0
const HIT_COST_FLAT := 8.0
const HIT_COST_PER_MAX_HEALTH := 60.0  # extra cost for a hit worth 100% of max health
const REGEN_DELAY := 4.0               # doc: regenerates 4 s after the last block
const REGEN_PER_SEC := 40.0
const RAISE_AFTER_BREAK_FRACTION := 0.3
const BLOCK_HALF_ANGLE := 75.0
const MOVE_SPEED_MULTIPLIER := 0.6
const GUARD_BREAK_STUN := 1.0
const RESTORE_ON_PARRY := 25.0
const RESTORE_ON_RIPOSTE := 15.0
const RESTORE_ON_KILL := 5.0
const JOLT_PUSH := Vector3(0.0, 0.0, 0.03)
const JOLT_TILT := Vector3(0.04, 0.0, 0.0)

var is_raised: bool = false
var composure: float = BASE_COMPOSURE

var _player: Player
var _regen_delay: float = 0.0
var _recovering: bool = false

func _ready() -> void:
	_player = get_parent()
	composure = get_max_composure()
	EventBus.parry_successful.connect(func(_p, _e): restore(RESTORE_ON_PARRY))
	EventBus.riposte_executed.connect(_on_riposte_executed)
	EventBus.enemy_died.connect(func(_e): restore(RESTORE_ON_KILL))

func get_max_composure() -> float:
	return BASE_COMPOSURE + _player.stat_sheet.get_misc_bonus("stamina") if _player and _player.stat_sheet else BASE_COMPOSURE

func has_shield() -> bool:
	return _player.equipment != null and _player.equipment.offhand is Shield

## RMB raises the shield instead of entering the weapon stance.
func overrides_stance() -> bool:
	return GameState.shield_on_rmb and has_shield()

func get_move_speed_multiplier() -> float:
	return MOVE_SPEED_MULTIPLIER if is_raised else 1.0

func _on_riposte_executed(source: Node, _target: Node) -> void:
	if source == _player:
		restore(RESTORE_ON_RIPOSTE)

func restore(amount: float) -> void:
	composure = minf(composure + amount, get_max_composure())

func _physics_process(delta: float) -> void:
	var max_composure := get_max_composure()
	var wants := overrides_stance() and Input.is_action_pressed("stance") \
			and not _player.status_effects.is_stunned() and not _player.is_input_blocked()
	if is_raised and not wants:
		_lower()
	elif not is_raised and wants and _player.melee_attack.is_idle() and _can_raise(max_composure):
		_raise()

	if is_raised:
		_regen_delay = REGEN_DELAY
		_spend(HOLD_DRAIN_PER_SEC * delta)
	elif _regen_delay > 0.0:
		_regen_delay -= delta
	elif composure < max_composure:
		composure = minf(composure + REGEN_PER_SEC * delta, max_composure)
	if _recovering and composure >= max_composure * RAISE_AFTER_BREAK_FRACTION:
		_recovering = false

func _can_raise(max_composure: float) -> bool:
	return not _recovering and composure > 0.0 and max_composure > 0.0

## Called by Player.take_damage() for every non-DoT hit. True if the raised
## shield faced the source and negated it.
func try_block(amount: float, source: Node) -> bool:
	if not is_raised or not (source is Node3D):
		return false
	var to_source := (source as Node3D).global_position - _player.global_position
	to_source.y = 0.0
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if to_source.length() < 0.01 or forward.length() < 0.01:
		return false
	if rad_to_deg(forward.normalized().angle_to(to_source.normalized())) > BLOCK_HALF_ANGLE:
		return false
	var max_health := maxf(_player.health.max_health, 1.0)
	EventBus.hit_blocked.emit(_player)
	_jolt()
	_retaliate(amount, source)
	_spend(HIT_COST_FLAT + HIT_COST_PER_MAX_HEALTH * amount / max_health)
	return true

## "Triggers Retaliation on Block": the attacker takes the blocked hit back,
## scaled by increased Retaliation damage.
const RETALIATION_SHARE := 1.0

func _retaliate(amount: float, source: Node) -> void:
	var sheet := _player.stat_sheet
	if sheet == null or sheet.get_misc_bonus("retaliate_on_block") <= 0.0 or not source is Enemy:
		return
	var mult := 1.0 + sheet.get_misc_bonus("increased_retaliation_damage") / 100.0
	(source as Enemy).take_damage(amount * RETALIATION_SHARE * mult, Constants.DamageType.KINETIC)

func _spend(amount: float) -> void:
	composure = maxf(composure - amount, 0.0)
	if composure <= 0.0 and is_raised:
		_break_guard()

func _break_guard() -> void:
	_lower()
	_recovering = true
	_regen_delay = REGEN_DELAY
	_player.status_effects.apply_effect("guard_break")
	var sway: CameraSway = _player.camera.get_node_or_null("CameraSway")
	if sway:
		sway.kick(Vector3(-0.06, 0.0, 0.04))
	guard_broken.emit()

func _raise() -> void:
	is_raised = true
	_player.weapon_stance.cancel()

func _lower() -> void:
	is_raised = false

func _jolt() -> void:
	if _player.arm_rig:
		_player.arm_rig._kick(JOLT_PUSH, JOLT_TILT)
	var sway: CameraSway = _player.camera.get_node_or_null("CameraSway")
	if sway:
		sway.kick(Vector3(-0.015, 0.0, randf_range(-0.01, 0.01)))
