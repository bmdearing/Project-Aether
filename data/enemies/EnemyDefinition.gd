extends Resource
class_name EnemyDefinition
## Data-driven enemy identity/stats/visuals, applied by Enemy._apply_definition()
## and Enemy._apply_model(). An Enemy with no definition keeps whatever its own
## scene/subclass sets, so archetypes migrate one at a time.

# Identity
@export var display_name: String = ""
@export var faction: String = ""           # "hollowed", "directorate", etc.
@export_multiline var lore_description: String = ""

# Visual
@export var model_scene: PackedScene = null
@export var animation_set: AnimationSet = null
@export var scale_modifier: float = 1.0
## Yaw (radians) between the model's front and +Z - see Enemy.model_forward_yaw_offset.
@export var model_yaw_offset: float = 0.0

# Level scaling - health/damage come from Constants.MOB_BASE_* by category
# and this level (see Enemy._apply_definition()); base_health/base_damage
# below are no longer read by Enemy.
@export var mob_level: int = 1
@export var archetype_category: String = "standard"  # "light", "standard", "heavy", "elite", "boss"
@export var ward_percent: float = 0.0  # spawn Ward pool as a fraction of max health; 0 = none, never regenerates

# Stats
@export var base_health: float = 100.0
@export var base_damage: float = 10.0
@export var armor_value: float = 0.0
@export var evasion_value: float = 0.0
@export var damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var move_speed: float = 3.0
@export var chase_range: float = 15.0
@export var stop_distance: float = 2.3
@export var retreat_distance: float = 0.0

# Combat
@export var is_ranged: bool = false  # spawned on RangedUnit.tscn instead of MeleeUnit.tscn (EnemyRoster)
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var xp_reward: float = 10.0
@export var gold_reward_min: int = 3
@export var gold_reward_max: int = 8

# Spawning
@export var valid_tilesets: Array[String] = []
@export var min_zone_level: int = 1
@export var pack_size_min: int = 1
@export var pack_size_max: int = 3

# Rarity weights (must sum to 100)
@export var weight_normal: int = 75
@export var weight_elite: int = 20
@export var weight_champion: int = 4
@export var weight_ascendant: int = 1
