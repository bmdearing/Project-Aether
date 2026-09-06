extends RefCounted
class_name DamageCalculator
## Implementation Brief v3.3 Section 1 damage formula (2026-08-31,
## BREAKING CHANGE - replaces the old multiplicative one below):
##   Attack Power = base_weapon_damage + (stat_value x grade_multiplier)
##   Spell Power  = stat_value x grade_multiplier  (same formula with
##     base_weapon_damage = 0 - a spell has no weapon; Ability._base_hit()
##     passes 0.0, not the old 1.0 multiplicative-identity placeholder,
##     since 1.0 would now silently add +1 flat damage to every spell)
##   Final Damage = Power x Motion Value x (1 + sum Increased%) x
##     product(More multipliers)
## Old formula (removed): base_weapon_damage x motion_value x
## (stat_value x grade_scale x (1 + mastery)) x increased x more - the
## old grade "scale" was a fraction of stat_value multiplied INTO an
## already-stat-scaled term, producing numbers in the thousands at level
## 1. Increased%/More multiplier logic is UNCHANGED per the brief -
## additive pool, multiplicative stack, same as always.

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
	mastery_bonus: float,         # e.g. 0.5 for +0.5 Mastery
	increased_percents: Array[float],   # additive pool, each e.g. 8.0 for 8%
	more_multipliers: Array[float],     # each e.g. 1.3 for a 30% More multiplier
	damage_type: Constants.DamageType
) -> DamageResult:
	var range: Vector2 = Constants.GRADE_MULTIPLIER_RANGES[scaling_grade]
	# lerp() returns Variant (polymorphic) - explicit : float avoids inferring Variant.
	var grade_multiplier: float = lerp(range.x, range.y, clamp(grade_roll_t, 0.0, 1.0))
	# Mastery only affects the grade multiplier for matching tags, never
	# universal - already scoped correctly since every caller only ever
	# passes a tag-matched mastery_bonus in.
	var effective_grade_multiplier := grade_multiplier * (1.0 + mastery_bonus)

	# Attack Power (weapon calls, base_weapon_damage > 0) or Spell Power
	# (spell calls, base_weapon_damage == 0) - same additive formula
	# either way, see this file's own header for why spells pass 0 here.
	var power := base_weapon_damage + (stat_value * effective_grade_multiplier)

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
		"mastery_bonus": mastery_bonus,
		"effective_grade_multiplier": effective_grade_multiplier,
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

## Patch v3.8: base crit chance is fixed per weapon/spell type (2%-8%);
## Finesse's crit-chance contribution (StatSheet.get_crit_chance_from_
## stats(), a flat fraction) now adds directly on top instead of scaling
## it multiplicatively - the old Instinct-based "x(1 + instinct*0.03)"
## formula is gone along with Instinct itself.
static func get_crit_chance(base_crit_chance: float, finesse_crit_bonus: float) -> float:
	return base_crit_chance + finesse_crit_bonus

## Base Critical Strike Damage multiplier 150%, flat - no longer stat-
## derived (Intellect, its old source, is gone; "crit_damage" is a
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
