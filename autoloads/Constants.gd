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

# Damage type display name + color, for UI (Fate Board grid, etc). Colors
# reuse the Gem palette from Section 15 (Jarne/Silfre/Raffe/Eldre/Ise/Leikre/
# Aedre/Rotne/Folre) so tag color language stays consistent across systems.
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

enum Stat { VITALITY, STRENGTH, INSTINCT, ARCANE, ENIGMA, INTELLECT }

# Display names - used by ItemCard's requirement line and EquipmentComponent's
# equip-block reason (user request 2026-08-30: gate Section 25's items behind
# a level + stat requirement) rather than each spot inventing its own
# capitalization of the enum key.
const STAT_NAME := {
	Stat.VITALITY: "Vitality",
	Stat.STRENGTH: "Strength",
	Stat.INSTINCT: "Instinct",
	Stat.ARCANE: "Arcane",
	Stat.ENIGMA: "Enigma",
	Stat.INTELLECT: "Intellect",
}

# Section 12 per-point values - shown in the advanced (Alt-hover) tooltip
# when a mod line links to one of these stats.
const STAT_GLOSSARY := {
	Stat.VITALITY: "+2 Life, +0.1 Life regen/sec, +3 Resilience (DoT mitigation) per point.",
	Stat.STRENGTH: "+1% increased Physical damage per point.",
	Stat.INSTINCT: "+3% increased Crit Chance, +1% Attack/Cast speed, +0.5% Move speed per point.",
	Stat.ARCANE: "+1% increased Elemental damage per point.",
	Stat.ENIGMA: "+1% increased Esoteric damage per point.",
	Stat.INTELLECT: "+1% increased Crit damage, +2 Mana, +0.1 Mana regen/sec, +1.5% Debuff effectiveness per point.",
}

# Section 09 - Status Effects. Scope: the 5 effects that already have a
# real applier in this project (Ability.applies_status_effects on the
# elemental/esoteric spells) - Bleed/Armor Shred/Stagger-Stun (Physical
# family, no weapon-side proc mechanic exists) and Scorch/Aetherburn/
# Pallid (no Fire-channel/Aetheric/Pale ability exists yet) are left for
# StatusEffectComponent to grow into once a real source exists (flagged
# in README). Blind is explicitly deferred in the patch doc itself, not
# just by this project, so it's not modeled at all.
const STATUS_EFFECT_DAMAGE_TYPE := {
	"ignite": DamageType.FIRE,
	"chill": DamageType.COLD,
	"freeze": DamageType.COLD,
	"electrocute": DamageType.LIGHTNING,
	"unraveling": DamageType.ENTROPIC,
	"slow": DamageType.PIERCING,  # Caltrops - a generic slow independent of Chill's Cold flavor, colored via its own Piercing source instead
}

## Section 20's Infusion Stone/Shrivening Stone/Shard of Tharsis - fixed,
## non-Brand crafting items (see data/consumables/instances/). Shared by
## Enemy.gd (loot drop), CraftingScreen.gd (their own action buttons),
## and InventoryScreen.gd (excluded from equip-on-click) so the 3 ids
## live in exactly one place.
const CRAFTING_CONSUMABLE_IDS := ["infusion_stone", "shrivening_stone", "shard_of_tharsis"]

const STATUS_EFFECT_NAME := {
	"ignite": "Ignite",
	"chill": "Chill",
	"freeze": "Freeze",
	"electrocute": "Electrocute",
	"unraveling": "Unraveling",
	"slow": "Slowed",
}

# Section 10 - Main Stat by Tag. Drives which stat DamageCalculator scales
# an attack against, keyed by the attack's damage type.
const DAMAGE_TYPE_MAIN_STAT := {
	DamageType.KINETIC: Stat.STRENGTH,
	DamageType.PIERCING: Stat.STRENGTH,
	DamageType.EXPLOSIVE: Stat.STRENGTH,
	DamageType.FIRE: Stat.ARCANE,
	DamageType.COLD: Stat.ARCANE,
	DamageType.LIGHTNING: Stat.ARCANE,
	DamageType.AETHERIC: Stat.ENIGMA,
	DamageType.ENTROPIC: Stat.ENIGMA,
	DamageType.PALE: Stat.ENIGMA,
}

enum ScalingGrade { S, A, B, C, D, E }

# Base scaling ranges (min, max) as decimal fractions of stat value. Section 11.
const SCALING_RANGES := {
	ScalingGrade.S: Vector2(1.50, 2.00),
	ScalingGrade.A: Vector2(1.06, 1.49),
	ScalingGrade.B: Vector2(0.76, 1.05),
	ScalingGrade.C: Vector2(0.56, 0.75),
	ScalingGrade.D: Vector2(0.36, 0.55),
	ScalingGrade.E: Vector2(0.20, 0.35),
}

# Chain Bonus System - Section 10. Tuple: (tile_range_start, tile_range_end, bonus_per_tile)
const CHAIN_BONUS_TIERS := [
	{"min": 1, "max": 20, "per_tile": 0.010},
	{"min": 21, "max": 40, "per_tile": 0.0075},
	{"min": 41, "max": 60, "per_tile": 0.005},
	{"min": 61, "max": 999999, "per_tile": 0.0025},
]

