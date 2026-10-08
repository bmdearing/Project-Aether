extends RefCounted
class_name BrandCombinationResolver
## Maps specific combinations of placed category Brands (by Brand.item_id)
## to the affix pool tags to union-roll from. Unlisted combinations fall
## back to CraftingSystem's single-category weighted pick.

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

## hone/inscribe share the "skills" tag, so they're matched by item_id.
const SKILL_PAIRING_IDS := ["hone", "inscribe"]

## brand_ids may contain duplicates. Returns [] when no combination matches.
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

## Const Dictionary values are untyped Arrays; convert for typed returns.
static func _to_string_array(arr: Array) -> Array[String]:
	var result: Array[String] = []
	for s in arr:
		result.append(s)
	return result

## Same Brand x3 guarantees T1-T3. Tier 1 is best, so this returns the worst
## allowed tier, or -1 if the bonus doesn't apply.
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
