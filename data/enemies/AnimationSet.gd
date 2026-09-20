extends Resource
class_name AnimationSet
## Maps this project's standard enemy animation slots to actual clip names in
## an imported model's AnimationPlayer. Names must match the clip exactly -
## the defaults below are UAL1_Standard.glb's own names (Universal Animation
## Library), not generic placeholders. An empty string means "this slot has no
## clip"; EnemyAnimationController falls back to the idle clip for that state.

@export var idle: String = "Idle"
@export var walk: String = "Walk"
@export var run: String = "Jog_Fwd"
@export var attack_light: String = "Punch_Jab"
@export var attack_heavy: String = "Punch_Cross"
@export var attack_special: String = ""
@export var hit_reaction: String = "Hit_Chest"
@export var stagger: String = "Hit_Head"
@export var death: String = "Death01"
@export var death_alt: String = ""
@export var ability_cast: String = ""
