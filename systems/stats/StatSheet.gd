extends Resource
class_name StatSheet
## The six baseline stats (Section 12 Stat System). Per Section 12: "All
## stats come from gear, Slates, Jewels, and infusions — no manual
## allocation on level up." The raw fields below are the character's
## permanently-fixed baseline (player_baseline.tres, 10.0 flat - an
## invented vertical-slice testing value, no doc-sourced baseline exists);
## equipment_bonus is the ONLY thing that ever grows a stat past that,
## fed by EquipmentComponent.compute_stat_bonuses() summing every
## equipped item's flat_<stat> affixes (see ItemRoller.gd) - Player.gd
## pushes a fresh total in via set_equipment_bonus() on every
## equip/unequip. Not persisted separately - it's entirely re-derived
## from GameState.equipment_refs (already saved) on every load, so there's
## no separate save/load path needed here.

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

## Mastery: DamageType -> float bonus (e.g. 0.5 for "+0.5 Cold Mastery").
## Never universal - keyed per tag per Section 10.
var mastery_by_tag: Dictionary = {}

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
	if stat == supercharged_stat:
		base *= SUPERCHARGE_MULTIPLIER
	return base

func set_equipment_bonus(bonus: Dictionary) -> void:
	equipment_bonus = bonus

func get_mastery(tag: Constants.DamageType) -> float:
	return mastery_by_tag.get(tag, 0.0)

func set_mastery(tag: Constants.DamageType, value: float) -> void:
	mastery_by_tag[tag] = value
