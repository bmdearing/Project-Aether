extends RefCounted
class_name DamageCalculator
## Damage formula:
##   Power = base_weapon_damage + (stat_value x grade_multiplier)
##   Final Damage = Power x Motion Value x (1 + sum Increased%) x
##     product(More multipliers)
## Since v4.8 the two callers use opposite halves of the power term:
##   Weapon._base_hit(): base = weapon base x (1 + Str%), stat_value 0.0 -
##     the grade drops out entirely.
##   Ability._base_hit(): base 0.0, stat_value = Conduit spell power x
##     (1 + Int%) - so power = spell power x grade.
## Increased% is an additive pool, More multipliers stack multiplicatively.

class DamageResult:
	var final_damage: float = 0.0
	var damage_type: Constants.DamageType
	var breakdown: Dictionary = {}   # for the debug overlay

static func calculate(
	base_weapon_damage: float,
	motion_value: float,
	stat_value: float,
	scaling_grade: Constants.ScalingGrade,
	grade_roll_t: float,          # 0.0-1.0 position within the grade's range
	increased_percents: Array[float],   # additive pool, each e.g. 8.0 for 8%
	more_multipliers: Array[float],     # each e.g. 1.3 for a 30% More multiplier
	damage_type: Constants.DamageType
) -> DamageResult:
	var range: Vector2 = Constants.GRADE_MULTIPLIER_RANGES[scaling_grade]
	# lerp() returns Variant (polymorphic) - explicit : float avoids inferring Variant.
	var grade_multiplier: float = lerp(range.x, range.y, clamp(grade_roll_t, 0.0, 1.0))

	# See this file's header for how weapons vs spells use each half.
	var power := base_weapon_damage + (stat_value * grade_multiplier)

	var increased_sum := 0.0
	for pct in increased_percents:
		increased_sum += pct
	var increased_multiplier := 1.0 + (increased_sum / 100.0)

	var more_multiplier := 1.0
	for m in more_multipliers:
		more_multiplier *= m

	var result := DamageResult.new()
	result.damage_type = damage_type
	result.final_damage = power * motion_value * increased_multiplier * more_multiplier
	result.breakdown = {
		"base_weapon_damage": base_weapon_damage,
		"motion_value": motion_value,
		"grade_multiplier": grade_multiplier,
		"power": power,
		"increased_multiplier": increased_multiplier,
		"more_multiplier": more_multiplier,
	}
	return result

## Section 16: Damage Reduction % = Armor / (Armor + 6 x Hit Damage).
## Doc splits Kinetic/Piercing/Explosive behavior without concrete ratios,
## so this applies the full formula uniformly to all Physical damage
## (placeholder, flagged in README).
static func physical_mitigation(armor: float, hit_damage: float) -> float:
	if armor <= 0.0 or hit_damage <= 0.0:
		return 0.0
	return armor / (armor + 6.0 * hit_damage)

## Patch v4.4 Evasion (design doc, Master v3.0). Dodge: an attack hit
## deals nothing. Deflection: the hit lands but is reduced by
## deflection_mitigation(). Caps are hard ceilings on the curves.
const DODGE_CHANCE_DIVISOR := 3800.0
const DODGE_CHANCE_CAP := 0.65
const DEFLECTION_CHANCE_DIVISOR := 2333.0
const DEFLECTION_CHANCE_CAP := 0.75
const DEFLECTION_MITIGATION_DIVISOR := 13000.0
const DEFLECTION_MITIGATION_CAP := 0.35

static func dodge_chance(evasion: float) -> float:
	if evasion <= 0.0:
		return 0.0
	return min(evasion / (evasion + DODGE_CHANCE_DIVISOR), DODGE_CHANCE_CAP)

static func deflection_chance(evasion: float) -> float:
	if evasion <= 0.0:
		return 0.0
	return min(evasion / (evasion + DEFLECTION_CHANCE_DIVISOR), DEFLECTION_CHANCE_CAP)

static func deflection_mitigation(evasion: float) -> float:
	if evasion <= 0.0:
		return 0.0
	return min(evasion / (evasion + DEFLECTION_MITIGATION_DIVISOR), DEFLECTION_MITIGATION_CAP)

## Patch v3.2 "Revision - Resistance System" gives no explicit floor or
## ceiling (only that Resistance Shred can push Resistance negative,
## amplifying damage taken) - these two bounds are user-set directly
## (2026-08-30), replacing this project's own earlier invented 75%-cap/
## uncapped-floor placeholder. -200% floor still leaves heavily-shredded
## Resistance able to roughly triple incoming damage of that type; 95%
## ceiling guarantees at least 5% of every hit always gets through no
## matter how much Resistance is stacked.
const RESISTANCE_FLOOR := -200.0
const RESISTANCE_CEILING := 95.0
static func resistance_mitigation(resistance_percent: float) -> float:
	return clamp(resistance_percent, RESISTANCE_FLOOR, RESISTANCE_CEILING) / 100.0

