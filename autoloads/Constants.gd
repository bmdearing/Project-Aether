extends Node
## Global constants and enums derived from Project Aether Master doc.
## Single source of truth for anything referenced across systems.

enum DamageCategory { PHYSICAL, ELEMENTAL, ESOTERIC }

enum DamageType {
	KINETIC, PIERCING, EXPLOSIVE,      # Physical
	FIRE, COLD, LIGHTNING,             # Elemental
	AETHERIC, ENTROPIC, PALE           # Esoteric
}

const DAMAGE_TYPE_CATEGORY := {
	DamageType.KINETIC: DamageCategory.PHYSICAL,
	DamageType.PIERCING: DamageCategory.PHYSICAL,
	DamageType.EXPLOSIVE: DamageCategory.PHYSICAL,
	DamageType.FIRE: DamageCategory.ELEMENTAL,
	DamageType.COLD: DamageCategory.ELEMENTAL,
	DamageType.LIGHTNING: DamageCategory.ELEMENTAL,
	DamageType.AETHERIC: DamageCategory.ESOTERIC,
	DamageType.ENTROPIC: DamageCategory.ESOTERIC,
	DamageType.PALE: DamageCategory.ESOTERIC,
}

# Damage type display names and UI colors.
const DAMAGE_TYPE_NAME := {
	DamageType.KINETIC: "Kinetic",
	DamageType.PIERCING: "Piercing",
	DamageType.EXPLOSIVE: "Explosive",
	DamageType.FIRE: "Fire",
	DamageType.COLD: "Cold",
	DamageType.LIGHTNING: "Lightning",
	DamageType.AETHERIC: "Aetheric",
	DamageType.ENTROPIC: "Entropic",
	DamageType.PALE: "Pale",
}

const DAMAGE_TYPE_COLOR := {
	DamageType.KINETIC: Color(0.55, 0.55, 0.58),
	DamageType.PIERCING: Color(0.75, 0.75, 0.8),
	DamageType.EXPLOSIVE: Color(0.85, 0.55, 0.15),
	DamageType.FIRE: Color(0.75, 0.15, 0.1),
	DamageType.COLD: Color(0.6, 0.85, 0.95),
	DamageType.LIGHTNING: Color(0.9, 0.85, 0.2),
	DamageType.AETHERIC: Color(0.3, 0.6, 0.65),
	DamageType.ENTROPIC: Color(0.35, 0.15, 0.45),
	DamageType.PALE: Color(0.85, 0.83, 0.75),
}

## Lowercase tag string -> DamageType. Non-damage tags ("spell", "attack",
## "generic") are intentionally absent.
const DAMAGE_TYPE_TAGS := {
	"kinetic": DamageType.KINETIC,
	"piercing": DamageType.PIERCING,
	"explosive": DamageType.EXPLOSIVE,
	"fire": DamageType.FIRE,
	"cold": DamageType.COLD,
	"lightning": DamageType.LIGHTNING,
	"aetheric": DamageType.AETHERIC,
	"entropic": DamageType.ENTROPIC,
	"pale": DamageType.PALE,
}

## Strength scales weapon damage and Intellect spell power, regardless of
## damage type. Pre-v4.8 names (Prowess/Finesse/Resolve) are migrated on
## load by ItemSerializer.
enum Stat { STRENGTH, AGILITY, INTELLECT }

const STAT_NAME := {
	Stat.STRENGTH: "Strength",
	Stat.AGILITY: "Agility",
	Stat.INTELLECT: "Intellect",
}

# Per-point effects shown in the Alt-hover tooltip (formulas live in StatSheet).
const STAT_GLOSSARY := {
	Stat.STRENGTH: "+1% increased Weapon Damage, +4 Life per point.",
	Stat.AGILITY: "+1% increased Attack Speed, +1% increased Evasion, +1% increased Critical Strike Chance per point.",
	Stat.INTELLECT: "+1% increased Spell Damage, +3 Mana, +1% increased Ward per point.",
}

