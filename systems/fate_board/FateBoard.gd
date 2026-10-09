extends Resource
class_name FateBoard
## The Fate Board: effectively unlimited grid space, gated by Aether budget
## rather than tile limits. Tracks placed Slates and delegates chain math
## to ChainCalculator.

signal placement_failed(reason: String)

## Aether budget by level (capacity_for_level()); Player keeps
## aether_capacity in sync on boot and level-up.
const AETHER_BASE := 10
const AETHER_PER_LEVEL := 2

var aether_capacity: int = AETHER_BASE
var aether_used: int = 0

static func capacity_for_level(level: int) -> int:
	return AETHER_BASE + (level - 1) * AETHER_PER_LEVEL

## cell (Vector2i) -> PlacedSlate
var _occupied_cells: Dictionary = {}
## placement_id (String, unique per placed instance) -> PlacedSlateData
var placements: Dictionary = {}

## Always treated as already "placed" for adjacency purposes, so an empty
## board has a legal first placement to build outward from. Centered on
## FateBoardGrid's own GRID_SIZE (150).
const ANCHOR_CELL := Vector2i(75, 75)
const _ADJACENT_DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

class PlacedSlateData:
	var placement_id: String
	var slate: Slate
	var origin: Vector2i
	var rotation_steps: int
	var flipped: bool
	var cells: Array[Vector2i]
	## Bound ability for Slates with requires_spell_designation; "" otherwise.
	var designated_ability_id: String = ""
	## Aether paid when placed (base cost + distance - Lens discounts), refunded on removal.
	var aether_paid: int = 0

