extends Node
class_name PlayerMeleeAttack
## Player-driven melee attack: Idle -> Windup -> Strike -> Recovery.
## Hit detection is a real Area3D (Player.attack_hitbox, sweeps with the
## blade mesh) - body_entered against the "enemy" group. Swing is a
## procedural Tween driving PlayerArmRig's bone poses (see _play_swing());
## camera shake is a separate procedural Tween on camera.position. Neither
## is baked Animation data. try_special_attack() (driven by WeaponStance's
## right-click hold, 2026-08-30) is the same state machine with a bigger,
## weapon-specific pose/motion-value/duration - see WEAPON_TYPE_SPECIAL_POSE.

enum State { IDLE, WINDUP, STRIKE, RECOVERY }

## User feedback (2026-08-30): the original 0.1/0.12/0.15s swing (0.37s
## total) "was far too fast" even before any weapon-type scaling - bumped
## up across the board as the new no-weapon-match baseline, on top of
## which WEAPON_TYPE_SWING_DURATION_MULT below applies per weapon type.
@export var windup_duration: float = 0.22
@export var strike_duration: float = 0.16
@export var recovery_duration: float = 0.24
## Stands in for a "Basic Attack" skill's motion value - no skill/Tome
## system exists yet to grant one (Section 11: motion values live on
## individual skills, never a bare weapon). Now the DEFAULT/fallback for
## _effective_motion_value() below rather than the value every weapon
## uses - see that function for the per-weapon-type differentiation.
@export var base_motion_value: float = 1.0

## User request (2026-08-30): "apply motion value to the new melee attack
## system, faster movesets for different weapons will have lower motion
## value, while slower weapons like the greatsword will have a higher
## motion value." Section 11 already establishes base_motion_value itself
## as an invented stand-in for a missing Basic Attack skill (see its own
## comment above) - this extends that same stand-in per weapon type
## rather than contradicting the doc's real "motion values live on
## skills" design further. Same minimal-table-plus-DEFAULT convention
## Constants.WEAPON_BASE_CRIT_CHANCE already uses - only weapon types
## with a real .tres instance in this project get an explicit entry;
## anything else (including ranged types, which never reach this class
## at all - see Player._physics_process()'s is_ranged dispatch) falls
## back to base_motion_value.
const WEAPON_TYPE_MOTION_VALUE := {
	"Dagger": 0.65,
	"Greatsword": 1.35,
	"Rapier": 0.55,
	"Staff": 1.0,
	"Gauntlet": 0.5,
}

## User feedback (2026-08-30): a greatsword swing needs to actually feel
## heavy, not just deal more damage per the motion value above - this
## multiplies windup/strike/recovery duration (via _effective_duration())
## so a Greatsword swing genuinely takes longer than a Dagger's, and
## scales how far PlayerArmRig's bone poses rotate (via
## WEAPON_TYPE_SWING_INTENSITY below) so a heavier weapon also reads as a
## bigger arc, not a slowed-down copy of the same small motion. Same
## minimal-table-plus-DEFAULT convention as WEAPON_TYPE_MOTION_VALUE.
## User feedback (2026-08-30, second follow-up): even at 1.85x "still
## don't feel right... slower side to side cleaves would look good" -
## pushed further still.
const WEAPON_TYPE_SWING_DURATION_MULT := {
	"Dagger": 0.75,
	"Greatsword": 2.4,
	"Rapier": 0.65,
	"Staff": 1.4,
	"Gauntlet": 0.55,
}
const WEAPON_TYPE_SWING_INTENSITY := {
	"Dagger": 0.85,
	"Greatsword": 1.3,
	"Rapier": 0.9,
	"Staff": 1.15,
	"Gauntlet": 0.8,
}

