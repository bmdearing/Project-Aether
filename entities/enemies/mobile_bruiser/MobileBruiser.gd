extends Enemy
class_name MobileBruiser
## Trinity Rule: Fast + Tanky. Hard to hit and hard to kill,
## lower individual damage.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.MOBILE_BRUISER
	move_speed = 180.0
	health.max_health = 180.0
