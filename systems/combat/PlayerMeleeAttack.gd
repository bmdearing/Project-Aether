extends Node
class_name PlayerMeleeAttack
## Player-driven melee attack: Idle -> Windup -> Strike -> Recovery.
## Hit detection is a real Area3D (Player.attack_hitbox, sweeps with the
## blade mesh) - body_entered against the "enemy" group. Swing is a
## procedural Tween driving PlayerArmRig's bone poses (see _play_swing());
## camera shake is a separate procedural Tween on camera.position. Neither
## is baked Animation data. try_charged_thrust() (driven by WeaponStance's
## right-click hold, 2026-08-30) is the same state machine with a bigger,
## weapon-specific pose/motion-value/duration - see WEAPON_TYPE_SPECIAL_POSE.
##
## Implementation Brief v3.3 Section 2/5 (2026-08-31): three distinct
## attack types, dispatched by Player.gd off LMB hold duration - light jab
## (tap, <0.6s hold), standard thrust (hold >=0.6s then release), and
## charged thrust (stance + LMB press - unchanged from the pre-brief
## "special attack," just renamed to match the brief's own terminology;
## `_is_special`/SPECIAL_* naming below still says "special" in a few
## internal spots rather than "charged," left as-is to keep this merge
## smaller). Per user direction merging this brief into the existing
## architecture: the old NORMAL_COMBO_POSES/WEAPON_TYPE_COMBO_POSES combo-
## index cycling (repeated presses rotating through a weapon's pose list)
## is REMOVED - the brief explicitly doesn't want a combo system. Each
## weapon's former combo list is repurposed as a fixed per-ATTACK-TYPE
## pose instead (index 0 -> jab, index 1 or wraparound -> thrust) so the
## per-weapon pose variety already authored survives, it just no longer
## cycles. Per-weapon MOTION VALUE/duration/intensity tables (WEAPON_TYPE_
## MOTION_VALUE etc.) are preserved unchanged, per user direction - the
## brief's own 0.6/1.0/1.8 jab/thrust/charged values are applied as
## MULTIPLIERS on top of that per-weapon base, not a replacement of it.

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

## Per-weapon light-jab / standard-thrust poses (Implementation Brief
## v3.3 Section 2, merged 2026-08-31) - each weapon's former 2-pose combo
## list (see git history / PATCH_NOTES.md for that saga) is repurposed
## here as a fixed jab pose (was combo index 0) and thrust pose (was
## combo index 1, or the same pose again for weapons that only ever had
## one - Rapier/Gauntlet). No cycling anymore: the SAME attack type always
## plays the SAME pose for a given weapon, distinguished by ATTACK TYPE
## (jab vs thrust) rather than by an incrementing combo counter.
const WEAPON_TYPE_JAB_POSE := {
	"Greatsword": PlayerArmRig.PoseSet.SWEEP_RIGHT,
	"Staff": PlayerArmRig.PoseSet.TWIRL_RIGHT,
	"Rapier": PlayerArmRig.PoseSet.DASH_THRUST,
	"Dagger": PlayerArmRig.PoseSet.CLEAVE,
	"Gauntlet": PlayerArmRig.PoseSet.JAB,
}
const WEAPON_TYPE_THRUST_POSE := {
	"Greatsword": PlayerArmRig.PoseSet.SWEEP_LEFT,
	"Staff": PlayerArmRig.PoseSet.TWIRL_LEFT,
	"Rapier": PlayerArmRig.PoseSet.DASH_THRUST,
	"Dagger": PlayerArmRig.PoseSet.DASH_THRUST,
	"Gauntlet": PlayerArmRig.PoseSet.JAB,
}
## Default jab/thrust poses for a weapon type with no entry above -
## CLEAVE (a generic slash) for jab, SWEEP_RIGHT for thrust, same
## fallback shape the old NORMAL_COMBO_POSES default used to provide.
const DEFAULT_JAB_POSE := PlayerArmRig.PoseSet.CLEAVE
const DEFAULT_THRUST_POSE := PlayerArmRig.PoseSet.SWEEP_RIGHT

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
## input - Player.gd calls try_charged_thrust() on a left-click while active.
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

## Implementation Brief v3.3 Section 2: light jab (motion value x0.6,
## quicker swing) and standard thrust (x1.0 - a no-op, i.e. identical
## timing/power to what a plain attack always did) - multipliers on top
## of the existing per-weapon WEAPON_TYPE_MOTION_VALUE base, same pattern
## SPECIAL_MOTION_VALUE_MULTIPLIER (1.8, "charged thrust" in the brief's
## terms) already established for the stance special.
const JAB_MOTION_VALUE_MULTIPLIER := 0.6
const THRUST_MOTION_VALUE_MULTIPLIER := 1.0
const JAB_DURATION_MULTIPLIER := 0.6

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

