extends Node
class_name HealthComponent
## HealthComponent is a CHILD of Enemy, and children ready before parents -
## Enemy subclasses (bosses) set max_health in their own _ready(), which
## runs after this one, so current_health initialization is deferred via
## call_deferred to see the real value.

signal died
signal health_changed(current: float, max: float)

@export var max_health: float = 100.0
## Section 12: Vitality -> "+0.1 Life regen/sec" per point - only ever
## set non-zero for the Player (Player._apply_derived_stats()), enemies
## have no StatSheet/Vitality to drive this from.
var regen_per_second: float = 0.0
var current_health: float = 0.0

func _ready() -> void:
	call_deferred("_initialize_current_health")

func _initialize_current_health() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

func _process(delta: float) -> void:
	if regen_per_second > 0.0 and is_alive() and current_health < max_health:
		current_health = min(max_health, current_health + regen_per_second * delta)
		health_changed.emit(current_health, max_health)

func apply_damage(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()

func heal(amount: float) -> void:
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

## Preserves missing health on change: heals by the delta on an increase
## (so gearing more Vitality doesn't just inflate the denominator), clamps
## on a decrease.
func set_max_health(new_max: float) -> void:
	var delta := new_max - max_health
	max_health = new_max
	current_health = clamp(current_health + max(delta, 0.0), 0.0, max_health)
	health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0
