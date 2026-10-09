extends RefCounted
class_name GearModifierPool
## The &"gear" ModifierPool for real items, built from the same sources and
## eligibility rules ItemRoller uses for drops (AFFIX_POOL for armour,
## shields and accessories; the weapon affix library for weapons), so Orbs
## and drops can't drift apart. Tiers follow ItemRoller: Tier 1's range
## decays by TIER_DECAY per tier (or the modifier's own LEVELLED_TIERS table),
## and tiers above what the item's level allows are left out.

## Words in an AFFIX_POOL stat_key that make it a suffix; everything else
## is a prefix. AFFIX_POOL has no prefix/suffix of its own.
const SUFFIX_KEYWORDS := ["resistance", "speed", "regen", "cooldown", "crit", "debuff", "stamina", "ailment", "skill_level", "rarity", "magic_find"]
## Old Brand category tags -> the Rev2 Brand tags they correspond to.
const TAG_ALIASES := {"resource": &"mana", "movement": &"speed"}
## Stat_key words -> Brand tags, for lines with no brand_tags of their own.
const DERIVED_TAGS := {
	"life": [&"life"], "crit": [&"critical"], "resistance": [&"resistance"],
	"elemental_taken": [&"resistance"], "esoteric_taken": [&"resistance"],
	"physical_taken": [&"armor"], "armor_to": [&"armor"],
	"riposte": [&"attack"], "parry": [&"attack"], "mana": [&"mana"],
}

## "<source key>|<best tier>" -> ModifierDef, so a def is the same object
## every time it's offered (preview merges outcomes by identity).
static var _cache: Dictionary = {}

static func defs_for(item: Item) -> Array[ModifierDef]:
	if item is Jewel:
		return JewelModifierPool.defs_for(item)
	var level := maxi(item.item_level, 1)
	var best_tier := ItemRoller.best_tier_for_level(level)
	var defs: Array[ModifierDef] = []
	if item is Weapon:
		for want_prefix in [true, false]:
			for source in ItemRoller._eligible_weapon_affixes(item, maxi(item.item_level, 1), want_prefix):
				defs.append(_library_def(source, best_tier, level))
	else:
		for entry in ItemRoller._pool_for(item):
			defs.append(_pool_def(entry, best_tier, level))
	return defs

static func _pool_def(entry: Dictionary, best_tier: int, level: int = 100) -> ModifierDef:
	var levelled := ItemRoller.has_levelled_tiers(entry["stat_key"])
	var key := "pool:%s|%d" % [entry["stat_key"], ItemRoller.levelled_tiers_for(entry["stat_key"], level).size() if levelled else best_tier]
	if _cache.has(key):
		return _cache[key]
	var def := ModifierDef.new()
	def.id = StringName(entry["stat_key"])
	def.group = StringName(StatKeys.canonical(entry["stat_key"]))  # one modifier per stat
	def.stat_key = entry["stat_key"]
	def.text = entry["desc"]
	def.affix_type = ModifierDef.AffixType.SUFFIX if _is_suffix(entry["stat_key"]) else ModifierDef.AffixType.PREFIX
	def.tags = _tags(entry["brand_tags"], entry["stat_key"])
	def.tiers = _levelled_tiers(entry["stat_key"], level) if levelled else _tiers(entry["tier1_min"], entry["tier1_max"], best_tier)
	_cache[key] = def
	return def

static func _library_def(source: ItemAffix, best_tier: int, level: int) -> ModifierDef:
	best_tier = ItemRoller.best_tier_for_level(level, ItemRoller.TIER_COUNT, ItemRoller.top_level_of(source))
	var id := source.affix_id if source.affix_id != "" else source.stat_key
	var levelled := ItemRoller.has_levelled_tiers(source.stat_key)
	var key := "lib:%s|%d" % [id, ItemRoller.levelled_tiers_for(source.stat_key, level).size() if levelled else best_tier]
	if _cache.has(key):
		return _cache[key]
	var def := ModifierDef.new()
	def.id = StringName(id)
	def.group = StringName(StatKeys.canonical(source.stat_key))  # one modifier per stat
	def.stat_key = source.stat_key
	def.text = source.description
	def.affix_type = ModifierDef.AffixType.PREFIX if source.is_prefix else ModifierDef.AffixType.SUFFIX
	var tags: Array = []
	if source.damage_type != -1:
		tags.append(Constants.DAMAGE_TYPE_NAME.get(source.damage_type, "").to_lower())
	def.tags = _tags(tags, source.stat_key)
	def.tiers = _levelled_tiers(source.stat_key, level) if levelled else _tiers(source.value_min, source.value_max, best_tier)
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
	for word in DERIVED_TAGS:
		if stat_key.contains(word):
			for tag in DERIVED_TAGS[word]:
				if not tags.has(tag):
					tags.append(tag)
	# Ailment lines follow the damage that causes the ailment.
	var ailment := stat_key.get_slice("_", stat_key.get_slice_count("_") - 1)
	if stat_key.contains("ailment") and StatusEffectComponent.AILMENT_DAMAGE_TYPES.has(ailment):
		for damage_type in StatusEffectComponent.AILMENT_DAMAGE_TYPES[ailment]:
			var tag := StringName(String(Constants.DAMAGE_TYPE_NAME[damage_type]).to_lower())
			if not tags.has(tag):
				tags.append(tag)
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

## A LEVELLED_TIERS modifier's tiers the level allows; the best is rarest.
static func _levelled_tiers(stat_key: String, level: int) -> Array[ModifierTier]:
	var table := ItemRoller.levelled_table(stat_key)
	var rows := ItemRoller.levelled_tiers_for(stat_key, level)
	if rows.is_empty():
		rows = [table[-1]]
	var tiers: Array[ModifierTier] = []
	for i in rows.size():
		var tier := ModifierTier.new()
		tier.tier = table.find(rows[i]) + 1
		tier.value_min = rows[i][1]
		tier.value_max = rows[i][2]
		tier.weight = i + 1
		tiers.append(tier)
	return tiers
