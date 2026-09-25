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
## Hold the ability's hotkey to aim (PlayerAbilityCast shows a ground
## ring), release to cast centered there, instead of the usual instant
## self-centered nova on press. Reserved for high-commitment single-target
## drops (Comet, Inferno, Stormcall) - not every ability's mechanic reads
## as "aim a spot," so this is opt-in per ability, not automatic.
@export var is_ground_targeted: bool = false

## AoE radius in meters - invented, not doc-sourced, loosely sized off
## each ability's flavor text.
@export var radius: float = 5.0

## Patch v3.7 Section 2. CAST_TIME abilities go through CastTimeHandler's
## windup before actually casting (interruptible by taking damage);
## INSTANT and CHANNELED both fire immediately - channeled cast-speed
## interaction is explicitly deferred, so CHANNELED behaves like INSTANT
## for now (several abilities, e.g. Flame Jets, already implement their
## own bespoke channel duration/tick loop in PlayerAbilityCast.gd,
## entirely separate from this).
enum CastType { INSTANT, CAST_TIME, CHANNELED }
@export var cast_type: CastType = CastType.INSTANT
@export var base_cast_time: float = 0.0       # seconds - CAST_TIME only
@export var base_recovery_time: float = 0.3   # fixed post-cast lockout - not yet consumed anywhere
@export var channel_duration: float = 0.0     # seconds - CHANNELED only, not yet consumed anywhere

## Doc-sourced base crit chance is per "spell type"; abilities here have
## no such classification (all execute as a generic nova), so this is a
## thematic guess at which doc category fits each one.
@export var base_crit_chance: float = 0.05

## Invented upgrade mechanic, not doc-sourced. Lives on the shared
## loaded .tres, same session-persistence as other "owns one" resources.
@export var rank: int = 0
const MAX_RANK := 5
const MOTION_VALUE_PER_RANK := 0.10       # +10% per rank
const COOLDOWN_REDUCTION_PER_RANK := 0.04 # -4% per rank
## Gold cost of the NEXT rank, invented (no doc-sourced economy for this
## any more than GearShop's own prices are) - scales with the rank being
## bought so later upgrades cost more, same shape as most ARPG skill trees.
const UPGRADE_BASE_COST := 20
const UPGRADE_COST_PER_RANK := 15

func get_effective_motion_value() -> float:
	return motion_value * (1.0 + rank * MOTION_VALUE_PER_RANK)

func get_effective_cooldown() -> float:
	return cooldown_seconds * (1.0 - rank * COOLDOWN_REDUCTION_PER_RANK)

## Real cast-time cooldown: rank reduction folded in, then divided by
## Instinct's Action/Cast Speed multiplier (PlayerAbilityCast's own
## treatment) - clamped so the combination of both sources can never take
## more than Constants.MAX_COOLDOWN_REDUCTION off the authored value.
func get_final_cooldown(action_speed_multiplier: float) -> float:
	var safe_multiplier: float = max(action_speed_multiplier, 0.01)
	var reduced: float = get_effective_cooldown() / safe_multiplier
	var floor_cooldown := cooldown_seconds * (1.0 - Constants.MAX_COOLDOWN_REDUCTION)
	return max(reduced, floor_cooldown)

func can_upgrade() -> bool:
	return rank < MAX_RANK

func get_upgrade_cost() -> int:
	return UPGRADE_BASE_COST + rank * UPGRADE_COST_PER_RANK

## Shared groundwork for predict_damage()/roll_damage() - see
## Weapon.gd's own _base_hit() for the same split rationale.
## v4.8: damage = Conduit spell power x (1 + Intellect%) x grade multiplier
## x MV x increased x more, for every damage type. No Conduit equipped
## (conduit_spell_power 0.0) means 0 spell damage - intended (user decision).
func _base_hit(stat_sheet: StatSheet) -> Dictionary:
	# Section 10's Chain Bonus System, stored as a raw fraction on StatSheet,
	# converted to the percent-units DamageCalculator.calculate() expects
	# (each entry "e.g. 8.0 for 8%").
	var increased: Array[float] = [
		stat_sheet.get_chain_bonus(damage_type) * 100.0,
	]
	# calculate()'s power term is base + stat_value x grade. Feeding the
	# boosted spell power in as stat_value (base 0.0) makes it spell power x
	# grade - the grade multiplies spell power rather than adding to it.
	var boosted_spell_power := stat_sheet.conduit_spell_power * (1.0 + stat_sheet.get_spell_power_from_stats())
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		0.0, get_effective_motion_value(), boosted_spell_power, scaling_grade,
		0.5, increased, [], damage_type
	)
	# Patch v4.0 Amulet Exclusive "Skill Level" - each level is +8%
	# effectiveness (brief's own invented value, "subject to balance
	# tuning"), applied as a multiplier on the WHOLE result rather than on
	# spell power alone (calculate()'s own signature/internals are off limits
	# per this patch's "Files to Leave Alone" - scaling final_damage is
	# mathematically identical to scaling the "power" term calculate()
	# computes internally, since power is a pure linear factor in its own
	# final_damage formula).
	var skill_level_mult := 1.0 + stat_sheet.get_skill_level_bonus(damage_type) * 0.08
	result.final_damage *= skill_level_mult
	return {
		"base_damage": result.final_damage,
		"crit_chance": DamageCalculator.get_crit_chance(base_crit_chance, stat_sheet.finesse_crit_bonus),
		"crit_damage_multiplier": DamageCalculator.get_crit_damage_multiplier(stat_sheet.get_crit_damage_bonus()),
	}

## Expected-value blend (not a random roll) - matches PlayerAbilityCast's
## actual cast exactly, so the stat card can't drift from reality.
func predict_damage(stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var hit := _base_hit(stat_sheet)
	return DamageCalculator.get_expected_damage(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])

## Real-cast counterpart to predict_damage() - actually rolls crit.
func roll_damage(stat_sheet: StatSheet) -> Dictionary:
	if stat_sheet == null:
		return {"final_damage": 0.0, "is_critical": false}
	var hit := _base_hit(stat_sheet)
	return DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
