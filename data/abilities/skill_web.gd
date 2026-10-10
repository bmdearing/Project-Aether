extends RefCounted
class_name SkillWeb
## Each spell's passive web (documents/Skill_Webs_Design.md). A spell earns
## one point per level above 1, spent only in its own web. Nodes are either
## shared building blocks (more damage, cheaper, wider...) chosen by the
## spell's tags, or the spell's own twists that change how it behaves.
## Ability.web_points holds what's allocated; Ability.web_value() and
## has_twist() read it, and the spell code applies it.
##
## Layout: the spell sits at the centre; ring 1 is open from the start, each
## outer node needs a point in a node it links from (`requires`).

## Effect keys read by Ability / PlayerAbilityCast.
const MORE_DAMAGE := &"more_damage"        # % more damage per point
const MANA_COST := &"mana_cost"            # % less Mana cost
const COOLDOWN := &"cooldown"              # % cooldown recovery
const AREA := &"area"                      # % increased area
const PROJECTILE_SPEED := &"projectile_speed"
const DURATION := &"duration"
const CRIT := &"crit"                      # + base crit chance, percentage points
const STATUS_CHANCE := &"status_chance"    # + chance for the spell's own ailments, percentage points
const LIMIT := &"limit"
const PROJECTILES := &"projectiles"        # + projectiles (spell decides what that means)
const TWIST := &"twist"                    # behaviour switch, read with has_twist(id)

class WebNode:
	var id: String
	var name: String
	var description: String
	var max_points: int = 1
	var effect: StringName
	var per_point: float = 0.0
	var requires: Array[String] = []
	var exclusive_with: String = ""
	## One of the spell's own nodes (TWISTS), laid out on the twist side even
	## when it adds a value rather than switching behaviour.
	var from_spell := false
	## Placed in a gap of the first ring and opened by the nodes either side.
	var auto_link := false
	## Polar layout: ring (1 = innermost) and angle in degrees.
	var ring: int = 1
	var angle: float = 0.0

	func _init(fields: Dictionary) -> void:
		for key in fields:
			set(key, fields[key])

	func is_twist() -> bool:
		return effect == TWIST

static var _cache: Dictionary = {}  # ability_id -> Array[WebNode]

## Building blocks: [id, name, description template, max, effect, per point,
## predicate key, ring]. Ring 2 blocks need their ring 1 tier.
const BLOCKS := [
	["potency", "Potency", "+%s%% more damage per point.", 3, MORE_DAMAGE, 6.0, "damage", 1],
	["efficiency", "Efficiency", "%s%% less Mana cost per point.", 3, MANA_COST, 6.0, "always", 1],
	["swiftness", "Swiftness", "+%s%% cooldown recovery and cast speed per point.", 3, COOLDOWN, 6.0, "cooldown", 1],
	["reach", "Reach", "+%s%% area per point.", 3, AREA, 8.0, "area", 1],
	["velocity", "Velocity", "+%s%% projectile speed per point.", 3, PROJECTILE_SPEED, 8.0, "projectile", 1],
	["endurance", "Endurance", "+%s%% duration per point.", 3, DURATION, 8.0, "duration", 1],
	["precision", "Precision", "+%s%% critical strike chance per point.", 3, CRIT, 3.0, "damage", 2],
	["affliction", "Affliction", "+%s%% chance to inflict this spell's ailments per point.", 3, STATUS_CHANCE, 6.0, "status", 2],
	["legion", "Legion", "+%s to how many can be active at once per point.", 2, LIMIT, 1.0, "limit", 2],
	["potency_2", "Greater Potency", "+%s%% more damage per point.", 3, MORE_DAMAGE, 6.0, "damage", 3],
	["reach_2", "Greater Reach", "+%s%% area per point.", 3, AREA, 8.0, "area", 3],
	["efficiency_2", "Thrift", "%s%% less Mana cost per point.", 2, MANA_COST, 8.0, "always", 3],
]
## Ring 2/3 blocks hang off these ring 1 blocks (else potency).
const BLOCK_PARENT := {"precision": "potency", "affliction": "potency", "legion": "efficiency",
	"potency_2": "precision", "reach_2": "reach", "efficiency_2": "efficiency"}

