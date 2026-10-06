extends Resource
class_name CurrencyText
## Every player-facing currency name, description and craft error message.
## Keys are currency ids / CraftResult.CraftError names; logic never reads
## these strings.

const PATH := "res://data/crafting/currency_text.tres"

@export var names: Dictionary = {}
@export var descriptions: Dictionary = {}
@export var errors: Dictionary = {}

static var _instance: CurrencyText

static func get_instance() -> CurrencyText:
	if _instance == null:
		_instance = load(PATH) as CurrencyText
		if _instance == null:
			_instance = CurrencyText.new()
	return _instance

static func name_of(id: StringName) -> String:
	return get_instance().names.get(String(id), String(id))

static func description_of(id: StringName) -> String:
	return get_instance().descriptions.get(String(id), "")

static func error_message(error_name: String) -> String:
	return get_instance().errors.get(error_name, error_name)
