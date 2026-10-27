extends Resource
class_name StatSheet
## Strength/Agility/Intellect plus the derived bonuses that feed combat.
## The exported fields are the fixed baseline (player_baseline.tres). Level,
## gear and Slate bonuses are pushed in by Player.gd and re-derived on load,
## never saved.

@export var strength: float = 0.0
@export var agility: float = 0.0
@export var intellect: float = 0.0

## Constants.Stat -> float from equipped gear.
var equipment_bonus: Dictionary = {}

## Constants.Stat -> float from placed Slates, chain-amplified
## (ChainCalculator.slate_stat_bonuses()).
var slate_bonus: Dictionary = {}

## Flat bonus to all three stats from character level. Kept separate because
## the baseline fields are the shared player_baseline.tres and must not mutate.
var level_bonus: float = 0.0

## DamageType -> increased damage fraction from Fate Board chains.
var chain_bonus_by_tag: Dictionary = {}

## "fire"/"cold"/"lightning"/"esoteric" -> percent from gear. Esoteric covers
## Aetheric/Entropic/Pale; Physical has no Resistance (Armor covers it).
var equipment_resistance: Dictionary = {}

func get_stat(stat: Constants.Stat) -> float:
	var base := 0.0
	match stat:
		Constants.Stat.STRENGTH: base = strength
		Constants.Stat.AGILITY: base = agility
		Constants.Stat.INTELLECT: base = intellect
	base += level_bonus
	base += equipment_bonus.get(stat, 0.0)
	base += slate_bonus.get(stat, 0.0)
	return base

func set_equipment_bonus(bonus: Dictionary) -> void:
	equipment_bonus = bonus

func set_slate_bonus(bonus: Dictionary) -> void:
	slate_bonus = bonus

## Derived values - callers should always go through these, never read
## strength/agility/intellect directly for a gameplay effect. Every
## "increased" getter returns a fraction (0.01 per point).

## Strength: +4 Life per point.
func get_max_life_bonus() -> float:
	return get_stat(Constants.Stat.STRENGTH) * 4.0

## Strength: +1% increased weapon base damage per point (Weapon._base_hit()).
func get_strength_weapon_multiplier() -> float:
	return get_stat(Constants.Stat.STRENGTH) * 0.01

## Agility: +1% increased Evasion per point, in the same increased% bracket
## as gear's increased_evasion.
func get_evasion_from_stats() -> float:
	return get_stat(Constants.Stat.AGILITY) * 0.01

## Total Evasion Rating: (gear base + flat affixes) x (1 + gear increased% +
## Agility's increased%).
func get_total_evasion(equipment: EquipmentComponent) -> float:
	return equipment.get_total_evasion(get_evasion_from_stats()) if equipment else 0.0

## Agility: +1% increased Critical Strike Chance per point - multiplicative
## on the weapon/ability's base crit (DamageCalculator.get_crit_chance()).
func get_crit_chance_from_stats() -> float:
	return get_stat(Constants.Stat.AGILITY) * 0.01

## Agility: +1% increased Attack Speed per point, summed with gear's
## attack_speed in Player.get_action_speed_multiplier().
func get_attack_speed_from_stats() -> float:
	return get_stat(Constants.Stat.AGILITY) * 0.01

## Intellect: +1% increased spell damage per point (Ability._increased_percents()).
func get_spell_power_from_stats() -> float:
	return get_stat(Constants.Stat.INTELLECT) * 0.01

## Intellect: +3 Mana per point.
func get_mana_from_stats() -> float:
	return get_stat(Constants.Stat.INTELLECT) * 3.0

## Intellect: +0.5% increased Ward per point, multiplying gear's Ward value.
const WARD_PER_INTELLECT := 0.005

func get_ward_increased_from_stats() -> float:
	return get_stat(Constants.Stat.INTELLECT) * WARD_PER_INTELLECT

func get_chain_bonus(tag: Constants.DamageType) -> float:
	return chain_bonus_by_tag.get(tag, 0.0)

