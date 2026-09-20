extends Item
class_name Shield
## Offhand shields per Section 13/25. block_chance (a fraction, 0.15 = 15%)
## is rolled against in Player.try_block_melee_hit(); Block Threshold was
## removed entirely in Patch v4.3.
##
## evasion_value/ward_value added alongside the original armor_value
## (user request 2026-08-30, generating Section 25's real shield lines) -
## Buckler/Rune Shield/Warded Barrier lines lead with Evasion or Ward
## instead of Armor as their primary defensive stat, same hybrid shape
## Armor.gd already models for Body Armour/Helmet/Gloves/Boots.

@export var block_chance: float = 0.0
@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var ward_value: float = 0.0
