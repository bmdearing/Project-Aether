extends Node
class_name ManaComponent
## Resource pool Ability.resource_cost draws from. Unlike WardComponent
## (Section 16: no passive regen, active-restoration only per the docs),
## there's no documented Mana design anywhere in the referenced sections -
## a slow passive regen here is an invented, undocumented default, not
## doc-sourced, same category as WardComponent's own placeholder
## restore-on-parry ratio.

@export var max_mana: float = 100.0
@export var regen_per_second: float = 5.0
var current_mana: float = 0.0

signal mana_changed(current: float, max: float)

func _ready() -> void:
	current_mana = max_mana

func _process(delta: float) -> void:
	if current_mana < max_mana:
		current_mana = min(max_mana, current_mana + regen_per_second * delta)
		mana_changed.emit(current_mana, max_mana)

func spend(amount: float) -> void:
	current_mana = max(0.0, current_mana - amount)
	mana_changed.emit(current_mana, max_mana)
