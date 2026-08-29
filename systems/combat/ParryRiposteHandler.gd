extends Node
class_name ParryRiposteHandler
## Orchestrates Parry -> Stance damage -> Composure Break -> Riposte window,
## per Section 07. Attach to the Player; targets are enemies carrying
## StanceComponent + ComposureComponent.
##
## Camera-agnostic by design: this handler doesn't care whether the game is
## first-person or third-person. `attempt_parry()` is currently fed by
## EnemyMeleeAttack.gd's Strike state, which calls it directly with the
## attacking enemy as `attacker` at the moment the swing resolves - a
## distance check stands in for a real hitbox until enemy art/animation
## exists (see EnemyMeleeAttack for why). A player-facing Area3D "parry
## detection" volume would only matter for attacks with actual trajectories,
## which don't exist yet either.

@export var parry_window_seconds: float = 0.25
@export var parry_stance_damage: float = 25.0

var _parry_active: bool = false
var _parry_timer: float = 0.0
var _riposte_available_target: Node = null

func _process(delta: float) -> void:
	if _parry_active:
		_parry_timer -= delta
		if _parry_timer <= 0.0:
			_parry_active = false

func start_parry_window() -> void:
	_parry_active = true
	_parry_timer = parry_window_seconds

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
	_riposte_available_target = attacker
	return true

## Riposte is universal per Section 07 - available to every build, not gated
## by Slate investment (Slates only amplify effectiveness).
func can_riposte(target: Node) -> bool:
	if target != _riposte_available_target:
		return false
	var composure: ComposureComponent = target.get_node_or_null("ComposureComponent")
	return composure != null and composure.is_broken

func execute_riposte(target: Node, riposte_ability: Ability) -> void:
	if not can_riposte(target):
		return
	if riposte_ability and riposte_ability.can_trigger_riposte == false:
		push_warning("Riposte executed with an ability not flagged can_trigger_riposte - check data authoring.")
	EventBus.riposte_executed.emit(get_parent(), target)
	_riposte_available_target = null
