extends Item
class_name Weapon
## Weapon base per Section 07/22. equip_slot decides which slot it fills;
## is_ranged decides melee vs ranged attack behavior independently of
## slot - Player.get_active_weapon() + is_ranged drive attack dispatch,
## so a ranged weapon can sit in either weapon slot.

@export var weapon_type: String = "Greatsword"

## Per-hit damage range: every hit rolls its base damage uniformly within
## [base_damage_min, base_damage_max] (roll_damage()). rolled_base_damage
## (a single per-drop roll, Patch v3.7) is no longer used for damage -
## kept only so older saves/.tres still load.
@export var base_damage_min: float = 0.0
@export var base_damage_max: float = 0.0
@export var rolled_base_damage: float = 0.0

func get_damage_range() -> Vector2:
	return Vector2(base_damage_min, base_damage_max)

## Average base damage (the range midpoint).
func get_base_damage() -> float:
	return (base_damage_min + base_damage_max) / 2.0

## A Conduit adds no flat spell damage (spells carry their own). Its local
## "increased Spell damage" applies to every spell; implicit/global spell
## damage is already summed by EquipmentComponent.compute_misc_bonuses().
func get_conduit_spell_damage_bonus() -> float:
	if not is_conduit:
		return 0.0
	return (get_local_multiplier("local_increased_spell_damage") - 1.0) * 100.0

@export var scaling_grade: Constants.ScalingGrade = Constants.ScalingGrade.C
@export var native_damage_type: Constants.DamageType = Constants.DamageType.KINETIC
@export var infused_damage_type: Constants.DamageType = -1  # -1 = not infused, uses native scaling
@export var is_two_handed: bool = false
@export var is_ranged: bool = false

## Implementation Brief v4.2 - ranged ammo/fire behavior, values set per
## weapon_type by tools/apply_ranged_weapon_stats.gd. Ignored by melee
## weapons. magazine_size 0 = no magazine (bows - ARROW is infinite).
@export var ammo_type: Constants.AmmoType = Constants.AmmoType.PISTOL
@export var magazine_size: int = 12
@export var fire_mode: Constants.FireMode = Constants.FireMode.SEMI_AUTO
@export var pellet_count: int = 1                 # shotguns fire 8-10, each rolling its own crit/spread
@export var pellet_spread_degrees: float = 0.0    # half-angle of the spread cone
@export var fire_rate: float = 0.0                # shots/sec for FULL_AUTO
@export var cycle_time: float = 0.0               # delay between shots for bolt/lever/pump/single-action (per shell when reload_per_shell)
@export var reload_time: float = 1.4
@export var reload_per_shell: bool = false        # pump shotgun loads one shell at a time

## Brief v4.2 table, weapon_type -> [ammo, magazine, mode, pellets, spread, fire_rate, cycle, reload, per_shell]
## "Bow" is the legacy single worn_bow.tres, not in the brief's table - it
## takes the Shortbow row.
const RANGED_PROFILES := {
	"Service Pistol": [Constants.AmmoType.PISTOL, 12, Constants.FireMode.SEMI_AUTO, 1, 0.0, 0.0, 0.0, 1.4, false],
	"Revolver": [Constants.AmmoType.REVOLVER, 6, Constants.FireMode.SINGLE_ACTION, 1, 0.0, 0.0, 0.3, 2.0, false],
	"Machine Pistol": [Constants.AmmoType.PISTOL, 20, Constants.FireMode.FULL_AUTO, 1, 3.0, 12.0, 0.0, 1.2, false],
	"Submachine Gun": [Constants.AmmoType.AUTOMATIC, 30, Constants.FireMode.FULL_AUTO, 1, 2.0, 10.0, 0.0, 1.4, false],
	"Loaded Shotgun": [Constants.AmmoType.SHOTGUN, 6, Constants.FireMode.SEMI_AUTO, 8, 14.0, 0.0, 0.0, 2.2, false],
	"Pump Action Shotgun": [Constants.AmmoType.SHOTGUN, 6, Constants.FireMode.PUMP_ACTION, 10, 16.0, 0.0, 0.6, 3.0, true],
	"Lever Action Rifle": [Constants.AmmoType.RIFLE, 8, Constants.FireMode.LEVER_ACTION, 1, 0.0, 0.0, 0.5, 2.4, false],
	"Bolt Action Rifle": [Constants.AmmoType.RIFLE, 5, Constants.FireMode.BOLT_ACTION, 1, 0.0, 0.0, 0.8, 2.8, false],
	"Battle Rifle": [Constants.AmmoType.RIFLE, 20, Constants.FireMode.SEMI_AUTO, 1, 0.5, 0.0, 0.0, 2.0, false],
	"Machine Gun": [Constants.AmmoType.AUTOMATIC, 60, Constants.FireMode.FULL_AUTO, 1, 4.0, 15.0, 0.0, 3.5, false],
	"Crossbow": [Constants.AmmoType.CROSSBOW_BOLT, 1, Constants.FireMode.SINGLE_ACTION, 1, 0.0, 0.0, 2.5, 0.0, false],
	# v4.7: bow cycle = draw time between shots (0.6s / 1.0s Longbow).
	"Shortbow": [Constants.AmmoType.ARROW, 0, Constants.FireMode.SEMI_AUTO, 1, 1.0, 0.0, 0.6, 0.0, false],
	"Bow": [Constants.AmmoType.ARROW, 0, Constants.FireMode.SEMI_AUTO, 1, 1.0, 0.0, 0.6, 0.0, false],
	"Longbow": [Constants.AmmoType.ARROW, 0, Constants.FireMode.SEMI_AUTO, 1, 0.0, 0.0, 1.0, 0.0, false],
}

