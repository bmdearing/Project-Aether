extends RefCounted
class_name SpecialCorruptionPool
## Corruption-only modifiers (Add Special Affix): one of the item's own
## modifiers at CORRUPTED_MULTIPLIER x its Tier 1 maximum, a strength normal
## crafting and drops can't reach. Shown as "(Corrupted)" instead of a tier.

const CORRUPTED_MULTIPLIER := 1.3

## Modifiers this item could gain, as ModifierDefs from its own pool.
static func defs_for(item: Item) -> Array[ModifierDef]:
	var top := item.duplicate() as Item
	top.item_level = 100
	return GearModifierPool.defs_for(top)

## The corrupted value of a def: its Tier 1 maximum x CORRUPTED_MULTIPLIER.
static func corrupted_value(def: ModifierDef) -> float:
	var best := 0.0
	for tier in def.tiers:
		best = maxf(best, tier.value_max)
	return roundf(best * CORRUPTED_MULTIPLIER) if ItemRoller.has_levelled_tiers(def.stat_key) else best * CORRUPTED_MULTIPLIER

static func get_random_for(item: Item) -> ItemAffix:
	var have := item.affixes.map(func(a: ItemAffix): return a.key())
	var defs := defs_for(item).filter(func(d: ModifierDef): return not have.has(StatKeys.canonical(d.stat_key)))
	if defs.is_empty():
		return null
	var def: ModifierDef = defs[randi() % defs.size()]
	var affix := ItemAffix.new()
	affix.stat_key = def.stat_key
	affix.affix_id = String(def.id)
	affix.value = corrupted_value(def)
	affix.value_min = affix.value
	affix.value_max = affix.value
	affix.is_prefix = def.affix_type == ModifierDef.AffixType.PREFIX
	affix.is_local = def.is_local
	affix.damage_type = def.damage_type
	affix.description = "%s (Corrupted)" % ItemRoller.describe_value(def.text, def.stat_key, affix.value)
	return affix
