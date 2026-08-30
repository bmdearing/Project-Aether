extends RefCounted
class_name FigmentTree
## Scaffolding for the Figment Tree - user request: "prepare legs for a
## Figment Tree to complete figments to get points, increasing the yield
## and type of content seen on Figments." This provides the data model
## (FigmentTreeNode) and a small hand-authored node list, plus real,
## tested unlock/validation logic (GameState.figment_tree_points spent
## against GameState.figment_tree_unlocked_nodes) - deliberately NOT a
## full system: no UI screen exists to spend points through yet, and no
## node's effect_key is actually wired into FigmentRoller/loot generation
## yet. "Prepare legs," not "build the whole thing" - the next pass that
## wants to finish this needs a UI (mirroring FateBoardEditor/Crafting
## Screen's own patterns) and to wire each effect_key into a real formula.

static func all_nodes() -> Array[FigmentTreeNode]:
	return [
		_node("keener_eye", "Keener Eye", "Figments you find carry more loot.", 1, "", "figment_loot_quantity"),
		_node("deeper_reality", "Deeper Reality", "Figments can roll one additional modifier.", 1, "", "figment_extra_affix"),
		_node("hungry_engine", "Hungry Engine", "Loot found in Figments skews toward higher rarity.", 2, "keener_eye", "figment_loot_rarity"),
		_node("echoing_boss", "Echoing Boss", "Figment bosses grant more Gold and XP.", 2, "deeper_reality", "boss_reward_increase"),
		_node("warped_convergence", "Warped Convergence", "Raises the maximum Figment tier that can drop.", 3, "hungry_engine", "figment_tier_ceiling_increase"),
	]

static func _node(id: String, display_name: String, desc: String, cost: int, prereq: String, effect: String) -> FigmentTreeNode:
	var n := FigmentTreeNode.new()
	n.node_id = id
	n.display_name = display_name
	n.description = desc
	n.point_cost = cost
	n.prerequisite_node_id = prereq
	n.effect_key = effect
	return n

static func get_node_by_id(node_id: String) -> FigmentTreeNode:
	for n in all_nodes():
		if n.node_id == node_id:
			return n
	return null

## True if this node isn't already unlocked, its prerequisite (if any) IS
## unlocked, and the player has enough points.
static func can_unlock(node_id: String) -> bool:
	if GameState.figment_tree_unlocked_nodes.has(node_id):
		return false
	var node := get_node_by_id(node_id)
	if node == null:
		return false
	if node.prerequisite_node_id != "" and not GameState.figment_tree_unlocked_nodes.has(node.prerequisite_node_id):
		return false
	return GameState.figment_tree_points >= node.point_cost

static func unlock(node_id: String) -> bool:
	if not can_unlock(node_id):
		return false
	var node := get_node_by_id(node_id)
	GameState.figment_tree_points -= node.point_cost
	GameState.figment_tree_unlocked_nodes.append(node_id)
	return true
