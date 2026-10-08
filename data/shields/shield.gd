extends Item
class_name Shield
## Offhand shield. block_chance (0.15 = 15%) is rolled in
## Player.try_block_melee_hit(). Some lines lead with Evasion or Ward
## rather than Armor.

@export var block_chance: float = 0.0
@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var ward_value: float = 0.0
