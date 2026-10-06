extends Enemy
class_name LordOfTheElements
## First Pinnacle boss (PinnacleArena). Each attack takes the next element
## in ELEMENT_ORDER.

const ELEMENT_ORDER: Array[Constants.DamageType] = [
	Constants.DamageType.FIRE,
	Constants.DamageType.COLD,
	Constants.DamageType.LIGHTNING,
]

var current_element: Constants.DamageType = ELEMENT_ORDER[0]
var _next_element_index: int = 0

func begin_attack_telegraph(windup_sec: float) -> void:
	current_element = ELEMENT_ORDER[_next_element_index]
	_next_element_index = (_next_element_index + 1) % ELEMENT_ORDER.size()
	var melee := get_node_or_null("MeleeAttack") as EnemyMeleeAttack
	if melee:
		melee.damage_type = current_element
	super.begin_attack_telegraph(windup_sec)
