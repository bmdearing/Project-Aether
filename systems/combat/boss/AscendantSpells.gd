extends RefCounted
class_name AscendantSpells
## Each Ascendant unit's own spellbook, cast through a BossBrain between its
## ordinary attacks (EnemyRarityComponent._late_setup()). No phases; spells
## only go off in combat with a clear line to the player, with a longer gap
## between them than a boss's.

const GAP := 3.5
const OPENING_GAP := 2.0

## Unit id -> BossAbility fields. Damage is the Ascendant's own hit times
## damage_mult (already scaled by its rarity and affixes).
const SPELLBOOKS := {
	"synod_vindicator": [
		{"id": "judgement", "display_name": "Judgement", "kind": BossAbility.Kind.BLAST, "count": 3, "radius": 2.2, "telegraph": 1.2,
			"cooldown": 9.0, "damage_mult": 1.0, "status": "aetherburn", "min_range": 4.0, "max_range": 20.0,
			"description": "Calls down three Aetheric strikes on and around you. They inflict Aetherburn."},
		{"id": "consecrate", "display_name": "Consecrate", "kind": BossAbility.Kind.SLAM, "radius": 4.5, "telegraph": 1.0,
			"cooldown": 8.0, "damage_mult": 1.3, "max_range": 4.5,
			"description": "Sears the ground around itself when you're close."},
		{"id": "vindicate", "display_name": "Vindicate", "kind": BossAbility.Kind.CHARGE, "telegraph": 0.9,
			"cooldown": 10.0, "damage_mult": 1.2, "min_range": 6.0, "max_range": 16.0,
			"description": "Charges straight at you, knocking you back."},
	],
	"legion_dreadknight": [
		{"id": "dread_grasp", "display_name": "Dread Grasp", "kind": BossAbility.Kind.PULL, "radius": 3.5, "telegraph": 1.0,
			"cooldown": 12.0, "damage_mult": 1.2, "status": "unraveling", "min_range": 5.0, "max_range": 12.0,
			"description": "Drags you to it, then slams the ground around itself. Inflicts Unraveling."},
		{"id": "blight_pool", "display_name": "Blight Pool", "kind": BossAbility.Kind.HAZARD, "radius": 3.0, "telegraph": 1.1,
			"duration": 5.0, "cooldown": 11.0, "damage_mult": 1.0, "status": "unraveling", "min_range": 3.0, "max_range": 18.0,
			"description": "Leaves a pool of Entropic rot under you that burns for 5 seconds."},
		{"id": "death_march", "display_name": "Death March", "kind": BossAbility.Kind.CHARGE, "telegraph": 1.0,
			"cooldown": 9.0, "damage_mult": 1.3, "min_range": 5.0, "max_range": 16.0,
			"description": "Charges straight at you, knocking you back."},
	],
	"veilborne_cantor": [
		{"id": "pale_litany", "display_name": "Pale Litany", "kind": BossAbility.Kind.VOLLEY, "count": 5, "spread_degrees": 50.0,
			"telegraph": 0.8, "cooldown": 7.0, "damage_mult": 0.8, "min_range": 4.0, "max_range": 18.0,
			"description": "Sings a fan of five Pale bolts at you."},
		{"id": "hollow_choir", "display_name": "Hollow Choir", "kind": BossAbility.Kind.BLAST, "radius": 3.0, "telegraph": 1.3,
			"cooldown": 9.0, "damage_mult": 1.4, "status": "pallid", "max_range": 20.0,
			"description": "A burst of Pale sound where you stand. Inflicts Pallid."},
		{"id": "call_the_veil", "display_name": "Call the Veil", "kind": BossAbility.Kind.SUMMON, "count": 2, "unit_id": "veilborne_mindbender",
			"telegraph": 1.2, "cooldown": 20.0, "max_range": 20.0,
			"description": "Summons two Veilborne Mindbenders."},
	],
}

static func has_spellbook(unit_id: String) -> bool:
	return SPELLBOOKS.has(unit_id)

static func abilities_for(unit_id: String) -> Array[BossAbility]:
	var list: Array[BossAbility] = []
	for fields in SPELLBOOKS.get(unit_id, []):
		list.append(BossAbility.make(fields))
	return list

## Gives the enemy a BossBrain casting its unit's spellbook. Null when the
## unit has none or the enemy already has a brain.
static func attach(enemy: Enemy, unit_id: String) -> BossBrain:
	if enemy.boss_brain != null or not has_spellbook(unit_id):
		return null
	var brain := BossBrain.new()
	brain.name = "AscendantSpells"
	brain.abilities = abilities_for(unit_id)
	brain.global_gap = GAP
	brain.opening_gap = OPENING_GAP
	brain.require_sight = true
	enemy.add_child(brain)
	return brain
