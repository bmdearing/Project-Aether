extends Resource
class_name StatSheet
## The six baseline stats (Section 12 Stat System). Per Section 12: "All
## stats come from gear, Slates, Jewels, and infusions — no manual
## allocation on level up." The raw fields below are the character's
## permanently-fixed baseline (player_baseline.tres, 10.0 flat - an
## invented vertical-slice testing value, no doc-sourced baseline exists);
## equipment_bonus and slate_bonus are what grow a stat past that - gear
## (EquipmentComponent.compute_stat_bonuses()) and placed Slates
## (FateBoard.compute_stat_bonuses()) respectively. Player.gd pushes a
## fresh total into each on every equip/unequip or Slate placement/
## removal. Neither is persisted separately - equipment_bonus is
## re-derived from GameState.equipment_refs (already saved) on every
## load; slate_bonus would need Fate Board LAYOUT to be saved to survive
## a reload the same way, which it isn't yet (README flagged gap) - so
## it's always just re-derived from whatever's currently placed, same as
## equipment_bonus, no separate save/load path needed for either.

@export var vitality: float = 0.0
@export var strength: float = 0.0
@export var instinct: float = 0.0
@export var arcane: float = 0.0
@export var enigma: float = 0.0
@export var intellect: float = 0.0

@export var supercharged_stat: Constants.Stat = -1  # -1 = none declared
const SUPERCHARGE_MULTIPLIER := 1.25

## Constants.Stat -> float, recomputed whenever equipment changes (see
## Player.gd). Not @export'd/persisted - always re-derived from currently
## equipped gear, never stored independently (see header).
var equipment_bonus: Dictionary = {}

## Constants.Stat -> float, recomputed whenever the Fate Board changes
## (Player._apply_fate_board_bonuses()) - the Slate-system counterpart to
## equipment_bonus, summing every PLACED Slate's flat_<stat> modifiers
## (FateBoard.compute_stat_bonuses(), Section 10's "Main Stat"/"Random
## Stat" per-tile formula, 5+ tile Slates only). Not persisted separately,
## same reasoning as equipment_bonus - Fate Board layout itself isn't
## saved yet either (README flagged gap), so there's nothing to re-derive
## FROM across a reload regardless.
var slate_bonus: Dictionary = {}

## Mastery: DamageType -> float bonus (e.g. 0.5 for "+0.5 Cold Mastery").
## Never universal - keyed per tag per Section 10. Sourced entirely from
## placed Slates' "mastery" modifiers (FateBoard.compute_mastery_bonuses())
## - already consumed by DamageCalculator.calculate()'s mastery_bonus
## param via Weapon/Ability._base_hit(), which read this dict but nothing
## populated it before the Slate-system stat wiring pass.
var mastery_by_tag: Dictionary = {}

## Section 10/23: "Mastery... multiplying the per-tile chain bonus rate."
## DamageType -> float fraction (e.g. 0.2375 for +23.75%), the Chain Bonus
## System's own output (ChainCalculator.amplify_by_mastery()) after
## Mastery amplification - fed into Weapon/Ability._base_hit()'s
## increased_percents pool as real "increased <category> damage".
var chain_bonus_by_tag: Dictionary = {}

## Patch v3.2 "Revision - Resistance System": String key ("fire"/"cold"/
## "lightning"/"esoteric") -> float percent (e.g. 20.0 for 20%), summed
## from equipped gear's resistance affixes (EquipmentComponent.
## compute_resistance_bonuses()). Esoteric is unified across Aetheric/
## Entropic/Pale per the patch - one value covers all three. Physical
## (Kinetic/Piercing/Explosive) has no Resistance stat; Armor still
## covers it, unchanged by this patch.
var equipment_resistance: Dictionary = {}

func get_stat(stat: Constants.Stat) -> float:
	var base := 0.0
	match stat:
		Constants.Stat.VITALITY: base = vitality
		Constants.Stat.STRENGTH: base = strength
		Constants.Stat.INSTINCT: base = instinct
		Constants.Stat.ARCANE: base = arcane
		Constants.Stat.ENIGMA: base = enigma
		Constants.Stat.INTELLECT: base = intellect
	base += equipment_bonus.get(stat, 0.0)
	base += slate_bonus.get(stat, 0.0)
	if stat == supercharged_stat:
		base *= SUPERCHARGE_MULTIPLIER
	return base

func set_equipment_bonus(bonus: Dictionary) -> void:
	equipment_bonus = bonus

func set_slate_bonus(bonus: Dictionary) -> void:
	slate_bonus = bonus

func get_mastery(tag: Constants.DamageType) -> float:
	return mastery_by_tag.get(tag, 0.0)

func set_mastery(tag: Constants.DamageType, value: float) -> void:
	mastery_by_tag[tag] = value

func get_chain_bonus(tag: Constants.DamageType) -> float:
	return chain_bonus_by_tag.get(tag, 0.0)

func set_chain_bonus_by_tag(bonus: Dictionary) -> void:
	chain_bonus_by_tag = bonus

