extends Resource
class_name Ability
## A skill/ability as referenced in the Skill System (Section 11) and
## Ability Staging Ground (Section 23). Motion Value drives the damage
## formula and is never shown to the player directly.

@export var ability_id: String
@export var display_name: String
@export var description: String                 # player-facing flavor text only - no tips/cross-refs per style rules
@export var damage_type: Constants.DamageType
@export var motion_value: float = 1.0
@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var cooldown_seconds: float = 0.0
@export var resource_cost: float = 0.0
@export var can_trigger_riposte: bool = false    # true only for high-MV committed attacks per Section 07
@export var is_auto_cast_eligible: bool = true   # false for e.g. Riposte itself
@export var applies_status_effects: Array[String] = []  # status effect ids, e.g. "chill", "ignite"