func set_chain_bonus_by_tag(bonus: Dictionary) -> void:
	chain_bonus_by_tag = bonus

## Resistance key covering damage_type; null for Physical.
static func resistance_key_for(damage_type: Constants.DamageType):
	match damage_type:
		Constants.DamageType.FIRE: return "fire"
		Constants.DamageType.COLD: return "cold"
		Constants.DamageType.LIGHTNING: return "lightning"
		Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE: return "esoteric"
	return null

func get_resistance(damage_type: Constants.DamageType) -> float:
	var key = resistance_key_for(damage_type)
	return equipment_resistance.get(key, 0.0) + spell_resistance.get(key, 0.0) if key else 0.0

## Resistance and maximum Resistance from switched-on spells (Triangulation,
## Dark Arts), key -> percent; PlayerAbilityCast._tick_toggles() sets them.
var spell_resistance: Dictionary = {}
var spell_max_resistance: Dictionary = {}

## Resistance counts up to its maximum: BASE_MAX_RESISTANCE plus "+% to
## maximum X Resistance" (jewels), never past the hard ceiling.
const BASE_MAX_RESISTANCE := 75.0

func get_max_resistance(damage_type: Constants.DamageType) -> float:
	var key = resistance_key_for(damage_type)
	if key == null:
		return BASE_MAX_RESISTANCE
	return minf(BASE_MAX_RESISTANCE + get_misc_bonus("max_%s_resistance" % key) + spell_max_resistance.get(key, 0.0), DamageCalculator.RESISTANCE_CEILING)

## What a hit is resisted by: Resistance minus Shred, capped at the maximum,
## so Resistance above the cap soaks Shred first.
func get_effective_resistance(damage_type: Constants.DamageType, shred: float = 0.0) -> float:
	return minf(get_resistance(damage_type) - shred, get_max_resistance(damage_type))

func set_equipment_resistance(resistance: Dictionary) -> void:
	equipment_resistance = resistance

## "increased_damage" affixes, generic and per DamageType (see
## get_increased_damage_percent()).
var increased_damage_generic: float = 0.0
var increased_damage_by_type: Dictionary = {}

## Routes a rolled ItemAffix to the bucket its stat_key belongs to.
func apply_affix(affix: ItemAffix) -> void:
	if EquipmentComponent.AFFIX_STAT_KEYS.has(affix.key()):
		var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[affix.key()]
		equipment_bonus[stat] = equipment_bonus.get(stat, 0.0) + affix.value
		return
	if EquipmentComponent.RESISTANCE_AFFIX_KEYS.has(affix.key()):
		var key: String = EquipmentComponent.RESISTANCE_AFFIX_KEYS[affix.key()]
		equipment_resistance[key] = equipment_resistance.get(key, 0.0) + affix.value
		return
	if affix.stat_key == "increased_damage":
		if affix.is_generic or affix.damage_type == -1:
			increased_damage_generic += affix.value
		else:
			var dt: Constants.DamageType = affix.damage_type
			increased_damage_by_type[dt] = increased_damage_by_type.get(dt, 0.0) + affix.value

## Recomputes the increased_damage buckets from equipped items' affixes.
func apply_equipment_affixes(items: Array[Item]) -> void:
	increased_damage_generic = 0.0
	increased_damage_by_type = {}
	for item in items:
		for affix in item.get_effective_affixes():
			if affix.stat_key == "increased_damage":
				apply_affix(affix)

## The player's UniqueEffects (set by Player), for unique_damage_multiplier().
var unique_effects: UniqueEffects

## "More" multiplier from equipped Uniques on a hit of damage_type.
func unique_damage_multiplier(damage_type: int) -> float:
	return unique_effects.damage_multiplier(damage_type) if unique_effects else 1.0

## The player's StatusEffectComponent (set by Player): Pallid and Meager on
## the player lower the damage they deal.
var status_effects: StatusEffectComponent

