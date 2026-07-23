extends Enemy
class_name GlassCannon
## Trinity Rule: Fast + Lethal. Rushes aggressively, dangerous if it
## connects, dies quickly. Tune via exported values on the base Enemy scene.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.GLASS_CANNON
	move_speed = 200.0
	health.max_health = 60.0
