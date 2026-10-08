extends PinnacleBoss
class_name Xalatath
## Second Pinnacle boss, shown as "Herald of the Maw" (a placeholder: the
## model and ids are Xalatath's, which is Blizzard's and must be replaced).
## Entropic. Melee within reach, Entropic bolts beyond it.
##   Phase 1: Void Rift pools, Shadow Lunge.
##   Phase 2 (66%): calls Veilborne Mindbenders; Entropic Volley.
##   Phase 3 (33%): Unmaking pulls you in for a heavy slam; Collapse rains blasts.

const DISPLAY_NAME := "Herald of the Maw"
const BOLT_RANGE := 20.0
const BOLT_MIN_RANGE := 5.0
const BOLT_COOLDOWN := 2.8

func _ready() -> void:
	super._ready()
	display_name = DISPLAY_NAME
	var ranged := get_node_or_null("RangedAttack") as EnemyRangedAttack
	if ranged:
		ranged.fire_range = BOLT_RANGE
		ranged.min_range = BOLT_MIN_RANGE
		ranged.cooldown_duration = BOLT_COOLDOWN

func abilities() -> Array:
	var entropic := Constants.DamageType.ENTROPIC
	return [
		{"id": "void_rift", "display_name": "Void Rift", "kind": BossAbility.Kind.HAZARD, "cooldown": 9.0, "telegraph": 1.0, "radius": 3.5, "duration": 7.0, "damage_mult": 1.0, "damage_type": entropic},
		{"id": "shadow_lunge", "display_name": "Shadow Lunge", "kind": BossAbility.Kind.CHARGE, "cooldown": 8.0, "telegraph": 0.9, "damage_mult": 1.5, "min_range": 5.0, "max_range": 16.0, "damage_type": entropic},
		{"id": "call_the_hollow", "display_name": "Call the Hollow", "kind": BossAbility.Kind.SUMMON, "cooldown": 30.0, "telegraph": 1.2, "count": 2, "unit_id": "veilborne_mindbender", "min_phase": 2},
		{"id": "entropic_volley", "display_name": "Entropic Volley", "kind": BossAbility.Kind.VOLLEY, "cooldown": 8.0, "telegraph": 0.9, "count": 7, "spread_degrees": 70.0, "damage_mult": 0.8, "min_range": 4.0, "max_range": 24.0, "min_phase": 2, "damage_type": entropic},
		{"id": "unmaking", "display_name": "Unmaking", "kind": BossAbility.Kind.PULL, "cooldown": 14.0, "telegraph": 1.1, "radius": 6.0, "damage_mult": 2.0, "max_range": 18.0, "min_phase": 3, "damage_type": entropic},
		{"id": "collapse", "display_name": "Collapse", "kind": BossAbility.Kind.BLAST, "cooldown": 12.0, "telegraph": 1.2, "radius": 3.0, "count": 5, "damage_mult": 1.3, "max_range": 24.0, "min_phase": 3, "damage_type": entropic},
	]

func phase_openers() -> Dictionary:
	return {2: "call_the_hollow", 3: "unmaking"}
