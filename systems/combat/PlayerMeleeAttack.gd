extends Node
class_name PlayerMeleeAttack
## Player-driven melee attack: Idle -> Windup -> Strike -> Recovery.
## Hit detection sweeps a per-weapon arc in front of the camera every
## Strike frame (SWING_SHAPES) and can hit several enemies per swing. The
## visible swing is PlayerArmRig.play_attack(), timed to these phases;
## camera shake is a separate procedural Tween on camera.position.
## try_charged_thrust() (WeaponStance right-click hold) is the same state
## machine with a bigger motion value/duration and the family's charged clip.
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
## is REMOVED - the brief explicitly doesn't want a combo system (v5.0
## brings back a three-hit chain at the user's request: COMBO_*). Each
## weapon's former combo list is repurposed as a fixed per-ATTACK-TYPE
## pose instead (index 0 -> jab, index 1 or wraparound -> thrust) so the
## per-weapon pose variety already authored survives, it just no longer
## cycles. Per-weapon MOTION VALUE/duration tables (WEAPON_TYPE_
## MOTION_VALUE etc.) are preserved unchanged, per user direction - the
## brief's own 0.6/1.0/1.6 jab/thrust/charged values are applied as
## MULTIPLIERS on top of that per-weapon base, not a replacement of it.

enum State { IDLE, WINDUP, STRIKE, RECOVERY }

## User feedback (2026-08-30): the original 0.1/0.12/0.15s swing (0.37s
## total) "was far too fast" even before any weapon-type scaling - bumped
## up across the board as the new no-weapon-match baseline, on top of
## which WEAPON_TYPE_SWING_DURATION_MULT below applies per weapon type.
## Combat feel pass (2026-10-07): longer anticipation and recovery around a
## short, fast strike - the contrast is what reads as punch.
## 2026-10-08: everything still hit too fast - about 15% slower again.
const BASE_WINDUP := 0.36
const BASE_STRIKE := 0.16
const BASE_RECOVERY := 0.40
@export var windup_duration: float = BASE_WINDUP
@export var strike_duration: float = BASE_STRIKE
@export var recovery_duration: float = BASE_RECOVERY
## Floors after every speed multiplier, so fast weapons + attack speed can't
## blur a swing into a flicker.
const MIN_WINDUP := 0.22
const MIN_STRIKE := 0.1
const MIN_RECOVERY := 0.27
## Hits register only from this fraction of Strike onward, when the blade is
## actually crossing the screen (the strike tween eases in).
const STRIKE_CONTACT_START := 0.6
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
## v4.51: every melee type tuned so sustained DPS (hit / swing time, see
## tests/balance/probe_dps.tscn) lands near 150 for one-handers, 155 for
## blunt/polearm one-handers and 165 for two-handers, which also cleave.
## v4.72b: all x1.45, then x1.3 (about 283 / 292 / 312) so weapons keep up with spells.
## Slow weapons get the biggest hits.
const WEAPON_TYPE_MOTION_VALUE := {
	"Dagger": 2.04, "Rapier": 1.62, "Saber": 1.89, "Shortsword": 1.94, "Cutlass": 2.30,
	"Pressure Fist": 2.38, "Mace": 2.26, "Spear": 2.30, "War Pick": 3.11, "Whip": 3.02,
	"Shock Lance": 3.55, "Halberd": 3.09, "Greataxe": 3.77, "Greatsword": 3.77, "Claymore": 4.02,
	"Staff": 1.89, "Gauntlet": 0.94,
}

## Per-weapon swing duration multiplier (via _effective_duration()), so a
## Greatsword swing genuinely takes longer than a Dagger's.
## 2026-10-07: light weapons were too quick to read - Dagger/Rapier/Gauntlet raised.
## 2026-10-08: every melee and conduit type has an entry (most used to fall
## back to 1.0, so a Halberd swung as fast as a Rapier). Two-handers are slowest.
## v5.0.3: the heavy two-handers (Shock Lance and up) swing 20% faster.
const WEAPON_TYPE_SWING_DURATION_MULT := {
	"Rapier": 0.95, "Dagger": 1.0, "Athame": 1.0, "Gauntlet": 0.9, "Spell Gauntlet": 0.95,
	"Shortsword": 1.1, "Pressure Fist": 1.1, "Saber": 1.15, "Cutlass": 1.15,
	"Fetish": 1.2, "Talisman": 1.2, "Rod": 1.25, "Tome": 1.3, "Grimoire": 1.3, "Whip": 1.3,
	"Spear": 1.35, "Staff": 1.4, "Mace": 1.45, "War Pick": 1.5, "Shock Lance": 1.6 / 1.2,
	"Halberd": 1.8 / 1.2, "Claymore": 2.2 / 1.2, "Greataxe": 2.3 / 1.2, "Greatsword": 2.4 / 1.2,
}

