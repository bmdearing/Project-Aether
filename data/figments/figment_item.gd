extends Item
class_name FigmentItem
## A Figment (PoE Map-style currency item, renamed per user request from
## "Map") - selecting one at the Reality Engine (formerly "Map Device")
## rolls the difficulty/reward of the generated Map instance you enter.
## Affixes reuse ItemAffix.gd, same shape Weapons/Armor use for rolled
## mods.
##
## `equip_slot` (inherited from Item) is meaningless here - a Figment is
## never equipped via EquipmentComponent.
##
## enemy_damage_multiplier/enemy_health_multiplier are applied to every
## Enemy spawned in the resulting Map (see Enemy.gd's
## _apply_map_modifiers()) on top of Enemy's own deterministic tier
## scaling. loot_quantity_multiplier/loot_rarity_multiplier are shown on
## the stat card but inert - no loot-quantity/rarity consumption of these
## specific multipliers exists yet (loot generation has its own separate,
## real power_level-based rarity curve - see ItemRoller.gd).

@export var tier: int = 1
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_health_multiplier: float = 1.0
@export var loot_quantity_multiplier: float = 1.0
@export var loot_rarity_multiplier: float = 1.0
