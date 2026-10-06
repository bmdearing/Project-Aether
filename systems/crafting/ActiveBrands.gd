extends RefCounted
class_name ActiveBrands
## Directive Brands switched on for the next Orb. Only Brands present in the
## carried inventory can be activated; consuming one removes a unit from it
## and switches it off.

var carried: Object
var _ids: Array[StringName] = []

func _init(p_carried: Object = null) -> void:
	carried = p_carried

func activate(id: StringName) -> bool:
	if carried == null or carried.count_of(id) <= 0:
		return false
	if not _ids.has(id):
		_ids.append(id)
	return true

func deactivate(id: StringName) -> void:
	_ids.erase(id)

func is_active(id: StringName) -> bool:
	return _ids.has(id)

func get_ids() -> Array[StringName]:
	return _ids.duplicate()

func consume(id: StringName) -> void:
	if carried != null:
		carried.remove_currency(id, 1)
	deactivate(id)