## Seconds for one plain swing (windup + strike + recovery) before attack
## speed, for the item card.
static func swing_seconds(weapon_type: String) -> float:
	return (BASE_WINDUP + BASE_STRIKE + BASE_RECOVERY) * WEAPON_TYPE_SWING_DURATION_MULT.get(weapon_type, 1.0)
const SPECIAL_MOTION_VALUE_MULTIPLIER := 1.6
const SPECIAL_DURATION_MULTIPLIER := 1.4

## Implementation Brief v3.3 Section 2: light jab (motion value x0.6,
## quicker swing) and standard thrust (x1.0 - a no-op, i.e. identical
## timing/power to what a plain attack always did) - multipliers on top
## of the existing per-weapon WEAPON_TYPE_MOTION_VALUE base, same pattern
## SPECIAL_MOTION_VALUE_MULTIPLIER (1.6, "charged thrust" in the brief's
## terms) already established for the stance special.
const JAB_MOTION_VALUE_MULTIPLIER := 0.6
const THRUST_MOTION_VALUE_MULTIPLIER := 1.0
const JAB_DURATION_MULTIPLIER := 0.6

@export var hitstop_time_scale: float = 0.05
@export var hitstop_duration: float = 0.07
@export var shake_strength: float = 0.04
@export var shake_duration: float = 0.15

## Impact scales with swing weight (see _swing_weight()).
const HITSTOP_CRIT_MULT := 1.3
const HITSTOP_KILL_MULT := 2.0
const SWING_KICK := 0.012          # radians of camera lean on every strike, hit or miss
const HIT_KICK_PITCH := 0.03       # downward camera dip on a landed hit
const HIT_KICK_YAW := 0.025
const KNOCKBACK_PER_WEIGHT := 2.6  # m/s of shove per unit of swing weight
const LUNGE_PER_WEIGHT := 1.4      # m/s forward step into the strike
const KILL_SHOVE := 6.0            # m/s the killing blow throws the body
## Aim assist: a strike turns you up to ASSIST_MAX_DEG toward the nearest
## enemy within ASSIST_CONE_DEG of the crosshair and reach + ASSIST_EXTRA_REACH.
const ASSIST_CONE_DEG := 25.0
const ASSIST_MAX_DEG := 12.0
const ASSIST_EXTRA_REACH := 0.8

## User request (2026-08-30): "Movement speed should be reduced when
## attacking with a melee weapon." Applies for the whole swing (Windup
## through Recovery, not just the Strike instant), matching Section 07's
## melee-weight framing of a swing as one committed action rather than an
## instant tap - Player._effective_speed() reads this every physics frame.
const ATTACKING_MOVE_SPEED_MULTIPLIER := 0.5

## User request (2026-08-30): "deal Counter damage and deal 15% more
## damage" - exact rate given, not invented.
const COUNTER_DAMAGE_MULTIPLIER := 1.15

## v5.0 (user request): jabs and thrusts chain into a three-hit combo. Hit 2
## swings back the other way, hit 3 is the weapon's finisher (its charged
## clip, a longer wind-up, COMBO_FINISHER_DAMAGE). Pressing attack during
## recovery queues the next hit; COMBO_WINDOW idle seconds reset the chain.
const COMBO_HITS := 3
const COMBO_WINDOW := 0.5
const COMBO_FINISHER_DAMAGE := 1.1
const COMBO_FINISHER_WINDUP := 1.2
## Dual-wielded melee: four hits, left-right-left, then both blades at once.
const DUAL_COMBO_HITS := 4
enum Strike { MAIN, OFF, BOTH }
const DUAL_COMBO_HANDS: Array[int] = [Strike.MAIN, Strike.OFF, Strike.MAIN, Strike.BOTH]
var _strike_hands: int = Strike.MAIN

## Implementation Brief v3.3 Section 2 - replaces the old boolean
## _is_special (special vs. not) now that there are 3 distinct attack
## types instead of 2. "SPECIAL" naming below
## SPECIAL_MOTION_VALUE_MULTIPLIER, etc.) predates the brief and still
## means CHARGED - not renamed everywhere to keep this merge smaller.
enum AttackType { JAB, THRUST, CHARGED }

