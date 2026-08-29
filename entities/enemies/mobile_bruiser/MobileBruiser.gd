extends Enemy
class_name MobileBruiser
## Trinity Rule: Fast + Tanky. Hard to hit and hard to kill,
## lower individual damage.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.MOBILE_BRUISER
	move_speed = 4.5
	stop_distance = 2.3  # just inside MeleeAttack.attack_range (2.5)
	health.max_health = 180.0
	_set_placeholder_color(Color(0.2, 0.5, 0.9))  # blue - fast/tanky
