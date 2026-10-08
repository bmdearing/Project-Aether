extends RefCounted
class_name JewelModifierPool
## The modifiers a Jewel can roll, used for drops (JewelRoller) and Orbs
## (GearModifierPool.defs_for() hands jewels here). A short list of global
## modifiers taken from ItemRoller.AFFIX_POOL, with fewer, tighter tiers
## than gear: Tier 1 is VALUE_SCALE of gear's Tier 1 and each tier keeps
## TIER_DECAY of the one above, so a jewel's worst roll still beats gear's
## worst tier.

const TIER_COUNT := 3
const TIER_DECAY := 0.9
const VALUE_SCALE := 0.6
## Roll weight per tier (index 0 = Tier 1).
const TIER_WEIGHTS: Array[int] = [15, 35, 50]

const STAT_KEYS := [
	"flat_strength", "flat_agility", "flat_intellect",
	"max_life", "max_mana", "life_regen", "mana_regen",
	"flat_armor", "flat_evasion", "flat_ward",
	"increased_physical_damage", "increased_spell_damage", "elemental_dmg_increased", "esoteric_dmg_increased",
	"increased_area_damage", "dot_multiplier",
	"fire_resistance_pct", "cold_resistance_pct", "lightning_resistance_pct", "esoteric_resistance_pct",
	"attack_speed", "cast_speed", "move_speed",
	"crit_chance_increased", "crit_damage_increased",
	"increased_aoe_radius", "skill_effect_duration",
	"item_rarity", "magic_find",
	"ailment_chance_bleed", "ailment_chance_ignite", "ailment_chance_chill", "ailment_chance_electrocute",
	"ailment_chance_shock", "ailment_chance_aetherburn", "ailment_chance_unraveling", "ailment_chance_pallid",
	"increased_ailment_damage_bleed", "increased_ailment_damage_ignite", "increased_ailment_damage_chill",
	"increased_ailment_damage_electrocute", "increased_ailment_damage_shock", "increased_ailment_damage_aetherburn",
	"increased_ailment_damage_unraveling", "increased_ailment_damage_pallid",
]

static var _cache: Dictionary = {}  # "<stat_key>|<best tier>" -> ModifierDef

## Low item levels can't reach the best tiers: level 1 rolls Tier 3 only,
## level 3 and up reaches Tier 1.
static func best_tier_for(item_level: int) -> int:
	return clampi(TIER_COUNT + 1 - maxi(item_level, 1), 1, TIER_COUNT)

static func defs_for(jewel: Item) -> Array[ModifierDef]:
	var best_tier := best_tier_for(jewel.item_level)
	var defs: Array[ModifierDef] = []
	for entry in ItemRoller.AFFIX_POOL:
		if STAT_KEYS.has(entry["stat_key"]):
			defs.append(_def_for(entry, best_tier))
	return defs

static func tier_range(tier1_min: float, tier1_max: float, tier: int) -> Vector2:
	var scale: float = VALUE_SCALE * pow(TIER_DECAY, tier - 1)
	return Vector2(tier1_min * scale, tier1_max * scale)

static func _def_for(entry: Dictionary, best_tier: int) -> ModifierDef:
	var key := "%s|%d" % [entry["stat_key"], best_tier]
	if _cache.has(key):
		return _cache[key]
	var def := ModifierDef.new()
	def.id = StringName(entry["stat_key"])
	def.group = def.id
	def.stat_key = entry["stat_key"]
	def.text = entry["desc"]
	def.affix_type = ModifierDef.AffixType.SUFFIX if GearModifierPool._is_suffix(entry["stat_key"]) else ModifierDef.AffixType.PREFIX
	def.tags = GearModifierPool._tags(entry["brand_tags"], entry["stat_key"])
	def.item_types = [&"jewel"]
	for t in range(best_tier, TIER_COUNT + 1):
		var range_ := tier_range(entry["tier1_min"], entry["tier1_max"], t)
		var tier := ModifierTier.new()
		tier.tier = t
		tier.value_min = range_.x
		tier.value_max = range_.y
		tier.weight = TIER_WEIGHTS[t - 1]
		def.tiers.append(tier)
	_cache[key] = def
	return def
