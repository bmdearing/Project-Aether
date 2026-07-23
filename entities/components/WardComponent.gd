extends Node
class_name WardComponent
## Absorbs Esoteric damage before Health. Does not regenerate passively -
## requires active restoration via kill, Parry, Riposte, or Aetheric skill
## use per the World Doc's Ward design notes (Section 16).

@export var max_ward: float = 0.0
var current_ward: float = 0.0

## Returns the remaining damage that should overflow to Health after Ward absorption.
func absorb(incoming_damage: float, damage_type: Constants.DamageType) -> float:
	if Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) != Constants.DamageCategory.ESOTERIC:
		return incoming_damage
	if current_ward <= 0.0:
		return incoming_damage

	var absorbed := min(current_ward, incoming_damage)
	current_ward -= absorbed
	if current_ward <= 0.0:
		EventBus.ward_depleted.emit(get_parent())
	return incoming_damage - absorbed

func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current_ward = min(max_ward, current_ward + amount)
	EventBus.ward_restored.emit(get_parent(), amount)

func restore_on_parry_success() -> void:
	restore(max_ward * 0.15)  # placeholder ratio - numerical formula deferred per Section 16