## Fate Board Mastery per damage type, as a fraction (0.3 = 30% more), from
## ChainCalculator.mastery_by_tag().
var mastery_by_tag: Dictionary = {}

func get_mastery(damage_type: int) -> float:
	return mastery_by_tag.get(damage_type, 0.0)

## Every "more" multiplier on the player's own hits from outside the skill
## itself: Uniques, Mastery, then the player's own debuffs.
func outgoing_more_multiplier(damage_type: int) -> float:
	return unique_damage_multiplier(damage_type) * (1.0 + get_mastery(damage_type)) * (status_effects.get_outgoing_damage_multiplier() if status_effects else 1.0) * inner_power_multiplier(damage_type)

## Inner Power, set by PlayerAbilityCast each frame: prepared on the bar it
## forbids Physical damage; switched on it adds more Aetheric damage.
var no_physical_damage := false
var inner_power_on := false
const INNER_POWER_AETHERIC_MORE := 0.1
## The current bonus (its Still Waters twist doubles it).
var inner_power_more := INNER_POWER_AETHERIC_MORE

func inner_power_multiplier(damage_type: int) -> float:
	if no_physical_damage and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.PHYSICAL:
		return 0.0
	if inner_power_on and damage_type == Constants.DamageType.AETHERIC:
		return 1.0 + inner_power_more
	return 1.0

## Percent totals (20.0 = +20%), re-derived on every stat refresh.
var cast_speed_bonus: float = 0.0
var cooldown_recovery_rate: float = 0.0

func get_effective_cast_time(base_cast_time: float) -> float:
	return base_cast_time / (1.0 + cast_speed_bonus / 100.0)

func get_effective_cooldown(base_cooldown: float) -> float:
	return base_cooldown / (1.0 + cooldown_recovery_rate / 100.0)

## Slate affix: adds conversion_percent of current Cast Speed to Cooldown
## Recovery Rate. Must be re-applied on every stat refresh.
func apply_cast_speed_to_cooldown_conversion(conversion_percent: float) -> void:
	var converted := cast_speed_bonus * (conversion_percent / 100.0)
	cooldown_recovery_rate += converted

## Increased Spell damage % from the equipped primary Conduit, pushed in by
## Player._on_equipment_changed().
var conduit_spell_damage_bonus: float = 0.0
## Extra projectiles the primary Conduit gives projectile spells.
var conduit_additional_projectiles: int = 0

## Pushed in by Player._apply_derived_stats(). stat_evasion_bonus is the
## total Evasion Rating, for display. finesse_crit_bonus (pre-v4.8 name) is
## the increased crit fraction from Agility and gear.
var stat_evasion_bonus: float = 0.0
var finesse_crit_bonus: float = 0.0

## stat_key -> summed percent for every other gear affix
## (EquipmentComponent.compute_misc_bonuses()).
var misc_bonus: Dictionary = {}

func get_misc_bonus(key: String) -> float:
	return misc_bonus.get(key, 0.0) + slate_misc_bonus.get(key, 0.0)

## True while the player holds a weapon stance (Player keeps it in sync),
## for "increased Spell damage while in stance".
var in_stance: bool = false

## Placed Slates' non-attribute modifiers, by canonical key (ChainCalculator.
## slate_misc_bonuses()), added on top of gear's.
var slate_misc_bonus: Dictionary = {}

