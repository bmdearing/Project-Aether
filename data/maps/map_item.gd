extends Item
class_name MapItem
## A Map item (PoE-style) - using it at the Map Device rolls the
## difficulty/reward of the Map instance you enter. Affixes reuse
## ItemAffix.gd, same shape Weapons/Armor/generic Items already use for
## rolled mods, rather than inventing a parallel format.
##
## `equip_slot` (inherited from Item) is meaningless here - a Map is
## never equipped via EquipmentComponent, and MapItem is deliberately
## kept out of InventoryScreen's equip-grid scan (see MapDevice.gd) so it
## never ends up clickable there.
##
## enemy_damage_multiplier/enemy_health_multiplier are real and applied
## to every Enemy spawned in the resulting Map (see Enemy.gd's
## _apply_map_modifiers()). loot_quantity_multiplier/
## loot_rarity_multiplier are tracked and shown on the item's stat card,
## but have nothing to actually affect yet - there's no loot generation
## system in this project (every item everywhere is still the "owns one
## of each" stand-in), so they're flagged as inert rather than silently
## doing nothing.

@export var tier: int = 1
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_health_multiplier: float = 1.0
@export var loot_quantity_multiplier: float = 1.0
@export var loot_rarity_multiplier: float = 1.0