## User feedback (2026-08-30, second follow-up): "slower side to side
## cleaves would look good" for Greatsword specifically - mixing in the
## diagonal CLEAVE made successive swings alternate between two visually
## unrelated motion types (a vertical cut, then a horizontal one) instead
## of reading as one consistent windmill - Greatsword alternates the two
## horizontal sweeps. User feedback (2026-08-30 later still): "the
## animations are all the same for all of the weapons" - Rapier/Dagger/
## Gauntlet had all been falling back to the same NORMAL_COMBO_POSES
## default, AND Staff had been sharing Greatsword's exact SWEEP pair (a
## scratch test asserting every weapon's combo pose LIST is distinct
## caught that second one). Each weapon now has its own: Rapier is a pure
## thruster (single-pose "combo" - every attack is DASH_THRUST, no
## cycling, since a rapier doesn't really slash), Dagger alternates a
## slash and a stab (a flurry, distinct from Rapier's pure-thrust
## identity), Gauntlet always JABs (its own elbow-driven punch pose, not
## a blade motion at all), Staff gets its own TWIRL pair (wrist-rotation-
## dominant, a spin rather than Greatsword's shoulder-driven heavy
## cleave). Same minimal-table-plus-DEFAULT convention as the rest of
## this file - anything still unmapped (a future weapon type) keeps the
## full 3-pose NORMAL_COMBO_POSES variety.
const WEAPON_TYPE_COMBO_POSES := {
	"Greatsword": [PlayerArmRig.PoseSet.SWEEP_RIGHT, PlayerArmRig.PoseSet.SWEEP_LEFT],
	"Staff": [PlayerArmRig.PoseSet.TWIRL_RIGHT, PlayerArmRig.PoseSet.TWIRL_LEFT],
	"Rapier": [PlayerArmRig.PoseSet.DASH_THRUST],
	"Dagger": [PlayerArmRig.PoseSet.CLEAVE, PlayerArmRig.PoseSet.DASH_THRUST],
	"Gauntlet": [PlayerArmRig.PoseSet.JAB],
}

## User request (2026-08-30): "holding right click puts you in a stance
## that preps you for heavier or special attacks... a great sword might
## have a big sweep, a rapier might dash and thrust in one direction." A
## real Rapier item didn't exist yet when this was first built, so
## DASH_THRUST was mapped onto Dagger as a stand-in (closest existing
## light one-handed weapon) - now that worn_rapier.tres exists (2026-08-30
## later still), Rapier gets its own entry (the "real" intended match),
## and Dagger keeps DASH_THRUST too since a quick dagger lunge is just as
## fitting. Staff reuses BIG_SWEEP (a staff sweep). Gauntlet's special is
## JAB, not DASH_THRUST anymore (2026-08-30 even later, "the animations
## are all the same" feedback) - its special should feel like a BIGGER
## punch, not switch to an entirely different motion family; the existing
## intensity/duration multipliers already make a scaled-up JAB read as a
## haymaker. Driven by WeaponStance.gd, which owns the right-click hold
## input and calls try_special_attack() on a left-click while active.
const WEAPON_TYPE_SPECIAL_POSE := {
	"Dagger": PlayerArmRig.PoseSet.DASH_THRUST,
	"Greatsword": PlayerArmRig.PoseSet.BIG_SWEEP,
	"Rapier": PlayerArmRig.PoseSet.DASH_THRUST,
	"Staff": PlayerArmRig.PoseSet.BIG_SWEEP,
	"Gauntlet": PlayerArmRig.PoseSet.JAB,
}
const SPECIAL_MOTION_VALUE_MULTIPLIER := 1.8
const SPECIAL_DURATION_MULTIPLIER := 1.4
## User feedback (2026-08-30, second follow-up): this stacked with
## WEAPON_TYPE_SWING_INTENSITY (1.3 for Greatsword) on top of BIG_SWEEP's
## own already-big base angles, swinging the sword ~114 degrees around
## the shoulder and off past the edge of frame - lowered here, and
## BIG_SWEEP's own base angles were independently halved in
## PlayerArmRig.gd, so neither change alone has to carry the whole fix.
const SPECIAL_INTENSITY_MULTIPLIER := 1.1
## Normal (non-stance) swings cycle through these so repeated attacks read
## as a combo instead of the identical cut every time - user request:
## "feel free to sweep from side to side as well."
const NORMAL_COMBO_POSES := [PlayerArmRig.PoseSet.CLEAVE, PlayerArmRig.PoseSet.SWEEP_RIGHT, PlayerArmRig.PoseSet.SWEEP_LEFT]

@export var hitstop_time_scale: float = 0.05
@export var hitstop_duration: float = 0.06
@export var shake_strength: float = 0.05
@export var shake_duration: float = 0.15

## User request (2026-08-30): "Movement speed should be reduced when
## attacking with a melee weapon." Applies for the whole swing (Windup
## through Recovery, not just the Strike instant), matching Section 07's
## melee-weight framing of a swing as one committed action rather than an
## instant tap - Player._effective_speed() reads this every physics frame.
const ATTACKING_MOVE_SPEED_MULTIPLIER := 0.5

