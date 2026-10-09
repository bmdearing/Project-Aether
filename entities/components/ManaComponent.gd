extends Node
class_name ManaComponent
## Mana pool spent by abilities, with slow passive regen.

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

## Like HealthComponent.set_max_health(): an increase adds the difference to
## current Mana, so a fresh Player (spawned full at the base maximum) stays
## full once gear raises it.
func set_max_mana(new_max: float) -> void:
	var delta := new_max - max_mana
	max_mana = new_max
	current_mana = clampf(current_mana + maxf(delta, 0.0), 0.0, max_mana)
	mana_changed.emit(current_mana, max_mana)

func spend(amount: float) -> void:
	current_mana = max(0.0, current_mana - amount)
	mana_changed.emit(current_mana, max_mana)

## Gains Mana up to the maximum (Mana on kill / on ailment modifiers).
func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current_mana = min(max_mana, current_mana + amount)
	mana_changed.emit(current_mana, max_mana)
