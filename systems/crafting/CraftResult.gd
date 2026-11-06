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
	CORRUPTED,
	QUALITY_CAPPED,
	MISSING_CURRENCY,
	CANT_AFFORD,
	INVALID_PAYMENT,
	OVER_LINE_LIMIT,
	NOT_UNLOCKED,
	UNCRAFTABLE,
	HAS_BOSS_PERK,
	PERK_LIMIT,
}

var success: bool = false
var error: CraftError = CraftError.NONE
var craft_id: StringName
var added: Array[ItemAffix] = []
var removed: Array[ItemAffix] = []
var anchored: ItemAffix
var quality_gained: int = 0
var sockets_rolled_to: int = -1
## Vestige: the boss perk it added and its roll.
var perk_added: StringName = &""
var perk_value: float = 0.0

static func error_name(code: CraftError) -> String:
	return CraftError.keys()[code]

func get_message() -> String:
	return "" if success else CurrencyText.error_message(error_name(error))
