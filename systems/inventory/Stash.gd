extends Resource
class_name Stash
## Hub stash: general tabs plus a currency-only and a Slate-only tab.

var tabs: Array[GridInventory] = []

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

func to_dict() -> Dictionary:
	var data := []
	for tab in tabs:
		data.append(tab.to_dict())
	return {"tabs": data}

static func from_dict(d: Dictionary) -> Stash:
	var raw: Array = d.get("tabs", [])
	if raw.is_empty():
		return create_default()
	var stash := Stash.new()
	for tab in raw:
		stash.tabs.append(GridInventory.from_dict(tab))
	return stash
