extends Resource
class_name FootprintTable
## Inventory footprint per item type, as Vector2i(wide, tall). Types missing
## from the table (currency, figments, tomes...) take default_footprint.

const PATH := "res://data/inventory/footprints.tres"

@export var footprints: Dictionary = {}
@export var default_footprint: Vector2i = Vector2i.ONE

static var _instance: FootprintTable

static func get_instance() -> FootprintTable:
	if _instance == null:
		_instance = load(PATH) as FootprintTable
		if _instance == null:
			_instance = FootprintTable.new()
	return _instance

static func footprint_for_type(item_type: StringName) -> Vector2i:
	var table := get_instance()
	return table.footprints.get(String(item_type), table.default_footprint)
