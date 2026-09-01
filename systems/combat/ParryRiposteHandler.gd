extends Node
class_name ParryRiposteHandler
## Orchestrates Parry -> Stance damage -> Composure Break -> Riposte,
## per Section 07. Attach to the Player; targets are enemies carrying
## StanceComponent + ComposureComponent.
##
## `attempt_parry()` is fed by EnemyMeleeAttack.gd's Strike state, called
## directly with the attacking enemy as `attacker` when the swing
## resolves - stands in for a real hitbox until enemy art/animation exists.
##
## Riposte itself is triggered from PlayerMeleeAttack._deal_damage() -
## any melee attack landed on a target while ComposureComponent.is_broken
## is true, not gated to only-after-a-parry (attrition-broken enemies are
## just as riposte-able as parry-broken ones). Riposte is universal per
## Section 07 - available to every build, not gated by Slate investment
## (Slates only amplify effectiveness).

@export var parry_window_seconds: float = 0.25
@export var parry_stance_damage: float = 25.0
## Riposte's motion-value multiplier on top of the weapon's normal swing -
## "a large amount of damage," invented, not doc-sourced with an exact
## number. Riposte damage also inherits ComposureComponent's existing
## "damage taken while broken" multiplier for free, since the target is
## still broken at the moment the hit lands (end_broken_state() runs after).
const RIPOSTE_MOTION_VALUE_MULTIPLIER := 3.0
@export var riposte_invuln_duration: float = 1.0

var is_invulnerable: bool = false
var _parry_active: bool = false
var _parry_timer: float = 0.0
var _invuln_timer: float = 0.0

func _process(delta: float) -> void:
	if _parry_active:
		_parry_timer -= delta
		if _parry_timer <= 0.0:
			_parry_active = false
	if is_invulnerable:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			is_invulnerable = false

## Implementation Brief v3.3 Section 7: a weapon's active stance can widen
## the parry window (Rapier's own rapier_stance.tres: 1.5x) - only the
## window DURATION changes, damage/Ward restore/Composure damage from a
## successful parry are unaffected, per the brief's own explicit scope.
func start_parry_window() -> void:
	var player := get_parent() as Player
	var window_mult := 1.0
	if player and player.weapon_stance and player.weapon_stance.is_active and player.weapon_stance.current_behavior:
		window_mult = player.weapon_stance.current_behavior.parry_window_multiplier
	_parry_active = true
	_parry_timer = parry_window_seconds * window_mult

## Call when an incoming attack from `attacker` would land while the parry
## window is open. Returns true if the parry succeeded.
func attempt_parry(attacker: Node, ward: WardComponent) -> bool:
	if not _parry_active:
		return false
	_parry_active = false

	var stance: StanceComponent = attacker.get_node_or_null("StanceComponent")
	if stance:
		stance.apply_parry_damage(parry_stance_damage)

	if ward:
		ward.restore_on_parry_success()

	EventBus.parry_successful.emit(get_parent(), attacker)
	return true

func can_riposte(target: Node) -> bool:
	var composure: ComposureComponent = target.get_node_or_null("ComposureComponent") if target else null
	return composure != null and composure.is_broken

## Big damage burst + a brief invulnerability window ("the duration of the
## animation" - there's no real animation, so this just times out
## alongside PlayerMeleeAttack's stronger riposte hitstop/shake). Ends the
## target's broken state - one riposte consumes the window, it doesn't
## loop for its remaining duration.
func execute_riposte(target: Enemy, weapon: Weapon, base_motion_value: float, damage_type: Constants.DamageType) -> void:
	if not can_riposte(target):
		return
	var player: Player = get_parent()
	var hit := weapon.roll_damage(base_motion_value * RIPOSTE_MOTION_VALUE_MULTIPLIER, player.stat_sheet)
	var final_damage: float = hit["final_damage"]

	target.take_damage(final_damage, damage_type)
	EventBus.damage_dealt.emit(player, target, final_damage, damage_type, false, hit["is_critical"])

	target.composure.end_broken_state()
	is_invulnerable = true
	_invuln_timer = riposte_invuln_duration
	EventBus.riposte_executed.emit(player, target)
