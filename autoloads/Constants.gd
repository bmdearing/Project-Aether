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

## Patch v3.6: lowercase tag string -> DamageType, for SlateAffixPool/
## Brand-combination lookups that key on a string tag rather than the
## enum directly. Only the 9 real damage types have an enum value -
## "spell"/"attack"/"generic" (Section 10's own non-damage-type Slate
## tags, see Slate.category_tag_override) are valid SlateAffix.tag
## strings with no DamageType counterpart, so they're deliberately absent
## here rather than mapped to a fake enum entry.
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

## Patch v3.8: six stats collapsed to three - Prowess (Attack Power/Life),
## Finesse (Evasion/Crit Chance), Resolve (Spell Power/Ward). Every old
## per-damage-type "which stat scales this" distinction is gone too -
## Attack Power always comes from Prowess, Spell Power always from
## Resolve, regardless of the weapon/ability's own damage type (DAMAGE_
## TYPE_MAIN_STAT below still exists as directional metadata, but nothing
## in the actual damage formula consults it anymore - see Weapon/Ability.
## _base_hit()). Old-save/old-data migration (~850 already-generated
## items' stat_requirement + primary/secondary_scaling_stat) maps
## Vitality/Strength -> Prowess, Instinct -> Finesse, Arcane/Enigma/
## Intellect -> Resolve - see tools/repair_stat_migration.gd.
enum Stat { PROWESS, FINESSE, RESOLVE }

# Display names - used by ItemCard's requirement line and EquipmentComponent's
# equip-block reason (user request 2026-08-30: gate Section 25's items behind
# a level + stat requirement) rather than each spot inventing its own
# capitalization of the enum key.
const STAT_NAME := {
	Stat.PROWESS: "Prowess",
	Stat.FINESSE: "Finesse",
	Stat.RESOLVE: "Resolve",
}

# Per-point values - shown in the advanced (Alt-hover) tooltip when a mod
# line links to one of these stats. See StatSheet.gd's own derived-value
# methods for the real formulas these describe.
const STAT_GLOSSARY := {
	Stat.PROWESS: "+2 Life, +1 Attack Power per point.",
	Stat.FINESSE: "+2 Evasion Rating, +1% increased Critical Strike Chance per point.",
	Stat.RESOLVE: "+1 Spell Power, +0.5% increased Ward per point.",
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
	"shock": DamageType.LIGHTNING,
}

## Section 20's Infusion Stone/Shrivening Stone/Shard of Tharsis - fixed,
## non-Brand crafting items (see data/consumables/instances/). Shared by
## Enemy.gd (loot drop), CraftingScreen.gd (their own action buttons),
## and InventoryScreen.gd (excluded from equip-on-click) so the 3 ids
## live in exactly one place.
const CRAFTING_CONSUMABLE_IDS := ["infusion_stone", "shrivening_stone", "shard_of_tharsis"]

## Implementation Brief v4.2 - ranged weapon ammo. ARROW is infinite (never
## tracked, never dropped); every other type has a persistent reserve in
## the AmmoInventory autoload.
enum AmmoType { PISTOL, REVOLVER, SHOTGUN, RIFLE, AUTOMATIC, CROSSBOW_BOLT, ARROW }

## SEMI_AUTO: one shot per click. FULL_AUTO: fires while held (Weapon.
## fire_rate). BOLT/LEVER/PUMP_ACTION and SINGLE_ACTION (revolver hammer,
## crossbow): a Weapon.cycle_time delay between shots.
enum FireMode { SEMI_AUTO, FULL_AUTO, BOLT_ACTION, LEVER_ACTION, PUMP_ACTION, SINGLE_ACTION }

## Ammo pickup Item ids (data/consumables/instances/) - see AmmoPack.
const AMMO_TYPE_PICKUP_ID := {
	AmmoType.PISTOL: "ammo_pistol",
	AmmoType.REVOLVER: "ammo_revolver",
	AmmoType.SHOTGUN: "ammo_shotgun",
	AmmoType.RIFLE: "ammo_rifle",
	AmmoType.AUTOMATIC: "ammo_automatic",
	AmmoType.CROSSBOW_BOLT: "ammo_crossbow",
}

const STATUS_EFFECT_NAME := {
	"ignite": "Ignite",
	"chill": "Chill",
	"freeze": "Freeze",
	"electrocute": "Electrocute",
	"unraveling": "Unraveling",
	"slow": "Slowed",
	"shock": "Shocked",
}