# Status effect -> damage type, used for its color.
const STATUS_EFFECT_DAMAGE_TYPE := {
	"ignite": DamageType.FIRE,
	"chill": DamageType.COLD,
	"freeze": DamageType.COLD,
	"electrocute": DamageType.LIGHTNING,
	"unraveling": DamageType.ENTROPIC,
	"slow": DamageType.PIERCING,  # Caltrops
	"shock": DamageType.LIGHTNING,
	"scorch": DamageType.FIRE,
	"aetherburn": DamageType.AETHERIC,
	"pallid": DamageType.PALE,
	"forbidden_fire": DamageType.ENTROPIC,
}

## The two physical crafting items left after Crafting Rev 3 (everything else
## is a Siphon craft paid in residue). Stackable currency.
const CRAFTING_CONSUMABLE_IDS := ["tempering", "shard_of_tharsis"]
## Crafting currency removed by Rev 3. Old saves refund residue for each one
## (Constants.LEGACY_CURRENCY_REFUND); see GridInventory.strip_legacy_currency().
const LEGACY_CURRENCY_IDS := ["quickening", "grafting", "elevation", "forging", "ascendant", "recasting",
	"severance", "absolution", "anchoring", "opening", "reckoning", "infusion_stone", "shrivening_stone"]
static func is_legacy_currency(id: String) -> bool:
	return LEGACY_CURRENCY_IDS.has(id) or id.begins_with("brand_") or id.begins_with("edict_")

## Every reserve is unlimited (AmmoInventory); ARROW weapons also have no
## magazine. THROWN: throwing weapons.
enum AmmoType { PISTOL, REVOLVER, SHOTGUN, RIFLE, AUTOMATIC, CROSSBOW_BOLT, ARROW, THROWN }

## SEMI_AUTO: one shot per click. FULL_AUTO: fires while held (Weapon.
## fire_rate). BOLT/LEVER/PUMP_ACTION and SINGLE_ACTION (revolver hammer,
## crossbow): a Weapon.cycle_time delay between shots.
enum FireMode { SEMI_AUTO, FULL_AUTO, BOLT_ACTION, LEVER_ACTION, PUMP_ACTION, SINGLE_ACTION }

## Hard socket ceiling per item category (ItemRoller.get_socket_category()).
## Bases are never raised to it; only Corruption's +1 can exceed it.
const MAX_SOCKETS_BY_CATEGORY := {
	"one_handed_melee": 3,
	"two_handed_melee": 6,
	"one_handed_ranged": 3,   # pistols, revolvers, machine pistols
	"two_handed_ranged": 6,   # rifles, bows, shotguns, SMG, machine gun
	"conduit_main_hand": 3,
	"conduit_two_handed": 6,  # staves, like other two-handed weapons
	"conduit_offhand": 3,
	"shield": 3,
	"body_armour": 4,
	"helmet": 3,
	"gloves": 2,
	"boots": 2,
	"ring": 1,
	"amulet": 2,
	"belt": 2,
}

const STATUS_EFFECT_NAME := {
	"ignite": "Ignite",
	"chill": "Chill",
	"freeze": "Freeze",
	"electrocute": "Electrocute",
	"unraveling": "Unraveling",
	"slow": "Slowed",
	"intimidated": "Intimidated",
	"shock": "Shocked",
	"scorch": "Scorched",
	"guard_break": "Guard Broken",
	"stun": "Stunned",
	"bleed": "Bleeding",
	"armor_shred": "Armor Shred",
	"entangle": "Entangled",
	"suppressed": "Suppressed",
	"marked": "Marked",
	"pallid": "Pallid",
	"aetherburn": "Aetherburn",
	"meager": "Meager",
	"fracturing": "Fracturing",
	"decompose": "Decompose",
	"elemental_fragility": "Elemental Fragility",
	"linger": "Linger",
	"forbidden_fire": "Forbidden Fire",
	"steadfast": "Steadfast",
	"drenched": "Drenched",
	"stone_skin": "Stone Skin",
	"punctured": "Punctured",
	"arach_mark": "Mark of Arach",
}

