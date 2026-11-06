extends RefCounted
class_name JewelRoller
## The 4-modifier, uncraftable jewel's name.
const GRAND_NAME := "Grand Jewel"
## Rolls a Jewel drop. Jewels top out at Uncommon (1-2 modifiers, one prefix
## and one suffix); a Common roll has none. JEWEL_GRAND_CHANCE of drops is a
## Rare with two prefixes and two suffixes that can't be crafted.

static func roll(item_level: int = 1, loot_rarity_multiplier: float = 1.0, rng: RandomNumberGenerator = null) -> Jewel:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var jewel := Jewel.new()
	jewel.item_id = "jewel_rolled_%d" % rng.randi()
	jewel.display_name = Jewel.DISPLAY_NAME
	jewel.item_level = maxi(item_level, 1)
	var count := 0
	if rng.randf() < Constants.JEWEL_GRAND_CHANCE * loot_rarity_multiplier:
		jewel.rarity = Constants.ItemRarity.RARE
		jewel.is_craftable = false
		jewel.display_name = GRAND_NAME
		count = 4
	else:
		jewel.rarity = mini(Loot.roll_rarity(loot_rarity_multiplier, rng), Constants.ItemRarity.UNCOMMON) as Constants.ItemRarity
		if jewel.rarity == Constants.ItemRarity.UNCOMMON:
			count = rng.randi_range(1, 2)
	add_random_modifiers(jewel, count, rng)
	return jewel

## Adds up to `count` modifiers, skipping groups already on the jewel and
## affix types that are full.
static func add_random_modifiers(jewel: Jewel, count: int, rng: RandomNumberGenerator) -> void:
	var resolver := CraftingResolver.new(rng)
	var limits := jewel.get_affix_limits()
	for i in count:
		if jewel.affixes.size() >= jewel.get_total_limit():
			return
		var groups := jewel.affixes.map(func(a: ItemAffix): return a.get_group())
		var prefixes := jewel.affixes.filter(func(a: ItemAffix): return a.is_prefix).size()
		var suffixes := jewel.affixes.size() - prefixes
		var cands: Array[Dictionary] = []
		for def in JewelModifierPool.defs_for(jewel):
			if groups.has(def.group):
				continue
			var is_prefix := def.affix_type == ModifierDef.AffixType.PREFIX
			if (is_prefix and prefixes >= limits.x) or (not is_prefix and suffixes >= limits.y):
				continue
			for tier in def.tiers:
				cands.append({"def": def, "tier": tier, "weight": tier.weight})
		if cands.is_empty():
			return
		jewel.affixes.append(resolver._roll_affix(resolver._pick(cands)))
