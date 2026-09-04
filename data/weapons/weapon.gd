extends Item
class_name Weapon
## Weapon base per Section 07/22. equip_slot decides which slot it fills;
## is_ranged decides melee vs ranged attack behavior independently of
## slot - Player.get_active_weapon() + is_ranged drive attack dispatch,
## so a ranged weapon can sit in either weapon slot.

@export var weapon_type: String = "Greatsword"

## Patch v3.7 Section 5: a damage ROLL RANGE per base, not one fixed
## number - rolled_base_damage is 0.0 until ItemRoller.roll() rolls a
## real value within [base_damage_min, base_damage_max] on drop;
## get_base_damage() falls back to the range's midpoint for anything not
## yet rolled (a base .tres loaded directly, or a hand-authored single).
@export var base_damage_min: float = 0.0
@export var base_damage_max: float = 0.0
@export var rolled_base_damage: float = 0.0

func get_base_damage() -> float:
	if rolled_base_damage > 0.0:
		return rolled_base_damage
	return (base_damage_min + base_damage_max) / 2.0

## Same roll-range pattern, for a Conduit's "Spell Power" - the base
## floor Ability._base_hit() adds to spell damage via StatSheet.
## conduit_spell_power (see Player._on_equipment_changed()). Only
## meaningful when is_conduit is true; 0/0 (and get_spell_power() ->
## 0.0) for every non-Conduit weapon.
@export var spell_power_min: float = 0.0
@export var spell_power_max: float = 0.0
@export var rolled_spell_power: float = 0.0

func get_spell_power() -> float:
	if rolled_spell_power > 0.0:
		return rolled_spell_power
	return (spell_power_min + spell_power_max) / 2.0

@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var native_damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var infused_damage_type: Constants.DamageType = -1  # -1 = not infused, uses native scaling
@export var is_two_handed: bool = false
@export var is_ranged: bool = false
@export var skill_ids: Array[String] = []

## Patch v3.5: which weapon slot this equips into, now that Sidearm/
## Conduit are gone as their own slots - EquipmentComponent.equip()
## routes a Weapon by these instead of equip_slot. Every melee/ranged
## weapon and main-hand caster type (Wand/Staff/Athame/Spell Gauntlet)
## keeps the default; only offhand-type caster foci (Rod/Tome/Fetish/
## Charm/Grimoire/Talisman) set is_offhand = true.
@export var is_main_hand: bool = true
@export var is_offhand: bool = false

## Patch v3.6b: per-line scaling metadata (Constants.Stat name as a
## lowercase string, e.g. "instinct") - user direction (2026-09-02):
## descriptive only, NOT read by damage calculation. scaling_grade above
## stays the only field DamageCalculator/_base_hit() actually consume,
## still resolved via Constants.DAMAGE_TYPE_MAIN_STAT off native_
## damage_type exactly as before - a real per-weapon-line stat override
## is a future system. secondary_scaling_stat is "" for single-stat lines.
@export var primary_scaling_stat: String = ""
@export var secondary_scaling_stat: String = ""

## Patch v3.6b Section 3: Conduit (caster weapon) identity. conduit_
## stance_type values: "spell_library", "unleash", "battlemage",
## "mana_stars", "stance_buff", "passive". spell_page_tag (only meaningful
## for stance_type == "spell_library"): "esoteric", "elemental", "generic".
## unleash_copy_count only meaningful for stance_type == "unleash".
@export var is_conduit: bool = false
@export var conduit_stance_type: String = ""
@export var spell_page_tag: String = ""
@export var unleash_copy_count: int = 0

func get_base_crit_chance() -> float:
	return Constants.WEAPON_BASE_CRIT_CHANCE.get(weapon_type, Constants.DEFAULT_BASE_CRIT_CHANCE)

## Shared groundwork for predict_damage()/roll_damage().
func _base_hit(motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	var damage_type: Constants.DamageType = infused_damage_type if infused_damage_type != -1 else native_damage_type
	var main_stat: Constants.Stat = Constants.DAMAGE_TYPE_MAIN_STAT.get(damage_type, Constants.Stat.STRENGTH)
	var stat_value: float = stat_sheet.get_stat(main_stat)
	var mastery: float = stat_sheet.get_mastery(damage_type)
	# Section 10's Chain Bonus System (Mastery-amplified - see
	# ChainCalculator.amplify_by_mastery()), stored as a raw fraction on
	# StatSheet, converted to the percent-units DamageCalculator.calculate()
	# expects (each entry "e.g. 8.0 for 8%"). Section 12's own Per-Point
	# Values table separately gives main_stat itself "+1% increased
	# <category> damage per point" - stacking on top of, not instead of,
	# main_stat's existing role scaling stat_value above. stat_value is
	# already in raw point units, which is 1:1 with percent at this rate.
	var increased: Array[float] = [
		stat_sheet.get_chain_bonus(damage_type) * 100.0,
		stat_value,
	]
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		get_base_damage(), motion_value, stat_value, scaling_grade,
		0.5, mastery, increased, [], damage_type
	)
	return {
		"base_damage": result.final_damage,
		"crit_chance": DamageCalculator.get_crit_chance(get_base_crit_chance(), stat_sheet.get_stat(Constants.Stat.INSTINCT)),
		"crit_damage_multiplier": DamageCalculator.get_crit_damage_multiplier(stat_sheet.get_stat(Constants.Stat.INTELLECT)),
	}

## Expected-value blend (not a random roll) so the stat card shows one
## stable number instead of jittering on every hover.
func predict_damage(motion_value: float, stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var hit := _base_hit(motion_value, stat_sheet)
	return DamageCalculator.get_expected_damage(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])

## Real-hit counterpart to predict_damage() - actually rolls crit.
func roll_damage(motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	if stat_sheet == null:
		return {"final_damage": 0.0, "is_critical": false}
	var hit := _base_hit(motion_value, stat_sheet)
	return DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
