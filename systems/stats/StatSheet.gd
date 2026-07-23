extends Resource
class_name StatSheet
## The six baseline stats (Section 13). All values come from gear/infusions
## in the full game - for the vertical slice these are set directly for
## testing the damage formula in isolation.

@export var vitality: float = 0.0
@export var strength: float = 0.0
@export var instinct: float = 0.0
@export var arcane: float = 0.0
@export var enigma: float = 0.0
@export var intellect: float = 0.0

@export var supercharged_stat: Constants.Stat = -1  # -1 = none declared
const SUPERCHARGE_MULTIPLIER := 1.25

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
	if stat == supercharged_stat:
		base *= SUPERCHARGE_MULTIPLIER
	return base

func get_mastery(tag: Constants.DamageType) -> float:
	return mastery_by_tag.get(tag, 0.0)

func set_mastery(tag: Constants.DamageType, value: float) -> void:
	mastery_by_tag[tag] = value
