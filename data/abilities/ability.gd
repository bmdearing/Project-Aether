extends Resource
class_name Ability
## A spell. Damage comes from its per-level base damage
## (base_damage_min/max); tags decide which gear modifiers apply. motion_value and scaling_grade are legacy data only.

@export var ability_id: String
@export var display_name: String
@export var description: String                 # player-facing flavor text only - no tips/cross-refs per style rules
@export var damage_type: Constants.DamageType
@export var motion_value: float = 1.0
@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var cooldown_seconds: float = 0.0
@export var resource_cost: float = 0.0
@export var can_trigger_riposte: bool = false    # high-MV committed attacks only
@export var is_auto_cast_eligible: bool = true   # false for e.g. Riposte itself
@export var applies_status_effects: Array[String] = []  # status effect ids, e.g. "chill", "ignite"
## Chance each applies_status_effects entry lands per hit, before the
## caster's "+% chance to cause X" gear.
@export var status_chance: float = 0.25
## Set on a cast's copy (CasterStance Pallid page): these always land.
var guaranteed_statuses: Array[String] = []
## Hold the hotkey to aim a ground reticle, release to cast there.
@export var is_ground_targeted: bool = false
## An Unleash conduit's stance fires several copies of it.
@export var unleashable: bool = false
## Per-cast "more" damage multiplier set on a cast's copy (CasterStance buffs).
var extra_more: float = 1.0

## AoE radius in meters - invented, not doc-sourced, loosely sized off
## each ability's flavor text.
@export var radius: float = 5.0

## CAST_TIME waits out an interruptible windup (CastTimeHandler). CHANNELED
## fires immediately like INSTANT; channel loops live in PlayerAbilityCast.
enum CastType { INSTANT, CAST_TIME, CHANNELED }
@export var cast_type: CastType = CastType.INSTANT
@export var base_cast_time: float = 0.0       # seconds - CAST_TIME only
@export var base_recovery_time: float = 0.3   # fixed post-cast lockout - not yet consumed anywhere
@export var channel_duration: float = 0.0     # seconds - CHANNELED only, not yet consumed anywhere

@export var base_crit_chance: float = 0.05

## Base damage per hit at level 1, before any modifier. Grows each level
## by DAMAGE_GROWTH_PER_LEVEL (compounding).
@export var base_damage_min: float = 0.0
@export var base_damage_max: float = 0.0

## What this spell is, and so which modifiers apply to it (see TAG_*).
## The damage type and "Spell" are implied and not listed here.
@export var tags: Array[StringName] = []

## Limit-tagged spells: how many can be active at once, before bonuses.
@export var base_limit: int = 0

const TAG_AREA := &"area"
const TAG_PROJECTILE := &"projectile"
const TAG_DURATION := &"duration"
const TAG_LIMIT := &"limit"
const TAG_CHANNELLING := &"channelling"
const TAG_MOVEMENT := &"movement"
const TAG_UTILITY := &"utility"
const TAG_WARCRY := &"warcry"
const TAG_NAMES := {
	TAG_AREA: "Area of Effect", TAG_PROJECTILE: "Projectile", TAG_DURATION: "Duration",
	TAG_LIMIT: "Limit", TAG_CHANNELLING: "Channelling", TAG_MOVEMENT: "Movement", TAG_UTILITY: "Utility",
	TAG_WARCRY: "Warcry",
}

## Spell level 1-20, raised with gold + Crystallized Aether. Gear's
## "+N to level of Spells" adds on top (get_effective_level()) and can push
## past MAX_LEVEL, where the over-cap bonuses below apply. Lives on the
## shared .tres; GameState.ability_levels persists it.
@export var level: int = 1
const MAX_LEVEL := 20
const DAMAGE_GROWTH_PER_LEVEL := 0.095

## Per level above MAX_LEVEL.
const OVERCAP_MORE_DAMAGE := 0.03
const OVERCAP_AREA := 0.02
const OVERCAP_DURATION := 0.03
const OVERCAP_PROJECTILE_SPEED := 0.03
const OVERCAP_COOLDOWN_REDUCTION := 0.01
const OVERCAP_LEVELS_PER_LIMIT := 4

