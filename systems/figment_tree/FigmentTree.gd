extends RefCounted
class_name FigmentTree
## The Figment Tree: a passive tree that steers what spawns in Figments.
## Points come from first clears (FigmentProgress). The root is always
## allocated; a node can be allocated when it links to an allocated node,
## and refunded (free) when every other allocated node still reaches the
## root without it.
##
## Six sectors fan out from the root: Terrain (which styles drop), Factions
## (who fills the packs), Monsters (pack size and rarity), Rewards (what
## drops), Encounters (chests, bosses, Maw Fragments) and Figments (drop
## chance, tier, mods). Every effect applies only inside a Figment.
##
## Effect keys (value units in brackets):
##   style_weight:<family> [% weight]   family_quantity:<family> [% IIQ]
##   faction_weight:<faction> [% weight] faction_rarity:<faction> [% IIR]
##   pack_size [%]  rarity_weight:<elite|champion|ascendant> [% weight]
##   ascendant_extra_rolls [drop rolls]  map_quantity / map_rarity [%]
##   reward:<currency|slates|jewels|uniques|gear> [% chance]
##   extra_chest [% chance of one more]  chest_quantity [%]
##   boss_reward [% Gold/XP]  boss_extra_rolls [drop rolls]
##   fragment_chance [% extra Maw Fragment]
##   figment_drop [% chance]  figment_tier_up [% chance]  figment_extra_mod [mods]

const ROOT_ID := "engine_core"
const FACTIONS: Array[String] = ["unchartered", "hollowed", "synod", "veilborne"]

static var _nodes: Array[FigmentTreeNode] = []
static var _by_id: Dictionary = {}
static var _effect_cache: Dictionary = {}
static var _effect_cache_hash: int = 0

static func all_nodes() -> Array[FigmentTreeNode]:
	if _nodes.is_empty():
		_build()
	return _nodes

static func get_node_by_id(node_id: String) -> FigmentTreeNode:
	all_nodes()
	return _by_id.get(node_id)

static func is_allocated(node_id: String) -> bool:
	return node_id == ROOT_ID or GameState.figment_tree_unlocked_nodes.has(node_id)

static func can_unlock(node_id: String) -> bool:
	var node := get_node_by_id(node_id)
	if node == null or is_allocated(node_id):
		return false
	if FigmentProgress.points_available() < node.point_cost:
		return false
	return node.links.any(func(id: String): return is_allocated(id))

static func unlock(node_id: String) -> bool:
	if not can_unlock(node_id):
		return false
	GameState.figment_tree_unlocked_nodes.append(node_id)
	return true

## Refundable when every other allocated node still reaches the root.
static func can_refund(node_id: String) -> bool:
	if node_id == ROOT_ID or not GameState.figment_tree_unlocked_nodes.has(node_id):
		return false
	var reached := {ROOT_ID: true}
	var frontier: Array[String] = [ROOT_ID]
	while not frontier.is_empty():
		var current: FigmentTreeNode = get_node_by_id(frontier.pop_back())
		for id in current.links:
			if id != node_id and not reached.has(id) and is_allocated(id):
				reached[id] = true
				frontier.append(id)
	for id in GameState.figment_tree_unlocked_nodes:
		if id != node_id and not reached.has(id):
			return false
	return true

static func refund(node_id: String) -> bool:
	if not can_refund(node_id):
		return false
	GameState.figment_tree_unlocked_nodes.erase(node_id)
	return true

static func reset() -> void:
	GameState.figment_tree_unlocked_nodes.clear()

## Sum of one effect over the allocated nodes; 0 outside a Figment unless
## `anywhere` (the tree screen's totals).
static func effect(key: String, anywhere: bool = false) -> float:
	if not anywhere and GameState.active_map == null:
		return 0.0
	var allocated: Array[String] = GameState.figment_tree_unlocked_nodes
	if allocated.hash() != _effect_cache_hash or _effect_cache.is_empty() and not allocated.is_empty():
		_effect_cache = {}
		for id in allocated:
			var node := get_node_by_id(id)
			if node:
				for k in node.effects:
					_effect_cache[k] = float(_effect_cache.get(k, 0.0)) + float(node.effects[k])
		_effect_cache_hash = allocated.hash()
	return float(_effect_cache.get(key, 0.0))

## ---- Layout --------------------------------------------------------------

## Sectors: centre angle (degrees, 0 = right, -90 = up), trunk nodes along
## it, then forks spread across FORK_SPREAD degrees, each a chain outward.
const TRUNK_START := 1.2
const STEP := 0.95
const FORK_SPREAD := 46.0
## Forks start at least this far out, so five fit side by side.
const FORK_MIN_RADIUS := 3.0

