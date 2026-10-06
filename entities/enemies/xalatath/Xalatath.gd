extends Enemy
class_name Xalatath
## Second Pinnacle boss: melee within reach, Entropic bolts beyond it.

const BOLT_RANGE := 20.0
const BOLT_MIN_RANGE := 5.0
const BOLT_COOLDOWN := 2.8

func _ready() -> void:
	super._ready()
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = BOLT_RANGE
		ranged.min_range = BOLT_MIN_RANGE
		ranged.cooldown_duration = BOLT_COOLDOWN