## Upgrade cost from level L to L+1: cheap at 1, ~120 Aether for 19 -> 20.
const AETHER_COST_MIN := 2.0
const AETHER_COST_MAX := 120.0
const AETHER_COST_CURVE := 1.6
const GOLD_COST_BASE := 20.0
const GOLD_COST_EXPONENT := 1.4
const AETHER_CURRENCY := &"crystallized_aether"

func get_effective_level(stat_sheet: StatSheet) -> int:
	return level + (stat_sheet.get_skill_level_bonus(damage_type) if stat_sheet else 0)

func get_levels_over_cap(stat_sheet: StatSheet) -> int:
	return maxi(get_effective_level(stat_sheet) - MAX_LEVEL, 0)

func get_status_chance(effect_id: String) -> float:
	return 1.0 if guaranteed_statuses.has(effect_id) else status_chance

## Rolls this spell's statuses, then the caster's gear-only ailment chances.
func apply_statuses(enemy: Enemy, source: Node, hit_damage: float) -> void:
	if enemy == null or enemy.status_effects == null:
		return
	for effect_id in applies_status_effects:
		enemy.status_effects.try_apply(effect_id, source, hit_damage, get_status_chance(effect_id.trim_prefix("enhanced:")))
	enemy.status_effects.roll_gear_ailments(source, hit_damage, applies_status_effects)

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)

## Player-facing tag list: Spell, the listed tags, then the damage type.
func get_tag_names() -> PackedStringArray:
	var names := PackedStringArray(["Spell"])
	for tag in tags:
		names.append(TAG_NAMES.get(tag, String(tag).capitalize()))
	if deals_damage():
		names.append(Constants.DAMAGE_TYPE_NAME.get(damage_type, "?"))
	return names

func deals_damage() -> bool:
	return base_damage_max > 0.0

func get_base_damage_range(stat_sheet: StatSheet = null) -> Vector2:
	var growth := pow(1.0 + DAMAGE_GROWTH_PER_LEVEL, get_effective_level(stat_sheet) - 1)
	return Vector2(base_damage_min, base_damage_max) * growth

func get_effective_cooldown(stat_sheet: StatSheet = null) -> float:
	var reduction := get_levels_over_cap(stat_sheet) * OVERCAP_COOLDOWN_REDUCTION
	if stat_sheet:
		reduction += stat_sheet.get_misc_bonus("cooldown_recovery_rate") / 100.0
	return cooldown_seconds / (1.0 + maxf(reduction, 0.0))

## Cooldown after level/gear reduction and action speed, with the total
## reduction capped at Constants.MAX_COOLDOWN_REDUCTION.
func get_final_cooldown(action_speed_multiplier: float, stat_sheet: StatSheet = null) -> float:
	var safe_multiplier: float = max(action_speed_multiplier, 0.01)
	var reduced: float = get_effective_cooldown(stat_sheet) / safe_multiplier
	var floor_cooldown := cooldown_seconds * (1.0 - Constants.MAX_COOLDOWN_REDUCTION)
	return max(reduced, floor_cooldown)

func get_mana_cost(stat_sheet: StatSheet = null) -> float:
	var reduction := stat_sheet.get_misc_bonus("mana_cost_reduction") / 100.0 if stat_sheet else 0.0
	return resource_cost * (1.0 - clampf(reduction, -1.0, 0.75))  # negative = costs more (Crown of the Ninth Bell)

func get_radius(stat_sheet: StatSheet = null) -> float:
	if not has_tag(TAG_AREA):
		return radius
	var bonus := get_levels_over_cap(stat_sheet) * OVERCAP_AREA
	if stat_sheet:
		bonus += stat_sheet.get_misc_bonus("increased_aoe_radius") / 100.0
	return radius * (1.0 + bonus)