var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Player
var _hitbox: Area3D
var _attack_type: AttackType = AttackType.THRUST
## instance id -> true for every enemy this swing already hit.
var _hit_this_swing: Dictionary = {}
var _strike_total: float = 0.0
var _swing_side: bool = false
var _active_hitstops: int = 0
## Which hit of the combo the current swing is (0-2).
var _combo_step: int = 0
var _combo_idle: float = INF
var _queued_attack: int = -1
## One charged stance release in progress (see release_stance_attack()):
## kind (PlayerArmRig.Attack clip), windup, motion_mult, recovery_mult, damage_type, plus
## optional shape (hit sweep override), on_contact (resolves the hit itself
## at Strike instead of sweeping) and on_hit(enemy, damage).
var _stance_release: Dictionary = {}

## Swing hit volume per weapon family: reach (m from the camera), half-angle
## of the horizontal arc, damage share for every target after the first, and
## a target cap. Thrusts reach far in a narrow line; heavy weapons cleave.
const SWING_SHAPES := {
	"thrust": {"reach": 3.2, "half_angle": 18.0, "splash": 0.5, "max_targets": 3},
	"slash": {"reach": 2.7, "half_angle": 50.0, "splash": 0.6, "max_targets": 4},
	# v4.72: two-handers sweep wider and harder so they hold their own against area spells.
	"heavy": {"reach": 3.6, "half_angle": 85.0, "splash": 0.9, "max_targets": 8},
	"whip": {"reach": 4.2, "half_angle": 30.0, "splash": 0.5, "max_targets": 3},
	"fist": {"reach": 2.1, "half_angle": 30.0, "splash": 0.4, "max_targets": 2},
}
const WEAPON_SWING_FAMILY := {
	"Dagger": "thrust", "Rapier": "thrust", "Spear": "thrust", "Shock Lance": "thrust",
	"Shortsword": "slash", "Saber": "slash", "Cutlass": "slash",
	"Claymore": "heavy", "Greataxe": "heavy", "Greatsword": "heavy", "Halberd": "heavy", "Mace": "heavy", "War Pick": "heavy", "Staff": "heavy",
	"Whip": "whip",
	"Pressure Fist": "fist", "Gauntlet": "fist",
}
const DEFAULT_SWING_FAMILY := "slash"
const CHARGED_REACH_BONUS := 0.6
const CHARGED_ANGLE_BONUS := 15.0
const CHARGED_SPLASH := 1.0
const SWING_VERTICAL_HALF_ANGLE := 50.0
const ENEMY_BODY_RADIUS := 0.5
const ENEMY_AIM_HEIGHT := 1.0

func _ready() -> void:
	_player = get_parent()

func is_idle() -> bool:
	return _state == State.IDLE

func get_move_speed_multiplier() -> float:
	return ATTACKING_MOVE_SPEED_MULTIPLIER if _state != State.IDLE else 1.0

## Implementation Brief v3.3 Section 2 - LMB tap (Player.gd's hold-time
## tracking releases under 0.6s), motion value x0.6, a quicker swing.
func try_light_jab() -> void:
	_try_combo_attack(AttackType.JAB)

## Implementation Brief v3.3 Section 2 - LMB held >=0.6s then released,
## motion value x1.0 (identical power/timing to what the old single
## try_attack() always did - this is that same attack, just under its new
## brief-given name now that jab exists as a separate, faster option).
func try_standard_thrust() -> void:
	_try_combo_attack(AttackType.THRUST)

func _try_combo_attack(type: AttackType) -> void:
	if _state == State.RECOVERY and _stance_release.is_empty():
		_queued_attack = type
		return
	if _state != State.IDLE or _player.get_active_weapon() == null:
		return
	_combo_step = (_combo_step + 1) % _combo_hits() if _combo_idle <= COMBO_WINDOW else 0
	_strike_hands = DUAL_COMBO_HANDS[_combo_step] if _player.dual_wield_kind() == "melee" else Strike.MAIN
	_ensure_hitbox_connected()
	_attack_type = type
	_enter_windup()

func _combo_hits() -> int:
	return DUAL_COMBO_HITS if _player.dual_wield_kind() == "melee" else COMBO_HITS

## Which hand(s) the current swing uses (Strike).
func get_strike_hands() -> int:
	return _strike_hands

## Mixed pair with a gun in the main hand: the Offhand Attack key swings the
## offhand blade.
func try_offhand_swing() -> void:
	if _state != State.IDLE or _player.get_offhand_weapon() == null:
		return
	_ensure_hitbox_connected()
	_attack_type = AttackType.THRUST
	_combo_idle = INF
	_combo_step = 0
	_strike_hands = Strike.OFF
	_enter_windup()