## User request (2026-08-30): "deal Counter damage and deal 15% more
## damage" - exact rate given, not invented.
const COUNTER_DAMAGE_MULTIPLIER := 1.15

var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Player
var _hitbox: Area3D
var _resolved_this_swing: bool = false
var _combo_index: int = 0
var _is_special: bool = false

func _ready() -> void:
	_player = get_parent()

func is_idle() -> bool:
	return _state == State.IDLE

func get_move_speed_multiplier() -> float:
	return ATTACKING_MOVE_SPEED_MULTIPLIER if _state != State.IDLE else 1.0

## Called from Player._physics_process on the "attack" action. Player's
## @onready vars (weapon_socket/camera/etc.) aren't touched until an
## actual attack, well after children ready before their parent.
func try_attack() -> void:
	if _state != State.IDLE:
		return
	if _player.get_active_weapon() == null:
		return
	_ensure_hitbox_connected()
	_is_special = false
	_enter_windup()

## Called from Player._physics_process instead of try_attack() when
## WeaponStance.is_active - the weapon's special per WEAPON_TYPE_SPECIAL_POSE
## (falls back to a boosted CLEAVE for anything unmapped, same
## minimal-table-plus-DEFAULT convention as the rest of this file). Dagger's
## special also fires a real forward dash before the thrust - see
## Player.try_special_dash() - best-effort: if the dash is on its own
## cooldown (shared with the Shift-dash, deliberately not a separate free
## dash resource) the thrust still lands, just without the lunge.
func try_special_attack() -> void:
	if _state != State.IDLE:
		return
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return
	if weapon.weapon_type == "Dagger":
		var forward := -_player.camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.01:
			_player.try_special_dash(forward.normalized())
	_ensure_hitbox_connected()
	_is_special = true
	_enter_windup()

func _ensure_hitbox_connected() -> void:
	if _hitbox != null:
		return
	_hitbox = _player.attack_hitbox
	if _hitbox:
		_hitbox.monitoring = false
		_hitbox.body_entered.connect(_on_hitbox_body_entered)

func get_special_pose_set() -> PlayerArmRig.PoseSet:
	var weapon := _player.get_active_weapon()
	return WEAPON_TYPE_SPECIAL_POSE.get(weapon.weapon_type, PlayerArmRig.PoseSet.CLEAVE) if weapon else PlayerArmRig.PoseSet.CLEAVE

func get_special_intensity() -> float:
	return _effective_swing_intensity() * SPECIAL_INTENSITY_MULTIPLIER

func _physics_process(delta: float) -> void:
	match _state:
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_enter_strike()
		State.STRIKE:
			_timer -= delta
			if _timer <= 0.0:
				_end_strike()
		State.RECOVERY:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE
				_is_special = false

## Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the
## base duration rather than mutating windup_duration/etc. directly.
## Also applies WEAPON_TYPE_SWING_DURATION_MULT so windup/strike/recovery
## timers and PlayerArmRig's tween durations (_play_swing() passes these
## same effective values) stay perfectly in sync regardless of weapon.
func _effective_duration(base: float) -> float:
	var weapon := _player.get_active_weapon()
	var swing_mult: float = WEAPON_TYPE_SWING_DURATION_MULT.get(weapon.weapon_type, 1.0) if weapon else 1.0
	if _is_special:
		swing_mult *= SPECIAL_DURATION_MULTIPLIER
	return base * swing_mult / _player.get_action_speed_multiplier()

func _effective_swing_intensity() -> float:
	var weapon := _player.get_active_weapon()
	return WEAPON_TYPE_SWING_INTENSITY.get(weapon.weapon_type, 1.0) if weapon else 1.0

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = _effective_duration(windup_duration)
	_play_swing()

func _enter_strike() -> void:
	_state = State.STRIKE
	_timer = _effective_duration(strike_duration)
	_resolved_this_swing = false
	if _hitbox:
		_hitbox.monitoring = true

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = _effective_duration(recovery_duration)

