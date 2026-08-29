extends Item
class_name Weapon
## Weapon base per Section 07 Weapon Architecture / Section 22 Weapon Types.
## equip_slot (inherited from Item) carries which of the four weapon
## slots this fills - PRIMARY_WEAPON, SIDEARM_WEAPON, CONDUIT, or
## SECONDARY_THROWABLE per Section 07's Weapon Architecture table.

@export var weapon_type: String = "Greatsword"
@export var base_damage: float = 10.0
@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var native_damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var infused_damage_type: Constants.DamageType = -1  # -1 = not infused, uses native scaling
@export var is_two_handed: bool = false  # occupies both weapon slots per Section 13
@export var skill_ids: Array[String] = []  # 3 skills per weapon slot per Section 11

## Predicted final damage for one hit with this weapon, given the
## attacking motion_value (PlayerMeleeAttack/PlayerRangedAttack each have
## their own base_motion_value constant - there's no per-weapon "Basic
## Attack" skill to pull one from, see those scripts' own header
## comments) and the wielder's StatSheet. Mirrors Ability.predict_damage()
## exactly - centralized so PlayerMeleeAttack._deal_damage()/
## PlayerRangedAttack._fire() and any UI showing a predicted number
## (CharacterScreen) can't drift apart. No Slate/gear stat aggregation
## into StatSheet exists yet (EquipmentComponent's own header flags the
## same gap), so increased/more pools are always empty here too.
func predict_damage(motion_value: float, stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var damage_type: Constants.DamageType = infused_damage_type if infused_damage_type != -1 else native_damage_type
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.STRENGTH)
	var stat_value: float = stat_sheet.get_stat(main_stat)
	var mastery: float = stat_sheet.get_mastery(damage_type)
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		base_damage, motion_value, stat_value, scaling_grade,
		0.5, mastery, [], [], damage_type
	)
	return result.final_damage