func can_place(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> bool:
	return _placement_failure_reason(slate, origin, rotation_steps, flipped) == ""

## check_rules is false when restoring a save: Slates placed before a rule
## existed stay, and the rules apply again to new placements.
func _placement_failure_reason(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool, check_rules: bool = true) -> String:
	var cells := _world_cells(slate, origin, rotation_steps, flipped)
	if check_rules and aether_used + placement_cost(slate, cells) > aether_capacity:
		return "insufficient_aether"
	for c in cells:
		if _occupied_cells.has(c):
			return "cell_occupied"
		if check_rules and c == ANCHOR_CELL:
			return "anchor_cell"
	if not _touches_existing(cells):
		return "not_connected"
	if check_rules and not _tag_connected(slate, cells):
		return "tag_not_connected"
	return ""

## True if any cell of the candidate placement is orthogonally adjacent
## to (or overlaps) ANCHOR_CELL or an already-occupied cell.
func _touches_existing(cells: Array[Vector2i]) -> bool:
	for c in cells:
		if c == ANCHOR_CELL:
			return true
		for dir in _ADJACENT_DIRS:
			if _occupied_cells.has(c + dir) or c + dir == ANCHOR_CELL:
				return true
	return false

## bypass_budget: used when restoring a save, so placements never drop
## because capacity is synced in a different order or a rule was added.
## aether_paid: what the save says the Slate paid (-1 when unknown: price it
## now, or charge its base cost when restoring an older save).
func place_slate(slate: Slate, origin: Vector2i, rotation_steps: int = 0, flipped: bool = false, designated_ability_id: String = "", bypass_budget: bool = false, aether_paid: int = -1) -> String:
	var reason := _placement_failure_reason(slate, origin, rotation_steps, flipped, not bypass_budget)
	if reason != "":
		placement_failed.emit(reason)
		return ""

	var placement_id := "%s_%d" % [slate.slate_id, placements.size()]
	var cells := _world_cells(slate, origin, rotation_steps, flipped)

	var data := PlacedSlateData.new()
	data.placement_id = placement_id
	data.slate = slate
	data.origin = origin
	data.rotation_steps = rotation_steps
	data.flipped = flipped
	data.cells = cells
	data.designated_ability_id = designated_ability_id
	if aether_paid >= 0:
		data.aether_paid = aether_paid
	else:
		data.aether_paid = slate.aether_cost if bypass_budget else placement_cost(slate, cells)

	for c in cells:
		_occupied_cells[c] = placement_id
	placements[placement_id] = data
	aether_used += data.aether_paid

	EventBus.slate_placed.emit(placement_id, origin)
	EventBus.aether_budget_changed.emit(aether_used, aether_capacity)
	GameState.sync_fate_board(self)
	return placement_id

func remove_slate(placement_id: String) -> void:
	if not placements.has(placement_id):
		return
	var data: PlacedSlateData = placements[placement_id]
	for c in data.cells:
		_occupied_cells.erase(c)
	aether_used -= data.aether_paid
	placements.erase(placement_id)

	EventBus.slate_removed.emit(placement_id, data.origin)
	EventBus.aether_budget_changed.emit(aether_used, aether_capacity)
	GameState.sync_fate_board(self)

func get_occupied_cells() -> Dictionary:
	return _occupied_cells

func _world_cells(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> Array[Vector2i]:
	var local := slate.get_transformed_shape(rotation_steps, flipped)
	var world: Array[Vector2i] = []
	for c in local:
		world.append(c + origin)
	return world

## ---- Placement rules and Lenses ------------------------------------------

## Tiles from the anchor per +1 Aether: far-out Slates cost more.
const AETHER_RING_SIZE := 5

## Damage-type tags of a Slate (its tag, and the second one when Hybrid).
static func slate_tags(slate: Slate) -> Array[int]:
	var tags: Array[int] = [slate.tag]
	if slate.is_hybrid and not tags.has(slate.secondary_tag):
		tags.append(slate.secondary_tag)
	return tags

## A placed Slate's tags plus any a Lens in range bridges it to.
func placed_tags(data: PlacedSlateData) -> Array[int]:
	var tags := slate_tags(data.slate)
	for effect in lens_effects_at(data.cells):
		if effect["mod"] == "bridge_tag" and not tags.has(effect["tag"]):
			tags.append(effect["tag"])
	return tags

## Aether a Slate costs at `cells`: its own cost, +1 per AETHER_RING_SIZE
## tiles of distance from the anchor, -1 per "cheap" Lens covering it; at least 1.
func placement_cost(slate: Slate, cells: Array[Vector2i]) -> int:
	var nearest := 1 << 30
	for c in cells:
		nearest = mini(nearest, maxi(absi(c.x - ANCHOR_CELL.x), absi(c.y - ANCHOR_CELL.y)))
	var cost := slate.aether_cost + nearest / AETHER_RING_SIZE
	for effect in lens_effects_at(cells):
		if effect["mod"] == "cheap":
			cost -= int(effect["value"])
	return maxi(cost, 1)

## A new Slate must touch the anchor, or a placed Slate it shares a tag with
## (Hybrids bridge two tags; Lenses can bridge or waive this).
func _tag_connected(slate: Slate, cells: Array[Vector2i]) -> bool:
	var tags := slate_tags(slate)
	for effect in lens_effects_at(cells):
		if effect["mod"] == "free_placement":
			return true
		if effect["mod"] == "bridge_tag" and not tags.has(effect["tag"]):
			tags.append(effect["tag"])
	for c in cells:
		for dir in _ADJACENT_DIRS:
			var next: Vector2i = c + dir
			if next == ANCHOR_CELL or c == ANCHOR_CELL:
				return true
			if not _occupied_cells.has(next):
				continue
			var neighbour: PlacedSlateData = placements[_occupied_cells[next]]
			if placed_tags(neighbour).any(func(t: int): return tags.has(t)):
				return true
	return false

## Radius modifiers of every Lens whose radius reaches any of `cells`:
## {"mod", "value", "tag", "placement_id"}. A cell is in radius when it's
## within `radius` tiles of any cell of the Lens's host Slate.
func lens_effects_at(cells: Array[Vector2i]) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for id in placements:
		var host: PlacedSlateData = placements[id]
		for lens in host.slate.lenses:
			if _in_radius(cells, host.cells, lens.radius):
				effects.append({"mod": lens.radius_mod, "value": lens.radius_value, "tag": lens.radius_tag, "placement_id": id})
	return effects

static func _in_radius(cells: Array[Vector2i], host_cells: Array[Vector2i], radius: int) -> bool:
	for c in cells:
		for h in host_cells:
			if Vector2(c - h).length() <= radius + 0.01:
				return true
	return false

## Cells within a Lens's radius of its host (for drawing the radius).
static func radius_cells(host_cells: Array[Vector2i], radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {}
	for h in host_cells:
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var c := h + Vector2i(dx, dy)
				if not seen.has(c) and Vector2(dx, dy).length() <= radius + 0.01:
					seen[c] = true
					result.append(c)
	return result
