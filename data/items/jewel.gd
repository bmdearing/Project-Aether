extends Item
class_name Jewel
## A socketable gem. Rolls and crafts like gear, but from JewelModifierPool
## and with Constants.AFFIX_LIMITS_JEWEL (one prefix, one suffix, Uncommon 1 line total).
## Socketed into an item's free socket, its modifiers count as that item's
## (Item.get_effective_affixes()).

const DISPLAY_NAME := "Jewel"

func get_affix_limits() -> Vector2i:
	return Constants.AFFIX_LIMITS_JEWEL.get(rarity, Vector2i.ZERO)

func get_total_limit() -> int:
	return Constants.AFFIX_TOTAL_LIMITS_JEWEL.get(rarity, 0)