static func _build() -> void:
	_nodes = []
	_by_id = {}
	var root := _make(ROOT_ID, "Reality Engine", "The heart of the tree. Always allocated.", {}, 0, true, "")
	root.position = Vector2.ZERO
	_sector("Terrain", -90.0, [
		["terrain_trunk_1", "Cartography", "+8% chance for monsters to drop a Figment", {"figment_drop": 8.0}],
		["terrain_trunk_2", "Wandering Memory", "+3% Item Quantity in Figments", {"map_quantity": 3.0}],
	], [
		_family_fork("dungeon", "Dungeon", "Stone Remembers"),
		_family_fork("desert", "Desert", "Shifting Sands"),
		_family_fork("forest", "Forest", "Old Growth"),
		_family_fork("snow", "Snow", "Long Winter"),
	])
	_sector("Factions", -30.0, [
		["faction_trunk_1", "Familiar Faces", "+3% Pack Size", {"pack_size": 3.0}],
	], [
		_faction_fork("unchartered", "Unchartered", "Debts Collected"),
		_faction_fork("hollowed", "Hollowed", "The Threshold Crowd"),
		_faction_fork("synod", "Synod", "Relic Hunters"),
		_faction_fork("veilborne", "Veilborne", "Choir of Thieves"),
	])
	_sector("Monsters", 30.0, [
		["monsters_trunk_1", "Crowded Memory", "+4% Pack Size", {"pack_size": 4.0}],
		["monsters_trunk_2", "Restless Dead", "+4% Pack Size", {"pack_size": 4.0}],
	], [
		[
			["pack_1", "Swarming", "+5% Pack Size", {"pack_size": 5.0}],
			["pack_2", "Swarming", "+5% Pack Size", {"pack_size": 5.0}],
			["pack_3", "Swarming", "+5% Pack Size", {"pack_size": 5.0}],
			["pack_notable", "Teeming", "+15% Pack Size", {"pack_size": 15.0}, 2],
		],
		_rarity_fork("elite", "Elite", "Blue Blood"),
		_rarity_fork("champion", "Champion", "Warbands"),
		[
			["ascendant_1", "Rising Power", "+20% chance for packs to be Ascendant", {"rarity_weight:ascendant": 20.0}],
			["ascendant_2", "Rising Power", "+20% chance for packs to be Ascendant", {"rarity_weight:ascendant": 20.0}],
			["ascendant_notable", "Ascendancy", "+50% chance for packs to be Ascendant\nAscendants get 1 extra drop roll", {"rarity_weight:ascendant": 50.0, "ascendant_extra_rolls": 1.0}, 2],
		],
	])
	_sector("Rewards", 90.0, [
		["rewards_trunk_1", "Plunder", "+3% Item Rarity in Figments", {"map_rarity": 3.0}],
	], [
		_reward_fork("currency", "Currency", "Hoarder"),
		_reward_fork("slates", "Slate", "Graven Fate"),
		_reward_fork("jewels", "Jewel and Lens", "Facets"),
		_reward_fork("uniques", "Unique", "Singular Things"),
		_reward_fork("gear", "Gear", "Armoury"),
	])
	_sector("Encounters", 150.0, [
		["encounters_trunk_1", "Hidden Rooms", "+25% chance of an extra treasure chest", {"extra_chest": 25.0}],
	], [
		[
			["chest_1", "Strongboxes", "+25% chance of an extra treasure chest", {"extra_chest": 25.0}],
			["chest_2", "Strongboxes", "+25% chance of an extra treasure chest", {"extra_chest": 25.0}],
			["chest_notable", "Treasure Hoard", "Treasure chests drop 50% more items", {"chest_quantity": 50.0}, 2],
		],
		[
			["boss_1", "Spoils of the Vault", "Figment bosses grant 15% more Gold and XP", {"boss_reward": 15.0}],
			["boss_2", "Spoils of the Vault", "Figment bosses grant 15% more Gold and XP", {"boss_reward": 15.0}],
			["boss_notable", "Echoing Boss", "Figment bosses get 3 extra drop rolls", {"boss_extra_rolls": 3.0}, 2],
		],
		[
			["fragment_1", "Maw Whispers", "Figment bosses have +10% chance to drop an extra Maw Fragment", {"fragment_chance": 10.0}],
			["fragment_2", "Maw Whispers", "Figment bosses have +10% chance to drop an extra Maw Fragment", {"fragment_chance": 10.0}],
			["fragment_notable", "Call of the Maw", "Figment bosses have +25% chance to drop an extra Maw Fragment", {"fragment_chance": 25.0}, 2],
		],
	])
	_sector("Figments", 210.0, [
		["figments_trunk_1", "Engine Attunement", "+10% chance for monsters to drop a Figment", {"figment_drop": 10.0}],
	], [
		[
			["figdrop_1", "Recollection", "+15% chance for monsters to drop a Figment", {"figment_drop": 15.0}],
			["figdrop_2", "Recollection", "+15% chance for monsters to drop a Figment", {"figment_drop": 15.0}],
			["figdrop_notable", "Self-Replicating", "+40% chance for monsters to drop a Figment", {"figment_drop": 40.0}, 2],
		],
		[
			["figtier_1", "Ascending Memory", "Dropped Figments have +5% chance to be one tier higher", {"figment_tier_up": 5.0}],
			["figtier_2", "Ascending Memory", "Dropped Figments have +5% chance to be one tier higher", {"figment_tier_up": 5.0}],
			["figtier_notable", "Climbing Memory", "Dropped Figments have +15% chance to be one tier higher", {"figment_tier_up": 15.0}, 2],
		],
		[
			["figmod_1", "Warped Memory", "+2% Item Rarity in Figments", {"map_rarity": 2.0}],
			["figmod_2", "Warped Memory", "+2% Item Rarity in Figments", {"map_rarity": 2.0}],
			["figmod_notable", "Deeper Reality", "Rolled Figments get 1 additional modifier", {"figment_extra_mod": 1.0}, 3],
		],
	])