func get_duration_multiplier(stat_sheet: StatSheet = null) -> float:
	if not has_tag(TAG_DURATION):
		return 1.0
	var bonus := get_levels_over_cap(stat_sheet) * OVERCAP_DURATION
	if stat_sheet:
		bonus += stat_sheet.get_misc_bonus("skill_effect_duration") / 100.0
	return 1.0 + bonus

func get_projectile_speed_multiplier(stat_sheet: StatSheet = null) -> float:
	if not has_tag(TAG_PROJECTILE):
		return 1.0
	var bonus := get_levels_over_cap(stat_sheet) * OVERCAP_PROJECTILE_SPEED
	if stat_sheet:
		bonus += (stat_sheet.get_misc_bonus("projectile_speed") - stat_sheet.get_misc_bonus("reduced_projectile_speed")) / 100.0
	return maxf(1.0 + bonus, 0.2)

func get_limit(stat_sheet: StatSheet = null) -> int:
	return base_limit + get_levels_over_cap(stat_sheet) / OVERCAP_LEVELS_PER_LIMIT

func can_upgrade() -> bool:
	return level < MAX_LEVEL

func get_upgrade_gold_cost() -> int:
	return int(round(GOLD_COST_BASE * pow(level, GOLD_COST_EXPONENT)))

func get_upgrade_aether_cost() -> int:
	var t := float(level - 1) / float(MAX_LEVEL - 2)
	return int(round(AETHER_COST_MIN + (AETHER_COST_MAX - AETHER_COST_MIN) * pow(clampf(t, 0.0, 1.0), AETHER_COST_CURVE)))

## Every "increased" modifier this spell's tags let in, as percents.
func _increased_percents(stat_sheet: StatSheet) -> Array[float]:
	var increased: Array[float] = [
		stat_sheet.get_chain_bonus(damage_type) * 100.0,
		stat_sheet.get_spell_power_from_stats() * 100.0,
		stat_sheet.get_misc_bonus("increased_spell_damage"),
		stat_sheet.conduit_spell_damage_bonus,
		stat_sheet.get_increased_damage_percent(damage_type, false),
	]
	if stat_sheet.in_stance:
		increased.append(stat_sheet.get_misc_bonus("spell_damage_in_stance"))
	if has_tag(TAG_AREA):
		increased.append(stat_sheet.get_misc_bonus("increased_area_damage"))
	return increased

func _base_hit(base_damage: float, stat_sheet: StatSheet) -> Dictionary:
	var more: Array[float] = [1.0 + get_levels_over_cap(stat_sheet) * OVERCAP_MORE_DAMAGE, extra_more, stat_sheet.unique_damage_multiplier(damage_type)]
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		base_damage, 1.0, 0.0, scaling_grade, 0.5, _increased_percents(stat_sheet), more, damage_type
	)
	return {
		"base_damage": result.final_damage,
		"crit_chance": DamageCalculator.get_crit_chance(base_crit_chance, stat_sheet.finesse_crit_bonus),
		"crit_damage_multiplier": DamageCalculator.get_crit_damage_multiplier(stat_sheet.get_crit_damage_bonus()),
	}

## Expected value (range midpoint, with crit).
func predict_damage(stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var r := get_base_damage_range(stat_sheet)
	var hit := _base_hit((r.x + r.y) / 2.0, stat_sheet)
	return DamageCalculator.get_expected_damage(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])

## Non-crit (min, max) a cast deals with every modifier applied - for cards.
func predict_damage_range(stat_sheet: StatSheet) -> Vector2:
	if stat_sheet == null:
		return get_base_damage_range()
	var r := get_base_damage_range(stat_sheet)
	return Vector2(_base_hit(r.x, stat_sheet)["base_damage"], _base_hit(r.y, stat_sheet)["base_damage"])

func roll_damage(stat_sheet: StatSheet) -> Dictionary:
	if stat_sheet == null:
		return {"final_damage": 0.0, "is_critical": false}
	var r := get_base_damage_range(stat_sheet)
	var hit := _base_hit(randf_range(r.x, r.y), stat_sheet)
	return DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