## Implementation Brief v3.3 Section 2 - replaces the old boolean
## _is_special (special vs. not) now that there are 3 distinct attack
## types instead of 2. "SPECIAL" naming below (WEAPON_TYPE_SPECIAL_POSE,
## SPECIAL_MOTION_VALUE_MULTIPLIER, etc.) predates the brief and still
## means CHARGED - not renamed everywhere to keep this merge smaller.
enum AttackType { JAB, THRUST, CHARGED }

var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Player
var _hitbox: Area3D
var _resolved_this_swing: bool = false
var _attack_type: AttackType = AttackType.THRUST

func _ready() -> void:
	_player = get_parent()

func is_idle() -> bool:
	return _state == State.IDLE

func get_move_speed_multiplier() -> float:
	return ATTACKING_MOVE_SPEED_MULTIPLIER if _state != State.IDLE else 1.0

## Implementation Brief v3.3 Section 2 - LMB tap (Player.gd's hold-time
## tracking releases under 0.6s), motion value x0.6, a quicker swing.
func try_light_jab() -> void:
	if _state != State.IDLE:
		return
	if _player.get_active_weapon() == null:
		return
	_ensure_hitbox_connected()
	_attack_type = AttackType.JAB
	_enter_windup()

## Implementation Brief v3.3 Section 2 - LMB held >=0.6s then released,
## motion value x1.0 (identical power/timing to what the old single
## try_attack() always did - this is that same attack, just under its new
## brief-given name now that jab exists as a separate, faster option).
func try_standard_thrust() -> void:
	if _state != State.IDLE:
		return
	if _player.get_active_weapon() == null:
		return
	_ensure_hitbox_connected()
	_attack_type = AttackType.THRUST
	_enter_windup()

## Called from Player._physics_process when WeaponStance.is_active and LMB
## is pressed (Implementation Brief v3.3 Section 2's "charged thrust" -
## renamed from the pre-brief try_special_attack(), same mechanic: the
## weapon's special per WEAPON_TYPE_SPECIAL_POSE, falls back to a boosted
## CLEAVE for anything unmapped, same minimal-table-plus-DEFAULT
## convention as the rest of this file). Dagger's charged thrust also
## fires a real forward dash before the thrust - see Player.
## try_special_dash() - best-effort: if the dash is on its own cooldown
## (shared with the Shift-dash, deliberately not a separate free dash
## resource) the thrust still lands, just without the lunge.
func try_charged_thrust() -> void:
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
	_attack_type = AttackType.CHARGED
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
				_attack_type = AttackType.THRUST

## Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the
## base duration rather than mutating windup_duration/etc. directly.
## Also applies WEAPON_TYPE_SWING_DURATION_MULT so windup/strike/recovery
## timers and PlayerArmRig's tween durations (_play_swing() passes these
## same effective values) stay perfectly in sync regardless of weapon.
func _effective_duration(base: float) -> float:
	var weapon := _player.get_active_weapon()
	var swing_mult: float = WEAPON_TYPE_SWING_DURATION_MULT.get(weapon.weapon_type, 1.0) if weapon else 1.0
	match _attack_type:
		AttackType.JAB:
			swing_mult *= JAB_DURATION_MULTIPLIER
		AttackType.CHARGED:
			swing_mult *= SPECIAL_DURATION_MULTIPLIER
		AttackType.THRUST:
			pass  # x1.0 - identical timing to the old, only attack type this project had before this brief
	return base * swing_mult / _player.get_action_speed_multiplier()

func _effective_swing_intensity() -> float:
	var weapon := _player.get_active_weapon()
	return WEAPON_TYPE_SWING_INTENSITY.get(weapon.weapon_type, 1.0) if weapon else 1.0

func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = _effective_duration(windup_duration)
	_play_swing()
	_play_swing_sound()

## Weapon types by swing sound family. Anything unlisted (staves, casting
## foci) stays silent rather than borrowing a mismatched sound.
const SWING_BLADE_TYPES := ["Greatsword", "Claymore", "Rapier", "Dagger", "Saber", "Cutlass", "Shortsword", "Whip"]
const SWING_BLUNT_TYPES := ["Mace", "War Pick", "Pressure Fist", "Gauntlet"]
const SWING_PIERCE_TYPES := ["Spear", "Halberd", "Shock Lance"]

