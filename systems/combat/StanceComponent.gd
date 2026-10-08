extends Node
class_name StanceComponent
## Enemy resource bar depleted primarily through successful Parries.
## Attach to any enemy that should be Parry-able. On full depletion,
## triggers a Composure Break (see ComposureComponent).

@export var max_stance: float = 100.0
var current_stance: float = 0.0

# Depletion weight multipliers by damage category.
const CATEGORY_WEIGHT := {
	Constants.DamageCategory.PHYSICAL: 1.0,   # Blunt/Explosive land at the strong end within Physical
	Constants.DamageCategory.ELEMENTAL: 0.6,  # treated as "ranged/moderate" until elemental-specific tuning lands
	Constants.DamageCategory.ESOTERIC: 0.35,  # Occult/Spell - weakest Stance depletion, bypasses physical guard
}

## Keeps ordinary hits from breaking Stance faster than Parries do.
const ATTACK_STANCE_DAMAGE_MULTIPLIER := 0.2

func _ready() -> void:
	current_stance = max_stance

func apply_parry_damage(amount: float) -> void:
	_deplete(amount)

func apply_attack_stance_damage(raw_amount: float, damage_type: Constants.DamageType) -> void:
	var category: Constants.DamageCategory = Constants.DAMAGE_TYPE_CATEGORY[damage_type]
	var weight: float = CATEGORY_WEIGHT.get(category, 0.5)
	_deplete(raw_amount * weight * ATTACK_STANCE_DAMAGE_MULTIPLIER)

func _deplete(amount: float) -> void:
	if current_stance <= 0.0:
		return
	current_stance = max(0.0, current_stance - amount)
	EventBus.stance_damaged.emit(get_parent(), amount, current_stance)
	if current_stance <= 0.0:
		EventBus.composure_broken.emit(get_parent())

func reset() -> void:
	current_stance = max_stance