# Thematic stat per damage type (SlateRoller's Main Stat line). Damage
# scaling doesn't use it.
const DAMAGE_TYPE_MAIN_STAT := {
	DamageType.KINETIC: Stat.STRENGTH,
	DamageType.PIERCING: Stat.STRENGTH,
	DamageType.EXPLOSIVE: Stat.STRENGTH,
	DamageType.FIRE: Stat.INTELLECT,
	DamageType.COLD: Stat.INTELLECT,
	DamageType.LIGHTNING: Stat.INTELLECT,
	DamageType.AETHERIC: Stat.INTELLECT,
	DamageType.ENTROPIC: Stat.INTELLECT,
	DamageType.PALE: Stat.INTELLECT,
}


# Chain Bonus System - Section 10. Tuple: (tile_range_start, tile_range_end, bonus_per_tile)
# v5.7.0: reversed (was 1% / 0.75% / 0.5% / 0.25%) so big late chains pay
# most and small early boards less.
const CHAIN_BONUS_TIERS := [
	{"min": 1, "max": 20, "per_tile": 0.0025},
	{"min": 21, "max": 40, "per_tile": 0.005},
	{"min": 41, "max": 60, "per_tile": 0.0075},
	{"min": 61, "max": 999999, "per_tile": 0.010},
]
## Mastery: every Slate tile of a damage type gives this much more damage of
## that type, times (1 + the Chain Bonus of the chain it's in).
const MASTERY_PER_TILE := 0.002

enum SlateRarity { COMMON, UNCOMMON, RARE, VERY_RARE, UNIQUE, MYTHIC }

# ITEM_RARITY_COLOR's palette plus violet for VERY_RARE.
const SLATE_RARITY_COLOR := {
	SlateRarity.COMMON: Color(0.9, 0.9, 0.9),
	SlateRarity.UNCOMMON: Color(0.3, 0.55, 0.95),
	SlateRarity.RARE: Color(0.95, 0.85, 0.2),
	SlateRarity.VERY_RARE: Color(0.7, 0.4, 0.9),
	SlateRarity.UNIQUE: Color(0.9, 0.55, 0.15),
	SlateRarity.MYTHIC: Color(0.98, 0.75, 0.75),
}

# OFFHAND holds a Shield or an offhand Weapon. Values are explicit because
# .tres files store equip_slot as a raw int - never renumber (5/7/8 are
# retired slots).
enum EquipmentSlot {
	HELMET = 0, BODY_ARMOUR = 1, GLOVES = 2, BOOTS = 3,
	PRIMARY_WEAPON = 4, OFFHAND = 6,
	AMULET = 9, BELT = 10, RING = 11,
}

enum ItemRarity { COMMON, UNCOMMON, RARE, UNIQUE, MYTHIC }

# White/Blue/Yellow/Orange/Peach.
const ITEM_RARITY_COLOR := {
	ItemRarity.COMMON: Color(0.9, 0.9, 0.9),
	ItemRarity.UNCOMMON: Color(0.3, 0.55, 0.95),
	ItemRarity.RARE: Color(0.95, 0.85, 0.2),
	ItemRarity.UNIQUE: Color(0.9, 0.55, 0.15),
	ItemRarity.MYTHIC: Color(0.98, 0.75, 0.75),
}
## Monster Infrequents (items with a perk) show green over their rarity colour.
const MONSTER_INFREQUENT_COLOR := Color(0.3, 0.85, 0.35)

