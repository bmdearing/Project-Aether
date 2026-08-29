extends Enemy
class_name HeavyHitter
## Trinity Rule: Lethal + Tanky. Slow, telegraphed, devastating
## if contact is made.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.HEAVY_HITTER
	move_speed = 1.8
	stop_distance = 2.3  # just inside MeleeAttack.attack_range (2.5)
	health.max_health = 220.0
	xp_reward = 25.0
	gold_reward = 12
	_set_placeholder_color(Color(0.5, 0.08, 0.08))  # dark red - slow/lethal/tanky
