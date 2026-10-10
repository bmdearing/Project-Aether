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
}

## Stackable crafting currency, held like the Orbs. Older saves held them as
## Items; GridInventory converts those on load.
const CRAFTING_CONSUMABLE_IDS := ["infusion_stone", "shrivening_stone", "shard_of_tharsis"]

## ARROW is infinite (never tracked or dropped); the rest have a reserve in
## the AmmoInventory autoload.
enum AmmoType { PISTOL, REVOLVER, SHOTGUN, RIFLE, AUTOMATIC, CROSSBOW_BOLT, ARROW }

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

## Ammo pickup Item ids (data/consumables/instances/) - see AmmoPack.
const AMMO_TYPE_PICKUP_ID := {
	AmmoType.PISTOL: "ammo_pistol",
	AmmoType.REVOLVER: "ammo_revolver",
	AmmoType.SHOTGUN: "ammo_shotgun",
	AmmoType.RIFLE: "ammo_rifle",
	AmmoType.AUTOMATIC: "ammo_automatic",
	AmmoType.CROSSBOW_BOLT: "ammo_crossbow",
}

## Placeholder Gold per round at the Hub AmmoStore.
const AMMO_ROUND_COST := {
	AmmoType.PISTOL: 1,
	AmmoType.AUTOMATIC: 1,
	AmmoType.REVOLVER: 2,
	AmmoType.CROSSBOW_BOLT: 2,
	AmmoType.SHOTGUN: 3,
	AmmoType.RIFLE: 3,
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

enum ScalingGrade { S, A, B, C, D, E }

# Spell quality multiplier ranges (min, max); weapons ignore grade. B is
# roughly neutral.
const GRADE_MULTIPLIER_RANGES := {
	ScalingGrade.S: Vector2(1.4, 1.8),
	ScalingGrade.A: Vector2(1.1, 1.4),
	ScalingGrade.B: Vector2(0.85, 1.1),
	ScalingGrade.C: Vector2(0.65, 0.85),
	ScalingGrade.D: Vector2(0.45, 0.65),
	ScalingGrade.E: Vector2(0.25, 0.45),
}

# Chain Bonus System - Section 10. Tuple: (tile_range_start, tile_range_end, bonus_per_tile)
const CHAIN_BONUS_TIERS := [
	{"min": 1, "max": 20, "per_tile": 0.010},
	{"min": 21, "max": 40, "per_tile": 0.0075},
	{"min": 41, "max": 60, "per_tile": 0.005},
	{"min": 61, "max": 999999, "per_tile": 0.0025},
]

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

# Base crit chance keyed by Weapon.weapon_type; unlisted types (e.g. Bow)
# use DEFAULT_BASE_CRIT_CHANCE.
const WEAPON_BASE_CRIT_CHANCE := {
	"Dagger": 0.08,
	"Rapier": 0.07,
	"Shortsword": 0.06,
	"Saber": 0.06,
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

## Enemy rank: offsets the item level of drops. BOSS is never auto-rolled.
enum EnemyRank { NORMAL, MAGIC, RARE, BOSS }

const ENEMY_RANK_NAME := {
	EnemyRank.NORMAL: "White",
	EnemyRank.MAGIC: "Blue",
	EnemyRank.RARE: "Rare",
	EnemyRank.BOSS: "Boss",
}

const ENEMY_RANK_ITEM_LEVEL_OFFSET := {
	EnemyRank.NORMAL: 0,
	EnemyRank.MAGIC: 1,
	EnemyRank.RARE: 2,
	EnemyRank.BOSS: 5,
}

## Spawn odds per rank (Boss is only ever set explicitly).
const ENEMY_RANK_SPAWN_WEIGHTS := {
	EnemyRank.NORMAL: 80.0,
	EnemyRank.MAGIC: 16.0,
	EnemyRank.RARE: 4.0,
}

## Independent of EnemyRank: rarity drives stat multipliers, affixes,
## auras and drop conversion; rank drives drop item level.
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

## Mob level curve (EnemyDefinition.mob_level / archetype_category), invented
## placeholder values pending playtest balance:
##   health = MOB_BASE_HEALTH[category] * (1 + MOB_HEALTH_GROWTH_PER_LEVEL * (level - 1))
##   damage = MOB_BASE_DAMAGE[category] * (1 + MOB_DAMAGE_GROWTH_PER_LEVEL * (level - 1))
const MOB_HEALTH_GROWTH_PER_LEVEL := 0.15
const MOB_DAMAGE_GROWTH_PER_LEVEL := 0.08
## v4.14 retune: a level-1 standard mob takes ~4 hits from the starter
## weapon (~14 per hit), a light one ~2, a heavy ~8.
const MOB_BASE_HEALTH := {
	"light": 30.0,
	"standard": 55.0,
	"heavy": 110.0,
	"elite": 280.0,
	"boss": 1600.0,
}
const MOB_BASE_DAMAGE := {
	"light": 5.0,
	"standard": 9.0,
	"heavy": 15.0,
	"elite": 24.0,
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

static func grade_to_letter(grade: int) -> String:
	match grade:
		0: return "S"
		1: return "A"
		2: return "B"
		3: return "C"
		4: return "D"
		5: return "E"
	return "?"

## Dark or light text, whichever reads over bg.
static func get_contrasting_text_color(bg: Color) -> Color:
	var luminance := 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color(0.05, 0.05, 0.05) if luminance > 0.6 else Color(0.95, 0.95, 0.95)

## ---- Orb crafting (Crafting & Inventory Rev2) ----------------------------

## Max prefixes (x) / suffixes (y) per rarity. Unique/Mythic aren't Orb-craftable.
const AFFIX_LIMITS_GEAR := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(3, 3),
}
## Jewels: up to two prefixes and two suffixes.
const AFFIX_LIMITS_JEWEL := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}
const AFFIX_LIMITS_SLATE := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(2, 2),
}