# Base crit chance keyed by Weapon.weapon_type; unlisted types (e.g. Bow)
# use DEFAULT_BASE_CRIT_CHANCE.
const WEAPON_BASE_CRIT_CHANCE := {
	"Dagger": 0.08,
	"Rapier": 0.07,
	"Shortsword": 0.06,
	"Saber": 0.06,
	"Katana": 0.07,
	"Cutlass": 0.05,
	"Mace": 0.03,
	"War Pick": 0.04,
	"Greatsword": 0.04,
	"Claymore": 0.04,
	"Greataxe": 0.05,
	"Halberd": 0.05,
	"Spear": 0.06,
	"Shock Lance": 0.05,
	"Whip": 0.04,
	"Pressure Fist": 0.03,
	"Service Pistol": 0.06,
	"Revolver": 0.07,
	"Machine Pistol": 0.03,
	"Crossbow": 0.08,
	"Throwing Knife": 0.07,
	"Throwing Axe": 0.05,
	"Javelin": 0.06,
	"Grenade": 0.02,
	"Bolt Action Rifle": 0.08,
	"Lever Action Rifle": 0.07,
	"Loaded Shotgun": 0.03,
	"Pump Action Shotgun": 0.03,
	"Battle Rifle": 0.05,
	"Submachine Gun": 0.03,
	"Machine Gun": 0.02,
	"Wand": 0.06,
	"Staff": 0.04,
	"Gauntlet": 0.06,
}
const DEFAULT_BASE_CRIT_CHANCE := 0.05

## Enemy rank: boss or not, set by boss scenes. BOSS keeps value 3 so
## scenes saved with the old four-rank enum still load as bosses.
enum EnemyRank { NORMAL, BOSS = 3 }

## Rarity drives stat multipliers, affixes, auras, drop rolls, drop item
## level and Aether drops.
enum EnemyRarity { NORMAL, ELITE, CHAMPION, ASCENDANT }

const ENEMY_RARITY_NAME := {
	EnemyRarity.NORMAL: "Normal",
	EnemyRarity.ELITE: "Elite",
	EnemyRarity.CHAMPION: "Champion",
	EnemyRarity.ASCENDANT: "Ascendant",
}

const ENEMY_RARITY_NAME_COLOR := {
	EnemyRarity.NORMAL: Color.WHITE,
	EnemyRarity.ELITE: Color(0.4, 0.6, 1.0),
	EnemyRarity.CHAMPION: Color(1.0, 0.85, 0.0),
	EnemyRarity.ASCENDANT: Color(1.0, 0.5, 0.0),
}

## Placeholder health/damage multipliers; NORMAL is absent (no scaling).
const ENEMY_RARITY_HEALTH_MULT := {
	EnemyRarity.ELITE: 1.5,
	EnemyRarity.CHAMPION: 3.0,
	EnemyRarity.ASCENDANT: 3.0,  # on top of an elite-class unit (280 base Life), not a 55 Life brigand
}
const ENEMY_RARITY_DAMAGE_MULT := {
	EnemyRarity.ELITE: 1.2,
	EnemyRarity.CHAMPION: 1.6,
	EnemyRarity.ASCENDANT: 1.5,
}

## Level-1 monster stats per archetype_category. Monster level is the Area
## Level (or EnemyDefinition.mob_level outside one); the curves compound per
## level (AreaLevel.HEALTH_GROWTH / DAMAGE_GROWTH).
## v4.14 retune: a level-1 standard mob takes ~4 hits from the starter
## weapon (~14 per hit), a light one ~2, a heavy ~8.
## v5.3.1: monster damage x1.5 (bosses excepted); on-level hits were too safe.
## v5.6.1: light 7.5 -> 10, standard 13.5 -> 18; on-level hits were only 1.5-4% of Life.
const MOB_BASE_HEALTH := {
	"light": 30.0,
	"standard": 55.0,
	"heavy": 110.0,
	"elite": 280.0,
	"boss": 1600.0,
}
const MOB_BASE_DAMAGE := {
	"light": 10.0,
	"standard": 18.0,
	"heavy": 22.5,
	"elite": 36.0,
	"boss": 45.0,
}

## Rarity is rolled per pack (EnemyRarityComponent.roll_pack_rarity()):
## Elite = the whole pack, Champion = one leader, Ascendant = one of
## ASCENDANT_UNITS with up to ASCENDANT_ESCORTS Normal escorts.
const ENEMY_PACK_RARITY_WEIGHTS := {
	EnemyRarity.NORMAL: 70.0,
	EnemyRarity.ELITE: 20.0,
	EnemyRarity.CHAMPION: 8.0,
	EnemyRarity.ASCENDANT: 2.0,
}
const ASCENDANT_UNITS := ["synod_vindicator", "legion_dreadknight", "veilborne_cantor"]
const ASCENDANT_ESCORTS := 2

