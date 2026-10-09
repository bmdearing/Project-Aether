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

## Returns Array[ChainResult], one per distinct connected same-tag group. A
## Slate with several tags (Hybrid, or bridged by a Lens) counts in a chain
## of each.
static func compute_chains(board: FateBoard) -> Array[ChainResult]:
	var visited_by_tag := {}  # tag -> {cell: true}
	var results: Array[ChainResult] = []
	var tags_of := {}
	for placement_id in board.placements:
		tags_of[placement_id] = board.placed_tags(board.placements[placement_id])

	for placement_id in board.placements.keys():
		var data: FateBoard.PlacedSlateData = board.placements[placement_id]
		for tag in tags_of[placement_id]:
			var visited: Dictionary = visited_by_tag.get(tag, {})
			visited_by_tag[tag] = visited
			for start_cell in data.cells:
				if visited.has(start_cell):
					continue
				var chain := _flood_fill(board, start_cell, tag, visited, tags_of)
				if chain.tile_count > 0:
					chain.tag = tag
					chain.bonus_percent = _bonus_for_tile_count(chain.tile_count)
					results.append(chain)

	return results

static func _flood_fill(board: FateBoard, start_cell: Vector2i, tag: int, visited_cells: Dictionary, tags_of: Dictionary) -> ChainResult:
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
		# Member if the Slate carries this tag (its own, Hybrid, or a Lens bridge).
		if not tags_of[placement_id].has(tag):
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
		var amplifier: float = (1.0 + chain_bonus_by_placement.get(placement_id, 0.0)) * lens_multiplier(board, data, true)
		for modifier in data.slate.modifiers:
			if EquipmentComponent.AFFIX_STAT_KEYS.has(modifier.stat_key):
				var stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[modifier.stat_key]
				totals[stat] = totals.get(stat, 0.0) + modifier.value * amplifier
		# Lenses' own (jewel) modifiers count at face value.
		for lens in data.slate.lenses:
			for affix in lens.affixes:
				if EquipmentComponent.AFFIX_STAT_KEYS.has(affix.key()):
					var lens_stat: Constants.Stat = EquipmentComponent.AFFIX_STAT_KEYS[affix.key()]
					totals[lens_stat] = totals.get(lens_stat, 0.0) + affix.value
	return totals

## What a placed Slate's attribute lines are multiplied by: its best chain's
## bonus times the Lenses covering it (the same sum slate_stat_bonuses uses).
static func attribute_multiplier(board: FateBoard, placement_id: String) -> float:
	var data: FateBoard.PlacedSlateData = board.placements.get(placement_id)
	if data == null:
		return 1.0
	var bonus := 0.0
	for result in compute_chains(board):
		if result.placement_ids.has(placement_id):
			bonus = maxf(bonus, result.bonus_percent)
	return (1.0 + bonus) * lens_multiplier(board, data, true)

## A lone Slate's multiplier: it forms a chain of its own tiles.
static func lone_multiplier(slate: Slate) -> float:
	return 1.0 + _bonus_for_tile_count(slate.get_size())

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
		var amplifier := lens_multiplier(board, data, false)
		for modifier in data.slate.modifiers:
			var key := StatKeys.canonical(modifier.stat_key)
			if EquipmentComponent.is_misc_key(key):
				totals[key] = totals.get(key, 0.0) + modifier.value * amplifier
		for affix in data.slate.explicits:
			if EquipmentComponent.is_misc_key(affix.key()):
				totals[affix.key()] = totals.get(affix.key(), 0.0) + affix.value * amplifier
		for lens in data.slate.lenses:
			for affix in lens.affixes:
				if EquipmentComponent.is_misc_key(affix.key()):
					totals[affix.key()] = totals.get(affix.key(), 0.0) + affix.value
	return totals

## How much stronger Lenses in range make a placed Slate's modifiers:
## "<Tag> Slates in radius have X% stronger modifiers" for its tags, plus
## "Attribute lines ... X% stronger" when attributes is true.
static func lens_multiplier(board: FateBoard, data: FateBoard.PlacedSlateData, attributes: bool) -> float:
	var percent := 0.0
	var tags := board.placed_tags(data)
	for effect in board.lens_effects_at(data.cells):
		if effect["mod"] == "amplify_tag" and tags.has(effect["tag"]):
			percent += effect["value"]
		elif effect["mod"] == "amplify_attributes" and attributes:
			percent += effect["value"]
	return 1.0 + percent / 100.0

## How chains work, with the tier table, for tooltips.
static func explanation() -> String:
	var lines := PackedStringArray([
		"Chains",
		"Slates that touch edge to edge and share a tag form a chain.",
		"Each chain amplifies the attribute lines (Strength, Agility, Intellect) of every",
		"Slate in it by its bonus. Other modifiers count at face value.",
		"Hybrid Slates and bridging Lenses count toward the chains of both tags.",
		"",
		"Bonus per tile in the chain:",
	])
	for tier in Constants.CHAIN_BONUS_TIERS:
		var range_text := "%d+" % tier["min"] if tier["max"] > 9999 else "%d-%d" % [tier["min"], tier["max"]]
		lines.append("  Tiles %s: +%.2f%% each" % [range_text, tier["per_tile"] * 100.0])
	lines.append("")
	lines.append("e.g. 20 tiles = +%.0f%%, 40 tiles = +%.0f%%" % [_bonus_for_tile_count(20) * 100.0, _bonus_for_tile_count(40) * 100.0])
	return "\n".join(lines)

## The chains a placed Slate belongs to, one line each, for its hover card.
static func chain_lines_for(board: FateBoard, placement_id: String) -> Array[String]:
	var lines: Array[String] = []
	for result in compute_chains(board):
		if result.placement_ids.has(placement_id):
			lines.append("%s chain: %d tiles, +%.2f%% attributes" % [Constants.DAMAGE_TYPE_NAME.get(result.tag, "?"), result.tile_count, result.bonus_percent * 100.0])
	return lines
