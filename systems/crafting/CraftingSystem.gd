extends RefCounted
class_name CraftingSystem
## The crafting actions that sit outside the Orb system (Crafting &
## Inventory Rev2 Part 1): Infusion/Shrivening Stone, the Shard of Tharsis
## (a thin wrapper around CorruptionSystem.gd), and Figment empowering.
## Orb crafting is CraftingResolver.gd. The old Cube was removed in Rev2.

## Figment "affixes" are FigmentMods mods, not player stats, so empowering
## is its own Gold-priced action. It can't pass the highest tier a Figment
## can drop at (FigmentProgress.max_drop_tier()).
const EMPOWER_FIGMENT_GOLD_COST := 25

static func empower_figment(figment: FigmentItem) -> Dictionary:
	if figment == null:
		return {"success": false, "message": "No Figment selected."}
	if figment.tier >= FigmentProgress.max_drop_tier():
		return {"success": false, "message": "Complete a Tier %d Figment to empower past it." % figment.tier if figment.tier < FigmentMods.MAX_TIER else "This Figment is already Tier %d." % FigmentMods.MAX_TIER}
	figment.tier += 1
	FigmentRoller.strengthen(figment)
	return {"success": true, "message": "The Figment grows harder - now Tier %d." % figment.tier}

## ---- Infusion / Shrivening Stone ---------------------------------

## Rerolls a weapon's damage-type identity to a random type other than
## its own native one.
static func infuse(weapon: Weapon) -> Dictionary:
	if weapon == null:
		return {"success": false, "message": "Choose a weapon to infuse."}
	if weapon.get_all_affixes().any(func(a: ItemAffix): return a.stat_key == UniqueEffects.NO_INFUSION):
		return {"success": false, "message": "%s cannot be Infused." % weapon.display_name}
	var options: Array = Constants.DamageType.values().filter(func(t): return t != weapon.native_damage_type)
	weapon.infused_damage_type = options[randi() % options.size()]
	EventBus.item_stats_changed.emit(weapon)
	return {"success": true, "message": "Infused with %s." % Constants.DAMAGE_TYPE_NAME.get(weapon.infused_damage_type, "?")}

static func shrive(weapon: Weapon) -> Dictionary:
	if weapon == null:
		return {"success": false, "message": "Choose a weapon to shrive."}
	if weapon.infused_damage_type == -1:
		return {"success": false, "message": "This weapon has no infusion to remove."}
	var native_name: String = Constants.DAMAGE_TYPE_NAME.get(weapon.native_damage_type, "?")
	weapon.infused_damage_type = -1
	EventBus.item_stats_changed.emit(weapon)
	return {"success": true, "message": "The infusion is stripped away - back to native %s." % native_name}

## ---- Shard of Tharsis (Corruption) --------------------------------

static func corrupt(item: Item, power_level: int = 1) -> Dictionary:
	var outcome := CorruptionSystem.corrupt(item, power_level)
	if not outcome.success:
		return {"success": false, "message": outcome.reason, "destroyed": false}
	var message := "%s (Tier %d)" % [outcome.outcome_name, outcome.tier]
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
	var rolled := ItemRoller.roll_tier_range(entry["stat_key"], entry["tier1_min"], entry["tier1_max"], power_level)
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