# Patch v3.8: directional metadata only now - Weapon._base_hit()/Ability.
# _base_hit() no longer branch on this at all (Attack Power is always
# Prowess, Spell Power is always Resolve, regardless of damage type), but
# it's kept updated/accurate for anything else that wants "which stat
# does this damage type thematically belong to."
const DAMAGE_TYPE_MAIN_STAT := {
	DamageType.KINETIC: Stat.PROWESS,
	DamageType.PIERCING: Stat.PROWESS,
	DamageType.EXPLOSIVE: Stat.PROWESS,
	DamageType.FIRE: Stat.RESOLVE,
	DamageType.COLD: Stat.RESOLVE,
	DamageType.LIGHTNING: Stat.RESOLVE,
	DamageType.AETHERIC: Stat.RESOLVE,
	DamageType.ENTROPIC: Stat.RESOLVE,
	DamageType.PALE: Stat.RESOLVE,
}

enum ScalingGrade { S, A, B, C, D, E }

# Grade Multiplier ranges (min, max) - Implementation Brief v3.3 Section 1,
# BREAKING CHANGE, replaces the old SCALING_RANGES entirely (2026-08-31).
# The old formula treated this range as a fraction of stat value multiplied
# into an already-stat-scaled damage term, producing numbers in the
# thousands at level 1; the new one is a flat multiplier on stat_value
# that's ADDED to base weapon damage (see DamageCalculator.calculate()) -
# same enum, deliberately different value ranges/units, not a tuning pass
# on the old numbers.
const GRADE_MULTIPLIER_RANGES := {
	ScalingGrade.S: Vector2(3.0, 4.0),
	ScalingGrade.A: Vector2(2.0, 2.9),
	ScalingGrade.B: Vector2(1.2, 1.9),
	ScalingGrade.C: Vector2(0.7, 1.1),
	ScalingGrade.D: Vector2(0.4, 0.6),
	ScalingGrade.E: Vector2(0.2, 0.3),
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

# Section 13 - Equipment Slots. OFFHAND covers a Shield OR an offhand-type
# Weapon (Weapon.is_offhand). Patch v3.5: Sidearm/Conduit/Secondary cut as
# their own slots - a weapon now equips into PRIMARY_WEAPON or OFFHAND
# based on Weapon.is_main_hand/is_offhand instead (see
# EquipmentComponent.equip()). Throwables are inventory stacks now, not an
# equipment slot at all (see ThrowableStack.gd).
#
# Every surviving entry keeps its ORIGINAL explicit int value (5/7/8 -
# SIDEARM_WEAPON/CONDUIT/SECONDARY_THROWABLE - are simply retired, not
# reassigned to anything else) rather than letting Godot renumber the
# enum. Item.equip_slot is stored as a raw int in every existing .tres
# file (Shields/Amulets/Belts/Rings included) - renumbering would silently
# repoint OFFHAND=6/AMULET=9/BELT=10/RING=11's old stored ints at whatever
# entry happens to occupy that number now, corrupting every one of those
# files without touching them.
enum EquipmentSlot {
	HELMET = 0, BODY_ARMOUR = 1, GLOVES = 2, BOOTS = 3,
	PRIMARY_WEAPON = 4, OFFHAND = 6,
	AMULET = 9, BELT = 10, RING = 11,
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

## Patch v3.9 "Enemy Rarity System" - a SEPARATE axis from EnemyRank
## above, per user direction (2026-09-06): EnemyRank keeps driving loot
## item-level exactly as before (untouched by this patch); EnemyRarity
## drives stat multipliers, affixes, auras, and drop conversion instead.
## An enemy carries both simultaneously - e.g. a MAGIC-rank Elite is a
## perfectly normal combination, the two systems don't interact.
enum EnemyRarity { NORMAL, ELITE, CHAMPION, ASCENDANT }

const ENEMY_RARITY_NAME := {
	EnemyRarity.NORMAL: "Normal",
	EnemyRarity.ELITE: "Elite",
	EnemyRarity.CHAMPION: "Champion",
	EnemyRarity.ASCENDANT: "Ascendant",
}

## Doc-exact: "Name shown in blue/yellow/orange."
const ENEMY_RARITY_NAME_COLOR := {
	EnemyRarity.NORMAL: Color.WHITE,
	EnemyRarity.ELITE: Color(0.4, 0.6, 1.0),
	EnemyRarity.CHAMPION: Color(1.0, 0.85, 0.0),
	EnemyRarity.ASCENDANT: Color(1.0, 0.5, 0.0),
}

## Doc-exact stat-scaling multipliers are never given a number by the doc
## itself (Section 24-style deferred balance) - these are this project's
## own invented placeholder curve, same footing as TIER_HEALTH_GROWTH_
## PER_TIER/ENEMY_RANK_SPAWN_WEIGHTS above. health/damage are multipliers
## (1.0 = no change); NORMAL is intentionally absent (no scaling at all).
const ENEMY_RARITY_HEALTH_MULT := {
	EnemyRarity.ELITE: 1.5,
	EnemyRarity.CHAMPION: 3.0,
	EnemyRarity.ASCENDANT: 8.0,
}
const ENEMY_RARITY_DAMAGE_MULT := {
	EnemyRarity.ELITE: 1.2,
	EnemyRarity.CHAMPION: 1.6,
	EnemyRarity.ASCENDANT: 2.4,
}

## Placeholder spawn-weight "config" (brief's own words: "Placeholder
## weights for testing... do not hardcode, read from spawn configuration")
## - this table IS that configuration (same role ENEMY_RANK_SPAWN_WEIGHTS
## already plays for the other axis) rather than a literal inline dict in
## the spawner script itself, so a future real config resource can replace
## just this table without touching spawn-site code.
const ENEMY_RARITY_SPAWN_WEIGHTS := {
	EnemyRarity.NORMAL: 75.0,
	EnemyRarity.ELITE: 20.0,
	EnemyRarity.CHAMPION: 4.0,
	EnemyRarity.ASCENDANT: 1.0,
}

# Cooldown Reduction cap (user request 2026-08-30): across every source that
# reduces an ability's cooldown at cast time - Ability.rank's own -4%/rank
# and Instinct's Action/Cast Speed (Player.get_action_speed_multiplier()) -
# an ability's cooldown can never drop below 25% of its authored
# cooldown_seconds. See Ability.get_final_cooldown().
const MAX_COOLDOWN_REDUCTION := 0.75

## Patch v3.7 Section 3 - Cast Speed affix tiers (percent, T1 best).
## min_item_level gates which tier a roll can reach, same shape as
## ItemRoller's own tier system (though this table is consumed directly
## by wherever Cast Speed affixes are authored/rolled, not through
## ItemRoller.AFFIX_POOL's tier1_min/max + TIER_DECAY scheme).
const CAST_SPEED_TIERS := [
	{"min": 18.0, "max": 22.0, "item_level": 72},  # T1
	{"min": 14.0, "max": 17.0, "item_level": 56},  # T2
	{"min": 10.0, "max": 13.0, "item_level": 40},  # T3
	{"min": 6.0,  "max": 9.0,  "item_level": 24},  # T4
	{"min": 2.0,  "max": 5.0,  "item_level": 8},   # T5
]

## Section 20 Brand rarity (Patch v3.5) - gates drop frequency via
## BrandRoller.roll(), which previously picked uniformly among every
## Brand regardless of power. Only covers Brands that actually exist as
## data/brands/instances/*.tres - Facsimile/Amalgam/Imbue are cut from
## this project (see Brand.gd's own header), so they're left out here too
## rather than pointing at nonexistent files.
enum BrandRarity { COMMON, UNCOMMON, RARE, LEGENDARY }

const BRAND_RARITIES := {
	"distill": BrandRarity.COMMON,
	"inscribe": BrandRarity.COMMON,
	"hone": BrandRarity.COMMON,
	"quicken": BrandRarity.COMMON,
	"impel": BrandRarity.UNCOMMON,
	"lancet": BrandRarity.UNCOMMON,
	"deflagrate": BrandRarity.UNCOMMON,
	"calcine": BrandRarity.UNCOMMON,
	"quench": BrandRarity.UNCOMMON,
	"galvanic": BrandRarity.UNCOMMON,
	"invoke": BrandRarity.UNCOMMON,
	"efface": BrandRarity.UNCOMMON,
	"hollow": BrandRarity.UNCOMMON,
	"anneal": BrandRarity.UNCOMMON,
	"attenuate": BrandRarity.UNCOMMON,
	"occlude": BrandRarity.UNCOMMON,
	"temper": BrandRarity.UNCOMMON,
	"inure": BrandRarity.UNCOMMON,
	"render": BrandRarity.UNCOMMON,
	"refine": BrandRarity.UNCOMMON,
	"sever": BrandRarity.UNCOMMON,
	"cleave": BrandRarity.RARE,
	"excise": BrandRarity.RARE,
	"bore": BrandRarity.RARE,
	"binder": BrandRarity.RARE,
	"rectify": BrandRarity.RARE,
}

const BRAND_DROP_WEIGHTS := {
	BrandRarity.COMMON: 100,
	BrandRarity.UNCOMMON: 35,
	BrandRarity.RARE: 8,
	BrandRarity.LEGENDARY: 1,
}

## Patch v3.8 Section 5 - ItemCard's Alt Info panel.
static func grade_to_letter(grade: int) -> String:
	match grade:
		0: return "S"
		1: return "A"
		2: return "B"
		3: return "C"
		4: return "D"
		5: return "E"
	return "?"

## Picks readable text over an arbitrary background color set at
## runtime (item rarity/damage-type colors) - without this, buttons
## colored with a light background (Common rarity white, etc.) get the
## same light default theme text as everything else and go illegible.
static func get_contrasting_text_color(bg: Color) -> Color:
	var luminance := 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color(0.05, 0.05, 0.05) if luminance > 0.6 else Color(0.95, 0.95, 0.95)
