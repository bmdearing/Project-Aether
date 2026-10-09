extends Resource
class_name Stash
## Hub stash: general tabs plus currency-only, Slate-only and Figment-only
## tabs, and the Unique tab: one slot per UniqueCatalog entry, holding one
## copy each.
##
## Affinities: each item category can point at one tab. Anything sent to
## the stash goes to its category's tab first (StashScreen). Currency,
## Slates, Uniques and Figments start pointed at their own tabs.

var tabs: Array[GridInventory] = []
## UniqueCatalog id -> the Item in that slot.
var uniques: Dictionary = {}
## Category -> tab index, or UNIQUE_TAB for the Unique tab.
var affinities: Dictionary = {}

const UNIQUE_TAB := -1
const CATEGORIES: Array[String] = ["currency", "slates", "uniques", "figments", "weapons", "armour", "accessories", "jewels"]
const CATEGORY_NAMES := {
	"currency": "Currency", "slates": "Slates", "uniques": "Uniques", "figments": "Figments",
	"weapons": "Weapons", "armour": "Armour & Shields", "accessories": "Rings, Amulets & Belts", "jewels": "Jewels & Lenses",
}

static func create_default() -> Stash:
	var stash := Stash.new()
	for i in Constants.STASH_TAB_COUNT:
		stash.tabs.append(GridInventory.new(Constants.STASH_TAB_SIZE.x, Constants.STASH_TAB_SIZE.y))
	stash.tabs.append(GridInventory.new(Constants.STASH_CURRENCY_TAB_SIZE.x, Constants.STASH_CURRENCY_TAB_SIZE.y, GridInventory.Accepts.CURRENCY))
	stash.tabs.append(GridInventory.new(Constants.STASH_SLATE_TAB_SIZE.x, Constants.STASH_SLATE_TAB_SIZE.y, GridInventory.Accepts.SLATE))
	stash.tabs.append(GridInventory.new(Constants.STASH_FIGMENT_TAB_SIZE.x, Constants.STASH_FIGMENT_TAB_SIZE.y, GridInventory.Accepts.FIGMENT))
	stash.reset_affinities()
	return stash

func get_tab(accepts: GridInventory.Accepts) -> GridInventory:
	for tab in tabs:
		if tab.accepts == accepts:
			return tab
	return null

## ---- Affinities ------------------------------------------------------------

func reset_affinities() -> void:
	affinities = {"uniques": UNIQUE_TAB}
	for pair in [["currency", GridInventory.Accepts.CURRENCY], ["slates", GridInventory.Accepts.SLATE], ["figments", GridInventory.Accepts.FIGMENT]]:
		var tab := get_tab(pair[1])
		if tab:
			affinities[pair[0]] = tabs.find(tab)

## Categories content belongs to, most specific first (a Unique sword is
## "uniques", then "weapons").
static func categories_of(content) -> Array[String]:
	var result: Array[String] = []
	if content is StringName:
		result.append("currency")
	elif content is Slate:
		result.append("slates")
	elif content is FigmentItem:
		result.append("figments")
	elif content is Item:
		var item := content as Item
		if item.unique_id != "":
			result.append("uniques")
		if item is Jewel:
			result.append("jewels")
		elif item is Weapon:
			result.append("weapons")
		elif item.equip_slot in [Constants.EquipmentSlot.AMULET, Constants.EquipmentSlot.BELT, Constants.EquipmentSlot.RING]:
			result.append("accessories")
		elif item.is_equipment():
			result.append("armour")
	return result

## Whether the tab at index (or UNIQUE_TAB) can hold anything of category.
func tab_can_take(index: int, category: String) -> bool:
	if index == UNIQUE_TAB:
		return category == "uniques"
	if index < 0 or index >= tabs.size():
		return false
	match tabs[index].accepts:
		GridInventory.Accepts.CURRENCY:
			return category == "currency"
		GridInventory.Accepts.SLATE:
			return category == "slates"
		GridInventory.Accepts.FIGMENT:
			return category == "figments"
	return true

## Points category at a tab, or clears it when it already points there.
func toggle_affinity(category: String, index: int) -> void:
	if affinities.has(category) and affinities[category] == index:
		affinities.erase(category)
	elif tab_can_take(index, category):
		affinities[category] = index

func categories_for_tab(index: int) -> Array[String]:
	var result: Array[String] = []
	for category in CATEGORIES:
		if affinities.has(category) and affinities[category] == index:
			result.append(category)
	return result

## ---- Uniques ---------------------------------------------------------------

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

## Every Figment in the stash's tabs.
func get_figments() -> Array[FigmentItem]:
	var result: Array[FigmentItem] = []
	for tab in tabs:
		for entry in tab.get_entries():
			if entry.content is FigmentItem:
				result.append(entry.content)
	return result

## Takes content out of whichever tab holds it.
func remove_content(content) -> bool:
	for tab in tabs:
		if tab.remove_content(content):
			return true
	return false

## ---- Save data -------------------------------------------------------------

func to_dict() -> Dictionary:
	var data := []
	for tab in tabs:
		data.append(tab.to_dict())
	var unique_data := {}
	for id in uniques:
		unique_data[id] = ItemSerializer.to_dict(uniques[id])
	return {"tabs": data, "uniques": unique_data, "affinities": affinities.duplicate()}

static func from_dict(d: Dictionary) -> Stash:
	var raw: Array = d.get("tabs", [])
	if raw.is_empty():
		return create_default()
	var stash := Stash.new()
	for tab in raw:
		stash.tabs.append(GridInventory.from_dict(tab))
	# Tabs added since the save was written, and the bigger currency tab.
	if stash.get_tab(GridInventory.Accepts.FIGMENT) == null:
		stash.tabs.append(GridInventory.new(Constants.STASH_FIGMENT_TAB_SIZE.x, Constants.STASH_FIGMENT_TAB_SIZE.y, GridInventory.Accepts.FIGMENT))
	var currency := stash.get_tab(GridInventory.Accepts.CURRENCY)
	if currency:
		currency.grow_to(Constants.STASH_CURRENCY_TAB_SIZE)
	var unique_data = d.get("uniques", {})
	if unique_data is Dictionary:
		for id in unique_data:
			var item := ItemSerializer.from_dict(unique_data[id])
			if item:
				stash.uniques[String(id)] = item
	var saved_affinities = d.get("affinities")
	if saved_affinities is Dictionary:
		for category in saved_affinities:
			var index := int(saved_affinities[category])
			if CATEGORIES.has(String(category)) and stash.tab_can_take(index, String(category)):
				stash.affinities[String(category)] = index
	else:
		stash.reset_affinities()
	return stash
