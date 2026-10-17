extends Node
class_name ParryRiposteHandler
## Parry -> Stance damage -> Composure Break -> Riposte. Attach to the Player.
##
## EnemyMeleeAttack calls attempt_parry() when a swing resolves.
## PlayerMeleeAttack triggers a riposte on any melee hit against a broken
## enemy, however it was broken.
##
## A parry runs startup -> active window -> recovery. Only the active window
## catches hits; a whiffed parry plays out its recovery before you can parry
## or attack again, so it can't be spammed. A successful one cancels the
## recovery, so a combo can be parried blow by blow and riposted at once.

## Before the blade is in place: a press at the moment of contact is too late.
const PARRY_STARTUP := 0.05
## Stances and gear widen this, never the startup or recovery.
@export var parry_window_seconds: float = 0.18
const WHIFF_RECOVERY := 0.35
@export var parry_stance_damage: float = 25.0
## On top of the swing's motion value. The broken-state damage bonus also
## applies, since the break ends after the hit. Never evadable.
const RIPOSTE_MOTION_VALUE_MULTIPLIER := 1.4
@export var riposte_invuln_duration: float = 1.0
const SUCCESS_HITSTOP := 0.06

enum Phase { IDLE, STARTUP, ACTIVE, RECOVERY }

var is_invulnerable: bool = false
var phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _active_length: float = 0.0
var _invuln_timer: float = 0.0

func _process(delta: float) -> void:
	if phase != Phase.IDLE:
		_phase_timer -= delta
		while phase != Phase.IDLE and _phase_timer <= 0.0:
			match phase:
				Phase.STARTUP:
					phase = Phase.ACTIVE
					_phase_timer += _active_length
				Phase.ACTIVE:
					phase = Phase.RECOVERY
					_phase_timer += WHIFF_RECOVERY
				_:
					phase = Phase.IDLE
	if is_invulnerable:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			is_invulnerable = false

## Startup, active or recovery: the parry owns the hands.
func is_busy() -> bool:
	return phase != Phase.IDLE

func is_window_open() -> bool:
	return phase == Phase.ACTIVE

## The active stance and gear widen the window.
func get_window_length() -> float:
	var player := get_parent() as Player
	var window_mult := 1.0
	if player and player.weapon_stance and player.weapon_stance.is_active and player.weapon_stance.current_behavior:
		window_mult = player.weapon_stance.current_behavior.parry_window_multiplier
	if player and player.stat_sheet:
		window_mult *= 1.0 + player.stat_sheet.get_misc_bonus("parry_window_duration") / 100.0
	return parry_window_seconds * window_mult

## Melee weapons only: ranged weapons and conduits can't parry.
func can_parry_with(weapon: Weapon) -> bool:
	return weapon == null or (not weapon.is_ranged and not weapon.is_conduit)

## Returns false while a parry is still playing out, or mid-swing: it cuts
## your own swing's recovery short, but not its windup or strike.
func start_parry_window() -> bool:
	if is_busy():
		return false
	var player := get_parent() as Player
	if player and not can_parry_with(player.get_active_weapon()):
		return false
	if player and player.melee_attack:
		player.melee_attack.cancel_recovery()
		if player.melee_attack.is_committed():
			return false
	_active_length = get_window_length()
	phase = Phase.STARTUP
	_phase_timer = PARRY_STARTUP
	if player and player.arm_rig:
		player.arm_rig.play_parry(PARRY_STARTUP, _active_length, WHIFF_RECOVERY)
	return true

## Call when an incoming attack from `attacker` would land while the parry
## window is open. Returns true if the parry succeeded.
func attempt_parry(attacker: Node, ward: WardComponent) -> bool:
	if phase != Phase.ACTIVE:
		return false
	phase = Phase.IDLE

	var stance: StanceComponent = attacker.get_node_or_null("StanceComponent")
	if stance:
		stance.apply_parry_damage(parry_stance_damage)

	if ward:
		ward.restore_on_parry_success()
		# Gear Ward-on-parry, on top of the base restore.
		var player := get_parent() as Player
		if player and player.stat_sheet:
			var ward_on_parry_pct := player.stat_sheet.get_misc_bonus("ward_on_parry") / 100.0
			if ward_on_parry_pct > 0.0:
				ward.restore(ward.max_ward * ward_on_parry_pct)

	var parent := get_parent() as Player
	if parent:
		if parent.arm_rig:
			parent.arm_rig.play_parry_deflect()
		if parent.melee_attack:
			parent.melee_attack.hitstop(SUCCESS_HITSTOP)
	EventBus.parry_successful.emit(get_parent(), attacker)
	return true

func can_riposte(target: Node) -> bool:
	var composure: ComposureComponent = target.get_node_or_null("ComposureComponent") if target else null
	return composure != null and composure.is_broken

## Big hit plus brief invulnerability. Ends the target's broken state.
## forced: a visceral already committed to (its rip-out, or a backstab).
func execute_riposte(target: Enemy, weapon: Weapon, base_motion_value: float, damage_type: Constants.DamageType, forced: bool = false) -> void:
	if not forced and not can_riposte(target):
		return
	var player: Player = get_parent()
	# Riposte crit chance gear: bump finesse_crit_bonus for this one roll.
	var riposte_crit_bonus := player.stat_sheet.get_misc_bonus("riposte_crit_chance") / 100.0
	var original_crit_bonus := player.stat_sheet.finesse_crit_bonus
	if riposte_crit_bonus > 0.0:
		player.stat_sheet.finesse_crit_bonus = original_crit_bonus * (1.0 + riposte_crit_bonus)
	var hit := weapon.roll_damage(base_motion_value * RIPOSTE_MOTION_VALUE_MULTIPLIER, player.stat_sheet)
	player.stat_sheet.finesse_crit_bonus = original_crit_bonus

	# Patch v4.0 "Increased Riposte Damage" - flat % on top of the whole roll.
	var final_damage: float = hit["final_damage"] * (1.0 + player.stat_sheet.get_misc_bonus("increased_riposte_damage") / 100.0)
	# Counterstrike: bonus damage equal to a share of the Riposte's own hit.
	final_damage += hit["final_damage"] * player.stat_sheet.get_misc_bonus("riposte_counter_damage") / 100.0

	target.take_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(player, target, final_damage, damage_type, false, hit["is_critical"])

	target.composure.end_broken_state()
	grant_invulnerability(riposte_invuln_duration)
	EventBus.riposte_executed.emit(player, target)

func grant_invulnerability(seconds: float) -> void:
	is_invulnerable = true
	_invuln_timer = maxf(_invuln_timer, seconds)
