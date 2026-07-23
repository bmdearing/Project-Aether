extends Enemy
class_name HeavyHitter
## Trinity Rule: Lethal + Tanky. Slow, telegraphed, devastating
## if contact is made.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.HEAVY_HITTER
	move_speed = 70.0
	health.max_health = 220.0
