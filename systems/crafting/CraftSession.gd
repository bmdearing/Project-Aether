extends RefCounted
class_name CraftSession
## One paid Siphon craft (CraftingResolver.begin()). The residue and the
## item's craft count are already spent; outcomes are simulated and the item
## is untouched until choose() applies one. decline() keeps the item as it was.

var resolver: CraftingResolver
var target: Resource
var craft_id: StringName
## CraftResult.CraftError; not NONE when begin() refused (nothing was spent).
var error: int = CraftResult.CraftError.NONE
var paid: Dictionary = {}
var outcomes: Array[Dictionary] = []
var _closed := false

func is_open() -> bool:
	return error == CraftResult.CraftError.NONE and not _closed

func choose(index: int) -> CraftResult:
	if not is_open() or index < 0 or index >= outcomes.size():
		var failed := CraftResult.new()
		failed.craft_id = craft_id
		failed.error = CraftResult.CraftError.NO_VALID_OUTCOME
		return failed
	_closed = true
	return resolver.commit(target, craft_id, outcomes[index])

func decline() -> CraftResult:
	_closed = true
	var result := CraftResult.new()
	result.craft_id = craft_id
	result.success = true
	return result