func is_combo_finisher() -> bool:
	return _combo_step == _combo_hits() - 1 and _attack_type != AttackType.CHARGED and _stance_release.is_empty()

## Called from Player._physics_process when WeaponStance.is_active and LMB
## is pressed (Implementation Brief v3.3 Section 2's "charged thrust" -
## renamed from the pre-brief try_special_attack(), same mechanic: the
## weapon family's charged clip on PlayerArmRig). Dagger's charged thrust also
## fires a real forward dash before the thrust - see Player.
## try_special_dash() - best-effort: if the dash is on its own cooldown
## (shared with the Shift-dash, deliberately not a separate free dash
## resource) the thrust still lands, just without the lunge.
func try_charged_thrust() -> void:
	if _state != State.IDLE:
		return
	var weapon := _player.get_attack_weapon()
	if weapon == null:
		return
	if weapon.weapon_type == "Dagger":
		var forward := -_player.camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.01:
			_player.try_special_dash(forward.normalized())
	_strike_hands = Strike.MAIN
	_ensure_hitbox_connected()
	_attack_type = AttackType.CHARGED
	_combo_idle = INF
	_enter_windup()

## The blade's own Area3D is only used for the headshot check now; swing
## hits come from _sweep_strike().
func _ensure_hitbox_connected() -> void:
	if _hitbox != null:
		return
	_hitbox = _player.attack_hitbox
	if _hitbox:
		_hitbox.monitoring = false

func _physics_process(delta: float) -> void:
	match _state:
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_enter_strike()
		State.STRIKE:
			_timer -= delta
			if _timer <= _strike_total * (1.0 - STRIKE_CONTACT_START) and not _stance_release.has("on_contact"):
				_sweep_strike()
			if _timer <= 0.0:
				_end_strike()
		State.RECOVERY:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.IDLE
				_player.attack_hand = Player.Hand.MAIN
				_combo_idle = 0.0 if _attack_type != AttackType.CHARGED and _stance_release.is_empty() else INF
				_attack_type = AttackType.THRUST
				_stance_release = {}
				if _queued_attack >= 0:
					var queued := _queued_attack as AttackType
					_queued_attack = -1
					_try_combo_attack(queued)
		State.IDLE:
			_combo_idle += delta

## Plays a charged stance attack (StanceAttack's release). The arm is
## already wound up from the charge, so the windup is short.
func release_stance_attack(params: Dictionary) -> void:
	if _state != State.IDLE or _player.get_active_weapon() == null:
		return
	_ensure_hitbox_connected()
	_attack_type = AttackType.CHARGED
	_stance_release = params
	_strike_hands = params.get("hands", Strike.MAIN)
	_enter_windup()

## Every live enemy within `radius` of `center` with a clear line from it.
func enemies_in_radius(center: Vector3, radius: float) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var flat := enemy.global_position - center
		flat.y = 0.0
		if flat.length() - ENEMY_BODY_RADIUS > radius:
			continue
		if _has_line_of_sight(center + Vector3.UP * 0.5, enemy.global_position + Vector3(0, ENEMY_AIM_HEIGHT, 0), enemy):
			found.append(enemy)
	return found

## One hit outside any swing (Halberd Brace), with its own motion value and type.
func deal_stance_damage(target: Enemy, motion_mult: float, damage_type: Constants.DamageType) -> void:
	var saved_release := _stance_release
	var saved_type := _attack_type
	_stance_release = {"motion_mult": motion_mult, "damage_type": damage_type}
	_attack_type = AttackType.CHARGED
	_deal_damage(target, 1.0, true)
	_stance_release = saved_release
	_attack_type = saved_type

## Deals the current swing's damage to each target; the first is primary.
func hit_targets(targets: Array[Enemy]) -> void:
	for i in targets.size():
		_deal_damage(targets[i], 1.0, i == 0)

## Section 12: Instinct -> "+1% Attack/Cast speed per point" divides the
## base duration rather than mutating windup_duration/etc. directly.
## Also applies WEAPON_TYPE_SWING_DURATION_MULT so windup/strike/recovery
## timers and PlayerArmRig's tween durations (_play_swing() passes these
## same effective values) stay perfectly in sync regardless of weapon.
func _effective_duration(base: float, minimum: float = 0.0) -> float:
	var weapon := _player.get_attack_weapon()
	var swing_mult: float = WEAPON_TYPE_SWING_DURATION_MULT.get(weapon.weapon_type, 1.0) if weapon else 1.0
	match _attack_type:
		AttackType.JAB:
			swing_mult *= JAB_DURATION_MULTIPLIER
		AttackType.CHARGED:
			swing_mult *= SPECIAL_DURATION_MULTIPLIER
		AttackType.THRUST:
			pass  # x1.0 - identical timing to the old, only attack type this project had before this brief
	return maxf(base * swing_mult / _player.get_attack_speed_multiplier(), minimum)

