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

## Stance an ordinary hit drains per 100% of the enemy's Life it deals, before
## the damage-category weight. Measured against Life, not raw damage, so it
## holds at every Area Level (raw damage x0.2 broke the flat 100 pool on every
## hit once player hits reached the thousands). At 120, Physical hits alone
## break Stance at about 83% of Life dealt: Parries stay the main way in.
const ATTACK_STANCE_PER_LIFE := 120.0

func _ready() -> void:
	current_stance = max_stance

func apply_parry_damage(amount: float) -> void:
	_deplete(amount * _stagger_multiplier())

func apply_attack_stance_damage(raw_amount: float, damage_type: Constants.DamageType) -> void:
	var category: Constants.DamageCategory = Constants.DAMAGE_TYPE_CATEGORY[damage_type]
	var weight: float = CATEGORY_WEIGHT.get(category, 0.5)
	_deplete(attack_stance_damage(raw_amount) * weight * _stagger_multiplier())

## A hit's Stance drain before its category weight: its share of the owner's Life.
func attack_stance_damage(raw_amount: float) -> float:
	var health: Node = get_parent().get_node_or_null("HealthComponent") if get_parent() else null
	var max_life: float = health.get("max_health") if health and health.get("max_health") != null else 0.0
	if max_life <= 0.0:
		return 0.0
	return raw_amount / max_life * ATTACK_STANCE_PER_LIFE

## The player's "increased Stagger effect": every Stance drain here comes from them.
func _stagger_multiplier() -> float:
	return 1.0 + GearEffects.player_bonus(get_tree(), "stagger_effect") / 100.0 if is_inside_tree() else 1.0

func _deplete(amount: float) -> void:
	if current_stance <= 0.0:
		return
	current_stance = max(0.0, current_stance - amount)
	EventBus.stance_damaged.emit(get_parent(), amount, current_stance)
	if current_stance <= 0.0:
		EventBus.composure_broken.emit(get_parent())

func reset() -> void:
	current_stance = max_stance
