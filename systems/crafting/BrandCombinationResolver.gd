extends RefCounted
class_name BrandCombinationResolver
## Patch v3.6 Section 2. Resolves a set of placed category Brands
## (DAMAGE_TYPE/DEFENSIVE_TYPE/UMBRELLA - CraftingSystem.gd's own
## category_brands) into which real ItemRoller.AFFIX_POOL tag(s) to roll
## from. Keyed on real Brand.item_id (this project's 26 actual Brand
## instances - see data/brands/instances/), not the brief's own
## brand_id/pool-name scheme, which assumed pool categories ("mana",
## "spell", "attack", "speed") that don't exist as real ItemRoller tags -
## every combo below resolves to a LIST of real category_tag strings to
## union-roll from instead of a made-up single hybrid pool name, so no
## new pool content has to be invented to make combinations mean
## something (Cube UI/GearAffixPool design stay untouched, per the brief).
##
## Falls back to CraftingSystem's existing single-category weighted pick
## for any combination not listed here - this only adds NAMED, deterministic
## flavor to specific combos the brief called out, it doesn't replace the
## general case.

## Two-Brand combinations -> real tags to union-roll from.
const DOUBLE_BRAND_TAGS := {
	"anneal+attenuate": ["armor", "evasion"],
	"anneal+occlude": ["armor", "ward"],
	"attenuate+occlude": ["evasion", "ward"],
	"temper+inure": ["resistance", "resilience"],
	"impel+anneal": ["kinetic", "armor"],
	"calcine+temper": ["fire", "resistance"],
	"invoke+occlude": ["aetheric", "ward"],
}

## Three-Brand combinations -> real tags to union-roll from.
const TRIPLE_BRAND_TAGS := {
	"deflagrate+impel+lancet": ["kinetic", "piercing", "explosive"],
	"calcine+galvanic+quench": ["fire", "cold", "lightning"],
	"efface+hollow+invoke": ["aetheric", "entropic", "pale"],
	"anneal+attenuate+occlude": ["armor", "evasion", "ward"],
	"distill+hone+quicken": ["resource", "skills", "movement"],
}

## Any damage-type Brand + hone/inscribe: both real Brands share the
## "skills" category_tag (there's no separate real "attack"/"spell" tag
## to distinguish them by, unlike the brief assumed), so this keys on the
## real item_id directly instead.
const SKILL_PAIRING_IDS := ["hone", "inscribe"]

## brand_ids: the item_id of every placed category Brand (duplicates
## allowed - same brand x2 doesn't change which combo matches, only
## _roll_tier_floor() below cares about count). Returns real tags to
## union-roll from, or [] if no named combination matches (caller should
## fall back to its own default weighting).
static func resolve_tags(brand_ids: Array[String], category_tags: Array[String]) -> Array[String]:
	var unique_ids := _unique(brand_ids)

	if unique_ids.size() == 2:
		var key := "+".join(_sorted(unique_ids))
		if DOUBLE_BRAND_TAGS.has(key):
			return _to_string_array(DOUBLE_BRAND_TAGS[key])
		var skill_pair := _skill_pairing_tags(unique_ids, category_tags)
		if not skill_pair.is_empty():
			return skill_pair

	if unique_ids.size() == 3:
		var key3 := "+".join(_sorted(unique_ids))
		if TRIPLE_BRAND_TAGS.has(key3):
			return _to_string_array(TRIPLE_BRAND_TAGS[key3])

	var empty: Array[String] = []
	return empty

## Const Dictionary values are plain untyped Array literals - copy into a
## properly-typed Array[String] so callers (and this file's own -> Array
## [String] return types) don't hit a runtime type mismatch.
static func _to_string_array(arr: Array) -> Array[String]:
	var result: Array[String] = []
	for s in arr:
		result.append(s)
	return result

## "Same Brand x3 - guaranteed T1-T3 floor" (brief's own phrasing) -
## this project's tiers run Tier 1 (best) to ItemRoller.TIER_COUNT
## (worst), so a "floor" is a CAP on how bad the roll can be, not a
## minimum number. Returns the max allowed tier (int) or -1 if the
## bonus doesn't apply.
static func same_brand_tier_cap(brand_ids: Array[String]) -> int:
	if brand_ids.size() == 3 and brand_ids[0] == brand_ids[1] and brand_ids[1] == brand_ids[2]:
		return 3
	return -1

static func _skill_pairing_tags(unique_ids: Array[String], category_tags: Array[String]) -> Array[String]:
	var has_skill_brand := false
	for id in unique_ids:
		if SKILL_PAIRING_IDS.has(id):
			has_skill_brand = true
			break
	if not has_skill_brand:
		return []
	var other_tags: Array[String] = []
	for tag in category_tags:
		if tag != "skills" and not other_tags.has(tag):
			other_tags.append(tag)
	if other_tags.is_empty():
		return []
	other_tags.append("skills")
	return other_tags

static func _unique(ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		if not result.has(id):
			result.append(id)
	return result

static func _sorted(ids: Array[String]) -> Array[String]:
	var copy := ids.duplicate()
	copy.sort()
	return copy