## Felt heaviness of the current swing: drives hitstop, knockback, lunge, kick.
func _swing_weight() -> float:
	var weapon := _player.get_attack_weapon()
	var weight: float = clampf(WEAPON_TYPE_SWING_DURATION_MULT.get(weapon.weapon_type, 1.0) if weapon else 1.0, 0.85, 1.8)
	match _attack_type:
		AttackType.JAB:
			weight *= 0.8
		AttackType.CHARGED:
			weight *= 1.4
	if is_combo_finisher():
		weight *= 1.25
	return weight

func _windup_time() -> float:
	if _stance_release.has("windup"):
		return _stance_release["windup"]
	return _effective_duration(windup_duration, MIN_WINDUP) * (COMBO_FINISHER_WINDUP if is_combo_finisher() else 1.0)

func _strike_time() -> float:
	if _stance_release.has("strike"):
		return _stance_release["strike"]
	return _effective_duration(strike_duration, MIN_STRIKE)

func _recovery_time() -> float:
	if _stance_release.has("recovery"):
		return _stance_release["recovery"]
	return _effective_duration(recovery_duration, MIN_RECOVERY) * _stance_release.get("recovery_mult", 1.0)

func _enter_windup() -> void:
	_state = State.WINDUP
	_player.attack_hand = Player.Hand.OFF if _strike_hands == Strike.OFF else Player.Hand.MAIN
	_swing_side = not _swing_side
	_timer = _windup_time()
	_play_swing()
	_play_swing_sound()

## Weapon types by swing sound family. Anything unlisted (staves, casting
## foci) stays silent rather than borrowing a mismatched sound.
const SWING_BLADE_TYPES := ["Greatsword", "Claymore", "Greataxe", "Rapier", "Dagger", "Saber", "Cutlass", "Shortsword", "Whip"]
const SWING_BLUNT_TYPES := ["Mace", "War Pick", "Pressure Fist", "Gauntlet"]
const SWING_PIERCE_TYPES := ["Spear", "Halberd", "Shock Lance"]

func _play_swing_sound() -> void:
	var weapon := _player.get_attack_weapon()
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
	_strike_total = _strike_time()
	_timer = _strike_total
	_hit_this_swing = {}
	if _hitbox:
		_hitbox.monitoring = true
	var weight := _swing_weight()
	_assist_aim()
	_kick_camera(Vector3(-0.5, _swing_yaw(), 0.0) * SWING_KICK * weight)
	var forward := -_player.camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() > 0.01 and not _stance_release.has("no_step"):
		_player.apply_impulse(forward.normalized() * LUNGE_PER_WEIGHT * weight)
	if _stance_release.has("on_contact"):
		(_stance_release["on_contact"] as Callable).call()
	if _player.ability_cast:
		_player.ability_cast.on_melee_swing()
	_strike_breakables()

## A swing that meets a CrackedWall within reach knocks at it.
func _strike_breakables() -> void:
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * float(get_swing_shape()["reach"]), 1)
	query.exclude = [_player.get_rid()]
	var wall := _player.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as CrackedWall
	if wall:
		wall.strike()

func _end_strike() -> void:
	if _hitbox:
		_hitbox.monitoring = false
	_enter_recovery()

func _enter_recovery() -> void:
	_state = State.RECOVERY
	_timer = _recovery_time()

## The viewmodel picks the clip for the weapon's family; these timings keep
## its strike pose landing exactly when the hit sweep turns on.
func _play_swing() -> void:
	var rig := _player.arm_rig
	if rig == null:
		return
	var kind: PlayerArmRig.Attack = PlayerArmRig.Attack.HEAVY
	match _attack_type:
		AttackType.JAB:
			kind = PlayerArmRig.Attack.LIGHT
		AttackType.CHARGED:
			kind = PlayerArmRig.Attack.CHARGED
	if is_combo_finisher():
		kind = PlayerArmRig.Attack.CHARGED
	var backswing := _combo_step == 1 and _stance_release.is_empty() and _attack_type != AttackType.CHARGED and _strike_hands == Strike.MAIN
	rig.play_attack(_stance_release.get("kind", kind), _windup_time(), _strike_time(), _recovery_time(), backswing, _strike_hands)

