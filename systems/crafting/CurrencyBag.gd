extends RefCounted
class_name CurrencyBag
## Minimal id -> count store. Anything with count_of()/remove_currency()
## (e.g. GridInventory) can stand in for it as a crafting currency source.

var counts: Dictionary = {}

func add_currency(id: StringName, amount: int = 1) -> void:
	counts[id] = counts.get(id, 0) + amount

func count_of(id: StringName) -> int:
	return counts.get(id, 0)

func remove_currency(id: StringName, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	counts[id] -= amount
	if counts[id] == 0:
		counts.erase(id)
	return true
