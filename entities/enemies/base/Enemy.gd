extends CharacterBody3D
class_name Enemy
## Base enemy per the Trinity Rule (Section 21) - archetype is a combination
## of at most two of {Fast, Lethal, Tanky}. Archetype-specific subclasses
## (GlassCannon, MobileBruiser, HeavyHitter) should extend this and tune
## exported values rather than duplicate component wiring.
##
## No AI yet - this is a static target dummy until the next Claude Code
## pass wires up an attack + telegraph per the vertical slice brief.

@export var archetype: Constants.EnemyArchetype
@export var move_speed: float = 3.0

@onready var health: HealthComponent = $HealthComponent
@onready var stance: StanceComponent = $StanceComponent
@onready var composure: ComposureComponent = $ComposureComponent

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
		move_and_slide()

func _on_died() -> void:
	queue_free()

func take_damage(amount: float, damage_type: Constants.DamageType) -> void:
	var multiplier := composure.get_damage_multiplier() if composure else 1.0
	health.apply_damage(amount * multiplier)
