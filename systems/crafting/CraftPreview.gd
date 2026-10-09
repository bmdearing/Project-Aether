extends RefCounted
class_name CraftPreview
## Side-effect-free view of an Orb use. outcomes covers the (next) added
## modifier: each entry is {def: ModifierDef, tier: ModifierTier,
## probability: float}. removals covers removal Orbs: {affix: ItemAffix,
## probability: float}. Forging adds several modifiers; outcomes describes
## the first pick, add_count says how many follow.

var error: CraftResult.CraftError = CraftResult.CraftError.NONE
var orb_id: StringName
var outcomes: Array[Dictionary] = []
var removals: Array[Dictionary] = []
var add_count: int = 0
## Existing modifiers the Orb would touch: {affix: ItemAffix, effect:
## &"remove" | &"replace" | &"anchor" | &"reroll", probability: float}.
var affected: Array[Dictionary] = []
var applied_brands: Array[StringName] = []
var consumed_brands: Array[StringName] = []

func is_valid() -> bool:
	return error == CraftResult.CraftError.NONE

func total_probability() -> float:
	var total := 0.0
	for o in outcomes:
		total += o["probability"]
	return total