## Spell twists: id -> node fields (requires defaults to the first ring 1
## block). Only twists the spell code applies are listed; more come in with
## their spells (documents/Skill_Webs_Design.md).
const TWISTS := {
	"comet": [
		{"id": "molten_core", "name": "Molten Core", "description": "Comet becomes Fire: it burns instead of chilling, and deals its bonus damage to Ignited enemies instead of Chilled ones.", "ring": 2},
		{"id": "meteor_shower", "name": "Meteor Shower", "description": "The strike splits into 3 smaller comets around the target, each dealing 45% damage over 60% of the area.", "ring": 3, "requires": ["molten_core", "reach_2"]},
		{"id": "heavy_mass", "name": "Heavy Mass", "description": "+60% more damage, but the comet falls 50% slower.", "ring": 3, "requires": ["potency_2"]},
	],
	"spark": [
		{"id": "static_swarm", "name": "Static Swarm", "description": "+1 spark per point.", "ring": 2, "max_points": 3, "effect": PROJECTILES, "per_point": 1.0, "requires": ["velocity"]},
		{"id": "overcharge", "name": "Overcharge", "description": "Sparks move 70% faster and deal 30% more damage, but last half as long.", "ring": 3, "requires": ["static_swarm"], "exclusive_with": "stalking_spark"},
		{"id": "stalking_spark", "name": "Stalking Spark", "description": "Sparks move 40% slower and last twice as long.", "ring": 3, "requires": ["static_swarm"], "exclusive_with": "overcharge"},
	],
	"ice_pulse": [
		{"id": "shard_volley", "name": "Shard Volley", "description": "The pulse becomes 5 icicles fired ahead of you.", "ring": 2, "exclusive_with": "second_pulse"},
		{"id": "splinters", "name": "Splinters", "description": "+1 icicle per point (Shard Volley).", "ring": 3, "max_points": 4, "effect": PROJECTILES, "per_point": 1.0, "requires": ["shard_volley"]},
		{"id": "frozen_nova", "name": "Frozen Nova", "description": "Icicles fire in a full ring around you instead (Shard Volley).", "ring": 3, "requires": ["shard_volley"]},
		{"id": "second_pulse", "name": "Second Pulse", "description": "A second pulse follows 0.4 seconds later at half damage.", "ring": 2, "exclusive_with": "shard_volley"},
		{"id": "deep_freeze", "name": "Deep Freeze", "description": "Hits on Chilled enemies Freeze them.", "ring": 3, "requires": ["second_pulse", "shard_volley"]},
	],
	"thunder_javelin": [
		{"id": "frost_javelin", "name": "Frost Javelin", "description": "The javelin is Cold instead of Lightning and Chills.", "ring": 2},
		{"id": "javelin_volley", "name": "Javelin Volley", "description": "Throws 3 javelins in a fan, each dealing 60% damage.", "ring": 2},
	],
	"cinder_lance": [
		{"id": "storm_lance", "name": "Storm Lance", "description": "The lance is Lightning instead of Fire and Shocks.", "ring": 2},
		{"id": "twin_lances", "name": "Twin Lances", "description": "Hurls a second lance in a V, each dealing 75% damage.", "ring": 2},
	],
	"inferno": [
		{"id": "inferno_firestorm", "name": "Firestorm", "description": "Three smaller columns erupt across the area instead of one, each with 50% damage and half the area.", "ring": 2},
		{"id": "conflagration", "name": "Conflagration", "description": "Every hit Ignites.", "ring": 3, "requires": ["inferno_firestorm", "potency_2"]},
	],
	"flame_wall": [
		{"id": "frost_wall", "name": "Frost Wall", "description": "The wall is Cold instead of Fire and Chills instead of igniting.", "ring": 2},
	],
	"flame_jets": [
		{"id": "walking_fire", "name": "Walking Fire", "description": "No longer slows you while channelling.", "ring": 2},
		{"id": "blue_flame", "name": "Blue Flame", "description": "+40% more damage, but drains Mana twice as fast.", "ring": 3, "requires": ["walking_fire", "potency_2"]},
	],
	"winters_eye": [
		{"id": "twin_eyes", "name": "Twin Eyes", "description": "Launches two orbs either side of the target, each dealing 60% damage.", "ring": 2},
	],
	"stormcall": [
		{"id": "hellfire_call", "name": "Hellfire Call", "description": "The strike is Fire instead of Lightning and Ignites.", "ring": 2},
		{"id": "thunderhead", "name": "Thunderhead", "description": "The strike repeats twice more at the same spot, 0.5 seconds apart, at 60% damage.", "ring": 2},
	],
	"static_discharge": [
		{"id": "grounded", "name": "Grounded", "description": "Half the radius, double the damage, and every hit Shocks.", "ring": 2, "exclusive_with": "chain_lightning"},
		{"id": "chain_lightning", "name": "Chain Lightning", "description": "Each arc jumps on to up to 3 enemies instead of 1.", "ring": 2, "exclusive_with": "grounded"},
	],
	"thunder_sweep": [
		{"id": "focused_sweep", "name": "Focused Sweep", "description": "Twice the bolts, all fired across the front half.", "ring": 2},
		{"id": "echo_sweep", "name": "Echo", "description": "The sweep repeats 0.6 seconds later, turned half a step, at 70% damage.", "ring": 3, "requires": ["focused_sweep", "potency_2"]},
	],
	"entropic_decay": [
		{"id": "pale_decay", "name": "Pale Decay", "description": "The decay is Pale instead of Entropic and leaves enemies Pallid (they deal less damage).", "ring": 2},
		{"id": "lingering_rot", "name": "Lingering Rot", "description": "The decay spreads out again 1 second later at 60% damage.", "ring": 2},
	],
	"black_hole": [
		{"id": "event_horizon", "name": "Event Horizon", "description": "Collapses at the end in a blast of Entropic damage (300%).", "ring": 2},
	],
	"tornado": [
		{"id": "firestorm", "name": "Firestorm", "description": "The tornado is Fire and Ignites.", "ring": 2},
		{"id": "twin_funnels", "name": "Twin Funnels", "description": "Summons two smaller tornadoes, each dealing 60% damage.", "ring": 3, "requires": ["firestorm", "legion"]},
	],
	"caltrops": [
		{"id": "barbed", "name": "Barbed", "description": "Caltrops inflict Bleed.", "ring": 2},
	],
	"frost_armor": [
		{"id": "rime", "name": "Rime", "description": "Its retaliation always Chills.", "ring": 2},
		{"id": "frost_shatter", "name": "Shatter", "description": "When the armour ends it bursts for 150% Cold damage over a wider area.", "ring": 3, "requires": ["rime", "potency_2"]},
	],
	"booming_blade": [
		{"id": "arc_blade", "name": "Arc Blade", "description": "Two more bolts, fanned wide.", "ring": 2},
	],
	"blink": [
		{"id": "long_step", "name": "Long Step", "description": "Teleport 60% further.", "ring": 2},
		{"id": "purging_step", "name": "Purging Step", "description": "Blinking removes every debuff on you.", "ring": 2},
	],
	"battle_cry": [
		{"id": "rallying_cry", "name": "Rallying Cry", "description": "Also restores 5% of your maximum Life.", "ring": 2},
	],
	"intimidating_shout": [
		{"id": "echoing_shout", "name": "Echoing Shout", "description": "The shout rings out again 2 seconds later.", "ring": 2},
	],
	"seismic_cry": [
		{"id": "aftershock", "name": "Aftershock", "description": "The slam repeats 0.8 seconds later at half strength.", "ring": 2},
	],
	"reap": [
		{"id": "withering_scythe", "name": "Withering Scythe", "description": "The scythe is Entropic instead of Aetheric and Unravels.", "ring": 2},
		{"id": "harvest", "name": "Harvest", "description": "Each enemy the scythe hits restores 1% of your maximum Life.", "ring": 2},
		{"id": "wide_arc", "name": "Wide Arc", "description": "The sweep covers 180 degrees, but deals 25% less damage.", "ring": 2},
		{"id": "second_swing", "name": "Second Swing", "description": "The scythe sweeps back again for 50% damage.", "ring": 3, "requires": ["harvest", "wide_arc", "potency_2"]},
	],
	"wraith": [
		{"id": "bound_soul", "name": "Bound Soul", "description": "The wraith lasts 50% longer.", "ring": 2},
		{"id": "ward_feast", "name": "Ward Feast", "description": "Every 4 Ward consumed adds damage, instead of every 7.", "ring": 2},
		{"id": "spectral_host", "name": "Spectral Host", "description": "Summons two wraiths that split the Ward between them.", "ring": 3, "requires": ["bound_soul", "ward_feast"]},
	],
	"shatter": [
		{"id": "resonance", "name": "Resonance", "description": "Each ailment broken on an enemy beyond the first adds 25% to all of its bursts.", "ring": 2},
		{"id": "splinter", "name": "Splinter", "description": "Every burst also hits enemies within 3 metres for 40% of its damage.", "ring": 3, "requires": ["resonance", "potency_2"]},
	],
	"purge": [
		{"id": "second_wind", "name": "Second Wind", "description": "Also restores 10% of your maximum Life.", "ring": 2},
	],
}

