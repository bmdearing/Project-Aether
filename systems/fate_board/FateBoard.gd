extends Resource
class_name FateBoard
## The Fate Board: effectively unlimited grid space, gated by Aether budget
## rather than tile limits. Tracks placed Slates and delegates chain math
## to ChainCalculator. See Section 10.

signal placement_failed(reason: String)

var aether_capacity: int = 30
var aether_used: int = 0

## cell (Vector2i) -> PlacedSlate
var _occupied_cells: Dictionary = {}
## placement_id (String, unique per placed instance) -> PlacedSlateData
var placements: Dictionary = {}

## User direction (2026-08-30): "Slates should have to connect with each
## other, not be placed freely." The board otherwise has no fixed origin
## (Section 10 calls it "effectively unlimited" - Aether is the only
## constraint) so this one cell is always treated as already "placed" for
## adjacency purposes, giving an empty board a legal first placement to
## build outward from - invented, no doc-given board origin exists.
const ANCHOR_CELL := Vector2i(16, 16)
const _ADJACENT_DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

class PlacedSlateData:
	var placement_id: String
	var slate: Slate
	var origin: Vector2i
	var rotation_steps: int
	var flipped: bool
	var cells: Array[Vector2i]
	## Section 10's Unique Slate "The Unbound Chorus": "Designate one Spell
	## skill" - which owned Ability this placement is bound to, for Slates
	## with Slate.requires_spell_designation. "" for every ordinary Slate.
	var designated_ability_id: String = ""

func can_place(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> bool:
	return _placement_failure_reason(slate, origin, rotation_steps, flipped) == ""

func _placement_failure_reason(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> String:
	if aether_used + slate.aether_cost > aether_capacity:
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

func place_slate(slate: Slate, origin: Vector2i, rotation_steps: int = 0, flipped: bool = false, designated_ability_id: String = "") -> String:
	var reason := _placement_failure_reason(slate, origin, rotation_steps, flipped)
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

## Section 10: "Slates sized 5 tiles and above provide stat contributions
## per tile... 2-4 tile Slates provide no stats." Sums every PLACED
## Slate's flat_<stat> modifiers regardless of chain participation - a
## Slate contributes its own stat line just by being placed; the Chain
## Bonus System (see ChainCalculator) is a separate, additional bonus on
## top. Reuses EquipmentComponent.AFFIX_STAT_KEYS' stat_key->Stat mapping
## so a Slate modifier with stat_key "flat_strength" means exactly what a
## gear affix of the same key already means.
func compute_stat_bonuses() -> Dictionary:
	var totals := {}
	for placement_id in placements:
		var data: PlacedSlateData = placements[placement_id]
		for modifier in data.slate.modifiers:
			if EquipmentComponent.AFFIX_STAT_KEYS.has(modifier.stat_key):
				var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[modifier.stat_key]
				totals[stat] = totals.get(stat, 0.0) + modifier.value
	return totals

## Section 10/23: Mastery is granted by a Slate's "mastery" modifier,
## applied to that Slate's own (primary) tag - a Hybrid Slate's mastery
## modifier only benefits its dominant tag, not both (Hybrid's "full
## bonus to both" wording in Section 10 describes chain-EXTENSION
## specifically, not a Slate's own static modifier lines - an invented
## simplification where the doc doesn't say either way).
func compute_mastery_bonuses() -> Dictionary:
	var totals := {}
	for placement_id in placements:
		var data: PlacedSlateData = placements[placement_id]
		for modifier in data.slate.modifiers:
			if modifier.stat_key == "mastery":
				totals[data.slate.tag] = totals.get(data.slate.tag, 0.0) + modifier.value
	return totals

func _world_cells(slate: Slate, origin: Vector2i, rotation_steps: int, flipped: bool) -> Array[Vector2i]:
	var local := slate.get_transformed_shape(rotation_steps, flipped)
	var world: Array[Vector2i] = []
	for c in local:
		world.append(c + origin)
	return world
