extends Resource
class_name Stash
## Hub stash: general tabs plus a currency-only and a Slate-only tab, and the
## Unique tab: one slot per UniqueCatalog entry, holding one copy each.

var tabs: Array[GridInventory] = []
## UniqueCatalog id -> the Item in that slot.
var uniques: Dictionary = {}

static func create_default() -> Stash:
	var stash := Stash.new()
	for i in Constants.STASH_TAB_COUNT:
		stash.tabs.append(GridInventory.new(Constants.STASH_TAB_SIZE.x, Constants.STASH_TAB_SIZE.y))
	stash.tabs.append(GridInventory.new(Constants.STASH_CURRENCY_TAB_SIZE.x, Constants.STASH_CURRENCY_TAB_SIZE.y, GridInventory.Accepts.CURRENCY))
	stash.tabs.append(GridInventory.new(Constants.STASH_SLATE_TAB_SIZE.x, Constants.STASH_SLATE_TAB_SIZE.y, GridInventory.Accepts.SLATE))
	return stash

func get_tab(accepts: GridInventory.Accepts) -> GridInventory:
	for tab in tabs:
		if tab.accepts == accepts:
			return tab
	return null

## Whether the item belongs in the Unique tab and its slot is free.
func can_store_unique(item) -> bool:
	return item is Item and (item as Item).unique_id != "" and not UniqueCatalog.get_def(item.unique_id).is_empty() and not uniques.has(item.unique_id)

func store_unique(item: Item) -> bool:
	if not can_store_unique(item):
		return false
	uniques[item.unique_id] = item
	return true

## Empties a slot and returns what was in it (null when empty).
func take_unique(id: String) -> Item:
	var item: Item = uniques.get(id)
	uniques.erase(id)
	return item

func to_dict() -> Dictionary:
	var data := []
	for tab in tabs:
		data.append(tab.to_dict())
	var unique_data := {}
	for id in uniques:
		unique_data[id] = ItemSerializer.to_dict(uniques[id])
	return {"tabs": data, "uniques": unique_data}

static func from_dict(d: Dictionary) -> Stash:
	var raw: Array = d.get("tabs", [])
	if raw.is_empty():
		return create_default()
	var stash := Stash.new()
	for tab in raw:
		stash.tabs.append(GridInventory.from_dict(tab))
	var unique_data = d.get("uniques", {})
	if unique_data is Dictionary:
		for id in unique_data:
			var item := ItemSerializer.from_dict(unique_data[id])
			if item:
				stash.uniques[String(id)] = item
	return stash
