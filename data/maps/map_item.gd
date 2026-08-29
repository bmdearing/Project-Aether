extends Item
class_name MapItem
## A Map item (PoE-style) - using it at the Map Device rolls the
## difficulty/reward of the Map instance you enter. Affixes reuse
## ItemAffix.gd, same shape Weapons/Armor use for rolled mods.
##
## `equip_slot` (inherited from Item) is meaningless here - a Map is
## never equipped via EquipmentComponent.
##
## enemy_damage_multiplier/enemy_health_multiplier are applied to every
## Enemy spawned in the resulting Map (see Enemy.gd's
## _apply_map_modifiers()). loot_quantity_multiplier/loot_rarity_multiplier
## are shown on the stat card but inert - no loot generation system exists yet.

@export var tier: int = 1
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_health_multiplier: float = 1.0
@export var loot_quantity_multiplier: float = 1.0
@export var loot_rarity_multiplier: float = 1.0