func _play_swing_sound() -> void:
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return
	var snd: AudioStream
	if SWING_BLADE_TYPES.has(weapon.weapon_type):
		snd = SoundLib.pick_random(SoundLib.library.swing_blade)
	elif SWING_BLUNT_TYPES.has(weapon.weapon_type):
		snd = SoundLib.pick_random(SoundLib.library.swing_blunt)
	elif SWING_PIERCE_TYPES.has(weapon.weapon_type):
		snd = SoundLib.pick_random(SoundLib.library.swing_pierce)
	AudioManager.play_at(snd, _player.global_position)

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
## extension right as Strike begins and the hitbox turns on). Pose is
## chosen purely by attack type now (Implementation Brief v3.3 Section 2,
## merged 2026-08-31) - jab and thrust each play a fixed per-weapon pose
## (WEAPON_TYPE_JAB_POSE/WEAPON_TYPE_THRUST_POSE), charged plays its
## weapon's dedicated special pose (get_special_pose_set()). No more
## combo-index cycling - the brief explicitly doesn't want a combo system.
func _play_swing() -> void:
	var rig := _player.arm_rig
	if rig == null:
		return
	var pose_set: PlayerArmRig.PoseSet
	var intensity: float
	var weapon := _player.get_active_weapon()
	match _attack_type:
		AttackType.CHARGED:
			pose_set = get_special_pose_set()
			intensity = get_special_intensity()
		AttackType.JAB:
			pose_set = WEAPON_TYPE_JAB_POSE.get(weapon.weapon_type, DEFAULT_JAB_POSE) if weapon else DEFAULT_JAB_POSE
			intensity = _effective_swing_intensity()
		AttackType.THRUST:
			pose_set = WEAPON_TYPE_THRUST_POSE.get(weapon.weapon_type, DEFAULT_THRUST_POSE) if weapon else DEFAULT_THRUST_POSE
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

## Implementation Brief v3.3 Section 2's jab/thrust/charged motion values
## (0.6/1.0/1.8) as multipliers on the per-weapon base above - see this
## file's own header for why they're multipliers, not a replacement.
func _attack_type_motion_multiplier() -> float:
	match _attack_type:
		AttackType.JAB:
			return JAB_MOTION_VALUE_MULTIPLIER
		AttackType.CHARGED:
			return SPECIAL_MOTION_VALUE_MULTIPLIER
		_:
			return THRUST_MOTION_VALUE_MULTIPLIER

func _deal_damage(target: Enemy) -> void:
	var weapon: Weapon = _player.get_active_weapon()
	var damage_type: Constants.DamageType = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
	var motion_value := _effective_motion_value(weapon) * _attack_type_motion_multiplier()

	# A melee hit on an already-broken enemy is a Riposte, not a normal
	# swing - big bonus damage + a moment of player invulnerability,
	# handled entirely by ParryRiposteHandler.
	if _player.parry_handler and _player.parry_handler.can_riposte(target):
		var riposte_is_critical_spot := target.is_critical_spot_hit(_hitbox)
		_player.parry_handler.execute_riposte(target, weapon, motion_value, damage_type)
		_trigger_hit_feedback(true)
		EventBus.hit_landed.emit(true, riposte_is_critical_spot, not target.health.is_alive())
		return

	var hit := weapon.roll_damage(motion_value, _player.stat_sheet)
	var final_damage: float = hit["final_damage"]
	var is_critical: bool = hit["is_critical"]

	# Implementation Brief v3.4 Section 3 - the weapon's own hitbox is
	# whichever Area3D is currently resolving this hit (_hitbox), checked
	# against the target's HeadZone for overlap - see Enemy.
	# is_critical_spot_hit()'s own header for why this replaces the
	# brief's hit_position-based check.
	var is_critical_spot := target.is_critical_spot_hit(_hitbox)
	if is_critical_spot:
		final_damage *= target.critical_spot_multiplier

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
	EventBus.melee_attack_executed.emit(_player, final_damage, damage_type, motion_value)
	EventBus.hit_landed.emit(is_critical, is_critical_spot, not target.health.is_alive())
	if is_counter:
		EventBus.counter_hit.emit(_player, target)
	_apply_water_slices(weapon, target, final_damage)

	_trigger_hit_feedback(false)

## Implementation Brief v3.4 Section 6's one fully-specified stance
## behavior (exact formula given, unlike every other stance in this
## file): Cutlass's WATER_SLICES page ("Gain As" - 40% of the hit's own
## damage dealt AGAIN as a separate Cold instance, original damage
## unchanged). Only while that stance page is actually active (RMB held,
## i.e. only ever during a charged thrust - jab/thrust can't coexist with
## stance being active, see Player._handle_attack_input()). The brief's
## own pseudocode says "Esoteric" in a comment but emits DamageType.COLD
## in the actual code - went with COLD (the code, and the thematically
## obvious read for "Water Slices" - water/ice fits Cold, not Esoteric).
## EventBus.damage_applied (the brief's own signal name) doesn't exist in
## this project - reused the existing damage_dealt signal instead, same
## as every other damage instance already announces itself.
const WATER_SLICES_COLD_BONUS_PERCENT := 0.40

func _apply_water_slices(weapon: Weapon, target: Enemy, original_damage: float) -> void:
	if weapon.weapon_type != "Cutlass" or not _player.weapon_stance.is_active:
		return
	var behavior := _player.weapon_stance.current_behavior
	if not (behavior is MeleeStanceBehavior) or behavior.stance_type != MeleeStanceBehavior.MeleeStanceType.WATER_SLICES:
		return
	var cold_bonus := original_damage * WATER_SLICES_COLD_BONUS_PERCENT
	target.take_damage(cold_bonus, Constants.DamageType.COLD)
	EventBus.damage_dealt.emit(_player, target, cold_bonus, Constants.DamageType.COLD, false, false)

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
