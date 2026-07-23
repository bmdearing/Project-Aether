extends CharacterBody2D
class_name Enemy
## Base enemy per the Trinity Rule (Section 21) - archetype is a combination
## of at most two of {Fast, Lethal, Tanky}. Archetype-specific subclasses
## (GlassCannon, MobileBruiser, HeavyHitter) should extend this and tune
## exported values rather than duplicate component wiring.

@export var archetype: Constants.EnemyArchetype
@export var move_speed: float = 120.0

@onready var health: HealthComponent = $HealthComponent
@onready var stance: StanceComponent = $StanceComponent
@onready var composure: ComposureComponent = $ComposureComponent

func _ready() -> void:
	health.died.connect(_on_died)

func _on_died() -> void:
	queue_free()

func take_damage(amount: float, damage_type: Constants.DamageType) -> void:
	var multiplier := composure.get_damage_multiplier() if composure else 1.0
	health.apply_damage(amount * multiplier)
