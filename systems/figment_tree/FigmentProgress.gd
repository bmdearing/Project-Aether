extends RefCounted
class_name FigmentProgress
## Endgame progression: which Figments (style x tier) have been completed.
## Each style is worth three Figment Tree points, one for its first clear in
## each band (Low, Mid, High). Figments can drop at most one tier above the
## highest tier completed, so tiers open one at a time.
##
## MILESTONES is the frame for the endgame story: entries unlock as the
## memory is rebuilt ("total" counts band clears). The story itself is a
## placeholder until it's written.

const MILESTONES := [
	{"total": 1, "title": "The First Figment", "text": "The Reality Engine holds its first rebuilt memory. Whose it is, it won't say."},
	{"total": 8, "title": "Echoes", "text": "The Figments begin to agree with each other. [Story placeholder]"},
	{"tier": FigmentMods.BAND_SIZE + 1, "title": "Deeper Memory", "text": "A Mid-band Figment completed: the memories grow older and stranger. [Story placeholder]"},
	{"total": 20, "title": "A Shape in the Engine", "text": "Enough has been rebuilt to see an outline. [Story placeholder]"},
	{"tier": FigmentMods.BAND_SIZE * 2 + 1, "title": "The Oldest Memories", "text": "A High-band Figment completed: something notices the rebuilding. [Story placeholder]"},
	{"total": 32, "title": "Half Remembered", "text": "[Story placeholder]"},
	{"tier": FigmentMods.MAX_TIER, "title": "The Last Tier", "text": "A Tier 21 Figment completed. [Story placeholder]"},
	{"total": -1, "title": "Whole", "text": "Every Figment rebuilt in every band. The final encounter waits here. [Final boss to be designed]"},
]

static func key(style_id: String, tier: int) -> String:
	return "%s:%d" % [style_id, tier]

static func is_completed(style_id: String, tier: int) -> bool:
	return GameState.figment_completions.has(key(style_id, tier))

## Has this style been completed at any tier of `band`?
static func is_band_completed(style_id: String, band: int) -> bool:
	return highest_in_band(style_id, band) > 0

## Highest tier of `band` completed in this style, 0 for none.
static func highest_in_band(style_id: String, band: int) -> int:
	var r := FigmentMods.band_range(band)
	for t in range(r.y, r.x - 1, -1):
		if is_completed(style_id, t):
			return t
	return 0

## Records a completed Figment; true when it's the style's first clear in
## that band (a point).
static func record(style_id: String, tier: int) -> bool:
	if style_id.is_empty():
		return false
	tier = clampi(tier, 1, FigmentMods.MAX_TIER)
	var first := not is_band_completed(style_id, FigmentMods.band_of(tier))
	var k := key(style_id, tier)
	GameState.figment_completions[k] = int(GameState.figment_completions.get(k, 0)) + 1
	return first

## Band clears so far: one per style per band.
static func total_completed() -> int:
	var clears := {}
	for k in GameState.figment_completions:
		var parts := String(k).split(":")
		clears["%s:%d" % [parts[0], FigmentMods.band_of(int(parts[1]))]] = true
	return clears.size()

static func total_possible() -> int:
	return MapTileset.all_ids().size() * 3

static func highest_tier_completed() -> int:
	var best := 0
	for k in GameState.figment_completions:
		best = maxi(best, int(String(k).get_slice(":", 1)))
	return best

## Highest tier a dropped Figment can be.
static func max_drop_tier() -> int:
	return clampi(highest_tier_completed() + 1, 1, FigmentMods.MAX_TIER)

## Styles cleared at least once in `band`.
static func completed_in_band(band: int) -> int:
	var n := 0
	for id in MapTileset.all_ids():
		if is_band_completed(id, band):
			n += 1
	return n

static func points_earned() -> int:
	return total_completed()

static func points_spent() -> int:
	var spent := 0
	for id in GameState.figment_tree_unlocked_nodes:
		var node := FigmentTree.get_node_by_id(id)
		if node:
			spent += node.point_cost
	return spent

static func points_available() -> int:
	return points_earned() - points_spent()

static func milestone_reached(m: Dictionary) -> bool:
	if m.has("tier"):
		return highest_tier_completed() >= int(m["tier"])
	var need := int(m["total"])
	return total_completed() >= (total_possible() if need < 0 else need)