static func _family_fork(family: String, label: String, notable: String) -> Array:
	var chain := []
	for i in 3:
		chain.append(["%s_%d" % [family, i + 1], "%s Memories" % label, "+20%% chance for %s Figments to drop" % label, {"style_weight:" + family: 20.0}])
	chain.append(["%s_notable" % family, notable, "+60%% chance for %s Figments to drop\n+6%% Item Quantity in %s Figments" % [label, label],
		{"style_weight:" + family: 60.0, "family_quantity:" + family: 6.0}, 2])
	return chain

static func _faction_fork(faction: String, label: String, notable: String) -> Array:
	var chain := []
	for i in 2:
		chain.append(["%s_%d" % [faction, i + 1], "%s Territory" % label, "+25%% chance for packs to be %s" % label, {"faction_weight:" + faction: 25.0}])
	chain.append(["%s_notable" % faction, notable, "+50%% chance for packs to be %s\n%s monsters drop items with +10%% Item Rarity" % [label, label],
		{"faction_weight:" + faction: 50.0, "faction_rarity:" + faction: 10.0}, 2])
	return chain

static func _rarity_fork(rarity: String, label: String, notable: String) -> Array:
	return [
		["%s_1" % rarity, "%s Packs" % label, "+15%% chance for packs to be %s" % label, {"rarity_weight:" + rarity: 15.0}],
		["%s_2" % rarity, "%s Packs" % label, "+15%% chance for packs to be %s" % label, {"rarity_weight:" + rarity: 15.0}],
		["%s_notable" % rarity, notable, "+40%% chance for packs to be %s" % label, {"rarity_weight:" + rarity: 40.0}, 2],
	]

static func _reward_fork(category: String, label: String, notable: String) -> Array:
	return [
		["reward_%s_1" % category, "%s Finds" % label, "+15%% chance for %s drops" % label, {"reward:" + category: 15.0}],
		["reward_%s_2" % category, "%s Finds" % label, "+15%% chance for %s drops" % label, {"reward:" + category: 15.0}],
		["reward_%s_notable" % category, notable, "+40%% chance for %s drops" % label, {"reward:" + category: 40.0}, 2],
	]

static func _sector(sector_name: String, angle: float, trunk: Array, forks: Array) -> void:
	var previous := ROOT_ID
	var dir := Vector2.from_angle(deg_to_rad(angle))
	var radius := TRUNK_START
	for spec in trunk:
		var node := _spec_node(spec, sector_name)
		node.position = dir * radius
		_link(previous, node.node_id)
		previous = node.node_id
		radius += STEP
	var trunk_end := previous
	radius = maxf(radius, FORK_MIN_RADIUS)
	for f in forks.size():
		var fork_angle := angle + (0.0 if forks.size() == 1 else (float(f) / (forks.size() - 1) - 0.5) * FORK_SPREAD)
		var fork_dir := Vector2.from_angle(deg_to_rad(fork_angle))
		var r := radius
		var prev := trunk_end
		for spec in forks[f]:
			var node := _spec_node(spec, sector_name)
			node.position = fork_dir * r
			_link(prev, node.node_id)
			prev = node.node_id
			r += STEP

static func _spec_node(spec: Array, sector_name: String) -> FigmentTreeNode:
	var cost: int = spec[4] if spec.size() > 4 else 1
	return _make(spec[0], spec[1], spec[2], spec[3], cost, cost > 1, sector_name)

static func _make(id: String, display_name: String, desc: String, effects: Dictionary, cost: int, notable: bool, sector_name: String) -> FigmentTreeNode:
	var n := FigmentTreeNode.new()
	n.node_id = id
	n.display_name = display_name
	n.description = desc
	n.point_cost = cost
	n.notable = notable
	n.effects = effects
	n.sector = sector_name
	_nodes.append(n)
	_by_id[id] = n
	return n

static func _link(a: String, b: String) -> void:
	var na: FigmentTreeNode = _by_id[a]
	var nb: FigmentTreeNode = _by_id[b]
	if not na.links.has(b):
		na.links.append(b)
	if not nb.links.has(a):
		nb.links.append(a)
