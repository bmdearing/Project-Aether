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

## Three stats. v4.8 renamed them (Prowess -> Strength, Finesse -> Agility,
## Resolve -> Intellect) and made every stat effect a percentage:
## Strength multiplies weapon base damage, Intellect multiplies Conduit
## spell power, regardless of the weapon/ability's own damage type
## (DAMAGE_TYPE_MAIN_STAT below is directional metadata only - see
## Weapon/Ability._base_hit()). Old saves are migrated on load by
## ItemSerializer.migrate_stat_key()/migrate_stat_text(); data files by
## tools/repair_v48_stat_rename.gd.
enum Stat { STRENGTH, AGILITY, INTELLECT }

# Display names - used by ItemCard's requirement line and EquipmentComponent's
# equip-block reason (user request 2026-08-30: gate Section 25's items behind
# a level + stat requirement) rather than each spot inventing its own
# capitalization of the enum key.
const STAT_NAME := {
	Stat.STRENGTH: "Strength",
	Stat.AGILITY: "Agility",
	Stat.INTELLECT: "Intellect",
}

# Per-point values - shown in the advanced (Alt-hover) tooltip when a mod
# line links to one of these stats. See StatSheet.gd's own derived-value
# methods for the real formulas these describe.
const STAT_GLOSSARY := {
	Stat.STRENGTH: "+1% increased Weapon Damage, +4 Life per point.",
	Stat.AGILITY: "+1% increased Attack Speed, +1% increased Evasion, +1% increased Critical Strike Chance per point.",
	Stat.INTELLECT: "+1% increased Spell Damage, +3 Mana, +1% increased Ward per point.",
}

# Section 09 - Status Effects. Scope: the 5 effects that already have a
# real applier in this project (Ability.applies_status_effects on the
# elemental/esoteric spells) - Bleed/Armor Shred/Stagger-Stun (Physical
# family, no weapon-side proc mechanic exists) and Aetherburn/
# Pallid (no Fire-channel/Aetheric/Pale ability exists yet) are left for
# StatusEffectComponent to grow into once a real source exists (flagged
# in DEVELOPMENT.md). Blind is explicitly deferred in the patch doc itself, not
# just by this project, so it's not modeled at all.
const STATUS_EFFECT_DAMAGE_TYPE := {
	"ignite": DamageType.FIRE,
	"chill": DamageType.COLD,
	"freeze": DamageType.COLD,
	"electrocute": DamageType.LIGHTNING,
	"unraveling": DamageType.ENTROPIC,
	"slow": DamageType.PIERCING,  # Caltrops - a generic slow independent of Chill's Cold flavor, colored via its own Piercing source instead
	"shock": DamageType.LIGHTNING,
	"scorch": DamageType.FIRE,
}

## Section 20's Infusion Stone/Shrivening Stone/Shard of Tharsis - stackable
## crafting currency (inventory StringName stacks, like the Orbs). Older
## saves held them as Items; GridInventory converts those on load.
const CRAFTING_CONSUMABLE_IDS := ["infusion_stone", "shrivening_stone", "shard_of_tharsis"]

## Implementation Brief v4.2 - ranged weapon ammo. ARROW is infinite (never
## tracked, never dropped); every other type has a persistent reserve in
## the AmmoInventory autoload.
enum AmmoType { PISTOL, REVOLVER, SHOTGUN, RIFLE, AUTOMATIC, CROSSBOW_BOLT, ARROW }

## SEMI_AUTO: one shot per click. FULL_AUTO: fires while held (Weapon.
## fire_rate). BOLT/LEVER/PUMP_ACTION and SINGLE_ACTION (revolver hammer,
## crossbow): a Weapon.cycle_time delay between shots.
enum FireMode { SEMI_AUTO, FULL_AUTO, BOLT_ACTION, LEVER_ACTION, PUMP_ACTION, SINGLE_ACTION }

