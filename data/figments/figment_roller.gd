extends RefCounted
class_name FigmentRoller
## Rolls a fresh FigmentItem - either a flat request (roll(), the Reality
## Engine's always-available free Tier 1 offer) or a drop-scaled one
## (roll_for_drop(), used by Enemy.gd's loot table and chests). Mods come
## from FigmentMods' pools (the tier's band decides which pools open);
## style weights come from the Figment Tree.

const MAX_TIER := FigmentMods.MAX_TIER
## Legacy stat keys from Figments rolled before the mod pools.
const LEGACY_KEYS := ["enemy_damage_multiplier", "enemy_health_multiplier", "loot_quantity_multiplier", "loot_rarity_multiplier"]

static func roll(tier: int) -> FigmentItem:
	var figment := FigmentItem.new()
	figment.item_id = "rolled_figment_t%d_%d" % [tier, randi()]
	figment.tier = clampi(tier, 1, MAX_TIER)
	figment.tileset_id = roll_style()
	var style := MapTileset.load_style(figment.tileset_id)
	figment.display_name = "%s Figment" % style.display_name if style else "Tier %d Figment" % figment.tier
	figment.flavor_text = "Reality bends where the Engine points it."
	var ids := FigmentMods.ids_for_tier(figment.tier)
	ids.shuffle()
	var count := mini(FigmentMods.roll_mod_count(figment.tier) + int(FigmentTree.effect("figment_extra_mod")), ids.size())
	for i in count:
		_set_mod(figment, ids[i])
	_finish(figment)
	return figment

## Lands near power_level (the killing Map's own tier, or player level in the
## Hub) with a chance to roll a tier higher or lower, capped one tier above
## the highest tier completed (FigmentProgress). The Figment Tree adds a
## chance to roll one more tier up.
static func roll_for_drop(power_level: int) -> FigmentItem:
	var tier: int = power_level + randi_range(-1, 1)
	if randf() * 100.0 < FigmentTree.effect("figment_tier_up"):
		tier += 1
	return roll(clampi(tier, 1, FigmentProgress.max_drop_tier()))

## A MapTileset style id, weighted by the tree's per-family weights.
static func roll_style() -> String:
	var ids := MapTileset.all_ids()
	if ids.is_empty():
		return ""
	var weights: Array[float] = []
	var total := 0.0
	for id in ids:
		var w := 1.0 + FigmentTree.effect("style_weight:" + MapTileset.family_of(id)) / 100.0
		weights.append(w)
		total += w
	var pick := randf() * total
	for i in ids.size():
		pick -= weights[i]
		if pick < 0.0:
			return ids[i]
	return ids[ids.size() - 1]

## Empowering: the tier has already gone up. Adds a mod from the (possibly
## newly opened) pools, or rerolls one higher when all are taken.
static func strengthen(figment: FigmentItem) -> void:
	_strip_legacy(figment)
	var open := FigmentMods.ids_for_tier(figment.tier).filter(func(id: String): return figment.get_mod(id) == null)
	if open.is_empty():
		var affix: ItemAffix = figment.affixes[randi() % figment.affixes.size()]
		_set_mod(figment, affix.stat_key)
	else:
		_set_mod(figment, open[randi() % open.size()])
	_finish(figment)

static func _set_mod(figment: FigmentItem, id: String) -> void:
	var affix := figment.get_mod(id)
	if affix == null:
		affix = ItemAffix.new()
		affix.stat_key = id
		figment.affixes.append(affix)
	affix.value = maxf(affix.value, FigmentMods.roll_value(id, figment.tier))
	affix.tier = FigmentMods.pool_of(id)
	if id == "monster_conversion" and affix.damage_type == -1:
		affix.damage_type = FigmentMods.CONVERSION_TYPES.pick_random()
	affix.description = FigmentMods.describe(id, affix.value, affix.damage_type)

static func _finish(figment: FigmentItem) -> void:
	figment.recompute_rewards()
	var pools := 0
	for affix in figment.affixes:
		pools = maxi(pools, FigmentMods.pool_of(affix.stat_key))
	figment.rarity = Constants.ItemRarity.RARE if pools >= 3 or figment.affixes.size() >= 4 else Constants.ItemRarity.UNCOMMON

static func _strip_legacy(figment: FigmentItem) -> void:
	var kept: Array[ItemAffix] = []
	for affix in figment.affixes:
		if not LEGACY_KEYS.has(affix.stat_key):
			kept.append(affix)
	figment.affixes = kept
	figment.enemy_damage_multiplier = 1.0
	figment.enemy_health_multiplier = 1.0