## The web for a spell: its building blocks, then its twists.
static func nodes_for(ability: Ability) -> Array:
	if ability == null:
		return []
	if _cache.has(ability.ability_id):
		return _cache[ability.ability_id]
	var nodes: Array = []
	var present := {}
	for b in BLOCKS:
		if not _applies(ability, b[6]):
			continue
		var node := WebNode.new({"id": b[0], "name": b[1], "description": b[2] % _num(b[5]), "max_points": b[3], "effect": b[4], "per_point": b[5], "ring": b[7]})
		present[node.id] = node
		nodes.append(node)
	for node: WebNode in nodes:
		if node.ring > 1:
			var parent: String = BLOCK_PARENT.get(node.id, "potency")
			if not present.has(parent):
				parent = "potency" if present.has("potency") else "efficiency"
			node.requires.assign([parent])
	var twists: Array = TWISTS.get(ability.ability_id, [])
	var twist_ids := twists.map(func(t): return t["id"])
	var twist_nodes: Array = []
	for fields in twists:
		var f: Dictionary = fields.duplicate()
		if not f.has("effect"):
			f["effect"] = TWIST
		var req: Array[String] = []
		req.assign(f.get("requires", []))
		f.erase("requires")
		var node := WebNode.new(f)
		node.from_spell = true
		node.requires.assign(req.filter(func(id): return present.has(id) or twist_ids.has(id)))
		# A twist that builds on another twist hangs off twists only, so its
		# links stay on the twist side of the web.
		var from_twists := node.requires.filter(func(id): return twist_ids.has(id))
		if not from_twists.is_empty():
			node.requires.assign(from_twists)
		# Otherwise _lay_out() links it to the two first-ring nodes beside it.
		if node.requires.is_empty():
			node.auto_link = true
		present[node.id] = node
		twist_nodes.append(node)
	nodes.append_array(twist_nodes)
	_lay_out(nodes, present)
	_cache[ability.ability_id] = nodes
	return nodes