## Bow draw time (0 for everything else). Read from RANGED_PROFILES, not
## cycle_time: the bow base .tres files bake cycle_time = 0 from before
## bows had a draw, and the profile table is the source of truth.
func get_draw_time() -> float:
	if not is_ranged or ammo_type != Constants.AmmoType.ARROW:
		return 0.0
	var row: Array = RANGED_PROFILES.get(weapon_type, [])
	return row[6] if not row.is_empty() else cycle_time

## Sets the ammo/fire fields above from RANGED_PROFILES for this weapon_type.
## Used by ItemSerializer for rolled weapons saved before these fields
## existed (they'd otherwise all load as a default semi-auto pistol).
func apply_ranged_profile() -> void:
	var row: Array = RANGED_PROFILES.get(weapon_type, [])
	if row.is_empty():
		return
	ammo_type = row[0]
	magazine_size = row[1]
	fire_mode = row[2]
	pellet_count = row[3]
	pellet_spread_degrees = row[4]
	fire_rate = row[5]
	cycle_time = row[6]
	reload_time = row[7]
	reload_per_shell = row[8]

## Rounds currently loaded. Runtime only (not exported/saved): -1 means
## "never fired yet" and reads as a full magazine, so a fresh or freshly
## loaded weapon starts full. Lives on the Weapon, not PlayerRangedAttack,
## so swapping weapon sets doesn't refill or lose a magazine.
var current_magazine: int = -1

func get_current_magazine() -> int:
	return magazine_size if current_magazine < 0 else current_magazine
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
## descriptive only, NOT read by damage calculation (weapons scale with
## Strength regardless - see _base_hit()). secondary_scaling_stat is ""
## for single-stat lines.
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
## Patch v3.6 per-line extras (see CasterStance). spell_page_modifier changes
## what page-2 spells do: "double_status", "enhanced_status", "pallid".
## stance_buff: "spell_damage", "ward_restore", "esoteric_damage".
@export var spell_page_modifier: String = ""
@export var stance_buff: String = ""

func get_base_crit_chance() -> float:
	return Constants.WEAPON_BASE_CRIT_CHANCE.get(weapon_type, Constants.DEFAULT_BASE_CRIT_CHANCE)

## v4.10 local mods: 1 + (this weapon's own "local_*" affix value)% for
## stat_key (e.g. "local_increased_weapon_damage"). Never enters the global
## StatSheet pools - only this weapon's own numbers.
func get_local_multiplier(stat_key: String) -> float:
	var mult := 1.0
	for affix in affixes:
		if affix.stat_key == stat_key:
			mult += affix.value / 100.0
	return mult

## Base crit with this weapon's local increased crit applied - what the
## card shows and what _base_hit() rolls against (before Agility/gear).
func get_local_crit_chance() -> float:
	return get_base_crit_chance() * get_local_multiplier("local_increased_crit_chance")

## Shared groundwork for predict_damage()/roll_damage(), for one base
## damage value within the weapon's range.
## v4.8: damage = base x (1 + Strength%) x MV x increased x more, for every
## damage type. v4.10: x this weapon's local increased Weapon Damage too.
func _base_hit(base: float, motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	var damage_type: Constants.DamageType = infused_damage_type if infused_damage_type != -1 else native_damage_type
	var boosted_base := base * (1.0 + stat_sheet.get_strength_weapon_multiplier()) * get_local_multiplier("local_increased_weapon_damage")
	# Section 10's Chain Bonus System, stored as a raw fraction on StatSheet,
	# converted to the percent-units DamageCalculator.calculate() expects
	# (each entry "e.g. 8.0 for 8%").
	var increased: Array[float] = [
		stat_sheet.get_chain_bonus(damage_type) * 100.0,
	]
	# scaling_grade is passed but has no effect on weapon damage since
	# stat_value = 0.0 (Strength is applied as a % multiplier on base_damage
	# before this call). Grade only affects spell damage via ability._base_hit().
	# Grade is shown in Alt info and can be degraded by Shard of Tharsis.
	var result: DamageCalculator.DamageResult = DamageCalculator.calculate(
		boosted_base, motion_value, 0.0, scaling_grade,
		0.5, increased, [stat_sheet.unique_damage_multiplier(damage_type)], damage_type
	)
	return {
		"base_damage": result.final_damage,
		"crit_chance": DamageCalculator.get_crit_chance(get_local_crit_chance(), stat_sheet.finesse_crit_bonus),
		"crit_damage_multiplier": DamageCalculator.get_crit_damage_multiplier(stat_sheet.get_crit_damage_bonus()),
	}

## Expected-value blend (not a random roll): the range midpoint (exact,
## since damage is linear in base and the roll is uniform) with crit.
func predict_damage(motion_value: float, stat_sheet: StatSheet) -> float:
	if stat_sheet == null:
		return 0.0
	var hit := _base_hit(get_base_damage(), motion_value, stat_sheet)
	return DamageCalculator.get_expected_damage(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])

## Non-crit (min, max) a hit can deal at this motion value - for cards.
func predict_damage_range(motion_value: float, stat_sheet: StatSheet) -> Vector2:
	if stat_sheet == null:
		return Vector2.ZERO
	var r := get_damage_range()
	return Vector2(_base_hit(r.x, motion_value, stat_sheet)["base_damage"], _base_hit(r.y, motion_value, stat_sheet)["base_damage"])

## A real hit: rolls base damage within the range, then crit.
func roll_damage(motion_value: float, stat_sheet: StatSheet) -> Dictionary:
	if stat_sheet == null:
		return {"final_damage": 0.0, "is_critical": false}
	var r := get_damage_range()
	var hit := _base_hit(randf_range(r.x, r.y), motion_value, stat_sheet)
	return DamageCalculator.apply_crit(hit["base_damage"], hit["crit_chance"], hit["crit_damage_multiplier"])