## Placeholder pack tables for GeneratedMap, rolled by EnemyRoster.roll_pack().
## Each unit entry is [unit_id or Array of unit_ids, min, max] - an Array
## picks a random id per unit. Unit ids are data/enemies/definitions/ files.
const UNCHARTERED_RAIDERS := ["unchartered_cutthroat", "unchartered_javelineer", "unchartered_brigand"]
const SYNOD_GOLEMS := ["synod_warden_golem", "synod_ember_golem", "synod_aether_golem"]
const ENEMY_PACKS_NORMAL := [
	{"weight": 1.0, "units": [["unchartered_brigand", 1, 1], ["unchartered_javelineer", 1, 2]]},
	{"weight": 1.0, "units": [["unchartered_enforcer", 1, 1], ["unchartered_cutthroat", 1, 2]]},
	{"weight": 1.0, "units": [[UNCHARTERED_RAIDERS, 2, 3]]},
	{"weight": 0.8, "units": [["hollowed_shambler", 3, 5]]},
	{"weight": 0.6, "units": [[SYNOD_GOLEMS, 1, 1], ["hollowed_shambler", 0, 2]]},
	{"weight": 0.6, "units": [["veilborne_mindbender", 2, 3]]},
]

# Combined cap across all cooldown reduction sources (Ability.get_final_cooldown()).
const MAX_COOLDOWN_REDUCTION := 0.75

## Cast Speed affix tiers (percent, T1 best), gated by item level.
const CAST_SPEED_TIERS := [
	{"min": 18.0, "max": 22.0, "item_level": 72},  # T1
	{"min": 14.0, "max": 17.0, "item_level": 56},  # T2
	{"min": 10.0, "max": 13.0, "item_level": 40},  # T3
	{"min": 6.0,  "max": 9.0,  "item_level": 24},  # T4
	{"min": 2.0,  "max": 5.0,  "item_level": 8},   # T5
]

## Dark or light text, whichever reads over bg.
static func get_contrasting_text_color(bg: Color) -> Color:
	var luminance := 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color(0.05, 0.05, 0.05) if luminance > 0.6 else Color(0.95, 0.95, 0.95)

## ---- Orb crafting (Crafting & Inventory Rev2) ----------------------------

## Max prefixes (x) / suffixes (y) per rarity. Unique/Mythic aren't Orb-craftable.
const AFFIX_LIMITS_GEAR := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}
## Rolling gear explicits are worth this much more now that items carry 4
## lines, not 6. ItemRoller.gear_line_scale() lists the exceptions.
const STAT_LINE_RESCALE := 1.4
## Jewels top out at Uncommon: one prefix and one suffix. The only Rare jewel
## is the rare uncraftable drop with two of each (JEWEL_GRAND_CHANCE).
const AFFIX_LIMITS_JEWEL := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}
const AFFIX_TOTAL_LIMITS_JEWEL := {
	ItemRarity.COMMON: 0,
	ItemRarity.UNCOMMON: 2,
	ItemRarity.RARE: 4,
}
## Share of jewel drops that come as a Rare with 4 modifiers that can't be crafted.
const JEWEL_GRAND_CHANCE := 0.01
const JEWEL_LINE_RESCALE := 1.3
## Lenses keep the old jewel limits (two prefixes, two suffixes).
const AFFIX_LIMITS_LENS := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}
const AFFIX_LIMITS_SLATE := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}