## Patch v4.0 Offensive Mod Pool - Penetration/Physical Shred. Real,
## reusable functions per this patch's own "Files to Modify" list, but
## NOT yet called from Enemy.take_damage() - Enemy.gd has no Armor or
## Resistance value of its own anywhere in this project (only Resistance
## SHRED exists enemy-side, applied as a bonus damage-taken multiplier,
## not a real mitigatable base value), and Enemy.gd is explicitly on this
## same patch's "Files to Leave Alone" list. Giving enemies a real Armor/
## Resistance stat to Penetrate/Shred is a bigger, separate change than
## this patch's own stated scope - flagged in PATCH_NOTES.md rather than
## either silently doing nothing or touching an excluded file.
##
## Doc: "Penetration reduces enemy resistance before mitigation... stacks
## with Resistance Shred but calculated separately - Penetration applies
## first, then Resistance Shred." attacker_stats is nullable so a caller
## with no live StatSheet (a non-Player attacker) degrades to 0 penetration.
static func get_effective_resistance(base_resistance: float, damage_type: Constants.DamageType, attacker_stats: StatSheet, resistance_shred: float = 0.0) -> float:
	var pen: float = attacker_stats.get_penetration(damage_type) if attacker_stats else 0.0
	var after_penetration: float = max(-200.0, base_resistance - pen)
	return after_penetration - resistance_shred

## Doc: "Physical Shred reduces enemy Armor value directly - same
## mechanic as Resistance Shred targeting Armor." Multiplies the ARMOR
## VALUE itself (not the mitigation percentage physical_mitigation()
## derives from it) - per this patch's own DO NOT.
static func get_effective_armor(base_armor: float, attacker_stats: StatSheet) -> float:
	var shred_percent: float = attacker_stats.get_physical_shred() if attacker_stats else 0.0
	return base_armor * (1.0 - shred_percent)

## Patch v3.8: base crit chance is fixed per weapon/spell type (2%-8%);
## Agility's crit-chance contribution (StatSheet.get_crit_chance_from_
## stats(), a flat fraction) now adds directly on top instead of scaling
## it multiplicatively - the old Instinct-based "x(1 + instinct*0.03)"
## formula is gone along with Instinct itself.
## Bug fix (2026-09-07, user-reported): Agility is "increased Critical
## Strike Chance," a multiplier on the weapon/ability's own base_crit_
## chance - not flat additive percentage points. finesse_crit_bonus keeps
## meaning exactly what StatSheet.get_crit_chance_from_stats() already
## computes (Agility * 0.01, e.g. 0.07 for 7 Agility) - only how it
## combines with base_crit_chance changed here.
static func get_crit_chance(base_crit_chance: float, finesse_crit_bonus: float) -> float:
	return base_crit_chance * (1.0 + finesse_crit_bonus)

## Base Critical Strike Damage multiplier 150%, flat - no longer stat-
## derived (the pre-v3.8 Intellect used to feed it; "crit_damage" is a
## gear-affix-only "removed expression" per Patch v3.8 Section 2).
## bonus_fraction defaults to 0.0 - no consumer sums a crit_damage affix
## into this yet, same "real value, no formula to feed it" footing as
## several other gear-affix-only stats this patch introduced.
static func get_crit_damage_multiplier(bonus_fraction: float = 0.0) -> float:
	return 1.5 * (1.0 + bonus_fraction)

## Section 12: "Resilience Mitigation % = Resilience / (Resilience + 2,000).
## Soft cap at 50% DoT mitigation." Reduces StatusEffectComponent's Ignite
## ticks for whichever side has Resilience (currently Player only - see
## Player.resilience).
static func dot_mitigation(resilience: float) -> float:
	if resilience <= 0.0:
		return 0.0
	return min(0.5, resilience / (resilience + 2000.0))

## roll_t: fixed 0.0-1.0 for reproducible rolls, or omit (< 0) to roll randomly.
static func apply_crit(base_damage: float, crit_chance: float, crit_damage_multiplier: float, roll_t: float = -1.0) -> Dictionary:
	var t: float = roll_t if roll_t >= 0.0 else randf()
	var is_critical: bool = t < crit_chance
	return {
		"final_damage": base_damage * crit_damage_multiplier if is_critical else base_damage,
		"is_critical": is_critical,
	}

## Expected-value blend (not a random roll) for stat-card "Predicted Damage" display.
static func get_expected_damage(base_damage: float, crit_chance: float, crit_damage_multiplier: float) -> float:
	return base_damage * (1.0 + clamp(crit_chance, 0.0, 1.0) * (crit_damage_multiplier - 1.0))
