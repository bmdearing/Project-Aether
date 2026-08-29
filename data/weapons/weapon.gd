extends Item
class_name Weapon
## Weapon base per Section 07/22. equip_slot decides which slot it fills;
## is_ranged decides melee vs ranged attack behavior independently of
## slot - Player.get_active_weapon() + is_ranged drive attack dispatch,
## so a ranged weapon can sit in either weapon slot.

@export var weapon_type: String = "Greatsword"
@export var base_damage: float = 10.0
@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var native_damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var infused_damage_type: Constants.DamageType = -1  # -1 = not infused, uses native scaling
@export var is_two_handed: bool = false
@export var is_ranged: bool = false
@export var skill_ids: Array[String] = []

func get_base_crit_chance() -> float:
	return Constants.WEAPON_BASE_CRIT_CHANCE.get(weapon_type, Constants.DEFAULT_BASE_CRIT_CHANCE)

## Shared groundwork for predict_damage()/roll_damage().
func _base_hit(motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	var damage_type: Constants.DamageType = infused_damage_type if infused_damage_type != -1 else native_damage_type
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.STRENGTH)
	var stat_value: float = stat_sheet.get_stat(main_stat)
	var mastery: float = stat_sheet.get_mastery(damage_type)
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		base_damage, motion_value, stat_value, scaling_grade,
		0.5, mastery, [], [], damage_type
	)
	return {
		"base_damage": result.final_damage,
		"crit_chance": DamageCalculator.get_crit_chance(get_base_crit_chance(), stat_sheet.get_stat(Constants.Stat.INSTINCT)),
		"crit_damage_multiplier": DamageCalculator.get_crit_damage_multiplier(stat_sheet.get_stat(Constants.Stat.INTELLECT)),
	}

## Expected-value blend (not a random roll) so the stat card shows one
## stable number instead of jittering on every hover.
func predict_damage(motion_value: float, stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var hit := _base_hit(motion_value, stat_sheet)
	return DamageCalculator.get_expected_damage(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])

## Real-hit counterpart to predict_damage() - actually rolls crit.
func roll_damage(motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	if stat_sheet == null:
		return {"final_damage": 0.0, "is_critical": false}
	var hit := _base_hit(motion_value, stat_sheet)
	return DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
