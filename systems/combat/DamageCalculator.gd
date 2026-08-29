extends RefCounted
class_name DamageCalculator
## Implements the Section 11 damage formula:
##   Final Damage = Base Weapon Damage x Motion Value
##                  x (Stat Scaling Grade Multiplier x Mastery Bonus)
##                  x (1 + sum of Increased%)
##                  x product(More multipliers)
##
## Increased multipliers pool additively; More multipliers are rare,
## multiplicative, and stack independently (Section 11).

class DamageResult:
	var final_damage: float = 0.0
	var damage_type: Constants.DamageType
	var breakdown: Dictionary = {}   # for the debug overlay

static func calculate(
	base_weapon_damage: float,
	motion_value: float,
	stat_value: float,
	scaling_grade: Constants.ScalingGrade,
	grade_roll_t: float,          # 0.0-1.0 position within the grade's range, for reproducible rolls
	mastery_bonus: float,         # e.g. 0.5 for +0.5 Mastery
	increased_percents: Array[float],   # additive pool, each e.g. 8.0 for 8%
	more_multipliers: Array[float],     # each e.g. 1.3 for a 30% More multiplier
	damage_type: Constants.DamageType
) -> DamageResult:
	var range: Vector2 = Constants.SCALING_RANGES[scaling_grade]
	# lerp()'s builtin signature returns Variant (it's polymorphic over
	# float/Vector2/Vector3/Color) - explicit : float forces the narrowing
	# so this doesn't infer Variant via :=.
	var base_scale: float = lerp(range.x, range.y, clamp(grade_roll_t, 0.0, 1.0))
	var effective_scale := base_scale * (1.0 + mastery_bonus)

	var scaled_stat_damage := stat_value * effective_scale

	var increased_sum := 0.0
	for pct in increased_percents:
		increased_sum += pct
	var increased_multiplier := 1.0 + (increased_sum / 100.0)

	var more_multiplier := 1.0
	for m in more_multipliers:
		more_multiplier *= m

	var result := DamageResult.new()
	result.damage_type = damage_type
	result.final_damage = base_weapon_damage * motion_value * scaled_stat_damage * increased_multiplier * more_multiplier
	result.breakdown = {
		"base_weapon_damage": base_weapon_damage,
		"motion_value": motion_value,
		"base_scale": base_scale,
		"mastery_bonus": mastery_bonus,
		"effective_scale": effective_scale,
		"scaled_stat_damage": scaled_stat_damage,
		"increased_multiplier": increased_multiplier,
		"more_multiplier": more_multiplier,
	}
	return result

## Section 16 Armor System: Damage Reduction % = Armor / (Armor + 6 x Hit
## Damage). The doc splits Kinetic (full %) / Piercing (partial) / Explosive
## (flat reduction) behavior but never gives a concrete ratio for the
## Piercing/Explosive cases, so this applies the full formula uniformly to
## all Physical damage as a placeholder - flagged in the README, not a
## silent guess. Soft cap ~6,000 Armor is inherent to the formula's shape,
## not separately enforced.
static func physical_mitigation(armor: float, hit_damage: float) -> float:
	if armor <= 0.0 or hit_damage <= 0.0:
		return 0.0
	return armor / (armor + 6.0 * hit_damage)
