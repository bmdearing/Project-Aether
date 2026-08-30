extends Item
class_name Shield
## Offhand shields per Section 13/25. Data only - no BlockComponent exists
## yet to consume block_chance/block_threshold; the Block System (Section
## 07) isn't implemented anywhere in the current combat code.
##
## evasion_value/ward_value added alongside the original armor_value
## (user request 2026-08-30, generating Section 25's real shield lines) -
## Buckler/Rune Shield/Warded Barrier lines lead with Evasion or Ward
## instead of Armor as their primary defensive stat, same hybrid shape
## Armor.gd already models for Body Armour/Helmet/Gloves/Boots.

@export var block_chance: float = 0.0
@export var block_threshold: float = 0.0
@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var ward_value: float = 0.0