## Which way the camera leans on a strike: alternates, so successive swings rock side to side.
func _swing_yaw() -> float:
	return 1.0 if _swing_side else -1.0

func _kick_camera(amount: Vector3) -> void:
	var sway: CameraSway = _player.camera.get_node_or_null("CameraSway") if _player.camera else null
	if sway:
		sway.kick(amount)

func _assist_aim() -> void:
	var forward := -_player.global_transform.basis.z
	var reach: float = get_swing_shape()["reach"] + ASSIST_EXTRA_REACH
	var best: Enemy = null
	var best_angle := deg_to_rad(ASSIST_CONE_DEG)
	for e in enemies_in_radius(_player.global_position, reach):
		var to := e.global_position - _player.global_position
		to.y = 0.0
		var angle := absf(forward.signed_angle_to(to, Vector3.UP))
		if to.length() > 0.01 and angle < best_angle:
			best = e
			best_angle = angle
	if best == null:
		return
	var to_best := best.global_position - _player.global_position
	var turn := clampf(forward.signed_angle_to(Vector3(to_best.x, 0.0, to_best.z), Vector3.UP), -deg_to_rad(ASSIST_MAX_DEG), deg_to_rad(ASSIST_MAX_DEG))
	create_tween().tween_property(_player, "rotation:y", _player.rotation.y + turn, 0.06)

func get_swing_shape() -> Dictionary:
	var weapon := _player.get_attack_weapon()
	var family: String = WEAPON_SWING_FAMILY.get(weapon.weapon_type, DEFAULT_SWING_FAMILY) if weapon else DEFAULT_SWING_FAMILY
	if _stance_release.has("shape"):
		return _stance_release["shape"]
	var shape: Dictionary = SWING_SHAPES[family].duplicate()
	if _attack_type == AttackType.CHARGED:
		shape["reach"] += CHARGED_REACH_BONUS
		shape["half_angle"] += CHARGED_ANGLE_BONUS
		shape["splash"] = CHARGED_SPLASH
		shape["max_targets"] += 2
	return shape

## Every physics frame of Strike: enemies inside the weapon's arc, in clear
## line of sight, not yet hit this swing. The one nearest the crosshair is
## the primary target; the rest take the splash share.
func _sweep_strike() -> void:
	var shape := get_swing_shape()
	if _hit_this_swing.size() >= int(shape["max_targets"]):
		return
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or _hit_this_swing.has(enemy.get_instance_id()) or not enemy.health.is_alive():
			continue
		var aim_point := enemy.global_position + Vector3(0, ENEMY_AIM_HEIGHT, 0)
		var to_enemy := aim_point - origin
		var flat := Vector3(to_enemy.x, 0.0, to_enemy.z)
		if flat.length() - ENEMY_BODY_RADIUS > float(shape["reach"]):
			continue
		var yaw_angle := rad_to_deg(flat_forward.angle_to(flat.normalized())) if flat.length() > 0.05 else 0.0
		# Up close the body fills more of the view, so widen the arc by its radius.
		var radius_slack := rad_to_deg(atan2(ENEMY_BODY_RADIUS, maxf(flat.length(), 0.1)))
		if yaw_angle > float(shape["half_angle"]) + radius_slack:
			continue
		var pitch := rad_to_deg(atan2(to_enemy.y, maxf(flat.length(), 0.1)))
		if absf(pitch) > SWING_VERTICAL_HALF_ANGLE + radius_slack:
			continue
		if not _has_line_of_sight(origin, aim_point, enemy):
			continue
		candidates.append({"enemy": enemy, "angle": yaw_angle})
	candidates.sort_custom(func(a, b): return a["angle"] < b["angle"])
	for entry in candidates:
		if _hit_this_swing.size() >= int(shape["max_targets"]):
			break
		var is_primary := _hit_this_swing.is_empty()
		_hit_this_swing[entry["enemy"].get_instance_id()] = true
		_deal_damage(entry["enemy"], 1.0 if is_primary else float(shape["splash"]), is_primary)

