extends Resource
class_name GridInventory
## Fixed-footprint grid inventory. Footprints come from FootprintTable and
## never rotate. Currency (Orbs, Brands, Edicts, Vestiges) is stored by id
## (StringName), takes one cell, and stacks to Constants.MAX_STACK per cell.
## Also serves as a crafting currency source (count_of/remove_currency).

enum Accepts { ANY, CURRENCY, SLATE, FIGMENT }

class Entry:
	## Item, Slate, or StringName for a currency stack.
	var content
	var count: int = 1
	var position: Vector2i
	var size: Vector2i

	func is_currency() -> bool:
		return content is StringName

	func get_rect() -> Rect2i:
		return Rect2i(position, size)

const NO_SPACE := Vector2i(-1, -1)

@export var width: int
@export var height: int
@export var accepts: Accepts = Accepts.ANY
var entries: Array[Entry] = []

func _init(p_width: int = Constants.INVENTORY_SIZE.x, p_height: int = Constants.INVENTORY_SIZE.y, p_accepts: Accepts = Accepts.ANY) -> void:
	width = p_width
	height = p_height
	accepts = p_accepts

## Crafting stones used to be Items; one arriving as an Item (old save,
## old drop) is stored as its currency stack instead.
static func as_currency_if_consumable(content):
	if content is Item and Constants.CRAFTING_CONSUMABLE_IDS.has(String(content.item_id)):
		return StringName(content.item_id)
	return content

static func footprint_of(content) -> Vector2i:
	if content is StringName:
		return Vector2i.ONE
	if content is Slate:
		return FootprintTable.footprint_for_type(&"slate")
	if content is Item:
		return FootprintTable.footprint_for_type(content.get_item_type())
	return Vector2i.ONE

func accepts_content(content) -> bool:
	match accepts:
		Accepts.CURRENCY:
			return content is StringName
		Accepts.SLATE:
			return content is Slate
		Accepts.FIGMENT:
			return content is FigmentItem
	return content is StringName or content is Item or content is Slate

func can_place(content, pos: Vector2i, ignore: Entry = null) -> bool:
	return accepts_content(content) and _is_free(Rect2i(pos, footprint_of(content)), ignore)

## First free spot for a footprint, scanning rows from the top-left.
func find_space(size: Vector2i) -> Vector2i:
	for y in height - size.y + 1:
		for x in width - size.x + 1:
			if _is_free(Rect2i(x, y, size.x, size.y)):
				return Vector2i(x, y)
	return NO_SPACE

## Drops content at pos. Currency dropped on a matching stack merges into
## it; overflow goes to new cells. Returns how many couldn't be stored.
func place(content, pos: Vector2i, count: int = 1) -> int:
	content = as_currency_if_consumable(content)
	if not accepts_content(content):
		return count
	if not content is StringName:
		if not can_place(content, pos):
			return count
		_new_entry(content, pos, 1)
		return count - 1
	var target := entry_at(pos)
	if target != null:
		if not _same(target.content, content):
			return count
		count = _fill(target, count)
	elif _is_free(Rect2i(pos, Vector2i.ONE)):
		var amount := mini(count, Constants.MAX_STACK)
		_new_entry(content, pos, amount)
		count -= amount
	else:
		return count
	return _add_new_stacks(content, count)

## Picks content up into the first available space. Currency tops up
## existing stacks before opening new cells. Returns how many didn't fit.
func add(content, count: int = 1) -> int:
	content = as_currency_if_consumable(content)
	if not accepts_content(content):
		return count
	if not content is StringName:
		var pos := find_space(footprint_of(content))
		return count if pos == NO_SPACE else place(content, pos)
	for e in _sorted_entries():
		if count == 0:
			break
		if _same(e.content, content):
			count = _fill(e, count)
	return _add_new_stacks(content, count)

func remove(entry: Entry) -> void:
	entries.erase(entry)

func remove_content(content) -> bool:
	for e in entries:
		if not e.is_currency() and _same(e.content, content):
			entries.erase(e)
			return true
	return false

