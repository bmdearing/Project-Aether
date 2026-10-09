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
	"flat_life", "flat_mana", "life_regen_flat", "mana_regen",
	"flat_armor", "flat_evasion", "flat_ward",
	"increased_physical_damage", "increased_spell_damage", "elemental_dmg_increased", "esoteric_dmg_increased",
	"increased_area_damage", "dot_multiplier",
	"fire_resistance", "cold_resistance", "lightning_resistance", "esoteric_resistance",
	"attack_speed", "cast_speed", "move_speed", "increased_attack_damage",
	"crit_chance_increased", "crit_damage_increased",
	"increased_aoe_radius", "skill_effect_duration",
	"item_rarity", "magic_find",
	"ailment_chance_bleed", "ailment_chance_ignite", "ailment_chance_chill", "ailment_chance_electrocute",
	"ailment_chance_shock", "ailment_chance_aetherburn", "ailment_chance_unraveling", "ailment_chance_pallid",
	"increased_ailment_damage_bleed", "increased_ailment_damage_ignite", "increased_ailment_damage_chill",
	"increased_ailment_damage_electrocute", "increased_ailment_damage_shock", "increased_ailment_damage_aetherburn",
	"increased_ailment_damage_unraveling", "increased_ailment_damage_pallid",
]

## Jewel-only lines with their own Tier 1 range (taken as is, not scaled by
## VALUE_SCALE). Where a key is also in STAT_KEYS, this range replaces it.
const OWN_RANGES := [
	{"stat_key": "increased_attack_damage", "tier1_min": 34.0, "tier1_max": 40.0, "desc": "+%d%% increased Weapon Damage", "brand_tags": ["kinetic", "piercing", "explosive"]},
	{"stat_key": "attack_speed", "tier1_min": 12.0, "tier1_max": 15.0, "desc": "+%d%% increased Attack Speed", "brand_tags": ["skills"]},
	{"stat_key": "crit_chance_increased", "tier1_min": 16.0, "tier1_max": 20.0, "desc": "+%d%% increased Critical Strike Chance", "brand_tags": []},
]

static var _cache: Dictionary = {}  # "<stat_key>|<best tier>" -> ModifierDef

## Tiers are gated by item level like gear (ItemRoller.tier_min_level()):
## Tier 3 from level 1, Tier 2 from 41, Tier 1 from 80.
static func best_tier_for(item_level: int) -> int:
	return ItemRoller.best_tier_for_level(maxi(item_level, 1), TIER_COUNT)

static func defs_for(jewel: Item) -> Array[ModifierDef]:
	var best_tier := best_tier_for(jewel.item_level)
	var defs: Array[ModifierDef] = []
	var own_keys := OWN_RANGES.map(func(e: Dictionary) -> String: return e["stat_key"])
	for entry in ItemRoller.AFFIX_POOL:
		if STAT_KEYS.has(entry["stat_key"]) and not own_keys.has(entry["stat_key"]):
			defs.append(_def_for(entry, best_tier, VALUE_SCALE))
	for entry in OWN_RANGES:
		defs.append(_def_for(entry, best_tier, 1.0))
	return defs

static func tier_range(tier1_min: float, tier1_max: float, tier: int, value_scale: float = VALUE_SCALE) -> Vector2:
	var scale: float = value_scale * pow(TIER_DECAY, tier - 1)
	return Vector2(tier1_min * scale, tier1_max * scale)

static func _def_for(entry: Dictionary, best_tier: int, value_scale: float) -> ModifierDef:
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
	def.item_types = [&"jewel", &"lens"]
	for t in range(best_tier, TIER_COUNT + 1):
		var range_ := tier_range(entry["tier1_min"], entry["tier1_max"], t, value_scale)
		var tier := ModifierTier.new()
		tier.tier = t
		tier.value_min = range_.x
		tier.value_max = range_.y
		tier.weight = TIER_WEIGHTS[t - 1]
		def.tiers.append(tier)
	_cache[key] = def
	return def
