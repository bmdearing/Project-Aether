extends Resource
class_name EnemyAffix
## A rolled modifier on a rare enemy (EnemyRarityComponent). PACK affixes
## roll on Elite packs; Champion and Ascendant each have their own pool.
##
## Auras are visual only, and damage conversion isn't consumed yet. Drop
## conversion only handles Figments.

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

## Aura (Champion/Ascendant only) - visual placeholder only this pass.
@export var has_aura: bool = false
@export var aura_radius: float = 8.0
@export var aura_stat_key: String = ""
@export var aura_value: float = 0.0