## Moves an entry within this grid. Currency moved onto a matching stack
## merges into it.
func move(entry: Entry, pos: Vector2i) -> bool:
	if not entries.has(entry):
		return false
	if entry.is_currency():
		var target := entry_at(pos)
		if target != null and target != entry:
			if not _same(target.content, entry.content) or target.count >= Constants.MAX_STACK:
				return false
			entry.count = _fill(target, entry.count)
			if entry.count == 0:
				remove(entry)
			return true
	if not _is_free(Rect2i(pos, entry.size), entry):
		return false
	entry.position = pos
	return true

## Moves an entry into another grid at pos. Returns false if nothing moved.
func transfer(entry: Entry, to: GridInventory, pos: Vector2i) -> bool:
	if to == self:
		return move(entry, pos)
	if not entries.has(entry):
		return false
	var leftover := to.place(entry.content, pos, entry.count)
	if leftover == entry.count:
		return false
	entry.count = leftover
	if entry.count == 0:
		remove(entry)
	return true

func entry_at(cell: Vector2i) -> Entry:
	for e in entries:
		if e.get_rect().has_point(cell):
			return e
	return null

func has_content(content) -> bool:
	return entries.any(func(e: Entry): return _same(e.content, content))

func get_entries() -> Array[Entry]:
	return entries.duplicate()

func count_of(id: StringName) -> int:
	var total := 0
	for e in entries:
		if e.is_currency() and e.content == id:
			total += e.count
	return total

func remove_currency(id: StringName, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	var stacks := entries.filter(func(e: Entry): return e.is_currency() and e.content == id)
	stacks.sort_custom(func(a: Entry, b: Entry): return a.count < b.count)
	for e: Entry in stacks:
		var taken := mini(amount, e.count)
		e.count -= taken
		amount -= taken
		if e.count == 0:
			remove(e)
		if amount == 0:
			break
	return true

## ---- Save data ---------------------------------------------------------

func to_dict() -> Dictionary:
	var data := []
	for e in entries:
		var d := {"x": e.position.x, "y": e.position.y, "count": e.count}
		if e.is_currency():
			d["currency"] = String(e.content)
		elif e.content is Slate:
			d["slate"] = SlateSerializer.to_dict(e.content)
		else:
			d["item"] = ItemSerializer.to_dict(e.content)
		data.append(d)
	return {"width": width, "height": height, "accepts": accepts, "entries": data}

## Enlarges the grid (never shrinks it); entries keep their positions.
func grow_to(size: Vector2i) -> void:
	width = maxi(width, size.x)
	height = maxi(height, size.y)

static func from_dict(d: Dictionary) -> GridInventory:
	var inv := GridInventory.new(int(d.get("width", Constants.INVENTORY_SIZE.x)), int(d.get("height", Constants.INVENTORY_SIZE.y)), int(d.get("accepts", Accepts.ANY)))
	for e in d.get("entries", []):
		var content
		if e.has("currency"):
			content = StringName(e["currency"])
		elif e.has("slate"):
			content = SlateSerializer.from_dict(e["slate"])
		elif ItemSerializer.is_legacy_brand(e.get("item", {})):
			content = ItemSerializer.legacy_brand_currency(e["item"])
			if content == &"":
				continue
		else:
			content = ItemSerializer.from_dict(e.get("item", {}))
		if content != null:
			inv.place(content, Vector2i(int(e.get("x", 0)), int(e.get("y", 0))), int(e.get("count", 1)))
	return inv

## ---- Internals ---------------------------------------------------------

func _is_free(rect: Rect2i, ignore: Entry = null) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > width or rect.end.y > height:
		return false
	for e in entries:
		if e != ignore and e.get_rect().intersects(rect):
			return false
	return true

func _new_entry(content, pos: Vector2i, count: int) -> Entry:
	var e := Entry.new()
	e.content = content
	e.count = count
	e.position = pos
	e.size = footprint_of(content)
	entries.append(e)
	return e

## Tops up a stack; returns what's left over.
func _fill(stack: Entry, count: int) -> int:
	var moved := mini(count, Constants.MAX_STACK - stack.count)
	stack.count += moved
	return count - moved

func _add_new_stacks(content, count: int) -> int:
	while count > 0:
		var pos := find_space(Vector2i.ONE)
		if pos == NO_SPACE:
			break
		var amount := mini(count, Constants.MAX_STACK)
		_new_entry(content, pos, amount)
		count -= amount
	return count

func _sorted_entries() -> Array[Entry]:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Entry, b: Entry): return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	return sorted

static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b
