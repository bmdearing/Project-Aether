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
