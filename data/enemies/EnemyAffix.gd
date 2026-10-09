extends Resource
class_name EnemyAffix
## A rolled modifier on a rare enemy (EnemyRarityComponent).
##   PACK      - Elite packs: the whole pack shares one, every member has it.
##   CHAMPION  - Champions: auras (has_aura) apply their stat lines to every
##               enemy within aura_radius, the Champion included; the rest
##               apply to the Champion alone.
##   ASCENDANT - Ascendants' own, stronger pool.
## Stat lines are percentages. `mechanic` names behaviour the component runs
## itself (EnemyRarityComponent.MECHANIC_*).

enum AffixCategory { PACK, CHAMPION, ASCENDANT }

@export var affix_id: String = ""
@export var display_name: String = ""
@export var category: AffixCategory = AffixCategory.PACK
@export var description: String = ""

## Drop modifiers - % increased Item Rarity/Quantity on this enemy's own
## drops (doc: "Item Rarity on the enemy affects the quality of converted
## drops... Item Quantity... affects the count").
@export var item_rarity_bonus: float = 0.0
@export var item_quantity_bonus: float = 0.0

## Drop conversion - "all-or-nothing" per the doc, flagged on the affix
## data itself rather than a separate system.
@export var converts_drops: bool = false
@export var drop_conversion_type: String = ""  # "figments", "brands", etc.

## Damage conversion (e.g. Dreamer: "Converts all damage to Entropic").
@export var converts_damage: bool = false
@export var damage_conversion_type: Constants.DamageType = Constants.DamageType.KINETIC

@export_group("Stats")
@export var more_damage: float = 0.0
@export var more_life: float = 0.0
@export var move_speed: float = 0.0
@export var attack_speed: float = 0.0
## Negative = takes less damage.
@export var damage_taken: float = 0.0
## % of maximum Life regenerated per second.
@export var life_regen: float = 0.0
## Ward as a % of maximum Life; refills after a few seconds without a hit.
@export var ward_percent: float = 0.0
## Heals this % of the damage its hits deal.
@export var leech: float = 0.0
## Status its hits apply, and the chance per hit.
@export var on_hit_status: String = ""
@export var on_hit_chance: float = 0.0
## Ignores slows, stuns, staggers and knockback.
@export var unstoppable: bool = false

@export_group("Aura")
@export var has_aura: bool = false
@export var aura_radius: float = 10.0

@export_group("Mechanic")
## EnemyRarityComponent.MECHANIC_* ("frenzy", "volatile", "soul_eater",
## "blink", "nova"), "" for none.
@export var mechanic: StringName = &""
@export var mechanic_value: float = 0.0
