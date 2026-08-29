extends Node
class_name HealthComponent
## Found via a diagnostic test while wiring up ability damage prediction:
## HealthComponent is a CHILD of Enemy, and Godot readies children before
## parents. Enemy archetype subclasses (HeavyHitter etc.) set
## health.max_health via GDScript in their own _ready(), which runs
## AFTER this component's _ready() already fired - so `current_health =
## max_health` here was always capturing the class default (100.0), not
## the archetype's real value (220/180/60), regardless of which
## archetype it was. Player is unaffected (Player.tscn sets max_health as
## a static node property, applied before any _ready() runs at all).
## Fixed the same way EnemyMeleeAttack's parent-onready bug was: defer
## via call_deferred so this runs after every _ready() this frame
## (including the archetype override) has finished.

signal died
signal health_changed(current: float, max: float)

@export var max_health: float = 100.0
var current_health: float = 0.0

func _ready() -> void:
	call_deferred("_initialize_current_health")

func _initialize_current_health() -> void:
	current_health = max_health
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

func is_alive() -> bool:
	return current_health > 0.0