## Total "% increased" for a hit of damage_type: generic, the type's own and
## its category's (Physical/Elemental/Esoteric), plus attack damage for
## weapon hits. Spell damage is added by Ability itself.
func get_increased_damage_percent(damage_type: int, is_attack: bool) -> float:
	var total: float = increased_damage_generic + increased_damage_by_type.get(damage_type, 0.0)
	total += get_misc_bonus("increased_generic_damage") + get_misc_bonus(StatKeys.type_damage_key(damage_type))
	var category: int = Constants.DAMAGE_TYPE_CATEGORY.get(damage_type, -1)
	total += get_misc_bonus(StatKeys.CATEGORY_DAMAGE_KEYS.get(category, ""))
	if is_attack:
		total += get_misc_bonus("increased_attack_damage")
	total += get_misc_bonus("hollow_damage_ward_drain")  # corruption: Hollow
	# Butterfly: a share of increased Movement Speed as increased damage.
	if unique_effects and unique_effects.has(UniqueEffects.DAMAGE_FROM_MOVE_SPEED):
		total += get_misc_bonus("move_speed") * unique_effects.value(UniqueEffects.DAMAGE_FROM_MOVE_SPEED) / 100.0
	return total

## Fraction added to the base crit multiplier. crit_damage and
## crit_damage_increased are the same effect under two keys.
func get_crit_damage_bonus() -> float:
	return (get_misc_bonus("crit_damage") + get_misc_bonus("crit_damage_increased")) / 100.0

## "+% to Critical Strike Multiplier": added to the base 150%, as a fraction.
func get_crit_multiplier_bonus() -> float:
	return get_misc_bonus("crit_multiplier") / 100.0

## What a crit multiplies a hit by: x1 (no extra damage) with Sanctum of the Mage.
func get_crit_damage_multiplier() -> float:
	if unique_effects and unique_effects.has(UniqueEffects.NO_CRIT_DAMAGE):
		return 1.0
	return DamageCalculator.get_crit_damage_multiplier(get_crit_damage_bonus(), get_crit_multiplier_bonus())

func set_misc_bonus(bonus: Dictionary) -> void:
	misc_bonus = bonus

## --- Mod pool getters (all read misc_bonus) --------------------------------

func get_gear_crit_chance_bonus() -> float:
	return get_misc_bonus("crit_chance_increased") / 100.0

## ailment_id is a StatusEffectComponent effect_id. The family lines (v5.5)
## add to every damaging or every control ailment.
func get_ailment_chance_bonus(ailment_id: String) -> float:
	var family := "damaging_ailment_chance" if StatusEffectComponent.DAMAGING_AILMENT_IDS.has(ailment_id) else "control_ailment_chance"
	return (get_misc_bonus("ailment_chance_%s" % ailment_id) + get_misc_bonus(family)) / 100.0

func get_ailment_damage_bonus(ailment_id: String) -> float:
	return get_misc_bonus("increased_ailment_damage_%s" % ailment_id) / 100.0

func get_ailment_duration_bonus(ailment_id: String) -> float:
	return (get_misc_bonus("increased_ailment_duration_%s" % ailment_id) + get_misc_bonus("ailment_duration")) / 100.0

func get_dot_multiplier() -> float:
	return get_misc_bonus("dot_multiplier") / 100.0

func get_ailment_tick_rate_bonus() -> float:
	return get_misc_bonus("ailment_tick_rate") / 100.0

func get_ailment_ignore_chance() -> float:
	return get_misc_bonus("ailment_ignore_chance") / 100.0

## Type-specific plus Elemental Penetration (additive); Esoteric Penetration
## covers Aetheric, Entropic and Pale.
func get_penetration(damage_type: Constants.DamageType) -> float:
	match damage_type:
		Constants.DamageType.FIRE:
			return get_misc_bonus("fire_penetration") + get_misc_bonus("elemental_penetration")
		Constants.DamageType.COLD:
			return get_misc_bonus("cold_penetration") + get_misc_bonus("elemental_penetration")
		Constants.DamageType.LIGHTNING:
			return get_misc_bonus("lightning_penetration") + get_misc_bonus("elemental_penetration")
		Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE:
			return get_misc_bonus("esoteric_penetration")
	return 0.0

func get_physical_shred() -> float:
	return get_misc_bonus("physical_shred") / 100.0

