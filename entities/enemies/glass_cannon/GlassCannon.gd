extends Enemy
class_name GlassCannon
## Trinity Rule: Fast + Lethal. Dangerous if it connects, dies quickly -
## now built as a kiting ranged skirmisher (EnemyRangedAttack, see
## GlassCannon.tscn) rather than a melee rusher: it closes to fire_range
## fast (move_speed), then backs off if the player closes inside
## retreat_distance, never sitting still in melee's reach where its low
## health folds instantly. Genre-standard read for "glass cannon" (avoids
## melee entirely, punishes anyone who lets it stand and shoot) and keeps
## the three archetypes distinct by engagement style, not just numbers -
## HeavyHitter/MobileBruiser stay melee brawlers.

func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.GLASS_CANNON
	move_speed = 5.5
	chase_range = 16.0
	stop_distance = 7.0       # holds near EnemyRangedAttack.fire_range (9.0)
	retreat_distance = 4.5    # backs off if the player closes inside this
	health.max_health = 60.0
	xp_reward = 12.0
	gold_reward = 6
	_set_placeholder_color(Color(0.95, 0.85, 0.2))  # yellow - fast/fragile
