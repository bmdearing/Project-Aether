extends RefCounted
class_name CraftPreview
## Side-effect-free view of a Siphon craft. outcomes covers the added
## modifier: {def: ModifierDef, tier: ModifierTier, probability: float}.
## removals: {affix: ItemAffix, probability: float}.

var error: CraftResult.CraftError = CraftResult.CraftError.NONE
var craft_id: StringName
var family: StringName
var cost: int = 0
var outcomes: Array[Dictionary] = []
var removals: Array[Dictionary] = []
var add_count: int = 0
## Existing modifiers the craft would touch: {affix: ItemAffix, effect:
## &"remove" | &"replace" | &"anchor" | &"reroll", probability: float}.
var affected: Array[Dictionary] = []

func is_valid() -> bool:
	return error == CraftResult.CraftError.NONE

func total_probability() -> float:
	var total := 0.0
	for o in outcomes:
		total += o["probability"]
	return total
