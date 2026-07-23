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

enum Stat { VITALITY, STRENGTH, INSTINCT, ARCANE, ENIGMA, INTELLECT }

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

enum EnemyArchetype { GLASS_CANNON, MOBILE_BRUISER, HEAVY_HITTER }