## Physical damage taken as Elemental: [[fraction, DamageType], ...].
func get_phys_damage_shift() -> Array:
	var shifts := []
	if get_misc_bonus("phys_as_fire") > 0.0:
		shifts.append([get_misc_bonus("phys_as_fire") / 100.0, Constants.DamageType.FIRE])
	if get_misc_bonus("phys_as_cold") > 0.0:
		shifts.append([get_misc_bonus("phys_as_cold") / 100.0, Constants.DamageType.COLD])
	if get_misc_bonus("phys_as_lightning") > 0.0:
		shifts.append([get_misc_bonus("phys_as_lightning") / 100.0, Constants.DamageType.LIGHTNING])
	# "as Elemental" splits evenly across the three.
	var elemental := get_misc_bonus("phys_as_elemental") / 300.0
	if elemental > 0.0:
		for type in [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]:
			shifts.append([elemental, type])
	return shifts

## Maximum Mana, pushed in by Player._apply_derived_stats(), for the "% of
## maximum Mana as added damage" modifiers (unique Slates).
var current_max_mana: float = 0.0

## Flat damage from "Gain X% of your maximum Mana as added ..." (key's total X).
func added_damage_from_mana(key: String) -> float:
	return current_max_mana * get_misc_bonus(key) / 100.0

func get_damage_from_mana_percent() -> float:
	return get_misc_bonus("damage_from_mana") / 100.0

func get_reduced_damage_taken(category: Constants.DamageCategory) -> float:
	match category:
		Constants.DamageCategory.PHYSICAL:
			return get_misc_bonus("reduced_physical_taken") / 100.0
		Constants.DamageCategory.ELEMENTAL:
			return get_misc_bonus("reduced_elemental_taken") / 100.0
		Constants.DamageCategory.ESOTERIC:
			return get_misc_bonus("reduced_esoteric_taken") / 100.0
	return 0.0

func get_ward_delay_reduction() -> float:
	return get_misc_bonus("ward_delay_reduction")

## Skill Level mods. Every Ability is a spell, so the _spell variants always apply.
const _V40_DAMAGE_TYPE_KEYS := {
	Constants.DamageType.KINETIC: "kinetic", Constants.DamageType.PIERCING: "piercing",
	Constants.DamageType.EXPLOSIVE: "explosive", Constants.DamageType.FIRE: "fire",
	Constants.DamageType.COLD: "cold", Constants.DamageType.LIGHTNING: "lightning",
	Constants.DamageType.AETHERIC: "aetheric", Constants.DamageType.ENTROPIC: "entropic",
	Constants.DamageType.PALE: "pale",
}

func get_skill_level_bonus(damage_type: Constants.DamageType) -> int:
	var bonus: int = int(get_misc_bonus("skill_level_all")) + int(get_misc_bonus("skill_level_spells"))
	var type_key: String = _V40_DAMAGE_TYPE_KEYS.get(damage_type, "")
	if type_key != "":
		bonus += int(get_misc_bonus("skill_level_%s" % type_key))
		bonus += int(get_misc_bonus("skill_level_spell_%s" % type_key))
	# Sanctum of the Mage: +1 per N% of total (capped) Elemental Resistance.
	if unique_effects and unique_effects.has(UniqueEffects.ELEMENTAL_LEVELS_PER_RES) \
			and Constants.DAMAGE_TYPE_CATEGORY.get(damage_type) == Constants.DamageCategory.ELEMENTAL:
		var per := maxf(unique_effects.value(UniqueEffects.ELEMENTAL_LEVELS_PER_RES), 1.0)
		var total := 0.0
		for t in [Constants.DamageType.FIRE, Constants.DamageType.COLD, Constants.DamageType.LIGHTNING]:
			total += maxf(get_effective_resistance(t), 0.0)
		bonus += floori(total / per)
	return bonus

## Flat addition to the shield's block_chance.
func get_block_chance_bonus() -> float:
	return get_misc_bonus("block_chance_bonus") / 100.0

## "% increased Chance to Block", applied after the flat points.
func get_block_chance_multiplier() -> float:
	return 1.0 + get_misc_bonus("increased_block_chance") / 100.0
