extends RefCounted
class_name ChainCalculator
## Computes connected Slate chains on a FateBoard and their bonus per the
## four-tier table in Constants.CHAIN_BONUS_TIERS.
##
## Interpretation flagged for design review: chains are computed per tag
## (same-tag adjacency), since Hybrid Slates "bridge two chains" - implying chains are tag-scoped, not one
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

## Sums compute_chains()'s per-chain results per tag - two disconnected
## same-tag chains both contribute.
static func bonus_by_tag(chains: Array[ChainResult]) -> Dictionary:
	var totals: Dictionary = {}
	for result in chains:
		totals[result.tag] = totals.get(result.tag, 0.0) + result.bonus_percent
	return totals

## v4.9: Constants.Stat -> float, every placed Slate's flat_<stat>
## modifiers (EquipmentComponent.AFFIX_STAT_KEYS) scaled by (1 + the bonus
## of the chain that Slate sits in). Only stat keys are amplified - every
## other modifier (damage%, ailment chance, auto-cast...) is read elsewhere
## at its face value. A lone Slate is its own chain (its own tile count),
## same as for the damage chain bonus - intended (user decision). Player's
## only source for StatSheet.slate_bonus.
static func slate_stat_bonuses(board: FateBoard, chains: Array[ChainResult]) -> Dictionary:
	var chain_bonus_by_placement := {}
	for result in chains:
		for placement_id in result.placement_ids:
			chain_bonus_by_placement[placement_id] = max(chain_bonus_by_placement.get(placement_id, 0.0), result.bonus_percent)
	var totals := {}
	for placement_id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		var amplifier: float = 1.0 + chain_bonus_by_placement.get(placement_id, 0.0)
		for modifier in data.slate.modifiers:
			if EquipmentComponent.AFFIX_STAT_KEYS.has(modifier.stat_key):
				var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[modifier.stat_key]
				totals[stat] = totals.get(stat, 0.0) + modifier.value * amplifier
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

## Every placed Slate's other modifiers (its fixed lines and the ones rolled
## or crafted onto it: damage, speed, ailments...), summed
## per canonical key at face value - chains amplify only attributes.
static func slate_misc_bonuses(board: FateBoard) -> Dictionary:
	var totals := {}
	for placement_id in board.placements:
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		for modifier in data.slate.modifiers:
			var key := StatKeys.canonical(modifier.stat_key)
			if EquipmentComponent.is_misc_key(key):
				totals[key] = totals.get(key, 0.0) + modifier.value
		for affix in data.slate.explicits:
			if EquipmentComponent.is_misc_key(affix.key()):
				totals[affix.key()] = totals.get(affix.key(), 0.0) + affix.value
	return totals
