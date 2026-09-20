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

## Stats, model and animations come from data/enemies/definitions/
## glass_cannon.tres (Enemy._apply_definition()/_apply_model()) - the first
## archetype on the EnemyDefinition + UAL animation pipeline.
func _ready() -> void:
	super._ready()
	archetype = Constants.EnemyArchetype.GLASS_CANNON
	_set_placeholder_color(Color(0.95, 0.85, 0.2))  # flash-restore reference color only - the real model is never painted with it
