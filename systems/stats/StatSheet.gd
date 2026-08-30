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
