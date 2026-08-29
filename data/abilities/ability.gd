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

## AoE radius in meters, used by PlayerAbilityCast's self-centered nova
## (see its header comment) and the range-pulse VFX. Not doc-sourced - no
## per-ability range/radius exists anywhere in the referenced docs, so
## these are invented per-spell placeholders (loosely sized off each
## ability's flavor text: Frost Armor is melee-retaliation so it's small,
## Winter's Eye "fires... at nearby enemies" so it's wide), not a real
## AoE-size system.
@export var radius: float = 5.0

## Upgrade rank (0 = unranked/base). Not doc-sourced - no upgrade/leveling
## system exists anywhere in the referenced docs for Abilities, so this
## whole mechanic (rank cap, per-rank scaling formula, and AbilitiesScreen
## making upgrades free/unlimited with no cost gating) is an invented
## placeholder, flagged same as the other invented tuning numbers in this
## project. `rank` lives on the shared loaded .tres Resource, same as
## every other "owns one of each" instance in this project (Slates,
## Items, Weapons) - upgrading persists for the running session (all
## references to this Ability see the new rank) but not across an app
## restart, since there's still no save/load system.
@export var rank: int = 0
const MAX_RANK := 5
const MOTION_VALUE_PER_RANK := 0.10       # +10% per rank
const COOLDOWN_REDUCTION_PER_RANK := 0.04 # -4% per rank

func get_effective_motion_value() -> float:
	return motion_value * (1.0 + rank * MOTION_VALUE_PER_RANK)

func get_effective_cooldown() -> float:
	return cooldown_seconds * (1.0 - rank * COOLDOWN_REDUCTION_PER_RANK)

func can_upgrade() -> bool:
	return rank < MAX_RANK

## Predicted final damage against a given StatSheet - the EXACT
## calculation PlayerAbilityCast._cast() uses when actually casting
## (base_weapon_damage passed as 1.0, since abilities aren't tied to a
## Weapon - see PlayerAbilityCast.gd's header). Centralized here, called
## from both the real cast path and ItemCard's stat-card display, so the
## displayed prediction can never drift from what casting actually does.
## grade_roll_t is fixed at 0.5 (same as the real cast), so this is a
## single deterministic number, not a min-max range.
func predict_damage(stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.ARCANE)
	var stat_value: float = stat_sheet.get_stat(main_stat)
	var mastery: float = stat_sheet.get_mastery(damage_type)
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		1.0, get_effective_motion_value(), stat_value, scaling_grade,
		0.5, mastery, [], [], damage_type
	)
	return result.final_damage