## ---- Residue & the Siphon (Crafting Rev 3, placeholders) --------------------
const RESIDUE_PER_KILL := {"light": 1, "standard": 2, "heavy": 3, "elite": 5, "boss": 40}
const RESIDUE_RARITY_MULT := {EnemyRarity.NORMAL: 1.0, EnemyRarity.ELITE: 2.0, EnemyRarity.CHAMPION: 4.0, EnemyRarity.ASCENDANT: 8.0}
const RESIDUE_BOSS_PER_KILL := 10
const RESIDUE_POOL_CAP := 8000
const RESIDUE_BOSS_POOL_CAP := 2000
const CRAFT_COST_GROWTH := 1.12
const CRAFT_COST_MULT_CAP := 10.0
const CRAFT_BASE_COST := {&"add": 40, &"recast": 60, &"bleed": 30, &"absolve": 20, &"settle": 50,
	&"anchor": 240, &"sockets": 80, &"retype": 120, &"restore_type": 40, &"vestige_add": 20}
const FORESIGHT_MAX_OUTCOMES := 4
const FORESIGHT_EXTRA_COST := 0.25
## A craft aimed at a family (add, recast, bleed, settle with one picked) costs
## this many times the unfocused price.
const CRAFT_FOCUS_COST_MULT := 2.0
## Old saves: each removed Orb, Brand, Edict or Stone refunds this to every regular pool.
const LEGACY_CURRENCY_REFUND := 5
## Family tag -> the pool that pays for crafts in it ("" = any regular pool).
const CRAFT_FAMILIES := {
	&"kinetic": &"residue_physical", &"piercing": &"residue_physical", &"explosive": &"residue_physical", &"armor": &"residue_physical",
	&"fire": &"residue_elemental", &"cold": &"residue_elemental", &"lightning": &"residue_elemental", &"evasion": &"residue_elemental",
	&"aetheric": &"residue_esoteric", &"entropic": &"residue_esoteric", &"pale": &"residue_esoteric", &"ward": &"residue_esoteric",
	&"life": &"", &"mana": &"", &"speed": &"", &"attack": &"", &"spell": &"", &"critical": &"",
	&"minion": &"", &"dot": &"", &"resistance": &"", &"resilience": &"",
	&"attributes": &"", &"area": &"", &"ailment": &"", &"block": &"", &"skill": &"", &"loot": &"",
}

const QUALITY_CAP := 25
## The "Tempered Limit" corruption outcome raises one item's quality cap by this much.
const CORRUPT_QUALITY_CAP_BONUS := 15
const TEMPERING_QUALITY_GAIN := Vector2i(2, 4)
const ANCHORING_MIN_MODIFIERS := 3
const MAX_ANCHORED_MODIFIERS := 1
## Slate size (tile count) -> best tier it may roll. Empty = no cap.
const SLATE_TIER_CAP_BY_SIZE := {}

## ---- Inventory & stash (placeholder sizes) -------------------------------
const INVENTORY_SIZE := Vector2i(14, 7)
const MAX_STACK := 100
const STASH_TAB_COUNT := 4
const STASH_TAB_SIZE := Vector2i(12, 12)
## The currency tab is shown as one slot per currency (CurrencyTabView); its
## grid is only storage, sized for many full stacks of each.
const STASH_CURRENCY_TAB_SIZE := Vector2i(30, 30)
const STASH_SLATE_TAB_SIZE := Vector2i(12, 12)
const STASH_FIGMENT_TAB_SIZE := Vector2i(12, 12)

## ---- Portals ---------------------------------------------------------------
## Portals per map run; -1 = unlimited.
const MAX_PORTALS := -1
## Placeholder Orb roll weight per gear tier (index 0 = Tier 1, the rarest).
const GEAR_TIER_WEIGHTS: Array[int] = [2, 4, 10, 20, 30, 36]
## Placeholder Orb roll weight per Slate tier (index 0 = Tier 1).
const SLATE_TIER_WEIGHTS: Array[int] = [10, 30, 60]

## Drop weights for the two physical crafting items (chests, secrets).
const CRAFTING_CONSUMABLE_WEIGHTS := {&"tempering": 85.0, &"shard_of_tharsis": 15.0}

static func roll_currency_drop(_item_level: int = 100) -> StringName:
	var roll := randf() * 100.0
	for id in CRAFTING_CONSUMABLE_WEIGHTS:
		roll -= CRAFTING_CONSUMABLE_WEIGHTS[id]
		if roll < 0:
			return id
	return &"tempering"
