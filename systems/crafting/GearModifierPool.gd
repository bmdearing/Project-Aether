extends RefCounted
class_name GearModifierPool
## The &"gear" ModifierPool for real items, built from the same sources and
## eligibility rules ItemRoller uses for drops (AFFIX_POOL for armour,
## shields and accessories; the weapon affix library for weapons), so Orbs
## and drops can't drift apart. Tiers follow ItemRoller: Tier 1's range
## decays by TIER_DECAY per tier, and tiers better than the item's level
## allows (ItemRoller._roll_tier()) are left out.

## Words in an AFFIX_POOL stat_key that make it a suffix; everything else
## is a prefix. AFFIX_POOL has no prefix/suffix of its own.
const SUFFIX_KEYWORDS := ["resistance", "speed", "regen", "cooldown", "crit", "debuff", "stamina", "ailment", "skill_level"]
## Old Brand category tags -> the Rev2 Brand tags they correspond to.
const TAG_ALIASES := {"resource": &"mana", "movement": &"speed"}

## "<source key>|<best tier>" -> ModifierDef, so a def is the same object
## every time it's offered (preview merges outcomes by identity).
static var _cache: Dictionary = {}

static func defs_for(item: Item) -> Array[ModifierDef]:
	var best_tier: int = clampi(ItemRoller.TIER_COUNT - maxi(item.item_level, 1), 1, ItemRoller.TIER_COUNT)
	var defs: Array[ModifierDef] = []
	if item is Weapon:
		for want_prefix in [true, false]:
			for source in ItemRoller._eligible_weapon_affixes(item, maxi(item.item_level, 1), want_prefix):
				defs.append(_library_def(source, best_tier))
	else:
		for entry in ItemRoller._pool_for(item):
			defs.append(_pool_def(entry, best_tier))
	return defs

static func _pool_def(entry: Dictionary, best_tier: int) -> ModifierDef:
	var key := "pool:%s|%d" % [entry["stat_key"], best_tier]
	if _cache.has(key):
		return _cache[key]
	var def := ModifierDef.new()
	def.id = StringName(entry["stat_key"])
	def.group = def.id
	def.stat_key = entry["stat_key"]
	def.text = entry["desc"]
	def.affix_type = ModifierDef.AffixType.SUFFIX if _is_suffix(entry["stat_key"]) else ModifierDef.AffixType.PREFIX
	def.tags = _tags(entry["brand_tags"], entry["stat_key"])
	def.tiers = _tiers(entry["tier1_min"], entry["tier1_max"], best_tier)
	_cache[key] = def
	return def

static func _library_def(source: ItemAffix, best_tier: int) -> ModifierDef:
	var id := source.affix_id if source.affix_id != "" else source.stat_key
	var key := "lib:%s|%d" % [id, best_tier]
	if _cache.has(key):
		return _cache[key]
	var def := ModifierDef.new()
	def.id = StringName(id)
	def.group = def.id
	def.stat_key = source.stat_key
	def.text = source.description
	def.affix_type = ModifierDef.AffixType.PREFIX if source.is_prefix else ModifierDef.AffixType.SUFFIX
	var tags: Array = []
	if source.damage_type != -1:
		tags.append(Constants.DAMAGE_TYPE_NAME.get(source.damage_type, "").to_lower())
	def.tags = _tags(tags, source.stat_key)
	def.tiers = _tiers(source.value_min, source.value_max, best_tier)
	def.damage_type = source.damage_type
	def.is_generic = source.is_generic
	def.is_local = source.is_local
	_cache[key] = def
	return def

static func _is_suffix(stat_key: String) -> bool:
	for word in SUFFIX_KEYWORDS:
		if stat_key.contains(word):
			return true
	return false

## Source tags plus the Rev2 umbrella tags (mana/speed/spell/attack).
static func _tags(source_tags: Array, stat_key: String) -> Array[StringName]:
	var tags: Array[StringName] = []
	for t in source_tags:
		tags.append(StringName(t))
		if TAG_ALIASES.has(t):
			tags.append(TAG_ALIASES[t])
	if stat_key.contains("spell") or stat_key.contains("cast"):
		tags.append(&"spell")
	if stat_key.contains("attack"):
		tags.append(&"attack")
	if stat_key.contains("speed") and not tags.has(&"speed"):
		tags.append(&"speed")
	return tags

static func _tiers(tier1_min: float, tier1_max: float, best_tier: int) -> Array[ModifierTier]:
	var tiers: Array[ModifierTier] = []
	for t in range(best_tier, ItemRoller.TIER_COUNT + 1):
		var range_ := ItemRoller._tier_range(tier1_min, tier1_max, t)
		var tier := ModifierTier.new()
		tier.tier = t
		tier.value_min = range_.x
		tier.value_max = range_.y
		tier.weight = Constants.GEAR_TIER_WEIGHTS[t - 1]
		tiers.append(tier)
	return tiers
