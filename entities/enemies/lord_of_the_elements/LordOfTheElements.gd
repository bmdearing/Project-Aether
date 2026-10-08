extends PinnacleBoss
class_name LordOfTheElements
## First Pinnacle boss (PinnacleArena). Each attack, and each ability that
## doesn't fix its own element, takes the next element in ELEMENT_ORDER.
##   Phase 1: Elemental Burst under you, Conflagration fire pools.
##   Phase 2 (66%): Frozen Expanse, a huge chilling slam; Storm Volley.
##   Phase 3 (33%): Cataclysm rains elemental blasts; Elemental Convergence
##   drags you in for a slam.

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

func get_ability_damage_type() -> int:
	return current_element

func abilities() -> Array:
	return [
		{"id": "elemental_burst", "display_name": "Elemental Burst", "kind": BossAbility.Kind.BLAST, "cooldown": 6.0, "telegraph": 1.1, "radius": 3.0, "damage_mult": 1.4},
		{"id": "conflagration", "display_name": "Conflagration", "kind": BossAbility.Kind.HAZARD, "cooldown": 10.0, "telegraph": 1.0, "radius": 3.5, "duration": 6.0, "damage_mult": 1.0, "damage_type": Constants.DamageType.FIRE},
		{"id": "frozen_expanse", "display_name": "Frozen Expanse", "kind": BossAbility.Kind.SLAM, "cooldown": 15.0, "telegraph": 1.6, "radius": 9.0, "damage_mult": 1.6, "min_phase": 2, "damage_type": Constants.DamageType.COLD, "status": "chill"},
		{"id": "storm_volley", "display_name": "Storm Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 7.0, "telegraph": 0.8, "count": 5, "spread_degrees": 50.0, "damage_mult": 0.9, "min_range": 4.0, "max_range": 24.0, "min_phase": 2, "damage_type": Constants.DamageType.LIGHTNING},
		{"id": "cataclysm", "display_name": "Cataclysm", "kind": BossAbility.Kind.BLAST, "cooldown": 16.0, "telegraph": 1.2, "radius": 3.0, "count": 6, "damage_mult": 1.3, "max_range": 26.0, "min_phase": 3},
		{"id": "elemental_convergence", "display_name": "Elemental Convergence", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.0, "radius": 5.0, "damage_mult": 1.8, "max_range": 18.0, "min_phase": 3},
	]

func phase_openers() -> Dictionary:
	return {2: "frozen_expanse", 3: "cataclysm"}
