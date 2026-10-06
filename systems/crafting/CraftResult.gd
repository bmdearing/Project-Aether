extends RefCounted
class_name CraftResult

enum CraftError {
	NONE,
	INVALID_TARGET,
	NO_VALID_OUTCOME,
	NO_OPEN_AFFIX,
	NOTHING_TO_REMOVE,
	ALREADY_ANCHORED,
	TOO_FEW_MODIFIERS,
	SOCKETS_ALREADY_ROLLED,
	NO_TOLERANCE,
	CORRUPTED,
	QUALITY_CAPPED,
	MISSING_CURRENCY,
}

var success: bool = false
var error: CraftError = CraftError.NONE
var orb_id: StringName
var added: Array[ItemAffix] = []
var removed: Array[ItemAffix] = []
var anchored: ItemAffix
var quality_gained: int = 0
var sockets_rolled_to: int = -1
var tolerance_spent: int = 0
var consumed_brands: Array[StringName] = []

static func error_name(code: CraftError) -> String:
	return CraftError.keys()[code]

func get_message() -> String:
	return "" if success else CurrencyText.error_message(error_name(error))