const ORB_IDS: Array[StringName] = [
	&"quickening", &"grafting", &"elevation", &"forging", &"ascendant", &"recasting",
	&"severance", &"absolution", &"anchoring", &"tempering", &"opening", &"reckoning",
]

## Placeholder tolerance cost per Orb use, rolled uniformly in [x, y].
const TOLERANCE_COST := {
	&"quickening": Vector2i(2, 4),
	&"grafting": Vector2i(3, 6),
	&"elevation": Vector2i(4, 8),
	&"forging": Vector2i(10, 16),
	&"ascendant": Vector2i(6, 10),
	&"recasting": Vector2i(6, 12),
	&"severance": Vector2i(3, 6),
	&"absolution": Vector2i(8, 14),
	&"anchoring": Vector2i(10, 18),
	&"tempering": Vector2i(1, 3),
	&"opening": Vector2i(4, 8),
	&"reckoning": Vector2i(4, 8),
}

## Placeholder starting tolerance range by item type (Item.get_item_type()),
## falling back to the default.
const STARTING_TOLERANCE_DEFAULT := Vector2i(40, 60)
const STARTING_TOLERANCE_BY_ITEM_TYPE := {
	&"slate": Vector2i(30, 50),
}

const QUALITY_CAP := 20
const TEMPERING_QUALITY_GAIN := Vector2i(2, 4)
const FORGING_MODIFIERS_GEAR := 4
const FORGING_MODIFIERS_SLATE := Vector2i(3, 4)
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
const GEAR_TIER_WEIGHTS: Array[int] = [4, 10, 20, 30, 36]
## Placeholder Orb roll weight per Slate tier (index 0 = Tier 1).
const SLATE_TIER_WEIGHTS: Array[int] = [10, 30, 60]

## Placeholder drop weights for crafting currency (Enemy._maybe_drop_loot()).
const CURRENCY_DROP_WEIGHTS := {
	&"quickening": 120, &"grafting": 100, &"severance": 60, &"reckoning": 50, &"tempering": 60,
	&"elevation": 40, &"recasting": 35, &"ascendant": 25, &"absolution": 20, &"opening": 20,
	&"forging": 10, &"anchoring": 6,
	&"brand_kinetic": 12, &"brand_piercing": 12, &"brand_explosive": 12, &"brand_fire": 12,
	&"brand_cold": 12, &"brand_lightning": 12, &"brand_aetheric": 12, &"brand_entropic": 12,
	&"brand_pale": 12, &"brand_armor": 12, &"brand_evasion": 12, &"brand_ward": 12,
	&"brand_resistance": 12, &"brand_resilience": 12, &"brand_mana": 12, &"brand_spell": 12,
	&"brand_attack": 12, &"brand_speed": 12, &"brand_life": 12, &"brand_critical": 12, &"brand_minion": 10,
	&"brand_prefix": 10, &"brand_suffix": 10,
	&"brand_preservation": 3,
	&"edict_prefix": 6, &"edict_suffix": 6, &"edict_spell": 6, &"edict_attack": 6,
}

static func roll_currency_drop() -> StringName:
	var total := 0
	for w in CURRENCY_DROP_WEIGHTS.values():
		total += w
	var roll := randi_range(0, total - 1)
	for id in CURRENCY_DROP_WEIGHTS:
		roll -= CURRENCY_DROP_WEIGHTS[id]
		if roll < 0:
			return id
	return &"quickening"
