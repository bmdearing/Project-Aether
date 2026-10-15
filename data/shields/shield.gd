extends Item
class_name Shield
## Offhand shield. block_chance (0.15 = 15%) is rolled in
## Player.try_block_melee_hit(). Some lines lead with Evasion or Ward
## rather than Armor.

@export var block_chance: float = 0.0
@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var ward_value: float = 0.0

## block_chance with this shield's own flat and increased Block modifiers.
func get_local_block_chance() -> float:
	return (block_chance + own_affix_total("block_chance_bonus") / 100.0) * (1.0 + own_affix_total("increased_block_chance") / 100.0)
