extends RefCounted
class_name ItemRoller
## Rolls a random piece of gear on demand - dropped by Enemy.gd on death,
## picked up via LootPickup.gd, or stocked by the Hub's GearShop. No
## procedural item-generation table exists in the docs, so this
## duplicates an existing hand-authored base item (real, balanced
## weapon_type/damage_type/scaling_grade/etc.) and re-rolls only its
## rarity + affix list.
##
## Rarity -> affix count matches Section 18 (Common 0, Uncommon 0-2, Rare
## 0-6 - rarity is determined by base quality, not affix count). Affix
## values roll in tiers (TIER_COUNT bands, Tier 1 best) gated by
## `power_level`. flat_<stat> affixes are the only source of stat growth
## in this project (Section 12: gear only) - summed into StatSheet by
## EquipmentComponent.compute_stat_bonuses().
##
## loot_rarity_multiplier (from the active Map, see MapItem.gd) shifts
## the rarity roll. loot_quantity_multiplier is consumed by Enemy.gd's
## drop-chance roll instead, not here.

const BASE_ITEM_DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
]

## 5 tiers per affix, Tier 1 best - the doc's own tier counts vary per
## mod (5 to 11+); this project picks one consistent count for every affix.
const TIER_COUNT := 5
## Each tier's range is TIER_DECAY of the tier above's - an invented
## approximation of the doc's tables' shape.
const TIER_DECAY := 0.8

## tier1_min/tier1_max define only the best (Tier 1) range - lower tiers
## are derived via _tier_range(). "applies_to": [] means any base item
## type; otherwise a list of category strings (see _pool_for()).
const AFFIX_POOL := [
	{"stat_key": "flat_vitality", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Vitality", "applies_to": []},
	{"stat_key": "flat_strength", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Strength", "applies_to": []},
	{"stat_key": "flat_instinct", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Instinct", "applies_to": []},
	{"stat_key": "flat_arcane", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Arcane", "applies_to": []},
	{"stat_key": "flat_enigma", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Enigma", "applies_to": []},
	{"stat_key": "flat_intellect", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Intellect", "applies_to": []},
	{"stat_key": "physical_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Physical damage", "applies_to": ["weapon"]},
	{"stat_key": "elemental_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Elemental damage", "applies_to": ["weapon"]},
	{"stat_key": "esoteric_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Esoteric damage", "applies_to": ["weapon"]},
	{"stat_key": "flat_armor", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Armor", "applies_to": ["armor", "shield"]},
	{"stat_key": "flat_ward", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Ward", "applies_to": ["armor"]},
]

## power_level: the active Map's tier, or player level as a fallback in
## the Hub - a rough "how strong should this roll be" signal.
## loot_rarity_multiplier: shifts the rarity roll upward.
static func roll(power_level: int = 1, loot_rarity_multiplier: float = 1.0) -> Item:
	var base := _pick_base_item()
	if base == null:
		return null
	var item: Item = base.duplicate(true)
	item.item_id = "%s_rolled_%d" % [base.item_id, randi()]

	var rarity_roll := randf() * loot_rarity_multiplier
	var affix_count := 0
	if rarity_roll >= 1.4:
		item.rarity = Constants.ItemRarity.RARE
		affix_count = randi_range(0, 6)
	elif rarity_roll >= 0.9:
		item.rarity = Constants.ItemRarity.UNCOMMON
		affix_count = randi_range(0, 2)
	else:
		item.rarity = Constants.ItemRarity.COMMON

	# A rolled item's affix list is fully re-rolled, not additive on top
	# of the base's own hand-authored implicit(s).
	item.affixes = []
	var pool := _pool_for(item)
	pool.shuffle()
	for i in range(min(affix_count, pool.size())):
		var entry: Dictionary = pool[i]
		var rolled_tier := _roll_tier(power_level)
		var value_range := _tier_range(entry["tier1_min"], entry["tier1_max"], rolled_tier)
		var value: float = randf_range(value_range.x, value_range.y)
		var affix := ItemAffix.new()
		affix.stat_key = entry["stat_key"]
		affix.value = value
		affix.value_min = value_range.x
		affix.value_max = value_range.y
		affix.tier = rolled_tier
		affix.description = "%s (Tier %d)" % [entry["desc"] % round(value), rolled_tier]
		affix.is_prefix = i % 2 == 0
		item.affixes.append(affix)

	return item

## Tier N's range = Tier 1's range scaled by TIER_DECAY^(N-1).
static func _tier_range(tier1_min: float, tier1_max: float, tier: int) -> Vector2:
	var scale: float = pow(TIER_DECAY, tier - 1)
	return Vector2(tier1_min * scale, tier1_max * scale)

## Invented - the doc never defines what gates tier access. The best
## tier reachable improves by one per power_level point; the actual roll
## is uniform between that and the worst tier.
static func _roll_tier(power_level: int) -> int:
	var best_reachable: int = clamp(TIER_COUNT - power_level, 1, TIER_COUNT)
	return randi_range(best_reachable, TIER_COUNT)

static func _pick_base_item() -> Item:
	var candidates: Array[String] = []
	for dir_path in BASE_ITEM_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				candidates.append(dir_path + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	if candidates.is_empty():
		return null
	return load(candidates[randi() % candidates.size()]) as Item

static func _pool_for(item: Item) -> Array:
	var category := _category_of(item)
	var result := []
	for entry in AFFIX_POOL:
		var applies: Array = entry["applies_to"]
		if applies.is_empty() or applies.has(category):
			result.append(entry)
	return result

static func _category_of(item: Item) -> String:
	if item is Weapon:
		return "weapon"
	if item is Armor:
		return "armor"
	if item is Shield:
		return "shield"
	return "item"
