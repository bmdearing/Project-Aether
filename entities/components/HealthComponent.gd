extends Node
class_name HealthComponent

signal died
signal health_changed(current: float, max: float)

@export var max_health: float = 100.0
var current_health: float = 0.0

func _ready() -> void:
	current_health = max_health

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

func is_alive() -> bool:
	return current_health > 0.0