## Implementation Brief v4.3 - hard socket ceiling per item category (see
## ItemRoller.get_socket_category()). A ceiling only: a base's own max_sockets
## (tier-scaled by tools/generate_base_types.gd) is never raised to it, and
## Bore/Corruption never take an item past it (bar Corruption's +1 "extra").
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
	"shock": "Shocked",
	"scorch": "Scorched",
	"guard_break": "Guard Broken",
	"bleed": "Bleeding",
	"armor_shred": "Armor Shred",
	"entangle": "Entangled",
	"suppressed": "Suppressed",
	"marked": "Marked",
	"pallid": "Pallid",
}

# Patch v3.8: directional metadata only now - Weapon._base_hit()/Ability.
# _base_hit() no longer branch on this at all (weapons always scale with
# Strength, spells with Intellect, regardless of damage type), but it's
# kept accurate for anything else that wants "which stat does this damage
# type thematically belong to" (SlateRoller's Main Stat line).
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

# Grade Multiplier ranges (min, max). Since v4.8 the grade is purely a spell
# quality multiplier: Ability._base_hit() computes Conduit spell power x
# (1 + Int%) x grade. Weapons ignore it entirely (they pass stat_value 0.0
# to DamageCalculator.calculate()). v4.8 follow-up retuned these for that
# role - B is roughly neutral (~1.0x), S boosts, E cuts.
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

# No doc-sourced color for SlateRarity - reuses ITEM_RARITY_COLOR's palette,
# plus an invented violet for the extra VERY_RARE tier. Placeholder, flagged in DEVELOPMENT.md.
const SLATE_RARITY_COLOR := {
	SlateRarity.COMMON: Color(0.9, 0.9, 0.9),
	SlateRarity.UNCOMMON: Color(0.3, 0.55, 0.95),
	SlateRarity.RARE: Color(0.95, 0.85, 0.2),
	SlateRarity.VERY_RARE: Color(0.7, 0.4, 0.9),
	SlateRarity.UNIQUE: Color(0.9, 0.55, 0.15),
	SlateRarity.MYTHIC: Color(0.98, 0.75, 0.75),
}

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
## same footing as other invented enemy tuning). User request (2026-08-30):
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
## The Vault's elite pack, spawned alongside its FigmentBoss.
const ENEMY_PACKS_VAULT_ELITE := [
	{"weight": 1.0, "units": [["unchartered_chieftain", 1, 1], [UNCHARTERED_RAIDERS, 2, 3]]},
	{"weight": 1.0, "units": [["directorate_adjudicator", 1, 1]]},
	{"weight": 1.0, "units": [["synod_vindicator", 1, 1], ["synod_exarch", 1, 1]]},
	{"weight": 1.0, "units": [["legion_threshold_knight", 1, 1], ["hollowed_shambler", 2, 3]]},
	{"weight": 1.0, "units": [["legion_dreadknight", 1, 1], ["hollowed_shambler", 2, 3]]},
	{"weight": 1.0, "units": [["veilborne_cantor", 1, 1], ["veilborne_mindbender", 2, 2]]},
	{"weight": 1.0, "units": [["synod_exarch", 1, 1], [SYNOD_GOLEMS, 1, 2]]},
]

# Cooldown Reduction cap (user request 2026-08-30): across every source that
# reduces an ability's cooldown at cast time - over-cap spell levels, gear
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

## ---- Orb crafting (Crafting & Inventory Rev2) ----------------------------

## Max prefixes (x) / suffixes (y) per rarity. Unique/Mythic aren't Orb-craftable.
const AFFIX_LIMITS_GEAR := {
	ItemRarity.COMMON: Vector2i(0, 0),
	ItemRarity.UNCOMMON: Vector2i(1, 1),
	ItemRarity.RARE: Vector2i(3, 3),
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
const STASH_CURRENCY_TAB_SIZE := Vector2i(12, 8)
const STASH_SLATE_TAB_SIZE := Vector2i(12, 12)

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
	&"brand_attack": 12, &"brand_speed": 12, &"brand_prefix": 10, &"brand_suffix": 10,
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