func _has_line_of_sight(from: Vector3, to: Vector3, target: Enemy) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [_player.get_rid(), target.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or not (hit["collider"] is StaticBody3D)

func _effective_motion_value(weapon: Weapon) -> float:
	return WEAPON_TYPE_MOTION_VALUE.get(weapon.weapon_type, base_motion_value)

## Implementation Brief v3.3 Section 2's jab/thrust/charged motion values
## (0.6/1.0/1.6) as multipliers on the per-weapon base above - see this
## file's own header for why they're multipliers, not a replacement.
func _attack_type_motion_multiplier() -> float:
	match _attack_type:
		AttackType.JAB:
			return JAB_MOTION_VALUE_MULTIPLIER
		AttackType.CHARGED:
			return _stance_release.get("motion_mult", SPECIAL_MOTION_VALUE_MULTIPLIER)
		_:
			return THRUST_MOTION_VALUE_MULTIPLIER

## Both-blade strikes (the dual combo finisher, Flurry's cross-cut) hit once
## with each weapon.
func _deal_damage(target: Enemy, damage_scale: float = 1.0, is_primary: bool = true) -> void:
	_deal_damage_once(target, damage_scale, is_primary)
	if _strike_hands == Strike.BOTH and _player.is_dual_wielding() and is_instance_valid(target) and target.health.is_alive() and not _player.is_in_visceral():
		_player.attack_hand = Player.Hand.OFF
		_deal_damage_once(target, damage_scale, false)
		_player.attack_hand = Player.Hand.MAIN

func _deal_damage_once(target: Enemy, damage_scale: float = 1.0, is_primary: bool = true) -> void:
	var weapon: Weapon = _player.get_attack_weapon()
	var damage_type := weapon.get_damage_type()
	damage_type = _stance_release.get("damage_type", damage_type)
	var motion_value := _effective_motion_value(weapon) * _attack_type_motion_multiplier()

	# A melee hit on an already-broken enemy is a Riposte, not a normal
	# swing - big bonus damage + a moment of player invulnerability,
	# handled entirely by ParryRiposteHandler.
	# A charged attack into the back of a rank-and-file enemy is a visceral too.
	var backstab := is_primary and _attack_type == AttackType.CHARGED and _stance_release.is_empty() \
		and target.is_rank_and_file() and target.is_behind(_player.global_position)
	if is_primary and _player.parry_handler and (_player.parry_handler.can_riposte(target) or backstab):
		_begin_visceral(target, weapon, motion_value, damage_type)
		return

	# Headshot: the crosshair is on the target's head. It always crits.
	var is_critical_spot := is_primary and target.is_critical_spot_aimed(_player.camera.global_position, -_player.camera.global_transform.basis.z)
	var hit := weapon.roll_damage(motion_value, _player.stat_sheet, is_critical_spot)
	var final_damage: float = hit["final_damage"] * damage_scale
	var is_critical: bool = hit["is_critical"]
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
	if is_combo_finisher():
		final_damage *= COMBO_FINISHER_DAMAGE

	if not target.take_damage(final_damage, damage_type, false, true, false, _stance_release.get("ignore_armor", false)):
		return  # dodged - no stance damage, riders, or hit feedback
	AudioManager.play_at(SoundLib.pick_random(SoundLib.library.hit_flesh), target.global_position, -2.0)
	BloodFx.hit(target, _blow_direction(target), _swing_weight() * damage_scale * (1.5 if is_critical or is_critical_spot else 1.0), not target.health.is_alive())
	if is_critical:
		AudioManager.play_at(SoundLib.pick_random(SoundLib.library.hit_critical), target.global_position, -4.0)
	if target.stance:
		target.stance.apply_attack_stance_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(_player, target, final_damage, damage_type, false, is_critical)
	target.status_effects.roll_gear_ailments(_player, final_damage, damage_type)
	if _player.gear_effects:
		_player.gear_effects.note_melee_hit()
	EventBus.melee_attack_executed.emit(_player, final_damage, damage_type, motion_value)
	EventBus.hit_landed.emit(is_critical, is_critical_spot, not target.health.is_alive())
	if is_counter:
		EventBus.counter_hit.emit(_player, target)
	if _stance_release.has("on_hit"):
		(_stance_release["on_hit"] as Callable).call(target, final_damage)

	_react_to_hit(target, damage_scale)
	if not target.health.is_alive():
		_shove_corpse(target, damage_scale)
	elif (is_combo_finisher() or _attack_type == AttackType.CHARGED) and target.is_rank_and_file():
		target.stagger()
	if is_primary:
		_trigger_hit_feedback(false, is_critical or is_critical_spot, not target.health.is_alive())

## Locks both into the visceral (Player.start_visceral()); the damage, blood
## and hit-stop land when the weapon rips out.
func _begin_visceral(target: Enemy, weapon: Weapon, motion_value: float, damage_type: Constants.DamageType) -> void:
	var dir := _blow_direction(target)
	_state = State.RECOVERY
	_timer = Player.VISCERAL_LOCK
	_queued_attack = -1
	if _hitbox:
		_hitbox.monitoring = false
	_player.start_visceral(target, func() -> void:
		if not is_instance_valid(target) or not target.health.is_alive():
			return
		_player.parry_handler.execute_riposte(target, weapon, motion_value, damage_type, true)
		# Crossguard: the offhand blade follows the main one in.
		if _two_blade_riposte() and target.health.is_alive():
			var off := _player.get_offhand_weapon()
			_player.parry_handler.execute_riposte(target, off, _effective_motion_value(off) * _attack_type_motion_multiplier(), off.get_damage_type(), true)
		var killed := not target.health.is_alive()
		BloodFx.visceral(target, dir)
		AudioManager.play_at(SoundLib.library.riposte, target.global_position)
		if killed:
			_shove_corpse(target, 1.5)
		else:
			target.interrupt_attack()  # reels from the rip-out
		_trigger_hit_feedback(true, false, killed)
		EventBus.hit_landed.emit(true, false, killed))

## Dual-wielding melee on the Crossguard page: ripostes strike with both blades.
func _two_blade_riposte() -> bool:
	if _player.dual_wield_kind() != "melee" or _player.weapon_stance.active_page != WeaponStance.StancePage.A:
		return false
	var b := StanceInfo.behavior_for(_player.get_active_weapon(), 0, true) as MeleeStanceBehavior
	return b != null and b.riposte_both_blades

func _shove_corpse(target: Enemy, scale: float) -> void:
	target.apply_knockback(_blow_direction(target) * KILL_SHOVE * clampf(scale, 0.5, 1.5) + Vector3.UP * 2.5)

## A dash cuts a swing's follow-through short.
func cancel_recovery() -> void:
	if _state == State.RECOVERY and not _player.is_in_visceral():
		_timer = 0.0
		_queued_attack = -1

func _blow_direction(target: Enemy) -> Vector3:
	var dir := target.global_position - _player.global_position
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.01 else -_player.global_transform.basis.z

func _react_to_hit(target: Enemy, scale: float) -> void:
	target.flash_hit()
	if _stance_release.has("no_push"):
		return
	var push := target.global_position - _player.global_position
	push.y = 0.0
	if push.length() > 0.01:
		target.apply_knockback(push.normalized() * KNOCKBACK_PER_WEIGHT * _swing_weight() * scale)

## True if target's own melee or ranged attack component is mid-swing
## (Windup/Telegraph through Strike) - "mid attack animation" per the
## user's own wording, not just the instant its hitbox is live.
func _target_is_attacking(target: Enemy) -> bool:
	var melee: Node = target.get_node_or_null("MeleeAttack")
	if melee and melee.has_method("is_attacking") and melee.is_attacking():
		return true
	var ranged: Node = target.get_node_or_null("RangedAttack")
	return ranged != null and ranged.has_method("is_attacking") and ranged.is_attacking()

func _trigger_hit_feedback(big: bool = false, critical: bool = false, killed: bool = false) -> void:
	var weight := _swing_weight()
	var duration := hitstop_duration * weight
	if critical:
		duration *= HITSTOP_CRIT_MULT
	if killed:
		duration *= HITSTOP_KILL_MULT
	if big:
		duration = hitstop_duration * 3.0
	Engine.time_scale = hitstop_time_scale * 0.5 if big else hitstop_time_scale
	_active_hitstops += 1
	get_tree().create_timer(duration, true, false, true).timeout.connect(_end_hitstop)

	_kick_camera(Vector3(-HIT_KICK_PITCH, _swing_yaw() * HIT_KICK_YAW, randf_range(-0.5, 0.5) * HIT_KICK_YAW) * weight * (2.0 if big else 1.0))

	var camera := _player.camera
	if camera == null:
		return
	var base_pos: Vector3 = camera.position
	var strength := shake_strength * (3.0 if big else weight)
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * strength
	var tween := create_tween()
	tween.tween_property(camera, "position", base_pos + offset, shake_duration * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(camera, "position", base_pos, shake_duration * 0.7).set_trans(Tween.TRANS_SINE)

## Overlapping hitstops (a kill right after a hit) end with the last one.
func _end_hitstop() -> void:
	_active_hitstops -= 1
	if _active_hitstops <= 0:
		_active_hitstops = 0
		Engine.time_scale = 1.0
