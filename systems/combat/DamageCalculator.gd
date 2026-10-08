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

## Damage Reduction = Armor / (Armor + 6 x Hit Damage), for all Physical types.
static func physical_mitigation(armor: float, hit_damage: float) -> float:
	if armor <= 0.0 or hit_damage <= 0.0:
		return 0.0
	return armor / (armor + 6.0 * hit_damage)

## Evasion. Dodge: an attack hit deals nothing. Deflection: the hit lands but is reduced by
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

## Negative Resistance (from Shred) amplifies damage taken.
const RESISTANCE_FLOOR := -200.0
const RESISTANCE_CEILING := 95.0
static func resistance_mitigation(resistance_percent: float) -> float:
	return clamp(resistance_percent, RESISTANCE_FLOOR, RESISTANCE_CEILING) / 100.0

## Penetration applies first, then Resistance Shred. Not called yet: enemies
## have no base Resistance to penetrate. attacker_stats may be null.
static func get_effective_resistance(base_resistance: float, damage_type: Constants.DamageType, attacker_stats: StatSheet, resistance_shred: float = 0.0) -> float:
	var pen: float = attacker_stats.get_penetration(damage_type) if attacker_stats else 0.0
	var after_penetration: float = max(-200.0, base_resistance - pen)
	return after_penetration - resistance_shred

## Physical Shred scales the Armor value itself, not the mitigation percent.
static func get_effective_armor(base_armor: float, attacker_stats: StatSheet) -> float:
	var shred_percent: float = attacker_stats.get_physical_shred() if attacker_stats else 0.0
	return base_armor * (1.0 - shred_percent)

## Increased crit chance multiplies the base, it doesn't add points.
static func get_crit_chance(base_crit_chance: float, finesse_crit_bonus: float) -> float:
	return base_crit_chance * (1.0 + finesse_crit_bonus)

## Base 150%, scaled by StatSheet.get_crit_damage_bonus().
static func get_crit_damage_multiplier(bonus_fraction: float = 0.0) -> float:
	return 1.5 * (1.0 + bonus_fraction)

## Resilience / (Resilience + 2000), capped at 50%. Reduces DoT ticks.
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