static func _applies(ability: Ability, key: String) -> bool:
	match key:
		"always": return true
		"damage": return ability.deals_damage()
		"cooldown": return ability.cooldown_seconds > 0.0 or ability.base_cast_time > 0.0
		"area": return ability.has_tag(Ability.TAG_AREA)
		"projectile": return ability.has_tag(Ability.TAG_PROJECTILE)
		"duration": return ability.has_tag(Ability.TAG_DURATION)
		"status": return not ability.applies_status_effects.is_empty()
		"limit": return ability.has_tag(Ability.TAG_LIMIT)
	return false

static func _num(v: float) -> String:
	return str(int(v)) if v == roundf(v) else str(v)

static func find(ability: Ability, node_id: String) -> WebNode:
	for node: WebNode in nodes_for(ability):
		if node.id == node_id:
			return node
	return null

## ---- Points ------------------------------------------------------------------

static func points_available(ability: Ability) -> int:
	return maxi(ability.level - 1, 0)

static func points_spent(ability: Ability) -> int:
	var total := 0
	for id in ability.web_points:
		total += int(ability.web_points[id])
	return total

static func points_left(ability: Ability) -> int:
	return points_available(ability) - points_spent(ability)

static func points_in(ability: Ability, node_id: String) -> int:
	return int(ability.web_points.get(node_id, 0))

## "" when a point can go into node_id, else why not.
static func why_not_allocate(ability: Ability, node_id: String) -> String:
	var node := find(ability, node_id)
	if node == null:
		return "Unknown node."
	if points_left(ability) <= 0:
		return "No points left. Level the spell up for more."
	if points_in(ability, node_id) >= node.max_points:
		return "Already maxed."
	if node.exclusive_with != "" and points_in(ability, node.exclusive_with) > 0:
		return "Can't be taken with %s." % find(ability, node.exclusive_with).name
	if node.ring > 1 and not node.requires.any(func(id): return points_in(ability, id) > 0):
		return "Needs a point in a connected node first."
	return ""

static func allocate(ability: Ability, node_id: String) -> bool:
	if why_not_allocate(ability, node_id) != "":
		return false
	ability.web_points[node_id] = points_in(ability, node_id) + 1
	return true

## Takes one point back, unless a node that depends on this one would be
## left without a connection.
static func refund(ability: Ability, node_id: String) -> bool:
	var have := points_in(ability, node_id)
	if have <= 0:
		return false
	if have == 1:
		for node: WebNode in nodes_for(ability):
			if points_in(ability, node.id) > 0 and node.ring > 1 and node.requires.has(node_id):
				if not node.requires.any(func(id): return id != node_id and points_in(ability, id) > 0):
					return false
	if have == 1:
		ability.web_points.erase(node_id)
	else:
		ability.web_points[node_id] = have - 1
	return true

