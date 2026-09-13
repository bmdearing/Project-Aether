extends Resource
class_name EnemyAffix
## Patch v3.9 "Enemy Rarity System" - a rolled modifier on an EnemyRarity-
## carrying enemy (see EnemyRarityComponent.gd). PACK affixes roll on
## Elite packs, CHAMPION/ASCENDANT affixes on their own tiers - Champion
## and Ascendant each draw from their own exclusive pool per the doc
## ("Rolls Champion-exclusive affixes" / "Rolls affixes from a stronger
## exclusive pool").
##
## Aura mechanics (has_aura/aura_*) are explicitly NOT wired this pass -
## visual placeholder only, per the brief's own DO NOT list. Damage
## conversion (converts_damage) and drop conversion (converts_drops) are
## data-only scaffolding too - LootDropper stubs the Figment conversion
## case, nothing consumes damage_conversion_type yet.

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
