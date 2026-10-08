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

func can_place(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> bool:
	return _placement_failure_reason(slate, origin, rotation_steps, flipped) == ""

func _placement_failure_reason(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool, check_budget: bool = true) -> String:
	if check_budget and aether_used + slate.aether_cost > aether_capacity:
		return "insufficient_aether"
	var cells := _world_cells(slate, origin, rotation_steps, flipped)
	for c in cells:
		if _occupied_cells.has(c):
			return "cell_occupied"
	if not _touches_existing(cells):
		return "not_connected"
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
## because capacity is synced in a different order.
func place_slate(slate: Slate, origin: Vector2i, rotation_steps: int = 0, flipped: bool = false, designated_ability_id: String = "", bypass_budget: bool = false) -> String:
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

	for c in cells:
		_occupied_cells[c] = placement_id
	placements[placement_id] = data
	aether_used += slate.aether_cost

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
	aether_used -= data.slate.aether_cost
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
