extends RefCounted
class_name CraftingSystem
## The crafting actions outside the Siphon (Crafting Rev 3): the two physical
## crafting items (Tempering and the Shard of Tharsis, a thin wrapper around
## CorruptionSystem.gd), the map-mod crafts the Siphon runs on Figments, and
## Figment empowering. Siphon crafting is CraftingResolver.gd.

## Figment "affixes" are FigmentMods mods, not player stats, so empowering
## is its own Gold-priced action. It can't pass the highest tier a Figment
## can drop at (FigmentProgress.max_drop_tier()).
const EMPOWER_FIGMENT_GOLD_COST := 25

static func empower_figment(figment: FigmentItem) -> Dictionary:
	if figment == null:
		return {"success": false, "message": "No Figment selected."}
	if figment.is_levelling():
		if figment.depth >= FigmentProgress.max_drop_depth():
			return {"success": false, "message": "Clear Depth %d to empower past it." % figment.depth}
		figment.depth += 1
		return {"success": true, "message": "The Figment sinks deeper - now Depth %d." % figment.depth}
	if figment.tier >= FigmentProgress.max_drop_tier():
		return {"success": false, "message": "Complete a Tier %d Figment to empower past it." % figment.tier if figment.tier < FigmentMods.MAX_TIER else "This Figment is already Tier %d." % FigmentMods.MAX_TIER}
	figment.tier += 1
	FigmentRoller.strengthen(figment)
	return {"success": true, "message": "The Figment grows harder - now Tier %d." % figment.tier}

## ---- Tempering ---------------------------------------------------

## Raises a weapon's or armour piece's quality (weapons: 1% more weapon
## damage per point; armour and shields: 1% more base defences). Works on
## corrupted, Unique and Mythic items too.
static func temper(item: Item) -> Dictionary:
	if not (item is Weapon or item is Armor or item is Shield):
		return {"success": false, "message": "Tempering only works on weapons and armour."}
	if item.quality >= item.get_quality_cap():
		return {"success": false, "message": CurrencyText.error_message("QUALITY_CAPPED")}
	var before := item.quality
	item.quality = mini(item.get_quality_cap(), item.quality + randi_range(Constants.TEMPERING_QUALITY_GAIN.x, Constants.TEMPERING_QUALITY_GAIN.y))
	EventBus.item_quality_changed.emit(item)
	EventBus.item_stats_changed.emit(item)
	return {"success": true, "message": "Quality +%d%% (now %d%%)." % [item.quality - before, item.quality]}

## ---- Shard of Tharsis (Corruption) --------------------------------

static func corrupt(item: Item, power_level: int = 1) -> Dictionary:
	var outcome := CorruptionSystem.corrupt(item, power_level)
	if not outcome.success:
		return {"success": false, "message": outcome.reason, "destroyed": false}
	var message := "%s: %s." % [CorruptionSystem.TIER_NAMES.get(outcome.tier, "?"), outcome.outcome_name]
	if not item.is_craftable:
		message += " This item can no longer be crafted except with an Orb of Opening or Tempering."
	EventBus.item_stats_changed.emit(item)
	return {"success": true, "message": message, "destroyed": false}

## One rolled AFFIX_POOL modifier from `pool` (entries already filtered for
## the item), skipping stat_keys in exclude_keys. Used by Shard outcomes.
static func _random_affix_for(item: Item, pool: Array, power_level: int, exclude_keys: Array = []) -> ItemAffix:
	var candidates: Array = pool.filter(func(entry): return not exclude_keys.has(entry["stat_key"]))
	if candidates.is_empty():
		return null
	var entry: Dictionary = candidates[randi() % candidates.size()]
	var tiers := ItemRoller.entry_tiers(entry, item.equip_slot)
	var rolled := ItemRoller.roll_tier_range(entry["stat_key"], tiers.x, tiers.y, power_level)
	var rolled_tier: int = rolled["tier"]
	var value_range := Vector2(rolled["min"], rolled["max"])
	var value := ItemRoller.roll_value(entry["stat_key"], value_range)
	var affix := ItemAffix.new()
	affix.stat_key = entry["stat_key"]
	affix.value = value
	affix.value_min = value_range.x
	affix.value_max = value_range.y
	affix.tier = rolled_tier
	affix.description = "%s (Tier %d)" % [ItemRoller.describe_value(entry["desc"], entry["stat_key"], value), rolled_tier]
	affix.is_prefix = item.affixes.size() % 2 == 0
	return affix

## ---- Siphon crafts on Figments ------------------------------------------

## The Siphon on a Figment works on its map mods (FigmentMods), not gear
## modifiers: add (+1), recast (one mod replaced), bleed (one removed),
## absolve (all removed), settle (values rerolled). Mods never pass the
## band's maximum count. CraftingResolver validates; this applies.
static func figment_craft(figment: FigmentItem, craft_id: StringName) -> void:
	var count := figment.affixes.size()
	match craft_id:
		&"add":
			_add_figment_mods(figment, 1)
		&"recast":
			var removed: ItemAffix = figment.affixes[randi() % count]
			figment.affixes.erase(removed)
			_add_figment_mods(figment, 1)
		&"bleed":
			figment.affixes.remove_at(randi() % count)
		&"absolve":
			figment.affixes = [] as Array[ItemAffix]
		&"settle":
			for affix in figment.affixes:
				affix.value = FigmentMods.roll_value(affix.stat_key, figment.tier)
				affix.description = FigmentMods.describe(affix.stat_key, affix.value, affix.damage_type)
	FigmentRoller._finish(figment)
	if figment.affixes.is_empty():
		figment.rarity = Constants.ItemRarity.COMMON

## Most mods a Figment can hold: its band's top count (plus the Figment Tree's extra mod).
static func figment_mod_cap(figment: FigmentItem) -> int:
	var band: Vector2i = FigmentMods.MOD_COUNT[figment.band()]
	return mini(band.y + int(FigmentTree.effect("figment_extra_mod")), FigmentMods.ids_for_tier(figment.tier).size())

## Adds up to `amount` mods the Figment doesn't have yet, within its cap.
static func _add_figment_mods(figment: FigmentItem, amount: int) -> void:
	var open := FigmentMods.ids_for_tier(figment.tier).filter(func(id: String): return figment.get_mod(id) == null)
	open.shuffle()
	for i in mini(amount, mini(open.size(), figment_mod_cap(figment) - figment.affixes.size())):
		FigmentRoller._set_mod(figment, open[i])