## Maps a DamageType to which of the 4 unified Resistance stats covers it
## (Patch v3.2) - null for Physical types, which Armor covers instead.
static func resistance_key_for(damage_type: Constants.DamageType):
	match damage_type:
		Constants.DamageType.FIRE: return "fire"
		Constants.DamageType.COLD: return "cold"
		Constants.DamageType.LIGHTNING: return "lightning"
		Constants.DamageType.AETHERIC, Constants.DamageType.ENTROPIC, Constants.DamageType.PALE: return "esoteric"
	return null

func get_resistance(damage_type: Constants.DamageType) -> float:
	var key = resistance_key_for(damage_type)
	return equipment_resistance.get(key, 0.0) if key else 0.0

func set_equipment_resistance(resistance: Dictionary) -> void:
	equipment_resistance = resistance

## Patch v3.5 Section 4. Generic "increased damage" affixes (no damage
## type) vs type-specific ones (Constants.DamageType -> float) - kept
## separate since a generic bonus should apply on top of every damage
## type, not get bucketed under one. Not consumed by DamageCalculator
## yet (no ItemRoller affix generation produces "increased_damage" affixes
## yet, that's a separate pass per the brief) - scaffolding only.
var increased_damage_generic: float = 0.0
var increased_damage_by_type: Dictionary = {}

## Single dispatch point for a rolled ItemAffix - routes to whichever
## bucket its stat_key means. Reuses EquipmentComponent's own stat_key
## tables rather than duplicating them, so there's one source of truth
## for what each key means.
func apply_affix(affix: ItemAffix) -> void:
	if EquipmentComponent.AFFIX_STAT_KEYS.has(affix.stat_key):
		var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[affix.stat_key]
		equipment_bonus[stat] = equipment_bonus.get(stat, 0.0) + affix.value
		return
	if EquipmentComponent.RESISTANCE_AFFIX_KEYS.has(affix.stat_key):
		var key: String = EquipmentComponent.RESISTANCE_AFFIX_KEYS[affix.stat_key]
		equipment_resistance[key] = equipment_resistance.get(key, 0.0) + affix.value
		return
	if affix.stat_key == "increased_damage":
		if affix.is_generic or affix.damage_type == -1:
			increased_damage_generic += affix.value
		else:
			var dt: Constants.DamageType = affix.damage_type
			increased_damage_by_type[dt] = increased_damage_by_type.get(dt, 0.0) + affix.value

## Recomputes increased_damage_generic/increased_damage_by_type from every
## equipped item's affixes - additive alongside set_equipment_bonus()/
## set_equipment_resistance() above (Player._on_equipment_changed() calls
## both), not a replacement for them.
func apply_equipment_affixes(items: Array[Item]) -> void:
	increased_damage_generic = 0.0
	increased_damage_by_type = {}
	for item in items:
		for affix in item.affixes:
			if affix.stat_key == "increased_damage":
				apply_affix(affix)

## Patch v3.7 Section 3. Additive pools, percentage totals (e.g. 20.0 for
## +20%) - not @export'd/persisted, same "always re-derived from currently
## equipped gear" footing as equipment_bonus/increased_damage_generic
## above. Recalculated on every stat refresh, never cached across one.
var cast_speed_bonus: float = 0.0
var cooldown_recovery_rate: float = 0.0

func get_effective_cast_time(base_cast_time: float) -> float:
	return base_cast_time / (1.0 + cast_speed_bonus / 100.0)

func get_effective_cooldown(base_cooldown: float) -> float:
	return base_cooldown / (1.0 + cooldown_recovery_rate / 100.0)

## Section 20 Slate affix: converts a fraction of the player's current
## Cast Speed into Cooldown Recovery Rate. conversion_percent is 15-25
## depending on the Slate's own tier. Recalculate on every stat refresh
## alongside cast_speed_bonus itself - not cached, so a change in Cast
## Speed from gear/Slates always propagates through immediately rather
## than freezing whatever conversion applied last time this ran.
func apply_cast_speed_to_cooldown_conversion(conversion_percent: float) -> void:
	var converted := cast_speed_bonus * (conversion_percent / 100.0)
	cooldown_recovery_rate += converted

## Patch v3.7 Section 1: the equipped Conduit's own spell power - the
## base floor Ability._base_hit() adds so spell damage doesn't collapse
## to single digits at low stats/grades (Weapon.base_damage's role, but
## for spells). Recomputed by Player._on_equipment_changed() from
## equipment.primary_weapon.get_spell_power() when it's a Conduit, 0.0
## otherwise - same "cache on StatSheet, no signature changes anywhere"
## pattern as equipment_bonus, so every existing Ability.predict_damage()/
## roll_damage() call site (15+ across PlayerAbilityCast.gd and several
## entities/effects/*_field/*.gd scripts) needed zero changes.
var conduit_spell_power: float = 0.0

func set_conduit_spell_power(value: float) -> void:
	conduit_spell_power = value