enum SlateRarity { COMMON, UNCOMMON, RARE, VERY_RARE, UNIQUE, MYTHIC }

# No doc-sourced color for SlateRarity - reuses ITEM_RARITY_COLOR's palette,
# plus an invented violet for the extra VERY_RARE tier. Placeholder, flagged in README.
const SLATE_RARITY_COLOR := {
	SlateRarity.COMMON: Color(0.9, 0.9, 0.9),
	SlateRarity.UNCOMMON: Color(0.3, 0.55, 0.95),
	SlateRarity.RARE: Color(0.95, 0.85, 0.2),
	SlateRarity.VERY_RARE: Color(0.7, 0.4, 0.9),
	SlateRarity.UNIQUE: Color(0.9, 0.55, 0.15),
	SlateRarity.MYTHIC: Color(0.98, 0.75, 0.75),
}

enum EnemyArchetype { GLASS_CANNON, MOBILE_BRUISER, HEAVY_HITTER }

# Section 13 - Equipment Slots. OFFHAND covers a Shield in the offhand slot.
enum EquipmentSlot {
	HELMET, BODY_ARMOUR, GLOVES, BOOTS,
	PRIMARY_WEAPON, SIDEARM_WEAPON, OFFHAND, CONDUIT, SECONDARY_THROWABLE,
	AMULET, BELT, RING,
}

# Section 18 - Item Rarity & Affixes. Distinct scale from SlateRarity above
# (that one's 6-tier and Slate-specific per Section 10).
enum ItemRarity { COMMON, UNCOMMON, RARE, UNIQUE, MYTHIC }

# Section 18's rarity color column (White/Blue/Yellow/Orange/Peach) - used
# for items with no damage-type identity of their own to key a color off of
# (e.g. a Shield, which isn't tied to one of the 9 damage types).
const ITEM_RARITY_COLOR := {
	ItemRarity.COMMON: Color(0.9, 0.9, 0.9),
	ItemRarity.UNCOMMON: Color(0.3, 0.55, 0.95),
	ItemRarity.RARE: Color(0.95, 0.85, 0.2),
	ItemRarity.UNIQUE: Color(0.9, 0.55, 0.15),
	ItemRarity.MYTHIC: Color(0.98, 0.75, 0.75),
}

# Section 11 "Base Crit Chance by Weapon Type", keyed by Weapon.weapon_type.
# Doc-exact for every weapon type Section 25 actually details a real tiered
# line for (see tools/generate_base_types.gd) - the doc's table also lists
# several caster types (Rod/Focus/Tome/Talisman/Seal/Charm/Lantern/Spell
# Gauntlet/Athame/Grimoire/Fetish/Rail Carbine/Voltage Pistol/Pressurized
# Rifle/Thermal Pistol/Jet Rifle) that have no Section 25 tier table at
# all, so this project has no base item that could ever read them -
# skipped rather than transcribed dead. "Bow" and "Gauntlet" (this
# project's own, added 2026-08-30 before Section 25 was fully read) aren't
# doc weapon types either - Gauntlet's own 6% stays as an invented value,
# and Bow simply isn't in this table (falls through to DEFAULT).
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

## Enemy rarity rank (invented - no doc-sourced enemy rank system exists,
## same footing as EnemyArchetype above). User request (2026-08-30):
## drives which item-level tier of Section 25's real base types a kill
## can drop - "White mobs are the area level, blue mobs are the area +1,
## rare mobs are the area + 2 levels, bosses are the area + 5 levels."
## BOSS is never auto-rolled (see Enemy._roll_rank()) - only set
## explicitly by a boss encounter's own scene/script.
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

## Spawn-time odds for a regular (non-boss-flagged) enemy to roll each
## rank - invented, genre-standard shape (most kills are White, Rare is
## uncommon). Boss is deliberately absent - it's only ever set explicitly.
const ENEMY_RANK_SPAWN_WEIGHTS := {
	EnemyRank.NORMAL: 80.0,
	EnemyRank.MAGIC: 16.0,
	EnemyRank.RARE: 4.0,
}

# Cooldown Reduction cap (user request 2026-08-30): across every source that
# reduces an ability's cooldown at cast time - Ability.rank's own -4%/rank
# and Instinct's Action/Cast Speed (Player.get_action_speed_multiplier()) -
# an ability's cooldown can never drop below 25% of its authored
# cooldown_seconds. See Ability.get_final_cooldown().
const MAX_COOLDOWN_REDUCTION := 0.75

## Picks readable text over an arbitrary background color set at
## runtime (item rarity/damage-type colors) - without this, buttons
## colored with a light background (Common rarity white, etc.) get the
## same light default theme text as everything else and go illegible.
static func get_contrasting_text_color(bg: Color) -> Color:
	var luminance := 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color(0.05, 0.05, 0.05) if luminance > 0.6 else Color(0.95, 0.95, 0.95)
