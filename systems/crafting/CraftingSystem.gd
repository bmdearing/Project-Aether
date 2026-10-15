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

## ---- Orbs on Figments -------------------------------------------------------

## Orbs on a Figment work on its map mods (FigmentMods), not gear modifiers:
## quickening (Common: 1-2 mods), forging (Common: a full roll), elevation
## (Uncommon: +2), grafting (Uncommon: +1), ascendant (Rare: +1), recasting
## (reroll all), severance (remove one), absolution (remove all), reckoning
## (reroll values). Mods never pass the band's maximum count.
const FIGMENT_ORBS: Array[StringName] = [&"quickening", &"forging", &"elevation", &"grafting", &"ascendant", &"recasting", &"severance", &"absolution", &"reckoning"]

static func craft_figment(figment: FigmentItem, orb_id: StringName) -> Dictionary:
	if not FIGMENT_ORBS.has(orb_id):
		return {"success": false, "message": "%s has no effect on a Figment." % CurrencyText.name_of(orb_id)}
	var count := figment.affixes.size()
	var cap := figment_mod_cap(figment)
	var rarity := figment.rarity if count > 0 else Constants.ItemRarity.COMMON
	match orb_id:
		&"quickening", &"forging":
			if count > 0:
				return {"success": false, "message": "Only works on a Figment with no mods."}
			_add_figment_mods(figment, randi_range(1, 2) if orb_id == &"quickening" else FigmentMods.roll_mod_count(figment.tier))
		&"elevation", &"grafting", &"ascendant":
			var needed := Constants.ItemRarity.RARE if orb_id == &"ascendant" else Constants.ItemRarity.UNCOMMON
			if rarity != needed:
				return {"success": false, "message": "Only works on a%s %s Figment." % ["" if needed == Constants.ItemRarity.RARE else "n", "Rare" if needed == Constants.ItemRarity.RARE else "Uncommon"]}
			if count >= cap:
				return {"success": false, "message": "This Figment already has its most mods (%d)." % cap}
			_add_figment_mods(figment, 2 if orb_id == &"elevation" else 1)
		&"recasting":
			if count == 0:
				return {"success": false, "message": "This Figment has no mods to reroll."}
			figment.affixes = [] as Array[ItemAffix]
			_add_figment_mods(figment, clampi(count, 1, cap))
		&"severance", &"absolution":
			if count == 0:
				return {"success": false, "message": "This Figment has no mods to remove."}
			if orb_id == &"absolution":
				figment.affixes = [] as Array[ItemAffix]
			else:
				figment.affixes.remove_at(randi() % count)
		&"reckoning":
			if count == 0:
				return {"success": false, "message": "This Figment has no mods to reroll."}
			for affix in figment.affixes:
				affix.value = FigmentMods.roll_value(affix.stat_key, figment.tier)
				affix.description = FigmentMods.describe(affix.stat_key, affix.value, affix.damage_type)
	FigmentRoller._finish(figment)
	if figment.affixes.is_empty():
		figment.rarity = Constants.ItemRarity.COMMON
	return {"success": true, "message": "%s used: %d mod%s." % [CurrencyText.name_of(orb_id), figment.affixes.size(), "" if figment.affixes.size() == 1 else "s"]}

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