## Swing choreography now lives on PlayerArmRig's own 3-bone chain
## (shoulder/elbow/wrist) instead of tweening one rigid WeaponSocket
## rotation - see PlayerArmRig.play_attack_swing() for the actual pose
## targets. Timings here still drive it so windup/strike/recovery stay
## exactly in sync with the state machine above (blade reaches full
## extension right as Strike begins and the hitbox turns on). A special
## attack always uses its weapon's dedicated pose (get_special_pose_set());
## a normal attack cycles that weapon's combo list (WEAPON_TYPE_COMBO_POSES,
## falling back to NORMAL_COMBO_POSES) so back-to-back swings read as a
## combo, not the same cut repeated.
func _play_swing() -> void:
	var rig := _player.arm_rig
	if rig == null:
		return
	var pose_set: PlayerArmRig.PoseSet
	var intensity: float
	if _is_special:
		pose_set = get_special_pose_set()
		intensity = get_special_intensity()
	else:
		var weapon := _player.get_active_weapon()
		var combo: Array = WEAPON_TYPE_COMBO_POSES.get(weapon.weapon_type, NORMAL_COMBO_POSES) if weapon else NORMAL_COMBO_POSES
		pose_set = combo[_combo_index % combo.size()]
		_combo_index += 1
		intensity = _effective_swing_intensity()
	rig.play_attack_swing(
		pose_set,
		_effective_duration(windup_duration),
		_effective_duration(strike_duration),
		_effective_duration(recovery_duration),
		intensity
	)

func _on_hitbox_body_entered(body: Node3D) -> void:
	if _state != State.STRIKE or _resolved_this_swing:
		return
	var enemy := body as Enemy
	if enemy == null:
		return
	_resolved_this_swing = true
	if _hitbox:
		_hitbox.set_deferred("monitoring", false)  # can't set monitoring synchronously from inside body_entered
	_deal_damage(enemy)

func _effective_motion_value(weapon: Weapon) -> float:
	return WEAPON_TYPE_MOTION_VALUE.get(weapon.weapon_type, base_motion_value)

func _deal_damage(target: Enemy) -> void:
	var weapon: Weapon = _player.get_active_weapon()
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var motion_value := _effective_motion_value(weapon) * (SPECIAL_MOTION_VALUE_MULTIPLIER if _is_special else 1.0)

	# A melee hit on an already-broken enemy is a Riposte, not a normal
	# swing - big bonus damage + a moment of player invulnerability,
	# handled entirely by ParryRiposteHandler.
	if _player.parry_handler and _player.parry_handler.can_riposte(target):
		_player.parry_handler.execute_riposte(target, weapon, motion_value, damage_type)
		_trigger_hit_feedback(true)
		return

	var hit := weapon.roll_damage(motion_value, _player.stat_sheet)
	var final_damage: float = hit["final_damage"]
	var is_critical: bool = hit["is_critical"]

	# User request (2026-08-30): "If you melee attack an enemy while they
	# are mid attack animation, you deal Counter damage and deal 15% more
	# damage." Checked here rather than in take_damage()/DamageCalculator -
	# whether a hit lands DURING the target's own committed attack window
	# is timing information only the attacker's own swing resolution has,
	# same reasoning Riposte's own branch above already follows.
	var is_counter := _target_is_attacking(target)
	if is_counter:
		final_damage *= COUNTER_DAMAGE_MULTIPLIER

	target.take_damage(final_damage, damage_type)
	if target.stance:
		target.stance.apply_attack_stance_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(_player, target, final_damage, damage_type, false, is_critical)
	if is_counter:
		EventBus.counter_hit.emit(_player, target)

	_trigger_hit_feedback(false)

## True if target's own melee or ranged attack component is mid-swing
## (Windup/Telegraph through Strike) - "mid attack animation" per the
## user's own wording, not just the instant its hitbox is live.
func _target_is_attacking(target: Enemy) -> bool:
	var melee: Node = target.get_node_or_null("MeleeAttack")
	if melee and melee.has_method("is_attacking") and melee.is_attacking():
		return true
	var ranged: Node = target.get_node_or_null("RangedAttack")
	return ranged != null and ranged.has_method("is_attacking") and ranged.is_attacking()

func _trigger_hit_feedback(big: bool = false) -> void:
	Engine.time_scale = hitstop_time_scale * 0.5 if big else hitstop_time_scale
	var duration := hitstop_duration * 3.0 if big else hitstop_duration
	get_tree().create_timer(duration, true, false, true).timeout.connect(_end_hitstop)

	var camera := _player.camera
	if camera == null:
		return
	var base_pos: Vector3 = camera.position
	var strength := shake_strength * 3.0 if big else shake_strength
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * strength
	var tween := create_tween()
	tween.tween_property(camera, "position", base_pos + offset, shake_duration * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(camera, "position", base_pos, shake_duration * 0.7).set_trans(Tween.TRANS_SINE)

func _end_hitstop() -> void:
	Engine.time_scale = 1.0
