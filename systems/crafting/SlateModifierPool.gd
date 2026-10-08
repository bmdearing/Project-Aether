extends RefCounted
class_name SlateModifierPool
## The &"slate" ModifierPool for real Slates, built from SlateAffixPool's
## data/slates/affix_pool/ entries. A Slate only rolls modifiers for its own
## tag(s) plus the untyped generic/spell/attack ones. Each entry's
## value_min/value_max is its Tier 1 range; lower tiers decay like gear.

const TIER_COUNT := 3
const UNTYPED_TAGS: Array[StringName] = [&"generic", &"spell", &"attack"]

static var _cache: Dictionary = {}  # affix_id -> ModifierDef

static func defs_for(slate: Slate) -> Array[ModifierDef]:
	var allowed: Array[StringName] = slate.get_slate_tags()
	allowed.append_array(UNTYPED_TAGS)
	var defs: Array[ModifierDef] = []
	for tag in SlateAffixPool.get_all_tags():
		if not allowed.has(StringName(tag)):
			continue
		for source in SlateAffixPool.get_pool_for_tag(tag):
			defs.append(_def_for(source))
	return defs

static func _def_for(source: SlateAffix) -> ModifierDef:
	var id := source.affix_id if source.affix_id != "" else source.stat_key
	if _cache.has(id):
		return _cache[id]
	var def := ModifierDef.new()
	def.id = StringName(id)
	def.group = def.id
	def.stat_key = source.stat_key
	def.text = source.description
	def.affix_type = ModifierDef.AffixType.PREFIX if source.is_prefix else ModifierDef.AffixType.SUFFIX
	def.tags.append(StringName(source.tag))
	def.damage_type = source.damage_type
	for t in TIER_COUNT:
		var range_ := ItemRoller._tier_range(source.value_min, source.value_max, t + 1)
		var tier := ModifierTier.new()
		tier.tier = t + 1
		tier.value_min = range_.x
		tier.value_max = range_.y
		tier.weight = Constants.SLATE_TIER_WEIGHTS[t]
		def.tiers.append(tier)
	_cache[id] = def
	return def
