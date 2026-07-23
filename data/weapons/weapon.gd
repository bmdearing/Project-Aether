extends Resource
class_name Weapon
## Weapon base per Section 07 Weapon Architecture / Section 22 Weapon Types.

@export var weapon_id: String
@export var display_name: String
@export var weapon_slot: String = "Primary"  # Primary, Sidearm, Conduit, Secondary
@export var weapon_type: String = "Greatsword"
@export var base_damage: float = 10.0
@export var native_damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var infused_damage_type: Constants.DamageType = -1  # -1 = not infused, uses native scaling
@export var skill_ids: Array[String] = []  # 3 skills per weapon slot per Section 11
