extends RefCounted
class_name ChainCalculator
## Computes connected Slate chains on a FateBoard and their bonus per the
## four-tier table in Constants.CHAIN_BONUS_TIERS.
##
## Interpretation flagged for design review: chains are computed per tag
## (same-tag adjacency), since Mastery is tag-specific and Hybrid Slates
## "bridge two chains" - implying chains are tag-scoped, not one
## board-wide connectivity graph.

class ChainResult:
	var tag: Constants.DamageType
	var tile_count: int = 0
	var bonus_percent: float = 0.0
	var placement_ids: Array[String] = []

## Returns Array[ChainResult], one per distinct connected same-tag group.
static func compute_chains(board: FateBoard) -> Array[ChainResult]:
	var visited_cells := {}
	var results: Array[ChainResult] = []

	for placement_id in board.placements.keys():
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		for start_cell in data.cells:
			if visited_cells.has(start_cell):
				continue
			var chain := _flood_fill(board, start_cell, data.slate.tag, visited_cells)
			if chain.tile_count > 0:
				chain.tag = data.slate.tag
				chain.bonus_percent = _bonus_for_tile_count(chain.tile_count)
				results.append(chain)

	return results

static func _flood_fill(board: FateBoard, start_cell: Vector2i, tag: Constants.DamageType, visited_cells: Dictionary) -> ChainResult:
	var result := ChainResult.new()
	var occupied := board.get_occupied_cells()
	var stack: Array[Vector2i] = [start_cell]
	var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited_cells.has(cell):
			continue
		if not occupied.has(cell):
			continue

		var placement_id: String = occupied[cell]
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]

		# Same-tag membership, OR this cell belongs to a Hybrid Slate touching this tag.
		var matches_tag := data.slate.tag == tag
		var hybrid_bridges := data.slate.is_hybrid and (data.slate.tag == tag or data.slate.secondary_tag == tag)
		if not (matches_tag or hybrid_bridges):
			continue

		visited_cells[cell] = true
		result.tile_count += 1
		if not result.placement_ids.has(placement_id):
			result.placement_ids.append(placement_id)

		for dir in directions:
			var next_cell: Vector2i = cell + dir
			if occupied.has(next_cell) and not visited_cells.has(next_cell):
				stack.append(next_cell)

	return result

## Section 10/23: "Mastery... multiplying the per-tile chain bonus rate."
## Takes compute_chains()'s raw per-chain results and amplifies each by
## (1 + that chain's tag's Mastery) - kept as a separate pass (rather than
## folded into compute_chains() itself) so the raw board geometry stays
## testable/displayable without a StatSheet dependency (FateBoardEditor's
## own chain_label still shows the unamplified per-tag numbers). Two
## disconnected same-tag chains both contribute, summed per tag.
static func amplify_by_mastery(chains: Array[ChainResult], stat_sheet: StatSheet) -> Dictionary:
	var totals: Dictionary = {}
	for result in chains:
		var mastery: float = stat_sheet.get_mastery(result.tag) if stat_sheet else 0.0
		var amplified: float = result.bonus_percent * (1.0 + mastery)
		totals[result.tag] = totals.get(result.tag, 0.0) + amplified
	return totals

static func _bonus_for_tile_count(tile_count: int) -> float:
	var bonus := 0.0
	var remaining := tile_count
	for tier in Constants.CHAIN_BONUS_TIERS:
		if remaining <= 0:
			break
		var tier_capacity: int = tier["max"] - tier["min"] + 1
		var tiles_in_tier: int = min(remaining, tier_capacity)
		bonus += tiles_in_tier * tier["per_tile"]
		remaining -= tiles_in_tier
	return bonus
