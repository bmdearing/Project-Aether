extends RefCounted
class_name ItemRoller
## Rolls a random piece of gear on demand - dropped by Enemy.gd on death,
## picked up via LootPickup.gd, or stocked by the Hub's GearShop. Picks a
## real, balanced base item (weapon_type/damage_type/scaling_grade/etc.)
## and re-rolls only its rarity + affix list.
##
## User request (2026-08-30): Section 25's full tiered base-type catalog
## is now real (see tools/generate_base_types.gd - ~750 generated .tres
## across data/weapons|armor|shields/instances/, each tagged item_level +
## base_line_id) alongside the original hand-authored singles (untagged,
## base_line_id == ""). power_level now doubles as the target item level:
## _pick_base_item() picks, per doc "Line", the single highest-item_level
## tier still <= power_level - "always the current best base your level
## has unlocked" - then rolls uniformly among every line's current pick
## plus every untagged standalone base. See Enemy._compute_item_level()
## for how a kill's own power_level is derived from area level + rank.
##
## Rarity -> affix count matches Section 18 (Common 0, Uncommon 0-2, Rare
## 0-6 - rarity is determined by base quality, not affix count). Affix
## values roll in tiers (TIER_COUNT bands, Tier 1 best) gated by
## `power_level`. flat_<stat> affixes are the only source of stat growth
## in this project (Section 12: gear only) - summed into StatSheet by
## EquipmentComponent.compute_stat_bonuses().
##
## loot_rarity_multiplier (from the active Map, see FigmentItem.gd) shifts
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
##
## "brand_tags": which Brand.category_tag value(s) (Section 20) a Cube
## craft's Damage Type/Defensive Type/Umbrella Brand can draw this entry
## from - see _pool_for_brand_tag(), used by CraftingSystem.gd. Evasion/
## Resistance/Resilience/Skills have no other stat anywhere in this
## project to hang a REAL affix off yet (same as flat_armor/flat_ward
## already were before this - README gap #18: descriptive-only, not
## aggregated into a formula), so their 4 entries below just extend that
## same existing gap rather than opening a new one.
const AFFIX_POOL := [
	{"stat_key": "flat_vitality", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Vitality", "applies_to": [], "brand_tags": []},
	{"stat_key": "flat_strength", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Strength", "applies_to": [], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "flat_instinct", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Instinct", "applies_to": [], "brand_tags": ["movement"]},
	{"stat_key": "flat_arcane", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Arcane", "applies_to": [], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "flat_enigma", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Enigma", "applies_to": [], "brand_tags": ["aetheric", "entropic", "pale"]},
	{"stat_key": "flat_intellect", "tier1_min": 20.0, "tier1_max": 25.0, "desc": "+%d Intellect", "applies_to": [], "brand_tags": ["resource"]},
	{"stat_key": "physical_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Physical damage", "applies_to": ["weapon"], "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "elemental_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Elemental damage", "applies_to": ["weapon"], "brand_tags": ["fire", "cold", "lightning"]},
	{"stat_key": "esoteric_dmg_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Esoteric damage", "applies_to": ["weapon"], "brand_tags": ["aetheric", "entropic", "pale"]},
	{"stat_key": "flat_armor", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Armor", "applies_to": ["armor", "shield"], "brand_tags": ["armor"]},
	{"stat_key": "flat_ward", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Ward", "applies_to": ["armor"], "brand_tags": ["ward"]},
	{"stat_key": "flat_evasion", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Evasion", "applies_to": ["armor"], "brand_tags": ["evasion"]},
	# Patch v3.2 "Revision - Resistance System": doc-exact range, matching
	# the Ember/Frost/Volt/Void Ring implicits (+11-27%) - Esoteric is
	# unified across Aetheric/Entropic/Pale per the patch, one stat covers
	# all three. applies_to: [] (any item) since the doc's own examples
	# are Rings, not armor.
	{"stat_key": "fire_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Fire Resistance", "applies_to": [], "brand_tags": ["resistance", "fire"]},
	{"stat_key": "cold_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Cold Resistance", "applies_to": [], "brand_tags": ["resistance", "cold"]},
	{"stat_key": "lightning_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Lightning Resistance", "applies_to": [], "brand_tags": ["resistance", "lightning"]},
	{"stat_key": "esoteric_resistance_pct", "tier1_min": 11.0, "tier1_max": 27.0, "desc": "+%d%% Esoteric Resistance", "applies_to": [], "brand_tags": ["resistance", "aetheric", "entropic", "pale"]},
	{"stat_key": "flat_resilience", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d Resilience", "applies_to": [], "brand_tags": ["resilience"]},
	{"stat_key": "skill_cooldown_reduced", "tier1_min": 8.0, "tier1_max": 12.0, "desc": "+%d%% reduced skill cooldowns", "applies_to": [], "brand_tags": ["skills"]},
]

## power_level: the active Map's tier, or player level as a fallback in
## the Hub - a rough "how strong should this roll be" signal.
## loot_rarity_multiplier: shifts the rarity roll upward.
static func roll(power_level: int = 1, loot_rarity_multiplier: float = 1.0) -> Item:
	var base := _pick_base_item(power_level)
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

## path -> {"item_level": int, "base_line_id": String} for every base item
## file across BASE_ITEM_DIRS - built once (loading ~750 generated .tres
## just to read 2 fields off each, every single kill, would be a real
## per-roll hitch) and reused for the process's whole lifetime; base items
## are static content, never added/removed/edited at runtime.
static var _candidate_meta_cache: Dictionary = {}

static func _pick_base_item(target_item_level: int) -> Item:
	if _candidate_meta_cache.is_empty():
		_build_candidate_meta_cache()
	if _candidate_meta_cache.is_empty():
		return null

	# Group tiered-line candidates (base_line_id != "") down to just the
	# single highest-item_level tier still <= target_item_level per line -
	# "always drop the current-tier base this level has unlocked," the
	# same ilvl-gated-base principle PoE-style tiered bases follow.
	# Standalone hand-authored items (base_line_id == "", every pre-
	# Section-25 base) are never grouped - always their own candidate,
	# gated only by their own item_level (1 by default, i.e. always in).
	var best_per_line: Dictionary = {}  # base_line_id -> {"path": String, "item_level": int}
	var pool: Array[String] = []
	for path in _candidate_meta_cache:
		var meta: Dictionary = _candidate_meta_cache[path]
		var item_level: int = meta["item_level"]
		if item_level > target_item_level:
			continue
		var line_id: String = meta["base_line_id"]
		if line_id == "":
			pool.append(path)
			continue
		var current: Dictionary = best_per_line.get(line_id, {})
		if current.is_empty() or item_level > int(current["item_level"]):
			best_per_line[line_id] = {"path": path, "item_level": item_level}
	for entry in best_per_line.values():
		pool.append(entry["path"])
	if pool.is_empty():
		return null
	return load(pool[randi() % pool.size()]) as Item

static func _build_candidate_meta_cache() -> void:
	for dir_path in BASE_ITEM_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path: String = dir_path + file_name
				var item := load(path) as Item
				if item:
					_candidate_meta_cache[path] = {"item_level": item.item_level, "base_line_id": item.base_line_id}
			file_name = dir.get_next()
		dir.list_dir_end()

static func _pool_for(item: Item) -> Array:
	var category := _category_of(item)
	var result := []
	for entry in AFFIX_POOL:
		var applies: Array = entry["applies_to"]
		if applies.is_empty() or applies.has(category):
			result.append(entry)
	return result

## Used by CraftingSystem.gd (Section 20's Cube) - same item-type
## filtering as _pool_for(), further narrowed to entries whose brand_tags
## include the Brand.category_tag driving the craft.
static func _pool_for_brand_tag(item: Item, tag: String) -> Array:
	var result := []
	for entry in _pool_for(item):
		var tags: Array = entry["brand_tags"]
		if tags.has(tag):
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