static func refund_all(ability: Ability) -> void:
	ability.web_points.clear()

## Points the spell no longer has (its level went down): dropped from the
## outermost nodes first.
static func trim_to_available(ability: Ability) -> void:
	var nodes := nodes_for(ability).duplicate()
	nodes.sort_custom(func(a: WebNode, b: WebNode): return a.ring > b.ring)
	for node: WebNode in nodes:
		while points_left(ability) < 0 and points_in(ability, node.id) > 0:
			if points_in(ability, node.id) == 1:
				ability.web_points.erase(node.id)
			else:
				ability.web_points[node.id] = points_in(ability, node.id) - 1

## ---- Layout ------------------------------------------------------------------

## Least angle between neighbours on a ring (outer rings are longer).
const RING_SPACING := {1: 40.0, 2: 30.0, 3: 24.0}

## Angles are degrees clockwise from the top. The first ring's blocks go
## evenly round the whole circle (Potency on top). The spell's twists sit
## in the gaps between them, all the way round, each opened by the two
## blocks beside it, so every branch leads somewhere different. Everything
## else sits near what opens it, then each ring is spaced out.
static func _lay_out(nodes: Array, by_id: Dictionary) -> void:
	var ring1: Array = nodes.filter(func(n: WebNode): return n.ring == 1 and not n.from_spell)
	ring1.sort_custom(func(a: WebNode, b: WebNode): return a.id == "potency" and b.id != "potency")
	for i in ring1.size():
		(ring1[i] as WebNode).angle = 360.0 * i / ring1.size()
	var auto: Array = nodes.filter(func(n: WebNode): return n.auto_link)
	for j in auto.size():
		var node: WebNode = auto[j]
		# The middle of a gap between first-ring blocks, gaps shared out evenly.
		var gaps := maxi(ring1.size(), 1)
		var gap := floori((j + 0.5) * gaps / float(auto.size()))
		var slot := 360.0 * (gap + 0.5) / gaps
		node.angle = slot
		if node.ring == 1:
			continue
		# The two first-ring blocks either side of the slot open it.
		var by_gap := ring1.duplicate()
		by_gap.sort_custom(func(a: WebNode, b: WebNode): return absf(angle_difference(deg_to_rad(a.angle), deg_to_rad(slot))) < absf(angle_difference(deg_to_rad(b.angle), deg_to_rad(slot))))
		node.requires.assign(by_gap.slice(0, mini(2, by_gap.size())).map(func(b: WebNode): return b.id))
	for ring in [2, 3]:
		var group: Array = nodes.filter(func(n: WebNode): return n.ring == ring)
		for node: WebNode in group:
			if node.auto_link:
				continue
			var parents: Array = node.requires.filter(func(id): return by_id.has(id) and by_id[id].ring < ring)
			if parents.is_empty():
				parents = node.requires.filter(func(id): return by_id.has(id) and by_id[id] != node)
			if not parents.is_empty():
				# Parents on opposite sides: hang it off the first, or its links would cross the web.
				if parents.size() > 1 and parents.any(func(id): return absf(angle_difference(deg_to_rad(by_id[id].angle), deg_to_rad(by_id[parents[0]].angle))) > deg_to_rad(120.0)):
					parents = [parents[0]]
					node.requires.assign(parents)
				node.angle = _mean_angle(parents.map(func(id): return by_id[id].angle))
		_space_out(group, RING_SPACING[ring])

## Pushes neighbours on a ring apart until they're `spacing` degrees apart.
static func _space_out(group: Array, spacing: float) -> void:
	var n := group.size()
	if n < 2:
		return
	var sep := minf(spacing, 360.0 / n)
	for _pass in 80:
		group.sort_custom(func(a: WebNode, b: WebNode): return fposmod(a.angle, 360.0) < fposmod(b.angle, 360.0))
		var moved := false
		for i in n:
			var a: WebNode = group[i]
			var b: WebNode = group[(i + 1) % n]
			var gap := fposmod(b.angle - a.angle, 360.0)
			if gap < sep - 0.01:
				var push := (sep - gap) * 0.5
				a.angle -= push
				b.angle += push
				moved = true
		if not moved:
			break
	for node: WebNode in group:
		node.angle = fposmod(node.angle, 360.0)

## Circular mean, in degrees.
static func _mean_angle(angles: Array) -> float:
	var v := Vector2.ZERO
	for a in angles:
		v += Vector2.from_angle(deg_to_rad(a))
	return fposmod(rad_to_deg(v.angle()), 360.0)
